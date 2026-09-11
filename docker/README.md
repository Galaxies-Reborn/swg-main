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
