# Superproject runtime overlays

`001-dedicated-transfer-server.patch` supervises the TransferServer alongside
TaskManager after CentralServer becomes available. The stock executable is
required for named-account bank transfers used by production money services;
the dedicated `swg-precu` cluster must not silently run without it.
