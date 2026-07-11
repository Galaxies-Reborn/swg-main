# SWG Source
This repository houses the base of the SWG Source project. 

## What Do You Need To Do To Get A Server Running?

SWG Source provides a pre-configured Virtual Machine for quick starting a local environment. Follow the [Initial Setup of the Virtual Machine](https://github.com/SWG-Source/swg-main/wiki/Initial-Setup-Of-The-Virtual-Machine-VM-version-3.0-(%22Irish%22)) guide on our [Wiki](https://github.com/SWG-Source/swg-main/wiki) for specific step-by-step guidance. Feel free to [join us in Discord](https://discord.gg/Va8e6n8) if you have any questions.

## Local Docker server

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
