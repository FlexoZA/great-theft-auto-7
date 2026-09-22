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

## Controls

| Key | Action |
| --- | --- |
| Arrows / WASD | Drive |
| Left mouse | Fire toward the cursor |
| Mouse at screen edge | Pan the camera (zooms out as it drifts) |
| C | Recentre the camera on your car |
| F1 | Show hitboxes |
| Esc | Leave the game |

## Multiplayer (LAN)

One player hosts, everyone else joins. Both need to be on the same network.

- **Host**: enter your name, click *Host LAN game*, wait for players, click *Start game*.
- **Join**: click *Join LAN game*. Hosts on the network appear within a second or two.
  If none show up, type the host's IP address and click *Connect*.
- The host must allow UDP ports **22122** (game) and **22123** (discovery) through
  their firewall. On Ubuntu/Mint: `sudo ufw allow 22122:22123/udp`.
- Testing alone: run `love .` twice on one machine. Host in one, join in the other.

Design and roadmap: [docs/networking.md](docs/networking.md).

## Other targets

```bash
make check      # luacheck
make fmt        # stylua
make build      # produces build/great-theft-auto-7.love
```

## Git workflow

Several people work on this repo, so nobody pushes straight to `main`.

| Branch | Purpose | Who merges into it |
| --- | --- | --- |
| `main` | Stable, playable at all times. Your starting point for new work | **Christiaan (@FlexoZA) only**, by merging `staging` |
| `staging` | Integration branch. All work lands here first | Any developer, via a reviewed pull request |
| `feature/<name>`, `bug/<name>` | Your work in progress | You |

### New developer, first time

```bash
git clone git@github.com:FlexoZA/great-theft-auto-7.git
cd great-theft-auto-7
sudo apt install love luajit lua-check   # Linux Mint / Ubuntu
love .                                    # make sure it runs
```

### Day-to-day

1. Branch from an up-to-date `main`. Use `feature/<name>` for new things and
   `bug/<name>` for fixes, lowercase with hyphens:

   ```bash
   git checkout main
   git pull
   git checkout -b feature/city-map
   ```

2. Commit as you go. Run `luacheck .` and make sure `love .` still starts before you push.

3. Push your branch and open a pull request **into `staging`** (never `main`):

   ```bash
   git push -u origin feature/city-map
   ```

4. Get one review, then merge into `staging`. Delete your branch afterwards.

5. If the pull request shows conflicts with `staging`, bring it in and push again:

   ```bash
   git fetch origin
   git merge origin/staging
   ```

### Releasing to main

Only Christiaan merges `staging` into `main`, after playing the staging build
and confirming nothing is broken. This is done with a pull request from
`staging` into `main`. Nobody else opens or merges that pull request, and
nobody cherry-picks or pushes single commits to `main`.

### Rules of thumb

- Small pull requests. One feature or fix each.
- Commit messages: short imperative subject line, e.g. `Add police chase AI`.
- Don't commit build output, `.love` files, or editor settings (see `.gitignore`).
- Binary assets (images, sounds) are fine to commit, but keep them small and
  put them under `assets/<type>/`.

## Layout

```
main.lua        entry point, forwards LÖVE callbacks to the current state
conf.lua        window + module config
src/state.lua   scene switcher
src/states/     menu, browser (join), lobby, game
src/net/        protocol, discovery, server, client, init (session)
src/ui.lua      buttons and text fields
src/car.lua     the car
lib/          vendored third-party libraries
assets/       images, sounds, fonts, maps
```
