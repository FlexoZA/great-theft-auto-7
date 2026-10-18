-- Halcyon's interceptors on the Overpass (docs/cyber-feud.md, "Halcyon"):
-- patrol cars parked on the shoulder at the map's `interceptors` posts that
-- come after you, ram you and shoot out of the window. troops.lua starts
-- and stops them with the rest of the level; their heads are
-- interceptor_brain.lua.
--
-- Each is an NPC driver from the bots feature (Bots:spawnNpc), so the
-- core moves its car, collisions and damage treat it as any car, and
-- wrecking it is a kill like any other. A grey SUV, tuned faster than it
-- left the factory (`maxSpeed`, `accel`) and armoured (`health`). `count` for one human, one
-- more for each human past the first, spread over the posts from the
-- bottom of the map. Wrecked (weapons blows it up and takes the car out of
-- the world), one spills koins and is taken off for good.
--
-- Enemies don't count them as players to go after (the `serverHidden`
-- hook, through init.lua): they are Halcyon's own, and the Static's
-- gangers leave cars to the war-rigs.
--
-- On every screen: a light bar flashing magenta and blue, and the officer
-- leaning out of the driver's window with his gun out.
--
-- Messages
--   server -> all  INT_UNITS [<id>]...   the players who are interceptors (all of them, each time it changes)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Car = require("src.car")
local Body = require("src.body")
local Bosses = require("src.features.bosses")
local Brain = require("src.features.cyber-feud.interceptor_brain")

local Interceptors = {}

-- Tuning ------------------------------------------------------------------
Interceptors.count = 3 -- for one human, one more for each human past the first (Bosses.plus), and more on a job
-- finished before
Interceptors.model = "suv-bluegrey"
Interceptors.maxSpeed = 540 -- px/s; a stock car tops out round 500
Interceptors.accel = 1.3 -- times the model's own
Interceptors.drops = 8 -- koins one spills when wrecked
Interceptors.health = 220 -- armoured; the stock SUV takes 150

local WRECK_GONE = 0.3 -- seconds after it is wrecked that the driver goes too

