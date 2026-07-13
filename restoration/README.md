# Pre-CU restoration overlays

This directory owns restoration changes without committing edits inside the
dsrc or src gitlinks. The manifest locks the x64-dx9 component commits. Scripts
refuse a source checkout whose gitlinks or initialized component HEADs drift.

The materializer is plan-only unless Apply is supplied. StagingRoot is always
mandatory, must be empty, and must be outside both this superproject and the
initialized source checkout. It creates local shared clones in that isolated
directory and applies ordered component patches there.

Run the current-state Phase-A contract:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-PhaseA.ps1 -SourceRoot <initialized-source-checkout> -Expectation Baseline

Use Expectation Ready as the implementation gate. It requires:

- 250 minus held skill costs for fresh, novice, and rifle-01 scenarios
- authoritative point enforcement in purchaseSkill
- trainer-derived skill, money, and point data
- a separate player-safe surrenderSkill command and native handler
- no unresolved actionable command grant on combat_marksman_rifle_01

Preview materialization without writing:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-RestorationMaterializer.ps1 -SourceRoot <initialized-source-checkout> -StagingRoot <empty-staging-directory>

The headShot1 gate is intentionally blocked. While blocked, the materializer
rejects any patch containing that feature name; a speculative combat-data row
is not an acceptable substitute for the missing HAM runtime behavior.
