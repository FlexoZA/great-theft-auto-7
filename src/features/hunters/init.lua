-- Hunters: the Combine's tripod hunters, a ranged enemy. Quick on their
-- three legs, they keep their distance and shoot uzi rounds that carry
-- shock damage, throw themselves aside from incoming fire and players'
-- abilities, and when badly hurt go after medkits and energy drinks lying
-- nearby.
--
-- Built in steps; so far they look the part (render.lua), walk a beat and
-- fight. They think as City 17's Combine soldiers do (d-day/troops.lua,
-- with `hunt` on) and see as they do: the same cone of sight, wider while
-- they are on edge, and anyone close by whichever way they face. Spot
-- somebody and a Hunter closes in, firing uzi bursts whose rounds stun
-- (damage's shock type); lose them and it searches where they were, then
-- walks back to its beat. Each is a squad of one, quicker than a soldier
-- and a good deal tougher. Rounds owned by nobody (the Combine's, the
-- turrets', their own) pass by them; anyone else's hurt them.
--
-- Another feature puts them on the map (City 17 has three round the
-- Citadel): `hunters:serverPatrol(server, route, count)` spreads `count` of
-- them round `route`, a loop of { x, y } corners they walk round and round.
-- `hunters:serverClear(server)` takes them all away again; a map change
-- does too.
--
-- The host owns them; clients hear where they are at 15 Hz.
--
-- Messages
--   server -> all  HTR_STATE <tick> (<id> <x> <y> <facing> <hp> <alert> <firing>)...   (unreliable, 15 Hz;
--                  alert 1 has somebody, 2 searching or looking into something, 0 neither)
--   server -> all  HTR_DOWN  <id> <x> <y> <angle>     one went down
--
-- Modules
--   render.lua   one drawn from above, walking, firing, hit and dodging

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Troops = require("src.features.d-day.troops")
local Sight = require("src.features.d-day.sight")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Render = require("src.features.hunters.render")

local Hunters = {
  name = "hunters",
}

-- Tuning ------------------------------------------------------------------
-- Their eyes: City 17's Combine soldiers' (a-man/city17.lua).
Hunters.fov = math.rad(60) -- how wide their cone of sight is
Hunters.alertFov = math.rad(100) -- and while one is on edge
Hunters.aware = 170 -- px all round them they notice somebody in, any way they face
Hunters.health = 180 -- three times a Combine soldier's: nine pistol rounds
Hunters.pace = 1.6 -- how much quicker than a soldier they walk, chase and search
Hunters.damage = 8 -- a round (an uzi's is 12): the stun is the danger
Hunters.burst = 5 -- rounds at the uzi's rate...
Hunters.pause = 1.4 -- ...then this many seconds
Hunters.drops = 8 -- koins one spills

local SYNC_EVERY = 2 -- server ticks between HTR_STATE
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a step
local STEP = 34 -- px walked in one full step cycle, for the legs
local EMPTY_AFTER = 1 -- sends of an empty list after the last one goes, so every screen clears
local FLASH = 0.12 -- seconds a muzzle flash shows
local HURT = 0.18 -- seconds one flashes white after a hit
local ROUND_TTL = 1.2 -- seconds a round flies when its gun doesn't say (weapons' default)

local function fmt(v)
  return ("%.1f"):format(v)
end

--- Their gun: the uzi, its rounds weaker and stunning whoever they hit.
local function arms()
  local uzi = Tiers.apply(Guns.uzi, Tiers.DEFAULT)
  local gun = setmetatable({ damage = Hunters.damage, damageType = "shock" }, { __index = uzi })
  return {
    gun = gun,
    burst = Hunters.burst,
    pause = Hunters.pause,
    reach = uzi.speed * (uzi.ttl or ROUND_TTL) * 0.85,
  }
end

-- Server --------------------------------------------------------------------

local sv = nil -- { troops, syncIn, emptySends }

--- The host's set, with a walking grid over the map in play.
local function server()
  if sv then
    return sv
  end
  local troops = Troops.new({
    hunt = true, fov = Hunters.fov, alertFov = Hunters.alertFov, aware = Hunters.aware,
    health = Hunters.health, radius = Render.RADIUS, pace = Hunters.pace,
  })
  local city = Features.byName["city-map"]
  local map = city and city.map
  if map then
    troops:navigate({ x = map.left, y = map.top, w = map.w, h = map.h })
  end
  sv = { troops = troops, syncIn = 0, emptySends = 0 }
  return sv
end

--- `route` with every corner moved to the nearest open spot.
local function settle(nav, route)
  if not nav then
    return route
  end
  local out = {}
  for _, p in ipairs(route) do
    local c, r = nav:nearestOpen(p.x, p.y)
    if c then
      local x, y = nav:centre(c, r)
      out[#out + 1] = { x = x, y = y }
    end
  end
  return out
end

--- `count` hunters spread evenly round `route` ({ x, y } corners, a loop),
--- walking it. Returns them.
function Hunters:serverPatrol(_server, route, count)
  local s = server()
  route = settle(s.troops.nav, route)
  local added = {}
  if #route < 2 then
    return added
  end
  for i = 1, count do
    local start = math.floor((i - 1) * #route / count) + 1
    local h = s.troops:addSquad(route, 1, start).members[1]
    s.troops:arm(h, arms())
    added[#added + 1] = h
  end
  return added
end

--- Take every hunter away.
function Hunters:serverClear()
  if sv then
    sv.troops.list = {}
  end
end

local shown = {} -- client: id -> { x, y, dx, dy, facing, hp, alert, wary, fov, cycle, stride, flash, hurt }

--- Another map: none left on either side, and the next ones get a walking
--- grid over their own map.
function Hunters:mapChanged()
  sv, shown = nil, {}
end

function Hunters:serverStart()
  sv = nil
end

local function sync(srv)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local list = sv.troops.list
  if #list == 0 then
    if sv.emptySends >= EMPTY_AFTER then
      return
    end
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  local parts = { srv.tick }
  for _, h in ipairs(list) do
    parts[#parts + 1] = h.id
    parts[#parts + 1] = ("%.0f"):format(h.x)
    parts[#parts + 1] = ("%.0f"):format(h.y)
    parts[#parts + 1] = ("%.2f"):format(h.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, h.hp))
    parts[#parts + 1] = h.alert and 1 or (Troops.wary(h) and 2 or 0)
    parts[#parts + 1] = h.fired and 1 or 0
    h.fired = false
  end
  local msg = Protocol.encode("HTR_STATE", unpack(parts))
  for _, player in pairs(srv.players) do
    if not player.bot then
      srv:send(player, msg, true)
    end
  end
end

function Hunters:serverStep(srv, dt)
  if not sv then
    return
  end
  sv.troops:update(srv, dt)
  sync(srv)
end

--- One down: pieces on every screen, a few koins, maybe a pickup.
local function down(srv, h, by, angle)
  srv:broadcast(Protocol.encode("HTR_DOWN", h.id, fmt(h.x), fmt(h.y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(srv, h.x, h.y, Hunters.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(srv, h.x, h.y)
  end
  Features.call("serverKill", srv, { kind = "hunter", x = h.x, y = h.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Rounds owned by
--- nobody (the Combine's, the turrets', their own) pass by.
function Hunters:serverShotAt(srv, x, y, radius, by, angle, damage)
  if not sv or by == 0 then
    return false
  end
  local h, i = sv.troops:at(x, y, radius)
  if not h then
    return false
  end
  if sv.troops:hurt(h, i, damage or Troops.SHOT_DAMAGE, angle) then
    down(srv, h, by, angle)
  end
  return true
end

function Hunters:serverFreezeArea(_server, x, y, radius, seconds)
  if sv then
    sv.troops:freeze(x, y, radius, seconds)
  end
end

function Hunters:serverPanicArea(_server, x, y, radius)
  if sv then
    sv.troops:scare(x, y, radius, 0.5)
  end
end

--- The host's hunters, for tests.
function Hunters.state()
  return sv
end

-- Client --------------------------------------------------------------------

local lastTick = 0
local clock = 0

function Hunters:exitGame()
  shown, lastTick = {}, 0
end

function Hunters:update(dt)
  clock = clock + dt
  local k = math.min(1, dt * SMOOTHING)
  for _, h in pairs(shown) do
    local ex, ey = h.x - h.dx, h.y - h.dy
    local moved = math.sqrt(ex * ex + ey * ey) * k
    if ex * ex + ey * ey > SNAP * SNAP then
      h.dx, h.dy = h.x, h.y
    else
      h.dx, h.dy = h.dx + ex * k, h.dy + ey * k
      h.cycle = h.cycle + moved / STEP -- the legs keep up with the ground
    end
    local speed = moved / math.max(dt, 1e-6)
    h.stride = h.stride + (math.min(1, speed / 40) - h.stride) * math.min(1, dt * 6)
    -- The cone opens out while it is on edge and closes again after.
    local fov = h.wary and Hunters.alertFov or Hunters.fov
    h.fov = h.fov + (fov - h.fov) * math.min(1, dt * 4)
    h.flash = math.max(0, h.flash - dt)
    h.hurt = math.max(0, h.hurt - dt)
  end
end

--- Their cones of sight, on the ground under everything, as the Combine's are.
function Hunters:drawBelowCars()
  for _, h in pairs(shown) do
    Sight.draw(h.dx, h.dy, h.facing, Troops.RANGE, h.alert, clock, h.fov)
  end
end

function Hunters:drawAboveCars()
  for _, h in pairs(shown) do
    Render.draw(h.dx, h.dy, h.facing, {
      cycle = h.cycle, stride = h.stride, firing = h.flash > 0, hurt = h.hurt / HURT * 0.7,
    }, clock)
    if h.hp < Hunters.health then -- a bar under it once it is hurt
      local bw, f = 30, math.max(0, h.hp / Hunters.health)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", h.dx - bw / 2 - 1, h.dy + Render.RADIUS + 6, bw + 2, 5)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", h.dx - bw / 2, h.dy + Render.RADIUS + 7, bw * f, 3)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

Hunters.clientMessages = {
  HTR_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local seen = {}
    for i = 2, #args - 6, 7 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local h = shown[id]
        if not h then
          h = { dx = x, dy = y, cycle = love.math.random(), stride = 0, fov = Hunters.fov, flash = 0, hurt = 0,
            hp = Hunters.health }
          shown[id] = h
        end
        h.x, h.y = x, y
        h.facing = tonumber(args[i + 3]) or h.facing or 0
        local hp = tonumber(args[i + 4]) or h.hp
        if hp < h.hp then
          h.hurt = HURT
        end
        h.hp = hp
        h.alert = args[i + 5] == "1"
        h.wary = args[i + 5] ~= "0"
        if args[i + 6] == "1" then
          h.flash = FLASH
        end
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  HTR_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if id then
      shown[id] = nil
    end
    if x and y and Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle)
      require("src.features.pedestrians.sounds").play("splat", x, y, 0.8)
    end
  end,
}

return Hunters
