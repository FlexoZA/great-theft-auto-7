-- Handsy Man: a repairman a player hires to fix their damaged buildings.
--
-- He is hired at the shop (the Hire shelf, `Hire.price` Fcks; the shop
-- hands the purchase to `serverDeliver` and this feature answers). The
-- shop only gets him when something of the buyer's needs fixing and they
-- can still pay for some of it after his fee; otherwise the hire is
-- refused with the reason on the shop screen. He turns up on the road
-- outside the door in a pickup and works on his own, on the host:
--
--   * Drive: to the nearest of his employer's damaged buildings (ruins
--     too) they can pay something towards, and pull up by its square.
--   * Repair: quote and charge for the job up front, at `Hire.markup` times
--     the repair menu's price (Kinds.repairCost), and `Hire.ruinMarkup`
--     times that again to rebuild a ruin: all of it, or as much as the
--     wallet covers. A ruin is rebuilt whole or not at all. Then mend
--     `Hire.rate` hit points a second until what was paid for is done.
--   * Home: nothing left to fix, or nothing the wallet covers: tell the
--     employer, drive back to the shop's door and go. New damage on the way
--     turns him round.
--
-- He drives by the traffic rules (bots/traffic.lua) and finds his way with
-- delivery's route.lua. His pickup is an NPC car like any other: it can be
-- shot and wrecked, and then he is gone (whatever was paid for and not yet
-- mended is given back). Away from the city (a quest) he waits. When his
-- employer leaves he finishes the job in hand at once and goes home with
-- them, and is back when they return (their player file).
--
-- Messages
--   server -> all    HSY_UNIT <id> <owner> <state> [<plotId>]  (a Handsy Man: what he does, where)
--   server -> all    HSY_GONE <id>
--   server -> owner  HSY_NEWS <what>                          (done | broke | lost | refund <fcks>)
--   server -> buyer  HSY_NO <reason>                           (the hire was refused: max | nowork | broke)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Car = require("src.car")
local Kinds = require("src.features.buildings.kinds")
local Traffic = require("src.features.bots.traffic")
local Route = require("src.features.delivery.route")
local Hire = require("src.features.handsy-man.hire")

local Handsy = {
  name = "handsy-man",
  priority = 806, -- after bots (800), which drive the pickups
}

