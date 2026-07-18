# Pre-CU restoration overlays

This directory owns restoration changes without committing edits inside the
dsrc, exe, or src gitlinks. The manifest locks the x64-dx9 component commits. Scripts
refuse a source checkout whose gitlinks or initialized component HEADs drift.

The materializer is plan-only unless Apply is supplied. StagingRoot is always
mandatory, must be empty, and must be outside both this superproject and the
initialized source checkout. It clones the complete locked superproject plus
all five pinned gitlinks into that isolated directory, then applies ordered
superproject, dsrc, exe, and src patches. The materialized tree therefore contains the top-level
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
- the unmultiplied Publish 14.1 XP rate used by those table-derived costs
- a supervised TransferServer endpoint for production named-account transfers
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

Validate the generic opt-in Publish 14.1 three-pool combat runtime:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14CombatHam.ps1 -SourceRoot <materialized-staging-directory>

Validate the first authenticated Publish 14.1 combat-command vertical slice:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14HeadShot1.ps1 -SourceRoot <materialized-staging-directory>

Validate the activated Marksman tier-I Health/Action command matrix and its
layered, identity-bound live fixture. The fixture owns reversible pistol-I,
carbine-I, and CDEF weapon setup while the established headShot1 fixture owns
world/HAM restoration; combat commands remain client-queue-only:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MarksmanTier1Gate.ps1 -SourceRoot <materialized-staging-directory>

Validate the build-complete, live-pending Core3 weapon-derived command-duration
seam independently:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14CommandDuration.ps1 -SourceRoot <materialized-staging-directory>

Validate the build-complete, live-pending Core3 primary hit-or-miss seam
independently (secondary outcomes are gated separately):

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14PrimaryAccuracy.ps1 -SourceRoot <materialized-staging-directory>

Validate the build-complete, live-pending Core3 block/dodge/counter/ricochet
seam independently (additional weapon profiles and live outcomes remain gated):

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14SecondaryDefense.ps1 -SourceRoot <materialized-staging-directory>

Validate persistent Publish 14.1 wounds, schema-271 storage, login/combat shock
retention, and the pinned Core3 post-damage linked-wound/shock roll
independently:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Wounds.ps1 -SourceRoot <materialized-staging-directory>

Validate the retained patient-side battle-fatigue medicine multiplier and its
250/251/500/1000 live boundaries independently:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14BattleFatigue.ps1 -SourceRoot <materialized-staging-directory>

Validate the six authentic medical wound-pack attributes, all-attribute
modifier application, one-charge depletion, and disposable-patient cleanup
independently:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MedicineConsumption.ps1 -SourceRoot <materialized-staging-directory>

Validate the atomic Publish 14.1 nine-attribute persistence and replication
runtime:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NineAttributeRuntime.ps1 -SourceRoot <materialized-staging-directory>

Validate the Publish 14.1 stat-migration tables, server-owned session,
tutorial commit, and authenticated normal-world Image Designer transaction:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14StatMigration.ps1 -SourceRoot <materialized-staging-directory>

This M3 seam restores atomic strict-positive Health/Action/Mind ability costs,
the Core3-derived cost formula from authoritative Strength/Quickness/Focus,
explicit primary target-pool
damage, and any-primary-pool incapacitation. It is inert for production combat
commands until a separate override row opts one in. `headShot1` is the first
authenticated opt-in: Marksman Rifle I grants it, the retail command row queues
it, the standard combat hook enforces rifle combat data, its Core3-derived
three-pool multipliers drain atomically, and successful damage targets Mind.
The companion nine-attribute slice restores the exact
Health/Strength/Constitution/Action/Quickness/Stamina/Mind/Focus/Willpower
order across templates, persistence, shared messages, creation tables, and
client replication. Existing six-value creature state is deterministically
migrated on authoritative load; Strength, Quickness, and Focus are the live
cost governors, while Constitution, Stamina, and Willpower are the live
regeneration governors.

