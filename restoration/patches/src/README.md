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

`004-p14-character-sheet-data.patch` restores the character-sheet producer's
persisted birth date and played time, prefers the durable cloning bind
location with a legacy facility fallback, keeps the last bank-terminal planet
without inventing coordinates, reports the residence object's own scene, and
sends account lots remaining from the authoritative configured cap plus the
persisted per-account adjustment. It adapts Core3 field semantics to the
retained SWGSource message envelope rather than claiming wire equivalence.

`005-precu-three-pool-combat-runtime.patch` supplies the native M3 primitives:
atomic strict-positive Health/Action/Mind cost drain, explicit primary-pool
damage routing, and incapacitation on any depleted primary pool with recovery
only after all three pools are positive. The original no-pool damage entry
point remains Health-only for unconverted commands.

`006-precu-nine-attribute-runtime.patch` restores the exact Publish 14
H/S/C/A/Q/St/M/F/W shared enum and all generated server/compiler template
arrays. It expands creation and stat-migration messages, replicates every
attribute, remaps item-bonus names, migrates persisted six-value creatures on
authoritative load, and derives pool regeneration from Constitution, Stamina,
and Willpower using the Core3 formula. The combat-damage script callback is
expanded atomically to the same nine-value order.

`007-p14-stat-migration-session.patch` restores the four retained migration
command handlers and a server-owned nine-target allocation session. Racial
minimums, maximums, and totals are authoritative; client-supplied points-left
is advisory. Valid tutorial allocations commit immediately in `newbie_hall`,
while normal-world allocations remain pending for the separate Image Designer
transaction milestone.

`008-p14-stat-migration-image-designer.patch` completes that normal-world
transaction boundary. Client change and cancel messages must match the
server-owned designer, recipient, and terminal identities; the Java-to-native
callback must also match the authoritative start time and design type. Stat
migration is non-self, requires both participants to remain in the original
salon structure, revalidates the recipient's exact nine-stat allocation, and
consumes it once after payment validation. The retained script awards the
authentic 2,000 Image Designer XP and the shared timer restores the 240-second
Publish 14 delay.

`009-p14-image-designer-wire-time32.patch` pins the controller message's start
time to the retail-era signed 32-bit wire field. This prevents an x64 client
host's 64-bit `time_t` from shifting the remaining payload and triggering the
32-bit game server's invalid-network-stream disconnect guard.

`010-p14-stat-migration-persistence.patch` stores a validated, zero-points-left
allocation on the recipient as a versioned native object-variable record. The
in-memory session reloads from that record after a game-server restart and is
validated again before use. A committing marker is persisted before mutation,
so partial or interrupted records fail closed and cannot replay the service or
its XP reward. Tutorial and successful salon commits consume the durable state.

`011-p14-precu-command-duration.patch` exposes authoritative weapon attack
speed to the Java combat-data bridge so authenticated Pre-CU commands can use
the Core3 duration equation without changing NGE command timing.

`012-p14-persistent-wounds.patch` restores wounds as a dedicated persistent
nine-value `CreatureObject` vector instead of the non-persistent attribute-mod
list. It stores the vector in retired NGE creature columns 18 through 26 under
database version 272, separates unwounded and wounded maximum attributes,
applies primary versus linked-secondary current-value semantics, and exposes
exact add/heal operations to scripts. The database server's required version,
version query, generated packager registration, and zero-baseline migration
travel in the same atomic overlay.

`328-p14-stat-migration-tutorial-admission.patch` keys free migration to the
authoritative full-or-skipped fresh-character tutorial lifecycle rather than a
nonexistent scene name. After first-planet handoff, the native commit boundary
requires a distinct entertainer who still owns `imagedesign`, plus both players
inside the same server-verified `salon` structure.

`332-p14-stat-migration-entertainer-camps.patch` extends that normal-world
boundary to crafted camps carrying `modules.entertainer`. The authenticated
session terminal must be the exact camp object, and its `campsite` trigger
volume must still contain both players when the server commits the allocation.
Permanent saloons retain their stricter shared-topmost-container check.

`333-precu-radial-menu-recovery.patch` guarantees a terminal or NPC radial
request receives an empty authoritative response when its buildout target is
temporarily unavailable, intentionally menu-less, or lacks a script object.
This prevents one unanswered world-snapshot object from blocking every later
interaction while authority transfer requests retain their normal retry path.

`334-precu-creature-attack-timing.patch` keeps AI default attacks on the
authoritative weapon attack time (with the Pre-CU one-second floor) instead of
the retained NGE command-table execute time. Player commands continue through
their existing explicit Pre-CU override/profile timing path.

`338-precu-combat-cadence.patch` unifies player and creature primary attacks
with the Publish 14 weapon-speed calculation already used by restored specials:
weapon attack time, weapon-family speed mods, melee/ranged speed bonuses,
positive combat haste, and a one-second floor. Primary cooldown is zero because
the full interval is now counted once in execute time. Player-controlled queues
remain unlimited, while non-player combat queues regain a two-action admission
ceiling so AI cannot stack attacks faster than its weapon cadence.

`349-p14-core3-cadence-and-harvest-execution-authority.patch` revalidates
Novice Scout when `harvestCorpse` actually executes, before Java dispatch. It
also records attack classification, weapon-family and private speed modifiers,
combat haste, and any unclassified player combat-queue command so live cadence
can be proven against the pinned Core3 formula rather than inferred from client
animation.

`350-p14-persisted-nge-skill-retirement.patch` removes retained NGE
`class_*`, `expertise`, `expertise_*`, and `internal_expertise_*` skills from
authoritative player persistence during database load. The removal happens
before `setupSkillData()` reconstructs commands, modifiers, schematics, and
level, so relogging cannot reactivate NGE progression authority. Quest,
conversation, zone, and independent quest/object-variable state remain intact.

`351-p14-npc-conversation-lifecycle-recovery.patch` makes a fresh player
converse request recover an older native conversation session before starting
the requested NPC. End triggers still run, but their `SCRIPT_OVERRIDE` result
can no longer skip proxy removal, object deletion, and the client's stop
message. Dedicated result and rejection telemetry makes every live request
observable in release builds.

`352-p14-object-menu-telemetry.patch` records the authoritative request,
cross-server route, empty response, and script-complete response boundaries for
NPC and terminal object menus. The category is diagnostic only: it does not
change menu admission, menu contents, authority routing, or response timing.

`354-p14-precu-faction-rank-authority.patch` reactivates the persisted/shared
`CreatureObject::m_rank` value and routes the script rank getter and a new
validated setter through it. NGE weekly GCW rating no longer supplies gameplay
faction rank, while the existing shared package continues to replicate the
PRE-CU rank byte to clients.
