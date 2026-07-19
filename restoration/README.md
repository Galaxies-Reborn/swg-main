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

The third Medic row restores all four passive Publish 14.1 boxes without
introducing a new gameplay-command seam. Organic Chemistry III also restores
six wound-medpack schematics from the canonical retail schematic-group table.
Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MedicTier3Progression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The fourth Medic row restores First Aid IV, Diagnostics IV, Pharmacology IV,
and Organic Chemistry IV with their retail five-point costs, XP caps, private
commands, modifiers, and nine exact schematics from the decoded
`patch_12_00.tre` table. First Aid IV owns the already-live-accepted Quick Heal
command. The reversible fixture purchases all four boxes after granting the
thirteen novice-through-tier-III prerequisites. Live acceptance acquired all
four boxes, five commands, nine schematics, and the exact modifier vector,
then restored the character twice without residue while both containers
remained healthy. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MedicTier4Progression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Master Medic restores the retail six-point capstone, all four tier-IV
prerequisites, its private command, injury-treatment/healing/foraging
modifiers, and Stimpack D. Its reversible fixture grants the complete
seventeen-box prerequisite tree before invoking production master-skill
validation, grant, and XP deduction. Live acceptance acquired the master
skill, private command, Stimpack D, and exact modifier vector, then restored
the full tree twice without residue while both containers remained healthy.
Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MedicMasterProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Novice Doctor now follows the Publish 14.1 profession boundary rather than
the retained NGE shortcut. It requires Master Medic, costs 11,250 medical XP
and six skill points, grants `healState` plus medical registration, restores
five wound/crafting/healing modifiers, and exposes the four retail state and
poison schematics. The reversible fixture owns the full eighteen-skill Medic
prerequisite tree and invokes production skill validation, grant, and XP
deduction. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DoctorNoviceProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Medic First Aid IV grants the original optional-target, nonqueued Quick Heal
command. The adapter preserves Core3's Focus-adjusted Mind cost, shared random
Health/Action heal power, Focus and Willpower wounds, six-meter organic target
boundary, and zero-medicine/zero-XP behavior. Protocol-22 live acceptance used
a fixture-owned 1,100 Focus allocation—the authentic Publish 14 Human
maximum—to bridge the NGE-origin test character's 400-point HAM profile without
altering the charged Mind pool. The command entered through the off-focus
client, charged exactly 333 Mind, used one 654-point roll for Health and Action,
added ten Focus and Willpower wounds, granted no XP, left the local queue empty,
and completed idempotent cleanup with both containers healthy. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14QuickHealCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Novice Doctor's first active command is now live accepted. The original
optional-target, five-second queued `healState` row enters a narrow adapter
that preserves Core3's six-meter organic-patient, visibility, PvP-help,
state-specific medicine, Focus-adjusted 20-Mind, injury-speed recovery,
one-charge consumption, state-removal, effect, and other-player-only 50-XP
boundaries. Protocol-23 off-focus acceptance removed dizzy state 14 from the
fixture player, charged exactly 18 Mind and one medicine charge, applied the
expected five-second recovery, granted zero self-treatment XP, and left the
client queue empty. The identity-bound fixture then restored its complete
Medic/Doctor, state, HAM, XP, cooldown, and medicine ownership twice without
residue while both isolated containers remained healthy. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14HealStateCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Doctor progression now includes the complete authentic first row. Wound
Treatment I, Wound Speed I, Medicine Knowledge I, and Medicine Crafting I each
require novice Doctor, cost 15,000 branch-appropriate XP and five skill points,
and grant only their retail passive modifiers and schematic groups. Five
later-era active commands are explicitly absent. The crafting branch restores
the exact six Publish 14.1 enhancement, state-treatment, and disease-cure
schematics decoded from `patch_12_00.tre`. Protocol-23 live acceptance bought
all four boxes through production validation, grant, and XP deduction, observed
the exact modifier and schematic vectors, and restored the complete
Medic-through-Doctor preimage twice without residue. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DoctorTier1Progression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The second Doctor row is also live accepted. Wound Treatment II and Wound
Speed II grant the authentic `healEnhance` and `curePoison` commands;
Medicine Knowledge II remains passive; and Medicine Crafting II grants twelve
exact wound-pack, cure, enhancement, and secondary-enhancement schematics.
All four boxes restore their retail four-point and XP costs and exact passive
modifiers, while nine NGE commands are explicitly absent. The command rows are
published at their authentic client-admission boundary; their gameplay
adapters remain separate vertical slices. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DoctorTier2Progression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The first Doctor tier-II gameplay adapter restores the nonqueued Cure Poison
command against the pinned Core3 behavior while retaining SWGSource medicine,
DOT-strength, area-pack, charge, effect, and PvP-help paths. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14CurePoisonCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The second Doctor tier-II gameplay adapter restores queued Heal Enhance
against the pinned Core3 behavior while retaining SWGSource enhancement-pack,
battle-fatigue, buff-replacement, charge, PvP-help, and presentation paths.
The adapter also exempts Publish 14 positive-duration medicine from the NGE
consumable path that otherwise zeroes its crafted modifier. Protocol-26 client
admission and the identity-bound live fixture verify a
disposable organic pet target, Focus-adjusted Mind, net enhancement, medical
XP (including its deferred server delivery), wound-treatment recovery, and
exact cleanup. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14HealEnhanceCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Doctor tier III restores all four authentic third-row boxes. The three
clinical branches cost 45,000 medical XP and three points each; Medicine
Crafting III costs 27,000 medicine-crafting XP and three points. The row owns
only the retail healing modifiers, `extinguishFire`, and thirteen exact
stimpack, secondary-wound, disease-cure, and enhancement schematics decoded
from `patch_12_00.tre`; sixteen NGE combat-buff commands are explicitly
absent. The identity-bound fixture purchases all four boxes through production
validation, grant, and XP deduction, then restores its complete
Medic-through-Doctor-II preimage. Protocol-26 live acceptance purchased every
box, observed the exact five-command, thirteen-schematic, and modifier vectors,
then restored the snapshot twice while both containers stayed healthy.
Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DoctorTier3Progression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Doctor Wound Speed III's active command is now live accepted. The authentic
optional-target, five-second nonqueued `extinguishFire` row enters a narrow
adapter that preserves Core3's seven-meter organic-patient, visibility,
PvP-help, fire-blanket, Focus-adjusted 100-Mind, wound-speed recovery,
one-charge, DOT-reduction, and fixed other-player 50-XP boundaries.
Protocol-27 off-focus self-treatment reduced fire strength from 90 to zero,
charged exactly 91 Mind and one blanket charge, applied the expected
five-second recovery, granted zero self-treatment XP, and left no queue
residue. The identity-bound fixture restored its complete Medic-through-
Doctor-III, fire, HAM, XP, cooldown, and medicine preimage twice while both
isolated containers remained healthy. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ExtinguishFireCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Doctor tier IV restores all four authentic fourth-row boxes. The three
clinical branches cost 60,000 medical XP and two points each; Medicine
Crafting IV costs 33,000 medicine-crafting XP and two points. Wound Speed IV
grants `cureDisease`, Wound Treatment IV grants `revivePlayer`, and the row
adds only the retail healing and medicine-crafting modifiers. Five decoded
`patch_12_00.tre` schematic groups resolve to eighteen exact wound, revive,
fire-blanket, cure, and enhancement schematics; twenty-four accumulated NGE
combat-buff grants are explicitly absent. The identity-bound fixture purchases
all four boxes through production validation, grant, and XP deduction, then
restores its complete Medic-through-Doctor-III preimage. Protocol-27 live
acceptance observed the exact seven-command, eighteen-schematic, modifier,
XP, and skill-point vectors, with an empty client queue and healthy isolated
containers after idempotent cleanup. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DoctorTier4Progression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Master Doctor restores the authentic Publish 14.1 capstone after all four
tier-IV branches. The one-point, 10,000-credit title grants `place_hospital`,
the retail wound-treatment, wound-speed, healing-ability, and private hospital
modifiers, and fourteen exact advanced wound, disease-cure, enhancement, and
secondary-enhancement schematics decoded from `patch_12_00.tre`. Six NGE
capstone commands and five unrelated NGE defense/efficiency modifiers are
explicitly absent. The identity-bound fixture purchases the capstone through
production validation, grant, and XP deduction, then restores its complete
thirty-five-skill Medic-through-Doctor-IV preimage. Protocol-27 live acceptance
observed the exact command, schematic, modifier, XP, and skill-point vectors
with an empty client queue and healthy isolated containers after idempotent
cleanup. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DoctorMasterProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Doctor Wound Speed IV's active Cure Disease command is now live accepted. The
authentic optional-target, five-second nonqueued row enters a narrow adapter
that preserves SWGSource disease DOTs, antidote selection and power, area
packs, charge use, effects, and PvP-help paths. Pinned Core3 supplies the
seven-meter organic-patient and visibility gates, Focus-adjusted 100-Mind
cost, shared condition-treatment recovery, and fixed other-player 50-XP
boundary. Protocol-28 off-focus self-treatment reduced disease strength from
90 to zero, consumed exactly 91 Mind and one charge, applied the expected
five-second recovery, granted zero self-treatment XP, and left no queue
residue. The identity-bound fixture restored its complete
Medic-through-Doctor-Wound-Speed-IV, disease, HAM, XP, cooldown, and medicine
preimage twice while both isolated containers remained healthy. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14CureDiseaseCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Doctor Wound Treatment IV's active Revive Player command is now live accepted.
The original optional-target, ten-second nonqueued `cmdRevivePlayer` hook
enters a narrow adapter that preserves the dead-player and resuscitation-window
gates, group-or-consent and PvP-help rules, seven-meter range, explicit or
automatic revive-pack selection, and one-charge consumption. The retained
medical library applies the Focus-adjusted 200-Mind cost, heals all six primary
damage and wound channels, grants exact medical XP, restores upright posture,
and applies one minute of grogginess across all nine Publish 14 attributes.
Protocol-29 off-focus two-player acceptance revived the grouped patient at
3.97 meters, charged exactly 183 Mind and one medicine charge, healed 218
points, granted 234 medical XP, applied nine groggy modifiers, and left the
client queue empty. The identity-bound fixture restored both players'
locations, skills, HAM, wounds, modifiers, XP, regeneration, and owned
medicine twice without residue while both isolated containers remained
healthy. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14RevivePlayerCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Master Doctor hospital placement is now live certified across the retained
production ownership path. Core3's `place_hospital` ability is not a slash
command handler: its three city-hospital templates require city rank three and
the placement certification. SWGSource preserves the equivalent gate through
`tryEnterPlacementMode`, `canPlaceStructure`, and `canOwnStructure`; each
hospital row requires `private_place_hospital=100` and uses
`place_hospital` as its failure message. A protocol-29 identity-bound lifecycle
proved all three rows denied an unskilled player (`000`), granted Master Doctor
and observed the exact ability/modifier vector plus all three admissions
(`111`), then restored all three denials twice. This milestone changes no
production placement code and requires no client-tools or asset publication.
Both isolated containers remained healthy. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14HospitalPlacementCertification.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Publish 14.1 player armor now follows the pinned Core3 ordering for
authenticated pre-CU combat actions: pool-aligned hit location, personal
shield generator, the armor piece in that location, post-armor
`mitigate_damage` food, target HAM, then the existing wound roll. Weapon
armor-piercing rating is explicit in the exact pre-CU weapon profiles; rating
differences use the retail 1.25/0.50 multipliers, damage-type protection is
applied per piece, and each layer receives 20 percent condition wear. The
default NGE route remains unchanged. Protocol-29 live acceptance equipped a
real LIGHT bone helmet and queued `headShot1` off-focus: 16 raw damage became
6 after armor and 5 after food, Mind fell by exactly 5, the helmet lost 3
condition, and one food charge was consumed. A separate 1000-point production
helper probe observed 400 post-armor, 300 final, 200 condition wear, and one
food charge. The identity-bound fixture then restored both players exactly and
proved repeated cleanup while both isolated containers remained healthy.
Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ArmorMitigationOrdering.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Validate the Publish 14.1 rolling three-incap death threshold, Core3-derived
recovery timer, all-primary-pool recovery, stale-task guard, and counter reset:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14IncapacitationRecovery.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Publish 14.1 clone penalties now replace the retained incomplete/NGE path.
Every clone option carries a parallel registered-versus-alternate penalty:
registered facilities add no wounds, while alternate facilities add exactly
100 Health, Action, and Mind wounds plus 100 battle fatigue. Pinned Core3's
death-type split is preserved: PvE/AI deaths decay eligible insured items by
one percent and uninsured items by five percent, consume the insured flag,
and exclude auto-insured items; player death-blows do not decay items. The
retained `insure_decay_event` table independently encodes the same `1/5/1`
death row. NGE cloning sickness is no longer applied.