Run the staged trainer purchase and persistence acceptance against only the
disposable station `91001` fixture. `Observe` is the default and performs no
mutation. The mutating phases require an explicit snapshot outside the source
tree. The snapshot is created atomically before the first mutation and is
checkpointed after each grant/transfer so interrupted work can be recovered
with `Cleanup`:

    # Observe reports the nearest loaded production Artisan trainer position/distance.
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-PhaseATrainerPersistence.ps1 -PlayerOid <fixture-oid>
    # Move the client within eight metres of that trainer BEFORE running Prepare.
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-PhaseATrainerPersistence.ps1 -PlayerOid <fixture-oid> -Mode Prepare -SnapshotPath <evidence-json>
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-PhaseATrainerPersistence.ps1 -PlayerOid <fixture-oid> -Mode Conversation -SnapshotPath <evidence-json>
    # Inspect/capture the visible client dialogue; this phase cannot purchase.
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-PhaseATrainerPersistence.ps1 -PlayerOid <fixture-oid> -Mode Purchase -SnapshotPath <evidence-json>
    # Relog, then prove the same authoritative Tatooine process plus a vanished volatile relog nonce.
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-PhaseATrainerPersistence.ps1 -PlayerOid <fixture-oid> -Mode VerifyBoundary -BoundaryKind Relog -SnapshotPath <evidence-json>
    # Gracefully restart the isolated server, relog, then prove a changed process lifetime plus vanished restart nonce.
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-PhaseATrainerPersistence.ps1 -PlayerOid <fixture-oid> -Mode VerifyBoundary -BoundaryKind Restart -SnapshotPath <evidence-json>
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Invoke-PhaseATrainerPersistence.ps1 -PlayerOid <fixture-oid> -Mode Surrender -SnapshotPath <evidence-json>

`Purchase` does not fabricate a conversation response. It validates a nearby,
loaded `npc.skillteacher.skillteacher`, its offered/qualified skill list,
distance, table-derived 1,000-credit cost, 500-XP cost, and absence of a
persuasion discount. It then enters the stock production
`money.requestPayment(..., "attemptedPayment")` path. The trainer's real
callback invokes `completeSkillPurchase`, then checkpoints a player-owned
named-account request before the skill-training accounting transfer. Purchase
success is not published until that transfer's success callback is durable;
stock refund-on-purchase-failure behavior remains intact. The result explicitly
records `conversationUi=false`; visible client dialogue remains a separate
acceptance surface.

Every asynchronous fixture transfer carries a unique persisted operation ID.
The external snapshot checkpoints `checkpointed` first. The server then writes
the same ID as an attempt anchor, publishes `reserving` with the complete
lifecycle/trainer/skill/cost/preimage record, verifies it, and commits
`reserved` before dispatch. An attempt-only crash residue is clearable only
from the exact matching external checkpoint, with no other operation leaf,
nonce, or gameplay drift; the same unchanged-preimage rule applies to exact
`reserving`/`reserved` markers. The dispatch state is read back
authoritatively; the runner never invents `queued` from an RPC return.

The schema-v8 runner remains wire-compatible with the frozen v6.4/protocol-64
server implementation. That protocol closes every tagged stock-money stage
before its side effects. Every trainer callback carries both exact handler names and an
explicit return code; a missing or unknown trainer code is quarantined before
stock code can normalize it. The native player-money envelope accepts an absent
code only while stock `getReturnCode` still reports `-1`; every later callback
must carry explicit success (`0`) or failure (`1`). Payment request advances
`enqueueing` to `paymentDispatching`;
pay-pass advances once to `paymentSucceededCallback`, and pay-fail advances
once to `paymentFailedCallback`; only that authoritative callback state can
enter the trainer. Tagged covert
deposit is impossible for this bank-funded canary and is quarantined. Every
stage verifies the complete operation, lifecycle, trainer, skill, cost, and
preimage record plus one of four authoritative vectors: PRE, DEBIT, HELD, or
REFUND. `player_money` now proves the same full lifecycle-relative, bank-funded
preimage equations as the trainer before it may advance to
`paymentDispatching` or call `money.pay`. The trainer independently revalidates
every persisted preimage leaf, binds both tagged player and trainer, and
re-proves the required vector at every state transition. Success callbacks
require exact bank-first DEBIT with unchanged prepared gameplay; failed-payment
callbacks require exact PRE. HELD requires the complete grant, exact debit,
spent XP and points, and the 2,000 trained cap. Refund success is terminal only
from exact restored REFUND and emits its success prose only after that verified
transition; refund failure is terminal only from exact retained DEBIT with no
skill grant. Missing leaves, partial grants, or balance/gameplay drift are
quarantined before any purchase, message, accounting, or money side effect.
All PRE/DEBIT/HELD/REFUND decisions also require the exact two-command,
six-modifier, five-group, 35-unique-schematic vector.

