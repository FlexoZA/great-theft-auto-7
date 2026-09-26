-- Garage: somewhere to keep your cars, and what happens to them (and to
-- you) when things go wrong.
--
-- A garage is a building (buildings' kind "garage", runs by this feature
-- through `service`): build it on a plot you own. Each holds `capacity`
-- cars. Drive onto its square, press the action key and park the car you
-- are driving there; it is out of the world, safe from thieves and guns,
-- and stays there when you leave or the host shuts down (the world save
-- keeps it). Take it out again from the vehicles screen while you stand on
-- the square.
--
-- The vehicles screen (G) lists every car you own: where it is, its health,
-- and what you can do with it.
--   On the road    tow it into your garage (towPrice), if nobody is in it
--   In a garage    repair it (up to repairPrice, less for less damage) or
--                  take it out (on the garage's square)
--   Destroyed      tow the wreck into your garage (towPrice), then repair it
--   Impounded      collect it at the impound lot (impoundPrice)
--
-- When a car of yours is wrecked in the city it doesn't come back by itself
-- any more: with a garage it is "destroyed" and waits for you to tow it
-- home; without one it is towed to the impound lot, whole, and waits for
-- you to pay to collect it. When you die you come back on foot at your
-- garage (the first one still standing) or, with none, at the hospital, and
-- your car stays wherever you left it. The hospital and the impound lot are
-- two of the city's own buildings (places.lua). Off the city (a quest map)
-- none of this applies and weapons' old respawn works as it always did; so
-- it does for bots, and for cars nobody owns.
--
-- A garage that comes down keeps its cars (nothing goes in or out until it
-- is rebuilt); one whose plot changes hands is gone, and whatever no longer
-- fits in the owner's other garages goes to the impound lot.
--
-- Kept cars are ordinary cars in `server.vehicles` with `car.hidden` and
-- `car.kept` set: the core leaves them out of STATE, weapons doesn't move
-- them and city-map doesn't seat anyone in them.
--
-- Messages
--   client -> server  GAR_PARK    <plotId>        (the car I drive, into my garage there)
--   client -> server  GAR_TAKE    <vid>           (out of my garage, onto the road by the square I'm on)
--   client -> server  GAR_TOW     <vid>           (a wreck, or my car on the road, into my garage)
--   client -> server  GAR_REPAIR  <vid>           (a car in my garage)
--   client -> server  GAR_COLLECT <vid>           (from the impound lot, standing at its gate)
--   server -> owner   GAR_KEPT    <vid> <state> <hp> <max>   (stored | wrecked | destroyed | impound)
--   server -> owner   GAR_FREE    <vid>           (back on the road)
--   server -> player  GAR_OK      <what>          (parked | taken | towed | repaired | collected)
--   server -> player  GAR_NO      <reason>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Car = require("src.car")
local Layout = require("src.features.city-map.layout")
local Catalog = require("src.features.vehicles.catalog")
local Places = require("src.features.garage.places")
local Screen = require("src.features.garage.screen")

local Garage = {
  name = "garage",
  priority = 975, -- the screen goes over the shop (970), under the inventory (995); loads after vehicles (100)
}

-- Tuning ------------------------------------------------------------------
Garage.capacity = 6 -- cars one garage holds
Garage.repairPrice = 20 -- Fcks to mend a wreck; less damage, less
Garage.towPrice = 10 -- Fcks to tow a car into your garage
Garage.impoundPrice = 15 -- Fcks to get a car back from the impound lot
Garage.gateRadius = 34 -- px from the impound lot's pay square that counts as standing on it

local T = Layout.TILE
local SLACK = 40 -- px the host allows for a player drawn a little behind where it is
local NOTICE_TIME = 2.5
local SETTLE_TIME = 1 -- seconds between the host's checks that every kept car still has a home
local SAVE_VERSION = 1
local STATES = { stored = true, wrecked = true, destroyed = true, impound = true }
local GREEN, RED = { 0.5, 1, 0.6 }, { 1, 0.45, 0.4 }
local REASONS = {
  away = "Stand on your garage's square.",
  gate = "Go to the impound lot's gate.",
  nogarage = "You don't have a garage. Build one on a plot you own.",
  full = "Your garages are full.",
  notyours = "That isn't your car.",
  notdriving = "Drive the car you want to park onto the square.",
  driven = "Someone is driving it.",
  notkept = "It isn't in your garage.",
  wrecked = "Repair it first.",
  intact = "It isn't damaged.",
  broke = "You can't afford it.",
  city = "Not here: garages are in the city.",
  unknown = "That can't be done.",
}
local DONE = {
  parked = "Parked. It's safe in your garage.",
  taken = "It's on the road.",
  towed = "Towed into your garage.",
  repaired = "Good as new.",
  collected = "Collected. Drive safe.",
}

local function cityMap()
  return Features.byName["city-map"]
end

local function buildings()
  return Features.byName.buildings
end

local function amount(n)
  local money = Features.byName.money
  return money and money.amount(n) or tostring(n)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The hospital and impound lot (places.lua) while the city is in play.
function Garage:places()
  local city = cityMap()
  if not (city and city.map and city.current == city.DEFAULT) then
    return nil
  end
  return Places.of(city.map)
end

--- Player `id`'s garages: { id = plot id, building, plot, x, y, ruined }.
local function garagesOf(id)
  local b = buildings()
  return b and b.ofKind and b:ofKind("garage", id) or {}
end

--- The first of `list` still standing, or nil.
local function standing(list)
  for _, g in ipairs(list) do
    if not g.ruined then
      return g
    end
  end
  return nil
end

--- Fcks to bring a car at `hp` of `max` back to full.
function Garage.repairCost(hp, max)
  local missing = math.max(0, max - hp)
  if missing <= 0 then
    return 0
  end
  return math.max(1, math.ceil(Garage.repairPrice * missing / max))
end

-- Client --------------------------------------------------------------------

Garage.open = false
Garage.page = 1
Garage.kept = {} -- vehicle id -> { state, hp, max }, my cars off the road (the host says: GAR_KEPT)
Garage.notice = nil -- { text, color, t }
Garage.atGarage = nil -- my standing garage whose square I'm on
Garage.atGate = false -- am I on the impound lot's pay square?
local time = 0

function Garage:load()
  Controls.register("vehicles", "Open / close your vehicles", "g")
  Controls.register("impound", "Collect a car (at the impound lot)", "f") -- the action key, like the shop's
end

function Garage:enterGame()
  self.open, self.page, self.notice, self.atGarage, self.atGate = false, 1, nil, nil, false
end

-- GAR_KEPT for cars kept before we joined arrives in the same burst as
-- START, so they are only forgotten on the way out.
function Garage:exitGame()
  self:enterGame()
  self.kept = {}
end

--- The `pointerTaken` convention: the mouse is ours while the screen is up.
function Garage:pointerTaken()
  return self.open
end

--- The `closeMenu` convention: Esc takes the screen down.
function Garage:closeMenu()
  if not self.open then
    return false
  end
  self:show(false)
  return true
end

--- The `actionTaken` convention: the action key is ours at the impound lot's gate.
function Garage:actionTaken()
  return self.atGate
end

function Garage:worldBlur()
  return self.open and 0.5 or 0
end

function Garage:say(text, color)
  self.notice = { text = text, color = color or RED, t = NOTICE_TIME }
end

--- Another panel that has the mouse (the inventory draws over ours).
local function covered()
  local inventory, shop = Features.byName.inventory, Features.byName.shop
  return (inventory and inventory.open) or (shop and shop.open) or false
end

function Garage:update(dt, client)
  time = time + dt
  if self.notice then
    self.notice.t = self.notice.t - dt
    if self.notice.t <= 0 then
      self.notice = nil
    end
  end
  self.atGarage, self.atGate = nil, false
  local x, y = client:myPose()
  local places = self:places()
  if not (x and places) then
    return
  end
  local im = places.impound
  self.atGate = im ~= nil and dist2(x, y, im.padX, im.padY) <= self.gateRadius ^ 2
  local b = buildings()
  for _, g in ipairs(garagesOf(client.myId)) do
    if not g.ruined and b.onPad(g.plot, x, y) then
      self.atGarage = g
      break
    end
  end
end

--- Open or close the screen.
function Garage:show(on)
  self.open = on
  if on then
    self.page = 1
    local b = buildings()
    if b then
      b.menu = false
    end
  end
end

function Garage:keypressed(key)
  if Controls.is("vehicles", key) then
    if self.open or not covered() then
      self:show(not self.open)
    end
  elseif Controls.is("impound", key) and self.atGate and not covered() then
    self:show(not self.open)
  end
end

--- Car `vid`'s model (a catalog entry), or nil for the car everyone starts with.
local function carModel(vid)
  local vehicles = Features.byName.vehicles
  return vehicles and Catalog.byKey[vehicles.models[vid] or ""]
end

--- How many of my cars are in my garages, and how many fit.
function Garage:spaces(client)
  local used = 0
  for vid, k in pairs(self.kept) do
    if (k.state == "stored" or k.state == "wrecked") and client.garage[vid] then
      used = used + 1
    end
  end
  return used, #garagesOf(client.myId) * self.capacity
end

--- Every car I own, in id order, as the screen shows it: { vid, name, model,
--- color, state, status, hp, max, actions = { { label, enabled, why, run } } }.
function Garage:entries(client)
  local used, room = self:spaces(client)
  local hasGarage = room > 0
  local weapons = Features.byName.weapons
  local money = Features.byName.money
  local mine = client:myVehicle()
  local out = {}
  for vid, info in pairs(client.garage) do
    if info.owner == client.myId then
      local k = self.kept[vid]
      local model = carModel(vid)
      local e = {
        vid = vid,
        name = model and model.name or "Starter car",
        model = model,
        color = Car.paletteColor(info.color),
        actions = {},
      }
      if k then
        e.state, e.hp, e.max = k.state, k.hp, k.max
      else
        e.state = "road"
        e.max = weapons and weapons.carMax[vid] or 100
        e.hp = weapons and weapons.carHealth[vid] or e.max
      end
      out[#out + 1] = e
    end
  end
  table.sort(out, function(a, b)
    return a.vid < b.vid
  end)

  local function action(e, label, price, why, run)
    local broke = price > 0 and money and money.canAfford and not money:canAfford(client, price)
    if price > 0 then
      label = ("%s (%s)"):format(label, amount(price))
    end
    if broke and not why then
      why = REASONS.broke
    end
    e.actions[#e.actions + 1] = { label = label, enabled = why == nil, why = why, run = run }
  end
  local function send(kind, vid)
    return function()
      client:send(Protocol.encode(kind, vid))
    end
  end
  local roomWhy = not hasGarage and REASONS.nogarage or (used >= room and REASONS.full) or nil

  for _, e in ipairs(out) do
    local vid = e.vid
    if e.state == "road" then
      local v = client.vehicles[vid]
      local driver = v and v.driver
      if driver == client.myId then
        e.status = "On the road: you're driving it"
      elseif driver then
        e.status = ("On the road: %s is driving it"):format(client:nameOf(driver) or "someone")
      else
        e.status = v and "Parked on the road" or "On its way back"
      end
      if self.atGarage and mine and mine.id == vid then
        action(e, "Park here", 0, roomWhy, function()
          client:send(Protocol.encode("GAR_PARK", self.atGarage.id))
        end)
      else
        action(e, "Tow home", self.towPrice, roomWhy or (driver and REASONS.driven) or (not v and REASONS.unknown)
          or nil, send("GAR_TOW", vid))
      end
    elseif e.state == "stored" or e.state == "wrecked" then
      e.status = e.state == "wrecked" and "In your garage, wrecked" or "In your garage"
      local cost = self.repairCost(e.state == "wrecked" and 0 or e.hp, e.max)
      if cost > 0 then
        action(e, "Repair", cost, nil, send("GAR_REPAIR", vid))
      end
      action(e, "Take out", 0, (e.state == "wrecked" and REASONS.wrecked) or (not self.atGarage and REASONS.away)
        or nil, send("GAR_TAKE", vid))
    elseif e.state == "destroyed" then
      e.status = "Destroyed: tow the wreck home"
      e.hp = 0
      action(e, "Tow home", self.towPrice, roomWhy, send("GAR_TOW", vid))
    elseif e.state == "impound" then
      e.status = "At the impound lot"
      action(e, "Collect", self.impoundPrice, not self.atGate and REASONS.gate or nil, send("GAR_COLLECT", vid))
    end
    if e.state == "wrecked" then
      e.hp = 0
    end
  end
  return out
end

--- The line under the title: my garages and how full they are.
function Garage:info(client)
  local used, room = self:spaces(client)
  if room == 0 then
    return "No garage: a wrecked car goes to the impound lot and you wake up in hospital. Build one on a plot."
  end
  local garages = room / self.capacity
  return ("%d garage%s, %d of %d spaces used. Wrecks wait for a tow; you come back at your garage."):format(
    garages, garages == 1 and "" or "s", used, room)
end

function Garage:mousepressed(x, y, button, client)
  if not self.open or button ~= 1 or covered() then
    return
  end
  local L = Screen.layout(self:entries(client), self.page)
  if L.prev and Screen.inside(L.prev, x, y) then
    self.page = (L.page - 2) % L.pages + 1
    return
  elseif L.next and Screen.inside(L.next, x, y) then
    self.page = L.page % L.pages + 1
    return
  end
  for _, r in ipairs(L.rows) do
    for _, b in ipairs(r.buttons) do
      if Screen.inside(b, x, y) then
        if b.action.enabled then
          b.action.run()
        else
          self:say(b.action.why or REASONS.unknown)
        end
        return
      end
    end
  end
end

-- Buildings asks for these on a garage's square (kinds.lua, `service`).

--- The menu rows on my garage's square: park what I'm driving, open the screen.
function Garage:buildingRows(client, plot, _b, row)
  local used, room = self:spaces(client)
  local car = client:myVehicle()
  local info = car and client.garage[car.id]
  local label = ("Park this car  (%d/%d)"):format(used, room)
  if not (car and info and info.owner == client.myId) then
    row(label .. ": drive your car in")
  elseif used >= room then
    row(label .. ": full")
  else
    row(label, function()
      client:send(Protocol.encode("GAR_PARK", plot.id))
    end)
  end
  row(("Your vehicles  (%s)"):format(Controls.name(Controls.bindings("vehicles")[1])), function()
    self:show(true)
  end)
end

--- The lines at the top of that menu.
function Garage:buildingInfo(client)
  local used, room = self:spaces(client)
  return {
    ("Holds %d cars. Yours: %d of %d spaces used."):format(self.capacity, used, room),
    "Parked cars are safe here, even while you're away.",
  }
end

--- A garage: a flat roof over a row of roll-up doors facing the street.
function Garage:drawBuilding(_b, _kind, r)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", r.x + 6, r.y + 6, r.w, r.h)
  love.graphics.setColor(0.42, 0.44, 0.47)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
  love.graphics.setColor(0.52, 0.54, 0.57)
  love.graphics.rectangle("fill", r.x + 8, r.y + 8, r.w - 16, r.h - 70)
  love.graphics.setColor(0.36, 0.38, 0.4)
  for i = 1, 3 do
    local ly = r.y + 8 + (r.h - 70) * i / 4
    love.graphics.line(r.x + 14, ly, r.x + r.w - 14, ly)
  end
  -- The doors along the bottom edge.
  local n = self.capacity
  local dw = (r.w - 16 - (n - 1) * 6) / n
  for i = 0, n - 1 do
    local dx = r.x + 8 + i * (dw + 6)
    love.graphics.setColor(0.72, 0.62, 0.3)
    love.graphics.rectangle("fill", dx, r.y + r.h - 54, dw, 46)
    love.graphics.setColor(0.55, 0.47, 0.22)
    for j = 1, 4 do
      love.graphics.line(dx + 2, r.y + r.h - 54 + j * 9, dx + dw - 2, r.y + r.h - 54 + j * 9)
    end
  end
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.printf("GARAGE", r.x + 1, r.y + (r.h - 70) / 2 - 2, r.w, "center")
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.printf("GARAGE", r.x, r.y + (r.h - 70) / 2 - 3, r.w, "center")
  love.graphics.setColor(1, 1, 1)
end

function Garage:drawBelowCars()
  local places = self:places()
  if not places then
    return
  end
  if places.hospital then
    Places.drawHospital(places.hospital, time)
  end
  if places.impound then
    Places.drawImpound(places.impound, self.atGate, time)
  end
end

--- How many of my cars wait at the impound lot.
function Garage:impounded(client)
  local n = 0
  for vid, k in pairs(self.kept) do
    if k.state == "impound" and client.garage[vid] then
      n = n + 1
    end
  end
  return n
end

local function prompt(text, color)
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, 1, h - 159, w, "center")
  love.graphics.setColor(color)
  love.graphics.printf(text, 0, h - 160, w, "center")
  love.graphics.setColor(1, 1, 1)
end

function Garage:drawHUD(client)
  if not self.open then
    if self.notice then
      prompt(self.notice.text, self.notice.color)
    elseif self.atGate then
      local key = Controls.name(Controls.bindings("impound")[1])
      local n = self:impounded(client)
      prompt(("Impound lot: %d of your cars here.  %s: open"):format(n, key), { 0.95, 0.75, 0.15 })
    end
    return
  end
  local mx, my = love.mouse.getPosition()
  local entries = self:entries(client)
  Screen.draw(entries, self.page, self:info(client), self.notice, mx, my)
  local vision = Features.byName.vision
  if vision then
    vision:drawCursor(client)
  end
  love.graphics.setColor(1, 1, 1)
end

Garage.clientMessages = {
  GAR_KEPT = function(_client, args)
    local vid, state = tonumber(args[1]), args[2]
    if vid and STATES[state] then
      Garage.kept[vid] = { state = state, hp = tonumber(args[3]) or 0, max = tonumber(args[4]) or 100 }
    end
  end,
  GAR_FREE = function(_client, args)
    local vid = tonumber(args[1])
    if vid then
      Garage.kept[vid] = nil
    end
  end,
  GAR_OK = function(_client, args)
    Garage:say(DONE[args[1]] or "Done.", GREEN)
  end,
  GAR_NO = function(_client, args)
    Garage:say(REASONS[args[1]] or REASONS.unknown)
  end,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { cars = { vehicle id -> state }, settle = seconds to the next check }

function Garage:serverStart()
  sv = { cars = {}, settle = SETTLE_TIME }
end

--- A car's hit points and ceiling, as weapons keeps them.
local function health(car)
  local weapons = Features.byName.weapons
  local hp, max
  if weapons and weapons.serverCarHealth then
    hp, max = weapons:serverCarHealth(car)
  end
  return hp or 100, max or 100
end

local function setHealth(server, car, hp)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverSetCarHealth then
    weapons:serverSetCarHealth(server, car, hp)
  end
end

--- Tell `car`'s owner, if they are here, how it is kept (or that it is free).
local function tell(server, car)
  local owner = car.owner and server.players[car.owner]
  if not owner or owner.bot then
    return
  end
  local state = sv.cars[car.id]
  if state then
    local hp, max = health(car)
    if state == "wrecked" or state == "destroyed" then
      hp = 0
    end
    server:send(owner, Protocol.encode("GAR_KEPT", car.id, state, hp, max))
  else
    server:send(owner, Protocol.encode("GAR_FREE", car.id))
  end
end

--- Take `car` out of the world into `state`, waiting at (x, y) if given.
--- Whoever sat in it is left standing there.
local function keep(server, car, state, x, y)
  local driver = car.driver and server.players[car.driver]
  if driver then
    server:unseat(driver, x, y)
  end
  if x then
    car.x, car.y = x, y
  end
  car.kept, car.hidden = true, true
  car:stop()
  sv.cars[car.id] = state
  tell(server, car)
end

--- Put a kept car back on the road at (x, y), facing `angle`, and seat
--- `player` in it if they are on foot.
local function release(server, car, x, y, angle, player)
  sv.cars[car.id] = nil
  car.kept, car.hidden = nil, false
  car.x, car.y, car.angle = x, y, angle
  car:stop()
  tell(server, car)
  if player and not player.vehicle then
    server:seat(player, car)
  end
end

--- Is player id `id` a person (here and not a bot, or remembered by the
--- world)? Their cars are the only ones a garage or the impound lot takes.
local function human(server, id)
  local p = id and server.players[id]
  if p then
    return not p.bot
  end
  return id ~= nil and server.names ~= nil and server.names[id] ~= nil
end

--- How many of `id`'s cars are in their garages.
local function housed(server, id)
  local n = 0
  for vid, state in pairs(sv.cars) do
    local car = server.vehicles[vid]
    if car and car.owner == id and (state == "stored" or state == "wrecked") then
      n = n + 1
    end
  end
  return n
end

local function hasRoom(server, id)
  return housed(server, id) < #garagesOf(id) * Garage.capacity
end

--- Send `car` to the impound lot, whole: where a car with no garage to go
--- to ends up.
local function impound(server, car, places)
  local im = places.impound
  if not im then
    return false
  end
  local _, max = health(car)
  setHealth(server, car, max)
  keep(server, car, "impound", im.padX, im.padY)
  return true
end

--- A place for `player` to stand: their garage's square, or the hospital's
--- door. Nil off the city.
function Garage:serverHome(player)
  local places = self:places()
  if not places then
    return nil
  end
  local g = standing(garagesOf(player.id))
  if g then
    return { x = g.x, y = g.y, angle = math.pi / 2 }
  end
  local h = places.hospital
  return h and { x = h.doorX, y = h.doorY, angle = math.pi / 2 } or nil
end

--- Weapons asks where a dead player comes back (the `serverRespawnPoint`
--- convention): at their garage, or at the hospital.
function Garage:serverRespawnPoint(spot, _server, player)
  if spot or not sv or player.bot then
    return spot
  end
  return self:serverHome(player)
end

--- Weapons asks whether we take a wreck (`serverWreckClaimed`): a person's
--- car in the city is ours. With a garage it waits there destroyed for a
--- tow; without one it goes to the impound lot, whole.
function Garage:serverWreckClaimed(server, car)
  local places = self:places()
  if not (sv and places and human(server, car.owner)) then
    return false
  end
  if #garagesOf(car.owner) > 0 then
    keep(server, car, "destroyed")
    return true
  end
  return impound(server, car, places)
end

--- A player sitting in a car we keep (their own, as the core seats them on
--- arrival) gets out at their garage or the hospital.
local function turnOut(self, server, player)
  local car = player.vehicle
  if car and car.kept then
    local home = self:serverHome(player)
    server:unseat(player, home and home.x, home and home.y)
  end
end

function Garage:serverPlayerJoined(server, player)
  if not sv or player.bot then
    return
  end
  turnOut(self, server, player)
  for vid in pairs(sv.cars) do
    local car = server.vehicles[vid]
    if car and car.owner == player.id then
      tell(server, car)
    end
  end
end

--- Every car we keep still exists, stays out of the world, and has a home:
--- a car in a garage that is gone, or that no longer fits, and a wreck with
--- no garage left to be towed to, go to the impound lot.
local function settle(self, server)
  for vid in pairs(sv.cars) do
    local car = server.vehicles[vid]
    if car then
      car.kept, car.hidden = true, true
    else
      sv.cars[vid] = nil
    end
  end
  local places = self:places()
  if not places then
    return -- a quest trip: the city's garages are put aside, not gone
  end
  local byOwner = {}
  for vid, state in pairs(sv.cars) do
    if state ~= "impound" then
      local owner = server.vehicles[vid].owner
      byOwner[owner] = byOwner[owner] or {}
      table.insert(byOwner[owner], vid)
    end
  end
  for owner, vids in pairs(byOwner) do
    local garages = #garagesOf(owner)
    local room, n = garages * self.capacity, 0
    table.sort(vids)
    for _, vid in ipairs(vids) do
      local car = server.vehicles[vid]
      if sv.cars[vid] == "destroyed" then
        if garages == 0 then
          impound(server, car, places)
        end
      else
        n = n + 1
        if n > room then
          impound(server, car, places)
        end
      end
    end
  end
end

function Garage:serverStep(server, dt)
  if not sv then
    return
  end
  sv.settle = sv.settle - dt
  if sv.settle <= 0 then
    sv.settle = SETTLE_TIME
    settle(self, server)
  end
end

--- Run `handler(server, player, args)`: nil when it went through (and the
--- word for GAR_OK), or false and the reason for GAR_NO.
local function answering(handler)
  return function(server, player, args)
    if not sv then
      return
    end
    local ok, word = handler(server, player, args)
    server:send(player, Protocol.encode(ok and "GAR_OK" or "GAR_NO", word or "unknown"))
  end
end

--- The car `args[1]` names, if it belongs to `player`.
local function ownCar(server, player, args)
  local car = server.vehicles[tonumber(args[1]) or -1]
  if not car then
    return nil, "unknown"
  elseif car.owner ~= player.id then
    return nil, "notyours"
  end
  return car
end

--- The standing garage of `player`'s whose square they are on, if any.
local function garageUnder(server, player)
  if not Features.present(player) then
    return nil
  end
  local x, y = Features.bodyPose(server, player)
  local b = buildings()
  for _, g in ipairs(garagesOf(player.id)) do
    if not g.ruined and b.onPad(g.plot, x, y, SLACK) then
      return g
    end
  end
  return nil
end

--- Take `price` from `player`, all or nothing.
local function pay(server, player, price, label)
  local money = Features.byName.money
  return not money or price <= 0 or money:spend(server, player.id, price, label)
end

--- The first bay of the impound lot with no car standing in it (the gate,
--- out on the road, when every one is taken): x, y, angle.
local function freeBay(server, im)
  for _, bay in ipairs(im.bays) do
    local taken = false
    for _, car in pairs(server.vehicles) do
      if not (car.hidden or car.stowed) and dist2(car.x, car.y, bay.x, bay.y) < 30 * 30 then
        taken = true
        break
      end
    end
    if not taken then
      return bay.x, bay.y, bay.angle
    end
  end
  return im.padX, im.padY + T, 0
end

Garage.serverMessages = {
  GAR_PARK = answering(function(server, player, args)
    if not Garage:places() then
      return false, "city"
    end
    local g = garageUnder(server, player)
    local car = player.vehicle
    if not (g and g.id == tonumber(args[1])) then
      return false, "away"
    elseif not car then
      return false, "notdriving"
    elseif car.owner ~= player.id then
      return false, "notyours"
    elseif not hasRoom(server, player.id) then
      return false, "full"
    end
    keep(server, car, "stored", g.x, g.y) -- they stand on the square
    return true, "parked"
  end),

  GAR_TAKE = answering(function(server, player, args)
    local car, reason = ownCar(server, player, args)
    if not car then
      return false, reason
    end
    local state = sv.cars[car.id]
    if state == "wrecked" then
      return false, "wrecked"
    elseif state ~= "stored" then
      return false, "notkept"
    end
    local g = garageUnder(server, player)
    if not g then
      return false, "away"
    end
    release(server, car, g.x, g.y + T, 0, player) -- onto the road in front of the square
    return true, "taken"
  end),

  GAR_TOW = answering(function(server, player, args)
    local car, reason = ownCar(server, player, args)
    local places = Garage:places()
    if not car then
      return false, reason
    elseif not places then
      return false, "city"
    end
    local state = sv.cars[car.id]
    if state and state ~= "destroyed" then
      return false, "unknown" -- already in a garage, or impounded
    elseif not state and (car.driver or car.hidden or car.stowed) then
      return false, car.driver and "driven" or "unknown"
    elseif #garagesOf(player.id) == 0 then
      return false, "nogarage"
    elseif not hasRoom(server, player.id) then
      return false, "full"
    elseif not pay(server, player, Garage.towPrice, "tow") then
      return false, "broke"
    end
    local g = garagesOf(player.id)[1]
    keep(server, car, state == "destroyed" and "wrecked" or "stored", g.x, g.y)
    return true, "towed"
  end),

  GAR_REPAIR = answering(function(server, player, args)
    local car, reason = ownCar(server, player, args)
    if not car then
      return false, reason
    end
    local state = sv.cars[car.id]
    if state ~= "stored" and state ~= "wrecked" then
      return false, "notkept"
    end
    local hp, max = health(car)
    local cost = Garage.repairCost(state == "wrecked" and 0 or hp, max)
    if cost <= 0 then
      return false, "intact"
    elseif not pay(server, player, cost, "repair") then
      return false, "broke"
    end
    setHealth(server, car, max)
    sv.cars[car.id] = "stored"
    tell(server, car)
    return true, "repaired"
  end),

  GAR_COLLECT = answering(function(server, player, args)
    local car, reason = ownCar(server, player, args)
    local places = Garage:places()
    if not car then
      return false, reason
    elseif sv.cars[car.id] ~= "impound" then
      return false, "notkept"
    elseif not (places and places.impound) then
      return false, "city"
    end
    local im = places.impound
    local x, y = Features.bodyPose(server, player)
    if not Features.present(player) or dist2(x, y, im.padX, im.padY) > (Garage.gateRadius + SLACK) ^ 2 then
      return false, "gate"
    elseif not pay(server, player, Garage.impoundPrice, "impound") then
      return false, "broke"
    end
    local bx, by, angle = freeBay(server, im)
    release(server, car, bx, by, angle, player)
    return true, "collected"
  end),
}

-- Saved worlds --------------------------------------------------------------

--- Every car we keep that the core saves (a remembered player's), with its
--- state and, in a garage, its health: { version, cars = { { id, state, hp } } }.
function Garage:serverSaveWorld(server)
  local list = {}
  for vid, state in pairs(sv and sv.cars or {}) do
    local car = server.vehicles[vid]
    if car and car.owner ~= nil and server.names[car.owner] ~= nil then
      local hp = health(car)
      list[#list + 1] = { id = vid, state = state, hp = state == "stored" and hp or nil }
    end
  end
  table.sort(list, function(a, b)
    return a.id < b.id
  end)
  return { version = SAVE_VERSION, cars = list }
end

--- The core has put the saved cars back (vehicles has made them their
--- models again): the ones we kept go back out of the world, and anyone the
--- core sat in one (its owner, in their own car) stands at their garage or
--- the hospital instead.
function Garage:serverLoadWorld(server, data)
  if not (sv and type(data) == "table" and type(data.cars) == "table") then
    return
  elseif (tonumber(data.version) or 1) > SAVE_VERSION then
    return
  end
  for _, rec in ipairs(data.cars) do
    local car = type(rec) == "table" and server.vehicles[tonumber(rec.id) or -1]
    if car and STATES[rec.state] and not sv.cars[car.id] and human(server, car.owner) then
      local driver = car.driver and server.players[car.driver]
      if type(rec.hp) == "number" and rec.hp == rec.hp then
        setHealth(server, car, rec.hp)
      end
      keep(server, car, rec.state)
      if driver then
        local home = self:serverHome(driver)
        if home then
          driver.body.x, driver.body.y, driver.body.facing = home.x, home.y, home.angle
        end
      end
    end
  end
end

return Garage
