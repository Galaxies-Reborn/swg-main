# dsrc overlays

Store ordered, component-relative Git patches here. Use numeric names such as
001-phase-a-skill-training.patch. The materializer applies files by name to an
isolated clone pinned by restoration/manifest.json.

Phase A is registered as `001-phase-a-training-and-surrender.patch`. It owns
the table-derived trainer/skill-point path, the authentic surrenderSkill
command row, and removal of the unresolved rifle-01 command grant.

`002-phase-a-runtime-probe.patch` adds a fixture-bound ServerConsole-only Java probe
for repeatable live purchase, surrender, skill-point, XP-cap, credit, command,
skill-mod, and draft-schematic assertions. Its fixed `craftingStatus` action
observes the complete novice-plus-Engineering I vector: both commands, all six
summed modifiers, and all 35 concrete schematics dynamically resolved from the
five authoritative groups. Queue acceptance is reported only as
`verification=pending`; use `verifySurrender` to observe the later authoritative
removed state. The probe has no attached-object or player-facing entry point
and enqueues surrender through the production command table. All actions are
restricted to disposable test station `91001`; invoke its uniquely named
`executeProbe` handler through CentralServer `runScript`.

The same probe now has a bounded trainer-payment canary. It discovers or
validates every nearby candidate until a loaded, authoritative production
skillteacher passes the complete contract, confirms that Engineering I
is offered and qualified, enforces the table's 1,000-credit and 500-XP costs
with no persuasion discount, then uses `money.requestPayment` and the trainer's
real `attemptedPayment` callback. It explicitly emits `conversationUi=false`;
this proves the stock payment/callback/purchase lifecycle without pretending a
client dialogue response was clicked. Exact-cost administrative funding/drain
and +/-500 crafting-XP setup actions exist only for the station fixture and are
paired by the fail-safe persistence runner.
The wider read-only `inspectTrainer` action reports the nearest loaded
production Artisan trainer's scene, cell, coordinates, distance, qualification,
and validation blocker without moving either object.

For the separate visible-dialogue gate, `queueTrainerConversation` queues the
production `npcConversationStart` command against that same validated trainer.
It reports only `conversationUi=pending purchaseMutation=false`; a connected
client must visibly confirm the dialogue mediator.

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
is recorded before lifecycle establishment and each grant so a lost begin
response cannot bypass cleanup. The post-cleanup status read owns the outcome:
it safely retries only the exact attempted partial/complete marker and requires
`none` with no attempt ID, committed ID, or baseline residue;
`finally` re-queries authoritative ownership, confirms Engineering I is absent
before revoking a temporary prerequisite novice, and never blindly revokes an
originally-owned novice when output is missing or malformed.

