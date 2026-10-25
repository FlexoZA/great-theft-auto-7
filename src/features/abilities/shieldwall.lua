-- Shield wall: a curved wall of blue light, a quarter of a circle round
-- you, put up on the side you point at and held for a few seconds. Rounds
-- fired by players go through it both ways, so you and your friends shoot
-- over it freely; rounds fired by anything else (the police, gang guards,
-- bosses and their troops, bots) stop dead on it, and no enemy on foot
-- walks through it (fliers go over). It covers one side only
-- and stays where it was put up: whatever comes from behind or round its
-- ends gets through, and stepping out from behind it leaves you in the open.
--
-- It aims the way the MG nest does (`aim = "direction"`): press its key and
-- the wall shows as a ghost in front of you, facing the cursor; the fire
-- button puts it up, the key again or right-click puts it away.
--
-- The host stops the rounds through the `serverShotAt` convention (the
-- abilities feature passes it on): weapons asks it along every round's
-- path, and a round that isn't a human player's, crossing the wall from the
-- outside, is swallowed there and sparks blue on every screen (the
-- "shield" material, weapons/explosions.lua). Enemies are kept back the
-- same way the audit finds them: every tick, after everything else has
-- moved, the wall asks for them (`serverEnemies`) and puts any that walked
-- into it back on the side they were on. Only rounds weapons flies are
-- stopped: an enemy whose feature flies its own shots, a blast's reach and
-- a blow up close still land.

local Features = require("src.features")

local Shield = {
  key = "shieldwall", -- on the wire and in a bag ("ability-shieldwall")
  title = "shield wall",
  hud = "shield", -- short enough to fit under its ring
  blurb = "A curved wall in front of you that stops enemy fire for a few seconds. Your own rounds and your "
    .. "friends' go straight through.",
  sound = "shieldwall",
  color = { 0.4, 0.72, 1 }, -- a cold electric blue
  aim = "direction",
}

-- Tuning ------------------------------------------------------------------
Shield.radius = 70 -- px from you to the wall
Shield.range = Shield.radius -- the aim arrow reaches the wall
Shield.arc = math.rad(90) -- how much of the circle round you it covers, centred on where you point
Shield.seconds = 8 -- how long it holds
Shield.cooldown = 30 -- seconds before the next
Shield.afterglow = 0.4 -- seconds it takes to fade once it drops
Shield.opening = 0.2 -- seconds it takes to spread out to its full width on screen
Shield.flicker = 1.5 -- the last seconds it flickers, a warning that it is about to drop
Shield.tierStats = { "cooldown", "seconds", "radius" } -- what a better tier improves, in order

local BACK = 8 -- px behind a round to look for where it came from: more than weapons' sweep step (6)

local walls = {} -- { by, x, y, angle, untilT, radius, sides }

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

--- How far `a` is from `b`, either way round, in radians (0 to pi).
local function apart(a, b)
  return math.abs((a - b + math.pi) % (2 * math.pi) - math.pi)
end

-- Server --------------------------------------------------------------------

function Shield.serverReset()
  walls = {}
end

--- Put a wall up round the caster, on the side of (x, y). Nobody is held;
--- the facing and the wall's middle (the caster) go out with ABL_FIRED.
function Shield.serverCast(server, caster, x, y, abilities, A)
  A = A or Shield -- the shield in the caster's tier
  local ox, oy = Features.bodyPose(server, caster)
  local angle = math.atan2(y - oy, x - ox)
  walls[#walls + 1] = {
    by = caster.id, x = ox, y = oy, angle = angle, untilT = abilities.sv.time + A.seconds, radius = A.radius,
    sides = setmetatable({}, { __mode = "k" }), -- enemy -> "out" or "in": the side of it they keep to
  }
  return {}, angle, ox, oy
end

--- Keep enemy `e` (a `serverEnemies` entry) on the side of wall `w` it was
--- on. Its side is noted while it is clear of the wall (round its ends, or
--- when the wall first sees it); while it is in front of the wall and has
--- walked into it, it is put back against it, unless that is inside
--- something solid.
local function hold(w, e)
  local body = e.id
  if e.flying or type(body) ~= "table" or body.x ~= e.x or body.y ~= e.y then
    return -- over the wall, or a list entry that isn't where it lives: nothing to move
  end
  local dx, dy = e.x - w.x, e.y - w.y
  local d = math.sqrt(dx * dx + dy * dy)
  local r = e.radius or 10
  local a = math.atan2(dy, dx)
  local facing = apart(a, w.angle) <= Shield.arc / 2 + r / math.max(d, 1)
  if not facing or not w.sides[body] then
    w.sides[body] = d >= w.radius and "out" or "in"
  end
  if not facing then
    return
  end
  local to
  if w.sides[body] == "out" and d < w.radius + r then
    to = w.radius + r
  elseif w.sides[body] == "in" and d > w.radius - r then
    to = math.max(0, w.radius - r)
  end
  if to then
    local nx, ny = w.x + math.cos(a) * to, w.y + math.sin(a) * to
    if not Features.any("blocksPoint", nx, ny) then
      body.x, body.y = nx, ny
    end
  end
end

--- Take down the walls that have run out, and keep enemies from walking
--- through the rest (this runs after every other feature has moved its own).
function Shield.serverStep(server, _dt, abilities)
  local now = abilities.sv.time
  for i = #walls, 1, -1 do
    if now >= walls[i].untilT then
      table.remove(walls, i)
    end
  end
  if #walls > 0 then
    Features.call("serverEnemies", server, function(e)
      for _, w in ipairs(walls) do
        hold(w, e)
      end
    end)
  end