After a proved server-process change, `purchaseApplying` plus exact HELD is
advanced only through `resumePurchaseAccounting`; HELD alone never proves
purchase success. `accountingRequested` can safely requeue its player-owned
request. `accountingDispatching` or `accountingPending` remains fail-closed
unless its durable outcome is exactly `SUCCESS`; that callback cut can be
terminalized without retrying the transfer. Two-write failure cuts retain
`REQUEST_QUEUE_FAILED`, `QUEUE_FAILED`, or `FAILED` against their exact current
accounting state; they are reload-valid but remain fail-closed and non-clearable.
Completed request-queue, native-queue, and callback failures likewise remain
durable and non-clearable. Exact DEBIT with no grant at
`paymentDispatching`, `paymentSucceededCallback`, or `purchaseApplying`
reconstructs and sends only the original trainer `attemptedPayment` callback;
it never replays the debit, `money.requestPayment`, `money.pay`, or a pay-pass
handler. `paymentDispatching` plus PRE, any same-process inference, and every
partial vector remain fail-closed. Refund state is generation-scoped by the
deterministic `<operation>.refund.<generation>` key. Generation 1 may claim the
single recovery generation 2 only from exact initial failure; either generation
may safely resume only from its `Claiming` cut. Dispatching, pending, queue
failure other than the exact generation-1 initial-failure gateway, callback
failure, and every consumed recovery DEBIT remain fail-closed.
Any exact generation state plus REFUND terminalizes without another transfer;
stale generation-1 callbacks are quarantined after generation 2 is claimed.
Schema v8 synchronizes an authoritative marker into a detached clone, copies
all seven protocol provenance leaves, normalizes its recovery target, validates
the full lifecycle, JSON-roundtrips it, and validates it again before replacing
the working operation. Recoverable settled refund failures are evaluated before
generic terminal handling, making exact generation-1 `refundInitialFailed` plus
DEBIT reach its single generation-2 retry while generation-2 failure remains
non-clearable. A validated recovery intent is atomically saved before its RPC.
After success, timeout, or exception the runner makes a best-effort authoritative
refresh; correlated reachable state is normalized and saved before return or
before rethrowing the original action error. Invalid refreshes retain the last
valid intent. The latest recovery source/process remains historical audit
evidence across allowed accounting, callback, and refund states, while advanced
targets are cleared so synchronized live state cannot carry stale action intent.
Attempt-only and `reserving` recovery accepts only a gap-free observable prefix
of the reservation writes, neutral refund/accounting leaves, an incomplete
marker, no volatile nonce, and the unchanged preimage. Immediately before either
reservation rollback or pre-dispatch clear, the server independently recomputes
the exact values and presence order of all 25 writes, including the eight
preimage leaves and the hidden provenance-presence cuts. A hidden gap therefore
retains evidence and makes clear fail closed; the runner records success only
after `cleared=true` and an authoritative marker-absent readback. A missing
attempt ID must have zero operation instrumentation before any checkpoint
discard or marker-cleared cleanup. Every complete or terminal operation marker
must carry a strictly positive durable `operation.updated` value in the server,
runner synchronization, held-evidence, and terminal-clear proofs. An early
gap-free `reserving` prefix may still omit `updated` only when the ordered write
has not yet occurred and no later reservation leaf is present.
Recovered purchase evidence is also saved after terminal confirmation and
before destructive marker removal, preserving marker-cleared replay after a
lost clear response.
Recovered purchase evidence retains the operation, lifecycle, trainer, skill,
cost, origin process, and outcome process through checkpointed held, surrender
intent, surrendered evidence, baseline cleanup, and terminal `cleaned` reloads.
If terminal marker removal succeeded but its response was lost, recovery
accepts only zero operation instrumentation, exact held gameplay, and exact
active-lifecycle/evidence lineage. A still-present terminal marker continues to
require strict equality of the entire persistent state.

