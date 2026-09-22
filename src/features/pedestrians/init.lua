-- Pedestrians: a crowd that wanders the streets, breaks for the kerb when a
-- car comes at it, and bursts into gibs when one connects.
--
-- The host owns every pedestrian (crowd.lua): it spawns them in a ring just
-- outside anyone's view, recycles the ones nobody can see, and decides who
-- gets flattened. Clients only receive positions and draw them (render.lua,
-- gibs.lua), so a pedestrian never dies twice or dodges differently on two
-- machines.
--
-- Positions go out unreliably at half tick rate and clients ease between
-- them, which keeps a crowd of eighty to a few kilobytes a second.
--
-- Messages
--   server -> all  PED_SYNC <tick> [<id> <x> <y> <flee>]...   (unreliable, 15 Hz)
--   server -> all  PED_GIB  <id> <x> <y> <angle> <killer> <total>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Crowd = require("src.features.pedestrians.crowd")
local Render = require("src.features.pedestrians.render")
local Gibs = require("src.features.pedestrians.gibs")
local Sounds = require("src.features.pedestrians.sounds")

local Pedestrians = {
  name = "pedestrians",
  priority = 60, -- after the grid (10), before the weapons HUD (950)
}

local SYNC_EVERY = 2 -- server ticks between PED_SYNC broadcasts
local YELP_CHANCE = 0.4 -- how often a pedestrian who bolts cries out
local YELP_GAP = 0.25 -- seconds between cries, so a crowd doesn't shriek at once
local YELP_RANGE = 1100 -- px from your car; further away nobody hears it

Pedestrians.roadkill = {} -- client side: player id -> pedestrians flattened
Pedestrians.lastSync = 0 -- client side: newest server tick seen in a PED_SYNC
Pedestrians.yelpTimer = 0 -- a PED_SYNC can land before enterGame runs

-- Client --------------------------------------------------------------------

function Pedestrians:load()
  Sounds.load()
end

function Pedestrians:enterGame()
  Render.clear()
  Gibs.clear()
  self.roadkill = {}
  self.lastSync = 0 -- a new host starts counting ticks from zero again
  self.yelpTimer = 0
end

function Pedestrians:exitGame()
  self:enterGame()
end

function Pedestrians:update(dt)
  Render.update(dt)
  Gibs.update(dt)
  self.yelpTimer = self.yelpTimer - dt
end

--- Let a few of the pedestrians who just bolted cry out. Only the ones near
--- enough to hear, and never two at once, however big the stampede.
function Pedestrians:panicCries(client)
  local me = client:myCar()
  if not me then
    return
  end
  for i = 1, Render.panickedN do
    local p = Render.panicked[i]
    local dx, dy = p.x - me.dx, p.y - me.dy
    if self.yelpTimer <= 0 and dx * dx + dy * dy < YELP_RANGE * YELP_RANGE then
      if love.math.random() < YELP_CHANCE then
        Sounds.panic(p.id, p.x, p.y)
        self.yelpTimer = YELP_GAP
      end
    end
  end
end

function Pedestrians:drawBelowCars(_client, camera)
  Gibs.drawStains()
  Render.draw(camera)
end

function Pedestrians:drawAboveCars()
  Gibs.drawChunks()
end

function Pedestrians:drawHUD(client)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.85, 0.5, 0.5)
  love.graphics.print(("roadkill %d"):format(self.roadkill[client.myId] or 0), 10, 100)
  love.graphics.setColor(1, 1, 1)
end

Pedestrians.clientMessages = {
  PED_SYNC = function(client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= Pedestrians.lastSync then
      return -- an unreliable packet that overtook a newer one
    end
    Pedestrians.lastSync = tick
    Render.sync(args)
    Pedestrians:panicCries(client)
  end,
  PED_GIB = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    local killer, total = tonumber(args[5]), tonumber(args[6])
    if not (x and y and angle) then
      return
    end
    if id then
      Render.remove(id) -- don't let them keep walking until the next sync
    end
    Gibs.splat(x, y, angle)
    Sounds.play("splat", x, y, 0.88 + love.math.random() * 0.24)
    if killer and total then
      Pedestrians.roadkill[killer] = total
    end
  end,
}

-- Server --------------------------------------------------------------------

function Pedestrians:serverStart()
  self.crowd = Crowd.new()
  self.scores = {}
  self.syncIn = 0
end

function Pedestrians:serverPlayerLeft(_server, player)
  if self.scores then
    self.scores[player.id] = nil
  end
end

--- One PED_SYNC line for the whole crowd. Pixel precision is plenty for a
--- walking figure and keeps the packet small.
local function syncMessage(crowd, tick)
  local parts = { tick }
  local peds = crowd.peds
  for i = 1, crowd.n do
    local p = peds[i]
    parts[#parts + 1] = p.id
    parts[#parts + 1] = ("%.0f"):format(p.x)
    parts[#parts + 1] = ("%.0f"):format(p.y)
    parts[#parts + 1] = p.flee > 0 and 1 or 0
  end
  return Protocol.encode("PED_SYNC", unpack(parts))
end

function Pedestrians:serverStep(server, dt)
  local crowd = self.crowd
  if not crowd then
    return
  end

  for _, kill in ipairs(crowd:update(server, dt)) do
    local total = (self.scores[kill.by] or 0) + 1
    self.scores[kill.by] = total
    server:broadcast(Protocol.encode("PED_GIB", kill.id, ("%.0f"):format(kill.x), ("%.0f"):format(kill.y),
      ("%.3f"):format(kill.angle), kill.by, total))
    Features.call("serverKill", server, { kind = "pedestrian", x = kill.x, y = kill.y, by = kill.by })
  end

  self.syncIn = self.syncIn - 1
  if self.syncIn > 0 then
    return
  end
  self.syncIn = SYNC_EVERY
  local msg = syncMessage(crowd, server.tick)
  for _, player in pairs(server.players) do
    server:send(player, msg, true)
  end
end

return Pedestrians