end

--- Was this round fired by a player the wall lets through: a human (bots
--- shoot at people, so they count as enemies)? `by` is 0 for a round no
--- player fired.
local function friendly(server, by)
  local player = by and server.players[by]
  return player ~= nil and not player.bot
end

--- The `serverShotAt` convention, passed on by the abilities feature: a
--- round at (x, y) flying along `angle` that isn't a friendly one, and
--- that has just come in through a wall from its outside, stops there.
function Shield.serverShotAt(server, x, y, _radius, by, angle)
  if #walls == 0 or type(angle) ~= "number" or friendly(server, by) then
    return nil
  end
  local px, py = x - math.cos(angle) * BACK, y - math.sin(angle) * BACK -- where it was a moment ago
  for _, w in ipairs(walls) do
    local r2 = w.radius * w.radius
    if
      dist2(x, y, w.x, w.y) <= r2
      and dist2(px, py, w.x, w.y) > r2
      and apart(math.atan2(y - w.y, x - w.x), w.angle) <= Shield.arc / 2
    then
      return "shield"
    end
  end
  return nil
end

--- For tests.
function Shield.serverWalls()
  return walls
end

-- Client --------------------------------------------------------------------

--- The wall round (x, y) facing `angle`, `r` out, `width` radians of it:
--- a band of blue glass, hexagons along it, a bright edge on the outside.
local function drawWall(x, y, angle, r, width, alpha, pulse)
  local c = Shield.color
  local from, to = angle - width / 2, angle + width / 2
  love.graphics.setLineWidth(10)
  love.graphics.setColor(c[1], c[2], c[3], (0.16 + 0.06 * pulse) * alpha)
  love.graphics.arc("line", "open", x, y, r - 3, from, to, 24)
  -- Hexagons along the band.
  love.graphics.setLineWidth(1)
  love.graphics.setColor(c[1], c[2], c[3], 0.35 * alpha)
  local n = math.max(2, math.floor(r * width / 12))
  for i = 0, n - 1 do
    local a = from + (i + 0.5) * width / n
    local hx, hy = x + math.cos(a) * (r - 3), y + math.sin(a) * (r - 3)
    local pts = {}
    for v = 0, 5 do
      local t = a + v * math.pi / 3
      pts[#pts + 1] = hx + math.cos(t) * 4.5
      pts[#pts + 1] = hy + math.sin(t) * 4.5
    end
    love.graphics.polygon("line", pts)
  end
  -- The face enemy fire meets, and a softer edge on the inside.
  love.graphics.setLineWidth(3)
  love.graphics.setColor(c[1], c[2], c[3], (0.7 + 0.25 * pulse) * alpha)
  love.graphics.arc("line", "open", x, y, r, from, to, 24)
  love.graphics.setLineWidth(1.5)
  love.graphics.setColor(0.85, 0.95, 1, 0.4 * alpha)
  love.graphics.arc("line", "open", x, y, r - 8, from, to, 24)
  love.graphics.setLineWidth(1)
end

--- While the ability is selected: the wall as a ghost round me, on the
--- side of the cursor, and an arrow out to it.
function Shield.drawAim(ox, oy, x, y, time)
  local c = Shield.color
  local angle = math.atan2(y - oy, x - ox)
  local pulse = 0.5 + 0.5 * math.sin(time * 6)
  drawWall(ox, oy, angle, Shield.radius, Shield.arc, 0.45 + 0.15 * pulse, pulse)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(c[1], c[2], c[3], 0.7)
  local from, to = 14, Shield.radius - 14
  local hx, hy = ox + math.cos(angle) * to, oy + math.sin(angle) * to
  love.graphics.line(ox + math.cos(angle) * from, oy + math.sin(angle) * from, hx, hy)
  local left, right = angle + 2.5, angle - 2.5
  love.graphics.polygon("fill", hx + math.cos(angle) * 7, hy + math.sin(angle) * 7,
    hx + math.cos(left) * 8, hy + math.sin(left) * 8, hx + math.cos(right) * 8, hy + math.sin(right) * 8)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- The wall where it was put up, spreading out from the middle when cast,
--- flickering in its last moments and fading once it drops.
function Shield.drawEffect(e)
  local radius = (e.ability or Shield).radius
  local open = math.min(1, e.t / Shield.opening)
  local width = Shield.arc * (1 - (1 - open) ^ 3)
  local fade = math.max(0, math.min(1, (e.seconds + Shield.afterglow - e.t) / Shield.afterglow))
  local left = e.seconds - e.t
  if left > 0 and left < Shield.flicker and math.sin(e.t * 40) > 0.3 then
    fade = fade * 0.45
  end
  local pulse = 0.5 + 0.5 * math.sin(e.t * 3)
  drawWall(e.x, e.y, e.angle or 0, radius, width, fade, pulse)
  if e.t < 0.35 then
    -- The cast: a bright edge thrown out past the wall.
    local k = e.t / 0.35
    love.graphics.setLineWidth(3)
    love.graphics.setColor(0.8, 0.92, 1, 1 - k)
    love.graphics.arc("line", "open", e.x, e.y, radius + k * 22, (e.angle or 0) - width / 2,
      (e.angle or 0) + width / 2, 24)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

return Shield
