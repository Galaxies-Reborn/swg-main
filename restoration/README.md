# Pre-CU restoration overlays

This directory owns restoration changes without committing edits inside the
dsrc or src gitlinks. The manifest locks the x64-dx9 component commits. Scripts
refuse a source checkout whose gitlinks or initialized component HEADs drift.

The materializer is plan-only unless Apply is supplied. StagingRoot is always
mandatory, must be empty, and must be outside both this superproject and the
initialized source checkout. It clones the complete locked superproject plus
all five pinned gitlinks into that isolated directory, then applies ordered
dsrc and src patches. The materialized tree therefore contains the top-level
build and runtime files as well as the edited components. The materializer
removes every staging `origin` after checkout so the transient tree cannot be
used for publishing.

Run the current-state Phase-A contract:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-PhaseA.ps1 -SourceRoot <initialized-source-checkout> -Expectation Baseline

Use Expectation Ready as the implementation gate. It requires:

- 250 minus held skill costs for fresh, novice, and rifle-01 scenarios
- authoritative point enforcement in purchaseSkill
- reachable trainer conversations with table-derived skill, species, money,
  and point data
- the authentic client-visible surrenderSkill command contract
- an actor-only native surrender path with transitive dependency rejection,
  protected-family policy, post-revoke verification, and XP-cap repair
- reference-count-safe cleanup, including a missing-schematic guard
- no unresolved actionable command grant on combat_marksman_rifle_01

Preview materialization without writing:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-RestorationMaterializer.ps1 -SourceRoot <initialized-source-checkout> -StagingRoot <empty-staging-directory>

Create and validate the isolated implementation:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-RestorationMaterializer.ps1 -SourceRoot <initialized-source-checkout> -StagingRoot <empty-staging-directory> -Apply
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-PhaseA.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The registered Phase-A overlays restore table-derived training and skill-point
enforcement, add the surrender command/service, harden schematic revocation,
and remove the scoped dangling aimedShot grant. No implementation is committed
inside this repository's gitlink working directories.

Phase A deliberately rejects hybrid `_prereq_` conversion rows and keeps
bounty-investigation-03 and squad-leader skills closed until their mission and
group-state cleanup hooks are restored. Pilot and Force families likewise stay
on their specialized progression paths.

The headShot1 gate is intentionally blocked. While blocked, the materializer
rejects any patch containing that feature name; a speculative combat-data row
is not an acceptable substitute for the missing HAM runtime behavior.
