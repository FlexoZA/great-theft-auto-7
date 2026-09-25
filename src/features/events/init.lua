-- Events: something big happening in the city, out of the blue. A boss comes
-- into the streets somewhere and goes after the players and their
-- buildings. When one starts every minimap flashes red where he came in and
-- keeps a mark on him while he is loose; a banner says what is going on. The
-- police want none of it: while an event runs they are off the streets
-- (police asks `serverEventActive`), and they come back once it is over.
--
-- One event at a time, and only on the default city map: a trip to a quest
-- map, or any map change, calls it off. For now an event starts by hand:
-- the host presses F8 ("Start the Bigfoot event (host)" in Settings >
-- Controls), or another feature calls `Events:serverTrigger(server, key)`.
-- When and how they start by themselves is still to be decided.
--
-- Each kind of event is a module in this folder, listed in `Events.kinds`
-- by key. The host owns everything; this file keeps which event is on and
-- tells every machine, and the event's module runs the rest. An event
-- module has:
--   key, title, subtitle, wonTitle, wonSubtitle, color
--   serverBegin(server, events) -> x, y   bring the boss in; nil if it can't
--   serverStep(server, dt, events)        every host tick while it is on;
--                                         `events:serverFinish(server, x, y)`
--                                         when the boss is beaten
--   serverStop(server)                    it is over, beaten or called off:
--                                         clear the host's side
--   serverPlayerJoined(server, player)    tell a latecomer what it only sends on change
--   serverShotAt / serverPanicArea / serverFreezeArea   passed on while it is on
--   start(x, y), stop()                   the same on every machine (EVT_START / EVT_END)
--   where() -> x, y                       where the boss is now, for the minimap
--   update(dt, client, camera), drawBelowCars, drawAboveCars, drawHUD(client, camera)
--   clientMessages                        its own message kinds, merged into ours
--
-- Messages
--   client -> server  EVT_TRIGGER <key>                 the host starts one (anyone else is ignored)
--   server -> player  EVT_NO    <reason>                it could not start: busy | away | nowhere
--   server -> all  EVT_START <key> <x> <y> <fresh>   an event began at (x, y); fresh = 0 for a latecomer
--   server -> all  EVT_END   <key> <x> <y> <won>     it is over: beaten there (won = 1) or called off

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Net = require("src.net")
local Controls = require("src.controls")
local Bigfoot = require("src.features.events.bigfoot")
local HuntSounds = require("src.features.alien-hunt.sounds")

local Events = {
  name = "events",
  priority = 960, -- the banner over most of the HUD, under the quest portraits (970+)
}

Events.kinds = { bigfoot = Bigfoot }

-- Tuning ------------------------------------------------------------------
Events.flashTime = 6 -- seconds the minimap flashes red when one starts
Events.bannerTime = 5 -- seconds the banner stays up
Events.noticeTime = 3 -- seconds a "can't start" notice stays up

local HOST_ID = 1 -- the host's own player, as bots has it
local REFUSED = {
  busy = "An event is already on",
  away = "Events only happen in the city, off a quest",
  nowhere = "Nowhere for him to come in",
  nogame = "No game running",
}

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { active = key or nil, x, y }

function Events:serverStart()
  if sv and sv.active then
    self.kinds[sv.active].serverStop(nil)
  end
  sv = { active = nil }
end

--- The `serverEventActive` convention: is an event on? Police stands down.
function Events:serverEventActive()
  return sv ~= nil and sv.active ~= nil
end

--- The event on the host, or nil.
function Events:serverActive()
  return sv and sv.active and self.kinds[sv.active] or nil
end

--- Start event `key` now. Returns true, or false and why not (for the cheat
--- banner): "busy" (one is on), "away" (not in the city, or on a quest),
--- "unknown" or "nowhere" (no place to bring the boss in).
function Events:serverTrigger(server, key)
  local event = self.kinds[key]
  if not (sv and server.started) then
    return false, "nogame"
  elseif not event then
    return false, "unknown"
  elseif sv.active then
    return false, "busy"
  end
  local city = Features.byName["city-map"]
  local quests = Features.byName.quests
  if (city and city.current ~= city.DEFAULT) or (quests and quests.serverActive and quests:serverActive()) then
    return false, "away"
  end
  local x, y = event.serverBegin(server, self)
  if not x then
    return false, "nowhere"
  end
  sv.active, sv.x, sv.y = key, x, y
  server:broadcast(Protocol.encode("EVT_START", key, fmt(x), fmt(y), 1))
  return true
