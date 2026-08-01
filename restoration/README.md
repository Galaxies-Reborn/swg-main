# Pre-CU restoration overlays

This directory owns restoration changes without committing edits inside the
dsrc, exe, or src gitlinks. The manifest locks the x64 server component commits. Scripts
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
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-PrecuRootRuntimeParity.ps1 -SourceRoot <materialized-staging-directory>

Deploy a materialized source mount to the existing PRE-CU Docker container with
a fail-closed sync/build/restart sequence:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Deploy-PrecuServer.ps1

The deployment command forces the read-only source mount into Docker's writable
build volume before compiling. It verifies the synchronized Scout-harvest and
combat-cadence sources, compiled Scout bytecode, ELF x86-64 server binary,
healthy cluster readiness, and the binary mapped by a live game process. A
plain container restart intentionally does not rebuild changed host sources.

Validate the Publish 14.1 creation/login invariant:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14CharacterCreation.ps1 -SourceRoot <materialized-staging-directory>

Validate retirement of the later NGE class/roadmap skill-template graph while
retaining the empty datatable schema required by inherited client libraries:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NgeSkillTemplateRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

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

Validate persistent Publish 14.1 wounds, schema-272 storage, login/combat shock
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

Validate the later expansion-world scene set, authentic Mustafar/Kashyyyk
starport matrix, Tansarii instance routing, all Ord Mantell shards, and the
Hoth/Nova Orion/heroic buildouts after materializing the overlays:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-PrecuExpansionWorlds.ps1 -SourceRoot <materialized-staging-directory>

All scenes remain registered and available in the materialized source. The
dedicated `docker-compose.precu.yml` profile sets `SWG_START_PLANETS` to a
bounded local acceptance set so a workstation does not start every ground,
space, and instance process simultaneously. Override
`SWG_PRECU_START_PLANETS` for a different test set, or set it to the complete
source list for a full-world deployment.

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
Fresh-character allocations commit immediately while either authoritative
tutorial lifecycle marker remains present. First-planet handoff retires that
free path. Normal-world targets remain pending until a distinct entertainer
commits them with both players still in the exact permanent salon or
entertainment-module camp recorded by the authenticated Image Designer session.

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