local MAGENTA = { 1.00, 0.24, 0.78 }
local BLUE = { 0.30, 0.50, 1.00 }
local LOOK = { -- the officer leaning out: Halcyon grey, a white helmet
  shirt = { 0.50, 0.52, 0.56 }, vest = { 0.66, 0.68, 0.72 }, hat = { 0.90, 0.91, 0.94 },
  skin = { 0.80, 0.70, 0.62 }, gun = true, gunLength = 8, shadow = false,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { units = { npc... } }

local function bots()
  return Features.byName.bots
end

local function broadcastUnits(server)
  local ids = {}
  for _, npc in ipairs(sv and sv.units or {}) do
    ids[#ids + 1] = npc.id
  end
  server:broadcast(Protocol.encode("INT_UNITS", unpack(ids)))
end

--- One interceptor parked on post `p` ({ x, y, angle }).
local function spawn(server, B, p, n)
  local npc = B:spawnNpc(server, { name = "Halcyon " .. n, x = p.x, y = p.y, angle = p.angle, brain = Brain,
    interceptor = true })
  B:park(npc, false) -- the Overpass has no traffic, so it was born parked
  local vehicles = Features.byName.vehicles
  local Catalog = require("src.features.vehicles.catalog")
  local model = Catalog.byKey[Interceptors.model]
  if vehicles and model then
    vehicles:serverSetModel(server, npc.car, model)
  end
  local car = npc.car
  car.maxSpeed = math.max(car.maxSpeed, Interceptors.maxSpeed)
  car.accel = car.accel * Interceptors.accel
  local weapons = Features.byName.weapons
  if weapons and weapons.serverSetCarMaxHealth then
    weapons:serverSetCarMaxHealth(server, car, Bosses.enemyHealth(Interceptors.health))
  end
  return npc
end

--- Park interceptors on `map`'s `interceptors` posts. Nothing on a map without them.
function Interceptors.serverStart(server, map)
  Interceptors.serverStop(server)
  local B = bots()
  if not (map.interceptors and B) then
    return
  end
  sv = { units = {} }
  local posts = map.interceptors
  local n = math.min(#posts, Bosses.plus(Interceptors.count, server))
  for i = 1, n do
    sv.units[#sv.units + 1] = spawn(server, B, posts[i], i)
  end
  broadcastUnits(server)
end

function Interceptors.serverStop(server)
  if not sv then
    return
  end
  local B = bots()
  for _, npc in ipairs(sv.units) do
    if B and server.players[npc.id] then
      B:removeNpc(server, npc)
    end
  end
  sv = nil
  server:broadcast(Protocol.encode("INT_UNITS"))
end

--- The wrecked spill koins and are gone a moment after.
function Interceptors.serverStep(server)
  if not sv then
    return
  end
  local now = love.timer.getTime()
  local B = bots()
  for i = #sv.units, 1, -1 do
    local npc = sv.units[i]
    if npc.wreckedAt and not npc.paid then
      npc.paid = true
      local money = Features.byName.money
      if money and money.drop then
        money:drop(server, npc.car.x, npc.car.y, Interceptors.drops)
      end
    end
    if npc.wreckedAt and now - npc.wreckedAt >= WRECK_GONE then
      table.remove(sv.units, i)
      if B and server.players[npc.id] then
        B:removeNpc(server, npc)
      end
      broadcastUnits(server)
    end
  end
end

--- A player joining mid-level hears which cars are interceptors.
function Interceptors.serverPlayerJoined(server, player)
  if sv and not player.bot then
    local ids = {}
    for _, npc in ipairs(sv.units) do
      ids[#ids + 1] = npc.id
    end
    server:send(player, Protocol.encode("INT_UNITS", unpack(ids)))
  end
end

--- Is `player` one of them (for `serverHidden`)?
function Interceptors.isOne(player)
  return player.interceptor == true
end

--- For tests.
function Interceptors.server()
  return sv
end

-- Client --------------------------------------------------------------------

local units = {} -- player id -> true
local clock = 0

function Interceptors.clear()
  units = {}
end

function Interceptors.update(dt)
  clock = clock + dt
end

--- Over each one: the light bar flashing, and the officer out of the window.
function Interceptors.drawAboveCars(client)
  local on = math.floor(clock * 6) % 2 == 0
  for id in pairs(units) do
    local c = client:vehicleOf(id)
    if c and not c.hidden then
      local half = Car.HEIGHT / 2
      love.graphics.push()
      love.graphics.translate(c.dx, c.dy)
      love.graphics.rotate(c.dangle)
      -- The officer, out of the driver's window (left), facing the way the car goes.
      Body.person(-2, -half - 4, 0, 0, LOOK)
      love.graphics.translate(-3, 0)
      love.graphics.setColor(0.10, 0.10, 0.12)
      love.graphics.rectangle("fill", -2, -half + 2, 4, Car.HEIGHT - 4, 1)
      local a, b = on and MAGENTA or BLUE, on and BLUE or MAGENTA
      love.graphics.setColor(a)
      love.graphics.rectangle("fill", -2, -half + 2, 4, half - 2, 1)
      love.graphics.setColor(b)
      love.graphics.rectangle("fill", -2, 0, 4, half - 2, 1)
      love.graphics.pop()
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- At night, the light bar lights the road round it.
function Interceptors.drawNightLights(client, glow)
  local on = math.floor(clock * 6) % 2 == 0
  for id in pairs(units) do
    local c = client:vehicleOf(id)
    if c and not c.hidden then
      local side = on and -1 or 1
      local ox, oy = -math.sin(c.dangle) * side * 12, math.cos(c.dangle) * side * 12
      glow(c.dx + ox, c.dy + oy, 90, on and MAGENTA or BLUE, 0.8)
    end
  end
end

Interceptors.clientMessages = {
  INT_UNITS = function(_client, args)
    units = {}
    for _, a in ipairs(args) do
      local id = tonumber(a)
      if id and id == id then -- never NaN: it can't be a key
        units[id] = true
      end
    end
  end,
}

return Interceptors
