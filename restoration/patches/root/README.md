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
