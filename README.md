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

## Git workflow

Several people work on this repo, so nobody pushes straight to `main`.

| Branch | Purpose | Who pushes |
| --- | --- | --- |
| `main` | Stable, playable at all times | Nobody directly. Updated only by merging `staging` via a pull request |
| `staging` | Integration branch. Everything lands here first | Feature branches, via pull request |
| `feature/<name>`, `fix/<name>` | Your work in progress | You |

### Day-to-day

1. Start from an up-to-date `staging`:

   ```bash
   git checkout staging
   git pull
   git checkout -b feature/car-physics
   ```

2. Commit as you go. Run `luacheck .` and make sure `love .` still starts before you push.

3. Push your branch and open a pull request **into `staging`** (not `main`):

   ```bash
   git push -u origin feature/car-physics
   ```

4. Get one review, then merge. Delete the branch afterwards.

5. If `staging` moved while you were working, bring it in before asking for review:

   ```bash
   git fetch origin
   git rebase origin/staging
   ```

### Releasing to main

When `staging` has been played and nothing is broken, open a pull request from
`staging` into `main` and merge it. Never cherry-pick or push single commits to
`main`.

### Rules of thumb

- Small pull requests. One feature or fix each.
- Commit messages: short imperative subject line, e.g. `Add police chase AI`.
- Don't commit build output, `.love` files, or editor settings (see `.gitignore`).
- Binary assets (images, sounds) are fine to commit, but keep them small and
  put them under `assets/<type>/`.

## Layout

```
main.lua      entry point (love.load / update / draw)
conf.lua      window + module config
src/          game code (require("src.car"))
lib/          vendored third-party libraries
assets/       images, sounds, fonts, maps
```