The first Dancer Ability branch slice restores the exact searchable
four-by-four box: Dancer novice prerequisite, 87,500 Dance XP, five points,
Spotlight, Color Lights, Dazzle, +10 dance Mind healing, and the 500,000 cap.
It replaces the retained NGE Entertainer XP, 25,000-cost, 200,000-cap,
modifier-free hidden row. Protocol 49 proves production purchase,
actor-only client surrender, five-point recovery, Dancer novice and its grants
retained, 350,000-cap recomputation, all modifier deltas reset, and exact
cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerAbilityOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The second Dancer Ability branch slice restores the exact searchable
four-by-four box: Ability I prerequisite, 125,000 Dance XP, four points,
Distract, +10 dance Mind healing, and the 700,000 cap. It removes the NGE-only
Color Swirl grant and replaces the retained Entertainer XP, 50,000-cost,
400,000-cap, modifier-free hidden row. Protocol 50 proves production purchase,
actor-only client surrender, four-point recovery, Ability I and all of its
grants retained, 500,000-cap recomputation, all modifier deltas reset, and
exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerAbilityTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The third Dancer Ability branch slice restores the exact searchable
four-by-four box: Ability II prerequisite, 175,000 Dance XP, three points,
Smoke Bomb, +20 dance Mind healing, and the 900,000 cap. It removes the
NGE-only Center Stage grant and replaces the retained Entertainer XP,
100,000-cost, 500,000-cap, modifier-free hidden row. Protocol 51 proves
production purchase, actor-only client surrender, three-point recovery,
Ability II and Distract retained, 700,000-cap recomputation, all modifier
deltas reset, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerAbilityThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The terminal Dancer Ability branch slice restores the exact searchable title
box: Ability III prerequisite, 225,000 Dance XP, two points, no command grant,
+25 dance Mind healing, and the 900,000 cap. It removes the NGE-only Floor
Lights grant and replaces the retained Entertainer XP, 125,000-cost,
500,000-cap, modifier-free hidden row. Protocol 52 proves production purchase,
actor-only client surrender, two-point recovery, Ability III and Smoke Bomb
retained, 900,000-cap recomputation, all modifier deltas reset, and exact
cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerAbilityFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The first Dancer Wound branch slice restores the exact searchable
four-by-four box: Dancer novice prerequisite, 25,000 Entertainer Healing XP,
five points, +5 dance Wound healing, and the 200,000 cap. It replaces the
retained NGE Dance XP, 87,500-cost, +10-modifier hidden row. Protocol 53
proves production purchase, actor-only client surrender, five-point recovery,
Dancer novice and all three grants retained, the Healing IV 75,000-cap
fallback, the independent 350,000 Dance XP cap, all modifier deltas reset,
and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerWoundOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The second Dancer Wound branch slice restores the exact searchable
four-by-four box: Wound I prerequisite, 50,000 Entertainer Healing XP, four
points, +10 dance Wound healing, and the 400,000 cap. It replaces the retained
NGE Dance XP, 125,000-cost hidden row. Protocol 54 proves production purchase,
actor-only client surrender, four-point recovery, Wound I and Dancer novice
grants retained, the Wound I 200,000-cap fallback, the independent 350,000
Dance XP cap, all modifier deltas reset, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerWoundTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The third Dancer Wound branch slice restores the exact searchable
four-by-four box: Wound II prerequisite, 100,000 Entertainer Healing XP,
three points, +10 dance Wound healing, and the 500,000 cap. It replaces the
retained NGE Dance XP, 175,000-cost, +20-modifier hidden row. Protocol 55
proves production purchase, actor-only client surrender, three-point recovery,
Wound II and lower boxes retained, the Wound II 400,000-cap fallback, the
independent 350,000 Dance XP cap, all modifier deltas reset, and exact
cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerWoundThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The terminal Dancer Wound branch slice restores the exact searchable title
box: Wound III prerequisite, 125,000 Entertainer Healing XP, two points,
+15 dance Wound healing, and the 500,000 cap. It replaces the retained NGE
Dance XP, 225,000-cost, +25-modifier hidden row. Protocol 56 proves production
purchase, actor-only client surrender, two-point recovery, Wound III and lower
boxes retained, the unchanged Wound III 500,000-cap fallback, the independent
350,000 Dance XP cap, all modifier deltas reset, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerWoundFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The first Dancer Shock branch slice restores the exact searchable
four-by-four box: Dancer novice prerequisite, 25,000 Entertainer Healing XP,
five points, +10 dance Shock healing, and the 200,000 cap. It removes the
retained NGE Entertainer XP, ribbon-prop command, +10 prop assembly,
`craftDancePropG` schematic group, and hidden row. Protocol 57 proves
production purchase, all three NGE grants absent, actor-only client surrender,
five-point recovery, Dancer novice retained, the Healing IV 75,000-cap
fallback, the independent 350,000 Dance XP cap, all modifier deltas reset,
and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerShockOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The second Dancer Shock branch slice restores the exact searchable
four-by-four box: Shock I prerequisite, 50,000 Entertainer Healing XP, four
points, +10 dance Shock healing, and the 400,000 cap. It removes the retained
NGE Entertainer XP, ribbon-magic prop command, +10 prop assembly,
`craftDancePropH` schematic group, and hidden row. Protocol 58 proves
production purchase, all three NGE grants absent, actor-only client surrender,
four-point recovery, Shock I retained, the 200,000-cap fallback, the
independent 350,000 Dance XP cap, all modifier deltas reset, and exact
cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerShockTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The third Dancer Shock branch slice restores the exact searchable
four-by-four box: Shock II prerequisite, 100,000 Entertainer Healing XP,
three points, +20 dance Shock healing, and the 500,000 cap. It removes the
retained NGE Entertainer XP, double-ribbon-magic prop command, +10 prop
assembly, `craftDancePropI` schematic group, and hidden row. Protocol 59
proves production purchase, all three NGE grants absent, actor-only client
surrender, three-point recovery, Shock II retained, the 400,000-cap fallback,
the independent 350,000 Dance XP cap, all modifier deltas reset, and exact
cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerShockThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The terminal Dancer Shock branch slice restores the exact searchable title
box: Shock III prerequisite, 125,000 Entertainer Healing XP, two points, +25
dance Shock healing, and the 500,000 cap. It removes the retained NGE
Entertainer XP, spark-ribbon prop command, +10 prop assembly,
`craftDancePropJ` schematic group, and hidden row. Protocol 60 proves
production purchase, all three NGE grants absent, actor-only client surrender,
two-point recovery, Shock III retained, terminal-cap retention, the
independent 350,000 Dance XP cap, all modifier deltas reset, and exact
cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerShockFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The first Dancer Knowledge branch slice restores the exact searchable
four-by-four box: Dancer novice prerequisite, 87,500 Dance XP, five points,
Popular 2, Tumble, +10 dance healing ability, and the 500,000 cap. It removes
the NGE-only Bunduki 2 command and hidden row. Protocol 61 proves production
purchase, both authentic commands present, Bunduki 2 absent, actor-only client
surrender, five-point recovery, Dancer novice and its three commands retained,
the 350,000-cap fallback, all modifier deltas reset, and exact cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerKnowledgeOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The second Dancer Knowledge branch slice restores the exact searchable
four-by-four box: Knowledge I prerequisite, 125,000 Dance XP, four points,
Poplock 2, Tumble 2, +10 dance healing ability, and the 700,000 cap. Protocol
62 proves production purchase, both new commands and all Knowledge I commands
present, actor-only client surrender, four-point recovery, Knowledge I and its
commands retained, the 500,000-cap fallback, all modifier deltas reset, and
exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerKnowledgeTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The third Dancer Knowledge branch slice restores the exact searchable
four-by-four box: Knowledge II prerequisite, 175,000 Dance XP, three points,
Lyrical, Breakdance, +10 dance healing ability, and the 900,000 cap. Protocol
63 proves production purchase, both new commands and all Knowledge I-II
commands present, actor-only client surrender, three-point recovery,
Knowledge II and its commands retained, the 700,000-cap fallback, all
modifier deltas reset, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerKnowledgeThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The fourth Dancer Knowledge branch slice restores the exact searchable title
box: Knowledge III prerequisite, 225,000 Dance XP, two points, Breakdance 2,
Exotic, Exotic 2, +10 dance healing ability, and the terminal 900,000 cap.
Protocol 64 proves production purchase, all three new commands and all
Knowledge I-III commands present, actor-only client surrender, two-point
recovery, Knowledge III and its commands retained, terminal cap retention,
all modifier deltas reset, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerKnowledgeFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The Dancer master slice restores the exact searchable four-branch title box:
all four terminal prerequisites, zero XP, one point, five authentic commands,
and all eight authentic modifiers. It removes the NGE-only 350,000 Dance XP
cost and 500,000 cap grant, spark prop command, prop assembly, and schematic
group. Protocol 65 proves zero-XP production purchase, exact grants,
actor-only client surrender, one-point recovery, all four terminal branches
and their commands retained, parent Dance and Healing XP caps retained, all
master modifier deltas reset, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14DancerMasterProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The Musician novice slice restores the exact searchable four-by-four title
box: Music IV and Healing IV prerequisites, 50,000 Music XP, six points,
Traz, location registration, Star Wars 4, five authentic modifiers, and the
classic instrument schematic group. It removes the NGE novice-level Kloo Horn
substitution while retaining Kloo Horn through Music IV. Protocol 66 proves
production purchase, exact command/modifier/schematic grants, actor-only
client surrender, six-point recovery, both prerequisite boxes and their
commands retained, Music-cap recomputation to 150,000, Healing-cap retention
at 75,000, modifier rollback, and exact cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianNoviceProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The Musician Ability I slice restores the exact searchable four-by-four box:
Musician novice prerequisite, 87,500 Music XP, five points, a 500,000 cap,
spotlight, colorlights, dazzle, +10 instrument assembly, and +10 Music mind
healing. Protocol 67 proves production purchase, exact grants, actor-only
client surrender, five-point recovery, Musician novice and all novice commands
retained, parent Kloo Horn retained, Music-cap recomputation to 350,000,
Healing-cap retention at 75,000, modifier rollback, and exact cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianAbilityOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The Musician Ability II slice restores the exact searchable four-by-four box:
Ability I prerequisite, 125,000 Music XP, four points, a 700,000 cap, Fire
Jet, +15 instrument assembly, +10 Music mind healing, and the Traz schematic
group. It removes the NGE-only Laser Show command. Protocol 68 proves exact
production purchase, actor-only client surrender, four-point recovery,
Ability I and all its commands retained, Music-cap recomputation to 500,000,
Healing-cap retention at 75,000, schematic and modifier rollback, and exact
cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianAbilityTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Ability III restores the exact searchable box: Ability II,
175,000 Music XP, three points, 900,000 cap, Ventriloquism, +15 assembly,
+20 Music mind healing, and Bandfill schematics, while removing NGE Fire Jet
2. Protocol 69 proves purchase, production surrender, three-point recovery,
Ability II grant retention, 700,000-cap recomputation, rollback, and cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianAbilityThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Ability IV restores the exact searchable box: Ability III,
225,000 Music XP, two points, terminal 900,000 cap, +25 instrument assembly,
+25 Music mind healing, and Omni Box schematics. It grants no command and
removes NGE Featured Solo. Protocol 70 proves purchase, production surrender,
two-point recovery, Ability III, Ventriloquism, and Bandfill retention,
terminal-cap retention, modifier and schematic rollback, and cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianAbilityFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Wound I restores the exact searchable box: Musician novice,
25,000 Entertainer Healing XP, five points, a 200,000 Healing cap, and +5
Music wound healing. It rejects the NGE Music XP and +10 modifier contract.
Protocol 71 proves purchase, production surrender, five-point recovery,
novice command and schematic retention, Healing-cap recomputation to 75,000,
independent Music-cap retention at 350,000, modifier rollback, and cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianWoundOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Wound II restores the exact searchable box: Wound I, 50,000
Entertainer Healing XP, four points, a 400,000 Healing cap, and +10 Music
wound healing. Protocol 72 proves purchase, production surrender, four-point
recovery, Wound I and novice grant retention, Healing-cap recomputation to
200,000, independent Music-cap retention, modifier rollback, and cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianWoundTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Wound III restores Wound II, 100,000 Entertainer Healing XP, three
points, a 500,000 cap, and +10 Music wound healing while rejecting NGE's
175,000 Music XP and +20 contract. Protocol 73 proves purchase, surrender,
Wound II retention, 400,000-cap recomputation, rollback, and cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianWoundThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Wound IV completes the branch with the exact searchable title box:
Wound III, 125,000 Entertainer Healing XP, two points, a terminal 500,000
Healing cap, and +15 Music wound healing. It rejects NGE's hidden, graphless
225,000 Music XP and +25 contract. Protocol 74 proves purchase, production
surrender, Wound III retention, terminal-cap retention, rollback, and
idempotent cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianWoundFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Shock I restores the exact searchable box: Musician novice, 25,000
Entertainer Healing XP, five points, a 200,000 Healing cap, and +10 Music
shock healing. It removes the NGE duplicate Traz, assembly modifier, and Traz
schematic group while retaining Traz from the novice parent. Protocol 75
proves purchase, production surrender, novice retention, 75,000-cap
recomputation, rollback, negative grants, and idempotent cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianShockOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Shock II restores Shock I, 50,000 Entertainer Healing XP, four
points, a 400,000 Healing cap, and +10 Music shock healing. Protocol 76 proves
purchase, production surrender, Shock I retention, 200,000-cap recomputation,
and rejection of the NGE Bandfill command, assembly modifier, and schematic
group. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianShockTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Shock III restores Shock II, 100,000 Entertainer Healing XP, three
points, a 500,000 Healing cap, and +20 Music shock healing. Protocol 77 proves
purchase, production surrender, Shock II retention, 400,000-cap recomputation,
and rejection of the NGE Flutedroopy command, assembly modifier, and schematic
group. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianShockThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Shock IV completes the branch with the exact searchable title box:
Shock III, 125,000 Entertainer Healing XP, two points, a terminal 500,000
Healing cap, and +25 Music shock healing. It removes NGE's hidden Omnibox
command, assembly modifier, and schematic group. Protocol 78 proves purchase,
production surrender, Shock III retention, terminal-cap retention, rollback,
negative grants, and idempotent cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianShockFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Knowledge I restores the exact searchable box: Musician novice,
87,500 Music XP, five points, a 500,000 Music cap, Ballad, and +5 Music
healing ability. It removes NGE's extra Swing grant. Protocol 79 proves
purchase, production surrender, novice command and schematic retention,
350,000-cap recomputation, independent Healing-cap retention, modifier
rollback, and idempotent cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianKnowledgeOneProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Knowledge II restores Knowledge I, 125,000 Music XP, four points, a
700,000 Music cap, Bandfill, Funk, and +10 Music healing ability. It moves
Bandfill back to its authentic branch after removal from NGE-mutated Shock II.
Protocol 80 proves purchase, production surrender, Knowledge I and Ballad
retention, 500,000-cap recomputation, independent Healing-cap retention,
modifier rollback, and idempotent cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianKnowledgeTwoProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Knowledge III restores Knowledge II, 175,000 Music XP, three points,
a 900,000 Music cap, Waltz, Flutedroopy, and +10 Music healing ability. It
moves Flutedroopy back to its authentic branch after removal from NGE-mutated
Shock III. Protocol 81 proves purchase, production surrender, all parent
commands retained, 700,000-cap recomputation, independent Healing-cap
retention, modifier rollback, and idempotent cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianKnowledgeThreeProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician Knowledge IV completes the branch with Knowledge III, 225,000 Music
XP, two points, a terminal 900,000 Music cap, Jazz, Omnibox, and +15 Music
healing ability. Protocol 82 proves purchase, production surrender, all
parent commands retained, terminal-cap retention, modifier rollback, and
idempotent cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianKnowledgeFourProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician master closes the profession with all four terminal branches, zero
XP, one point, Virtuoso, Nalargon, cantina and theater placement, and the exact
nine Publish 14.1 modifiers. It removes the NGE 350,000-XP charge, 500,000 cap,
altered healing and assembly values, hidden graph state, and Nalargon schematic
group. Protocol 83 proves purchase, production surrender, four-terminal
retention, no schematic grant, modifier rollback, both terminal-cap retentions,
and idempotent cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianMasterProgression.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Musician profession closure restores the top-level `social_musician` root as
a searchable `fourByFour` profession definition and verifies the complete
19-row family against one normalized Publish 14.1 digest. This removes the
last NGE-hidden, graphless Musician table row after every purchasable box was
already restored. The compiled table loaded in the protocol-83 client and the
Skills window opened off-focus at the restored 250-point baseline. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14MusicianProfessionClosure.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Weapon certification ownership restores the Core3/Publish 14.1 template
contract to every exact weapon shared by the two baselines. The pinned import
maps 314 non-empty Core3 declarations, materializes 293 exact SWGSource
templates, and reports 21 absent ranged-melee variants without inventing
substitutions. The production gate now requires every template declaration
through command or skill ownership and no longer reads NGE profession
templates, combat levels, or weapon-level table columns. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14WeaponCertificationOwnership.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Force-sensitive eligibility now reads the native Jedi state instead of the
retired NGE class template. The inherited combat-level helper remains
ABI-compatible but fails closed, while both crystal-tuning gates use Core3's
exact `force_title_jedi_rank_01` requirement. A reversible live probe proves
state 1, state 2, skill admission, and exact restoration. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ForceSensitiveEligibility.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

