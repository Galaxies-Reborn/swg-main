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

`021-p14-marksman-tier1-live-fixture.patch` adds the identity-bound reversible
live layer for Pistol I, Carbine I, and their CDEF weapons. It requires the same
lifecycle from `precu_headshot1_fixture`, which continues to own location, PvP,
combat-state, and HAM restoration. The tier-I layer can arm success and strict
no-partial boundaries, but it cannot equip a weapon, queue a command, or
fabricate damage.

`022-p14-live-combat-diagnostics.patch` adds an opt-in, fixture-scoped record of
the production Pre-CU primary-accuracy components and random result plus the
secondary block, dodge, or counter profile, operands, rolls, and result. The
Marksman tier-I fixture clears that record on every arm and owns dedicated CDEF
rifle, pistol, and carbine weapons for the bound defender. Normal players do not
enable the diagnostic objvar, and the fixture still never equips, queues, rolls,
or fabricates a combat result.

`023-p14-command-duration-control.patch` restores the authentic Publish 14.1
`headShot2` command row, rifle combat-data row, and standard combat wrapper as
the shared duration seam's non-opted control. It deliberately has no
`precu_combat_overrides` row, so its fixed 1.5-second command-table execute time
proves that commands not yet migrated to the Core3 weapon-speed model continue
to fail closed.

`024-p14-primary-accuracy-live-fixture.patch` extends only the identity-bound
Marksman diagnostic fixture with reversible ideal-range, near-maximum, and
non-opted fallback placements. Status includes the inherited global
combat-range gate plus the equipped weapon and action ranges. Its fixed
wilderness anchor uses terrain-derived elevations on a verified clear
positive-z sight line, avoiding city geometry and terrain occlusion in the
near-maximum control. It resets telemetry and combat state but never equips or
queues a command; the connected Publish 14.1 client remains the sole
command-execution owner, and the underlying headShot1 lifecycle restores both
players' original locations and state.

`025-p14-primary-command-range.patch` gives `headShot1` an explicit 64-meter
client command range, matching its restored combat-data row. This prevents the
inherited NGE CDEF object range from canceling a valid Pre-CU command before
the authoritative server action runs.

`026-p14-secondary-defense-live-fixture.patch` extends the identity-bound
Marksman fixture with reversible block, dodge, counter, lightsaber-ricochet,
and missing-profile fallback controls. It creates exact defender weapons and
uses additive, snapshot-backed defense modifiers to make the authentic Core3
inequalities certain without replacing random rolls or outcomes. The connected
client remains the only command owner. Combat telemetry records exact block
scaling, counter dispatch, and whether the isolated ricochet ever entered the
NGE parry or reflect branches. A server-only ricochet adapter is a real
`WeaponObject` with the canonical `isLightsaber=1` marker, while inheriting the
DL44 weapon type and shared arrangement that are stable across the Publish 14
client and NGE server template sets. `jedi.isLightsaber(obj_id)` recognizes that
canonical marker, and passive defense reads the held weapon instead of the NGE
current-weapon combat cache. Live acceptance proved block, dodge, counter,
ricochet, missing-profile NGE fallback, and complete fixture cleanup.

`027-p14-core3-wounds.patch` activates the pinned Core3 post-damage wound roll
for exact authenticated CDEF rifle, pistol, carbine, and player-unarmed
profiles. A surviving positive-damage hit wounds the selected primary and its
two linked secondary attributes by one and attempts three shock wounds. Legacy
medicine helpers use the same native add/heal seam. The Marksman fixture
snapshots all nine defender wounds plus shock, exposes production telemetry,
and restores only the positive wound delta owned by its lifecycle. The NGE
combat-exit hook no longer erases shock wounds when combat ends, preserving
the persistent battle-fatigue input expected by the retained medicine path.
The NGE player-initialization hook likewise no longer zeros battle fatigue
after the creature is reconstructed from its persisted database row.

`028-p14-battle-fatigue-fixture.patch` adds an identity-bound, reversible
ServerConsole fixture for the retained patient-side medical multiplier. It
controls only the bound patient's shock wounds and reports the production
`healing.applyShockWoundModifier` result at 250, 251, 500, and 1000. It does
not consume medicine, fabricate healing, or introduce a combat-accuracy
modifier.

`029-p14-medicine-consumption.patch` carries that multiplier through actual
inventory medicine. It removes the retained Health-only final application
gate so every already-validated attribute modifier reaches the shared
`utils.addAttribMod` path. Its identity-bound fixture creates authentic Health,
Strength, Constitution, Action, Quickness, and Stamina wound packs with two
charges, consumes each through the production ownership, skill,
patient-fatigue, stomach, modifier, and charge path, and destroys its
disposable patient and remaining medicine during cleanup. The Mind trio
remains an entertainer-healing boundary rather than a fabricated medical pack.

`030-p14-heal-wound-command.patch` restores the authentic Publish 14.1
`healWound` command row and Medic novice command grant, then routes the queued
command through a thin `player.cmd.heal_wound` adapter into the retained
production medicine path. The pinned Core3 equations provide a base 50 Mind
cost adjusted by Focus, a minimum-three-second wound-treatment round time, and
2.5 medical XP per wound healed. Combat, patient, six-meter range,
line-of-sight, PvP-help, facility/droid/camp, medicine, wound, and cooldown
checks remain authoritative. Its opt-in, identity-bound fixture never queues a
command; the connected client owns both live queue entries. Acceptance proved
one successful wound treatment, exact Mind and charge costs, exact asynchronous
medical XP, the retained seven-second queue entry, a second cooldown rejection
without partial mutation, and complete cleanup.

