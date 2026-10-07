-- Park bums: every park in the city has a bum living on one of its benches,
-- his shopping cart parked beside him. Walk up to him and the action key
-- (F) asks who you want sorted out; pick another player or a traffic bot,
-- pay `Bums.PRICE` (1000 Fcks) and he gets up and goes after them. He
-- punches them bloody (melee, and a bleed harder than a plain melee hit
-- leaves) and shouts abuse the whole time, until they go down, they leave,
-- or he gives up and shuffles back to his bench. The target's screen warns
-- them; nobody is told who paid. His first punch has them cry "I have been
-- stabbed", and a cop who sees it only answers "I don't think you have
-- mate"; shoot back at him in front of one, though, and you are wanted. A
-- bot he goes after fights him off. He can be shot, hit by cars, frozen or
-- farted at; put down, another takes his bench a minute later.
--
-- The host runs the bums (bums.lua); clients draw what they are told. The
-- benches come from the map (city-map's parks), so every machine knows
-- where they are without being told. What they say is lines.lua, picked
-- on the host so every screen shows the same words, said in voice.lua's
-- slurred synth voice.
--
-- Messages
--   client -> server  BUM_HIRE  <bum> <target>      hire that bum to go after that player
--   server -> all     BUM_STATE <tick> [<bum> <x> <y> <facing> <mode> <punch> <target>]...
--                     (unreliable, 10 Hz; mode s = on his bench, h = on a job, w = walking home;
--                     a bum left out is down)
--   server -> all     BUM_SAY   <bum> <kind> <line> a line of lines.lua's `kind`
--   server -> all     BUM_DOWN  <bum> <x> <y> <angle>
--   server -> all     BUM_CRY   <player>          his first punch landed on them: they cry out
--   server -> hirer   BUM_OK    <bum> <target>
--   server -> hirer   BUM_NO    <reason>            broke | busy | away | target | gone | nogame

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Bums = require("src.features.park-bums.bums")
local Lines = require("src.features.park-bums.lines")
local Voice = require("src.features.park-bums.voice")
local Render = require("src.features.park-bums.render")

local ParkBums = { name = "park-bums" }

local SYNC_EVERY = 3 -- server ticks between BUM_STATE packets
local SMOOTHING = 10 -- per second, easing towards the last position heard
local SNAP = 150 -- px; a jump this big is a bum back on his bench, not a step
local NOTICE_TIME = 3
local MAX_ROWS = 9 -- targets on the menu, one per number key
local MODES = { s = "sit", h = "hunt", w = "home" }
local WIRE = { sit = "s", hunt = "h", home = "w" }
local REFUSALS = {
  broke = "Not enough Fcks. He wants %s up front.",
  busy = "He's busy with somebody else.",
  away = "Get closer to him, on foot.",
  target = "They're not around right now.",
  gone = "There's nobody on that bench.",
  nogame = "Not now.",
}

local function fmt(v)
  return ("%.0f"):format(v)
end

--- "1000 Fcks", the way the money feature writes a price.
local function price()
  local money = Features.byName.money
  return money and money.amount(Bums.PRICE) or tostring(Bums.PRICE)
end

local function refusal(reason)
  return (REFUSALS[reason] or REFUSALS.nogame):format(price())
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

-- Server --------------------------------------------------------------------

local sv = nil -- { bums, syncIn, sent }

function ParkBums:serverStart()
  sv = { bums = Bums.new(cityMap()), syncIn = 0, sent = 0 }
end

--- A new map: its own parks, its own bums (none off the city).
function ParkBums:mapChanged(map, server)
  if server and sv then
    sv.bums = Bums.new(map)
  end
  self.bums, self.cries = {}, {}
  self.open, self.near = false, nil
end

--- What was said and who went down, out to everyone.
local function flush(server)
  local says, downs, cries = sv.bums:drain()
  for _, id in ipairs(cries) do
    server:broadcast(Protocol.encode("BUM_CRY", id))
  end
  for _, s in ipairs(says) do
    server:broadcast(Protocol.encode("BUM_SAY", s.id, s.kind, s.index))
  end
  for _, k in ipairs(downs) do
    server:broadcast(Protocol.encode("BUM_DOWN", k.id, fmt(k.x), fmt(k.y), ("%.3f"):format(k.angle)))
    Features.call("serverKill", server, { kind = "pedestrian", x = k.x, y = k.y, by = k.by })
  end
end

function ParkBums:serverStep(server, dt)
  if not sv then
    return
  end
  sv.bums:step(server, dt)
  flush(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local parts = { server.tick }
  for _, b in ipairs(sv.bums.list) do
    if b.mode ~= "down" then
      parts[#parts + 1] = b.id
      parts[#parts + 1] = fmt(b.x)
      parts[#parts + 1] = fmt(b.y)
      parts[#parts + 1] = ("%.2f"):format(b.facing)
      parts[#parts + 1] = WIRE[b.mode]
      parts[#parts + 1] = b.swing > 0 and 1 or 0
      parts[#parts + 1] = b.target or 0
    end
  end
  if #parts == 1 and sv.sent == 0 then
    return -- nobody about, and everyone knows it
  end
  sv.sent = #parts - 1
  local msg = Protocol.encode("BUM_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- A bullet passing through (x, y): the `serverShotAt` convention. A bum
--- standing (or sitting) there takes it.
function ParkBums:serverShotAt(server, x, y, radius, by, angle, damage)
  local b = sv and sv.bums:at(x, y, radius)
  if not b then
    return false
  end
  sv.bums:hurt(b, damage or Bums.SHOT_DAMAGE, by ~= 0 and by or nil, angle)
  flush(server)
  return true
end

--- Somebody fired (the `serverShotFired` event, heard before the police
--- hear it): one who cried out to a bum and is still owed a cop's answer
--- gets it now, before that cop goes after them for shooting.
function ParkBums:serverShotFired(server, player)
  if sv and player then
    sv.bums:answer(server, 0, player.id)
  end
end

function ParkBums:serverFreezeArea(_server, x, y, radius, seconds)
  if sv then
    sv.bums:freeze(x, y, radius, seconds)
  end
end

function ParkBums:serverPanicArea(_server, x, y, radius)
  if sv then
    sv.bums:scare(x, y, radius, 0.5)
  end
end

--- Cars on patrol stop for a bum up and walking (the `serverWalkers` event).
function ParkBums:serverWalkers(_server, add)
  if not sv then
    return
  end
  for _, b in ipairs(sv.bums.list) do
    if b.mode == "hunt" or b.mode == "home" then
      add(b.x, b.y)
    end
  end
end

ParkBums.serverMessages = {
  BUM_HIRE = function(server, player, args)
    local id, targetId = tonumber(args[1]), tonumber(args[2])
    local function no(reason)
      server:send(player, Protocol.encode("BUM_NO", reason))
    end
    if not (sv and id and targetId) then
      return no("gone")
    end
    local target = server.players[targetId]
    local ok, why = sv.bums:canHire(server, player, id, target)
    if not ok then
      return no(why)
    end
    local money = Features.byName.money
    if money then
      local paid, reason = money:spend(server, player.id, Bums.PRICE, "bum")
      if not paid then
        return no(reason or "broke")
      end
    end
    sv.bums:hire(id, target)
    flush(server)
    server:send(player, Protocol.encode("BUM_OK", id, targetId))
  end,
}

--- For tests.
function ParkBums.server()
  return sv
end

-- Client --------------------------------------------------------------------

ParkBums.bums = {} -- id -> { x, y, dx, dy, angle, mode, punch, target, say, bob }
ParkBums.open = false -- the hire menu is up
ParkBums.near = nil -- the bum on his bench I am standing beside
ParkBums.cries = {} -- player id -> seconds their "I have been stabbed" hangs on
local time, lastTick = 0, 0
local homes, homesOf, homesVersion = {}, nil, nil -- every bum's bench, worked out from the map

function ParkBums:load()
  Voice.load()
  Controls.register("bum", "Hire a park bum (next to him)", "f") -- the action key, like the shop's
end

function ParkBums:exitGame()
  self.bums, self.cries = {}, {}
  self.open, self.near, self.notice = false, nil, nil
  lastTick = 0
end

--- The benches of the map in play.
local function currentHomes()
  local map = cityMap()
  if map ~= homesOf or (map and map.version ~= homesVersion) then
    homes, homesOf, homesVersion = Bums.homes(map), map, map and map.version
  end
  return homes
end

--- Who I could set a bum on: everyone else in the game but the police and
--- anybody's hired drivers, players before bots, by name.
local function targets(client)
  local police = Features.byName.police
  local delivery = Features.byName.delivery
  local bots = Features.byName.bots
  local list = {}
  for id, p in pairs(client.players) do
    if id ~= client.myId and not (police and police.units[id]) and not (delivery and delivery.units[id]) then
      list[#list + 1] = { id = id, name = p.name or "?", bot = bots and bots.ids[id] or false }
    end
  end
  table.sort(list, function(a, b)
    if a.bot ~= b.bot then
      return not a.bot
    end
    return a.name:lower() < b.name:lower()
  end)
  while #list > MAX_ROWS do
    list[#list] = nil
  end
  return list
end

function ParkBums:say(text, kind)
  self.notice = { text = text, t = NOTICE_TIME, kind = kind }
end

function ParkBums:update(dt, client)
  time = time + dt
  local k = math.min(1, dt * SMOOTHING)
  for _, b in pairs(self.bums) do
    local ex, ey = b.x - b.dx, b.y - b.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      b.dx, b.dy = b.x, b.y
    else
      b.dx, b.dy = b.dx + ex * k, b.dy + ey * k
    end
    if b.say then
      b.say.t = b.say.t - dt
      if b.say.t <= 0 then
        b.say = nil
      end
    end
  end
  for id, t in pairs(self.cries) do
    self.cries[id] = t > dt and t - dt or nil
  end
  -- The bum on his bench I am standing beside, on foot.
  local x, y, onFoot = client:myPose()
  local best, bestD2 = nil, Bums.TALK_REACH ^ 2
  if x and onFoot then
    for id, b in pairs(self.bums) do
      local d2 = (b.dx - x) ^ 2 + (b.dy - y) ^ 2
      if b.mode == "sit" and d2 <= bestD2 then
        best, bestD2 = id, d2
      end
    end
  end
  self.near = best
  if self.open and not best then
    self.open = false -- walked off, or he got up
  end
  if self.notice then
    self.notice.t = self.notice.t - dt
    if self.notice.t <= 0 then
      self.notice = nil
    end
  end
end

--- Ask the host to set the bum I am beside on `row`'s player.
local function hire(self, client, row)
  local money = Features.byName.money
  if money and not money:canAfford(client, Bums.PRICE) then
    self:say(refusal("broke"), "no")
    return
  end
  if self.near then
    client:send(Protocol.encode("BUM_HIRE", self.near, row.id))
  end
end

function ParkBums:actionTaken()
  return self.open or self.near ~= nil
end

function ParkBums:menuOpen()
  return self.open
end

function ParkBums:pointerTaken()
  return self.open
end

function ParkBums:closeMenu()
  if not self.open then
    return false
  end
  self.open = false
  return true
end

function ParkBums:keypressed(key, client)
  if Controls.is("bum", key) and (self.open or self.near) then
    self.open = not self.open
    return
  end
  local n = self.open and tonumber(key:match("^kp(%d)$") or key:match("^(%d)$"))
  local row = n and targets(client)[n]
  if row then
    hire(self, client, row)
  end
end

-- The menu's layout: the panel and a box per row.
local PANEL_W, ROW_H, ROW_GAP, HEAD_H, FOOT_H = 380, 34, 6, 96, 34

local function menuLayout(rows)
  local w, h = love.graphics.getDimensions()
  local ph = HEAD_H + math.max(1, #rows) * (ROW_H + ROW_GAP) + FOOT_H
  local px, py = math.floor((w - PANEL_W) / 2), math.floor((h - ph) / 2)
  local boxes = {}
  for i = 1, #rows do
    boxes[i] = { x = px + 20, y = py + HEAD_H + (i - 1) * (ROW_H + ROW_GAP), w = PANEL_W - 40, h = ROW_H }
  end
  return { x = px, y = py, w = PANEL_W, h = ph }, boxes
end

function ParkBums:mousepressed(x, y, button, client)
  if not (self.open and button == 1) then
    return
  end
  local rows = targets(client)
  local _, boxes = menuLayout(rows)
  for i, b in ipairs(boxes) do
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      hire(self, client, rows[i])
      return
    end
  end
end

ParkBums.clientMessages = {
  BUM_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local seen = {}
    for i = 2, #args - 6, 7 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local b = ParkBums.bums[id]
        if not b then
          b = { dx = x, dy = y, bob = love.math.random() * 6 }
          ParkBums.bums[id] = b
        end
        b.x, b.y = x, y
        b.angle = tonumber(args[i + 3]) or b.angle or 0
        b.mode = MODES[args[i + 4]] or "sit"
        b.punch = args[i + 5] == "1"
        local target = tonumber(args[i + 6]) or 0
        b.target = target ~= 0 and target or nil
        seen[id] = true
      end
    end
    for id in pairs(ParkBums.bums) do
      if not seen[id] then
        ParkBums.bums[id] = nil
      end
    end
  end,
  BUM_SAY = function(_client, args)
    local id, kind, index = tonumber(args[1]), args[2], tonumber(args[3])
    local text = Lines[kind] and index and Lines[kind][index]
    if not (id and text) then
      return
    end
    local shout = kind ~= "mutter"
    local b = ParkBums.bums[id]
    local home = currentHomes()[id]
    local x, y = b and b.dx or home and home.x, b and b.dy or home and home.y
    if b then
      b.say = { text = text, t = Voice.sayTime(text), shout = shout }
    end
    if x then
      Voice.play(text, x, y, shout)
    end
  end,
  BUM_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if id then
      ParkBums.bums[id] = nil
    end
    if x and y and Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle)
      require("src.features.pedestrians.sounds").play("splat", x, y, 0.9 + love.math.random() * 0.2)
    end
  end,
  BUM_CRY = function(_client, args)
    local id = tonumber(args[1])
    if id then
      ParkBums.cries[id] = Voice.sayTime(Lines.stabbed)
    end
  end,
  BUM_OK = function(client, args)
    local target = client.players[tonumber(args[2]) or -1]
    ParkBums.open = false
    ParkBums:say(("Paid. He's off after %s."):format(target and target.name or "them"), "ok")
  end,
  BUM_NO = function(_client, args)
    ParkBums:say(refusal(args[1]), "no")
  end,
}

-- Drawing ---------------------------------------------------------------------

--- Is (x, y) within `pad` of what the camera shows?
local function onScreen(camera, x, y, pad)
  if not camera then
    return true
  end
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  return math.abs(x - camera.x) <= w / 2 / s + pad and math.abs(y - camera.y) <= h / 2 / s + pad
end

--- Each bum's cart beside his bench, whether he is on it or not.
function ParkBums:drawBelowCars(_client, camera)
  for _, h in ipairs(currentHomes()) do
    local side = h.angle + math.pi / 2
    local x, y = h.x + math.cos(side) * 30, h.y + math.sin(side) * 30
    if onScreen(camera, x, y, 40) then
      Render.cart(x, y, h.angle + math.pi)
    end
  end
end

function ParkBums:drawAboveCars(client, camera)
  for id, b in pairs(self.bums) do
    if onScreen(camera, b.dx, b.dy, 30) then
      local sitting = b.mode == "sit"
      local swing = sitting and 0 or math.sin(time * (b.mode == "hunt" and 14 or 7) + b.bob) * 1.4
      local sip = sitting and math.max(0, math.sin(time * 0.6 + id * 1.7) - 0.85) / 0.15 or 0
      Render.bum(b.dx, b.dy, b.angle, swing, b.punch, sitting, sip)
    end
  end
  for _, b in pairs(self.bums) do
    if b.say and onScreen(camera, b.dx, b.dy, 200) then
      Voice.drawBubble(b.dx, b.dy - 10, b.say.text, math.min(1, b.say.t * 2), b.say.shout)
    end
  end
  for id, t in pairs(self.cries) do
    local x, y = Features.clientBodyPose(client, id)
    if x and onScreen(camera, x, y, 200) then
      Voice.drawBubble(x, y - 44, Lines.stabbed, math.min(1, t * 2), false) -- over the bum's, if he is close
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- A dot on each bench with a bum on it, and a red one on any bum after me.
function ParkBums:drawOnMinimap(client, toMap)
  for _, b in pairs(self.bums) do
    local x, y = toMap(b.dx, b.dy)
    if b.mode == "hunt" and b.target == client.myId then
      local pulse = 0.5 + 0.5 * math.sin(time * 8)
      love.graphics.setColor(1, 0.15, 0.1, 0.4 * pulse)
      love.graphics.circle("fill", x, y, 5 + 2 * pulse)
      love.graphics.setColor(1, 0.2, 0.1)
      love.graphics.circle("fill", x, y, 3)
    elseif b.mode == "sit" then
      love.graphics.setColor(0, 0, 0, 0.7)
      love.graphics.circle("fill", x, y, 3)
      love.graphics.setColor(0.72, 0.52, 0.30)
      love.graphics.circle("fill", x, y, 2)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- The footsteps feature's hook: bums up and walking.
function ParkBums:footstepWalkers()
  local list = {}
  for id, b in pairs(self.bums) do
    if b.mode ~= "sit" then
      list[#list + 1] = { key = id, x = b.dx, y = b.dy, size = "person" }
    end
  end
  return list
end

local function centred(text, y, color)
  local w = love.graphics.getWidth()
  love.graphics.setColor(0, 0, 0, 0.6 * (color[4] or 1))
  love.graphics.printf(text, 1, y + 1, w, "center")
  love.graphics.setColor(color)
  love.graphics.printf(text, 0, y, w, "center")
end

function ParkBums:drawHUD(client)
  local h = love.graphics.getHeight()
  love.graphics.setFont(UI.fonts.body)
  if self.near and not self.open then
    local key = Controls.name(Controls.bindings("bum")[1])
    centred(("A bum.  %s: hire him to beat somebody up (%s)"):format(key, price()), h - 130,
      { 0.85, 0.68, 0.45 })
  end
  -- Somebody paid one to come after me.
  for _, b in pairs(self.bums) do
    if b.mode == "hunt" and b.target == client.myId then
      local x, y = client:myPose()
      local far = x and math.floor(math.sqrt((b.dx - x) ^ 2 + (b.dy - y) ^ 2) / 10 + 0.5)
      local pulse = 0.6 + 0.4 * math.sin(time * 6)
      local top, lineH = 120, UI.fonts.heading:getHeight() -- under the police's WANTED
      love.graphics.setColor(0.08, 0, 0, 0.6)
      love.graphics.rectangle("fill", 0, top - 6, love.graphics.getWidth(), lineH + UI.fonts.small:getHeight() + 14)
      love.graphics.setFont(UI.fonts.heading)
      centred("A BUM HAS BEEN PAID TO GET YOU", top, { 1, 0.3, 0.2, pulse })
      if far then
        love.graphics.setFont(UI.fonts.small)
        centred(("%d m away"):format(far), top + lineH + 2, { 1, 0.75, 0.7, 0.9 })
      end
      break
    end
  end
  if self.notice and not self.open then
    love.graphics.setFont(UI.fonts.body)
    local c = self.notice.kind == "no" and { 1, 0.5, 0.4 } or { 0.6, 1, 0.6 }
    centred(self.notice.text, h - 160, { c[1], c[2], c[3], math.min(1, self.notice.t * 2) })
  end
  love.graphics.setColor(1, 1, 1)
end

--- The hire menu, over every HUD piece (the core's `drawScreen`).
function ParkBums:drawScreen(client)
  if not self.open then
    return
  end
  local rows = targets(client)
  local panel, boxes = menuLayout(rows)
  UI.panel(panel.x, panel.y, panel.w, panel.h)
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0.85, 0.68, 0.45)
  love.graphics.printf("HIRE A BUM", panel.x, panel.y + 14, panel.w, "center")
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.85, 0.85, 0.9)
  love.graphics.printf(("%s up front. He'll find them, beat them bloody and tell them what he thinks of them.")
    :format(price()), panel.x + 20, panel.y + 50, panel.w - 40, "center")
  local mx, my = love.mouse.getPosition()
  local money = Features.byName.money
  local afford = not money or money:canAfford(client, Bums.PRICE)
  for i, b in ipairs(boxes) do
    local row = rows[i]
    local hover = mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h
    love.graphics.setColor(1, 1, 1, hover and 0.14 or 0.06)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6)
    love.graphics.setColor(row.bot and { 0.6, 0.6, 0.65 } or { 1, 0.4, 0.3 })
    love.graphics.rectangle("fill", b.x, b.y + 6, 4, b.h - 12, 2)
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1, afford and 1 or 0.5)
    local y = b.y + math.floor((b.h - UI.fonts.body:getHeight()) / 2)
    love.graphics.print(i .. "   " .. row.name, b.x + 14, y)
    if row.bot then
      love.graphics.setFont(UI.fonts.small)
      love.graphics.setColor(0.6, 0.6, 0.65)
      love.graphics.printf("bot", b.x, b.y + math.floor((b.h - UI.fonts.small:getHeight()) / 2), b.w - 12, "right")
    end
  end
  love.graphics.setFont(UI.fonts.small)
  if #rows == 0 then
    love.graphics.setColor(0.7, 0.7, 0.75)
    love.graphics.printf("There's nobody else here to set him on.", panel.x, panel.y + HEAD_H + 8, panel.w, "center")
  end
  local foot = self.notice and self.notice.text
    or ("number or click: pick   %s / Esc: close"):format(Controls.name(Controls.bindings("bum")[1]))
  love.graphics.setColor(self.notice and self.notice.kind == "no" and { 1, 0.5, 0.4 } or { 0.6, 0.6, 0.65 })
  love.graphics.printf(foot, panel.x + 10, panel.y + panel.h - 26, panel.w - 20, "center")
  local vision = Features.byName.vision
  if vision then
    vision:drawCursor(client) -- over the menu, not under it
  end
  love.graphics.setColor(1, 1, 1)
end

return ParkBums
