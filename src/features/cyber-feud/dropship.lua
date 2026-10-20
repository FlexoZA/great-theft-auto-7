-- Halcyon's dropship over the Roof (docs/cyber-feud.md, "On the Roof"):
-- while VEX has the roof she calls it in, every so often, to put troops
-- down by the relay players are going for. A tiltrotor with rockets where
-- the rotors would be, in Halcyon's military paint: a matte olive-grey hull
-- in two tones with its panel lines, sponsons down its sides, a chin gun,
-- hazard stripes on its ramp, a stencilled number and a small magenta
-- company roundel, a high wing, a V tail, and at each wingtip a nacelle
-- that tilts from flying flat out
-- (its rocket's flame trailing behind) to hanging over the roof (pointing
-- down, a blue-white jet scorching the ground).
--
-- It comes in from off the roof at a relay left (`target`: the one furthest
-- along, else the one nearest a player), the spot it will set down on ringed
-- in magenta on the ground all the way in. It slows, tilts its rockets down
-- and sinks to `hover`, opens its ramp, and `squad` of Halcyon's officers
-- (troops.lua's `serverPack`) rope down by the relay and walk a beat round
-- it; with them comes one of Cyber Feud's harder units, taking turns
-- (`specials`): an assassin droid walking the beat with them (droids.lua,
-- dodging), an enforcer planting his riot shield by the relay facing out
-- (enforcers.lua), or a brute (brutes.lua); from the second drop on one of
-- the officers is an elite (troops.lua's `serverElite`). After `hold` s it climbs, tilts flat and flies on, off the
-- roof. It comes again `every` s after the last one left, while fewer than
-- `most` of what it brought are still up (`Bosses.plus` for both: more
-- humans, more); and whenever a relay falls with none in the air, it comes
-- at once, whatever its wait or how many are up.
-- It can't be shot: it is VEX's call, not a fight of its own.
--
-- troops.lua starts, steps and stops it with VEX and draws it over
-- everything on the ground; init.lua loads its engine.
--
-- Messages
--   server -> all  DS_STATE <tick> [<x> <y> <angle> <altitude> <tilt> <phase> <sx> <sy>]
--                  (unreliable, 15 Hz; just the tick: none; tilt 0 flat out .. 1 hanging; phase
--                  0 coming in, 1 dropping, 2 leaving; (sx, sy) the spot it sets down on)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Sounds = require("src.features.cyber-feud.flyer_sounds")

local Dropship = {}

-- Tuning ------------------------------------------------------------------
Dropship.firstIn = 12 -- seconds after VEX takes the roof before the first one
Dropship.every = 35 -- seconds after one leaves before the next comes
Dropship.squad = 3 -- officers a drop, for one human
Dropship.most = 5 -- of what it brought up at once before it stops coming, for one human
Dropship.speed = 460 -- px/s flat out
Dropship.from = 1500 -- px off the relay it starts from, and flies on to before it is gone
Dropship.cruise = 150 -- px up flying in and out (its shadow falls this far)
Dropship.hover = 46 -- px up over the drop
Dropship.hold = 4 -- seconds over the drop
Dropship.ropeAt = 1.2 -- seconds into the hold the officers are down
Dropship.off = 130 -- px from the relay, towards the middle of the roof, that it sets down at
Dropship.guard = 120 -- px round the relay the officers walk
Dropship.specials = { "droid", "enforcer", "brute" } -- the harder one with each drop, in turn

local SYNC = 1 / 15
local SMOOTHING = 8
local SNAP = 400
local STALE = 1
local SCALE = 1.6

local WHITE = { 0.86, 0.88, 0.90 }
local HULL = { 0.52, 0.56, 0.46 } -- matte olive-grey (light enough to read over the roof at night)
local CAMO = { 0.41, 0.45, 0.37 } -- its second tone
local HULL_DARK = { 0.30, 0.33, 0.28 }
local PANEL = { 0.22, 0.24, 0.20 } -- panel lines
local HAZARD = { 0.92, 0.72, 0.14 }
local STENCIL = { 0.80, 0.82, 0.76 }
local MAGENTA = { 1.00, 0.24, 0.78 }
local GLASS = { 0.10, 0.13, 0.10 }
local JET = { 0.55, 0.78, 1.00 }
local CORE = { 0.92, 0.97, 1.00 }
local FLAME = { 1.00, 0.55, 0.20 }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function wrap(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

local function troops()
  return require("src.features.cyber-feud.troops")
end

--- The harder unit with drop `n` (Dropship.specials, in turn), set down at
--- (x, y) by relay `r` with the officers' `beat`. Returns it, or nil.
local function special(n, x, y, r, beat)
  local kind = Dropship.specials[(n - 1) % #Dropship.specials + 1]
  if kind == "droid" then
    return require("src.features.cyber-feud.droids").serverJoin(x, y, beat)
  elseif kind == "enforcer" then -- holding the ground between the relay and whoever comes, facing out
    return require("src.features.cyber-feud.enforcers").serverJoin(x, y, math.atan2(y - r.y, x - r.x))
  elseif kind == "brute" then
    local Brutes = require("src.features.cyber-feud.brutes")
    local b = Brutes.serverJoin(x, y, beat, 1)
    Brutes.serverWake()
    return b
  end
end

-- Server --------------------------------------------------------------------

local sv = nil -- { ship, nextIn, brought, syncIn, drops, fallen, rush }

function Dropship.serverStart()
  sv = { ship = nil, nextIn = nil, brought = {}, syncIn = 0, drops = 0, fallen = 0, rush = false }
end

function Dropship.serverStop(server)
  if sv and sv.ship and server then
    server:broadcast(Protocol.encode("DS_STATE", server.tick))
  end
  sv = nil
end

--- What it brought that is still up.
local function up()
  local n = 0
  for i = #sv.brought, 1, -1 do
    if sv.brought[i].hp > 0 then
      n = n + 1
    else
      table.remove(sv.brought, i)
    end
  end
  return n
end

--- The relay to defend: the one furthest along, else the one nearest a player.
local function target(server, vex)
  local best, bestScore
  for i, r in ipairs(vex.relays) do
    if not r.done then
      local near = math.huge
      for _, p in pairs(server.players) do
        if Features.present(p) then
          local x, y = Features.bodyPose(server, p)
          near = math.min(near, dist2(x, y, r.x, r.y))
        end
      end
      local score = near - r.progress * 1e9
      if not bestScore or score < bestScore then
        best, bestScore = i, score
      end
    end
  end
  return best and vex.relays[best]
end

--- Send one in at relay `r`, setting down towards (cx, cy) from it.
local function launch(r, cx, cy)
  local toMid = math.atan2(cy - r.y, cx - r.x)
  local sx, sy = r.x + math.cos(toMid) * Dropship.off, r.y + math.sin(toMid) * Dropship.off
  local come = toMid + math.pi / 2 + (random() - 0.5) * 1.2 -- in from one side, across the roof
  local x, y = sx - math.cos(come) * Dropship.from, sy - math.sin(come) * Dropship.from
  sv.ship = {
    x = x, y = y, angle = come, alt = Dropship.cruise, tilt = 0, phase = 0, t = 0, dropped = false,
    sx = sx, sy = sy, relay = r,
  }
end

--- The officers rope down: a pack of Halcyon's onto a beat round the relay.
local function drop(server, s)
  local r = s.relay
  local g = Dropship.guard
  local beat = {
    { x = r.x + g, y = r.y }, { x = r.x, y = r.y + g }, { x = r.x - g, y = r.y }, { x = r.x, y = r.y - g },
  }
  local T = troops()
  T.serverWake()
  local pack = T.serverPack(server, "halcyon", { x = s.sx, y = s.sy }, beat, Bosses.plus(Dropship.squad, server),
    false, r.x, r.y)
  for _, m in ipairs(pack) do
    sv.brought[#sv.brought + 1] = m
  end
  sv.drops = sv.drops + 1
  local k = math.atan2(s.sy - r.y, s.sx - r.x)
  local unit = special(sv.drops, s.sx + math.cos(k) * 40, s.sy + math.sin(k) * 40, r, beat)
  if unit then
    sv.brought[#sv.brought + 1] = unit
  end
  if sv.drops == 1 then
    server:broadcast(Protocol.encode("CF_BEAT", "roof.dropship"))
  elseif pack[1] then
    T.serverElite(pack[1]) -- from the second drop on, one of them is an elite
  end
end

local function fly(s, dt)
  local dx, dy = s.sx - s.x, s.sy - s.y
  local d = math.sqrt(dx * dx + dy * dy)
  if s.phase == 0 then -- coming in: slowing, tilting down and sinking as it gets there
    s.angle = s.angle + wrap(math.atan2(dy, dx) - s.angle) * math.min(1, dt * 2)
    local speed = math.max(40, math.min(Dropship.speed, d * 1.1))
    local step = math.min(d, speed * dt)
    if d > 0 then
      s.x, s.y = s.x + dx / d * step, s.y + dy / d * step
    end
    local near = math.max(0, math.min(1, 1 - (d - 60) / 400))
    s.tilt = s.tilt + (near - s.tilt) * math.min(1, dt * 3)
    s.alt = Dropship.cruise + (Dropship.hover - Dropship.cruise) * near
    if d < 6 then
      s.phase, s.t, s.tilt, s.alt = 1, 0, 1, Dropship.hover
    end
  elseif s.phase == 1 then -- over the drop
    s.t = s.t + dt
    return s.t >= Dropship.ropeAt and not s.dropped
  else -- leaving: climbing, tilting flat, faster and faster, on the way it was facing
    s.t = s.t + dt
    s.tilt = math.max(0, s.tilt - dt * 0.8)
    s.alt = math.min(Dropship.cruise, s.alt + dt * 70)
    local speed = Dropship.speed * math.min(1, 0.15 + s.t * 0.4)
    s.x, s.y = s.x + math.cos(s.angle) * speed * dt, s.y + math.sin(s.angle) * speed * dt
  end
  return false
end

--- Every host tick from troops.lua, with VEX's state (`Vex.server()`).
function Dropship.serverStep(server, dt, vex)
  if not sv then
    return
  end
  if not (vex and vex.stage == "on") then
    if sv.ship then
      sv.ship = nil
      server:broadcast(Protocol.encode("DS_STATE", server.tick))
    end
    sv.nextIn = nil
    return
  end
  local fallen = 0
  for _, r in ipairs(vex.relays) do
    fallen = fallen + (r.done and 1 or 0)
  end
  if fallen > sv.fallen then -- a relay fell: with none in the air, it comes now
    sv.fallen = fallen
    if not sv.ship then
      sv.nextIn, sv.rush = 0, true
    end
  end
  local s = sv.ship
  if not s then
    sv.nextIn = (sv.nextIn or Dropship.firstIn) - dt
    if sv.nextIn <= 0 and (sv.rush or up() < Bosses.plus(Dropship.most, server)) then
      sv.rush = false
      local r = target(server, vex)
      if r then
        local cx, cy = 0, 0 -- the middle of the relays: the helipad's
        for _, q in ipairs(vex.relays) do
          cx, cy = cx + q.x / #vex.relays, cy + q.y / #vex.relays
        end
        launch(r, cx, cy)
      end
    end
  else
    if fly(s, dt) then
      s.dropped = true
      drop(server, s)
    end
    if s.phase == 1 and s.t >= Dropship.hold then
      s.phase, s.t = 2, 0
    end
    if s.phase == 2 and dist2(s.x, s.y, s.sx, s.sy) > Dropship.from ^ 2 then
      sv.ship, sv.nextIn = nil, Dropship.every
      server:broadcast(Protocol.encode("DS_STATE", server.tick))
      return
    end
  end
  sv.syncIn = sv.syncIn - dt
  if sv.ship and sv.syncIn <= 0 then
    sv.syncIn = SYNC
    local sh = sv.ship
    server:broadcast(Protocol.encode("DS_STATE", server.tick, fmt(sh.x), fmt(sh.y), ("%.3f"):format(sh.angle),
      fmt(sh.alt), ("%.2f"):format(sh.tilt), sh.phase, fmt(sh.sx), fmt(sh.sy)))
  end
end

--- For tests.
function Dropship.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = nil -- { x, y, angle, alt, tilt, phase, sx, sy, dx, dy, da, dalt, dtilt }
local lastTick, heardAt, clock = 0, 0, 0
local engine = nil

function Dropship.clear()
  shown, lastTick = nil, 0
  if engine then
    engine:stop()
    engine = nil
  end
end

function Dropship.update(dt)
  clock = clock + dt
  if shown and love.timer.getTime() - heardAt > STALE then
    Dropship.clear()
  end
  if not shown then
    return
  end
  local k = math.min(1, dt * SMOOTHING)
  local ex, ey = shown.x - shown.dx, shown.y - shown.dy
  if ex * ex + ey * ey > SNAP * SNAP then
    shown.dx, shown.dy = shown.x, shown.y
  else
    shown.dx, shown.dy = shown.dx + ex * k, shown.dy + ey * k
  end
  shown.da = shown.da + wrap(shown.angle - shown.da) * k
  shown.dalt = shown.dalt + (shown.alt - shown.dalt) * k
  shown.dtilt = shown.dtilt + (shown.tilt - shown.dtilt) * k
  if not engine then
    engine = Sounds.loop("dropship")
  end
  if engine then
    Sounds.place(engine, shown.dx, shown.dy, 0.9 + 0.2 * shown.dtilt)
  end
end

--- Its outline in its own frame (x forward, 1 = a pixel at SCALE), for the
--- hull and its shadow.
local function silhouette(fill)
  love.graphics.polygon("fill", 58, 0, 48, -9, -40, -12, -60, -6, -60, 6, -40, 12, 48, 9) -- the fuselage
  love.graphics.rectangle("fill", -34, -17, 52, 34, 6, 6) -- the sponsons down its sides
  love.graphics.rectangle("fill", -14, -66, 26, 132) -- the wing
  love.graphics.polygon("fill", -48, -10, -66, -30, -72, -28, -60, -6) -- the V tail
  love.graphics.polygon("fill", -48, 10, -66, 30, -72, 28, -60, 6)
  if fill then
    fill()
  end
end

--- A rocket nacelle at (0, y): flat out its flame trails behind it; hanging,
--- its jet points down, a ring of blue-white under it.
local function nacelle(y, tilt)
  local flick = 0.8 + 0.2 * math.sin(clock * 47 + y)
  if tilt < 0.95 then -- the flame behind, shorter as it tilts down
    local len = (40 + 10 * flick) * (1 - tilt)
    love.graphics.setColor(FLAME[1], FLAME[2], FLAME[3], 0.55 * (1 - tilt))
    love.graphics.polygon("fill", -20, y - 8, -20 - len, y, -20, y + 8)
    love.graphics.setColor(JET[1], JET[2], JET[3], 0.9 * (1 - tilt))
    love.graphics.polygon("fill", -20, y - 4.5, -20 - len * 0.6, y, -20, y + 4.5)
  end
  love.graphics.setColor(HULL_DARK)
  local length = 40 - 18 * tilt -- tilting down, it shows more of its end than its side
  love.graphics.rectangle("fill", -length / 2, y - 11, length, 22, 5, 5)
  love.graphics.setColor(CAMO)
  love.graphics.rectangle("fill", -length / 2 + 4, y - 7, length - 8, 14, 3, 3)
  love.graphics.setColor(PANEL)
  love.graphics.rectangle("fill", length / 2 - 6, y - 11, 2, 22) -- its intake ring
  love.graphics.rectangle("fill", -length / 2, y - 11, 3, 22) -- the nozzle
  if tilt > 0.05 then -- the jet straight down: a hot ring at its mouth
    love.graphics.setColor(JET[1], JET[2], JET[3], 0.7 * tilt)
    love.graphics.circle("fill", 0, y, 12 * flick, 16)
    love.graphics.setColor(CORE[1], CORE[2], CORE[3], 0.95 * tilt)
    love.graphics.circle("fill", 0, y, 6 * flick, 12)
  end
end

--- Drawn over everything on the ground: the spot it sets down on, its jets'
--- wash there, its shadow, and it.
function Dropship.drawAboveCars()
  local s = shown
  if not s then
    return
  end
  local x, y, a, alt, tilt = s.dx, s.dy, s.da, s.dalt, s.dtilt
  if s.phase < 2 then -- where its troops will come down: keep an eye on it
    local pulse = 0.5 + 0.5 * math.abs(math.sin(clock * 4))
    love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.35 + 0.35 * pulse)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", s.sx, s.sy, 46, 40)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.12 + 0.1 * pulse)
    love.graphics.circle("fill", s.sx, s.sy, 46, 40)
  end
  if tilt > 0.3 then -- its jets' wash on the roof, rippling out
    for i = 0, 2 do
      local k = (clock * 1.4 + i / 3) % 1
      love.graphics.setColor(JET[1], JET[2], JET[3], 0.25 * (1 - k) * tilt * (1 - alt / Dropship.cruise))
      love.graphics.circle("line", x, y, 40 + k * 110, 40)
    end
  end
  love.graphics.push()
  love.graphics.translate(x + alt * 0.55, y + alt * 0.75) -- its shadow, further off the higher it is
  love.graphics.rotate(a)
  love.graphics.scale(SCALE)
  love.graphics.setColor(0, 0, 0, 0.3)
  silhouette()
  love.graphics.pop()

  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(a)
  love.graphics.scale(SCALE * (1 + alt / 900)) -- nearer the camera the higher it is
  love.graphics.setColor(HULL)
  silhouette(function()
    love.graphics.setColor(CAMO) -- the second tone, in broad angular patches
    love.graphics.polygon("fill", 30, -9, 10, -12, -6, 12, 14, 10)
    love.graphics.polygon("fill", -24, -15, -40, -12, -50, 6, -30, 15)
    love.graphics.polygon("fill", -14, -66, 12, -66, 12, -44, -14, -30)
    love.graphics.polygon("fill", -14, 40, 12, 26, 12, 66, -14, 66)
    love.graphics.setColor(HULL_DARK)
    love.graphics.rectangle("fill", 7, -66, 5, 132) -- the wing's leading edge, in its shade
    love.graphics.setColor(PANEL) -- panel lines
    love.graphics.setLineWidth(0.8)
    love.graphics.line(40, -9, 40, 9)
    love.graphics.line(18, -17, 18, 17)
    love.graphics.line(-34, -17, -34, 17)
    love.graphics.line(-14, -66, -14, 66)
    love.graphics.line(-1, -66, -1, -14)
    love.graphics.line(-1, 14, -1, 66)
    love.graphics.line(-50, -8, -50, 8)
    love.graphics.rectangle("line", -26, -15, 14, 8) -- its side doors
    love.graphics.rectangle("line", -26, 7, 14, 8)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(GLASS)
    love.graphics.polygon("fill", 54, 0, 46, -6, 34, -6, 34, 6, 46, 6) -- the canopy, armoured slits
    love.graphics.setColor(0.45, 0.55, 0.35, 0.45)
    love.graphics.polygon("fill", 50, -2, 46, -4, 38, -4, 40, -2)
    love.graphics.setColor(HULL_DARK) -- the chin gun, under the nose
    love.graphics.circle("fill", 50, 0, 3.5, 10)
    love.graphics.setColor(PANEL)
    love.graphics.rectangle("fill", 52, -1, 12, 2)
    love.graphics.setColor(MAGENTA) -- Halcyon's roundel, small, on each wing
    love.graphics.circle("fill", 0, -50, 4, 12)
    love.graphics.circle("fill", 0, 50, 4, 12)
    love.graphics.setColor(HULL)
    love.graphics.circle("fill", 0, -50, 1.8, 10)
    love.graphics.circle("fill", 0, 50, 1.8, 10)
    love.graphics.setColor(STENCIL) -- its number, stencilled across the wing root
    for i, bar in ipairs({ 3, 1, 3, 2 }) do
      love.graphics.rectangle("fill", -10 + i * 3, -36, 1.6, bar * 2.5)
      love.graphics.rectangle("fill", -10 + i * 3, 30 + (3 - bar) * 2.5, 1.6, bar * 2.5)
    end
    love.graphics.setColor(HAZARD) -- hazard stripes across the ramp
    for i = 0, 3 do
      love.graphics.polygon("fill", -58, -6 + i * 3.5, -58, -4.5 + i * 3.5, -52, -3 + i * 3.5, -52, -4.5 + i * 3.5)
    end
  end)
  if s.phase == 1 then -- the ramp down, the bay lit red, as for a drop at night
    love.graphics.setColor(0.95, 0.25, 0.2, 0.8)
    love.graphics.rectangle("fill", -64, -6, 8, 12)
  end
  nacelle(-66, tilt)
  nacelle(66, tilt)
  local blink = math.floor(clock * 2) % 2 == 0
  love.graphics.setColor(1, 0.15, 0.12, blink and 1 or 0.3) -- port, red
  love.graphics.circle("fill", 0, -60, 2.5, 8)
  love.graphics.setColor(0.2, 1, 0.4, blink and 1 or 0.3) -- starboard, green
  love.graphics.circle("fill", 0, 60, 2.5, 8)
  if math.floor(clock * 1.3) % 3 == 0 and clock * 1.3 % 1 < 0.15 then -- the white strobe on its tail
    love.graphics.setColor(1, 1, 1)
    love.graphics.circle("fill", -60, 0, 3, 8)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

function Dropship.drawNightLights(glow)
  local s = shown
  if not s then
    return
  end
  local c, sn = math.cos(s.da), math.sin(s.da)
  local span = 66 * SCALE
  for _, side in ipairs({ -1, 1 }) do -- its rockets
    glow(s.dx - sn * span * side, s.dy + c * span * side, 60 + 60 * s.dtilt, JET, 0.5 + 0.4 * s.dtilt)
  end
  glow(s.dx, s.dy, 120, WHITE, 0.25)
  if s.phase < 2 then
    glow(s.sx, s.sy, 80, MAGENTA, 0.4)
  end
end

Dropship.clientMessages = {
  DS_STATE = function(_client, args)
    local tick = tonumber(args[1]) or 0
    if tick < lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local x = tonumber(args[2])
    if not x then
      Dropship.clear()
      lastTick = tick
      return
    end
    local y, a, alt, tilt = tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    local phase, sx, sy = tonumber(args[7]) or 0, tonumber(args[8]) or x, tonumber(args[9]) or y
    if not shown then
      shown = { dx = x, dy = y, da = a, dalt = alt, dtilt = tilt }
    end
    shown.x, shown.y, shown.angle, shown.alt, shown.tilt = x, y, a, alt, tilt
    shown.phase, shown.sx, shown.sy = phase, sx, sy
  end,
}

return Dropship
