# Server x64 migration

This branch is the isolated starting point for moving the SWG server processes
from 32-bit Linux to 64-bit Linux. It does not replace the existing
`x64-dx9-vanilla` deployment path.

## Branch topology

- `Galaxies-Reborn/src:agent/server-x64-bootstrap` starts at
  `SWG-Source/src:64-bit-types` and reapplies the Galaxies-Reborn
  `Support Docker-local server services` delta.
- `Galaxies-Reborn/swg-main:agent/server-x64-bootstrap` merges the upstream
  64-bit Ant/build configuration, pins the prepared `src` branch, and adds a
  separate x64 Docker/Compose path.
- The existing `docker/Dockerfile` and default Compose build remain the
  32-bit fallback.

## First x64 build

Initialize all submodules, then build the separate image and work volume:

```sh
git submodule update --init --recursive
docker compose -f docker-compose.yml -f docker-compose.x64.yml build swg-server
docker compose -f docker-compose.yml -f docker-compose.x64.yml run --rm swg-server init
docker compose -f docker-compose.yml -f docker-compose.x64.yml run --rm swg-server verify-arch
docker compose -f docker-compose.yml -f docker-compose.x64.yml up -d
```

Do not reuse the legacy `swg-work` volume for the x64 build. The override uses
`swg-work-x64` so CMake products from the two architectures cannot mix.

## Initial acceptance gate

Before calling the migration playable:

1. Every core executable must report `ELF 64-bit`.
2. Oracle schema creation and template loading must complete without bind-size
   or numeric-conversion errors.
3. Login, character enumeration, character creation, world entry, chat, object
   persistence, logout, and restart/reload must pass.
4. Exercise travel, combat, AI/pathfinding, inventory, quests, mail, bazaar,
   structures, and inter-server transfers.
5. Run an ASan/UBSan build and a multi-hour soak before any production switch.

## Rollback

The migration is additive. Stop the x64 Compose stack and start the unchanged
default Compose stack against its original 32-bit work volume. Database
compatibility must be verified before pointing both architectures at the same
non-disposable database.
