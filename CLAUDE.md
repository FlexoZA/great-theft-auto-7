# Great Theft Auto 7

Top-down driving game in Lua using LÖVE 11.5.

## Commands
- Run: `love .` (or `make run`)
- Lint: `luacheck .`
- Format: `stylua .`
- Package: `make build` -> `build/great-theft-auto-7.love`

## Conventions
- Lua 5.1 / LuaJIT semantics (LÖVE ships LuaJIT). No `goto`, no integer division `//`, no bit ops syntax.
- Game code lives in `src/`, one module per file returning a table. Require with dotted paths: `require("src.car")`.
- Screens are states in `src/states/` switched via `src/state.lua`. Networking is under `src/net/`; game code talks only to `Net.client` (the host runs its own client). Design in `docs/networking.md`.

## Adding a feature (maps, cars, guns, anything gameplay)
Gameplay is built as features so several people can work without touching the same files. Read `docs/features.md` before starting.
- One folder per feature: `src/features/<feature-name>/` with an `init.lua` that returns a table of hooks. Everything the feature needs (other modules, assets) lives in that folder. Copy `src/features/_template/init.lua` to start; it lists every hook.
- Features are discovered automatically. Do not register them anywhere, and do not edit `main.lua`.
- Hooks, all optional: `load`, `enterGame`, `exitGame`, `update(dt, client)`, `drawBelowCars(client, camera)`, `drawAboveCars(client, camera)`, `drawHUD(client)`, `keypressed(key, client)`, `mousepressed(x, y, button, client)`, `wheelmoved(dx, dy, client)`, `serverStart(server)`, `serverStep(server, dt)`, `serverPlayerJoined(server, player)`, `serverPlayerLeft(server, player)`, plus `clientMessages` and `serverMessages` tables keyed by message kind.
- Rule: anything that changes the world happens on the server (`server*` hooks); clients only send intent and draw. Never trust a client message.
- Core files (`main.lua`, `src/net/`, `src/states/`, `src/audio/`, `src/art/`, `src/state.lua`, `src/ui.lua`, `src/car.lua`, `src/body.lua`) are shared. Only change them when a feature genuinely needs a new hook, keep the change minimal, and call it out in the pull request.
- Anything a player can equip (guns, abilities, armor, clothes, and whatever comes next) has tiers: common, uncommon, rare, legendary (`src/features/tiers`, "Tiers" in `docs/features.md`). Give new equipment `tierStats` and read its numbers through `Tiers.apply`. Consumables (health, stamina), ammo and materials have none.
- Check the file lists in this folder before creating something: if a feature or message kind with the same purpose exists, extend it instead.
- Third-party libs are vendored under `lib/`, never edited in place.
- 2-space indent, double quotes, 120-column lines (see `.stylua.toml`, `.luacheckrc`).
- Keep `love.update(dt)` frame-rate independent: always scale by `dt`.
- Assets go in `assets/<type>/` and are loaded once in `love.load`, not per frame.

## Git workflow
- `main` is release-only. Only Christiaan (@FlexoZA) merges into it, always from `staging`. Never commit or push to it directly.
- Branch from `main`: `feature/<name>` for features, `bug/<name>` for bug fixes (lowercase, hyphens: `feature/city-map`, `bug/car-spins-in-place`). Open pull requests into `staging`.
- Run `luacheck .` before pushing.