NGE inspiration retirement removes profession-template duration calculation
and all three active heartbeat calls while retaining music/dance healing,
action drain, and XP. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NgeInspirationRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The authentic entertainer session now accumulates Core3's two-minute duration
segments and performance shock-heal strength for same-group or explicitly
targeted patrons in qualifying venues. Stopping watch/listen applies the
percentage to unmodified Mind for dance or Focus and Willpower for music,
preserves stronger existing buffs, and clears transient session state. The
NGE class-percentage inspiration path remains retired. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EntertainerAttributeBuffSession.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The active NGE Smuggler corpse-inspection menu is retired. Publish 14.1
Smuggler owns container/terminal/weapon/armor slicing, not the
`class_smuggler_phase1_novice` corpse-contraband command, combat-level gate,
or expertise loot roll. Ordinary corpse loot, group loot, and harvesting
remain unchanged, and the inherited command handler is retained only as a
compatibility boundary. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NgeCorpseContrabandRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

All three Corvette loot containers now admit restored Publish 14.1
characters without an NGE Trader/Entertainer class-template check. Their
ITEM_OPEN, enemy-spawn, ownership, and timed-respawn behavior remains intact.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14CorvetteLootAdmission.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

GCW crafting-tool attributes no longer read an NGE Trader profession. Charges
and power remain unchanged, and the class-dependent fatigue display collapses
to its neutral value of one for the classless Publish 14.1 progression model.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14GcwCraftingToolClassRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The shared profession predicate now answers from exact Publish 14.1 novice
skill ownership, permitting simultaneous professions instead of reading one
NGE class template. The retained Officer enum is a compatibility alias for
Squad Leader, Force Sensitive uses native Jedi state, and Spy and unknown
values fail closed. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ProfessionOwnershipPredicate.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Direct content, static-item, dynamic-armor, click-item, and loot-schematic
profession gates now accept exact owned skills or the known compatibility
tokens through that predicate. Empty, Spy, unknown, and ambiguous later
class-master requirements fail closed. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ProfessionRequirementGates.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Armor revalidation now uses the same exact ownership rule as equip and
transfer for both equipped and appearance inventories. Mandalorian armor uses
Core3's four exact master alternatives—Bounty Hunter, Commando, Squad Leader,
or Ranger—instead of three NGE phase skills. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ArmorOwnershipRevalidation.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The item script layer no longer reads the singular NGE class template. The
unused senator-crate read is removed, and the later Collection ice-cream
fryer's `trader_0a`-only Domestics reward is retired without assigning it to a
speculative Publish 14.1 profession. Ordinary fryer rewards, combinations,
fourth ingredients, and the existing debuff fallback remain intact. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ItemClassReadRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The NGE Build-a-Buff completion path no longer feeds the later entertainer
profession-slot Collection or reads a singular class template. Its tracker,
two-hour duration gate, random roll, and Collection slot mutation are retired.
The already-restored Publish 14.1 entertainer Mind or Focus/Willpower session
remains the authoritative buff path. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NgeEntertainerCollectionRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Later droid combat-module display tiers and droid caps no longer rise from a
singular NGE Trader class or combat levels 30/60. Positive module potency keeps
the classless runtime's neutral display level one and the inherited cap stays
60; exact Droid Engineer ownership does not reactivate the unauthored bonus.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NgeDroidClassBonusRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Post-CU expertise now fails closed: combat level no longer auto-grants its
root or introduction, and direct expertise skill admission is rejected
without consulting an NGE profession template. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NgeExpertiseAdmissionRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Player Generated Chronicles quest completion no longer routes later level- and
class-derived rewards into Publish 14.1 combat, crafting, or entertainer XP.
Both PGC reward overloads fail closed while the rest of the isolated
Chronicles compatibility surface remains untouched. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14PgcQuestXpRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

