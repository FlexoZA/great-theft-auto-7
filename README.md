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
| Space | Handbrake (hold while turning to slide) |
| Left mouse | Fire toward the cursor |
| Mouse at screen edge | Pan the camera (zooms out as it drifts) |
| C | Recentre the camera on your car |
| F1 | Show hitboxes |
| Tab | Toggle the minimap |
| B / N | Add / remove an AI bot (host only) |
| Esc | Leave the game |

Every key above can be rebound under *Settings > Controls*, with a primary and a secondary
binding per action. Volumes are under *Settings > Sound*, and display mode, window size,
VSync, FPS counter, screen shake and menu scanlines under *Settings > Video*. All are saved to
the LÖVE save directory.

*Inclusive mode*, the toggle at the top right of the main menu, gives the menu face dark skin
and swaps the metal theme for a boom-bap hip-hop one. It is saved with everything else.

## Multiplayer (LAN)

One player hosts, everyone else joins. Both need to be on the same network.

- **Host**: enter your name, click *Host LAN game*, wait for players, click *Start game*.
- **Join**: click *Join LAN game*. Hosts on the network appear within a second or two.
  If none show up, type the host's IP address and click *Connect*.
- The host must allow UDP ports **22122** (game) and **22123** (discovery) through
  their firewall. On Ubuntu/Mint: `sudo ufw allow 22122:22123/udp`.
- The city is generated from a fixed seed in `src/features/city-map/layout.lua`, so it is
  identical on every machine without sending anything.
- Testing alone: run `love .` twice on one machine. Host in one, join in the other.
  Or just host and press Start: one AI bot cruises the city (B adds more). Bots are peaceful
  until you shoot or ram them, then they hunt you for a while. Two police cars patrol too:
  shoot, ram or run someone over where they can see it and you're wanted until the heat dies.
  With inclusive mode on you start the game wanted, so shake the police first.

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
main.lua          entry point, loads features, forwards LÖVE callbacks
conf.lua          window + module config
src/features/     one folder per gameplay feature (yours go here)
src/features/init.lua   the registry
src/art/          pixel-art helpers, the 7 logo, the menu face and backdrop
src/audio/        synth engine, the two menu themes, playback
src/state.lua     scene switcher
src/states/       menu, browser (join), lobby, game
src/net/          protocol, discovery, server, client, init (session)
src/ui.lua        buttons and text fields
src/car.lua       car physics, hitbox and drawing
lib/              vendored third-party libraries
assets/           images, sounds, fonts, maps
```
