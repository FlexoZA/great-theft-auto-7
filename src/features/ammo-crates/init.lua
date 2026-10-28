-- Ammo crates: military crates scattered over every quest map (not the
-- city), each an ammo dump for whoever breaks it open. Walk up to one and
-- press the action key (F, through `actionTaken`), or shoot it (any
-- player's round or blast: `serverShotAt`, `serverBlast`), and the lid
-- comes off and BOXES boxes of ammo spill out round it, each for a gun
-- picked by `weights`: the guns' own `dropWeight`s, as an enemy's drop,
-- but the AK's a little likelier. The boxes are ordinary pickups (pickups'
-- `serverDrop`), first come first served. An open crate stays where it is,
-- empty, until the map changes.
--
-- The host scatters COUNT of them when the map changes (`mapChanged`) on
-- open floor (city-map's `randomRoadPoint`), clear of walls, of everyone
-- and of each other, and tells everyone; a joiner hears them all.
--
-- Messages
--   client -> server  AMC_OPEN  <id>                 (I'm at it and pressed the action key)
--   server -> all     AMC_SPAWN <id> <x> <y> <open>   (a crate there; open 1 when it's been broken already)
--   server -> all     AMC_OPENED <id>                 (it was broken open: the sound, the splinters)
--   server -> all     AMC_CLEAR                       (the map changed: forget every crate)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Guns = require("src.features.weapons.guns")
local Sounds = require("src.features.ammo-crates.sounds")

local Crates = {
  name = "ammo-crates",
  priority = 69, -- under the pickups (70), so the boxes spill over the crate
}

-- Tuning ------------------------------------------------------------------
Crates.COUNT = 5 -- crates on a quest map
Crates.BOXES = 2 -- ammo boxes out of one: little enough that ammo stays worth looking for
Crates.MAGAZINES = 1.5 -- of its gun's magazines in each box (an enemy's holds 1)
Crates.SPILL = 70 -- px from the crate the boxes land
Crates.REACH = 56 -- px from a crate that lets the action key open it
Crates.RADIUS = 22 -- px: a round this near the middle hits it
Crates.CLEAR = 350 -- px a crate keeps from everyone when it is put down
Crates.APART = 500 -- px between crates
-- Which gun a box is for, by weight: each gun's `dropWeight` (pickups),
-- with these instead. The AK's 3 is 5 here: a dump is the army's.
Crates.weights = { ak47 = 5 }

local W, H = 44, 30 -- px: the crate, long side across
local OLIVE = { 0.33, 0.39, 0.22 }
local STENCIL = { 0.95, 0.82, 0.3 }

-- Client --------------------------------------------------------------------

Crates.crates = {} -- id -> { x, y, open, t (seconds since it broke, nil while shut) }
Crates.near = nil -- id of the shut crate I'm standing at, on foot
local time = 0

function Crates:load()
  Sounds.load()
  Controls.register("crate", "Open an ammo crate (standing at it)", "f") -- the action key, like the shop's
end

function Crates:enterGame()
  self.crates, self.near, time = {}, nil, 0
end

function Crates:exitGame()
  self.crates, self.near = {}, nil
end

--- The `actionTaken` convention: the action key is ours at a shut crate,
--- so on-foot doesn't take it to get into a car.
function Crates:actionTaken()
  return self.near ~= nil
end

function Crates:update(dt, client)
  time = time + dt
  for _, c in pairs(self.crates) do
    if c.t then
      c.t = c.t + dt
    end
  end
  self.near = nil
  local x, y, onFoot = client:pose(client.myId)
  if not (x and onFoot) then
    return
  end
  local best = self.REACH * self.REACH
  for id, c in pairs(self.crates) do
    local d2 = (c.x - x) ^ 2 + (c.y - y) ^ 2
    if not c.open and d2 <= best then
      self.near, best = id, d2
    end
  end
end

function Crates:keypressed(key, client)
  if self.near and Controls.is("crate", key) and not Features.any("pointerTaken", client) then
    client:send(Protocol.encode("AMC_OPEN", self.near))
  end
end

--- A crate: olive boards with a darker frame, rope handles at the ends, and
--- AMMO stencilled on the lid. Broken open, the lid lies askew beside it,
--- the inside dark and empty, and splinters fly for a moment.
local function drawCrate(c)
  local x, y = c.x, c.y
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x - W / 2 + 3, y - H / 2 + 4, W, H, 2) -- shadow
  love.graphics.setColor(OLIVE[1] * 0.7, OLIVE[2] * 0.7, OLIVE[3] * 0.7)
  love.graphics.rectangle("fill", x - W / 2, y - H / 2, W, H, 2) -- the frame
  love.graphics.setColor(0.2, 0.2, 0.2)
  love.graphics.rectangle("fill", x - W / 2 - 3, y - 4, 3, 8, 1) -- rope handles
  love.graphics.rectangle("fill", x + W / 2, y - 4, 3, 8, 1)
  if c.open then
    love.graphics.setColor(0.1, 0.09, 0.06)
    love.graphics.rectangle("fill", x - W / 2 + 3, y - H / 2 + 3, W - 6, H - 6, 1) -- empty
    love.graphics.push()
    love.graphics.translate(x + 10, y + 14)
    love.graphics.rotate(0.35)
    love.graphics.setColor(OLIVE)
    love.graphics.rectangle("fill", -W / 2, -4, W, 8, 1) -- the lid, knocked off
    love.graphics.setColor(OLIVE[1] * 0.7, OLIVE[2] * 0.7, OLIVE[3] * 0.7)
    love.graphics.rectangle("line", -W / 2, -4, W, 8, 1)
    love.graphics.pop()
    local t = c.t
    if t and t < 0.6 then -- splinters
      for i = 0, 7 do
        local a = i * math.pi / 4 + 0.3
        local d = 10 + t * 120
        love.graphics.setColor(0.6, 0.5, 0.3, 1 - t / 0.6)
        love.graphics.rectangle("fill", x + math.cos(a) * d - 2, y + math.sin(a) * d - 1, 4, 2)
      end
    end
    return
  end
  love.graphics.setColor(OLIVE)
  love.graphics.rectangle("fill", x - W / 2 + 2, y - H / 2 + 2, W - 4, H - 4, 1) -- the lid
  love.graphics.setColor(OLIVE[1] * 0.75, OLIVE[2] * 0.75, OLIVE[3] * 0.75)
  love.graphics.rectangle("fill", x - W / 2 + 2, y - H / 2 + 2, 4, H - 4) -- the battens at the ends
  love.graphics.rectangle("fill", x + W / 2 - 6, y - H / 2 + 2, 4, H - 4)
  love.graphics.setColor(STENCIL)
  local font = UI.fonts.small
  love.graphics.setFont(font)
  local s = 0.72
  love.graphics.print("AMMO", math.floor(x - font:getWidth("AMMO") * s / 2 + 0.5),
    math.floor(y - font:getHeight() * s / 2 + 0.5), 0, s, s)
end

function Crates:drawBelowCars()
  for _, c in pairs(self.crates) do
    drawCrate(c)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Over the crate I'm at: a soft ring round it, so it is plain which one
--- the key opens, and the key over it (on the crate, not at the bottom of
--- the screen: a quest's boss bar is there).
function Crates:drawAboveCars()
  local c = self.near and self.crates[self.near]
  if not c then
    return
  end
  local pulse = 0.5 + 0.5 * math.sin(time * 5)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(STENCIL[1], STENCIL[2], STENCIL[3], 0.4 + pulse * 0.4)
  love.graphics.rectangle("line", c.x - W / 2 - 5, c.y - H / 2 - 5, W + 10, H + 10, 4)
  love.graphics.setLineWidth(1)
  local font = UI.fonts.small
  local text = Controls.name(Controls.bindings("crate")[1]) .. ": open"
  local tw, th = font:getWidth(text) + 12, font:getHeight() + 4
  local tx, ty = c.x - tw / 2, c.y - H / 2 - 12 - th
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", tx, ty, tw, th, 4)
  love.graphics.setFont(font)
  love.graphics.setColor(STENCIL)
  love.graphics.printf(text, tx, ty + 2, tw, "center")
  love.graphics.setColor(1, 1, 1)
end

--- At night a shut crate shows faintly, so it can be found in the dark.
function Crates:drawNightLights(_client, _camera, glow)
  for _, c in pairs(self.crates) do
    if not c.open then
      glow(c.x, c.y, 60, STENCIL, 0.35)
    end
  end
end

Crates.clientMessages = {
  AMC_SPAWN = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if id and x and y then
      Crates.crates[id] = { x = x, y = y, open = args[4] == "1" }
    end
  end,
  AMC_OPENED = function(_client, args)
    local c = Crates.crates[tonumber(args[1]) or 0]
    if c and not c.open then
      c.open, c.t = true, 0
      Sounds.play(c.x, c.y)
    end
  end,
  AMC_CLEAR = function()
    Crates.crates, Crates.near = {}, nil
  end,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { crates = { id -> { x, y, open } }, nextId }

function Crates:serverStart()
  sv = { crates = {}, nextId = 1 }
end

local function spawnMsg(id, c)
  return Protocol.encode("AMC_SPAWN", id, ("%.0f"):format(c.x), ("%.0f"):format(c.y), c.open and 1 or 0)
end

--- May a crate go at (x, y)? Not in a wall, and CLEAR from everyone and
--- APART from the crates already down.
local function freeSpot(server, x, y)
  if Features.any("blocksPoint", x, y) then
    return false
  end
  for _, p in pairs(server.players) do
    if p.body then
      local px, py = Features.bodyPose(server, p)
      if px and (px - x) ^ 2 + (py - y) ^ 2 < Crates.CLEAR * Crates.CLEAR then
        return false
      end
    end
  end
  for _, c in pairs(sv.crates) do
    if (c.x - x) ^ 2 + (c.y - y) ^ 2 < Crates.APART * Crates.APART then
      return false
    end
  end
  return true
end

--- Everyone was moved to another map: the old crates go, and a quest map
--- gets COUNT new ones.
function Crates:mapChanged(_map, server)
  if not (server and sv) then
    return
  end
  sv.crates = {}
  server:broadcast(Protocol.encode("AMC_CLEAR"))
  local city = Features.byName["city-map"]
  if not (city and city.randomRoadPoint) or city.current == city.DEFAULT then
    return -- the city has its own ways to get rounds
  end
  for _ = 1, self.COUNT do
    for _ = 1, 40 do
      local x, y = city:randomRoadPoint()
      if x and freeSpot(server, x, y) then
        local id = sv.nextId
        sv.nextId = id + 1
        sv.crates[id] = { x = x, y = y, open = false }
        server:broadcast(spawnMsg(id, sv.crates[id]))
        break
      end
    end
  end
end

function Crates:serverPlayerJoined(server, player)
  if sv and not player.bot then
    for id, c in pairs(sv.crates) do
      server:send(player, spawnMsg(id, c))
    end
  end
end

--- An ammo type for a box (guns.lua's `ammoTypes`: its item, and the gun
--- that sizes it), by `weights`, else its gun's `dropWeight`.
local function pickAmmo()
  local list, total = {}, 0
  for _, t in ipairs(Guns.ammoTypes) do
    local w = Crates.weights[t.owner.key] or t.gun.dropWeight or 1
    list[#list + 1] = { t = t, w = w }
    total = total + w
  end
  local roll = love.math.random() * total
  for _, e in ipairs(list) do
    roll = roll - e.w
    if roll < 0 then
      return e.t
    end
  end
  return list[#list] and list[#list].t
end

--- Break crate `id` open: everyone hears it, and the boxes spill out round
--- it, a little way apart, starting at a random angle.
local function open(server, id)
  local c = sv.crates[id]
  if not c or c.open then
    return false
  end
  c.open = true
  server:broadcast(Protocol.encode("AMC_OPENED", id))
  local pickups = Features.byName.pickups
  if not (pickups and pickups.serverDrop) then
    return true
  end
  local a0 = love.math.random() * 2 * math.pi
  for k = 1, Crates.BOXES do
    local t = pickAmmo()
    if t then
      local a = a0 + k * 2 * math.pi / Crates.BOXES
      local n = t.gun.tank and 1 or math.max(1, math.floor(Crates.MAGAZINES * t.gun.magazine + 0.5))
      pickups:serverDrop(server, t.item, c.x + math.cos(a) * Crates.SPILL,
        c.y + math.sin(a) * Crates.SPILL, n)
    end
  end
  return true
end
Crates.serverOpen = open -- for tests

--- A round through (x, y): the `serverShotAt` convention. A player's round
--- breaks a shut crate open there and stops; anything else (Heck's, the
--- Combine's) flies on.
function Crates:serverShotAt(server, x, y, radius, by)
  if not sv or not by or by == 0 then
    return false
  end
  local r = self.RADIUS + (radius or 0)
  for id, c in pairs(sv.crates) do
    if not c.open and (c.x - x) ^ 2 + (c.y - y) ^ 2 <= r * r then
      return open(server, id) and "solid"
    end
  end
  return false
end

--- A player's blast (a rocket, a grenade) breaks every shut crate it reaches.
function Crates:serverBlast(server, x, y, radius, _damage, by)
  if not sv or not by or by == 0 then
    return
  end
  for id, c in pairs(sv.crates) do
    if not c.open and (c.x - x) ^ 2 + (c.y - y) ^ 2 <= radius * radius then
      open(server, id)
    end
  end
end

Crates.serverMessages = {
  AMC_OPEN = function(server, player, args)
    local c = sv and sv.crates[tonumber(args[1]) or 0]
    if not (c and Features.present(player) and player.body and not player.vehicle) then
      return
    end
    local x, y = Features.bodyPose(server, player)
    local reach = Crates.REACH + 10 -- a step of slack for the trip over the wire
    if (c.x - x) ^ 2 + (c.y - y) ^ 2 <= reach * reach then
      open(server, tonumber(args[1]))
    end
  end,
}

return Crates