GCW score rows and instance-entry logs no longer present one NGE roadmap
profession or combat level. They use a neutral `Publish 14.1 skills` label and
level zero where the fixed GCW schema requires a value. Score accumulation,
faction data, group logging, and both instance transfer calls remain intact.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NeutralProgressionPresentation.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Residual public skill-library compatibility helpers no longer calculate HAM
or secondary statistics from an NGE profession/combat level, emit level-up
stat spam, or validate expertises against a singular class template. Persisted
expertise allocations are removed with the narrow native reset so pre-CU buffs
and respec state remain untouched. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14SkillLibraryProgressionRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The NGE-inspiration retirement overlay is rebased onto the preceding
entertainer healing and action-drain overlays. This preserves identical
runtime behavior while allowing the numbered overlay series to replay
sequentially from the pinned baseline through milestone 160.

Seven post-victory Heroic log rows no longer present a singular NGE
profession. The Tusken Army, Axkva Min, Star Destroyer, IG-88, Exar Kun, and
both Echo Base victory paths use the neutral `Publish 14.1 skills` label while
preserving token awards, timers, objectives, victory SUI, and group identity.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14HeroicProgressionPresentation.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Post-CU New Player Experience class-template gates fail closed instead of
being translated into Publish 14.1 professions. The Tatooine handoff detaches
without granting NPE quests or rewriting the toolbar, and the later
entertainer training action cannot grant its quest or toolbar layout. Skill
teachers and skill-box acquisition remain the authoritative onboarding path.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NpeClassProgressionRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

