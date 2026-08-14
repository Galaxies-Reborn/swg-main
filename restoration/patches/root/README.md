# Superproject runtime overlays

`001-dedicated-transfer-server.patch` supervises the TransferServer alongside
TaskManager after CentralServer becomes available. The stock executable is
required for named-account bank transfers used by production money services;
the dedicated `swg-precu` cluster must not silently run without it.

`002-p14-database-migration-runner.patch` runs the ordered database updater on
every existing-runtime start before configuration is rewritten. Both database
creation and update targets fail closed when the Perl migration process fails,
so a schema mismatch cannot be hidden behind an otherwise successful Ant run.

`003-x64-container-address-prerequisite.patch` installs `iproute2` and makes
container-address discovery compatible with fail-fast shell execution.

`004-bounded-local-scene-profile.patch` adds an opt-in `SWG_START_PLANETS`
runtime filter. The complete scene set remains registered in source, while the
dedicated local acceptance container can start a bounded test set without
saturating the host and delaying gameplay commands.

`005-precu-docker-runtime-parity.patch` closes direct-repository drift in the
isolated Pre-CU Compose definition, networking/port configuration, operator
documentation, and repository text rules. It intentionally preserves the
TransferServer supervisor already restored by patch 001.
