-- Open borders: what the "open borders" ability (abilities/openborders.lua)
-- lets loose. Cast it and twenty-five simps pour out round you, torches in
-- hand. For thirty seconds they run about near you lighting fires and
-- punch anyone who comes close, you included; each fire burns for thirty
-- seconds and hurts everything that touches it but the simps. Shoot them
-- (two pistol rounds) or run them over to thin them out.
--
-- The host runs the horde (horde.lua) and hears the cast through the
-- `serverOpenBorders` event; clients draw what they are told: simps from
-- OB_SIMPS, fires from OB_FIRE (each burns out on its own clock), flames
-- animated by fire.lua.
--
-- Messages
--   server -> all  OB_SIMPS <tick> [<id> <x> <y> <facing> <swing> <look>]...  (unreliable, 15 Hz; empty = all gone)
--   server -> all  OB_SIMP_DOWN <id> <x> <y> <angle> <playerId>   one went down (0 = nobody's kill)
--   server -> all  OB_FIRE <id> <x> <y> <seconds left>            a fire caught (also to anyone joining)
--   server -> all  OB_CLEAR                                       every simp and fire gone (a new map)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Horde = require("src.features.open-borders.horde")
local Fire = require("src.features.open-borders.fire")

local OpenBorders = { name = "open-borders" }

local SYNC_EVERY = 2 -- server ticks between OB_SIMPS packets
local SMOOTHING = 10 -- per second, easing towards the last position heard
local SNAP = 150 -- px; a jump this big is a spawn, not a step
local SKIN = { 0.90, 0.76, 0.62 }
-- Hoodies, one per `look` (Horde.LOOKS of them).
local LOOKS = {
  { 0.55, 0.2, 0.2 }, { 0.2, 0.42, 0.3 }, { 0.3, 0.3, 0.5 }, { 0.55, 0.45, 0.2 }, { 0.35, 0.35, 0.35 },
  { 0.5, 0.25, 0.45 },
}

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { horde, syncIn, simpsOut }

function OpenBorders:serverStart()
  sv = { horde = Horde.new(), syncIn = 0, simpsOut = 0 }
end

--- The ability was cast (the `serverOpenBorders` event): let them in.
function OpenBorders:serverOpenBorders(_server, caster, x, y, seconds)
  if sv then
    sv.horde:unleash(caster.id, x, y, seconds)
  end
end

--- One simp down: gibs on every screen, and the other features price it
--- (money drops a koin, the same as a pedestrian).
local function simpDown(server, kill)
  server:broadcast(Protocol.encode("OB_SIMP_DOWN", kill.id, fmt(kill.x), fmt(kill.y), ("%.3f"):format(kill.angle),
    kill.by or 0))
  Features.call("serverKill", server, { kind = "pedestrian", x = kill.x, y = kill.y, by = kill.by })
end

--- A bullet passing through (x, y): the `serverShotAt` convention. A simp
--- standing there takes it.
function OpenBorders:serverShotAt(server, x, y, radius, by, angle)
  if not sv then
    return false
  end
  local s, i = sv.horde:simpAt(x, y, radius)
  if not s then
    return false
  end
  local kill = sv.horde:hurt(i, Horde.SHOT_DAMAGE, by ~= 0 and by or nil, angle)
  if kill then
    simpDown(server, kill)
  end
  return true
end

--- Something froze the world around (x, y): simps inside stand still.
function OpenBorders:serverFreezeArea(_server, x, y, radius, seconds)
  if sv then
    sv.horde:freeze(x, y, radius, seconds)
  end
end

--- Something stinks at (x, y) (the `serverPanicArea` event, a panic fart):
--- simps inside run from it for a moment.
function OpenBorders:serverPanicArea(_server, x, y, radius)
  if sv then
    sv.horde:scare(x, y, radius, 0.5)
  end
end

--- A new map: the horde and its fires stay behind on the old one.
function OpenBorders:mapChanged(_map, server)
  if server and sv then
    sv.horde:clear()
    sv.simpsOut = 0
    server:broadcast(Protocol.encode("OB_CLEAR"))
  elseif not server then
    self.simps, self.fires = {}, {}
  end
end

--- Someone joining mid-blaze sees the fires already burning (the simps
--- arrive with the next OB_SIMPS).
function OpenBorders:serverPlayerJoined(server, player)
  if not sv then
    return
  end
  local now = sv.horde.time
  for _, f in ipairs(sv.horde.fires) do
    server:send(player, Protocol.encode("OB_FIRE", f.id, fmt(f.x), fmt(f.y), ("%.2f"):format(f.untilT - now)))
  end
end

function OpenBorders:serverStep(server, dt)
  if not sv then
    return
  end
  local horde = sv.horde
  local kills, lit = horde:step(server, dt, self)
  for _, kill in ipairs(kills) do
    simpDown(server, kill)
  end
  for _, f in ipairs(lit) do
    server:broadcast(Protocol.encode("OB_FIRE", f.id, fmt(f.x), fmt(f.y), ("%.2f"):format(Horde.FIRE_SECONDS)))
  end
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  if #horde.simps == 0 and sv.simpsOut == 0 then
    return
  end
  local parts = { server.tick }
  for _, s in ipairs(horde.simps) do
    parts[#parts + 1] = s.id
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = s.swing > 0 and 1 or 0
    parts[#parts + 1] = s.look
  end
  local msg = Protocol.encode("OB_SIMPS", unpack(parts))
  for _, player in pairs(server.players) do
    server:send(player, msg, true)
  end
  sv.simpsOut = #horde.simps
end

--- For tests.
function OpenBorders.server()
  return sv
end

-- Client --------------------------------------------------------------------

OpenBorders.simps = {} -- id -> { x, y, dx, dy, angle, swing, look, bob }
OpenBorders.fires = {} -- { id, x, y, t, seconds, seed }
OpenBorders.puffs = {} -- { x, y, t }: a simp whose time ran out, leaving
local time, lastTick = 0, 0

function OpenBorders:load()
  Fire.load()
end

function OpenBorders:exitGame()
  self.simps, self.fires, self.puffs = {}, {}, {}
  lastTick = 0
end

function OpenBorders:update(dt)
  time = time + dt
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(self.simps) do
    local ex, ey = s.x - s.dx, s.y - s.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      s.dx, s.dy = s.x, s.y
    else
      s.dx, s.dy = s.dx + ex * k, s.dy + ey * k
    end
  end
  for i = #self.fires, 1, -1 do
    local f = self.fires[i]
    f.t = f.t + dt
    if f.t >= f.seconds then
      table.remove(self.fires, i)
    end
  end
  for i = #self.puffs, 1, -1 do
    local p = self.puffs[i]
    p.t = p.t + dt
    if p.t > 0.6 then
      table.remove(self.puffs, i)
    end
  end
end

local lastWhoosh = 0

OpenBorders.clientMessages = {
  OB_SIMPS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local seen = {}
    for i = 2, #args - 5, 6 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = OpenBorders.simps[id]
        if not s then
          s = { dx = x, dy = y, bob = love.math.random() * 6 }
          OpenBorders.simps[id] = s
        end
        s.x, s.y = x, y
        s.angle = tonumber(args[i + 3]) or s.angle or 0
        s.swing = args[i + 4] == "1"
        s.look = tonumber(args[i + 5]) or 1
        seen[id] = true
      end
    end
    for id, s in pairs(OpenBorders.simps) do
      if not seen[id] then
        OpenBorders.simps[id] = nil
        OpenBorders.puffs[#OpenBorders.puffs + 1] = { x = s.dx, y = s.dy, t = 0 } -- off they go
      end
    end
  end,
  OB_SIMP_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if id then
      OpenBorders.simps[id] = nil
    end
    if x and y and Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle)
      require("src.features.pedestrians.sounds").play("splat", x, y, 0.9 + love.math.random() * 0.2)
    end
  end,
  OB_FIRE = function(_client, args)
    local id, x, y, left = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if not (id and x and y and left) or left <= 0 then
      return
    end
    local burnt = math.max(0, Horde.FIRE_SECONDS - left) -- a joiner's fire has been going a while
    OpenBorders.fires[#OpenBorders.fires + 1] = {
      id = id, x = x, y = y, t = burnt, seconds = burnt + left, seed = (id * 0.618) % 1,
    }
    if time - lastWhoosh > 0.12 then
      lastWhoosh = time -- a dozen at once is one whoosh
      Fire.play(x, y)
    end
  end,
  OB_CLEAR = function()
    OpenBorders.simps, OpenBorders.fires, OpenBorders.puffs = {}, {}, {}
  end,
}

-- Drawing ---------------------------------------------------------------------

--- Is (x, y) within `pad` of what the camera shows?
local function onScreen(camera, x, y, pad)
  if not camera then
    return true
  end
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  return math.abs(x - camera.x) <= w / 2 / s + pad and math.abs(y - camera.y) <= h / 2 / s + pad
end

function OpenBorders:drawBelowCars(_client, camera)
  for _, f in ipairs(self.fires) do
    if onScreen(camera, f.x, f.y, 80) then
      Fire.drawGround(f, Horde.FIRE_RADIUS, time)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- A simp from above: a hoodie, a head, a torch held out to one side with
--- a flame licking off it, and a fist out front while a punch lands.
local function drawSimp(s)
  local x, y, r = s.dx, s.dy, Horde.RADIUS
  local fx, fy = math.cos(s.angle), math.sin(s.angle)
  local swing = math.sin(time * 14 + s.bob) * 1.4
  local sx, sy = -fy * swing, fx * swing
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, r, 10)
  love.graphics.setColor(SKIN)
  if s.swing then
    love.graphics.circle("fill", x + fx * (r + 6), y + fy * (r + 6), 2.4, 6) -- the fist
  end
  love.graphics.circle("fill", x - fy * (r + 1) - sx, y + fx * (r + 1) - sy, 2, 6)
  -- The torch, in the right hand, pointing forward and out.
  local hx, hy = x + fy * (r + 1) + sx, y - fx * (r + 1) + sy
  local tx, ty = hx + fx * 7 + fy * 2, hy + fy * 7 - fx * 2
  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.4, 0.26, 0.12)
  love.graphics.line(hx, hy, tx, ty)
  love.graphics.setLineWidth(1)
  local flick = 0.8 + 0.4 * love.math.noise(time * 9, s.bob)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 0.45, 0.1, 0.35)
  love.graphics.circle("fill", tx, ty, 6 * flick, 10)
  love.graphics.setColor(1, 0.75, 0.25, 0.9)
  love.graphics.circle("fill", tx, ty, 2.6 * flick, 8)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(LOOKS[s.look] or LOOKS[1])
  love.graphics.circle("fill", x + sx * 0.5, y + sy * 0.5, r, 10)
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", x + fx * 2, y + fy * 2, 3.2, 8)
end

function OpenBorders:drawAboveCars(_client, camera)
  for _, f in ipairs(self.fires) do
    if onScreen(camera, f.x, f.y, 80) then
      Fire.drawFlames(f, Horde.FIRE_RADIUS, time)
    end
  end
  for _, s in pairs(self.simps) do
    if onScreen(camera, s.dx, s.dy, 30) then
      drawSimp(s)
    end
  end
  for _, p in ipairs(self.puffs) do
    local k = p.t / 0.6
    love.graphics.setColor(0.6, 0.6, 0.62, 0.5 * (1 - k))
    love.graphics.circle("fill", p.x, p.y, 6 + k * 14, 14)
  end
  love.graphics.setColor(1, 1, 1)
end

return OpenBorders