GCW city-pylon construction no longer reads a singular Trader class. One dead
read is removed, and the unsupported reduced-fatigue Trader branch is replaced
by the neutral inherited five-stack path. Quest, tool, construction value,
faction participation, and crafting-credit behavior remain intact. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14GcwPylonClassRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Post-era TCG vendor contracts and Player Generated Chronicles relic booster
packs fail closed at both menus and state-mutating callbacks. Their script
bodies remain link-compatible for old object data, but they cannot apply
vendor skill mods, create NPCs, consume contracts, or mint relics. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14TcgChroniclesRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

NGE profession-respec sellers, combat-respec tokens, the repurposed veteran
anti-decay kit, and combat-level holocrons now fail closed at every reachable
menu or callback. Base-player template-change handlers only clear stale respec
state. The remaining 41 template reads are an exact, machine-checked inventory
of native, CTS, dormant compatibility, GM/QA, and reversible fixture code.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14RespecAutolevelEntrypointRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Player Generated Chronicles and Storyteller command scripts now detach on
attach and initialization. Chronicles client-ready handling no longer queues
terms-of-service or reserve-reminder messages. The only retained storyteller
attachment call is inside the already-retired live-conversion script.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ChroniclesScriptLifecycleRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Saga holocrons, control devices, donated-credit rewards, Chronicles reward
vendors, the Fan Faire PGC profession vendor, and Storyteller token vendors
now fail closed at attach, menu, conversation, and callback boundaries.
Persisted object and conversation classes remain loadable. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14PgcHolocronVendorRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Nine player-owned Storyteller token scripts now detach synchronously on both
attach and initialization. Existing token objects and serialized data remain
loadable, but their menu, alarm, and deployment handlers cannot remain
attached. Already-deployed controllers are deliberately retained so their
timers can clean up existing world objects. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14StorytellerTokenLifecycleRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Residual command-table movement and rotation handlers now retain their link
names but perform no mutation, including radial queue wrappers. Ordinary city
zoning remains available while its later Storyteller-rights choice and direct
command fail closed. CSR destruction commands remain available for cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14StorytellerCommandSurfaceRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Pre-existing Storyteller invitation terminals now detach on attach and
initialization, preserving serialized objects without exposing invite menus
or sending relationship-acceptance messages. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14StorytellerInvitationTerminalRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The later shared holiday-band spawner now destroys tracked musicians and
instruments on initialization, then detaches. New attachments detach without
spawning or creating badge trigger volumes. Buildout anchors and their
separate event cleanup scripts remain intact. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14StorytellerBandSpawnerRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Later Storyteller event anchors no longer become persistent through the
anniversary helper. The `deleteEventProps` operator switch still destroys
anchors immediately; otherwise the helper detaches, leaving independent event
scripts intact. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14StorytellerEventPersistenceRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Later Life Day gift/badge trees and Love Day berry-conversion fountains now
detach at attach and initialization. Their buildout anchors remain loadable,
but reward menus and mutations cannot remain active. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14LaterHolidayRewardAnchorRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Empire and Remembrance Day parade anchors now invoke their existing sound,
NPC, and vehicle cleanup before detaching. Visual anchors remain, but no
parade, gift, badge, or ceremony lifecycle is scheduled. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EmpireDayParadeControllerRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Later Empire and Remembrance Day area, patrol, and random-sign spawners now
clean up tracked creations and detach at lifecycle entry. The shared guard is
limited to eight event-specific spawn-name families and the exact
`empireday_ceremony` requirement, preserving ordinary generic spawners.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EmpireDaySpawnerRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The independent Empire Day building-interior spawner now destroys tracked
NPCs, removes their persistent tracking state, and detaches from its host
building. Eight buildout attachments and 317 rows across 12 later spawn
tables are covered; the host cantinas and military buildings remain intact.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EmpireDayInteriorSpawnerRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The shared holiday controller can no longer start Empire Day from server
startup or its four god-speech commands. Each path stops stale universe-wide
event state synchronously and reports the Publish 14.1 retirement boundary;
the Halloween, Life Day, and Love Day branches remain for separate audits.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EmpireDayControlPlaneRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Empire Day planet leaderboard roots, scores, and timestamps are now removed
regardless of server configuration. Queued setup and reset callbacks clean
the same namespace and return, while Life Day planet score data and alarms
remain available for their separate audit. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EmpireDayPlanetStateRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Five generic systems no longer branch on the Empire Day configuration. Theed
guards and delivery NPCs remain active, GCW spawns and city guard difficulty
use regional control, and both banner classes render their requested faction.
Only the later event overrides were removed. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EmpireDayGenericSystemOverrides.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The three persistent Tyrena Love Day barrels remain as passive serialized
anchors. Their shared wave controller requires an already-active matching
quest task; only three Mr. Hate tables match, and their sole grantable
variants came from the retired Blaire producer. The generic controller and
ordinary wave quests remain unchanged. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14LoveDayWaveBarrelAdmissionClosure.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The final Love Day residual audit classifies all 34 event buildout rows and
all 37 Love Day-bearing server scripts. Every world-producing row is covered
by an earlier retirement; remaining code is subordinate compatibility,
existing-reward behavior, cleanup/rejection logic, passive data, or a
privileged character-builder diagnostic. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14LoveDayResidualReferenceClosure.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Both Galactic Moon Festival city buildouts are wholly registered behind
`eventRequired=halloween`: 638 passive decoration rows and 26 generic
skeleton/vendor spawners cannot instantiate without the universe event.
Startup and operator paths only stop that event, and the engine unloads
already-created event rows when the planet event list changes. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14HalloweenBuildoutAdmissionClosure.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The Halloween player/reward chain is also admission-closed. Its five
trick-or-treat costumes come only from the event vendor, whose two world
spawners are inside those inactive buildouts. Coin payout and all 46 catalog
rows are subordinate to that path; only privileged diagnostics remain as
independent grants. Existing projectors, song books, and house-sign
compatibility remain available to already-owned items. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14HalloweenPlayerRewardAdmissionClosure.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The final Halloween residual audit classifies all 664 event-city rows, the
one incidental outside prop, two creature definitions, 46 vendor rows, 21
event master items, 13 buffs, and all 12 identifier-bearing server scripts.
No unclassified world producer, quest, or direct event start remains. Passive
templates, existing reward/sign compatibility, and privileged diagnostics are
retained. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14HalloweenResidualReferenceClosure.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The Life Day lineage inventory separates the retained 2004 Wookiee quest from
the later factional city event. It preserves the Mos Espa candy route, six
forest orbs, five `lifeday04*` conversations, five static-NPC anchors, and
original rewards while classifying 27 later city rows and 42 faction-vendor
rows. It also proves the two original anchor-spawner scripts currently have no
automatic admission anchor and require restoration. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14LifeDayLineageBoundary.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The three later factional Life Day city producer sets are retired through the
exact `eventRequired=life_day` discriminator: six random objective spawners
and 18 vendor/soldier area spawners clean tracked children and fail queued
callbacks closed. Their three main-tree anchors were already inert. The
retained `lifeday` universe event, Mos Espa/orb route, five conversations, and
two original NPC-spawner scripts remain untouched. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14LaterLifeDayCitySpawnerRetirement.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The original 2004 Life Day admission path now reconciles three city anchors
and twelve forest anchors through the retained `lifeday` control plane. Each
planet creates only while its scene is authoritative, preventing an
unavailable remote scene from being misplaced into the local GameServer.
Anchors and their five `lifeday04*` quest NPC variants are idempotent,
ownership-marked, and cleanup-first. The identity-locked fixture drives
immediate activation and deactivation without weakening the default
`lifeday=false` boundary. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14LifeDay2004AdmissionRestoration.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The five original conversations form a one-time talk-to-NPC quest rather than
a candy/orb collection. Kkatamik initializes a tracker, the Elder contributes
bit 1, and Anarra, Tebeurra, and Radrrl contribute bits 2, 4, and 8; mask 15
unlocks a four-item random reward or Wookiee robe choice. Reward state changes
only after successful inventory creation, so a full inventory remains
retryable. The historical unused age calculation and unreachable fallback are
retained exactly. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14LifeDay2004QuestStateMachine.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The stateful skills-window surrender boundary now matches the pinned Core3
behavior that can be safely reproduced in this engine. Surrendering
`combat_bountyhunter_investigation_03` aborts a live bounty mission. Squad
Leader surrender retires active volley targeting and clears obsolete rally
and pending-XP state when the novice box leaves; passive group defense already
reads the leader's current skill modifiers and needs no copied cache.

