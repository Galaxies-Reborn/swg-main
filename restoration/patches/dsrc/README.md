# dsrc overlays

Store ordered, component-relative Git patches here. Use numeric names such as
001-phase-a-skill-training.patch. The materializer applies files by name to an
isolated clone pinned by restoration/manifest.json.

Phase A is registered as `001-phase-a-training-and-surrender.patch`. It owns
the table-derived trainer/skill-point path, the authentic surrenderSkill
command row, and removal of the unresolved rifle-01 command grant.

`002-phase-a-runtime-probe.patch` adds an inert ServerConsole-only Java probe
for repeatable live purchase, surrender, skill-point, XP-cap, credit, command,
skill-mod, and draft-schematic assertions. Its fixed `craftingStatus` action
observes the Artisan Engineering I command, `general_assembly` modifier, and a
concrete schematic resolved from `craftArtisanToolGroupA`. Queue acceptance is
reported only as `verification=pending`; use `verifySurrender` to observe the
later authoritative removed state. The probe has no attached-object or
player-facing entry point and enqueues surrender through the production command
table. All actions are restricted to disposable test station `91001`; invoke
its uniquely named `executeProbe` handler through CentralServer `runScript`.

`restoration/scripts/Invoke-PhaseARuntimeSmoke.ps1` queries that status without
mutation by default. Its opt-in `-ExerciseSurrender` path refuses to touch an
already-owned Artisan Engineering I box, temporarily grants only the missing
Artisan skills, validates the command/mod/schematic state produced by those
administrative grants, then polls `verifySurrender` after a production queued
surrender. It asserts the runtime-probed two-point cost, the current canary's
1500-to-2000 crafting XP-cap transition, and unchanged XP. It snapshots skill,
selected command, selected concrete schematic, points, XP/cap, selected skill
mod, cash, and bank before the slice, checks the same canary fields immediately
after surrender, then checks their restoration after cleanup. Mutation intent
is recorded before each grant so a lost response cannot bypass cleanup;
`finally` re-queries authoritative ownership, confirms Engineering I is absent
before revoking a temporary prerequisite novice, and never blindly revokes an
originally-owned novice when output is missing or malformed.

This is deliberately a focused lifecycle canary, not a complete inventory of
every command, modifier, or schematic contributed by Artisan novice and
Engineering I. The fixed probe exposes one Engineering command, one aggregated
modifier, and one concrete schematic; "restored" therefore means equality for
the explicitly observed fields, not proof of whole-player-object equivalence.
The path is also not a trainer-credit purchase test.

`003-precu-character-creation.patch` retires the NGE Choose Your Path mediator
and skip-tutorial payload from the login path. It also removes the NGE-era
all-novice grant so character creation can retain exactly the one Publish 14.1
novice profession selected by the client while preserving the room-nine
trainer handoff and its relog/exit fallbacks.

`004-p14-tutorial-startup.patch` removes the later `c_newbie_hall_01`
groundquest grant from checked-tutorial startup. The original client-ready,
`handleWelcome`, and room-by-room `NewbieTutorialRequest` protocol remains the
authoritative Publish 14.1 flow.

`005-p14-starting-location-handoff.patch` keeps unchecked characters in the
shared hall until terminal use, sends the canonical availability list to the
retained `/AvLoc2` client path, validates a one-shot selection, and retires the
skipped state only after world transfer is observed. It removes the fixed Mos
Eisley, NGE groundquest, ribbon, and automatic-arrival warp path.
