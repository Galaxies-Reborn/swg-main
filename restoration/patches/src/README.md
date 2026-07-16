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