Pilot skills remain recruiter-only. A direct skills-window attempt is routed
through the retained revoke veto, producing the localized retirement warning
and recruiter waypoint without dropping the skill. Force and Jedi families
remain fail-closed because their Core3 path requires village, title,
discipline, trial, and FRS eligibility beyond ordinary dependency checks.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14StatefulProfessionSurrender.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The Force-sensitive phase opens only the 64 authentic intermediate boxes
whose names end in `_01` through `_04`. A player holding the Jedi rank title
cannot surrender at or below the retained 24-box floor; the production command
returns `jedi_spam:revoke_force_sensitive`. Successful revocation recalculates
Force power through the retained Jedi library.

Jedi novice and title boxes, discipline trees, active trials, and FRS ranks
remain outside generic surrender because those paths require specialized
village, trial, and rank state transitions. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ForceSensitiveSurrender.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Restored combat commands now emit the Publish-era `cbt_spam` prose key selected
by the pinned Core3 command stem and the authoritative hit, miss, evade,
counter, or block result. Hit prose receives applied damage; defended prose
receives the raw pre-defense value. Commands without a mapping retain the
existing SWGSource fallback.

The live fixture also owns the CDEF rifle certification explicitly and
reversibly. Empty-profession startup no longer makes the authenticated
`headShot1` validation depend on a stale character-template grant. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3CombatSpam.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The fail-closed Core3 generator now closes its first two ordinary weapon
specials: `polearmLegHit1` and `unarmedHeadHit1`. Their thin hooks, command and
combat rows, HAM multipliers, target pools, accuracy, duration, animation,
spam stems, skill ownership, and representative weapon profiles are pinned to
Core3 commit `6ea64f60ef33b89121c2a8d188b93f4bc6f158e8`.

The live x64 compatibility stack admits the staff as polearm type 7 with mask
`0x0080` and the default unarmed weapon as type 6 with mask `0x0040`. Both
commands passed the production client queue and server execution boundary;
the identity-bound fixture restored both players afterward. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3GeneratedCombatHooks.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The first deferred area-action seam restores `polearmSpinAttack1` with its
Core3 16-meter area range and RANDOM HAM target. RANDOM is resolved once for
each defender using Core3's inclusive 0..100 thresholds: Health on 0..60,
Action on 61..95, and Mind on 96..100. That one resolved pool is reused for
armor hit location, damage, and wound attribution.

The production x64 client admitted the command with polearm mask `0x0080`;
the server reported configured pool 3, a concrete resolved pool, authentic
`limbsmasher` spam, single-pool HAM damage, and successful queue removal. The
fixture restores both current HAM and any generated wounds or shock. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3RandomAreaCombat.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Validate the paired Core3 one-handed/two-handed area-spin restoration with:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3MeleeSpinAttacks.ps1 -SourceRoot <materialized-staging-directory> -Expectation Build

