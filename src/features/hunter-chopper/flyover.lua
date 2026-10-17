-- A Hunter-Chopper passing over: another feature's boss calling one in
-- to drop something on the players (`HunterChopper:serverFlyover`: the
-- Antlion Guard has it drop rollermines). It is not the Outer City's boss:
-- no gun, no health bar, nothing to shoot down. It comes in low from where
-- it was sent (off behind whoever it is after, so it comes at them from
-- their back), flies straight at them, turning to follow them no faster than
-- `turnRate`, lets its cargo go as it passes over them and flies on until it
-- is `past` px beyond, where it is gone.
--
-- Its cargo is another feature's to set down: `{ feature, count, spread }`,
-- each one let go `spread` px apart along its line and landing `fall` s later,
-- where that feature's `serverSummon(server, x, y, 1, 10)` sets it down
-- (rollermines: already awake). Every screen sees each one falling, a steel
-- ball with its shadow closing in, onto a ring on the ground.
--
-- Messages
--   server -> all  HC_PASS <tick> (<id> <x> <y> <angle>)...   (unreliable, 15 Hz; an empty list: none)
--   server -> all  HC_CARGO <x> <y> <fall>                    one of its cargo falling onto (x, y)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Render = require("src.features.hunter-chopper.render")
local Sounds = require("src.features.hunter-chopper.sounds")

local Flyover = {}

-- Tuning ------------------------------------------------------------------
Flyover.speed = 300 -- px a second
Flyover.turnRate = 1.2 -- radians a second it turns to follow whoever it is after
Flyover.altitude = 70 -- px up (its shadow falls this far)
Flyover.over = 40 -- px from them that counts as over them: it lets go
Flyover.past = 1400 -- px it flies on past them before it is gone
Flyover.most = 12 -- seconds at most before it is gone, whatever happens
Flyover.fall = 0.9 -- seconds from letting go to the ground
Flyover.ring = 34 -- px, the ring each lands in

local SYNC_EVERY = 2 -- server ticks between HC_PASS
local SMOOTHING = 10
local SNAP = 300

local function fmt(v)
  return ("%.1f"):format(v)
end

