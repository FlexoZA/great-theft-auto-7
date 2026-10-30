-- Plasma puddles (docs/borderline.md, "Plasma"): molten Bragium left
-- burning on the floor (the Smelter's gush), purple, glowing and crusting
-- over as it cools. Whoever stands in one takes `plasma` (which melts their
-- armor: the damage feature) every TICK while it lasts. It never hurts the
-- army. The host keeps them; every screen draws its own copy from where,
-- how big and for how long the host said.
--
-- Messages
--   server -> all  HYP_POOL <x> <y> <radius> <seconds>   a puddle left burning there

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Hauler = require("src.features.borderline.hauler_look")

local Puddles = {}

Puddles.TICK = 0.25 -- seconds between bites
Puddles.FOOT = 8 -- px; how fat a player on foot is to a puddle
Puddles.FADE = 1 -- seconds a puddle takes to cool off at the end, still drawn

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { list = { x, y, r, t, dps }, tickIn }

function Puddles.serverStart()
  sv = { list = {}, tickIn = Puddles.TICK }
end

function Puddles.serverStop()
  sv = nil
end

--- A puddle `radius` px round (x, y), burning for `seconds` at `dps`
--- plasma a second (grown on a job done before).
function Puddles.serverPour(server, x, y, radius, seconds, dps)
  if not sv then
    return
  end
  sv.list[#sv.list + 1] = { x = x, y = y, r = radius, t = seconds, dps = dps * Bosses.enemyPower() }
  server:broadcast(Protocol.encode("HYP_POOL", fmt(x), fmt(y), radius, ("%.2f"):format(seconds)))
end

--- Is (x, y) in a puddle now? Returns its dps (the worst, when in more than one).
local function under(x, y)
  local worst = nil
  for _, p in ipairs(sv.list) do
    if (x - p.x) ^ 2 + (y - p.y) ^ 2 <= (p.r + Puddles.FOOT) ^ 2 and (not worst or p.dps > worst) then
      worst = p.dps
    end
  end
  return worst
end

function Puddles.serverStep(server, dt)
  if not sv then
    return
  end
  for i = #sv.list, 1, -1 do
    sv.list[i].t = sv.list[i].t - dt
    if sv.list[i].t <= 0 then
      table.remove(sv.list, i)
    end
  end
  sv.tickIn = sv.tickIn - dt
  if sv.tickIn > 0 then
    return
  end
  sv.tickIn = Puddles.TICK
  local weapons = Features.byName.weapons
  if #sv.list == 0 or not (weapons and weapons.serverDamage) then
    return
  end
  for _, p in pairs(server.players) do
    if Features.visible(server, p) and not p.vehicle then
      local x, y = Features.bodyPose(server, p)
      local dps = under(x, y)
      if dps then
        weapons:serverDamage(server, p, nil, math.max(1, math.floor(dps * Puddles.TICK + 0.5)), 0, "plasma")
      end
    end
  end
end

-- Client --------------------------------------------------------------------

local pools = {} -- { x, y, r, t, total, seed }

function Puddles.clear()
  pools = {}
end

function Puddles.update(dt)
  for i = #pools, 1, -1 do
    pools[i].t = pools[i].t + dt
    if pools[i].t > pools[i].total + Puddles.FADE then
      table.remove(pools, i)
    end
  end
end

--- The puddles on the floor: a molten middle that bubbles, a crust closing
--- in from the rim as it cools, a glow over it.
function Puddles.draw(clock)
  local C = Hauler.C
  for _, p in ipairs(pools) do
    local left = math.max(0, math.min(1, (p.total + Puddles.FADE - p.t) / Puddles.FADE)) -- 1 until it cools
    local grow = math.min(1, p.t / 0.25) -- it spreads as it lands
    local r = p.r * (0.6 + 0.4 * grow)
    love.graphics.setColor(0.16, 0.08, 0.22, 0.85 * left) -- the crust round it
    love.graphics.circle("fill", p.x, p.y, r * 1.08, 24)
    love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.85 * left)
    love.graphics.circle("fill", p.x, p.y, r * (0.55 + 0.4 * left), 24)
    love.graphics.setColor(C.plasmaHot[1], C.plasmaHot[2], C.plasmaHot[3], 0.7 * left)
    for k = 0, 2 do -- bubbles coming up and bursting
      local b = ((p.t * 0.9 + k * 0.33 + p.seed) % 1)
      local a = p.seed * 6.3 + k * 2.1
      love.graphics.circle("line", p.x + math.cos(a) * r * 0.35, p.y + math.sin(a) * r * 0.35, 2 + b * 5, 10)
    end
    love.graphics.setBlendMode("add")
    love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], (0.18 + 0.06 * math.sin(clock * 5 + p.seed * 9))
      * left)
    love.graphics.circle("fill", p.x, p.y, r * 1.6, 24)
    love.graphics.setBlendMode("alpha")
  end
  love.graphics.setColor(1, 1, 1)
end

Puddles.clientMessages = {
  HYP_POOL = function(_client, args)
    local x, y, r, t = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and r and t and t > 0 then
      pools[#pools + 1] = { x = x, y = y, r = r, t = 0, total = t, seed = love.math.random() }
    end
  end,
}

return Puddles
