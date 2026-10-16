-- Where Heck's walkers may stand, and the lava, on the host. Sight.blocked
-- is the walls: what stops sight and rounds. Lava (the Crucible's pit and
-- moat, the Smelters' vats, Earth's Crater) is `low` on the map: no wall to
-- sight or rounds, so you can shoot across it, and a hazard, not a wall, to
-- a player (docs/eternal-mood.md, "Shared look"): walk into it and you burn
-- (`serverStep`, the damage feature's `ignite`, kept up while you're in
-- it). Nothing of Heck's walks into it: Ground.blocked is the walls and the
-- lava, and every walker's brain asks it instead of Sight.blocked;
-- `closeNav` shuts the walking grid's cells over the lava.
--
-- city-map's `map.lows`: { x, y, w, h, round } the low solids
-- (eternal_mood.lua's `cover` with `low`).

local Sight = require("src.features.d-day.sight")
local Nav = require("src.features.d-day.nav")

local Features = require("src.features")

local Ground = {}

Ground.BURN = 1.5 -- seconds a player stays alight after the lava...
Ground.BURN_DPS = 30 -- ...at this much `fire` a second
Ground.BURN_EVERY = 0.25 -- seconds between lighting them up again while they stand in it

local lows = {} -- the map in play's

--- Use `map`'s low solids from now on (horde.lua, on starting a level).
function Ground.use(map)
  lows = map and map.lows or {}
end

local function low(x, y)
  for _, s in ipairs(lows) do
    if x >= s.x and x <= s.x + s.w and y >= s.y and y <= s.y + s.h then
      return true
    end
  end
  return false
end

local burnIn = {} -- player id -> seconds to the next lighting up

--- Is (x, y) in the lava proper (a round one's ellipse, not its box)?
local function inLava(x, y)
  for _, s in ipairs(lows) do
    if s.round then
      local rx, ry = s.w / 2, s.h / 2
      if ((x - s.x - rx) / rx) ^ 2 + ((y - s.y - ry) / ry) ^ 2 <= 1 then
        return true
      end
    elseif x >= s.x and x <= s.x + s.w and y >= s.y and y <= s.y + s.h then
      return true
    end
  end
  return false
end

--- One tick: anyone on foot standing in the lava is alight, and stays so
--- while they're in it.
function Ground.serverStep(server, dt)
  if #lows == 0 then
    return
  end
  local damage = Features.byName.damage
  for id, p in pairs(server.players) do
    local body = p.body
    burnIn[id] = math.max(0, (burnIn[id] or 0) - dt)
    if damage and body and not p.vehicle and not body.dead and Features.present(p) and burnIn[id] <= 0
      and inLava(body.x, body.y) then
      burnIn[id] = Ground.BURN_EVERY
      damage:ignite(server, p, Ground.BURN, Ground.BURN_DPS)
    end
  end
end

--- Can nothing of Heck's stand at (x, y)? A wall, or lava.
function Ground.blocked(x, y)
  return Sight.blocked(x, y) or low(x, y)
end

--- Does a walker `r` px across the shoulders fit at (x, y): nothing solid
--- and no lava under its middle or round its edge?
function Ground.fits(x, y, r)
  local c = r * 0.7
  return not (Ground.blocked(x, y) or Ground.blocked(x - r, y) or Ground.blocked(x + r, y)
    or Ground.blocked(x, y - r) or Ground.blocked(x, y + r) or Ground.blocked(x - c, y - c)
    or Ground.blocked(x + c, y - c) or Ground.blocked(x - c, y + c) or Ground.blocked(x + c, y + c))
end

--- Move walker `w` ({ x, y, stuck }, `r` px across) along `angle` at
--- `speed` for `dt`, sliding along walls. Returns false, counting
--- `w.stuck` up, when it got nowhere.
function Ground.walk(w, angle, speed, dt, r)
  local mx, my = math.cos(angle) * speed * dt, math.sin(angle) * speed * dt
  if Ground.fits(w.x + mx, w.y + my, r) then
    w.x, w.y = w.x + mx, w.y + my
  elseif Ground.fits(w.x + mx, w.y, r) then
    w.x = w.x + mx
  elseif Ground.fits(w.x, w.y + my, r) then
    w.y = w.y + my
  else
    w.stuck = w.stuck + dt
    return false
  end
  w.stuck = 0
  return true
end

--- Can a walker go straight from (x0, y0) to (x1, y1)? No wall and no
--- lava on the way (Sight.clear's, with the lava).
function Ground.clear(x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.floor(math.sqrt(dx * dx + dy * dy) / Sight.STEP)
  for i = 1, n do
    local k = i / (n + 1)
    if Ground.blocked(x0 + dx * k, y0 + dy * k) then
      return false
    end
  end
  return true
end

--- Shut `nav`'s cells over the lava (and a walker's width round it).
function Ground.closeNav(nav)
  local m = Nav.CLEARANCE
  for _, s in ipairs(lows) do
    local c0, r0 = nav:cellOf(s.x - m, s.y - m)
    local c1, r1 = nav:cellOf(s.x + s.w + m, s.y + s.h + m)
    for c = math.max(0, c0), math.min(nav.cols - 1, c1) do
      for r = math.max(0, r0), math.min(nav.rows - 1, r1) do
        nav.open[r * nav.cols + c] = false
      end
    end
  end
end

return Ground
