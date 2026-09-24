-- MG nest: a machine gun on a tripod behind sandbags, put down a short way
-- from you, facing the way you point. For as long as it lasts it rakes
-- whoever steps into its forty-five-degree arc with rifle fire (weapons'
-- AK-47 rounds, owned by whoever placed it, so its kills are theirs and it
-- never shoots them): other players, bots and police cars, officers on
-- foot and pedestrians, nearest first. Then it is gone.
--
-- It aims differently from freeze: press its key to select it and an
-- arrow from you shows where the nest would go and which way it would
-- face (towards the cursor); the fire button puts it there, the key again
-- or right-click puts it away. `aim = "direction"` asks the abilities
-- feature for that flow.

local Features = require("src.features")
local Guns = require("src.features.weapons.guns")

local Nest = {
  key = "mgnest", -- on the wire and in a bag ("ability-mgnest")
  title = "MG nest",
  sound = "mgnest",
  color = { 1, 0.62, 0.25 }, -- brass
  aim = "direction",
}

-- Tuning ------------------------------------------------------------------
Nest.range = 150 -- px in front of you the nest is put down
Nest.radius = 22 -- px, the sandbag ring
Nest.arc = math.rad(45) -- the whole arc it covers, centred on its facing
Nest.reach = 420 -- px it shoots out to
Nest.seconds = 20 -- how long it stands
Nest.cooldown = 30 -- seconds before the next one
Nest.afterglow = 0.6 -- seconds the sandbags linger on screen once it is spent
Nest.gun = Guns.ak47 -- what it fires; its damage, speed and scatter
Nest.fireEvery = 0.16 -- seconds between rounds: slower than a rifleman
Nest.barrel = 16 -- px from the middle to the muzzle

local nests = {} -- { owner, x, y, angle, untilT, nextShot }

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

--- The smallest turn from `a` to `b`, in -pi..pi.
local function turn(a, b)
  local d = (b - a + math.pi) % (2 * math.pi) - math.pi
  return d
end

-- Server --------------------------------------------------------------------

function Nest.serverReset()
  nests = {}
end

--- Put a nest down at (x, y), facing away from the caster. Nobody is held,
--- so the list is empty; the facing goes out with ABL_FIRED.
function Nest.serverCast(server, caster, x, y, abilities)
  local ox, oy = Features.bodyPose(server, caster)
  local angle = math.atan2(y - oy, x - ox)
  -- Not inside a wall: pulled back towards the caster until it stands clear.
  local d = math.sqrt(dist2(x, y, ox, oy))
  while d > 0 and Features.any("blocksPoint", x, y) do
    d = math.max(0, d - 8)
    x, y = ox + math.cos(angle) * d, oy + math.sin(angle) * d
  end
  nests[#nests + 1] = {
    owner = caster.id, x = x, y = y, angle = angle, untilT = abilities.sv.time + Nest.seconds, nextShot = 0,
  }
  return {}, angle, x, y
end

local SIGHT_STEP = 14 -- px between the points checked for a wall on the way to a target

--- Is there a clear shot from the nest to (px, py)? Every feature that
--- owns walls answers `blocksPoint`; a round would stop at the first.
local function clearShot(nest, px, py)
  local dx, dy = px - nest.x, py - nest.y
  local d = math.sqrt(dx * dx + dy * dy)
  local n = math.floor(d / SIGHT_STEP)
  for i = 1, n do
    local k = i * SIGHT_STEP / d
    if Features.any("blocksPoint", nest.x + dx * k, nest.y + dy * k) then
      return false
    end
  end
  return true
end

--- The nearest thing inside the arc, in the open, that a bullet would
--- hurt: any present player but the owner (bots and police units are
--- players), an officer on foot (police keeps them) or a pedestrian (the
--- pedestrians crowd). Anyone behind a wall is left alone.
local function targetOf(server, nest)
  local best, bestD2
  local function consider(px, py)
    local d2 = dist2(px, py, nest.x, nest.y)
    if d2 <= Nest.reach ^ 2 and (not bestD2 or d2 < bestD2) then
      local a = math.atan2(py - nest.y, px - nest.x)
      if math.abs(turn(nest.angle, a)) <= Nest.arc / 2 and clearShot(nest, px, py) then
        best, bestD2 = { x = px, y = py }, d2
      end
    end
  end
  for id, p in pairs(server.players) do
    if id ~= nest.owner and Features.present(p) then
      consider(Features.bodyPose(server, p))
    end
  end
  local police = Features.byName.police
  local officers = police and police.serverOfficers and police:serverOfficers()
  if officers then
    for i = 1, officers.n do
      local o = officers.list[i]
      consider(o.x, o.y)
    end
  end
  local pedestrians = Features.byName.pedestrians
  local crowd = pedestrians and pedestrians.crowd
  if crowd then
    for i = 1, crowd.n do
      local ped = crowd.peds[i]
      consider(ped.x, ped.y)
    end
  end
  return best
end

