# Docker SWG Server

This Docker setup builds and runs the SWG Source server against an Oracle XE
container while keeping the checked-out repositories independent. The checked
out source is mounted read-only and synced into the `swg-work` Docker volume so
CMake builds on a Linux filesystem instead of repeatedly walking the Windows
bind mount.

The sibling `client-assets` checkout is mounted read-only at `/client-assets`.
At startup the container stages `/client-assets/swgsource_3.0.tre` into the
Linux `swg-work` volume and adds that staged TRE to the server's `[SharedFile]`
tree search paths so runtime assets that only exist in the client TRE are
available to the game servers.

## First Run

From `swg-main`:

```bash
docker compose build swg-server
docker compose run --rm swg-server init
docker compose up swg-server
```

The `init` command creates `local.properties`, prepares Oracle tablespaces and
grants, localizes the server configs, creates/updates the SWG schema, compiles
the C++ services, compiles Station Chat, compiles Java scripts, and loads
template CRCs into Oracle.

For a Windows client on the same machine, set the game client's `login.cfg` to:

```ini
loginServerAddress0=127.0.0.1
loginServerPort0=44453
```

For LAN or external clients, set `SWG_PUBLIC_ADDRESS` in `docker-compose.yml` to
the host IP/DNS name that those clients can reach, then run:

```bash
docker compose run --rm swg-server ant update_configs
docker compose run --rm swg-server run
```

The default Oracle XE image stores PDB datafiles under
`/opt/oracle/oradata/XE/XEPDB1`; override `SWG_DB_DATAFILE_DIR` if you use a
different Oracle image or service layout.

## Useful Commands

```bash
docker compose up oracle
docker compose run --rm swg-server build
docker compose run --rm swg-server ant compile_java
docker compose run --rm swg-server ant stop
docker compose down
```

Generated `build/`, `data/`, `chat/`, localized config files, and
`local.properties` live in the `swg-work` Docker volume. Source changes still
belong in this checkout and are synced into the volume at container startup.

## Isolated Pre-CU Runtime

`docker-compose.precu.yml` defines a separate runtime for the Pre-CU effort.
It does not share containers, ports, network, or named volumes with
`docker-compose.yml`:

```bash
docker compose -f docker-compose.precu.yml build swg-precu
docker compose -f docker-compose.precu.yml up -d
docker compose -f docker-compose.precu.yml ps
```

The default bind mounts are the audited materialized source at
`E:/SWG/SWGSource/Staging/swg-precu-runtime-source` and the sibling
`pre-cu-reborn-assets` checkout. Override them with `SWG_PRECU_SOURCE_DIR` and
`SWG_PRECU_ASSETS_DIR` when needed. The local client connects to login port
`45453`; the externally advertised connection-server port is `45463`. Oracle
is exposed to localhost only on `127.0.0.1:1522`, and customer-service ports
are `5100-5101`.

`swg-precu-runtime-source` is the stable local alias for the currently audited
materialization. Update that alias, or override `SWG_PRECU_SOURCE_DIR`, only
while the `swg-precu` game container is stopped; the materialized tree remains
read-only inside the container.

`SWG_PRECU_SYNC_SOURCE` defaults to `auto`: an empty work volume is populated,
and explicit `init` or `build` commands resynchronize source, while ordinary
restarts reuse the already compiled Linux volume. Set it to `true` for a forced
exact resync or `false` only when deliberately operating on the current volume.

For a remote client, set `SWG_PRECU_PUBLIC_ADDRESS` to the reachable host
address. `SWG_PRECU_PUBLIC_CONNECTION_PORT` defaults to the mapped port
`45463`. The entrypoint writes both values to `cluster_list` on every server
start. Do not use `down -v` unless the dedicated `swg-precu-*` database and
build volumes are intentionally being discarded.