Protocol-31 acceptance now drives the real Publish 14 clone list rather than
calling the penalty helper directly. The server retains the bounded row seen
by the generic-selection callback when the legacy close payload omits it.
Same-scene clone warps mark completion pending and schedule an idempotent
five-second fallback through the normal `handleCloneRespawn` handler, covering
the retained engine path that can complete a warp without delivering its
callback. Live row-zero acceptance produced 100 wounds in all three primary
pools, 100 battle fatigue, no PvP item decay, an upright player, exact layered
cleanup, and healthy isolated server/database containers. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ClonePenalties.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The real PvE clone path now also emits the pinned Core3 Publish 14.1 decay
report after condition loss. Its single-button list uses the authentic title,
prompt, green section header, and post-decay condition percentages, and only
contains items that actually entered the one/five-percent decay path.
Auto-insured items and player death-blows remain excluded. A stale tracked
page is force-closed before replacement, while the retained
`handleDecayReport` callback removes the entire script-var tree on OK.

Protocol-31 acceptance rendered the real list with the controlled insured and
uninsured rifles at 99 and 95 percent, respectively. The close callback
removed the tracked page without changing the already-applied wounds or item
condition, and the identity-bound fixture restored its full preimage twice
while both isolated containers remained healthy. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14CloneDecayReport.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Publish 14.1 performance Action drain now replaces the retained no-op. Every
ten-second dance, music, and juggle heartbeat applies the pinned Core3
Quickness adjustment to the authentic performance-table base and truncates
the non-negative result. Solo and band flourishes use Core3's separate
Quickness-over-35 half-cost equation. Both paths refuse a charge when the
performer has exactly the required Action, preventing a performance from
draining its owner to zero.