Core3 generated combat animations now preserve the command's base token and
append `_medium` only when applied damage exceeds one quarter of the weapon's
maximum damage; otherwise they append `_light`. `GENERATE_RANGED` additionally
appends `_face` for a head hit, while `GENERATE_INTENSITY` does not. Commands
without explicit metadata retain their existing animation, and creature
wildcard routing remains unchanged. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3GeneratedAnimation.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Validate the exact Core3 `bodyShot2` / `bodyShot3` Marksman-Pistoleer
continuation, including skill ownership, Health targeting, generated ranged
animation metadata, combat spam, and reversible pistol fixture ownership:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3BodyShotContinuation.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Validate the exact Core3 `headShot2` / `headShot3` rifle continuation:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3HeadShotContinuation.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Validate the exact Core3 `melee1hBodyHit1` Brawler one-handed continuation:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3OneHandBodyHitOne.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 239 closes the Phase-A Artisan runtime frontier. The server novice
row again carries its authoritative XP, command, and movement-mod fields; the
client profession asset remains byte-identical. The disposable station fixture
completed the production skillteacher payment/callback path, survived a
same-process relog and a game-server restart, surrendered through the
production command, and returned to its exact 191-point/zero-XP/zero-credit
baseline. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14PhaseARuntimeClosure.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 240 closes the remaining nonstandard profession matrix. A
station-91001 fixture proved Shipwright, all three pilot affiliations, four
Force-sensitive families, five Force disciplines, both FRS ranks, Jedi title,
four light/dark Journeyman/Master families, and Padawan with exact root/novice
ownership and cleanup. The production x64 Skills mediator rendered the native
four-by-four, one-by-four, and pyramid templates while preserving the ordinary
33-row All Professions catalog. The marker survived both a client relog and a
game-server restart, and the final server remained healthy. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14NonstandardProfessionMatrixClosure.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 241 restores the authoritative Publish 14.1 `sampleDNA` command
registration that Bio Engineer novice already grants and reconnects it to the
retained `cmdHarvestDNA`/`bio_engineer` lifecycle. An authenticated
protocol-155 proof dispatched the real client command against a disposable
worrt, entered the production handler once, spent exactly 100 Action and 250
Mind, created a DNA component, persisted 92 DNA-harvesting XP, preserved the
creature, and restored every fixture-owned mutation. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14SampleDnaCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 242 restores `tame` as a complete Creature Handler lifecycle rather
than an inert command row. The production path owns an exclusive 30-second,
three-utterance transaction; revalidates range, skill, chance, capacity,
control level, and datapad at commit; and converts a successful wild baby into
a persistent growth-stage-one pet with a durable PCD, callable links, default
commands, saved pet state, follow behavior, and level-times-20 Creature Handler
XP. A lifecycle-owned task receiver holds the wild target with nonpersistent
one-second `stop` heartbeats between the three phase callbacks; STOP behavior
is never written as a persistent default, so process loss cannot strand a wild
target. The split runtime runner proves authenticated protocol-155 dispatch
and storage before a real restart, then PCD persistence, login-rearmed
owner-context recall, exact cleanup, and idempotent cleanup after relogin.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14TameCommandLifecycle.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 243 restores `emboldenpets`, already owned by Creature Handler
Healing II, as a complete active-pet transaction. The retained
`ai.pet_master` receiver now validates a living owned creature pet within 50
meters, charges the Focus-adjusted base-100 Mind cost only after a successful
buff, enhances all three primary pools by 15 percent for 60 seconds, and
stores a 300-second cooldown on that pet. The identity-bound fixture creates
its pet through the real tame/PCD lifecycle, while the authenticated runtime
runner dispatches the nonqueued command through the real client, proves the
resource and pool deltas, and exactly restores every fixture-owned mutation.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14EmboldenPetsCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 244 restores `healMind`, owned by Combat Medic Healing Range Speed
IV, as an actor-routed treatment transaction. The production handler validates
a living PvP-helpable player or creature-pet target within five meters and
line of sight, enforces the 250 current-Mind threshold without directly
charging it, and scales the 800-plus-random treatment by Combat Medic
effectiveness and battle fatigue. Five percent of the amount healed becomes
Mind, Focus, and Willpower wounds plus equal battle fatigue on the healer. The
authenticated protocol-155 proof isolates the exact command delta from normal
pet regeneration, proves real-client nonqueued dispatch, and restores the pet,
PCD, skills, pools, wounds, and battle fatigue idempotently. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14HealMindCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 245 restores `berserk1`, granted by Brawler novice, as a complete
HAM-to-state transaction. The persistent player receiver requires a melee or
unarmed weapon, applies the pinned random-plus-berserk threshold, calculates
the Strength/Quickness/Focus-adjusted 100/100/50 costs, drains all three pools,
and enters `STATE_BERSERK` for 20 seconds. An absolute durable expiry is
generation-checked by the callback and rearmed on login, preventing both
process-loss leakage and stale-timer clears. The authenticated protocol-156
proof dispatches the real nonqueued client command, proves exact adjusted
handler-local costs from the character's snapshotted governing attributes,
observes natural expiration,
and restores the six current/max attributes, skills, points, state, and expiry
idempotently. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14BerserkOneCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 246 restores `berserk2`, granted by Brawler master with
`berserk=20`, on the durable state path proven by `berserk1`. The persistent
player receiver preserves the same melee/unarmed, adjusted 100/100/50 HAM,
strict-pool, and random-plus-modifier policies while extending the state to
40 seconds. Its identity-bound fixture grants the complete Brawler tree,
proves the master modifier with deterministic roll 5 and total chance 25,
then restores the full chain, skill points, six current/max attributes, state,
and expiry idempotently. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14BerserkTwoCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 247 restores `formup`, granted by Squad Leader Defense I, as a real
group support transaction. The persistent player receiver requires group
leadership, scales base cost 50 by group size, derives Health/Action/Mind
costs from the leader's live Strength/Quickness/Focus values, and applies the
strict-pool rule before clearing dizzy and stunned from eligible player group
members. Two separately rooted protocol-159 clients prove target, invite,
join, the production nonqueued command, disband, guarded crash recovery, and
exact idempotent cleanup without touching the user's client process. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14FormupCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 248 restores `retreat`, granted by Squad Leader Support III, from the
exact Publish-era client command row and pinned Core3 behavior. A real group
leader pays the Quickness/Focus-adjusted, group-size-scaled Action/Mind cost;
each eligible non-leader player receives a composable 1.822 movement and
acceleration multiplier for 30 seconds, a matching cooldown, PvP-help
accounting, and natural expiry. The identity-bound two-client fixture proves
activation, leader exclusion, natural speed/acceleration restoration, real
group dissolution, reversible state restoration, and idempotent cleanup.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14RetreatCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 249 restores `boostmorale`, granted by Squad Leader Defense IV,
from the exact Publish-era client command row and pinned Core3 behavior. A
real group leader pays the group-size-scaled, Strength/Quickness/Focus-adjusted
Health/Action/Mind cost. The handler clears all nine wound attributes from
eligible player members, then redistributes the exact conserved total using
ceiling per-member and per-attribute slices. The identity-bound protocol-161
two-client fixture proves a 91-wound transaction, exact 46/110/129 HAM drain,
real group formation and dissolution, reversible restoration, and idempotent
cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14BoostMoraleCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 250 restores `steadyaim`, granted by Squad Leader Offense I. A real
group leader pays group-size-scaled, adjusted Health/Action/Mind costs before
eligible ranged player members receive `private_aim` equal to five plus the
leader modifier for 300 seconds. Protocol 162 proves two reversible CDEF
rifles, exact 46/110/129 HAM, both +5 effects, grouping, disband, and
idempotent cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14SteadyAimCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 251 restores Combat Medic `applyPoison` and `applyDisease` as the
shared DOT-pack lifecycle defined by pinned Core3. The actor-routed handler
validates organic attackable targets, PvP and line of sight, exact skill
ownership, carried medicine type, range, Focus-adjusted base-150 Mind cost,
and independent recovery. It then delegates to the retained single/area DOT,
resistance, combat, XP, and charge-consumption path. Protocol 164 proved one
production handler entry per command, exact 140-Mind and one-charge costs,
both strength-108 effects, normalized database cleanup at zero markers, and
idempotent restoration. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ApplyDotCommands.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 252 restores Ranger `areatrack` from its exact installed Publish 14
row and the pinned three-part Core3 lifecycle. Ranger novice opens the real
Animal/NPC/Player option SUI with harvest-tier gating. The selected scan waits
six seconds, rejects movement beyond one meter or combat, filters visible
creatures within 512 meters, and exposes harvest-tier direction and distance
in the production results SUI. Protocol 165 proved the exact option page and
ordinary selection/OK callbacks, a target 10 meters east, delayed result
completion, zero normalized fixture markers, native SUI cleanup, and
idempotent restoration. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14AreaTrackCommand.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 253 restores the complete Commando flame-thrower command family:
`flameSingle1`, `flameSingle2`, `flameCone1`, and `flameCone2`. The exact
pinned Core3 damage, timing, HAM multipliers, cone geometry, RANDOM pool,
generated animation, combat-spam, and 100-by-60-second fire DOT definitions
run through the retained production combat engine. Protocol 174 proved all
four commands with the canonical runtime weapon type 13, successful queue
removal, generated medium animations, real three-pool drains, live DOT pulses,
and reversible idempotent two-client cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3FlameDotFamily.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 254 restores Marksman `healthShot1` and `mindShot1` from the pinned
Core3 definitions and their exact installed Publish-era rows. The combat-data
bridge now carries an explicit DOT attribute, and retained DOT pulses route
through the same primary HAM pool as the direct hit. Protocol 175 proved the
PISTOL and RIFLE gates, exact adjusted three-pool costs, `sapshot` and
`distractshot` spam, generated ranged animations, successful queue removal,
and isolated Health-then-Mind bleeding pulses with reversible idempotent
two-client cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3PoolSpecificBleedingShots.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 255 restores Marksman `actionShot1` from the pinned Core3 definition
and its exact installed Publish-era row. The table-driven command requires a
carbine, routes direct damage and its retained bleeding pulse to Action, and
applies the historical 100-percent posture-down state check after a successful
hit. The resolver preserves immunity, posture-defense, level, and 30-second
recovery behavior; an immediate repeat during recovery stands a non-upright
target back up. Protocol 176 proved the CDEF carbine gate, exact adjusted
three-pool costs, `sapshot` spam, generated ranged animation, isolated Action
damage and bleeding, posture application, recovery, and reversible idempotent
two-client cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3ActionShotPostureDown.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 256 restores Carbineer `actionShot2` from the pinned Core3
definition and its exact installed Publish-era command row. It reuses the
proven posture-down resolver while adding the historical 15-degree cone,
2.0 damage and speed multipliers, `fire_5_special_single` generated ranged
animation, and `sapblast` combat spam. Protocol 177 proved a concrete CDEF
carbine, exact adjusted costs, successful queue removal, isolated Action
damage and bleeding, posture application, recovery, and reversible idempotent
two-client cleanup. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14Core3ActionShotTwoCone.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 264 makes the existing 20-second `berserk1` and 40-second `berserk2`
state lifecycle visible in the client status panel. A dedicated, effect-free
`command.berserk` row deliberately avoids the retained later-era 25/50-percent
melee damage bonuses. Application precedes the HAM debit, failure rolls the
icon back, expiry removes it, and relog restores only the remaining interval.
Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14BerserkStatusReplication.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