`031-p14-heal-damage-command.patch` restores the authentic five-second
`healDamage` combat-queue entry and routes it through
`player.cmd.heal_damage`. The retained stim backend now uses the pinned Core3
50-Mind Focus adjustment, real injury-treatment cooldown with a four-second
floor, seven-meter normal-stim command range, and actual Health, Action, and
Mind deltas. Medical XP is immediate and limited to 25 percent of Health plus
Action restored to another player; self and pet treatment award none. Its
identity-bound fixture creates a disposable three-pool patient and two-charge
stim while the connected client remains the sole queue owner. Live protocol-16
acceptance proved 214 points restored to each HAM pool, exact 45 Mind and one
charge costs, no pet medical XP, a five-second second-handler entry rejected
by the retained 19-second cooldown, and complete fixture cleanup.

`032-p14-tending-commands.patch` restores the authentic five-second
`tendDamage` and `tendWound` combat-queue entries. Their adapters use the
pinned Core3 organic tending contract rather than the unrelated retained
medikit helpers: six-meter patient checks, no medicine consumption,
Focus-adjusted 200/400 Mind costs, five Focus and Willpower wounds, and
patient battle-fatigue scaling. Damage tending restores Health and Action
without XP. Wound tending chooses the first wounded Health-through-Stamina
attribute by default, excludes the Mind trio, and grants 2.5 medical XP per
wound to another target. The identity-bound tending fixture owns reversible
healer state and handler telemetry only. It composes with the already accepted
single-purpose healDamage and healWound disposable-patient fixtures while the
connected protocol-17 client remains the sole queue owner. Active lifecycle
mismatches fail closed; inactive packed objvar leaves are deterministically
re-keyed, re-snapshotted, and reset on the next preparation.

`033-p14-diagnose-command.patch` restores the authentic five-second,
nonqueued `diagnose` row and its `player.cmd.diagnose` adapter. The handler
uses the pinned Core3 six-meter organic-target/PvP contract and displays the
original ten-line wound and Battle Fatigue medical listbox. The reversible
identity-bound fixture records SUI telemetry only after a real protocol-18
client admission, snapshots every patient current value and wound plus Battle
Fatigue, and restores skill and command ownership. SUI dismissal remains
client-owned because ServerConsole handlers have no script owner context.

`034-p14-medical-forage-command.patch` restores the authentic targetless,
nonqueued `medicalForage` row and implements its pinned Core3 manager behavior
inside the retained player utility. It applies the Quickness-adjusted 50-Action
cost, outdoor and mount gates, 8.5-second stationary delay, combat-at-finish
gate, per-player 10-meter/three-use/30-minute area history, the
`medical_foraging` chance formula, and the original five reward bands. The
protocol-19 identity-bound fixture forces one ordinary biologic-component
result through production creation and randomization, then destroys that exact
reward and restores the player's Action, location, skill, command, and runtime
state.

`035-p14-medic-tier1-progression.patch` restores the visible Publish 14.1
Medic profession root and all four first-tier boxes. It carries the exact
medical and medicine-crafting XP costs, two-point box costs, private commands,
healing and crafting modifiers, and retail novice/tier-I schematic groups.
Its identity-bound fixture invokes the production validation, grant, and XP
deduction operations while omitting only the owner-context-dependent holocron
notification that ServerConsole cannot emit. Live protocol-19 acceptance
proved all four boxes, five commands, six schematics, exact modifier deltas,
227 remaining skill points, and reversible idempotent cleanup.

`036-p14-first-aid-command.patch` restores the authentic optional-target,
nonqueued `firstAid` row and a thin `player.cmd.first_aid` adapter. Invalid
targets fall back to self; other patients must be living organic players or
pets within six meters, visible, and legal to help. The production path
removes bleeding strength equal to three times injury treatment while
consuming no medicine or Mind and granting no medical XP. Its identity-bound
fixture seeds only a private DOT in the retained library's script-variable
format, while the protocol-20 client owns the real command admission and the
production handler owns reduction, effects, and feedback. Live acceptance
proved a 105-point request removed the full 90-point bleed with exact
Health/Mind/XP preservation and idempotent cleanup.

`037-p14-drag-incapacitated-player.patch` restores the authentic optional-
target, nonqueued, two-second `dragIncapacitatedPlayer` row and a narrow
`player.cmd.drag_incap_player` adapter. The production path follows the pinned
Core3 command rather than the incompatible NGE corpse helper: Medic injury-
speed tier II, legal PvP help, line of sight, outdoor-only placement, an
incapacitated or dying player, and group membership or patient consent are all
required. Range is `10 + healing_ability * 0.2` meters and each successful
command uses raw world-position distance and pulls the patient at most five
meters toward the medic, clamps the destination to terrain, faces the patient
toward the medic, emits the original drag effect and fly text, and records
help/TEF. Its two-player fixture owns only reversible skill, command,
healing-ability, incapacitation-resistance, Health-regeneration, location,
posture, locomotion, and HAM preimages; the protocol-21 clients remain the sole
group and command owners. Live acceptance proved one nonqueued group-authorized
handler call, 900-to-400-centimeter separation, exact 500-centimeter movement,
zero HAM/medical-XP mutation, real group disband, and idempotent cleanup.

`038-p14-medic-tier2-progression.patch` activates all four authentic
Publish 14.1 Medic tier-II boxes as one coherent progression slice. It
restores the exact three-point and XP costs, prerequisites, private and
gameplay commands, healing/crafting modifiers, and searchable four-by-four
rows. It also corrects the retained group-B labels to their retail contents:
duration-release and solid-shell components plus `med_stimpack_b`. Its
identity-bound fixture grants novice and tier I only as reversible
prerequisites, snapshots that modifier baseline, then exercises production
validation, grant, and XP deduction for each tier-II purchase.

