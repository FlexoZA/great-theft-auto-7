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
- Third-party libs are vendored under `lib/`, never edited in place.
- 2-space indent, double quotes, 120-column lines (see `.stylua.toml`, `.luacheckrc`).
- Keep `love.update(dt)` frame-rate independent: always scale by `dt`.
- Assets go in `assets/<type>/` and are loaded once in `love.load`, not per frame.

## Git workflow
- `main` is release-only. Only Christiaan (@FlexoZA) merges into it, always from `staging`. Never commit or push to it directly.
- Branch from `main` (`feature/<name>` or `fix/<name>`) and open pull requests into `staging`.
- Run `luacheck .` before pushing.
