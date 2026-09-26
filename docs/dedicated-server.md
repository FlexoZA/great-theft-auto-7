# Dedicated server

The game server with nobody at the keyboard: the same `Server` a hosting
player runs (`src/net/server.lua`), started headless on a machine of its own,
in Docker or on a cloud box. Players join it by address from the Join screen
and go straight into the running game.

## Running it

```bash
GTA7_SERVER=1 GTA7_WORLD=world love .    # or: make server WORLD=world
```

`GTA7_SERVER` makes `conf.lua` start LÖVE without a window, graphics or sound
modules and with its own save directory (`great-theft-auto-7-server`).
`main.lua` sees there is no window and hands over to `src/dedicated.lua`,
which loads the features, opens the world, starts the server at once and
forwards `love.update` and `love.quit` to it. No display or sound card is
needed; it runs over SSH or in a container.

| Variable | Meaning |
| --- | --- |
| `GTA7_SERVER=1` | Run as a dedicated server |
| `GTA7_WORLD` | Name of the saved world to run. Made on first run, continued after that. Unset: nothing is saved |
| `GTA7_NAME` | The server's name on the Join screen (default `Dedicated server`) |

Stopping it (Ctrl-C, `docker stop`, any SIGTERM) goes through `love.quit`, so
the world and everyone in it are saved first, like a host leaving.

Server settings (bot difficulty, autosave interval) are the ones a host sets
under *Settings > Server*, read from `settings.lua` in the save directory. A
dedicated server has no settings screen, so write the file by hand:

```lua
return {
  server = { botDifficulty = "hard", autosaveMinutes = 5 },
}
```

## Docker

```bash
docker build -t gta7-server .
docker run -d --name gta7 --restart unless-stopped \
  -p 22122:22122/udp -v gta7-data:/data \
  -e GTA7_WORLD=world -e GTA7_NAME="Our server" gta7-server
docker logs -f gta7
```

The image is Ubuntu 24.04 with the `love` package (11.5), about 470 MB.
`XDG_DATA_HOME=/data` puts the save directory at
`/data/love/great-theft-auto-7-server`, so the `gta7-data` volume holds the
worlds and `settings.lua`. Port 22123/udp is LAN discovery and only worth
mapping on a LAN; on the internet players type the address.

On a cloud box: any small VM does (the server idles at a few percent of one
core and about 20% with the default bots, in under 30 MB). Open UDP 22122 in
the provider's firewall and the OS one (`sudo ufw allow 22122/udp`).

## What is different from a hosted game

- Nobody is the host: no one has the Start button (the game starts by
  itself), and the host-only keys (adding and removing bots, triggering
  events) have nobody to press them.
- With no host key, `player.id` 1 is not reserved; bots take the first ids
  and the first human gets the next one. Saved worlds still know players by
  key (`docs/persistence.md`), so this changes nothing that is kept.
- Features load with no-op stand-ins for `love.graphics`, `love.audio` and
  the other modules that need a screen or a sound card, because they build
  sounds and car art in their `load` hooks. Nothing on the server path draws
  or plays; a feature that starts to would be a bug on a hosted game too.

## Not done yet

- **No authentication.** A player key is a random string in a settings
  file; anyone who has it can play as that person, and anyone who knows the
  address can join up to `Server.MAX_PLAYERS`. Fine on a LAN, a real gap on
  the internet.
- **No rate limiting** on messages, and an error in any feature's server
  hook stops the process. Docker's `--restart unless-stopped` and the
  autosave cover crashes for now.
- **Admin controls** for what the host's keys did (bots, events) and for
  server settings without editing a file.
- The default `love.run` loop sleeps one millisecond between updates. A loop
  that sleeps until the next tick would cut idle CPU further.
