-- Teleport: vanish and reappear a long way off, tearing through whoever is
-- on the line in between. Press the key and the arrival ring follows the
-- cursor, kept within `range` of you; the fire button (left click) goes
-- (`aim = "point"`). Walls don't stop you, but you never arrive inside
-- one: the spot is pulled back towards you until it is clear. Only on foot
-- (`onFoot = true`).
--
-- The line hurts: every other player (bots too, on foot or behind a wheel)
-- within `width` of it takes `damage` (weapons' serverDamage, so it is your
-- kill), and the soft targets along it (pedestrians, officers, a boss) are
-- hit through the `serverShotAt` convention. You are never hurt yourself.
--
-- It is A-Man's (src/features/a-man): he drops it when he goes down in a
-- city event, and uses the same line himself (`Teleport.serverThrough`).
-- Never sold.
--
-- The host moves the caster in one go. Every client draws the tear from
-- where it last drew them to where they arrive (ABL_FIRED's x, y): the
-- core snaps a body that jumps this far, so nobody slides across the map.

local Features = require("src.features")
local Car = require("src.car")
local Body = require("src.body")

local Teleport = {
  key = "teleport", -- on the wire and in a bag ("ability-teleport")
  title = "teleport",
  blurb = "Vanish and reappear far away, tearing through anyone in between. Only won by beating A-Man.",
  hud = "teleport",
  sound = "teleport",
  color = { 0.55, 0.95, 0.65 }, -- his eyes
  unsold = true, -- the shop leaves it off the shelf
  onFoot = true,
  aim = "point", -- a press shows the arrival, a click goes
}

-- Tuning ------------------------------------------------------------------
Teleport.range = 700 -- px; the furthest you can go
Teleport.radius = 22 -- px; the arrival ring
Teleport.width = 14 -- px either side of the line that it tears through
Teleport.damage = 50 -- to everyone on the line
Teleport.seconds = 0.35 -- how long the tear hangs in the air
Teleport.cooldown = 14 -- seconds before the next one
Teleport.afterglow = 0.4
-- What a better tier improves, in order: an uncommon one comes back sooner,
-- a rare one goes further too, a legendary one also hurts more.
Teleport.tierStats = { "cooldown", "range", "damage" }

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

--- Squared distance from (px, py) to the segment (ax, ay)-(bx, by).
local function segDist2(px, py, ax, ay, bx, by)
  local vx, vy = bx - ax, by - ay
  local len2 = vx * vx + vy * vy
  local k = len2 > 0 and math.max(0, math.min(1, ((px - ax) * vx + (py - ay) * vy) / len2)) or 0
  return dist2(px, py, ax + vx * k, ay + vy * k)
end

--- Is a circle of radius `r` at (x, y) in a wall (the `blocksPoint`
--- convention)? Tested at the centre and its four extremes.
local function blocked(x, y, r)
  return Features.any("blocksPoint", x, y)
    or Features.any("blocksPoint", x - r, y)
    or Features.any("blocksPoint", x + r, y)
    or Features.any("blocksPoint", x, y - r)
    or Features.any("blocksPoint", x, y + r)
end

-- Server --------------------------------------------------------------------

--- Where someone of radius `r` going from (sx, sy) towards (x, y) arrives:
--- there, or pulled back towards the start until it is out of the walls.
function Teleport.clear(sx, sy, x, y, r)
  local angle = math.atan2(y - sy, x - sx)
  local d = math.sqrt(dist2(x, y, sx, sy))
  while d > 0 and blocked(x, y, r or Body.RADIUS) do
    d = math.max(0, d - 8)
    x, y = sx + math.cos(angle) * d, sy + math.sin(angle) * d
  end
  return x, y
end

--- Tear through everything on the line from (sx, sy) to (ex, ey): players
--- within `width` of it take `damage` from `by` (a player, or nil for a
--- boss), all but `skip`; the soft targets along it are hit through
--- `serverShotAt` (`by`'s id, 0 for nobody). Returns how many players it caught.
function Teleport.serverThrough(server, sx, sy, ex, ey, damage, width, by, skip)
  local angle = math.atan2(ey - sy, ex - sx)
  local caught = {}
  for _, p in pairs(server.players) do
    if p ~= skip and Features.present(p) then
      local px, py, onFoot = Features.bodyPose(server, p)
      local reach = (onFoot and Body.RADIUS or Car.WIDTH / 2) + width
      if segDist2(px, py, sx, sy, ex, ey) <= reach * reach then
        caught[#caught + 1] = p
      end
    end
  end
  -- Hurt them once they are all found: a wreck moves its driver.
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    for _, p in ipairs(caught) do
      weapons:serverDamage(server, p, by, damage, angle, "impact")
    end
  end
  -- The soft targets, a step of two widths at a time. Something hit at one
  -- step is passed over at the next, so a boss on the line is hit once.
  local steps = math.max(1, math.ceil(math.sqrt(dist2(sx, sy, ex, ey)) / (2 * width)))
  local byId = by and by.id or 0
  local justHit = {}
  for i = 0, steps do
    local x, y = sx + (ex - sx) * i / steps, sy + (ey - sy) * i / steps
    for _, f in ipairs(Features.list) do
      if f.serverShotAt then
        if justHit[f] then
          justHit[f] = nil
        elseif f:serverShotAt(server, x, y, width, byId, angle, damage, "impact") then
          justHit[f] = true
        end
      end
    end
  end
  return #caught
end

function Teleport.serverCast(server, caster, x, y, _abilities, A)
  A = A or Teleport -- the teleport in the caster's tier
  local sx, sy = Features.bodyPose(server, caster)
  x, y = Teleport.clear(sx, sy, x, y)
  local angle = math.atan2(y - sy, x - sx)
  Teleport.serverThrough(server, sx, sy, x, y, A.damage, A.width, caster, caster)
  local body = caster.body
  body.x, body.y, body.facing = x, y, angle
  return {}, angle, x, y
end

-- Client --------------------------------------------------------------------

--- ABL_FIRED: the tear starts from where the caster is drawn right now.
function Teleport.onFired(e, client)
  local x, y = client:pose(e.by)
  e.sx, e.sy = x or e.x, y or e.y
end

--- A tear in the air from where they were to where they are: a pale line
--- with a flicker of static along it, closing to nothing, and a ring
--- folding in on each end.
function Teleport.drawEffect(e)
  Teleport.drawTear(e.sx, e.sy, e.x, e.y, e.t / (e.seconds + e.ability.afterglow), e.ability.color)
end

--- The tear from (sx, sy) to (ex, ey), `k` (0..1) of the way through fading.
--- A-Man's blinks draw the same.
function Teleport.drawTear(sx, sy, ex, ey, k, c)
  if k >= 1 then
    return
  end
  local fade = 1 - k
  local len = math.sqrt(dist2(sx, sy, ex, ey))
  local nx, ny = 0, 0
  if len > 0 then
    nx, ny = -(ey - sy) / len, (ex - sx) / len
  end
  love.graphics.setLineWidth(10 * fade + 1)
  love.graphics.setColor(c[1], c[2], c[3], 0.25 * fade)
  love.graphics.line(sx, sy, ex, ey)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 1, 1, 0.8 * fade)
  love.graphics.line(sx, sy, ex, ey)
  -- Static: short ticks off the line, the same ones all through one tear.
  local seed = math.floor(sx * 3 + ey * 7)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(c[1], c[2], c[3], 0.7 * fade)
  for i = 1, math.floor(len / 24) do
    local t = ((seed * i) % 97) / 97
    local side = (seed + i) % 2 == 0 and 1 or -1
    local px, py = sx + (ex - sx) * t, sy + (ey - sy) * t
    local s = 4 + (seed * i) % 7
    love.graphics.line(px, py, px + nx * side * s * fade, py + ny * side * s * fade)
  end
  for _, p in ipairs({ { sx, sy }, { ex, ey } }) do
    love.graphics.setColor(c[1], c[2], c[3], 0.8 * fade)
    love.graphics.circle("line", p[1], p[2], 6 + 20 * fade, 24)
  end
  love.graphics.setColor(1, 1, 1)
end

return Teleport