Protocol-31 identity-bound acceptance used Basic dance index 281 and the
connected character's authoritative Quickness 400. The loop charged 25
Action (`100 -> 75`), the flourish charged 9 (`100 -> 91`), and both
equal-cost cases were rejected without mutation. Cleanup restored Action 500,
Quickness 400, and performance index zero; a second cleanup was already clean.
An interrupted earlier lifecycle was also recovered exactly after a server
restart. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14PerformanceActionDrain.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Protocol-32 real-client acceptance now closes the continuous dance-session
boundary. The dedicated client admitted the ordinary `startDance rhythmic`,
`flourish 1`, and `stopDance` commands; the authoritative server observed
rhythmic index 283, flourish Action `100 -> 91`, and complete explicit
performance-script detachment. A second real-client start at exactly 25
Action remained active until the ten-second heartbeat, then stopped
automatically without draining below the inclusive exhaustion boundary.

The fixture restored Action 500, Action regen 6.190476, posture, locomotion,
novice-skill ownership, and performance state. Its second cleanup was already
clean, and both isolated containers remained healthy. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14RealClientPerformanceSession.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Protocol-33 real-client acceptance closes the matching solo music boundary.
The fixture creates and equips its own slitherhorn, while the dedicated client
queues ordinary `startMusic starwars1`, `flourish 1`, and `stopMusic`
commands. The authoritative server must observe performance index 1, the
Star Wars 1 flourish charge at reference Quickness 400, the retained
15-second post-performance outro, and exact-cost exhaustion at 25 Action.
Live acceptance proved flourish Action `100 -> 91`, the one explicit-outro
heartbeat at `91 -> 66`, and automatic too-tired outro at exactly 25 Action
without underflow. Cleanup destroyed the instrument and restored Action 500,
Quickness 400, Action regen 6.190476, posture, locomotion, and novice-skill
ownership; its second pass was already clean. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14RealClientMusicSession.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Protocol-34 real-client acceptance extends the music seam to an authentic
two-player band. The identity-bound clients form their group with `/invite`
and `/join`, then the leader queues ordinary `startBand starwars1`,
`bandFlourish 1`, and `stopBand` commands. Both server-owned slitherhorn
performers must share one performance start time, pay their separately
calculated nine- and ten-Action flourish charges, and complete the retained
15-second band outro. The leader
then dissolves the group through `/disband` before the fixture restores both
locations, instruments, HAM, regen, skill ownership, posture, locomotion, and
performance state. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14RealClientBandMusicSession.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The first post-novice Entertainer progression slice restores the exact
Publish 14.1 Entertainer root, novice, and Music I rows. This removes retained
NGE novice commands and XP fields, restores the Pre-CU performance command
vector and search visibility, and makes Music I grant Rock plus the Fizz
instrument with only five points of music-healing ability. Protocol-35
acceptance purchases Music I through the production skill service, starts and
stops Rock through the real client, then submits the ordinary player
`surrenderSkill social_entertainer_music_01` command. The server must revoke
all three Music I abilities, return exactly two skill points without refunding
the spent music XP, and recompute the XP cap. Live acceptance also fixes two
cross-stack ambiguities: Rock on slitherhorn is runtime performance index 15
with instrument-audio ID 2, and the actor-routed `surrenderSkill` request must
carry no target because its command row declares `targetType=none`. Validate
with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerMusicOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The second Entertainer music slice restores the exact Publish 14.1 Music II
row: 5,000 music XP, three skill points, Star Wars 2, five
`healing_music_ability`, the two-schematic Fizz group, a 30,000 XP cap, and
four-by-four search visibility. Protocol-36 acceptance purchases the box,
plays slitherhorn Star Wars 2 at runtime index 29, completes the authentic
outro, and actor-routes the ordinary Music II surrender. The server proves
both commands and both schematics are removed, exactly three points return,
the spent XP stays spent, and the Music I cap is restored. Validate with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerMusicTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The third slice restores exact Music III costs, Folk, Fanfar, five
music-healing ability, a 90,000 XP cap, and tree visibility. Protocol 37
proves real Folk at runtime index 43, delayed stop, actor-only surrender,
four-point recovery, Music II grant retention, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerMusicThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The fourth slice restores exact Music IV costs, Star Wars 3, Kloo Horn, ten
music-healing ability, a 150,000 XP cap, and tree visibility. Protocol 38
proves real Star Wars 3 at runtime index 57, delayed stop, actor-only
surrender, five-point recovery, Music III grant retention, and exact cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerMusicFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The capstone slice restores the exact four-terminal Entertainer master row,
removing retained NGE XP, props, assembly modifiers, and schematics.
Protocol 39 proves all-terminal qualification, six-point purchase, five
capstone commands, four +10 healing modifiers, real Ceremonial at runtime
index 71, delayed stop, actor-only surrender, prerequisite retention, and
exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerMasterProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The first Dance branch slice restores exact Dance I costs, Basic 2, five
dance-healing ability, a 10,000 XP cap, and tree visibility. Protocol 40
proves real Basic 2 at runtime index 282, immediate stop, actor-only surrender,
two-point recovery, the novice 2,000 XP-cap fallback, and exact cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerDanceOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The second Dance branch slice restores exact Dance II costs, Rhythmic 2, five
additional dance-healing ability, a 30,000 XP cap, and tree visibility.
Protocol 41 proves real Rhythmic 2 at runtime index 284, immediate stop,
actor-only surrender, three-point recovery, Dance I command and skill
retention, the Dance I 10,000 XP-cap fallback, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerDanceTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The third Dance branch slice restores exact Dance III costs, Footloose, five
additional dance-healing ability, a 90,000 XP cap, and tree visibility.
Protocol 42 proves real Footloose at runtime index 285, the exact
Quickness-adjusted 33 Action loop cost, immediate stop, actor-only surrender,
four-point recovery, Dance I-II grant retention, the Dance II 30,000 XP-cap
fallback, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerDanceThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The terminal Dance branch slice restores exact Dance IV costs, Formal, ten
additional dance-healing ability, a 150,000 XP cap, and title-box visibility.
Protocol 43 proves real Formal at runtime index 287, two exact
Quickness-adjusted 33 Action loop drains, immediate stop, actor-only
surrender, five-point recovery, Dance I-III grant retention, the Dance III
90,000 XP-cap fallback, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerDanceFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The first Hairstyle branch slice restores exact Hairstyle I costs, the private
hair marker, one hair customization rank, a 10,000 Image Designer XP cap,
and tree visibility. Protocol 44 proves production purchase, actor-only
surrender, two-point recovery, the novice 2,000 XP-cap fallback, and exact
cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerHairstyleOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The second Hairstyle branch slice restores exact Hairstyle II costs, its
private marker, one face and one markings rank, a 20,000 Image Designer XP
cap, and tree visibility. Protocol 45 proves production purchase, actor-only
surrender, three-point recovery, Hairstyle I retention, its 10,000 XP-cap
fallback, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerHairstyleTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The third Hairstyle branch slice restores exact Hairstyle III costs, its
private marker, one additional hair rank, a 30,000 Image Designer XP cap, and
tree visibility. Protocol 46 proves production purchase, actor-only surrender,
four-point recovery, Hairstyle I-II retention, the Hairstyle II 20,000 XP-cap
fallback, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerHairstyleThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The terminal Hairstyle branch slice restores exact Hairstyle IV costs, its
private marker, one hair and one face rank, a 30,000 Image Designer XP cap,
title-box status, and tree visibility. Protocol 47 proves production purchase,
actor-only surrender, five-point recovery, Hairstyle I-III retention, the
Hairstyle III 30,000 XP-cap fallback, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerHairstyleFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The Dancer entry slice restores the searchable profession root and exact
novice box: Dance IV plus Healing IV prerequisites, 50,000 Dance XP, six
points, Popular, Poplock, registration, four distinct healing modifiers, and
the 350,000 cap. It removes the retained NGE Bunduki/prop/crafting surface.
Protocol 48 proves real Popular at runtime index 291, its exact
Quickness-adjusted 36 Action drain, actor-only surrender, six-point recovery,
both Entertainer prerequisite boxes, the Dance IV 150,000 cap fallback, and
exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerNoviceProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready
