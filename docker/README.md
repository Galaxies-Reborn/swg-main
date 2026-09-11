# Docker SWG Server

This Docker setup builds and runs the Galaxies Reborn server against an Oracle XE
container while keeping the checked-out repositories independent. The checked
out source is mounted read-only and synced into the `swg-work` Docker volume so
CMake builds on a Linux filesystem instead of repeatedly walking the Windows
bind mount.

The sibling `client-assets` checkout is mounted read-only at `/client-assets`.
At startup the container stages the client TRE specified in the startup script into the
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
powershell -File restoration/scripts/Test-PrecuDockerNetwork.ps1
```

The default bind mounts are the audited materialized source directory
and the sibling `pre-cu-reborn-assets` checkout, as configured in
`docker-compose.precu.yml`. Override them with `SWG_PRECU_SOURCE_DIR` and
`SWG_PRECU_ASSETS_DIR` when needed. The local client connects to login port
`45453`; ConnectionServer uses `45462` for ping, `45463` for its public client
service, and `45464` for its private client service. Those three ports are
mapped same-to-same because LoginServer embeds them in its status response;
the login port remains translated from host `45453` to container `44453`. Oracle
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
`45463`; `SWG_PRECU_PUBLIC_CONNECTION_PING_PORT` and
`SWG_PRECU_PRIVATE_CONNECTION_PORT` default to `45462` and `45464`. Each
configured ConnectionServer port is mapped same-to-same inside Docker. The
three ports must be distinct and must not use the fixed host mappings
`45450-45461` or `45465`.

`SWG_PRECU_CENTRAL_LOGIN_SERVICE_PORT` defaults to `44452`. The entrypoint
writes the public address and this CentralServer login-service port to
`cluster_list`, and writes the same service port to the LoginServer and
CentralServer runtime configuration. This repairs dedicated volumes created by
an earlier entrypoint that incorrectly stored the client handoff port `45463`
in `cluster_list.port`; that column is not a client handoff port. Do not use
`down -v` unless the dedicated `swg-precu-*` database and build volumes are
intentionally being discarded.