`restoration/scripts/Invoke-PhaseATrainerPersistence.ps1` is observation-only
by default. Explicit Prepare/Conversation/Purchase/VerifyBoundary/Surrender
phases preserve a strict, atomically replaced external JSON snapshot. The
mutating modes acquire one container/player lock plus the snapshot's sibling
lock before their first server read and hold both for the full invocation.
The snapshot is schema v8, layered over the unchanged v6.4/protocol-64 server
contract. Lifecycle establishment writes a durable 32-hex
attempt ID first, records and verifies seven baseline fields, publishes and
verifies `established`, and makes the active lifecycle ID the single final
write. No mutation follows that commit write. Every mutation and asynchronous
callback requires the exact complete record. Operation reservation mirrors
that protocol with an ID-first `reserving` record containing
lifecycle/trainer/skill/cost and full preimage, then publishes `reserved`. Its
25 sequential writes are a normative, gap-free prefix: the Java rollback and
clear paths both recompute every present value and presence implication
immediately before deleting the root. An attempt-only marker is clearable only
from its exact external checkpoint with no residual operation leaf, nonce, or
gameplay drift; exact pre-dispatch partial/reserved records retain the same
strict rule, and a failed hidden-prefix proof preserves the marker for
investigation. Every complete or terminal marker must also contain a strictly
positive durable `operation.updated` value before synchronization, callback
acceptance, or destructive clear. The gap-free `reserving` prefix remains valid
without `updated` only before that ordered write and only while every later leaf
is absent.
Dispatch state is sampled rather than synthesized. Tagged payment request,
pay-pass, pay-fail, and trainer callbacks advance through one-shot durable
states before any tally, message, money, or purchase side effect, while tagged
covert deposit is quarantined as impossible for the bank-only canary. Each
trainer callback requires exact `attemptedPayment` handler/pay-handler names
and explicit code `0` or `1`; only the native pre-callback envelope may omit the
code, and then only while stock `getReturnCode` is exactly `-1`. Each
stage requires complete operation/lifecycle/preimage identity and exact
bank-first cash, bank, and total-credit relations. The v6.4 protocol requires
`player_money` and the trainer callback to prove the same full
lifecycle-relative preimage and binds tagged player and trainer plus
amount/total/skill/cost/lifecycle before any side effect. PRE, DEBIT, HELD, and
REFUND are explicit authoritative vectors, including two commands, six skill
mods, five dynamically enumerated schematic groups, and exactly 35 unique
schematics. Purchase success starts from exact DEBIT and reaches HELD, but it
terminalizes only after the player-owned named-account callback durably records
`SUCCESS`; failed payment requires exact PRE. After a proved process transition,
`purchaseApplying` plus HELD resumes accounting rather than inferring success.
Pending accounting is replayable only from `accountingRequested`; an in-flight
transfer remains ambiguous unless its durable callback outcome is `SUCCESS`.
Failure outcomes written before their terminal state are retained as exact
request/dispatch/pending crash cuts and are always fail-closed and non-clearable.
DEBIT/no-grant at
`paymentDispatching`, `paymentSucceededCallback`, or `purchaseApplying`
reconstructs only the exact trainer `attemptedPayment` callback and never
replays the debit path. Same-process inference, `paymentDispatching` plus PRE,
and partial grants remain fail-closed. Refund attempts carry generation 1 or 2
and deterministic operation-scoped keys. REFUND terminalizes without transfer;
DEBIT may advance from initial failure to recovery exactly once, and only a
`Claiming` cut can safely resume dispatch. Dispatching, pending, failed, stale,
and consumed recovery DEBIT states other than that exact generation-1 gateway
are quarantined against duplicate credit.
The schema-v8 runner evaluates recoverable settled refund failures before the
generic terminal path. It clone-normalizes and JSON-roundtrip-validates every
authoritative operation checkpoint, including the seven protocol provenance
leaves and exact immutable trainer/skill/cost identity. Recovery intent is saved
before its RPC; success, timeout, and exception paths all attempt a fresh live
read and save any correlated reachable state before returning or rethrowing the
original error. Historical recovery source/process evidence survives the exact
allowed advanced-state matrix while stale action targets are cleared. Confirmed
purchase evidence is durably saved before `clearOperation`, so response loss
after server marker deletion remains replayable from the external snapshot.
Partial `reserving` recovery admits only the server write order's absent or
neutral refund/accounting leaves, an incomplete marker, no boundary nonce, and
an unchanged preimage; a missing attempt ID requires zero operation residue.
The conversation trainer is reused for purchase. Unique persisted operation IDs
and player/trainer callbacks make funding, draining, purchasing, and refunds
terminal before a quiet settlement interval can pass. Relog proof requires an
unchanged authoritative Tatooine `SwgGameServer` process-lifetime token plus a
vanished volatile nonce; ordered restart proof requires a changed token plus
its separately armed nonce disappearing. The runner derives the token from
Linux boot ID, PID, and process start ticks, so a Java script reload cannot
impersonate a restart.
Surrender is unavailable until both boundaries pass and must restore every
named command/mod/schematic identity without returning credits or XP. Cleanup
refuses pending or uncorrelated operations and restores the original fixture
after removing only the prerequisite it administratively added. It persists a
`releasePending` checkpoint before lifecycle release, supports residue-free
lost-response replay, and makes terminal Cleanup an immutable no-op. A lost
terminal-clear response is accepted only with zero operation instrumentation,
exact gameplay, and exact lifecycle/purchase-evidence lineage; marker-present
validation remains strict over all persistent fields. The v7 snapshot retains
immutable purchase evidence and explicit recovered-held,
surrender-intent, surrendered, baseline-cleanup, and release stages so a
response loss or process crash cannot erase purchase/surrender lineage. The
materializer injects one composite SHA-256 into the runtime probe, both callback
classes, and staged contract; the runner contract-locks that value and its own
file hash.

`002b-phase-a-attached-bank-dispatch.patch` routes administrative lifecycle
fund/drain requests onto the fixture's attached `player_money` script before
calling native named-account APIs. Those APIs require an object owner context;
an unattached ServerConsole probe cannot dispatch them directly.

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

