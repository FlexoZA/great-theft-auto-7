# Great Theft Auto 7

A top-down driving game built with [LÖVE](https://love2d.org/) 11.5 and Lua.

## Setup (Linux Mint / Ubuntu)

```bash
sudo apt install love luajit lua-check
```

Optional: `stylua` (formatter) and `lua-language-server` for editor support.
The `.luarc.json` expects the LuaLS `love2d` addon (install it via your editor's
Lua extension addon manager).

## Run

```bash
make run        # or: love .
```

## Other targets

```bash
make check      # luacheck
make fmt        # stylua
make build      # produces build/great-theft-auto-7.love
```

## Layout

```
main.lua      entry point (love.load / update / draw)
conf.lua      window + module config
src/          game code (require("src.car"))
lib/          vendored third-party libraries
assets/       images, sounds, fonts, maps
```