end

--- The boss was beaten at (x, y): the event is over and the police come back.
function Events:serverFinish(server, x, y)
  self:serverEnd(server, x, y, true)
end

--- Over, beaten (`won`) or called off.
function Events:serverEnd(server, x, y, won)
  if not (sv and sv.active) then
    return
  end
  local key = sv.active
  sv.active = nil
  self.kinds[key].serverStop(server)
  server:broadcast(Protocol.encode("EVT_END", key, fmt(x or sv.x), fmt(y or sv.y), won and 1 or 0))
end

--- Any map change calls it off: the boss belongs to the city.
function Events:mapChanged(_map, server)
  if server then
    self:serverEnd(server, nil, nil, false)
  end
end

function Events:serverStep(server, dt)
  local event = self:serverActive()
  if event then
    event.serverStep(server, dt, self)
  end
end

--- Someone joining mid-event hears it is on (no flash: it didn't just
--- start) and whatever the event only sends on change.
function Events:serverPlayerJoined(server, player)
  local event = self:serverActive()
  if event and server.started and not player.bot then
    server:send(player, Protocol.encode("EVT_START", sv.active, fmt(sv.x), fmt(sv.y), 0))
    if event.serverPlayerJoined then
      event.serverPlayerJoined(server, player)
    end
  end
end

function Events:serverShotAt(server, x, y, radius, by, angle)
  local event = self:serverActive()
  return event ~= nil and event.serverShotAt ~= nil and event.serverShotAt(server, x, y, radius, by, angle)
end

function Events:serverPanicArea(server, x, y, radius)
  local event = self:serverActive()
  if event and event.serverPanicArea then
    event.serverPanicArea(server, x, y, radius)
  end
end

function Events:serverFreezeArea(server, x, y, radius, seconds)
  local event = self:serverActive()
  if event and event.serverFreezeArea then
    event.serverFreezeArea(server, x, y, radius, seconds)
  end
end

--- For tests.
function Events.server()
  return sv
end

-- Client --------------------------------------------------------------------

Events.active = nil -- { key, x, y }: the event on, as the host said
Events.flash = 0 -- seconds of red flashing left on the minimap
Events.banner = nil -- { title, subtitle, color, t }
local time = 0
local camera = nil

local function clear()
  if Events.active then
    Events.kinds[Events.active.key].stop()
  end
  Events.active, Events.flash, Events.banner = nil, 0, nil
end

function Events:load()
  Controls.register("event-bigfoot", "Start the Bigfoot event (host)", "f8")
end

function Events:exitGame()
  clear()
  self.notice = nil
end

function Events:keypressed(key, client)
  if Net.isHost() and Controls.is("event-bigfoot", key) then
    client:send(Protocol.encode("EVT_TRIGGER", "bigfoot"))
  end
end

function Events:update(dt, client, cam)
  time = time + dt
  camera = cam
  self.flash = math.max(0, self.flash - dt)
  if self.notice then
    self.notice.t = self.notice.t - dt
    self.notice = self.notice.t > 0 and self.notice or nil
  end
  local b = self.banner
  if b then
    b.t = b.t - dt
    if b.t <= 0 then
      self.banner = nil
    end
  end
  if self.active then
    self.kinds[self.active.key].update(dt, client, cam)
  end
end

function Events:drawBelowCars(client, cam)
  if self.active then
    self.kinds[self.active.key].drawBelowCars(client, cam)
  end
end

function Events:drawAboveCars(client, cam)
  if self.active then
    self.kinds[self.active.key].drawAboveCars(client, cam)
  end
end