`039-p14-medic-tier3-progression.patch` activates the complete third Medic
row. It restores exact four-point and XP costs, private commands, passive
healing/crafting modifiers, and the six retail wound-medpack schematics from
the decoded `patch_12_00.tre` group table. Its reversible fixture grants the
nine novice-through-tier-II prerequisites in dependency order, snapshots the
tier-II modifier baseline, and purchases all four tier-III boxes through
production validation and mutation.

`040-p14-quick-heal-command.patch` restores the Publish 14.1 Quick Heal command
row and a thin player-command adapter. It uses the pinned Core3 Focus cost
formula, heals Health and Action with one shared 150–750 roll, charges ten
Focus and Willpower wounds, consumes no medicine, and grants no XP. Its
identity-bound fixture creates a deterministic self-heal boundary, records
production telemetry, and restores the complete five-attribute preimage. The
fixture temporarily raises only Focus to the authentic Human Publish 14 maximum
of 1,100 because the retained test character was created with an NGE 400-point
Mind/Focus profile. That removable modifier leaves the charged Mind pool and
production cost formula untouched. Protocol-22 live execution charged exactly
333 Mind, applied ten wounds to both mental secondaries, granted zero XP, and
proved idempotent cleanup.

`041-p14-medic-tier4-progression.patch` activates all four authentic
Publish 14.1 Medic tier-IV boxes. It restores the exact five-point and XP
costs, private commands, healing/crafting modifiers, Quick Heal ownership, and
nine retail schematics: Stimpack C, four advanced medicine components, and
four secondary-stat wound medpacks. Its identity-bound fixture grants the
thirteen novice-through-tier-III prerequisites in dependency order, snapshots
that modifier baseline, and purchases all four tier-IV boxes through
production validation, grant, and XP deduction.

`042-p14-medic-master-progression.patch` restores the authentic Master Medic
capstone. It requires all four tier-IV boxes, costs six skill points, grants
the private master command, adds the exact injury-treatment, healing-ability,
and medical-foraging modifiers, and grants retail Stimpack D. Its reversible
fixture owns the full seventeen-skill prerequisite tree and purchases the
master box through production validation, grant, and XP deduction.

`043-p14-doctor-novice-progression.patch` restores the authentic Doctor root
and novice box. It replaces the NGE two-branch/125,000-XP shortcut with Master
Medic, 11,250 medical XP, six skill points, `healState`, registration, five
medical modifiers, and four retail state/poison schematics. The exact
Publish 14 command-table row is restored at this data boundary; its gameplay
handler is a separate vertical slice. The identity-bound fixture grants the
complete eighteen-skill Medic tree and purchases novice Doctor through
production validation, grant, and XP deduction.

`044-p14-heal-state-command.patch` completes that gameplay slice. It routes
the authentic optional-target, five-second queued `healState` row through a
narrow SWGSource adapter preserving the pinned Core3 six-meter organic-patient,
line-of-sight, PvP-help, state-medicine, Focus-adjusted 20-Mind, injury-speed
recovery, state-removal, charge, effect, and other-player-only 50-XP behavior.
The command recognizes stunned, dizzy, blinded, and intimidated in retail
priority order. Its identity-bound fixture owns the complete Medic-plus-novice-
Doctor skill chain and a two-charge dizzy pack while the protocol-23 client
remains the sole queue owner. Live self-treatment removed state 14, charged
exactly 18 Mind and one medicine charge, applied the expected five-second
recovery, granted zero self-treatment XP, drained the client queue, and
completed exact idempotent cleanup.

`045-p14-doctor-tier1-progression.patch` restores all four authentic Doctor
tier-I boxes as one progression boundary. Each box requires novice Doctor,
costs five skill points and 15,000 medical or medicine-crafting XP, and grants
only its Publish 14.1 passive modifiers; the retained NGE `bandage`,
`countertoxin`, `bactaInfusion_1`, `poisonInnoculation`, and
`endorphineInjection` grants are removed. Medicine Crafting I restores six
retail enhancement, state-treatment, and disease-cure schematics through the
three decoded group-A/group-B rows. Its identity-bound fixture owns the full
nineteen-skill prerequisite chain, purchases all four boxes through production
validation, grant, and XP deduction, and restores XP, skill points, commands,
schematics, modifiers, and every fixture-owned skill.

`046-p14-doctor-tier2-progression.patch` restores all four authentic Doctor
tier-II boxes and the exact 94-column `curePoison` and `healEnhance` client
admission rows. The branches require their matching tier-I boxes, cost four
skill points, and use 30,000 medical XP or 21,000 medicine-crafting XP.
Medicine Crafting II restores twelve retail wound-pack, poison-cure,
enhancement, and secondary-enhancement schematics from four decoded groups.
Nine retained NGE command grants and their unrelated defense/efficiency
modifiers are absent. The identity-bound fixture owns the complete
Medic-through-Doctor-tier-I prerequisite chain, purchases all four boxes
through production validation, grant, and XP deduction, and performs exact
and idempotent cleanup.

`047-p14-cure-poison-command.patch` completes the first Doctor tier-II gameplay
slice. It routes the authentic optional-target, five-second nonqueued
`curePoison` row through a narrow adapter while retaining the existing
medicine, DOT-strength, area-pack, charge, effect, and PvP-help mechanics. The
pinned Core3 behavior supplies the seven-meter organic-patient gate,
Focus-adjusted 100-Mind cost, shared condition-treatment recovery, and fixed
50 medical XP for another player only. Its identity-bound fixture owns one
private poison DOT, one two-charge antidote, and the complete
Medic-through-Doctor-Wound-Speed-II skill chain.

