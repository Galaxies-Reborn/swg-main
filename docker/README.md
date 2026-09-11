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
docker compose up -d --force-recreate swg-server
```

The default Oracle XE image stores PDB datafiles under
`/opt/oracle/oradata/XE/XEPDB1`; override `SWG_DB_DATAFILE_DIR` if you use a
different Oracle image or service layout.

## Proxmox LXC with Docker inside LXC

**Note for administrators and LLM assistants:** a successful build or a service
bound to `0.0.0.0` does not make an advertised address of `127.0.0.1` reachable
from another computer. A bind address controls where the service listens; the
advertised address tells the client where to connect. On a remote client,
`127.0.0.1` points back to that client's own computer.

For clients on the LAN:

1. Set `services.swg-server.environment.SWG_PUBLIC_ADDRESS` in
   `docker-compose.yml` to the **LXC container's LAN IP reachable from the
   client**, for example `192.168.1.50`. Use the exact uppercase variable name.
   The current Compose file hardcodes this value, so setting it in `.env` alone
   does not override it. A Compose override file can also set the service's
   environment value explicitly.
2. Set the client's `login.cfg` to the same reachable address:

   ```ini
   [ClientGame]
   loginServerAddress0=192.168.1.50
   loginServerPort0=44453
   ```

3. Recreate the server service to apply the changed environment:

   ```bash
   docker compose up -d --force-recreate swg-server
   docker compose logs -f swg-server
   ```

   No recompilation or database reset is required for this address change.
   Startup updates the cluster database address and ConnectionServer's
   `altPublicBindAddress` from `SWG_PUBLIC_ADDRESS`. A plain `docker compose
   restart` does not apply a changed Compose environment.
4. Ensure Docker publishes the game ports and that Proxmox, LXC, and any
   intervening firewall/NAT permit **UDP 44453** (login) and **UDP 44463**
   (the default public game connection). This repository publishes UDP
   `44450-44465`. Ping and TCP-only port tests do not verify UDP connectivity.
5. Confirm the log reports `Cluster swg is ready for players`; successful
   compilation or Docker health alone does not establish gameplay readiness.

Replace the example IP with the actual LXC address. Do not advertise the
internal Docker bridge address unless clients are explicitly routed to it.
For internet clients, advertise the reachable public address and forward the
required UDP ports through the router/NAT to the LXC's published Docker ports.

Keep a valid bind configuration: an application already listening on
`0.0.0.0` can keep doing so. The repository also uses `eth0` bindings for several
services; those must refer to an interface present inside the Docker container.
Do not change internal service addresses indiscriminately to the public IP.

These Compose instructions apply to **Docker inside LXC**. A server installed
directly in LXC needs equivalent runtime/database configuration rather than a
Compose environment change. When diagnosing a report, establish the topology,
the client's destination address, and whether failure occurs at login, server
selection, or world entry before assuming Proxmox itself is the cause.

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
