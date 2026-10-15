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

Straight into a saved world, skipping the menus (handy for testing):

```bash
love . --world <slug>                # host the saved world <slug> and start it
love . --world <slug> --quest <id>   # ...and take everyone straight onto quest <id>
```

`--name <name>` plays under that name instead of `$USER`. The quest ids are listed at the top
of `src/launch.lua`.

## Controls

Press **F1** in game for the full controls overview: a keyboard with every bound key lit up,
and a list of every action, read live from your current bindings.

### Driving

| Key | Action |
| --- | --- |
| W / S (or Up / Down) | Accelerate / brake and reverse |
| A / D (or Left / Right) | Steer |
| Space | Handbrake (hold while turning to slide) |
| Shift | Boost |
| V | Horn (hold) |
| F | Get out of the car, and back in when you are standing next to one |

### On foot

| Key | Action |
| --- | --- |
| WASD | Walk (world directions; you face the cursor) |
| Shift | Sprint, until your stamina runs out |
| Space | Dodge |
| F | Action key: get in a car, open the shop, gym or job board at its door, open an ammo crate, buy a property, call a car on a car station's pad, collect a car at the impound lot, hire a park bum |

### Combat

| Key | Action |
| --- | --- |
| Left mouse | Fire toward the cursor |
| Right mouse | Sniper scope (hold); with the scout car, the tau cannon (tap, or hold to charge); cancels a readied ability |
| R | Reload |
| Z / X, mouse wheel | Previous / next weapon |
| 1 / 2 / 3 | Ability slots (also building menu options, and gym purchases 1-7 while the gym is open) |
| G | Ready a grenade (click throws it) |
| H | Use a medkit |
| J | Drink an energy drink |

### Menus, map and camera

| Key | Action |
| --- | --- |
| I | Inventory |
| P | Your vehicles |
| M | Big map (in game) / mute the music (in the menus) |
| Tab | Toggle the minimap |
| Mouse at screen edge | Pan the camera (zooms out as it drifts) |
| C | Recentre the camera |
| ` | Hide / show sight cones |
| Enter / Backspace | Accept / decline a quest offer; Enter also respawns at the picked point when dead |
| E | Ask VEX to open a locked door (Halcyon Tower) |
| Esc | Close the open panel, or pause (settings and quit are in the pause menu) |

### Debug and host

| Key | Action |
| --- | --- |
| F1 | Controls overview |
| F2 | List the cheat codes |
| F3 | Show hitboxes |
| F8 | Event menu (host only) |
| B / N | Add / remove an AI bot (host only) |

Every action can be rebound under *Settings > Controls*, with a primary and a secondary
binding each; weapon slots 1-4 have no key by default but can be bound there too. The other
Settings tabs are *Sound* (volumes), *Video* (display mode, window size, VSync, FPS counter,
screen shake, menu scanlines) and *Server* (bot difficulty, for when you host). Settings can be
opened from the main menu or the pause menu, and are saved to the LÖVE save directory.

*Inclusive mode*, the toggle at the top right of the main menu, gives the menu face dark skin
and swaps the metal theme for a boom-bap hip-hop one. It is saved with everything else.

Click the version label on the main menu to read *what's new* (the changelog).

## Multiplayer (LAN)

One player hosts, everyone else joins. Both need to be on the same network.

- **Host**: enter your name, click *Host LAN game*, start a new world or continue a saved one,
  wait for players, click *Start game*. Worlds are saved on the host's machine, so everyone
  gets their money, loadout and upgrades back next time ([docs/persistence.md](docs/persistence.md)).
  Players can also join a game that is already running.
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
make audit      # rate this branch out of 10 against staging (docs/audit.md)
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

2. Commit as you go. Before you push, run `luacheck .` and `make audit` (GitHub runs the audit
   on every pull request into `staging` and it must pass), and make sure `love .` still starts.
   Add a line for players under `## [Unreleased]` in `CHANGELOG.md` for anything noticeable.

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
src/features/     one folder per gameplay feature (yours go here, see docs/features.md)
src/features/init.lua   the registry (features are discovered automatically)
src/controls.lua  rebindable key bindings
src/settings.lua  saved settings; settings_panel.lua draws the Settings screen
src/saves.lua     saved worlds
src/launch.lua    --world / --quest launch options
src/art/          pixel-art helpers, the 7 logo, the menu face and backdrop
src/audio/        synth engine, the two menu themes, playback
src/state.lua     scene switcher
src/states/       menu, worlds (host), browser (join), lobby, game, settings, changelog
src/net/          protocol, discovery, server, client, init (session)
src/ui.lua        buttons and text fields
src/car.lua       car physics, hitbox and drawing
lib/              vendored third-party libraries
assets/           images, sounds, fonts, maps
```