`048-p14-heal-enhance-command.patch` completes the second Doctor tier-II
gameplay slice. It routes the authentic optional-target, seven-second queued
`healEnhance` row through a narrow adapter while retaining SWGSource's
consumable certification, battle-fatigue scaling, modifier replacement,
charge, PvP-help, and presentation paths. The pinned Core3 behavior supplies
the seven-meter organic-patient, medical-location, combat, and line-of-sight
gates; Focus-adjusted 150-Mind cost; wound-speed recovery; automatic
enhancement-pack selection; and 2.5-times net-enhancement medical XP. Its
identity-bound fixture owns a disposable Bantha pet, a two-charge Health pack,
the complete Medic-through-Doctor-Wound-II skill chain, and exact cleanup of
the touched facility and player state. The patch preserves the positive
crafted modifier for Publish 14 buff medicine instead of sending it through
the NGE consumable calculation that produces a zero-value enhancement.

`049-p14-doctor-tier3-progression.patch` restores the complete third Doctor
row. Its four three-point boxes use the retail 45,000 medical or 27,000
medicine-crafting XP costs and caps, grant only the authentic healing and
medicine-crafting modifiers, and replace sixteen NGE combat-buff commands with
the single retail `extinguishFire` grant. Five decoded
`patch_12_00.tre` schematic groups resolve to thirteen exact medicine
schematics. The reversible fixture grants the complete
Medic-through-Doctor-II prerequisite vector and purchases every box through
production validation and mutation.

`050-p14-extinguish-fire-command.patch` completes the Doctor tier-III active
gameplay slice. It routes the authentic optional-target, five-second nonqueued
`extinguishFire` row through a narrow adapter while retaining SWGSource's fire
DOT, medicine, charge, effect, and PvP-help mechanics. The pinned Core3
behavior supplies the seven-meter organic-patient and line-of-sight gates,
Focus-adjusted 100-Mind cost, shared condition-treatment recovery,
wound-treatment blanket power, and fixed 50 medical XP for another player.
Its identity-bound fixture owns one private fire DOT, a two-charge fire
blanket, and the complete Medic-through-Doctor-Wound-Speed-III skill chain.

`051-p14-doctor-tier4-progression.patch` restores the complete fourth Doctor
row. Its four two-point boxes use the retail 60,000 medical or 33,000
medicine-crafting XP costs and caps, grant only the authentic healing and
medicine-crafting modifiers, and replace the accumulated NGE combat-buff
surface with `cureDisease` and `revivePlayer`. Both authentic 94-column
command-admission rows are restored. Five decoded `patch_12_00.tre`
schematic groups resolve to eighteen exact medicine schematics. The reversible
fixture grants the complete Medic-through-Doctor-III prerequisite vector and
purchases every box through production validation and mutation.

`052-p14-doctor-master-progression.patch` restores the authentic Master Doctor
capstone. The one-point, 10,000-credit title requires all four tier-IV branches,
grants `place_hospital`, applies only the four retail Doctor modifiers, and
removes six NGE combat-buff commands plus five unrelated NGE modifiers.
Four decoded `patch_12_00.tre` groups resolve to fourteen exact advanced
medicine schematics. The reversible fixture grants the complete thirty-five
skill Medic-through-Doctor-IV prerequisite vector and purchases the capstone
through production validation, grant, and XP deduction.

`053-p14-cure-disease-command.patch` completes the Doctor tier-IV Cure Disease
gameplay slice. It binds the authentic optional-target, five-second nonqueued
row to a narrow adapter while retaining SWGSource disease DOTs, antidote
selection and power, area packs, charge use, effects, and PvP-help mechanics.
The pinned Core3 behavior supplies the seven-meter organic-patient and
line-of-sight gates, Focus-adjusted 100-Mind cost, shared condition-treatment
recovery, and fixed 50 medical XP for another player. Its identity-bound
fixture owns one private disease DOT, a two-charge antidote, and the complete
Medic-through-Doctor-Wound-Speed-IV skill chain.

`054-p14-revive-player-command.patch` completes the Doctor tier-IV Revive
Player gameplay slice. It restores the original optional-target, ten-second
nonqueued hook and routes it through a narrow adapter. Pinned Core3 supplies
the dead-player and resuscitation-window gates, group-or-consent and PvP-help
admission, seven-meter range, Focus-adjusted 200-Mind cost, six-channel
healing, one-charge use, exact medical XP, upright recovery, and nine-attribute
grogginess. The patch also corrects the retained NGE medical attribute-name
helper so Publish 14 Willpower cleanup cannot index beyond its list. Its
identity-bound fixture owns a two-charge revive pack and restores the complete
medic and patient preimages after reversible two-player acceptance.

`055-p14-hospital-placement-certification.patch` adds a reversible acceptance
fixture around the retained Master Doctor hospital-ownership path. The
production structure library and all three Tatooine, Corellia, and Naboo
hospital rows already enforce the authentic city-rank-three,
`private_place_hospital=100`, and `place_hospital` certification contract.
The fixture proves negative admission, direct Master Doctor grant, positive
three-template admission, exact restoration, and idempotent cleanup without
changing production placement behavior.

`056-p14-armor-mitigation-ordering.patch` restores the pinned Core3 player
mitigation sequence only for authenticated pre-CU combat actions. It maps the
selected HAM pool to a physical hit location, applies PSG and hit-location
armor layers with explicit NONE/LIGHT/MEDIUM/HEAVY armor-piercing multipliers,
uses damage-type protection, applies 20 percent condition wear per layer, and
then consumes retained or migrated `mitigate_damage` food before the existing
HAM and wound paths. Exact CDEF rifle, pistol, carbine, and unarmed profiles
declare armor-piercing NONE; the untouched NGE aggregate-armor path remains the
fallback. Its reversible two-player fixture uses a real LIGHT bone helmet,
bypasses the NGE certification transfer callback only while equipping that
fixture-owned item, immediately restores its armor script, and certifies both a
deterministic 1000-point probe and a protocol-29 off-focus `headShot1`.