Every mutating invocation holds a deterministic container/player lock and the
sibling `<evidence-json>.lock` from before its first observation through exit.
Prepare first writes a versioned external snapshot with a random lifecycle ID.
The server writes that ID first as `lifecycle.attemptId`, records and verifies
all seven baseline leaves, publishes and verifies `established`, and makes
`lifecycle.id` the single final write. No rollback or other mutation follows
that commit write; a lost or incomplete readback is handled as authoritative
partial/corrupt residue by cleanup.
Status distinguishes `none`, `partial`, `complete`, and corrupt residue; every
mutation and callback requires the exact complete record. Cleanup from
`lifecyclePending` is a dedicated metadata-only path: gameplay drift is rejected
before any gameplay API, while exact partial/complete response-loss residue can
be authoritatively cleared. Other cleanup checkpoints `releasePending`, restores the
exact baseline, removes the lifecycle marker, re-reads the authoritative state,
and only then records `complete`/`cleaned`. Replaying terminal Cleanup is an
immutable no-op; any drift from both final evidence and baseline is rejected.
The runner identity includes its own SHA-256 and the injected materialization
fingerprint, so source, staged contract, and deployed callback classes cannot
be silently mixed.

Boundary evidence does not rely on Java static state. The runner samples the
authoritative Tatooine `SwgGameServer` Linux boot ID, PID, and process start
ticks immediately before and after each probe. Relog requires that token to
remain identical; restart requires it to change. This prevents a script reload
from being accepted as a server restart and rejects a process transition that
occurs while state is being sampled.

`Conversation` is that separate surface: after the same trainer validation it
queues the production `npcConversationStart` command against the trainer and
reports only `conversationUi=pending purchaseMutation=false`. The connected
client must supply the visible acceptance evidence; the server probe never
claims the mediator opened merely because the command entered the queue.
That validated trainer OID is stored in the snapshot, and `Purchase` refuses to
use any different trainer.

The staged acceptance supplies exactly the resources that the authentic
Engineering I purchase consumes. This allows surrender to prove that neither
credits nor XP are refunded, while the final administrative prerequisite
cleanup can still restore the fixture's exact original state. The held snapshot
also covers the complete novice-plus-Engineering vector by identity: both
named commands, all six prepared-to-held modifier deltas, and each of the 35
named concrete schematics in the five authoritative schematic groups.

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

The stat-migration gate requires authentic Publish 14.1 racial limits, racial
modifiers, and profession allocations plus all four retained command entry
points. The server owns target initialization, bounds, and total validation.
Tutorial allocations commit immediately only in `newbie_hall`; normal-world
targets remain pending until the Image Designer transaction milestone restores
its authoritative commit and persistence boundary.

The registered Phase-A overlays restore table-derived training and skill-point
enforcement, add the surrender command/service, harden schematic revocation,
and remove the scoped dangling aimedShot grant. No implementation is committed
inside this repository's gitlink working directories.

Phase A deliberately rejects hybrid `_prereq_` conversion rows and keeps
bounty-investigation-03 and squad-leader skills closed until their mission and
group-state cleanup hooks are restored. Pilot and Force families likewise stay
on their specialized progression paths.

The headShot1 gate is ready only as the complete command-specific overlay. The
materializer still rejects its feature name whenever the gate is moved away
from `ready`; a speculative combat-data row cannot bypass the three-pool HAM,
skill-grant, queue, rifle, hook, Mind-routing, or atomic-drain acceptance.

`bodyShot1` and `legShot1` now complete the authentic Marksman tier-I trio beside
the accepted rifle/Mind `headShot1` slice. Pistol/Health and carbine/Action use
the pinned Core3 CDEF speed, range, accuracy, defense, posture, secondary-defense,
and 10/15/10 HAM profiles; the standard combat wrapper consumes the already
accepted weapon-derived duration, primary-accuracy, and three-pool runtime seams.
The exact compiled combat, command, and skill IFFs are published on
`swgsais/pre-cu-reborn-assets:x64-dx9`. Static, isolated-build, and two-client
live execution acceptance are complete. Pistol/BodyShot1 and
carbine/LegShot1 succeeded through the production client queue with exact
three-pool costs; all six rifle/pistol/carbine cross-use cases and both strict
no-partial boundaries cancelled without HAM mutation. The layered fixtures
then restored all owned state. Live diagnostic exposure for command duration,
primary-accuracy components, and secondary-defense results was subsequently
added, and the tier-I matrix is now `ready`. The shared command-duration
contract also has live evidence for both the modeled 4.725-second `headShot1`
timer and the non-opted 1.5-second `headShot2` static fallback; primary-accuracy
and secondary-defense keep their separate live-readiness boundaries.

