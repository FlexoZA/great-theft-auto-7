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
2. **Movement sync**: clients send `{throttle, steer}` each tick. Server
   integrates all cars, broadcasts positions. Clients draw all cars.
3. **Join/leave**: spawn on connect, remove on disconnect or timeout.
4. **Polish**: client-side interpolation, host migration (maybe never), NAT
   traversal for internet play (out of scope for now).

## Message shapes (milestone 2)

```
client -> server   INPUT  <seq> <throttle> <steer>
server -> client   STATE  <tick> <id x y angle speed>...
server -> client   JOIN   <id>       / LEAVE <id>
```

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