--- The minimap hook: flashing red all over while the event is fresh, with
--- rings going out from where the boss came in, and a pulsing red mark on
--- him for as long as he is loose.
function Events:drawOnMinimap(_client, toMap, w, h)
  local a = self.active
  if not a then
    return
  end
  if self.flash > 0 then
    local fade = math.min(1, self.flash / 1.5)
    local blink = 0.5 + 0.5 * math.sin(time * 12)
    love.graphics.setColor(0.9, 0.05, 0.05, (0.15 + 0.3 * blink) * fade)
    love.graphics.rectangle("fill", 0, 0, w, h)
    local sx, sy = toMap(a.x, a.y)
    love.graphics.setLineWidth(2)
    for i = 0, 2 do
      local k = (time * 0.9 + i / 3) % 1
      love.graphics.setColor(1, 0.15, 0.1, (1 - k) * fade)
      love.graphics.circle("line", sx, sy, 4 + k * 40)
    end
    love.graphics.setLineWidth(1)
  end
  local x, y = self.kinds[a.key].where()
  if x then
    local px, py = toMap(x, y)
    local pulse = 0.5 + 0.5 * math.sin(time * 8)
    love.graphics.setColor(1, 0.1, 0.05, 0.35 * pulse)
    love.graphics.circle("fill", px, py, 7 + 3 * pulse)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.circle("fill", px, py, 5)
    love.graphics.setColor(1, 0.15, 0.1)
    love.graphics.circle("fill", px, py, 4)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle("line", px, py, 5)
  end
end

--- The banner: a big title over a line of what to do, fading out.
local function drawBanner(b)
  local w = love.graphics.getWidth()
  local alpha = math.min(1, b.t * 2, (Events.bannerTime - b.t) * 4 + 0.2)
  local c = b.color
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0, 0, 0, 0.6 * alpha)
  love.graphics.printf(b.title, 2, 132, w, "center")
  love.graphics.setColor(c[1], c[2], c[3], alpha)
  love.graphics.printf(b.title, 0, 130, w, "center")
  love.graphics.setFont(UI.fonts.body)
  local sub = b.subtitle
  UI.label(sub, math.floor((w - UI.fonts.body:getWidth(sub)) / 2), 130 + UI.fonts.heading:getHeight() + 6,
    { 1, 0.9, 0.85, alpha })
end

function Events:drawHUD(client)
  if self.active then
    self.kinds[self.active.key].drawHUD(client, camera)
  end
  if self.banner then
    drawBanner(self.banner)
  end
  local n = self.notice
  if n then
    local w = love.graphics.getWidth()
    love.graphics.setFont(UI.fonts.body)
    UI.label(n.text, math.floor((w - UI.fonts.body:getWidth(n.text)) / 2), 130, { 1, 0.6, 0.5, math.min(1, n.t) })
  end
  love.graphics.setColor(1, 1, 1)
end

local function banner(title, subtitle, color)
  Events.banner = { title = title, subtitle = subtitle, color = color, t = Events.bannerTime }
end

Events.clientMessages = {
  EVT_START = function(_client, args)
    local event = Events.kinds[args[1] or ""]
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (event and x and y) then
      return
    end
    clear()
    Events.active = { key = args[1], x = x, y = y }
    event.start(x, y)
    if args[4] == "1" then
      Events.flash = Events.flashTime
      banner(event.title, event.subtitle, event.color)
      HuntSounds.play("roar", camera and camera.x or x, camera and camera.y or y) -- heard wherever you are
    end
  end,
  EVT_END = function(_client, args)
    local event = Events.kinds[args[1] or ""]
    if not (event and Events.active and Events.active.key == args[1]) then
      return
    end
    local x, y = tonumber(args[2]), tonumber(args[3])
    Events.active, Events.flash = nil, 0
    event.stop()
    if args[4] == "1" and x and y then
      banner(event.wonTitle, event.wonSubtitle, { 0.55, 1, 0.45 })
    end
  end,
}

Events.clientMessages.EVT_NO = function(_client, args)
  Events.notice = { text = REFUSED[args[1] or ""] or "No event", t = Events.noticeTime }
end

Events.serverMessages = {
  EVT_TRIGGER = function(server, player, args)
    if player.id ~= HOST_ID then
      return -- only the host starts events by hand
    end
    local ok, why = Events:serverTrigger(server, args[1] or "")
    if not ok then
      server:send(player, Protocol.encode("EVT_NO", why))
    end
  end,
}

for kind, handler in pairs(Bigfoot.clientMessages) do
  Events.clientMessages[kind] = handler
end

return Events