The first production medical command is now `ready`. `healWound` enters the
real retained client combat queue, enforces the pinned Core3 patient, combat,
range, PvP, facility, medicine, Focus-cost, and round-time behavior, consumes
the real wound pack, and awards 2.5 medical XP per wound. The live lifecycle
proved success followed by an in-queue cooldown rejection and exact fixture
cleanup; `Test-P14HealWoundCommand.ps1` locks the table, runtime, skill-grant,
and evidence boundaries.

The next production medical command is live accepted. `healDamage` restores
the authentic five-second queue row, corrects the retained disabled injury
cooldown and doubled Mind cost, measures all three primary HAM pools, and
locks Core3's other-player-only 25-percent Health-plus-Action medical XP
boundary in `Test-P14HealDamageCommand.ps1`. The reversible pet/stim lifecycle
proved one successful three-pool treatment followed five seconds later by a
cooldown rejection with no additional cost or consumption.

`tendDamage` and `tendWound` are restored together as the next Medic novice
slice. Both use authentic five-second queue rows and organic treatment—no
medicine item—with six-meter patient, visibility, and PvP gates. The shared
backend applies Focus-adjusted 200/400 Mind costs, five Focus and five
Willpower wounds, and patient battle-fatigue scaling. `tendDamage` restores
Health and Action without XP; `tendWound` selects Health through Stamina and
awards 2.5 medical XP per wound to another target. Protocol-17 live acceptance
proved 22-point Health/Action tending for exact 183 Mind, then 22 Health-wound
tending for exact 368 Mind and 55 asynchronously observed medical XP. Each
command added five Focus and Willpower wounds, both client queue admissions
drained, and all three composed fixtures restored their owned state.

`diagnose` is now the first completed read-only Medic SUI slice. Its
required-target, five-second, nonqueued row routes through
`player.cmd.diagnose`, applies the pinned Core3 six-meter organic-creature and
PvP-help gates, and opens the Publish 14 listbox with all nine wounds plus
Battle Fatigue. Protocol-18 live acceptance observed the exact ten values from
the authoritative player, kept the local combat queue at zero, dismissed the
page through background client input, and restored every fixture-owned value.
Validate a materialized tree with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DiagnoseCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

`medicalForage` completes the Medic novice command surface. Its authentic
targetless, two-second, nonqueued row enters the retained player utility, which
now implements the pinned Core3 Quickness-adjusted Action cost, outdoor and
mount gates, 8.5-second stationary search, combat-at-completion check,
per-player 10-meter area depletion, 30-minute expiration, medical-foraging
chance, and the original food, local flora resource, and tiered medical
component reward bands. Protocol-19 live acceptance charged 45 Action, waited
nine game seconds, used novice `medical_foraging=10`, and awarded a real
randomized biologic component. The fixture then destroyed only that reward and
restored Action, location, skill, command, and both runtime roots. Validate
with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MedicalForageCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The Medic profession tree now advances beyond novice. The authentic
four-by-four root and all four tier-I boxes restore their exact XP and
skill-point costs, private commands, healing/crafting modifiers, and retail
novice plus Organic Chemistry I schematic groups. Protocol-19 live acceptance
acquired every box through production skill validation, grant, and XP
deduction operations, displayed the four highlighted boxes in the legacy
Skills window, then restored the character twice without residue. Validate
with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MedicTier1Progression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Medic progression now includes the complete authentic tier-II row. First Aid
II, Diagnostics II, Pharmacology II, and Organic Chemistry II restore their
retail three-point costs, XP/caps, commands, modifiers, and group-B
schematics. The component and stimpack groups are corrected to the decoded
Publish 14 table rather than retaining later mislabeled contents. Validate a
materialized tree with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MedicTier2Progression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready
