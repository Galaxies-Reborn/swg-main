# Galaxies Reborn
This repository houses the base of the Galaxies Reborn project. 

## What Do You Need To Do To Get A Server Running?

Use the Galaxies Reborn build and deployment instructions for this branch. Source dependencies must resolve to Galaxies-Reborn repositories.

## Local Docker server

For administrators and LLM assistants deploying Docker inside a Proxmox LXC,
read the [Proxmox LXC networking note](docker/README.md#proxmox-lxc-with-docker-inside-lxc).
Remote clients require a reachable `SWG_PUBLIC_ADDRESS` and matching client
login address; binding to `0.0.0.0` does not correct an advertised loopback IP.

The compose setup expects `client-assets` beside this repository and persists both Oracle data and Linux build products in named volumes. Start or resume the local cluster with:

```powershell
docker compose up --build -d
docker compose logs -f swg-server
```

The first start initializes Oracle and compiles the server. The cluster is playable when the log reports `Cluster swg is ready for players` and `docker compose ps` reports the server as healthy.

Source is mounted read-only at `/swg-main-source` and synchronized into the `swg-work` build volume. `SWG_SYNC_SOURCE=auto` populates an empty volume and synchronizes before `init`, `build`, or `ant` commands. After source changes, rebuild without discarding the database:

```powershell
docker compose stop swg-server
docker compose run --rm swg-server build
docker compose up -d swg-server
```

With no external authentication URL configured, the local LoginServer accepts a client account name and derives its station ID from it; the password is not checked. The persisted development database currently has station ID `1001`, character `Mago Eopoli`, and uses `local` as the conventional client password.

## Galaxies Reborn community

Join the [Galaxies Reborn Discord](https://discord.gg/CEwKVvKxK5) for project discussion, support, and announcements.