`057-p14-incapacitation-recovery-lifecycle.patch` replaces the retained NGE
second-incap `incapWeaken` death with the pinned Core3 rolling three-incap
threshold over 600 seconds. Recovery time is derived from the most-depleted
Health, Action, or Mind pool, stale delayed messages are generation-checked,
and every non-positive primary pool is raised to one so the native
recapacitation posture callback can complete. Every player-death path clears
the counter. Its ServerConsole-only station-91001 fixture drives real Health,
Action, and Mind transitions, proves the timer boundaries and automatic third
death, and restores the exact preimage without adding a client protocol.

`058-p14-death-blow-admission.patch` restores the pinned Core3 player
death-blow admission boundary while preserving both authentic Publish 14.1
`coupDeGrace` and `deathBlow` client rows. The client continues to advertise
and queue the three-second command at sixteen meters; the server owns the
inclusive five-meter execution range plus distinct-player, alive-incapacitated,
non-feigning, PvP-attackable, and line-of-sight gates. The immediate and
retained delayed handlers share the same admission method and then preserve
the existing `pclib.coupDeGrace` death path. Its protocol-30 acceptance fixture
layers six-meter rejection, feign rejection, and four-meter execution over the
exact reversible combat snapshot without directly invoking gameplay code.

`059-p14-clone-penalties.patch` replaces retained NGE clone sickness with the
pinned Core3 registered-versus-alternate facility penalty. Alternate
facilities add 100 Health, Action, and Mind wounds plus 100 battle fatigue.
PvE decay remains one percent for insured items and five percent for uninsured
items, consumes the insured flag, and excludes auto-insured items; player
death-blows retain the no-decay death-type split. Its reversible fixture owns
three controlled items and snapshots all pre-existing eligible item state.

`060-p14-clone-selection-compatibility.patch` completes real-client
acceptance without moving authority into the client. It stores only a
server-observed, vector-bounded row for the current clone SUI and uses it when
the legacy close payload omits `SelectedRow`. Clone warps mark completion
pending before transfer, while a persistent five-second call to the normal
completion handler covers same-scene transfers whose engine callback is lost.
The completion handler is idempotent, so callback races cannot duplicate
healing, wounds, item decay, or effects. Protocol-31 row-zero acceptance
proved the real prompt round-trip, OK callback, upright recovery, exact PvP
penalties, residue-free cleanup, and healthy isolated containers.

`061-p14-clone-decay-report.patch` restores the pinned Core3 Publish 14.1
decay report on the authoritative PvE item-decay path. The report contains
only items actually processed by clone decay, computes their condition after
the retained one/five-percent loss, and uses the authentic title, explanatory
copy, green header, row shape, and single OK button. It force-closes a stale
tracked page before replacement and reuses the existing residue-free
`handleDecayReport` callback. The clone fixture exposes the report lifecycle
without taking ownership of unrelated pages and proved protocol-31 render,
close, exact restoration, and idempotent cleanup.

`062-p14-entertainer-mind-healing.patch` restores the pinned Core3 performance
heartbeat for Mind, Focus, Willpower, and Battle Fatigue healing. It overlays
all six authentic fields for the 154 Publish 14.1 performance rows that have
unique counterparts while preserving 157 later rows, restores the four-box
entertainer-healing XP branch, and removes the retained NGE healer-XP
conversion. Performers heal themselves and valid patrons within 60 meters;
the exact base/skill/flourish calculation grants solo or active-group
`entertainer_healing` XP within 40 meters. Its identity-bound fixture proves
the Basic-dance three-point four-channel heal, asynchronous six-XP delivery,
exact preimage restoration, and idempotent cleanup.

`063-p14-performance-action-drain.patch` restores the pinned Core3 Action
costs for every performance heartbeat and flourish. Ten-second dance, music,
and juggle loops use the performance row's Action base with the
Quickness-300-over-1200 adjustment and truncate after clamping to zero.
Solo and band flourishes retain their distinct base-minus-Quickness-over-35,
half-cost, rounded equation. Both paths reject when current Action is equal
to the calculated charge. The identity-bound fixture proves Basic dance at
the live character's authoritative Quickness 400: loop cost 25, flourish
cost 9, both exact-cost rejection boundaries, interrupted-lifecycle recovery,
exact preimage restoration, and idempotent cleanup.

`064-p14-real-client-performance-session.patch` adds the reversible,
identity-bound fixture for the real Publish 14.1 client command seam. Protocol
32 admits fixed `startDance rhythmic`, `flourish 1`, and `stopDance` requests
through the ordinary client command queue while the server retains every
skill, posture, session, Action, heartbeat, and termination decision. Live
acceptance proved rhythmic index 283, flourish Action `100 -> 91`, explicit
stop and script detachment, then automatic too-tired termination at exactly
25 Action without underflow. Cleanup restored Action, regen, posture,
locomotion, novice-skill ownership, and performance residue.

`065-p14-real-client-music-session.patch` adds the reversible,
identity-bound instrument fixture for the real Publish 14.1 music command
seam. Protocol 33 admits fixed `startMusic starwars1`, `flourish 1`, and
`stopMusic` requests through the ordinary client command queue. The server
still owns slitherhorn equip state, song/instrument abilities, performance
index 1, heartbeat cost, and the authentic 15-second post-performance outro.
Live acceptance proved flourish Action `100 -> 91`, the explicit-stop outro
and its single heartbeat at `91 -> 66`, then the exact-cost 25-Action
exhaustion outro without underflow. Cleanup destroyed the fixture instrument
and restored the full character preimage.

