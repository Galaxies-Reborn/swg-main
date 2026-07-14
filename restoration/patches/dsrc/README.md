# dsrc overlays

Store ordered, component-relative Git patches here. Use numeric names such as
001-phase-a-skill-training.patch. The materializer applies files by name to an
isolated clone pinned by restoration/manifest.json.

Phase A is registered as `001-phase-a-training-and-surrender.patch`. It owns
the table-derived trainer/skill-point path, the authentic surrenderSkill
command row, and removal of the unresolved rifle-01 command grant.

`002-phase-a-runtime-probe.patch` adds an inert ServerConsole-only Java probe
for repeatable live purchase, surrender, skill-point, and XP-cap assertions.
It has no attached-object or player-facing entry point and enqueues surrender
through the production command table. All actions are restricted to disposable
test station `91001`; invoke its uniquely named `executeProbe` handler through
CentralServer `runScript`.

`003-precu-character-creation.patch` retires the NGE Choose Your Path mediator
and skip-tutorial payload from the login path. It also removes the NGE-era
all-novice grant so character creation can retain exactly the one Publish 14.1
novice profession selected by the client while preserving the room-nine
trainer handoff and its relog/exit fallbacks.

`004-p14-tutorial-startup.patch` removes the later `c_newbie_hall_01`
groundquest grant from checked-tutorial startup. The original client-ready,
`handleWelcome`, and room-by-room `NewbieTutorialRequest` protocol remains the
authoritative Publish 14.1 flow.
