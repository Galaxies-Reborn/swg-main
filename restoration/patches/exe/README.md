# Executable/runtime configuration overlays

`001-p14-xp-rate.patch` removes the later three-times bonus XP setting from
the dedicated Pre-CU server configuration. Publish 14.1 skill-training costs
and the Phase-A lifecycle are expressed in unmultiplied table XP, so the
restored runtime must use `xpMultiplier=1`.

The same overlay gives the dedicated cluster a private TransferServer endpoint.
CentralServer uses that endpoint for named-account bank transfers, including
ordinary trainer payment/accounting paths.