`066-p14-real-client-band-music-session.patch` adds the reversible,
identity-bound two-player fixture for the retained Publish 14.1 band command
path. Protocol 34 uses real clients for `/invite`, `/join`, `startBand`,
`bandFlourish`, `stopBand`, and `/disband`; the fixture only prepares and
observes server-owned state. Acceptance requires both equipped group members
to share one performance start time, pay their authentic Quickness-dependent
flourish and heartbeat costs independently, enter and leave the 15-second
outro together, and restore both complete preimages after real-client group
dissolution.

`067-p14-entertainer-music-one-progression.patch` restores the exact
Publish 14.1 Entertainer root, novice, and Music I rows and adds the
identity-bound purchase, Rock, surrender, and cleanup fixture.

`068-p14-entertainer-music-two-progression.patch` restores the exact Music II
row, including Star Wars 2 and the Fizz schematic group, and extends the same
fixture through purchase, real-client playback, actor-routed surrender, and
idempotent restoration.

`069-p14-entertainer-music-three-progression.patch` restores exact Music III,
including Folk and Fanfar, and extends the fixture through protocol-37
purchase, playback, surrender, prerequisite retention, and cleanup.

`070-p14-entertainer-music-four-progression.patch` restores exact Music IV,
including Star Wars 3 and Kloo Horn, and extends the fixture through
protocol-38 purchase, playback, surrender, prerequisite retention, and
cleanup.

`071-p14-entertainer-master-progression.patch` restores the exact
four-terminal Entertainer capstone and extends the fixture through protocol-39
purchase, Ceremonial playback, surrender, prerequisite retention, and
cleanup.

`072-p14-entertainer-dance-one-progression.patch` restores exact Dance I,
including Basic 2, and adds the protocol-40 purchase, playback, surrender,
novice-cap recomputation, and cleanup fixture.

`151-p14-profession-ownership-predicate.patch` removes the singular NGE class
template from the shared profession predicate. It maps retained compatibility
enums to exact Publish 14.1 novice ownership, native Jedi state, or a
fail-closed result, and adds an identity-bound reversible live fixture.

`169-p14-storyteller-token-lifecycle-retirement.patch` retires nine
player-owned Storyteller token lifecycles. Blueprint, theater, NPC, prop,
destructible-prop, effect, jukebox-converter, and NPC-difficulty token
scripts detach at attach and initialization while their object classes remain
loadable. Deployed controller scripts remain intact to clean up existing
world objects.

`170-p14-storyteller-command-surface-retirement.patch` closes command-table
movement and rotation handlers plus the special city-zoning path. Handler
names remain link-compatible, ordinary zoning remains intact, and CSR destroy
commands remain available for later-era object cleanup.

`171-p14-storyteller-invitation-terminal-retirement.patch` detaches persisted
invitation terminals at attach and initialization, retaining object linkage
without active invite menus or relationship messages.

`172-p14-storyteller-band-spawner-retirement.patch` cleans up tracked holiday
band members and instruments before detaching the shared spawner. Buildout
anchors and separate event cleanup scripts remain intact.

`173-p14-storyteller-event-persistence-retirement.patch` removes automatic
event-anchor persistence while retaining immediate config-driven deletion and
independent event scripts.

`174-p14-later-holiday-reward-anchor-retirement.patch` detaches Life Day
gift/badge trees and Love Day berry-conversion fountains while retaining their
buildout anchor objects.

`175-p14-empire-day-parade-controller-retirement.patch` runs existing
sound/NPC/dropship cleanup before detaching both parade anchors.
`176-p14-empire-day-spawner-retirement.patch` retires later Empire and
Remembrance Day area, patrol, and random-sign spawners through a narrowly
scoped shared predicate, cleanup-first lifecycle detachment, and callback
guards while retaining ordinary generic spawning.

`177-p14-empire-day-interior-spawner-retirement.patch` destroys tracked
Empire Day building-interior NPCs, clears their persistent tracking state,
and detaches the independent spawner while retaining its host buildings.

`178-p14-empire-day-control-plane-retirement.patch` prevents startup and
operator commands from starting the later universe event, synchronously
stops stale Empire Day state, and retains the other shared holiday branches.

`179-p14-empire-day-planet-state-retirement.patch` removes persistent Empire
Day leaderboard roots, scores, and timestamps and closes queued setup/reset
callbacks while retaining Life Day planet state.

`180-p14-empire-day-generic-system-overrides.patch` removes Empire Day
configuration branches from generic city guards, GCW spawns, delivery NPCs,
and two banner implementations while retaining their normal behavior.

`181-p14-later-holiday-control-plane-retirement.patch` synchronously retires
the post-Publish-14.1 Halloween and Love Day universe events at startup and
through all operator commands. The distinct 2004 Life Day control path remains
intact for its own reconstruction.

`182-p14-love-day-custom-spawner-retirement.patch` cleans and detaches the
Cupid registration/manager pair, both romance-target anchors, and the
disillusion spawner. Queued callbacks fail closed, while passive templates,
buildout anchors, and generic spawners remain for separate treatment.

`183-p14-love-day-generic-spawner-retirement.patch` retires 11 area and 11
random Love Day rows through an exact shared predicate. Lifecycle cleanup now
finds children by authoritative `objParent` ownership before detaching, and
queued spawn/location callbacks fail closed. Ordinary and Life Day spawners
remain active.

Milestone 184 is evidence-only and therefore has no overlay patch. It proves
the three retained Love Day quest barrels have no admission path after the
sole Blaire quest giver was retired, while preserving the generic wave-event
controller and passive serialized anchors.

Milestone 185 is also evidence-only. Its residual audit partitions every Love
Day buildout row among the already-retired producer families or passive barrel
anchors and proves no unclassified world producer remains.

