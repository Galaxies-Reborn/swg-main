# Executable/runtime configuration overlays

`001-p14-xp-rate.patch` removes the later three-times bonus XP setting from
the dedicated Pre-CU server configuration. Publish 14.1 skill-training costs
and the Phase-A lifecycle are expressed in unmultiplied table XP, so the
restored runtime must use `xpMultiplier=1`.

The same overlay gives the dedicated cluster a private TransferServer endpoint.
CentralServer uses that endpoint for named-account bank transfers, including
ordinary trainer payment/accounting paths.

The overlay also enables all six `space_ord_mantell` shards already present in
the x64 source corpus. The NPE station transport library probes those scene
IDs at runtime and load-balances station Gamma traffic only across shards that
CentralServer actually started.

`002-p14-combat-cadence-log-target.patch` routes only the native
`PreCuCombatCadence` category to `logs/precuCombatCadence.log`. This makes live
player and creature attack timestamps inspectable without enabling the broad
legacy log streams or changing combat behavior.

`003-p14-scout-harvest-log-target.patch` routes native and Java
`PreCuScoutHarvest` rejection evidence to a dedicated runtime log, leaving the
normal server log categories unchanged.

`004-p14-npc-conversation-log-target.patch` routes only the native
`PreCuConversation` lifecycle and rejection records to
`logs/precuNpcConversation.log`, so a missing UI response can be distinguished
from distance, target, parameter, script-trigger, or stale-session failure.

`005-p14-object-menu-log-target.patch` routes only the native
`PreCuObjectMenu` request/response records to `logs/precuObjectMenu.log`. This
keeps NPC, Bazaar, and other terminal interaction diagnostics separate from the
broad legacy server logs.