--- Every nest looks down its arc and fires at whoever is there.
function Nest.serverStep(server, _dt, abilities)
  local now = abilities.sv.time
  local weapons = Features.byName.weapons
  for i = #nests, 1, -1 do
    local nest = nests[i]
    if now >= nest.untilT then
      table.remove(nests, i)
    elseif weapons and weapons.serverFireFrom and now >= nest.nextShot then
      local t = targetOf(server, nest)
      if t then
        local aim = math.atan2(t.y - nest.y, t.x - nest.x)
        local mx, my = nest.x + math.cos(aim) * Nest.barrel, nest.y + math.sin(aim) * Nest.barrel
        weapons:serverFireFrom(server, nest.owner, mx, my, aim, Nest.gun)
        nest.nextShot = now + Nest.fireEvery
      end
    end
  end
end

--- For tests.
function Nest.serverNests()
  return nests
end

-- Client --------------------------------------------------------------------

--- The arc a nest at (x, y) facing `angle` covers, as a wedge.
local function wedge(mode, x, y, angle, reach)
  love.graphics.arc(mode, "pie", x, y, reach, angle - Nest.arc / 2, angle + Nest.arc / 2, 24)
end

--- Sandbags in a ring, the gun on its tripod pointing along `angle`.
local function drawNest(x, y, angle, alpha)
  local c = Nest.color
  love.graphics.setColor(0.45, 0.4, 0.28, alpha)
  love.graphics.circle("fill", x, y, Nest.radius, 24)
  love.graphics.setColor(0.6, 0.53, 0.36, alpha)
  for k = 0, 7 do
    local a = k * math.pi / 4 + angle
    love.graphics.circle("fill", x + math.cos(a) * (Nest.radius - 5), y + math.sin(a) * (Nest.radius - 5), 6, 12)
  end
  love.graphics.setColor(0.2, 0.2, 0.22, alpha)
  love.graphics.circle("fill", x, y, 7, 16)
  love.graphics.setLineWidth(4)
  love.graphics.line(x, y, x + math.cos(angle) * (Nest.barrel + 8), y + math.sin(angle) * (Nest.barrel + 8))
  love.graphics.setLineWidth(2)
  love.graphics.setColor(c[1], c[2], c[3], alpha)
  love.graphics.line(x, y, x + math.cos(angle) * Nest.barrel, y + math.sin(angle) * Nest.barrel)
  love.graphics.setLineWidth(1)
end

--- While the ability is selected: an arrow from me to where the nest would
--- stand, the nest as a ghost there, and the arc it would cover.
function Nest.drawAim(ox, oy, x, y, time)
  local c = Nest.color
  local angle = math.atan2(y - oy, x - ox)
  local pulse = 0.5 + 0.5 * math.sin(time * 6)
  love.graphics.setColor(c[1], c[2], c[3], 0.10 + 0.06 * pulse)
  wedge("fill", x, y, angle, Nest.reach)
  love.graphics.setLineWidth(1.5)
  love.graphics.setColor(c[1], c[2], c[3], 0.5)
  wedge("line", x, y, angle, Nest.reach)
  -- The arrow: a shaft from me, a head at the nest.
  love.graphics.setLineWidth(3)
  love.graphics.setColor(c[1], c[2], c[3], 0.9)
  local sx, sy = ox + math.cos(angle) * 24, oy + math.sin(angle) * 24
  local hx, hy = x - math.cos(angle) * (Nest.radius + 4), y - math.sin(angle) * (Nest.radius + 4)
  love.graphics.line(sx, sy, hx, hy)
  local left, right = angle + 2.5, angle - 2.5
  love.graphics.polygon("fill", hx + math.cos(angle) * 10, hy + math.sin(angle) * 10,
    hx + math.cos(left) * 12, hy + math.sin(left) * 12, hx + math.cos(right) * 12, hy + math.sin(right) * 12)
  love.graphics.setLineWidth(1)
  drawNest(x, y, angle, 0.55)
end

--- The nest in the world for as long as it stands, its arc faint on the
--- ground, fading out through the afterglow once it is spent.
function Nest.drawEffect(e)
  local c = Nest.color
  local fade = math.max(0, math.min(1, (e.seconds + Nest.afterglow - e.t) / Nest.afterglow))
  local angle = e.angle or 0
  love.graphics.setColor(c[1], c[2], c[3], 0.07 * fade)
  wedge("fill", e.x, e.y, angle, Nest.reach)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(c[1], c[2], c[3], 0.3 * fade)
  wedge("line", e.x, e.y, angle, Nest.reach)
  drawNest(e.x, e.y, angle, fade)
  if e.t < 0.3 then
    -- Just put down: a puff of dust settling round the sandbags.
    local k = e.t / 0.3
    love.graphics.setColor(0.7, 0.62, 0.45, 0.5 * (1 - k))
    love.graphics.circle("fill", e.x, e.y, Nest.radius + 4 + k * 22, 24)
  end
  love.graphics.setColor(1, 1, 1)
end

return Nest
