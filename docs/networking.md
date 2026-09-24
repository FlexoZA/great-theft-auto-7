# Networking design

## Decision

**Client/server over ENet, with one player acting as host.** Both pieces are
built into LÖVE 11.5 (verified: `enet` 1.3.13 and `luasocket` 3.0), so there is
nothing to vendor or install.

| Need | Choice | Why |
| --- | --- | --- |
| Transport | `require("enet")` | UDP with optional reliable/ordered channels. Built for games, built into LÖVE. |
| Topology | Host-authoritative | One player runs the server inside their game. Server owns the world state; clients send inputs and render what the server tells them. Simplest way to avoid cheating and desync. |
| LAN discovery | `require("socket")` UDP broadcast | ENet can't broadcast. The host answers a "who's hosting?" broadcast on a fixed port so clients get a join list without typing IPs. |
| Serialization | Plain `string.pack`-free text for the first milestone, then a vendored [bitser](https://github.com/gvx/bitser) or MessagePack once the message set is stable | Keep it debuggable first. |
| Tick rate | Server 30 Hz, client input 30 Hz, rendering unlocked | Enough for a driving game on LAN. Add interpolation on clients later. |

## Rejected

- **Peer-to-peer / lockstep**: every client simulates everything, needs
  deterministic physics. Lua floats across machines make this fragile.
- **LuaSocket TCP**: head-of-line blocking hurts real-time movement. Fine for
  lobby chat later, not for state.
- **External servers (noobhub, websockets)**: needs a Node process or similar.
  Overkill for LAN.

## Milestones

1. **Lobby** (done): Host button starts an ENet server on `0.0.0.0:22122` and a UDP
   discovery responder on `22123`. Join button broadcasts, lists hosts, connects.
2. **Movement sync** (done): clients send `{throttle, steer}` each tick. Server
   integrates all cars, broadcasts positions. Clients draw all cars.
3. **Join/leave** (done): players can join a running game. The server sends
   the newcomer every car (`VEHICLE`) and the names of those who left
   (`KNOWN`), spawns them at the free-est map spawn point, lets features send
   their state in `serverPlayerJoined`, then sends `START`. Someone who leaves
   takes their body with them; their own car stays parked, still theirs.
   Saved worlds build on this, see `persistence.md`.
4. **Polish**: client-side prediction for the local car (right now your own
   car is drawn from server snapshots too, so remote players feel one
   round-trip plus one tick behind their keys), host migration (maybe never),
   NAT traversal for internet play (out of scope for now).

## How movement sync works (milestone 2)

- On Start the server gives every player a body and a `Car` of their own,
  lined up along x at `SPAWN_SPACING` intervals around the origin, facing
  up, and seats them.
- Server steps the simulation at a fixed 30 Hz (`Server.TICK`) with an
  accumulator, applying each driver's latest input to the car they are in
  (a parked car rolls to a stop), then sends one `STATE` packet per tick on
  channel 1, unreliable. ENet drops packets that arrive out of order, and
  the client also ignores any tick older than the last.
- Clients send `INPUT <seq> <throttle> <steer>` at 30 Hz on channel 1,
  unreliable. The server ignores sequence numbers that go backwards.
- Clients keep the latest snapshot as the target and ease the drawn position
  toward it (`SMOOTHING` in `src/states/game.lua`). Cars missing from a
  snapshot are removed.

## Message shapes

```
client -> server   INPUT        <seq> <throttle> <steer> <handbrake>
server -> client   STATE        <tick> <n> [<vid> <x> <y> <angle> <speed> <driver>]... [<id> <x> <y> <facing>]...
server -> client   VEHICLE      <vid> <owner> <color>      a car entered the world (owner 0 = nobody's)
server -> client   VEHICLE_GONE <vid>
server -> client   JOIN         <id> <name>  / LEAVE <id>
server -> client   KNOWN        <id> <name>          someone who left earlier; client:nameOf(id) finds them
```

The world is people and cars. STATE lists every car in the world with who
is driving it (0 = parked), then every player on foot; a player in neither
list is out of the world for the moment (wrecked). Clients keep what
VEHICLE said about a car's owner and colour, since a wreck drops out of
STATE and comes back.

Use ENet channel 0 (reliable) for JOIN/LEAVE, channel 1 (unsequenced) for
INPUT and STATE. Latest state wins; never queue old snapshots.

## Code layout

```
src/net/server.lua     ENet host, tick loop, world authority
src/net/client.lua     connect, send input, receive state
src/net/discovery.lua  UDP broadcast / respond
src/net/protocol.lua   encode/decode messages
```

The `love.update` in `main.lua` calls `server:update(dt)` when hosting and
`client:update(dt)` always (the host is also a client of itself).
