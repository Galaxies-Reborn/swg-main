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
