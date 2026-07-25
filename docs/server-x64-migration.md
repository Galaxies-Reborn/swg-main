# Server x64 migration

This branch builds a 64-bit client and server by default.

## Defaults

- `docker-compose.yml` builds `docker/Dockerfile.x64`, sets `SWG_SERVER_BITS=64`
  and uses the `swg-work-x64` build volume.
- `docker/entrypoint.sh` defaults `SWG_SERVER_BITS` to `64`.
- `build.properties` sets `bits = 64`, which drives the `-m64` CMake
  configuration in `build.xml`.
- The Compose project name is pinned to `swg-main-x64`. Compose would otherwise
  derive it from the directory name (`swg-main`), which is the namespace the
  legacy 32-bit volumes already occupy, and the 64-bit server would attach to
  the 32-bit database.
- The client is built from `Galaxies-Reborn/client-tools` on `x64-dx9-vanilla`
  via `scripts/Build-X64Client.ps1`, which produces `Release|x64`.

## Build

```sh
git submodule update --init --recursive
docker compose build swg-server
docker compose run --rm swg-server init
docker compose run --rm swg-server verify-arch
docker compose up -d
```

`init` performs database initialization and template loading as well as the
build. Confirm the selected Oracle database is disposable before running it.

## 32-bit fallback

The 32-bit path is still available as an override:

```sh
docker compose -f docker-compose.yml -f docker-compose.32.yml build swg-server
docker compose -f docker-compose.yml -f docker-compose.32.yml run --rm swg-server init
```

It uses its own project namespace (`swg-main-32`) and its own `swg-work-32`
volume, so CMake products from the two architectures never mix.

`docker-compose.x64.yml` is retained as a compatibility shim for existing
invocations and only restates the defaults.

## Acceptance gates

Before calling the migration playable:

1. Every core executable must report `ELF 64-bit`.
2. Oracle schema creation and template loading must complete without bind-size
   or numeric-conversion errors.
3. Login, character enumeration, character creation, world entry, chat, object
   persistence, logout, and restart/reload must pass.
4. Exercise travel, combat, AI/pathfinding, inventory, quests, mail, bazaar,
   structures, and inter-server transfers.
5. Run an ASan/UBSan build and a multi-hour soak before any production switch.

## LP64 hazards already addressed

- `AutoDeltaPackedMap` specializations for `<NetworkId,int>`, `<int,NetworkId>`
  and `<int,Unicode::String>` wrote their counts at mixed widths, desynchronising
  the stream under LP64.
- `DebugHelp::getCallStack()` passed a `uint32` buffer to `backtrace()`, which
  writes `void*`, overrunning every call stack buffer by 2x.
- `QueryPerformanceCounter` was backed by non-monotonic `gettimeofday()`.
- `JavaLibrary::fatalHandler()` dereferenced a hardcoded 32-bit frame offset.

Remaining areas to watch: pointer/integer casts, serialization widths,
structure layout, network and database field sizes, format specifiers,
alignment, and third-party ABI compatibility.

## Rollback

Stop the stack and bring it up with the `docker-compose.32.yml` override
against its own volume. Database compatibility must be verified before pointing
both architectures at the same non-disposable database. The packed-map fix
deliberately preserves the 32-bit on-disk format so data stays readable by both.
