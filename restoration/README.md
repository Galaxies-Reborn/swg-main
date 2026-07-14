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

Validate the Publish 14.1 creation/login invariant:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14CharacterCreation.ps1 -SourceRoot <materialized-staging-directory>

Validate checked-tutorial startup independently:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14TutorialStartup.ps1 -SourceRoot <materialized-staging-directory>

Validate the unchecked Publish 14 shared-hall and starting-location handoff:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14StartingLocation.ps1 -SourceRoot <materialized-staging-directory>

Validate the Publish 14 character-sheet server payload:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14CharacterSheetServer.ps1 -SourceRoot <materialized-staging-directory>

This gate requires exactly the six retail starting-profession keys, safe
PlayerObject-first setup and failure teardown, a deferred selected-skill
handoff for the full tutorial, a verified immediate grant when the tutorial is
skipped, the original `newbie_hall`/room-nine trainer flow, and absence of the
NGE hangar, profession-template mediator, skip payload, and all-six-novice
grant.

The tutorial-startup gate additionally requires checked characters to enter
the original client-ready/`handleWelcome` room sequence without granting the
later `c_newbie_hall_01` groundquest. The separate starting-location gate
requires unchecked characters to persist on the tutorial scene, enter the
shared `newbie_hall_skipped` room one, and remain there across relog until the
travel terminal opens the canonical location list. It rejects the fixed Mos
Eisley/NGE groundquest path, validates the selected location before reporting
success, and enforces an ephemeral one-shot selection gate whose
`newbie.startSkippedTutorial` marker is retired only after a valid transfer.

The character-sheet server gate requires persisted PlayerObject birth and
played-time values, a durable bind location with legacy facility fallback,
the last bank-terminal planet with intentionally zero coordinates, the complete
local and remote residence request/response path, and account lots remaining
from the authoritative configured cap plus account adjustment in the original
response-field order. Core3 is a semantic behavior reference for these fields;
the implementation deliberately retains the SWGSource network-message envelope
and does not claim Core3 wire-format equivalence.

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