-- Tuning ------------------------------------------------------------------
Handsy.speed = 190 -- px/s on the way to a job
Handsy.idleSpeed = 140 -- px/s cruising about while there is nothing to do here (a quest map)
Handsy.lookEvery = 3 -- seconds between looks for work while idle or on the way home
Handsy.arrive = 130 -- px from a square (or the shop's door) that counts as pulled up at it
Handsy.giveUp = 90 -- seconds on the way somewhere before looking again (lost, or stuck)

local NOTICE_TIME = 4
local NEWS = {
  done = "Your buildings are all fixed. Your Handsy Man is heading home.",
  broke = "You're out of Fcks for repairs. Your Handsy Man is heading home.",
  lost = "Your Handsy Man was wrecked.",
}
local REFUSED = {
  max = "You already have a Handsy Man at work.",
  nowork = "None of your buildings need fixing. There's no work for a Handsy Man.",
  broke = "After his fee you couldn't pay for any of the repairs.",
}

local function buildings()
  return Features.byName.buildings
end

local function money()
  return Features.byName.money
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

--- The shop, while the city is in play; nil elsewhere or without it.
local function shopHere()
  local shop = Features.byName.shop
  return shop and shop.here and shop:here()
end

-- Client ------------------------------------------------------------------

Handsy.units = {} -- player id -> { owner, state, plot }
Handsy.notice = nil -- { text, t }
Handsy.refused = nil -- a refusal to put on the shop screen next frame

-- HSY_UNIT for a latecomer arrives in the burst with START, so they are
-- only forgotten on the way out.
function Handsy:exitGame()
  self.units = {}
  self.notice, self.refused = nil, nil
end

local function say(text)
  Handsy.notice = { text = text, t = NOTICE_TIME }
end

function Handsy:update(dt)
  -- The shop says "can't be delivered" right after our reason (SHOP_NO
  -- follows HSY_NO in the same burst); ours is the useful one, so it goes
  -- up a frame later, over the shop's.
  if self.refused then
    local shop = Features.byName.shop
    if shop and shop.open and shop.say then
      shop:say(self.refused)
    else
      say(self.refused)
    end
    self.refused = nil
  end
  if self.notice then
    self.notice.t = self.notice.t - dt
    if self.notice.t <= 0 then
      self.notice = nil
    end
  end
end

--- Where the building on plot `id` meets its square: the middle of its
--- front wall.
local function frontOf(id)
  local re = Features.byName["real-estate"]
  local plot = re and re.plots and re.plots[id]
  if plot then
    return plot.x + plot.w / 2, plot.y + plot.h - 4
  end
end

--- Welding sparks flying off (x, y), new ones every few frames.
local function sparks(x, y)
  local t = love.timer.getTime()
  local frame = math.floor(t * 14)
  love.graphics.setLineWidth(2)
  for i = 1, 6 do
    local seed = (frame * 7 + i * 13) % 31
    local a = -math.pi / 2 + (seed / 31 - 0.5) * 2.4
    local len = 8 + (seed % 5) * 4
    local x0, y0 = x + (seed % 7 - 3) * 6, y
    love.graphics.setColor(1, 0.85 - (seed % 3) * 0.15, 0.3, 0.9)
    love.graphics.line(x0, y0, x0 + math.cos(a) * len, y0 + math.sin(a) * len)
  end
  love.graphics.setColor(1, 1, 0.8, 0.5 + 0.5 * math.abs(math.sin(t * 23)))
  love.graphics.circle("fill", x, y, 4)
  love.graphics.setLineWidth(1)
end

--- A spanner, centred on (x, y).
local function spanner(x, y, angle)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", -8, -1, 16, 4, 1)
  love.graphics.setColor(0.8, 0.82, 0.86)
  love.graphics.rectangle("fill", -9, -2, 16, 4, 1)
  love.graphics.circle("fill", 8, 0, 4.5)
  love.graphics.circle("fill", -9, 0, 3.5)
  love.graphics.setColor(0.2, 0.2, 0.22)
  love.graphics.rectangle("fill", 8, -1.5, 5, 3)
  love.graphics.pop()
end

--- Over each pickup a spanner, sparks at a building being mended, and for
--- the employer what he is up to.
function Handsy:drawAboveCars(client)
  for id, u in pairs(self.units) do
    local x, y = client:pose(id)
    if x then
      local working = u.state == "repair"
      spanner(x + 40, y - 6, working and math.sin(love.timer.getTime() * 10) * 0.6 or -0.5)
      if working and u.plot then
        local fx, fy = frontOf(u.plot)
        if fx then
          sparks(fx, fy)
        end
      end
      if u.owner == client.myId then
        love.graphics.setFont(UI.fonts.small)
        local text = Hire.states[u.state] or u.state
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.printf(text, x - 79, y + 43, 160, "center")
        love.graphics.setColor(0.6, 0.85, 1)
        love.graphics.printf(text, x - 80, y + 42, 160, "center")
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- My own Handsy Man on the minimap: a diamond in my colour with a dark rim.
function Handsy:drawOnMinimap(client, toMap)
  for id, u in pairs(self.units) do
    if u.owner == client.myId then
      local wx, wy = client:pose(id)
      if wx then
        local x, y = toMap(wx, wy)
        local c = Car.colorFor(client.myId)
        love.graphics.setColor(0.1, 0.1, 0.1)
        love.graphics.polygon("fill", x, y - 5, x + 5, y, x, y + 5, x - 5, y)
        love.graphics.setColor(c[1], c[2], c[3])
        love.graphics.polygon("fill", x, y - 3.5, x + 3.5, y, x, y + 3.5, x - 3.5, y)
      end
    end
  end
end

function Handsy:drawHUD()
  local n = self.notice
  if not n then
    return
  end
  local w = love.graphics.getWidth()
  love.graphics.setFont(UI.fonts.body)
  local alpha = math.min(1, n.t)
  love.graphics.setColor(0, 0, 0, 0.6 * alpha)
  love.graphics.printf(n.text, 2, 152, w, "center")
  love.graphics.setColor(0.6, 0.85, 1, alpha)
  love.graphics.printf(n.text, 0, 150, w, "center")
  love.graphics.setColor(1, 1, 1)
end

Handsy.clientMessages = {
  HSY_UNIT = function(_client, args)
    local id, owner = tonumber(args[1]), tonumber(args[2])
    if id and owner then
      Handsy.units[id] = { owner = owner, state = args[3] or "idle", plot = tonumber(args[4]) }
    end
  end,
  HSY_GONE = function(_client, args)
    local id = tonumber(args[1])
    if id then
      Handsy.units[id] = nil
    end
  end,
  HSY_NEWS = function(_client, args)
    if args[1] == "refund" then
      local m = Features.byName.money
      local n = tonumber(args[2]) or 0
      local paid = m and m.amount and m.amount(n) or tostring(n)
      say(("Your Handsy Man couldn't finish a job. %s back for the repairs he didn't do."):format(paid))
    elseif NEWS[args[1]] then
      say(NEWS[args[1]])
    end
  end,
  HSY_NO = function(_client, args)
    Handsy.refused = REFUSED[args[1]] or "You can't hire a Handsy Man right now."
  end,
}

-- Server ------------------------------------------------------------------

-- men: npc id -> { npc, owner (player id), look, job }
--   job: nil (idle) or { state = drive | repair | home, id (plot; nil going home), x, y (its square,
--        or the shop's door), lane (route.lua's target), age, left (hit points paid for and not yet
--        mended), mended, fee (Fcks paid for the job), carry (part of a hit point mended) }
local sv = nil

function Handsy:serverStart()
  sv = { men = {} }
end

local function unitMessage(m)
  local job = m.job
  if job and job.id then
    return Protocol.encode("HSY_UNIT", m.npc.id, m.owner, job.state, job.id)
  end
  return Protocol.encode("HSY_UNIT", m.npc.id, m.owner, job and job.state or "idle")
end

local function tell(server, m)
  server:broadcast(unitMessage(m))
end

local function news(server, owner, ...)
  local p = server.players[owner]
  if p then
    server:send(p, Protocol.encode("HSY_NEWS", ...))
  end
end

--- The Handsy Men `owner` has on the road.
local function menOf(owner)
  local out = {}
  for _, m in pairs(sv.men) do
    if m.owner == owner then
      out[#out + 1] = m
    end
  end
  table.sort(out, function(a, b)
    return a.npc.id < b.npc.id
  end)
  return out
end

--- What player `owner` can spend: their wallet (no limit without money).
local function wallet(owner)
  local mo = money()
  return mo and mo.wallet and mo:wallet(owner) or math.huge
end

--- Every building of `owner`'s that is short of hit points, ruins too:
--- { id, x, y, b, kind }, (x, y) the middle of its square.
local function damaged(owner)
  local b = buildings()
  local out = {}
  if not (b and b.ofKind and inCity()) then
    return out
  end
  for _, kind in ipairs(Kinds.list) do
    for _, at in ipairs(b:ofKind(kind.key, owner)) do
      if at.building.hp < kind.hp then
        out[#out + 1] = { id = at.id, x = at.x, y = at.y, b = at.building, kind = kind }
      end
    end
  end
  return out
end

--- What mending building `rec` of `kind` comes to with `purse` Fcks to
--- spend: the hit points it ends up with and the price, `Hire.markup`
--- times the repair menu's (and `Hire.ruinMarkup` times that again for a
--- ruin). All of it when the purse covers that, else as much as it does;
--- a ruin is rebuilt whole or not at all. Nil when nothing is affordable
--- (or there is nothing to do).
local function quote(rec, kind, purse)
  local full = Kinds.repairCost(kind, rec.hp)
  if full <= 0 or purse < 1 then
    return nil
  elseif rec.hp <= 0 then
    local cost = full * Hire.markup * Hire.ruinMarkup
    if cost <= purse then
      return kind.hp, cost
    end
    return nil
  elseif full * Hire.markup <= purse then
    return kind.hp, full * Hire.markup
  end
  -- The most hit points the purse covers: repairCost falls as hp rises.
  local menu = math.floor(purse / Hire.markup) -- what the purse covers at the menu's price
  local lo, hi = rec.hp, kind.hp
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if full - Kinds.repairCost(kind, mid) <= menu then
      lo = mid
    else
      hi = mid - 1
    end
  end
  local cost = (full - Kinds.repairCost(kind, lo)) * Hire.markup
  if lo <= rec.hp or cost < 1 then
    return nil
  end
  return lo, cost
end

local function dist2(m, x, y)
  local car = m.npc.car
  return (car.x - x) ^ 2 + (car.y - y) ^ 2
end

--- The nearest damaged building of the owner's that `purse` pays something towards.
local function bestJob(m, purse)
  local best, bestD
  for _, at in ipairs(damaged(m.owner)) do
    if quote(at.b, at.kind, purse) then
      local dd = dist2(m, at.x, at.y)
      if not bestD or dd < bestD then
        best, bestD = at, dd
      end
    end
  end
  return best
end

local function setJob(server, m, state, at)
  local before = m.job and m.job.state or "idle"
  local beforeId = m.job and m.job.id
  if state then
    m.job = { state = state, id = at.id, x = at.x, y = at.y, age = 0 }
  else
    m.job = nil
  end
  if (m.job and m.job.state or "idle") ~= before or (m.job and m.job.id) ~= beforeId then
    tell(server, m)
  end
end

--- Take a Handsy Man off the road for good.
local function dismiss(server, m)
  sv.men[m.npc.id] = nil
  server:broadcast(Protocol.encode("HSY_GONE", m.npc.id))
  local bots = Features.byName.bots
  if bots and bots.removeNpc then
    bots:removeNpc(server, m.npc)
  end
end

--- Pick what `m` does next: the nearest job the wallet covers, else go
--- home and say why. Away from the city there is nothing to do but wait.
local function plan(server, m)
  m.look = Handsy.lookEvery
  if not inCity() then
    setJob(server, m, nil)
    return
  end
  local job = bestJob(m, wallet(m.owner))
  if job then
    setJob(server, m, "drive", job)
    return
  end
  local shop = shopHere()
  if not shop then
    dismiss(server, m) -- nowhere to go back to
    return
  end
  if not (m.job and m.job.state == "home") then
    news(server, m.owner, next(damaged(m.owner)) and "broke" or "done")
    setJob(server, m, "home", { x = shop.doorX, y = shop.doorY })
  end
end

--- Pulled up at the job: charge for it and start mending, or think again
--- if the wallet no longer covers anything here.
local function startRepair(server, m, rec)
  local kind = Kinds.byKey[rec.kind]
  local target, cost = quote(rec, kind, wallet(m.owner))
  local mo = money()
  if not target or (mo and mo.spend and not mo:spend(server, m.owner, cost, "Handsy Man repairs")) then
    plan(server, m)
    return
  end
  local job = m.job
  job.state, job.left, job.mended, job.fee, job.carry = "repair", target - rec.hp, 0, cost, 0
  tell(server, m)
end

--- The job in hand was cut short: what was paid for and not mended goes back.
local function refund(server, m)
  local job = m.job
  if not (job and job.state == "repair" and job.left > 0 and job.fee > 0) then
    return
  end
  local back = math.floor(job.fee * job.left / (job.left + job.mended))
  local mo = money()
  if back > 0 and mo and mo.give then
    mo:give(server, m.owner, back)
    news(server, m.owner, "refund", back)
  end
  job.left = 0
end

--- Mend the rest of what was paid for in one go (the employer is leaving,
--- or the city is being left behind).
local function finish(server, m)
  local job = m.job
  local b = buildings()
  if job and job.state == "repair" and job.left > 0 and b and b.serverRepair then
    local rec = b:serverBuilding(job.id)
    if rec and rec.owner == m.owner and (rec.hp > 0 or job.mended == 0) then
      b:serverRepair(server, job.id, job.left)
      job.left = 0
    else
      refund(server, m)
    end
  end
end

--- Is the pickup stopped by where it is going?
local function arrived(m)
  return dist2(m, m.job.x, m.job.y) <= Handsy.arrive ^ 2 and math.abs(m.npc.car.speed) < 20
end

local function mend(server, m, dt)
  local job = m.job
  local b = buildings()
  local rec = b and b:serverBuilding(job.id)
  -- Gone, sold, knocked down again after he had started on it, or mended
  -- from the menu meanwhile: what he didn't get to is given back, and a
  -- ruin is quoted afresh.
  local kind = rec and Kinds.byKey[rec.kind]
  if not kind or rec.owner ~= m.owner or (rec.hp <= 0 and job.mended > 0) or rec.hp >= kind.hp then
    refund(server, m)
    plan(server, m)
    return
  end
  job.carry = job.carry + Hire.rate * dt
  local n = math.min(job.left, math.floor(job.carry))
  if n >= 1 then
    job.carry = job.carry - n
    b:serverRepair(server, job.id, n)
    job.left, job.mended = job.left - n, job.mended + n
  end
  if job.left <= 0 then
    plan(server, m)
  end
end

local function step(server, m, dt)
  local car = m.npc.car
  if not car or car.hidden then
    return -- wrecked (going), or parked out of sight on a map without traffic
  end
  local job = m.job
  if not job then
    m.look = (m.look or 0) - dt
    if m.look <= 0 then
      plan(server, m)
    end
    return
  end
  if job.state == "repair" then
    mend(server, m, dt)
    return
  end
  job.age = job.age + dt
  if job.state == "drive" then
    local b = buildings()
    local rec = b and b:serverBuilding(job.id)
    if not rec or rec.owner ~= m.owner or rec.hp >= Kinds.byKey[rec.kind].hp then
      plan(server, m) -- mended, sold or gone on the way
    elseif arrived(m) then
      startRepair(server, m, rec)
    elseif job.age > Handsy.giveUp then
      m.npc.ai.route = nil -- find the street again
      plan(server, m)
    end
    return
  end
  -- Home: gone at the door (or after long enough on the way); new damage turns him round.
  if not shopHere() then
    plan(server, m)
  elseif arrived(m) or job.age > Handsy.giveUp then
    dismiss(server, m)
  else
    m.look = (m.look or 0) - dt
    if m.look <= 0 then
      m.look = Handsy.lookEvery
      if bestJob(m, wallet(m.owner)) then
        plan(server, m)
      end
    end
  end
end

-- The brain bots runs every tick for a Handsy Man: steer to the job, hold
-- still while mending, cruise about with nothing to do.
local Brain = {}

function Brain.think(server, npc, dt)
  local bots = Features.byName.bots
  local m = sv and sv.men[npc.id]
  local job = m and m.job
  local car, input = npc.car, npc.input
  if not job then
    bots:cruise(server, npc, Handsy.idleSpeed)
    return
  end
  if job.state == "repair" then
    input.steer = 0
    input.throttle = Traffic.throttleFor(car, 0)
    return
  end
  local g = graph()
  if not g then
    -- Open ground: straight at the square, slowing to stop on it.
    local dist = bots.driveTowards(npc, job.x, job.y, 1)
    input.throttle = Traffic.throttleFor(car, math.min(Handsy.speed, math.max(0, dist - 60) * 1.2))
    bots.unstick(npc, dt)
    return
  end
  if not job.lane or job.graph ~= g then
    job.lane, job.graph = Route.target(g, job.x, job.y), g
  end
  local speed = Handsy.speed
  local route = npc.ai.route
  if route and job.lane then
    local along = Route.on(route, job.lane) and Route.along(route, car)
    if along and along <= job.lane.stop + 40 then
      -- On the street the square is on: brake to stop beside it.
      local room = math.max(0, job.lane.stop - along)
      speed = math.min(speed, room * 1.6, math.sqrt(2 * (car.brake or 700) * 0.5 * room))
    elseif route.plannedFrom ~= job.lane then
      route.next = Route.nextExit(route, job.lane) or route.next
      route.plannedFrom = job.lane
    end
  end
  bots:cruise(server, npc, speed)
end

--- Put a Handsy Man for `owner` on the road at (x, y).
local function hire(server, owner, x, y, angle)
  local bots = Features.byName.bots
  if not (bots and bots.spawnNpc) then
    return nil
  end
  local npc = bots:spawnNpc(server, {
    name = "Handsy Man", x = x, y = y, angle = angle, brain = Brain, civilian = true,
  })
  local vehicles, model = Features.byName.vehicles, Hire.truck()
  if vehicles and vehicles.serverSetModel and model then
    vehicles:serverSetModel(server, npc.car, model)
  end
  local m = { npc = npc, owner = owner.id, look = 0 }
  sv.men[npc.id] = m
  tell(server, m)
  return m
end

--- The shop sold a Handsy Man: he turns up at (x, y), outside its door,
--- when there is work for him and the buyer can pay for some of it.
function Handsy:serverDeliver(server, player, item, x, y, angle)
  if item ~= Hire.ITEM or not sv or player.bot then
    return false
  end
  local reason
  if #menOf(player.id) >= Hire.maxPerPlayer then
    reason = "max"
  elseif not next(damaged(player.id)) then
    reason = "nowork"
  else
    local shop = Features.byName.shop
    local dev = shop and shop.serverDev and shop:serverDev(player)
    local afterFee = wallet(player.id) - (dev and 0 or Hire.price)
    local any = false
    for _, at in ipairs(damaged(player.id)) do
      if quote(at.b, at.kind, afterFee) then
        any = true
        break
      end
    end
    reason = not any and "broke" or nil
  end
  if reason then
    server:send(player, Protocol.encode("HSY_NO", reason))
    return false
  end
  return hire(server, player, x, y, angle or 0) ~= nil
end

--- A wrecked pickup: he is gone, next step.
function Handsy:serverKill(_server, kill)
  local m = sv and kill.kind == "car" and kill.victim and sv.men[kill.victim]
  if m then
    m.wrecked = true
  end
end

function Handsy:serverStep(server, dt)
  if not sv then
    return
  end
  for _, m in pairs(sv.men) do
    if m.wrecked then
      refund(server, m)
      news(server, m.owner, "lost")
      dismiss(server, m)
    end
  end
  for _, m in pairs(sv.men) do
    step(server, m, dt)
  end
end

--- Leaving the city (a quest) or coming back: the job in hand is finished
--- at once and each starts over from wherever bots put them.
function Handsy:mapChanged(_map, server)
  if not (server and sv) then
    return
  end
  for _, m in pairs(sv.men) do
    finish(server, m)
    m.job, m.look = nil, Handsy.lookEvery
    tell(server, m)
  end
end

--- Someone arriving mid-game hears every Handsy Man.
function Handsy:serverPlayerJoined(server, player)
  if not (sv and server.started) or player.bot then
    return
  end
  for _, m in pairs(sv.men) do
    server:send(player, unitMessage(m))
  end
end

--- An employer who leaves takes their Handsy Men home, the job in hand
--- done (their player file keeps them).
function Handsy:serverPlayerLeft(server, player)
  if not sv or player.bot then
    return
  end
  for _, m in ipairs(menOf(player.id)) do
    finish(server, m)
    dismiss(server, m)
  end
end

-- Saved games -------------------------------------------------------------

local SAVE_VERSION = 1

--- How many Handsy Men a player has at work.
function Handsy:serverSavePlayer(_server, player)
  if not sv or player.bot then
    return nil
  end
  return { version = SAVE_VERSION, men = #menOf(player.id) }
end

--- Their Handsy Men are back on the road, somewhere in the city's traffic,
--- and look for work (or go home) from there.
function Handsy:serverLoadPlayer(server, player, data)
  if not sv or type(data) ~= "table" or (tonumber(data.version) or 0) > SAVE_VERSION then
    return
  end
  local n = math.min(math.floor(tonumber(data.men) or 0), Hire.maxPerPlayer)
  for _ = 1, n - #menOf(player.id) do
    local g = graph()
    local x, y, angle
    if g then
      x, y, angle = Traffic.randomLanePoint(g, server.vehicles, 150)
    end
    if not x then
      x, y, angle = Features.bodyPose(server, player)
      y = (y or 0) + 120
    end
    hire(server, player, x or 0, y, angle or 0)
  end
end

return Handsy