`006-p14-mos-eisley-artisan-trainer.patch` restores the production Artisan
skill trainer removed from Mos Eisley's outdoor population. A durable
`systems.spawning.spawner_area` buildout object creates exactly one stationary
`trainer_artisan` at the Publish 14.1/Core3 position `(3503, 5, -4809)`. This
matches the established trainer-spawner pattern already used by the Mos Eisley
buildout and keeps the stock `npc.skillteacher.skillteacher` behavior owned by
the mobile definition. The adjacent later profession quest-giver remains a
separate NPC and is not used as a substitute for the trainer lifecycle.

`008-precu-three-pool-combat-runtime.patch` installs the script-side half of
the generic M3 combat seam. A separate override table opts individual commands
into Core3-derived Health/Action/Mind costs and explicit target-pool routing;
all existing commands retain their legacy drain and Health-damage defaults.
The initial weapon-cost table pins only the authenticated CDEF rifle fixture.

`009-precu-nine-attribute-runtime.patch` restores the nine attribute constants
and three-value HAM groups, reopens object-template TDF versions 9 through 11
to the Publish 14 enum, fills the player/creature/NPC base templates plus
direct vehicular roots, and replaces the temporary neutral combat-cost
governors with authoritative Strength, Quickness, and Focus reads. It also
retires NGE combat-level stat grants and pool recalculation so attach,
initialize, respec, and level-change paths cannot overwrite Publish 14 HAM;
the retained compatibility recalculation may only heal pools to their
existing authoritative maxima.

`010-p14-stat-migration-tables.patch` replaces the temporary nine-attribute
creation stubs with the decoded Publish 14.1 racial limits, racial modifiers,
and starting-profession allocations. The corresponding retail IFF hashes and
semantic canaries are locked by `contracts/p14-stat-migration.json`.

`011-p14-image-designer-live-fixture.patch` adds a ServerConsole-only,
identity-bound two-client location fixture for the Image Designer live gate. It
stores persistent original-location snapshots for both disposable characters,
moves them into the authentic Tatooine salon cell, and restores only its owned
state during cleanup. Skill grants, grouping, session start, acceptance, and
commit remain on their production gameplay paths.

`012-p14-stat-migration-image-designer-xp.patch` fixes the pure stat-migration
reward boundary. A `DT_STAT_MIGRATION` transaction now reaches the authentic
2,000 Image Designer XP branch even when no cosmetic hair, morph, index, or
holo-emote field changed. The reward is granted directly to the dedicated
`imagedesigner` pool because SWGSource's NGE social-style helper ignores that
pool and redirects rewards through the active expertise template.

`013-p14-stat-migration-persistence-fixture.patch` adds a read-only,
identity-bound ServerConsole probe for the recipient's durable migration
record. It reports the state marker, nine targets, and sum but exposes no
mutation action; production client commands remain the only writers.

`014-p14-headshot1-vertical-slice.patch` activates the first authenticated
Publish 14.1 combat command. Marksman Rifle I grants the queued `headShot1`
entry, its thin script wrapper uses the production standard-combat path, combat
data restricts it to rifles and applies 1.5x weapon damage, and the explicit
override selects 0.5/0.5/1.0 three-pool costs plus Mind target damage.

`015-p14-headshot1-live-fixture.patch` adds the ServerConsole-only, fixed-identity
two-player preparation used to prove that slice live. It reversibly owns the
temporary skill grants, positions, personal-enemy flags, and current HAM values,
while the connected P14 client remains the only component allowed to queue the
actual command.

`016-p14-precu-command-duration-data.patch` replaces fixed execute timing for
opted-in Pre-CU attacks with the pinned Core3 weapon-speed, profession-speed,
and combat-haste equation while leaving non-opted NGE commands unchanged.

`017-p14-precu-primary-accuracy.patch` installs the fail-closed Core3 primary
hit equation for authenticated weapon profiles and keeps it isolated from the
NGE defender-result table.

`018-p14-precu-secondary-defense.patch` adds exact profile-driven block, dodge,
and counter outcomes for the authenticated CDEF rifle and player-unarmed seam.

`019-p14-precu-lightsaber-ricochet.patch` restores profile-driven lightsaber
ricochet for ranged attacks without invoking NGE parry, proc, or reflect logic.

`020-p14-marksman-tier1-activation.patch` activates authentic Publish 14.1
Marksman Rifle I, Pistol I, and Carbine I rows and adds `bodyShot1` plus
`legShot1` across command, combat, skill, override, CDEF HAM-cost, weapon-profile,
and standard combat-dispatch data.