Milestone 186 is evidence-only. Both Halloween city buildouts are wholly
universe-event gated, and the already-retired control plane plus engine
start/stop callbacks prevent or unload all 664 rows without altering the
retained Life Day event.

Milestone 187 is evidence-only. The event vendor is the sole normal costume
provider and its two spawners are in the inactive Halloween buildouts.
Trick-or-treat payout, coins, projectors, the song book, and the 46-row reward
catalog are subordinate to that closed path. Existing-item compatibility and
privileged diagnostics remain unchanged.

Milestone 188 is evidence-only. It partitions every remaining Halloween
world/data and server-script surface, including the one incidental Dathomir
prop, passive templates, owned-item/sign compatibility, cleanup code, and
privileged diagnostics. No unclassified normal world producer remains.

Milestone 189 is evidence-only. It separates the retained 2004 Life Day
Wookiee quest lineage from the later 27-row factional city event and identifies
the missing automatic admission anchor for the two original NPC-spawner
scripts.

`190-p14-later-life-day-city-spawner-retirement.patch` extends the exact
cleanup-first generic spawner predicate to `eventRequired=life_day`, retiring
six random and 18 area spawners in the later factional cities. It deliberately
does not match the retained `lifeday` event or either original 2004 custom
spawner.

`191-p14-life-day-2004-admission-restoration.patch` restores the retained
2004 Life Day control path across six planet objects. It materializes three
city and twelve forest quest anchors only on authoritative scene servers,
corrects the forest coordinate fan-out, owns both anchor and celebrity NPC
lifecycles, and adds an identity-locked activation/cleanup fixture.

Milestone 192 is evidence-only. It locks the retained `lifeday04*` scripts as
a four-bit, one-time conversation quest, proves full-inventory reward retries,
classifies candy/orbs as passive scenery rather than collection objectives,
and preserves the original unused age calculation without inventing a gate.

`193-p14-later-life-day-scoreboard-retirement.patch` retires the later
factional daily scoreboard independently of the retained 2004 event switch.
Both planet lifecycle entry points clean the later `lifeday` namespace;
already-queued daily/update messages and persisted competitive-buff callbacks
also fail closed. The cleanup deliberately does not match `lifeday04`.

`194-p14-later-life-day-stap-admission-retirement.patch` removes the sole
NGE-era TK-555 building-spawn row still keyed directly to the retained
`lifeday` switch. The five passive cantina candy props and food container
remain, as do persisted STAP quest scripts; Saun Dann's sole producer remains
closed by the earlier Figrin Dan band-spawner retirement.

`195-p14-later-life-day-gcw-override-retirement.patch` removes the later
factional event's Dearic invasion suppression from `gcwIsInvasionCityOn`.
Ordinary `gcwcity*` configuration remains authoritative, so enabling the
restored 2004 Life Day event no longer disables unrelated GCW gameplay.

`196-p14-life-day-level-up-loot-retirement.patch` removes the post-era
one-in-ten-thousand `levelup_lifeday_orb` substitution from ordinary
space-combat loot. Table-selected loot remains unchanged, the original 2004
quest orb remains, and the later orb template is retained only for persisted
object compatibility.

Milestone 197 is evidence-only. It partitions all 45 remaining Life Day
server scripts plus 37 content-bearing datatables and 196 templates among the
restored 2004 route, closed later systems, existing-object compatibility,
passive/incidental data, cleanup, and privileged diagnostics. No
unclassified normal world producer remains.

`202-p14-core3-random-area-combat.patch` restores Core3's default RANDOM
target-pool policy and the first generated area command, `polearmSpinAttack1`.
RANDOM resolves once per defender hit using the pinned 61/35/5 outcome counts
across the inclusive 0..100 roll, then the same resolved pool drives physical
hit location, HAM damage, and wound attribution. The area pilot retains its
16-meter Core3 range, and its identity-bound fixture now snapshots and
restores all nine wounds plus shock wounds.

`203-p14-core3-melee-spin-attacks.patch` restores the first one- and two-hand
AREA specials with exact Core3 HAM, accuracy, spam, animation, and weapon
metadata, backed by reversible Rantok and cleaver fixture objects.

`204-p14-core3-generated-animation.patch` restores Core3's generated ranged
and intensity suffix rules after authoritative damage and hit-location
resolution while leaving unmapped and creature-wildcard animations unchanged.

`205-p14-core3-body-shot-continuation.patch` restores `bodyShot2` and
`bodyShot3` with their exact Marksman/Pistoleer ownership, pistol admission,
Health targeting, HAM costs, damage multipliers, `bodyshot` spam, and generated
ranged playback. The live fixture owns a reversible CDEF pistol and snapshots
both commands plus its certification.

`206-p14-core3-head-shot-continuation.patch` replaces the earlier
duration-only `headShot2` placeholder with exact Core3 combat behavior and
adds `headShot3`. Both restore rifle admission, Mind targeting, exact costs,
damage, accuracy, distinct combat spam, and generated ranged head playback;
the existing fixture snapshots and restores the new command ownership.

`207-p14-core3-one-hand-body-hit-one.patch` restores the Brawler
one-handed-II `melee1hBodyHit1` special with its exact Core3 Health target,
HAM costs, damage, timing, accuracy, `saimai` spam, Rantok admission, and
generated intensity playback. The identity-bound fixture reuses its existing
Rantok while independently snapshotting and restoring the new command.

`208-p14-core3-one-hand-body-hit-continuation.patch` completes the ordinary
Swordsman body-hit line with `melee1hBodyHit2` and `melee1hBodyHit3`. Both
retain exact Core3 Health targeting, HAM costs, damage, timing, accuracy,
`saisun`/`saitok` spam, Rantok admission, and generated intensity playback;
the fixture snapshots and restores each command independently.

