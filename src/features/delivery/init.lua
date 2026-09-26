-- Delivery: drivers a player hires to keep their factories fed.
--
-- A driver is hired at the shop (the Hire shelf, `Hire.price` Fcks; the
-- shop hands the purchase to `serverDeliver` and this feature answers) and
-- turns up on the road outside the door in a box truck, with their
-- employer's name over it. From then on they work on their own, on the
-- host:
--
--   * Collect: drive to one of the employer's quarries or oil wells that
--     has something made that one of the employer's factories needs for
--     what it is making now (its product's recipe, not every material its
--     hopper holds), pull up by its square (the loading zone) and load as
--     much as the factories still need, up to `Hire.slots` stacks. What the
--     factories are shortest of is fetched first, and what the employer's
--     other drivers are already carrying counts as on its way. With room
--     left and more to collect, go on to the next one first.
--   * Deliver: drive to the nearest of the employer's factories that needs
--     some of the load, and unload into its hopper. What the hopper has no
--     room for goes into the factory's yard (up to `Hire.yard` materials,
--     an even share for each material the product needs, so one can't
--     crowd out another), so a driver never sits outside a well-stocked
--     factory with a full truck; the factory feeds its hopper from the yard
--     as it works. What neither holds stays on the truck for the next
--     factory. A load nobody has needed for a while (a product was
--     switched) is left at any factory whose hopper holds it.
--   * Nothing to do: cruise the streets and look again every few seconds.
--
-- They drive by the traffic rules (bots/traffic.lua) and find their way
-- with route.lua. A wrecked truck spills its load on the road as crates
-- (pickups' material crates) and the driver is gone: hire another. When
-- their employer leaves, the drivers go home with them and are back, load
-- and all, when they return (their player file). A factory's yard is lost
-- with the factory (in ruins or gone) and is kept in the saved world.
--
-- Everyone sees the load on a truck and the crates in a yard; the employer
-- also sees what each of their drivers is doing and their trucks on the
-- minimap. Tuning is at the top of hire.lua and below.
--
-- Messages
--   server -> all    DLV_UNIT <id> <owner> <state> [<item> <n>]...  (a driver: its player id, what it does, its load)
--   server -> all    DLV_GONE <id>
--   server -> all    DLV_YARD <plotId> [<item> <n>]...               (a factory's yard; nothing after the id = empty)
--   server -> owner  DLV_LOST                                       (one of your drivers was wrecked)
--   server -> buyer  DLV_NO <reason>                                (the hire was refused: max)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Car = require("src.car")
local Kinds = require("src.features.buildings.kinds")
local Render = require("src.features.buildings.render")
local Traffic = require("src.features.bots.traffic")
local Layout = require("src.features.city-map.layout")
local Hire = require("src.features.delivery.hire")
local Route = require("src.features.delivery.route")

local Delivery = {
  name = "delivery",
  priority = 805, -- after bots (800), which drive the trucks; draws over the buildings (26)
}

-- Tuning ------------------------------------------------------------------
Delivery.speed = 190 -- px/s a driver keeps to on the way to a job
Delivery.idleSpeed = 140 -- px/s cruising about with nothing to do
Delivery.loadTime = 2.5 -- seconds parked at a square to load or unload
Delivery.lookEvery = 3 -- seconds between looks for work while idle
Delivery.minLoad = 10 -- materials worth driving for (less when that is all the factories want)
Delivery.arrive = 130 -- px from a square that counts as pulled up at it
Delivery.giveUp = 90 -- seconds on the way to one job before looking again (lost, or stuck)
Delivery.feedEvery = 0.5 -- seconds between a yard topping up its factory's hopper
Delivery.stranded = 20 -- seconds idle with a load nobody needs before leaving it at any factory that holds it

local T = Layout.TILE
local NOTICE_TIME = 4
local REASONS = {
  max = ("You already have %d delivery drivers."):format(Hire.maxPerPlayer),
  lost = "Your delivery driver was wrecked and dropped their load. Hire another at the shop.",
}

local function buildings()
  return Features.byName.buildings
end

--- The street graph of the map in play, or nil (open ground).
local function graph()
  local city = Features.byName["city-map"]
  return city and city.map and Traffic.graph(city.map)
end

--- Is the city in play (not a quest map)? Buildings only stand there.
local function inCity()
  local city = Features.byName["city-map"]
  return city == nil or city.current == city.DEFAULT
end

--- The pad of a plot, as buildings has it: the middle of the square on the
--- sidewalk below it.
local function padOf(plot)
  return plot.x + plot.w / 2, plot.y + plot.h + T / 2
end

--- Material -> n as a flat list in Kinds.materials order: item, n, item, n...
local function flat(items)
  local out = {}
  for _, m in ipairs(Kinds.materials) do
    if (items[m] or 0) > 0 then
      out[#out + 1] = m
      out[#out + 1] = math.floor(items[m])
    end
  end
  return out
end

--- The other way round, from a message's fields starting at `i`.
local function unflat(args, i)
  local out = {}
  while args[i] and args[i + 1] do
    local n = tonumber(args[i + 1])
    if Kinds.isMaterial(args[i]) and n and n > 0 then
      out[args[i]] = n
    end
    i = i + 2
  end
  return out
end

local function total(items)
  local n = 0
  for _, v in pairs(items) do
    n = n + v
  end
  return n
end

-- Client ------------------------------------------------------------------

Delivery.units = {} -- player id -> { owner, state, cargo = { item -> n } }
Delivery.yards = {} -- plot id -> { item -> n }
Delivery.notice = nil -- { text, t }

-- DLV_UNIT and DLV_YARD for a latecomer arrive in the burst with START,
-- so they are only forgotten on the way out.
function Delivery:exitGame()
  self.units = {}
  self.yards = {}
  self.notice = nil
end

function Delivery:update(dt)
  if self.notice then
    self.notice.t = self.notice.t - dt
    if self.notice.t <= 0 then
      self.notice = nil
    end
  end
end

local function say(text)
  Delivery.notice = { text = text, t = NOTICE_TIME }
end

--- A row of little heaps with their counts, centred on (cx, y).
local function drawLoad(items, cx, y, alpha)
  local list = flat(items)
  local n = #list / 2
  if n == 0 then
    return
  end
  local font = UI.fonts.small
  local w = 44
  local x0 = cx - (n * w) / 2 + w / 2
  love.graphics.setColor(0, 0, 0, 0.45 * alpha)
  love.graphics.rectangle("fill", x0 - w / 2 - 2, y - 11, n * w + 4, 22, 5)
  for k = 1, n do
    local x = x0 + (k - 1) * w
    love.graphics.push()
    love.graphics.translate(x - 10, y)
    love.graphics.scale(0.5)
    Render.itemIcon(list[2 * k - 1], 0, 0)
    love.graphics.pop()
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.print(tostring(list[2 * k]), x - 1, y - font:getHeight() / 2)
  end
end

--- A factory's yard: a crate per material on the sidewalk beside its
--- square, and how much is waiting.
function Delivery:drawBelowCars()
  local re = Features.byName["real-estate"]
  if not re then
    return
  end
  for id, items in pairs(self.yards) do
    local plot = re.plots[id]
    if plot and next(items) then
      local px, py = padOf(plot)
      local x = px + 44
      for _, m in ipairs(Kinds.materials) do
        if (items[m] or 0) > 0 then
          love.graphics.setColor(0, 0, 0, 0.3)
          love.graphics.rectangle("fill", x - 11 + 3, py - 11 + 3, 22, 22, 2)
          love.graphics.setColor(0.55, 0.4, 0.22)
          love.graphics.rectangle("fill", x - 11, py - 11, 22, 22, 2)
          love.graphics.push()
          love.graphics.translate(x, py)
          love.graphics.scale(0.6)
          Render.itemIcon(m, 0, 0)
          love.graphics.pop()
          x = x + 26
        end
      end
      love.graphics.setFont(UI.fonts.small)
      UI.label(("yard %d"):format(total(items)), px + 33, py + 12, { 0.95, 0.85, 0.55 })
    end
  end
end

--- Over each truck: what it carries, and for its employer what it is up to.
function Delivery:drawAboveCars(client)
  for id, u in pairs(self.units) do
    local x, y = client:pose(id)
    if x then
      drawLoad(u.cargo, x, y + 42, 1)
      if u.owner == client.myId then
        love.graphics.setFont(UI.fonts.small)
        local text = Hire.states[u.state] or u.state
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.printf(text, x - 79, y + 59, 160, "center")
        love.graphics.setColor(1, 0.8, 0.4)
        love.graphics.printf(text, x - 80, y + 58, 160, "center")
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- My own trucks on the minimap: a square in my colour with a dark rim.
function Delivery:drawOnMinimap(client, toMap)
  for id, u in pairs(self.units) do
    if u.owner == client.myId then
      local wx, wy = client:pose(id)
      if wx then
        local x, y = toMap(wx, wy)
        local c = Car.colorFor(client.myId)
        love.graphics.setColor(0.1, 0.1, 0.1)
        love.graphics.rectangle("fill", x - 4, y - 4, 8, 8, 1)
        love.graphics.setColor(c[1], c[2], c[3])
        love.graphics.rectangle("fill", x - 3, y - 3, 6, 6, 1)
      end
    end
  end
end

function Delivery:drawHUD()
  local n = self.notice
  if not n then
    return
  end
  local w = love.graphics.getWidth()
  love.graphics.setFont(UI.fonts.body)
  local alpha = math.min(1, n.t)
  love.graphics.setColor(0, 0, 0, 0.6 * alpha)
  love.graphics.printf(n.text, 2, 122, w, "center")
  love.graphics.setColor(1, 0.75, 0.4, alpha)
  love.graphics.printf(n.text, 0, 120, w, "center")
  love.graphics.setColor(1, 1, 1)
end

Delivery.clientMessages = {
  DLV_UNIT = function(_client, args)
    local id, owner = tonumber(args[1]), tonumber(args[2])
    if id and owner then
      Delivery.units[id] = { owner = owner, state = args[3] or "idle", cargo = unflat(args, 4) }
    end
  end,
  DLV_GONE = function(_client, args)
    local id = tonumber(args[1])
    if id then
      Delivery.units[id] = nil
    end
  end,
  DLV_YARD = function(_client, args)
    local id = tonumber(args[1])
    if id then
      local items = unflat(args, 2)
      Delivery.yards[id] = next(items) and items or nil
    end
  end,
  DLV_LOST = function()
    say(REASONS.lost)
  end,
  DLV_NO = function(_client, args)
    say(REASONS[args[1]] or "You can't hire a driver right now.")
  end,
}

-- Server ------------------------------------------------------------------

-- drivers: npc id -> { npc, owner (player id), cargo = { item -> n }, job, look }
--   job: nil (idle) or { state = pickup | loading | drop | unloading, id (plot), x, y (its square),
--        lane (route.lua's target), age, t }
-- yards: plot id -> { owner, items = { item -> n } }
local sv = nil

function Delivery:serverStart()
  sv = { drivers = {}, yards = {}, feed = 0 }
end

local function unitMessage(d)
  local state = d.job and d.job.state or "idle"
  return Protocol.encode("DLV_UNIT", d.npc.id, d.owner, state, unpack(flat(d.cargo)))
end

local function tell(server, d)
  server:broadcast(unitMessage(d))
end

local function yardMessage(id)
  local y = sv.yards[id]
  return Protocol.encode("DLV_YARD", id, unpack(flat(y and y.items or {})))
end

--- The drivers `owner` has on the road.
local function driversOf(owner)
  local out = {}
  for _, d in pairs(sv.drivers) do
    if d.owner == owner then
      out[#out + 1] = d
    end
  end
  table.sort(out, function(a, b)
    return a.npc.id < b.npc.id
  end)
  return out
end

--- The host's building on plot `id` if it still stands and is `owner`'s.
local function standing(id, owner)
  local b = buildings()
  local rec = b and b.serverBuilding and b:serverBuilding(id)
  return rec and rec.owner == owner and rec.hp > 0 and rec or nil
end

--- `owner`'s buildings still standing, sorted into what digs or pumps a
--- material (sources) and what runs on them (factories): { id, x, y, b, kind }.
local function premises(owner)
  local b = buildings()
  local sources, factories = {}, {}
  if not (b and b.ofKind) then
    return sources, factories
  end
  for _, kind in ipairs(Kinds.list) do
    for _, at in ipairs(b:ofKind(kind.key, owner)) do
      if not at.ruined then
        local entry = { id = at.id, x = at.x, y = at.y, b = at.building, kind = kind }
        if kind.hopper and next(kind.hopper) then
          factories[#factories + 1] = entry
        elseif kind.products and not next(kind.inputs or {}) then
          sources[#sources + 1] = entry
        end
      end
    end
  end
  return sources, factories
end

--- What factory `f` is making needs per batch: item -> n (its product's
--- recipe, kinds.lua). A factory's hopper takes more materials than that
--- (every product's), but only these keep it working.
local function needs(f)
  return Kinds.recipe(f.kind, f.b.product).inputs
end

--- Room left in factory `f`'s yard for `item`. Each material its product
--- needs gets an even share of the yard, so a pile of one can't crowd out
--- another it can't work without. `any`: a load nobody needs, taken by any
--- factory whose hopper holds that material, as long as the yard has room.
local function yardRoom(f, item, any)
  local y = sv.yards[f.id]
  local items = y and y.items or {}
  local free = Hire.yard - total(items)
  if any then
    return f.kind.hopper[item] and math.max(0, free) or 0
  end
  local inputs = needs(f)
  if not inputs[item] then
    return 0
  end
  local count = 0
  for _ in pairs(inputs) do
    count = count + 1
  end
  local share = math.floor(Hire.yard / count)
  return math.max(0, math.min(free, share - (items[item] or 0)))
end

--- How much of `item` factory `f` takes right now: hopper, then yard. Only
--- what its product needs, unless `any` (see yardRoom).
local function takes(f, item, any)
  if not (any or needs(f)[item]) then
    return 0
  end
  return buildings():serverHopperRoom(f.id, item) + yardRoom(f, item, any)
end

--- How much more of `item` the owner's factories need than the owner's
--- drivers are already carrying to them.
local function demand(d, factories, item)
  local n = 0
  for _, f in ipairs(factories) do
    n = n + takes(f, item)
  end
  for _, o in pairs(sv.drivers) do
    if o.owner == d.owner then
      n = n - (o.cargo[item] or 0)
    end
  end
  return n
end

--- How short the owner's factories are of `item`: the least any factory
--- needing it has in its hopper and yard, counted in batches. A factory
--- with none of one of its materials is standing still, so that material
--- is fetched first.
local function stockOf(factories, item)
  local least
  for _, f in ipairs(factories) do
    local per = needs(f)[item]
    if per then
      local y = sv.yards[f.id]
      local have = (f.b.hopper[item] or 0) + (y and y.items[item] or 0)
      least = math.min(least or math.huge, have / per)
    end
  end
  return least or math.huge
end

local function dist2(d, x, y)
  local car = d.npc.car
  return (car.x - x) ^ 2 + (car.y - y) ^ 2
end

--- Is another of the owner's drivers already on its way to collect at plot `id`?
local function claimed(d, id)
  for _, o in pairs(sv.drivers) do
    if o ~= d and o.job and o.job.id == id and (o.job.state == "pickup" or o.job.state == "loading") then
      return true
    end
  end
  return false
end

--- The source worth collecting from: of those with a load worth the trip,
--- the one making what the factories are shortest of, the nearest of those.
local function bestPickup(d, sources, factories)
  local best, bestStock, bestD
  for _, s in ipairs(sources) do
    local item = s.kind.products[s.b.product]
    local have = math.floor(s.b.output or 0)
    if item and Kinds.isMaterial(item) and have >= 1 and not claimed(d, s.id) then
      local room = Kinds.room(d.cargo, Hire.slots, item)
      local wanted = demand(d, factories, item)
      local want = math.min(have, room, wanted)
      if want >= 1 and want >= math.min(Delivery.minLoad, room, wanted) then
        local stock, dd = stockOf(factories, item), dist2(d, s.x, s.y)
        if not best or stock < bestStock or (stock == bestStock and dd < bestD) then
          best, bestStock, bestD = s, stock, dd
        end
      end
    end
  end
  return best
end

--- The nearest factory that takes some of what `d` carries (`any`: see yardRoom).
local function bestDrop(d, factories, any)
  local best, bestD
  for _, f in ipairs(factories) do
    for item, n in pairs(d.cargo) do
      if n > 0 and takes(f, item, any) > 0 then
        local dd = dist2(d, f.x, f.y)
        if not bestD or dd < bestD then
          best, bestD = f, dd
        end
        break
      end
    end
  end
  return best
end

local function setJob(server, d, state, at, any)
  local before = d.job and d.job.state or "idle"
  if at then
    d.job = { state = state, id = at.id, x = at.x, y = at.y, age = 0, any = any }
  else
    d.job = nil
  end
  if (d.job and d.job.state or "idle") ~= before then
    tell(server, d)
  end
end

--- Pick what `d` does next: top the load up while there is room and
--- something worth collecting, else deliver, else wait and look again. A
--- load no factory has needed for `Delivery.stranded` seconds (its product
--- was switched) goes to any factory that can hold it, so it doesn't take
--- up the truck for good.
local function plan(server, d)
  local sources, factories = premises(d.owner)
  local pick = Kinds.slotsUsed(d.cargo) < Hire.slots and bestPickup(d, sources, factories)
  local drop = next(d.cargo) and bestDrop(d, factories)
  if pick then
    setJob(server, d, "pickup", pick)
  elseif drop then
    setJob(server, d, "drop", drop)
  elseif next(d.cargo) and (d.stranded or 0) >= Delivery.stranded and bestDrop(d, factories, true) then
    setJob(server, d, "drop", bestDrop(d, factories, true), true)
  else
    setJob(server, d, nil)
    d.look = Delivery.lookEvery
  end
end

--- Load what the factories need from the source on the job's plot.
local function load(server, d)
  local _, factories = premises(d.owner)
  local rec = standing(d.job.id, d.owner)
  local kind = rec and Kinds.byKey[rec.kind]
  local item = kind and kind.products and kind.products[rec.product]
  if not (item and Kinds.isMaterial(item)) then
    return
  end
  local want = math.min(Kinds.room(d.cargo, Hire.slots, item), demand(d, factories, item))
  if want >= 1 then
    local _, taken = buildings():serverTakeOutput(server, d.job.id, want)
    if taken > 0 then
      d.cargo[item] = (d.cargo[item] or 0) + taken
    end
  end
end

--- Unload at the factory on the job's plot what it takes: its hopper
--- first, then its yard. Anything on the truck that no factory needs any
--- more (a product was switched on the way) is left here too if this
--- factory's hopper holds it, so it doesn't take up a stack for good.
local function unload(server, d)
  local b = buildings()
  local id = d.job.id
  local rec = standing(id, d.owner)
  local kind = rec and Kinds.byKey[rec.kind]
  if not kind then
    return
  end
  local _, factories = premises(d.owner)
  local f = { id = id, kind = kind, b = rec }
  local yardChanged = false
  for _, item in ipairs(Kinds.materials) do
    local n = d.cargo[item] or 0
    local any = d.job.any or (n > 0 and not needs(f)[item] and demand(d, factories, item) + n <= 0)
    if n > 0 and (any or needs(f)[item]) then
      n = n - b:serverFillHopper(server, id, item, n)
      local into = math.min(n, yardRoom(f, item, any))
      if into > 0 then
        local y = sv.yards[id] or { owner = d.owner, items = {} }
        sv.yards[id] = y
        y.items[item] = (y.items[item] or 0) + into
        n = n - into
        yardChanged = true
      end
      d.cargo[item] = n > 0 and n or nil
    end
  end
  if yardChanged then
    server:broadcast(yardMessage(id))
  end
end

--- Is the truck stopped by the job's square?
local function arrived(d)
  local car = d.npc.car
  return dist2(d, d.job.x, d.job.y) <= Delivery.arrive ^ 2 and math.abs(car.speed) < 20
end

local function step(server, d, dt)
  local car = d.npc.car
  if not car or car.hidden then
    return -- wrecked (going), or parked out of sight on a map without traffic
  end
  local job = d.job
  if job or not next(d.cargo) then
    d.stranded = 0
  else
    d.stranded = (d.stranded or 0) + dt -- idle with a load nobody takes
  end
  if not job then
    d.look = (d.look or 0) - dt
    if d.look <= 0 then
      plan(server, d)
    end
    return
  end
  if not standing(job.id, d.owner) then
    plan(server, d) -- the building came down or changed hands
    return
  end
  if job.state == "pickup" or job.state == "drop" then
    job.age = job.age + dt
    if arrived(d) then
      job.state, job.t = job.state == "pickup" and "loading" or "unloading", Delivery.loadTime
      tell(server, d)
    elseif job.age > Delivery.giveUp then
      d.npc.ai.route = nil -- find the street again
      plan(server, d)
    end
  else
    job.t = job.t - dt
    if job.t <= 0 then
      if job.state == "loading" then
        load(server, d)
      else
        unload(server, d)
      end
      tell(server, d)
      plan(server, d)
    end
  end
end

-- The brain bots runs every tick for a driver: steer to the job, hold still
-- while loading, cruise about with nothing to do.
local Brain = {}

function Brain.think(server, npc, dt)
  local bots = Features.byName.bots
  local d = sv and sv.drivers[npc.id]
  local job = d and d.job
  local car, input = npc.car, npc.input
  if not job then
    bots:cruise(server, npc, Delivery.idleSpeed)
    return
  end
  if job.state == "loading" or job.state == "unloading" then
    input.steer = 0
    input.throttle = Traffic.throttleFor(car, 0)
    return
  end
  local g = graph()
  if not g then
    -- Open ground: straight at the square, slowing to stop on it.
    local dist = bots.driveTowards(npc, job.x, job.y, 1)
    input.throttle = Traffic.throttleFor(car, math.min(Delivery.speed, math.max(0, dist - 60) * 1.2))
    bots.unstick(npc, dt)
    return
  end
  if not job.lane or job.graph ~= g then
    job.lane, job.graph = Route.target(g, job.x, job.y), g
  end
  local speed = Delivery.speed
  local route = npc.ai.route
  if route and job.lane then
    local along = Route.on(route, job.lane) and Route.along(route, car)
    if along and along <= job.lane.stop + 40 then
      -- On the street the square is on: brake to stop beside it, the way this truck brakes.
      local room = math.max(0, job.lane.stop - along)
      speed = math.min(speed, room * 1.6, math.sqrt(2 * (car.brake or 700) * 0.5 * room))
    elseif route.plannedFrom ~= job.lane then
      route.next = Route.nextExit(route, job.lane) or route.next
      route.plannedFrom = job.lane
    end
  end
  bots:cruise(server, npc, speed)
end

--- Put a driver for `owner` on the road at (x, y), carrying `cargo`.
local function hire(server, owner, x, y, angle, cargo)
  local bots = Features.byName.bots
  if not (bots and bots.spawnNpc) then
    return nil
  end
  local npc = bots:spawnNpc(server, { name = owner.name, x = x, y = y, angle = angle, brain = Brain, civilian = true })
  local vehicles, model = Features.byName.vehicles, Hire.truck()
  if vehicles and vehicles.serverSetModel and model then
    vehicles:serverSetModel(server, npc.car, model)
  end
  local d = { npc = npc, owner = owner.id, cargo = cargo or {}, look = 0 }
  sv.drivers[npc.id] = d
  tell(server, d)
  return d
end

--- Take a driver off the road for good.
local function dismiss(server, d)
  sv.drivers[d.npc.id] = nil
  server:broadcast(Protocol.encode("DLV_GONE", d.npc.id))
  local bots = Features.byName.bots
  if bots and bots.removeNpc then
    bots:removeNpc(server, d.npc)
  end
end

--- The shop sold a driver: they turn up at (x, y), outside its door.
function Delivery:serverDeliver(server, player, item, x, y, angle)
  if item ~= Hire.ITEM or not sv or player.bot then
    return false
  end
  if #driversOf(player.id) >= Hire.maxPerPlayer then
    server:send(player, Protocol.encode("DLV_NO", "max"))
    return false
  end
  return hire(server, player, x, y, angle or 0) ~= nil
end

--- A wrecked truck: its load goes on the road where it went up, next step.
function Delivery:serverKill(_server, kill)
  local d = sv and kill.kind == "car" and kill.victim and sv.drivers[kill.victim]
  if d then
    d.wreck = { x = kill.x, y = kill.y }
  end
end

--- Spill `d`'s load around (x, y) as crates.
local function spill(server, d, x, y)
  local pickups = Features.byName.pickups
  if not (pickups and pickups.serverDrop) then
    return
  end
  local k = 0
  for _, item in ipairs(Kinds.materials) do
    local n = d.cargo[item] or 0
    if n > 0 then
      local a = k * 2.4
      pickups:serverDrop(server, item, x + math.cos(a) * 26, y + math.sin(a) * 26, n)
      k = k + 1
    end
  end
  d.cargo = {}
end

--- Every half second each yard feeds its factory's hopper; a yard whose
--- factory fell or changed hands is lost with it (only judged in the city,
--- where the buildings stand).
local function feedYards(server)
  local b = buildings()
  for id, y in pairs(sv.yards) do
    if not standing(id, y.owner) then
      if inCity() then
        sv.yards[id] = nil
        server:broadcast(yardMessage(id))
      end
    else
      local changed = false
      for item, n in pairs(y.items) do
        local moved = b:serverFillHopper(server, id, item, n)
        if moved > 0 then
          y.items[item] = n - moved > 0 and n - moved or nil
          changed = true
        end
      end
      if not next(y.items) then
        sv.yards[id] = nil
      end
      if changed then
        server:broadcast(yardMessage(id))
      end
    end
  end
end

function Delivery:serverStep(server, dt)
  if not sv then
    return
  end
  for _, d in pairs(sv.drivers) do
    if d.wreck then
      spill(server, d, d.wreck.x, d.wreck.y)
      local owner = server.players[d.owner]
      if owner then
        server:send(owner, Protocol.encode("DLV_LOST"))
      end
      dismiss(server, d)
    end
  end
  for _, d in pairs(sv.drivers) do
    step(server, d, dt)
  end
  sv.feed = sv.feed - dt
  if sv.feed <= 0 and buildings() then
    sv.feed = Delivery.feedEvery
    feedYards(server)
  end
end

--- Leaving the city (a quest) or coming back: every driver starts over
--- from wherever bots put them. Their loads and the yards stay.
function Delivery:mapChanged(_map, server)
  if not (server and sv) then
    return
  end
  for _, d in pairs(sv.drivers) do
    d.job, d.look = nil, Delivery.lookEvery
    tell(server, d)
  end
end

--- Someone arriving mid-game hears every driver and every yard.
function Delivery:serverPlayerJoined(server, player)
  if not (sv and server.started) or player.bot then
    return
  end
  for _, d in pairs(sv.drivers) do
    server:send(player, unitMessage(d))
  end
  for id in pairs(sv.yards) do
    server:send(player, yardMessage(id))
  end
end

--- An employer who leaves takes their drivers home (their player file keeps them).
function Delivery:serverPlayerLeft(server, player)
  if not sv or player.bot then
    return
  end
  for _, d in ipairs(driversOf(player.id)) do
    dismiss(server, d)
  end
end

-- Saved games -------------------------------------------------------------

local SAVE_VERSION = 1

--- A load read back from a file: materials only, whole numbers, and no
--- more than a truck holds.
local function cargoFrom(t)
  local cargo = {}
  if type(t) ~= "table" then
    return cargo
  end
  for _, m in ipairs(Kinds.materials) do
    local n = t[m]
    if type(n) == "number" and n >= 1 then
      n = math.min(math.floor(n), Kinds.room(cargo, Hire.slots, m))
      cargo[m] = n > 0 and n or nil
    end
  end
  return cargo
end

--- A player's drivers and what each is carrying.
function Delivery:serverSavePlayer(_server, player)
  if not sv or player.bot then
    return nil
  end
  local list = {}
  for _, d in ipairs(driversOf(player.id)) do
    list[#list + 1] = { cargo = d.cargo }
  end
  return { version = SAVE_VERSION, drivers = list }
end

--- Their drivers are back on the road, somewhere in the city's traffic.
function Delivery:serverLoadPlayer(server, player, data)
  if not sv or type(data) ~= "table" or type(data.drivers) ~= "table" then
    return
  end
  if (tonumber(data.version) or 0) > SAVE_VERSION then
    return
  end
  for i, rec in ipairs(data.drivers) do
    if i > Hire.maxPerPlayer or #driversOf(player.id) >= Hire.maxPerPlayer then
      break
    end
    local g = graph()
    local x, y, angle
    if g then
      x, y, angle = Traffic.randomLanePoint(g, server.vehicles, 150)
    end
    if not x then
      x, y, angle = Features.bodyPose(server, player)
      y = (y or 0) + 120
    end
    hire(server, player, x or 0, y, angle or 0, cargoFrom(type(rec) == "table" and rec.cargo))
  end
end

--- The city's plots, while on another map too (buildings keeps them the same way).
local function cityPlots()
  local city, re = Features.byName["city-map"], Features.byName["real-estate"]
  if not (city and re) then
    return nil
  end
  if city.current == city.DEFAULT then
    return re.plots
  end
  return city.home and re.plotsOf and re.plotsOf(city.home)
end

--- Every yard, by the block its factory stands on.
function Delivery:serverSaveWorld(server)
  local plots = cityPlots()
  if not (sv and plots) then
    return nil
  end
  local list = {}
  for id, y in pairs(sv.yards) do
    local plot = plots[id]
    if plot and plot.block and server.names[y.owner] then
      list[#list + 1] = { bi = plot.block.bi, bj = plot.block.bj, owner = y.owner, items = y.items }
    end
  end
  table.sort(list, function(a, b)
    return a.bi < b.bi or (a.bi == b.bi and a.bj < b.bj)
  end)
  return { version = SAVE_VERSION, yards = list }
end

--- The yards come back beside factories that came back (buildings loads first).
function Delivery:serverLoadWorld(server, data)
  local re = Features.byName["real-estate"]
  if not (sv and re and re.plotOnBlock) or type(data) ~= "table" or type(data.yards) ~= "table" then
    return
  end
  if (tonumber(data.version) or 0) > SAVE_VERSION then
    return
  end
  for _, rec in ipairs(data.yards) do
    local plot = type(rec) == "table" and tonumber(rec.bi) and tonumber(rec.bj)
      and re.plotOnBlock(re.plots, rec.bi, rec.bj)
    if plot and standing(plot.id, rec.owner) then
      local items = cargoFrom(rec.items)
      local n = 0
      for m, v in pairs(items) do
        items[m] = math.min(v, Hire.yard - n)
        n = n + items[m]
        items[m] = items[m] > 0 and items[m] or nil
      end
      if next(items) then
        sv.yards[plot.id] = { owner = rec.owner, items = items }
        server:broadcast(yardMessage(plot.id))
      end
    end
  end
end

return Delivery
