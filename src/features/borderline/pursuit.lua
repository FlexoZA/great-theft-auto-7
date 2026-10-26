-- Thousand Papercuts' pursuit (docs/borderline.md, "7. Thousand
-- Papercuts"): everything Max has left comes up the road behind you, so
-- you keep climbing. Two things press on whoever is furthest back:
--
--   Waves of the army come up the road from out of sight below them,
--   every `EVERY[1]` seconds while they keep climbing, quicker the longer
--   they hang about (down to `EVERY[2]` once they have stopped `STALL`
--   seconds), up to `CAP` of the pursuit's out at once; each wave goes
--   straight for them.
--
--   Max's barrage creeps up the road behind them: rockets on red rings
--   (barrage.lua, owned by nobody, so they never hurt the army) landing
--   along a line that climbs `CREEP` px a second on its own, and that
--   jumps up to `LAG` px behind the rearmost whenever they get ahead of it.
--   Stand still and it walks onto you, and stays on you; go back down and
--   it follows you. It never climbs past the map's `stop` (below the
--   bunker door, where the hold is).
--
-- It starts `GRACE` seconds after the level does. The map says where the
-- road is (city-map's `map.pursuit` { tile, y0, bottom, stop, rows = {
-- [r] = { x, half } } }: the road's middle and half its width on each row,
-- world px). init.lua passes its hooks on to this module; it needs no
-- messages of its own (the rings are barrage.lua's, the waves the army's).

local Features = require("src.features")
local Army = require("src.features.borderline.army")
local Barrage = require("src.features.borderline.barrage")

local Pursuit = {}

-- Tuning ------------------------------------------------------------------
Pursuit.GRACE = 8 -- seconds after arriving before it starts
Pursuit.BACK = 760 -- px below the rearmost player a wave comes up from
Pursuit.EVERY = { 13, 5 } -- seconds between waves: climbing, and stopped
Pursuit.STALL = 10 -- seconds without the rearmost climbing before the waves come their quickest
Pursuit.CLIMB = 96 -- px the rearmost must climb to count as moving on
Pursuit.CAP = 12 -- of the pursuit's out at once
Pursuit.WAVES = { -- what each wave is, in turn
  { "JNK", "JNK", "GUN" }, { "GUN", "EXP" }, { "GUN", "GUN" }, { "STK", "GUN" }, { "EXP", "EXP", "GUN" },
  { "GUN", "RPG" },
}
Pursuit.CREEP = 34 -- px/s the barrage climbs on its own (you walk at 45)
Pursuit.LAG = 420 -- px behind the rearmost it jumps up to when they get ahead
Pursuit.FIRE_EVERY = 0.45 -- seconds between its rockets
Pursuit.SPREAD = 70 -- px either side of its line a rocket lands
Pursuit.ROCKET = { radius = 80, damage = 22, delay = 1.1 }

-- Server --------------------------------------------------------------------

local sv = nil -- { spec, t, best, stall, waveIn, wave, out, line, fireIn, warned } while a level has one

function Pursuit.serverStart(map)
  sv = nil
  if map and map.pursuit then
    sv = { spec = map.pursuit, t = 0, best = math.huge, stall = 0, waveIn = 0, wave = 1, out = {},
      line = map.pursuit.bottom, fireIn = 0 }
  end
end

function Pursuit.serverStop()
  sv = nil
end

--- The road on world row `y`: its middle and half its width, px.
local function road(spec, y)
  local r = math.floor((y - spec.y0) / spec.tile)
  local row = spec.rows[math.max(0, math.min(#spec.rows, r))]
  return row.x, row.half
end

--- The human player furthest down the road (the largest y), and where.
local function rearmost(server)
  local who, x, y = nil, nil, -math.huge
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local px, py = Features.bodyPose(server, p)
      if py > y then
        who, x, y = p, px, py
      end
    end
  end
  return who, x, y
end

--- A wave up the road from below (x, y) at the rearmost (tx, ty).
local function wave(spec, tx, ty)
  local alive = {}
  for _, s in ipairs(sv.out) do
    if Army.serverAlive(s) then
      alive[#alive + 1] = s
    end
  end
  sv.out = alive
  if #alive >= Pursuit.CAP then
    return
  end
  local codes = Pursuit.WAVES[(sv.wave - 1) % #Pursuit.WAVES + 1]
  sv.wave = sv.wave + 1
  local y = math.min(spec.bottom, ty + Pursuit.BACK)
  local x, half = road(spec, y)
  for k, code in ipairs(codes) do
    local across = (k - (#codes + 1) / 2) * math.min(60, half * 0.6)
    local s = Army.serverSpawn(code, x + across, y + k * 30, -math.pi / 2)
    if s then
      alive[#alive + 1] = s
      if s.brain.wake then
        s.brain.wake(s, tx, ty)
      end
    end
  end
end

--- The barrage: its line climbs as far as the rearmost (`ry`) and no
--- further, jumps up behind them when they get ahead, follows them back
--- down, and drops a rocket somewhere along it every so often.
local function barrage(server, spec, ry, dt)
  sv.line = math.min(sv.line, ry + Pursuit.LAG) -- they got ahead: it catches up
  sv.line = math.max(spec.stop, ry, sv.line - Pursuit.CREEP * dt)
  sv.fireIn = sv.fireIn - dt
  if sv.fireIn <= 0 then
    sv.fireIn = Pursuit.FIRE_EVERY
    local y = sv.line + (math.random() - 0.5) * 2 * Pursuit.SPREAD
    local x, half = road(spec, y)
    x = x + (math.random() - 0.5) * 2 * half
    local R = Pursuit.ROCKET
    Barrage.serverFire(server, x, y + 900, x, y, R.radius, R.damage, R.delay)
  end
end

--- `beat(what)` raises a story beat: "pursuit" when it starts, "stall"
--- the first time the rearmost stops long enough for the waves to come
--- their quickest.
function Pursuit.serverStep(server, dt, beat)
  if not sv then
    return
  end
  local spec = sv.spec
  local who, rx, ry = rearmost(server)
  if not who then
    return
  end
  sv.t = sv.t + dt
  if sv.t < Pursuit.GRACE then
    return
  end
  if not sv.started then
    sv.started = true
    beat("pursuit")
  end
  if ry < sv.best - Pursuit.CLIMB then -- climbing
    sv.best, sv.stall = ry, 0
  else
    sv.stall = sv.stall + dt
    if sv.stall >= Pursuit.STALL and not sv.warned then
      sv.warned = true
      beat("stall")
    end
  end
  local k = math.min(1, sv.stall / Pursuit.STALL)
  sv.waveIn = sv.waveIn - dt
  if sv.waveIn <= 0 then
    sv.waveIn = Pursuit.EVERY[1] + (Pursuit.EVERY[2] - Pursuit.EVERY[1]) * k
    wave(spec, rx, ry)
  end
  barrage(server, spec, ry, dt)
end

--- Where the barrage's line is, and the pursuit's out on the road: for tests.
function Pursuit.server()
  return sv
end

return Pursuit
