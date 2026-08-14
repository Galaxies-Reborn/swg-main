#!/usr/bin/env python3
"""Conservatively classify direct server calls to buff.applyBuff* APIs."""

from __future__ import annotations

import argparse
import collections
import csv
import json
import re
import sys
from pathlib import Path


CALL_RE = re.compile(r"\bbuff\.(applyBuff|applyBuffWithStackCount)\s*\(")
STRING_RE = re.compile(r'"((?:\\.|[^"\\])*)"')
IDENTIFIER_RE = re.compile(r"^(?:[A-Za-z_$][\w$]*\.)*([A-Za-z_$][\w$]*)$")
CONSTANT_RE = re.compile(
    r"\b(?:public\s+|private\s+|protected\s+)?(?:static\s+)?final\s+String\s+"
    r"([A-Za-z_$][\w$]*)\s*=\s*\"((?:\\.|[^\"\\])*)\"\s*;"
)
OWNER_NAMES = {
    "attacker",
    "caster",
    "defender",
    "owner",
    "player",
    "self",
    "source",
    "station",
    "target",
}


def strip_comments(text: str) -> str:
    output = list(text)
    index = 0
    quote = ""
    while index < len(text):
        char = text[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
            index += 1
            continue
        if char in ('"', "'"):
            quote = char
            index += 1
            continue
        if text.startswith("//", index):
            end = text.find("\n", index)
            if end < 0:
                end = len(text)
            output[index:end] = " " * (end - index)
            index = end
            continue
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            end = len(text) if end < 0 else end + 2
            for position in range(index, end):
                if output[position] not in "\r\n":
                    output[position] = " "
            index = end
            continue
        index += 1
    return "".join(output)


def find_closing_paren(text: str, opening: int) -> int:
    depth = 0
    quote = ""
    index = opening
    while index < len(text):
        char = text[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
            index += 1
            continue
        if char in ('"', "'"):
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    raise ValueError(f"unbalanced call beginning at byte {opening}")


def split_arguments(text: str) -> list[str]:
    arguments: list[str] = []
    start = 0
    depths = {"(": 0, "[": 0, "{": 0}
    closing = {")": "(", "]": "[", "}": "{"}
    quote = ""
    index = 0
    while index < len(text):
        char = text[index]
        if quote:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = ""
            index += 1
            continue
        if char in ('"', "'"):
            quote = char
        elif char in depths:
            depths[char] += 1
        elif char in closing:
            depths[closing[char]] -= 1
        elif char == "," and all(depth == 0 for depth in depths.values()):
            arguments.append(text[start:index].strip())
            start = index + 1
        index += 1
    arguments.append(text[start:].strip())
    return arguments


def decode_java_string(value: str) -> str:
    return bytes(value, "utf-8").decode("unicode_escape")


def load_catalog(path: Path) -> set[str]:
    with path.open("r", encoding="utf-8-sig", newline="") as source:
        lines = source.read().splitlines()
    if len(lines) < 3:
        raise ValueError("buff table is missing its header/type/data rows")
    rows = csv.DictReader(lines[2:], fieldnames=lines[0].split("\t"), delimiter="\t")
    return {row["NAME"] for row in rows if row.get("NAME")}


def resolve_expression(
    expression: str,
    catalog: set[str],
    local_constants: dict[str, set[str]],
    global_constants: dict[str, set[str]],
) -> tuple[set[str], str]:
    expression = expression.strip()
    full_string = re.fullmatch(r'"((?:\\.|[^"\\])*)"', expression, re.DOTALL)
    if full_string:
        return {decode_java_string(full_string.group(1))}, "literal"
    identifier = IDENTIFIER_RE.fullmatch(expression)
    if identifier:
        name = identifier.group(1)
        values = local_constants.get(name) or global_constants.get(name, set())
        if len(values) == 1:
            return set(values), "constant"
        return set(), "dynamic"
    literals = [decode_java_string(match.group(1)) for match in STRING_RE.finditer(expression)]
    if literals and "+" in expression:
        prefix = literals[0]
        matches = {name for name in catalog if name.startswith(prefix)}
        return matches, "prefix-family" if matches else "unmatched-prefix"
    return set(), "dynamic"


def looks_like_owner(expression: str) -> bool:
    identifier = IDENTIFIER_RE.fullmatch(expression.strip().strip("()"))
    return bool(identifier and identifier.group(1).lower() in OWNER_NAMES)


def analyze(buff_table: Path, script_root: Path) -> dict[str, object]:
    catalog = load_catalog(buff_table)
    files = sorted(script_root.rglob("*.java"))
    source_by_file: dict[Path, str] = {}
    local_by_file: dict[Path, dict[str, set[str]]] = {}
    global_constants: dict[str, set[str]] = collections.defaultdict(set)
    for path in files:
        text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        source_by_file[path] = text
        local: dict[str, set[str]] = collections.defaultdict(set)
        for match in CONSTANT_RE.finditer(text):
            value = decode_java_string(match.group(2))
            local[match.group(1)].add(value)
            global_constants[match.group(1)].add(value)
        local_by_file[path] = local

    resolved_names: set[str] = set()
    missing_names: set[str] = set()
    method_counts: collections.Counter[str] = collections.Counter()
    resolution_counts: collections.Counter[str] = collections.Counter()
    unresolved: collections.Counter[str] = collections.Counter()
    missing_occurrences: list[dict[str, object]] = []
    call_count = 0
    for path, text in source_by_file.items():
        for match in CALL_RE.finditer(text):
            call_count += 1
            method_counts[match.group(1)] += 1
            opening = match.end() - 1
            closing = find_closing_paren(text, opening)
            args = split_arguments(text[opening + 1 : closing])
            candidates = args[1:3]
            names: set[str] = set()
            resolution = "dynamic"
            selected = candidates[0] if candidates else ""
            if candidates:
                names, resolution = resolve_expression(
                    candidates[0], catalog, local_by_file[path], global_constants
                )
            if len(candidates) > 1 and looks_like_owner(candidates[0]):
                selected = candidates[1]
                names, resolution = resolve_expression(
                    candidates[1], catalog, local_by_file[path], global_constants
                )
            resolution_counts[resolution] += 1
            if names:
                resolved_names.update(names)
                missing_for_call = sorted(name for name in names if name not in catalog)
                missing_names.update(missing_for_call)
                if missing_for_call:
                    missing_occurrences.append(
                        {
                            "file": path.relative_to(script_root).as_posix(),
                            "line": text.count("\n", 0, match.start()) + 1,
                            "expression": selected,
                            "names": missing_for_call,
                        }
                    )
            else:
                normalized = re.sub(r"\s+", " ", selected).strip()
                unresolved[normalized] += 1

    return {
        "schemaVersion": 1,
        "callCount": call_count,
        "methodCounts": dict(sorted(method_counts.items())),
        "resolutionCounts": dict(sorted(resolution_counts.items())),
        "resolvedStatusCount": len(resolved_names),
        "resolvedStatuses": sorted(resolved_names),
        "missingStatuses": sorted(missing_names),
        "missingOccurrences": missing_occurrences,
        "unresolvedExpressionCount": sum(unresolved.values()),
        "unresolvedExpressions": [
            {"expression": expression, "calls": count}
            for expression, count in sorted(unresolved.items(), key=lambda item: (-item[1], item[0]))
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--buff-table", required=True, type=Path)
    parser.add_argument("--script-root", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = analyze(args.buff_table, args.script_root)
        payload = json.dumps(result, indent=2) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(payload, encoding="utf-8", newline="\n")
        else:
            sys.stdout.write(payload)
        return 1 if result["missingStatuses"] else 0
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
