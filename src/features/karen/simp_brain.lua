-- Karen's simps' brain, on the host: what each one does each tick. The gang
-- itself (who is out, their names, their health, the cars that flatten
-- them) is simps.lua; a simp is handed in as `s`, the gang's numbers as `S`.
--
-- Each is always in one of these, the later ones cutting in on the earlier:
--
--   hang     nobody to go after: they stay by Karen, milling about her
--            (or where they stand once she is down)
--   defend   somebody shot Karen in the last DEFEND_TIME seconds: that
--            player, whoever else is nearer, if they are in sight
--   hunt     otherwise the nearest player in sight. Each first makes for
--            his own spot on a ring FLANK px round them, spread round the
--            side the gang comes from (`flank`, up to FLANK_SPREAD either
--            way), so the gang closes round them rather than queueing up
--            behind one another; there, he goes straight in and punches
--            whatever he reaches, car or walker
--
-- A stink sends them off away from it at a run.

local Features = require("src.features")
local Car = require("src.car")

local Brain = {}

-- Tuning --------------------------------------------------------------------

Brain.DEFEND_TIME = 6 -- seconds a shot at Karen keeps the gang on whoever fired it
Brain.FLANK = 100 -- px round the target the ring each makes for first is
Brain.FLANK_SPREAD = 1.6 -- radians either way of the gang's approach their spots spread
Brain.FLANK_RESET = 320 -- px; further from the target than this and he makes for his spot again
Brain.HANG = 150 -- px from Karen they keep to with nobody about

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Solid ground, through the `blocksPoint` convention (the city map owns it).
local function blockedAt(x, y, r)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

--- One step, each axis on its own so a wall is slid along; wedged, he
--- sidesteps for a moment.
function Brain.walk(S, s, angle, speed, dt)
  if s.sidestep > 0 then
    s.sidestep = s.sidestep - dt
    angle = angle + s.side * math.pi / 2
  end
  local px, py = s.x, s.y
  local nx = s.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, s.y, S.RADIUS) then
    s.x = nx
  end
  local ny = s.y + math.sin(angle) * speed * dt
  if not blockedAt(s.x, ny, S.RADIUS) then
    s.y = ny
  end
  if dist2(s.x, s.y, px, py) < (speed * dt * 0.4) ^ 2 then
    s.stuck = s.stuck + dt
    if s.stuck > 0.4 then
      s.stuck, s.sidestep, s.side = 0, 0.6, -s.side
    end
  else
    s.stuck = 0
  end
end

--- Who he goes after: whoever shot Karen lately, if he can see them;
--- otherwise the nearest player in sight. `bodies` is the gang's list of
--- everyone this tick ({ id, player, x, y, onFoot }).
local function pickTarget(S, s, bodies, nbodies, boss, time)
  local best, bestD2
  local avenge = boss and boss.lastHitBy and time - (boss.lastHitT or -99) < Brain.DEFEND_TIME and boss.lastHitBy
  for i = 1, nbodies do
    local e = bodies[i]
    local d2 = dist2(e.x, e.y, s.x, s.y)
    if d2 <= S.SIGHT * S.SIGHT then
      if e.id == avenge then
        return e, d2, "defend"
      end
      if not bestD2 or d2 < bestD2 then
        best, bestD2 = e, d2
      end
    end
  end
  return best, bestD2, "hunt"
end

--- At `target`: in from his own side until he is close, then straight in,
--- and a punch for whatever he reaches.
local function hunt(S, s, server, dt, target, dist, boss)
  local reach = S.RADIUS + S.REACH + (target.onFoot and 0 or Car.HEIGHT / 2)
  local tx, ty = target.x, target.y
  if s.flankOn ~= target.id or dist > Brain.FLANK_RESET then
    s.flankOn, s.flanked = target.id, false -- a new target, or he fell back: his spot first
  end
  if not s.flanked then
    -- His spot on the ring, round from the side the gang comes from (Karen's).
    local from = boss and math.atan2(boss.y - ty, boss.x - tx) or math.atan2(s.y - ty, s.x - tx)
    local a = from + s.flank
    local fx, fy = tx + math.cos(a) * Brain.FLANK, ty + math.sin(a) * Brain.FLANK
    if dist2(s.x, s.y, fx, fy) < 30 * 30 or dist < reach then
      s.flanked = true
    else
      tx, ty = fx, fy
    end
  end
  s.facing = math.atan2(ty - s.y, tx - s.x)
  if dist > reach then
    Brain.walk(S, s, s.facing, S.CHASE_SPEED, dt)
  end
  s.punchTimer = s.punchTimer - dt
  if dist <= reach and s.punchTimer <= 0 then
    s.punchTimer = S.PUNCH_INTERVAL
    s.swing = 0.3
    s.facing = math.atan2(target.y - s.y, target.x - s.x)
    local weapons = Features.byName.weapons
    if weapons and weapons.serverDamage then
      weapons:serverDamage(server, target.player, nil, S.PUNCH_DAMAGE, s.facing, "melee")
    end
  end
end

--- Nobody about: back to Karen if he has wandered off, milling about
--- where he is otherwise.
local function hang(S, s, dt, boss)
  if boss and dist2(s.x, s.y, boss.x, boss.y) > Brain.HANG * Brain.HANG then
    s.facing = math.atan2(boss.y - s.y, boss.x - s.x)
    Brain.walk(S, s, s.facing, S.WALK_SPEED, dt)
    return
  end
  if s.stuck > 0.5 or random() < dt * 0.6 then
    s.facing = s.facing + (random() - 0.5) * 2.5
    s.stuck = 0
  end
  Brain.walk(S, s, s.facing, S.WALK_SPEED * 0.5, dt)
end

--- One simp's tick. `boss` is Karen (nil once she is down), `time` the
--- gang's clock.
function Brain.think(S, s, server, dt, bodies, nbodies, boss, time)
  s.swing = math.max(0, s.swing - dt)
  s.flank = s.flank or (random() * 2 - 1) * Brain.FLANK_SPREAD -- his own side to come in from
  if s.panic then
    -- A stink: away from it at a run, whoever is about.
    s.mode = "panic"
    s.panic.left = s.panic.left - dt
    s.facing = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
    Brain.walk(S, s, s.facing, S.WALK_SPEED, dt)
    if s.panic.left <= 0 then
      s.panic = nil
    end
    return
  end
  local target, d2, why = pickTarget(S, s, bodies, nbodies, boss, time)
  s.target = target and target.id or nil
  if target then
    s.mode = why
    hunt(S, s, server, dt, target, math.sqrt(d2), boss)
  else
    s.mode = "hang"
    hang(S, s, dt, boss)
  end
end

return Brain