local function wrap(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

-- Server --------------------------------------------------------------------

--- A new, empty set of passes, on the host.
function Flyover.new()
  return { list = {}, cargo = {}, nextId = 1, syncIn = 0, shown = false }
end

--- Send one in from (x, y) at player `target` (an id) with `cargo`.
function Flyover.start(set, x, y, target, cargo)
  local id = set.nextId
  set.nextId = id + 1
  set.list[#set.list + 1] = { id = id, x = x, y = y, angle = 0, target = target, cargo = cargo, t = 0, aimed = false }
  return id
end

--- Where `p` is now: its player's body, or nil when they have gone.
local function targetAt(server, p)
  local player = p.target and server.players[p.target]
  if player and Features.visible(server, player) then
    return Features.bodyPose(server, player)
  end
  return nil
end

--- Let its cargo go, `spread` px apart along its line round where it is.
local function drop(set, server, p)
  local c = p.cargo
  local n = c.count or 1
  local ca, sa = math.cos(p.angle), math.sin(p.angle)
  for i = 1, n do
    local along = ((i - 1) - (n - 1) / 2) * (c.spread or 40)
    local x, y = p.x + ca * along, p.y + sa * along
    set.cargo[#set.cargo + 1] = { x = x, y = y, t = Flyover.fall, feature = c.feature }
    server:broadcast(Protocol.encode("HC_CARGO", fmt(x), fmt(y), ("%.2f"):format(Flyover.fall)))
  end
  p.dropped, p.flown = true, 0
end

function Flyover.step(set, server, dt)
  for i = #set.list, 1, -1 do
    local p = set.list[i]
    p.t = p.t + dt
    if not p.dropped then
      local tx, ty = targetAt(server, p)
      if tx then
        p.tx, p.ty = tx, ty
      end
      if p.tx then
        local want = math.atan2(p.ty - p.y, p.tx - p.x)
        if not p.aimed then
          p.angle, p.aimed = want, true -- it comes in already pointed at them
        else
          local d = wrap(want - p.angle)
          p.angle = p.angle + math.max(-Flyover.turnRate * dt, math.min(Flyover.turnRate * dt, d))
        end
      end
    end
    p.x, p.y = p.x + math.cos(p.angle) * Flyover.speed * dt, p.y + math.sin(p.angle) * Flyover.speed * dt
    if p.dropped then
      p.flown = p.flown + Flyover.speed * dt
    elseif p.tx then
      local dx, dy = p.tx - p.x, p.ty - p.y
      -- Over them, or gone past them (it turns too slowly to come round): let go.
      if dx * dx + dy * dy <= Flyover.over * Flyover.over or dx * math.cos(p.angle) + dy * math.sin(p.angle) < 0 then
        drop(set, server, p)
      end
    end
    if (p.dropped and p.flown >= Flyover.past) or p.t >= Flyover.most then
      table.remove(set.list, i)
    end
  end
  for i = #set.cargo, 1, -1 do
    local c = set.cargo[i]
    c.t = c.t - dt
    if c.t <= 0 then
      table.remove(set.cargo, i)
      local feature = Features.byName[c.feature]
      if feature and feature.serverSummon then
        feature:serverSummon(server, c.x, c.y, 1, 10)
      end
    end
  end
  set.syncIn = set.syncIn - 1
  if set.syncIn > 0 or (#set.list == 0 and not set.shown) then
    return
  end
  set.syncIn = SYNC_EVERY
  local parts = { server.tick }
  for _, p in ipairs(set.list) do
    parts[#parts + 1], parts[#parts + 2], parts[#parts + 3] = p.id, ("%.0f"):format(p.x), ("%.0f"):format(p.y)
    parts[#parts + 1] = ("%.3f"):format(p.angle)
  end
  set.shown = #set.list > 0 -- one empty list after the last goes clears every screen
  local msg = Protocol.encode("HC_PASS", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- Off every screen: an empty list (a quest's end, a map change).
function Flyover.stop(set, server)
  if set.shown then
    server:broadcast(Protocol.encode("HC_PASS", server.tick))
  end
end

-- Client --------------------------------------------------------------------

local passes = {} -- id -> { x, y, angle, to = { x, y, angle }, rotor }
local falling = {} -- { x, y, t, total }
local lastTick = 0

function Flyover.clear()
  for _, p in pairs(passes) do
    if p.rotor then
      p.rotor:stop()
    end
  end
  passes, falling, lastTick = {}, {}, 0
end

function Flyover.update(dt)
  local k = math.min(1, dt * SMOOTHING)
  for _, p in pairs(passes) do
    local to = p.to
    if (to.x - p.x) ^ 2 + (to.y - p.y) ^ 2 > SNAP * SNAP then
      p.x, p.y = to.x, to.y
    else
      p.x, p.y = p.x + (to.x - p.x) * k, p.y + (to.y - p.y) * k
    end
    p.angle = p.angle + wrap(to.angle - p.angle) * k
    p.rotor = p.rotor or Sounds.rotor(p.x, p.y)
    if p.rotor then
      Sounds.place(p.rotor, p.x, p.y, 1.05)
    end
  end
  for i = #falling, 1, -1 do
    local c = falling[i]
    c.t = c.t - dt
    if c.t <= 0 then
      table.remove(falling, i) -- what lands is the other feature's to show
    end
  end
end

--- A rollermine on its way down, `height` px up over (x, y): a steel ball,
--- its blades shut, a light blinking, its shadow off to the side.
local function drawCargo(x, y, height, time)
  local size = 1 + height / 300
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", x + height * 0.75, y + height, 9, 14)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(size, size)
  love.graphics.rotate(time * 4)
  love.graphics.setColor(0.32, 0.35, 0.38)
  love.graphics.circle("fill", 0, 0, 10, 16)
  love.graphics.setColor(0.18, 0.20, 0.22)
  love.graphics.setLineWidth(2)
  for k = 0, 2 do -- the blades, folded flat against it
    local a = k * 2 * math.pi / 3
    love.graphics.line(math.cos(a) * 3, math.sin(a) * 3, math.cos(a) * 9, math.sin(a) * 9)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.75, 0.80, 0.85, 0.7)
  love.graphics.circle("fill", -3, -3, 3, 8)
  love.graphics.setColor(0.35, 0.75, 1, math.sin(time * 16) > 0 and 1 or 0.35)
  love.graphics.circle("fill", 0, 0, 2.5, 8)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- The rings on the ground where they will land, under everyone.
function Flyover.drawBelowCars(time)
  for _, c in ipairs(falling) do
    local k = 1 - c.t / c.total
    local pulse = 0.6 + 0.4 * math.sin(time * (8 + k * 20))
    love.graphics.setColor(0.35, 0.7, 1, 0.08 + 0.18 * k)
    love.graphics.circle("fill", c.x, c.y, Flyover.ring * k, 24)
    love.graphics.setColor(0.4, 0.75, 1, (0.4 + 0.4 * k) * pulse)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", c.x, c.y, Flyover.ring, 24)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- The choppers and what they let go, over everyone.
function Flyover.drawAboveCars(time)
  for _, c in ipairs(falling) do
    drawCargo(c.x, c.y, (c.t / c.total) * Flyover.altitude, time)
  end
  for _, p in pairs(passes) do
    Render.chopper({ x = p.x, y = p.y, angle = p.angle, altitude = Flyover.altitude }, time)
  end
end

Flyover.clientMessages = {
  HC_PASS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local seen = {}
    for i = 2, #args - 3, 4 do
      local id, x, y, angle = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2]), tonumber(args[i + 3])
      if id and x and y and angle then
        seen[id] = true
        local p = passes[id]
        if not p then
          p = { x = x, y = y, angle = angle }
          passes[id] = p
          Sounds.play("dive", x, y)
        end
        p.to = { x = x, y = y, angle = angle }
      end
    end
    for id, p in pairs(passes) do
      if not seen[id] then
        if p.rotor then
          p.rotor:stop()
        end
        passes[id] = nil
      end
    end
  end,
  HC_CARGO = function(_client, args)
    local x, y, fall = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or Flyover.fall
    if x and y then
      falling[#falling + 1] = { x = x, y = y, t = fall, total = fall }
      Sounds.play("whistle", x, y)
    end
  end,
}

return Flyover