Milestone 265 validates the complete retained status catalog consumed by the
x64 DX11 client: all 1,845 unique visible rows resolve through 500 authored
style paths with valid polarity and stack metadata, every user-facing effect
is describable, and duplicate names are client-compatible. A balanced parser
classifies all 607 direct server applications, expands concatenated families,
and rejects resolved names outside the table; two orphan NGE recourse handlers
were retired. The protocol-255 live gate reports zero authored or unresolved
icon misses and covers positive, debuff, stacked, refreshed, cleared, and real
server-expired panel lifecycles. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14StatusCatalogIntegrity.ps1 -SourceRoot <materialized-staging-directory> -Expectation Ready

The PRE-CU equipment certification overlay retires NGE combat-level equip
requirements and their weapon/armor attribute labels. Legacy CL1 starter
weapons are certified by default; all other uncertified weapons may still be
equipped but suffer a 50-point miss-chance penalty. Weapon minimum/maximum
damage, speed, and elemental damage remain unchanged. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14PrecuEquipmentCertification.ps1 -SourceRoot <materialized-staging-directory>

Milestone 266 makes the pinned Core3 Publish 14 weapon-speed catalog
authoritative for every player and creature attack. The generated table has
342 exact weapon templates plus 13 PRE-CU family fallbacks for retained
expansion weapons. New and loaded NGE-speed objects migrate without replacing
plausible crafted variation; a combat-facing fallback also covers default or
lazy objects that miss the persistence callback. Primary attacks, restored
specials, and retained expansion ATTACK/DELAY_ATTACK rows now share the Core3
weapon-speed, skill-modifier, multiplier, haste, and one-second-floor cadence.
The same deployment closes the remaining creature-harvest bypass by requiring
Novice Scout across direct, radial, command, droid-target, and droid-auto
harvest paths. Validate:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14AuthoritativeWeaponSpeeds.ps1 -SourceRoot <materialized-staging-directory>
    powershell -NoProfile -ExecutionPolicy Bypass -File .\restoration\scripts\Test-P14ScoutHarvesting.ps1 -SourceRoot <materialized-staging-directory>