`209-p14-core3-two-hand-head-hit-continuation.patch` restores all three
ordinary two-handed head-hit specials with exact Brawler/Swordsman ownership,
Mind targeting, HAM, damage, timing, accuracy, scalp spam, cleaver admission,
and generated `combo_2d` intensity playback.

`210-p14-core3-basic-melee-hits.patch` restores the first two ordinary
one-handed and two-handed melee hit specials with exact Brawler/Swordsman
ownership, random HAM targeting, costs, damage, timing, accuracy, combat spam,
Rantok/cleaver admission, and their distinct generated intensity animations.

`211-p14-core3-polearm-leg-hit-continuation.patch` restores the two advanced
Polearm leg-hit specials with exact Pikeman ownership, Action targeting, HAM
costs, damage, timing, accuracy, `legsmasher`/`legbreaker` spam, wooden-staff
admission, and their distinct generated intensity animations.

`212-p14-core3-polearm-hit-and-area.patch` restores the Brawler Polearm hit
and Pikeman area special with exact ownership, RANDOM targeting, HAM costs,
damage, timing, accuracy, `bonebruiser`/`whirlwind` spam, wooden-staff
admission, generated intensity playback, and the area's 16-meter shape.

`213-p14-core3-two-hand-spin-attack-continuation.patch` restores Swordsman
ability I's `melee2hSpinAttack2` with exact Core3 RANDOM targeting, HAM costs,
3x damage, 2.5 timing, 10 accuracy, `spinslam` spam, cleaver admission,
generated `combo_4b` intensity playback, and its 16-meter area shape.

`214-p14-core3-body-shot-one-closure.patch` closes the original Marksman
`bodyShot1` path against pinned Core3 evidence. It corrects command timing
from 1.5 to 1.0, restores the authentic `bodyshot` spam stem, and makes the
reversible Marksman fixture ignore diagnostic-only objvars when validating
ownership so retained diagnostics cannot block a fresh preparation.

`215-p14-core3-burst-shot-one.patch` restores Carbineer ability I's
single-target `burstShot1` with exact RANDOM targeting, 1.75/1.25/0.5 HAM
costs, 4x damage, 2.0 timing, 25 accuracy, `burstshot` spam, CDEF carbine
admission, and generated `fire_7_single` ranged playback. Its fixture owns
the ability skill and CDEF carbine certification reversibly. `burstShot2`
remains deferred because Core3 adds a separate 30-degree cone seam.

`216-p14-core3-disarming-shot-one.patch` restores Pistoleer ability I's
single-target `disarmingShot1` with exact RANDOM targeting, 0.5/0.75/0.5 HAM
costs, 2x damage, 1.5 timing, 50 accuracy, `disarmshot` spam, CDEF pistol
admission, and generated `fire_3_single` ranged playback. Its fixture owns
the ability skill reversibly. `disarmingShot2` remains deferred because Core3
adds a separate 15-degree cone seam.

`217-p14-core3-double-tap.patch` restores Pistoleer ability II's single-target
`doubleTap` with exact RANDOM targeting, 0.5/0.75/0.5 HAM costs, 2.8x damage,
2.1 timing, 50 accuracy, `doubletap` spam, CDEF pistol admission, and generated
`fire_7_single` ranged playback. Its fixture owns the ability-II skill
reversibly and uses the already-proven ordinary generic combat path.

`218-p14-core3-stopping-shot.patch` restores Pistoleer ability III's
single-target `stoppingShot` with exact RANDOM targeting, 0.5/1.25/0.5 HAM
costs, 5x damage, 2.5 timing, 50 accuracy, `stoppingshot` spam, CDEF pistol
admission, and generated `fire_1_special_single` ranged playback. Its fixture
owns the ability-III skill reversibly.

`219-p14-core3-crippling-shot.patch` restores Carbineer speed III's
single-target `cripplingShot` with exact RANDOM targeting, 0.5/2.0/0.5 HAM
costs, 5x damage, 2.0 timing, 25 accuracy, `cripplingshot` spam, CDEF carbine
admission, and generated `fire_5_single` ranged playback. Its fixture owns
and restores both complete Marksman-to-elite prerequisite chains so advanced
skill grants cannot leave hidden prerequisite boxes behind.

`220-p14-core3-point-blank-single-two.patch` restores Pistoleer accuracy I's
single-target `pointBlankSingle2` with exact RANDOM targeting, 1.0/1.0/1.0
HAM costs, 3x damage, 1.8 timing, zero accuracy bonus, `pointblankblast` spam,
CDEF pistol admission, a strict 10-meter maximum, and generated
`fire_5_single` ranged playback. The reversible fixture owns the accuracy-I
box and both complete Marksman-to-elite prerequisite chains.

`221-p14-core3-point-blank-area-one.patch` restores Marksman novice's
short-range `pointBlankArea1` with exact RANDOM targeting, 0.5/1.25/0.5 HAM
costs, 2x damage, 1.5 timing, +15 accuracy, `pointblankblast` spam, aggregate
ranged admission, a 12-meter maximum, a 15-meter area radius, and generated
`fire_area_no_trails` intensity playback. The existing layered fixtures own
Marksman novice, their complete prerequisite chains, and exact cleanup.

`222-p14-core3-point-blank-area-two.patch` restores Pistoleer Accuracy IV's
short-range `pointBlankArea2` with exact RANDOM targeting, 0.5/1.5/0.5 HAM
costs, 4x damage, 1.5 timing, +50 accuracy, `areashot` spam, pistol admission,
a 12-meter/60-degree cone, and generated `fire_area_no_trails` intensity
playback. The layered fixture owns Accuracy I through IV and exact cleanup.
