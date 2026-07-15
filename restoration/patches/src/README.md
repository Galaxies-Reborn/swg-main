# src overlays

Store ordered, component-relative Git patches here. Use numeric names such as
001-phase-a-surrender-command.patch. The materializer applies files by name to
an isolated clone pinned by restoration/manifest.json.

Phase A is registered as `001-phase-a-surrender-service.patch`. It owns the
actor-only surrender service, XP-cap repair, and schematic cleanup guard.

Publish 14.1 character creation is registered as
`002-precu-character-creation.patch`. It validates the six authentic starting
profession keys, creates the PlayerObject before granting the selected novice
skill and schematics for skipped-tutorial characters, and rejects incomplete
setup instead of persisting a partially initialized character. Tutorial
characters retain the selected-skill handoff for the room-nine trainer and are
routed into the Publish 14.1 `newbie_hall` instead of the NGE hangar.

`003-p14-skipped-hall.patch` restores the unchecked Publish 14 handoff. Both
creation choices persist the tutorial scene, while the unchecked path uses a
dedicated onboarding marker and a shared `newbie_hall_skipped` singleton at
the Core3-locked tutorial coordinate before entering room `r1`.

`004-p14-character-sheet-data.patch` restores the character-sheet producer's
persisted birth date and played time, prefers the durable cloning bind
location with a legacy facility fallback, keeps the last bank-terminal planet
without inventing coordinates, reports the residence object's own scene, and
sends account lots remaining from the authoritative configured cap plus the
persisted per-account adjustment. It adapts Core3 field semantics to the
retained SWGSource message envelope rather than claiming wire equivalence.

`005-precu-three-pool-combat-runtime.patch` supplies the native M3 primitives:
atomic strict-positive Health/Action/Mind cost drain, explicit primary-pool
damage routing, and incapacitation on any depleted primary pool with recovery
only after all three pools are positive. The original no-pool damage entry
point remains Health-only for unconverted commands.
