-- Quests: jobs you pick up in the world. Every job starts at the Jobs
-- building in the city (jobs.lua picks it from the map): stand on the
-- square by its door, open the job board on the action key and take one of
-- the jobs listed there; the host takes everyone to the map the job is on
-- (city-map's `switchTo`). There is one world, so a quest is a group
-- outing: whoever takes the job takes the whole server with them.
--
-- Three jobs so far: one sends everyone to Crazy Karen's cul-de-sac (the
-- karen feature runs the fight), one into the forest after a wild man
-- hunting aliens (alien-hunt), and one onto a defended beach to take Major
-- Looz'er's hill (d-day). A blue star by the entrance of each brings
-- everyone home again; a star comes up when you drive or walk onto it, and
-- declined it waits until you come back. A map may have several stars; the
-- nearest one is the one on offer. Add a quest to `Quests.list` with
-- `board = true` and the board, the offer and the trip are all done here;
-- a quest marked `returns` is the way back and ends the one under way. What
-- happens on the quest is another feature's business: this one raises
-- `questStarted(client, quest, byId)` / `questEnded(client, quest)` on every
-- machine and `serverQuestStarted(server, quest, player)` /
-- `serverQuestEnded(server, quest)` on the host, and a feature that finishes
-- the job calls `quests:serverComplete(server, questId, x, y)`.
--
-- A boss that goes down far from the way in leaves a way out: pass where it
-- fell to `serverComplete` and an EXIT star comes up right there, taking
-- everyone home the same as the blue star by the entrance.
--
-- The host decides: it checks the taker's body is on the star (or at the
-- Jobs building's door for a job on the board), that the star is on the
-- map in play and that the destination exists, then switches the map and
-- tells everyone. Clients only draw the stars and the board, and ask.
--
-- Messages
--   client -> server  QST_ACCEPT <questId>
--   server -> all     QST_MAP    <mapName>              (play on this map from now on; before QST_START)
--   server -> all     QST_START  <questId> <playerId>   (who took the job)
--   server -> all     QST_DONE   <questId>              (the job is done)
--   server -> all     QST_EXIT   <x> <y>                (an EXIT star home stands here, on the map in play)
--   server -> player  QST_NO     <reason>               (away | gone)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Jobs = require("src.features.quests.jobs")

local Quests = {
  name = "quests",
  priority = 22, -- star over the map (20), under real-estate (25); QST_MAP reaches a joiner before RE_EXPAND
}

-- Quests -------------------------------------------------------------------
-- `board = true` puts a job on the Jobs building's board in the default
-- city; otherwise `onMap` is the map its star sits on and (x, y) where.
-- `map` is where accepting takes everyone. Every name is a key of
-- city-map's `maps`.
-- `returns` marks the trip home: taking it ends the quest under way instead
-- of starting one. `label` and `color` dress the star; `banner` is what
-- everyone reads when the trip happens (%s is the taker's name). `boss`
-- names the feature that owns the fight there (karen listens for its own).
Quests.list = {
  {
    id = "karen",
    title = "Crazy Karen is at it again, let's end this",
    text = "She's out on her street again, screaming at the neighbourhood. "
      .. "Get everyone over there and shut her up for good.",
    board = true,
    map = "culdesac",
    boss = "karen",
    label = "KAREN",
    banner = "%s took the job. Welcome to Karen's Cul-de-sac.",
  },
  {
    id = "alien-hunt",
    title = "The truth is out there (in the woods)",
    text = "A wild-eyed man with half his lunch down his shirt is waving you over. He swears aliens are "
      .. "harvesting human hair to eat, and he knows where they land. Follow him into the forest.",
    board = true,
    map = "forest",
    boss = "alien-hunt",
    label = "ALIENS?",
    color = { 0.55, 1, 0.45 },
    banner = "%s followed the wild man. Welcome to Whispering Pines.",
  },
  {
    id = "d-day",
    title = "D-Day landing",
    text = "Major Looz'er has dug in on the hill above the beach and will not stop talking about it. "
      .. "Wade ashore, keep your head down between the tank stoppers, get past the bunkers and take his flag.",
    board = true,
    map = "beach",
    boss = "d-day",
    label = "D-DAY",
    color = { 0.78, 0.82, 0.45 },
    banner = "%s hit the beach. Welcome to Looz'er Beach.",
  },
  {
    id = "home",
    title = "Back to the City",
    text = "Done here. Call it a day and take everyone back into town.",
    onMap = "culdesac",
    x = 0, -- the entrance of the street
    y = 800,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-forest",
    title = "Back to the City",
    text = "Enough trees for one day. Take everyone back into town.",
    onMap = "forest",
    x = 0, -- the entrance of the trail, between the parked cars
    y = 1164, -- city-map puts the forest entrance (map.cx, map.cy) here
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-beach",
    title = "Back to the City",
    text = "Back in the boat. Take everyone back into town.",
    onMap = "beach",
    x = 0, -- in the surf between the landing craft
    y = 1676, -- city-map puts the beach's way in (map.cx, map.cy) here
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
}
Quests.byId = {}
Quests.board = {} -- the jobs on the Jobs building's board, in list order
for _, q in ipairs(Quests.list) do
  Quests.byId[q.id] = q
  if q.board then
    Quests.board[#Quests.board + 1] = q
  end
end

-- Tuning ------------------------------------------------------------------
Quests.starRadius = 60 -- px from the star that brings the offer up
Quests.leaveRadius = 140 -- px from the star that takes it down again (and forgets a decline)
Quests.starSize = 30 -- px, outer radius of the star
Quests.doorRadius = 60 -- px from the Jobs building's door that lets the board open

local SLACK = 60 -- px the host allows for a taker drawn a little behind where it is
local NOTICE_TIME = 2.5 -- seconds a refusal stays on the offer
local BANNER_TIME = 4 -- seconds the "took the job" banner stays up
local PANEL_W = 560
local REASONS = {
  away = "Get back to the star (or the Jobs door) to take it.",
  gone = "That job is off the table.",
}

local function cityMap()
  return Features.byName["city-map"]
end

--- The EXIT star a fallen boss leaves on map `onMap` at (x, y): the way
--- home, the same as the blue star by the entrance.
local function exitQuest(onMap, x, y)
  local city = cityMap()
  return {
    id = "exit",
    title = "Get out of here",
    text = "The boss is down. Head home and leave this place behind.",
    onMap = onMap,
    x = x,
    y = y,
    map = city and city.DEFAULT or "city",
    returns = true,
    label = "EXIT",
    color = { 0.45, 1, 0.75 },
    banner = "%s found the way out. Welcome back to The City.",
  }
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The Jobs building (jobs.lua) while the default city is in play.
function Quests:jobs()
  local city = cityMap()
  if not (city and city.map and city.current == city.DEFAULT) then
    return nil
  end
  return Jobs.of(city.map)
end

--- The quest whose star on map `current` is nearest to (x, y), or the
--- first one there when no position is given. `extra` is an EXIT star, if
--- one is up.
local function offeredOn(current, x, y, extra)
  local best, bestD2
  for i = 1, #Quests.list + 1 do
    local q = Quests.list[i] or extra
    if q and q.onMap == current then
      local d2 = x and dist2(x, y, q.x, q.y) or 0
      if not bestD2 or d2 < bestD2 then
        best, bestD2 = q, d2
      end
    end
  end
  return best
end

-- Client --------------------------------------------------------------------

Quests.active = nil -- id of the quest everyone is on, from the host
Quests.done = nil -- id of a quest finished on this trip (the star home is still the way back)
Quests.prompt = nil -- the quest whose offer is up
Quests.exit = nil -- the EXIT star a fallen boss left, from the host
Quests.atJobs = false -- standing on the square by the Jobs building's door
Quests.boardOpen = false -- the job board is up
Quests.pick = 1 -- the job picked on the board (an index of `Quests.board`)
local declined = nil -- quest id turned down; forgotten once you leave its star
local seenMap = nil -- the map the last frame was on, to notice arriving on another
local notice, noticeTimer = nil, 0
local banner, bannerTimer = nil, 0
local time = 0

function Quests:load()
  Controls.register("quest-accept", "Accept a quest (offer up)", "return")
  Controls.register("quest-decline", "Decline a quest (offer up)", "backspace")
  Controls.register("jobs", "Open / close the job board (at the Jobs building)", "f") -- the action key, like the shop's
end

-- QST_MAP and QST_START for a quest under way arrive in the same burst as
-- START, so the quest is only forgotten on the way out.
function Quests:exitGame()
  self.active, self.done, self.prompt, self.exit, declined, seenMap = nil, nil, nil, nil, nil, nil
  self.atJobs, self.boardOpen, self.pick = false, false, 1
  notice, noticeTimer, banner, bannerTimer = nil, 0, nil, 0
end

--- The `pointerTaken` convention: the mouse is ours while the board is up.
function Quests:pointerTaken()
  return self.boardOpen
end

--- The `closeMenu` convention: Esc takes the board down.
function Quests:closeMenu()
  if not self.boardOpen then
    return false
  end
  self.boardOpen = false
  return true
end

--- The `actionTaken` convention: the action key is ours at the Jobs door
--- and while the board is up, so on-foot leaves the cars alone.
function Quests:actionTaken()
  return self.boardOpen or self.atJobs
end

--- Ask the host for job `quest` (the offer or the board stays up until it
--- answers).
local function accept(client, quest)
  client:send(Protocol.encode("QST_ACCEPT", quest.id))
end

--- The quest whose star on the map I am on is nearest (x, y), if any.
function Quests:offered(x, y)
  local city = cityMap()
  return city and offeredOn(city.current, x, y, self.exit) or nil
end

function Quests:update(dt, client)
  time = time + dt
  noticeTimer = math.max(0, noticeTimer - dt)
  bannerTimer = math.max(0, bannerTimer - dt)
  local x, y = client:myPose()
  local jobs = x and self:jobs()
  local jd2 = jobs and dist2(x, y, jobs.doorX, jobs.doorY) or math.huge
  self.atJobs = jd2 <= self.doorRadius ^ 2
  if self.boardOpen and jd2 > self.leaveRadius ^ 2 then
    self.boardOpen = false -- walked off: the board goes down
  end
  local quest = self:offered(x, y)
  local city = cityMap()
  if x and city and city.current ~= seenMap and (seenMap or city.current ~= city.DEFAULT) then
    -- Just arrived (or joined a game out on a quest map): the cars land
    -- beside this map's star, and nobody wants the trip straight back. It
    -- counts as declined until you drive off.
    self.prompt, declined = nil, quest and quest.id or nil
  end
  if x then
    seenMap = city and city.current or nil -- not before we are placed: a latecomer may not be yet
  end
  if not (quest and x) then
    self.prompt, declined = nil, nil
    return
  end
  local d2 = dist2(x, y, quest.x, quest.y)
  if d2 > self.leaveRadius ^ 2 then
    self.prompt, declined = nil, nil -- drove off: the offer goes down and a no is forgotten
  elseif d2 <= self.starRadius ^ 2 and not self.prompt and declined ~= quest.id then
    self.prompt, notice, noticeTimer = quest, nil, 0
  end
end

function Quests:keypressed(key, client)
  if self.boardOpen then
    if Controls.is("jobs", key) or Controls.is("quest-decline", key) then
      self.boardOpen = false
    elseif Controls.is("quest-accept", key) and self.board[self.pick] then
      accept(client, self.board[self.pick])
    end
    return
  end
  if self.atJobs and Controls.is("jobs", key) then
    self.boardOpen, self.pick, notice, noticeTimer = true, 1, nil, 0
    return
  end
  local quest = self.prompt
  if not quest then
    return
  end
  if Controls.is("quest-accept", key) then
    accept(client, quest)
  elseif Controls.is("quest-decline", key) then
    declined, self.prompt = quest.id, nil
  end
end

--- Another screen over ours that has the mouse (the inventory draws on top
--- and takes the clicks meant for it).
local function covered()
  local inventory = Features.byName.inventory
  return inventory and inventory.open or false
end

--- Pick a job on the board, take it, or leave.
function Quests:mousepressed(x, y, button, client)
  if not self.boardOpen or button ~= 1 or covered() then
    return
  end
  local L = Jobs.layout(self.board, self.pick)
  for i, r in ipairs(L.rows) do
    if Jobs.inside(r, x, y) then
      self.pick = i
      return
    end
  end
  if Jobs.inside(L.accept, x, y) and self.board[self.pick] then
    accept(client, self.board[self.pick])
  elseif Jobs.inside(L.close, x, y) then
    self.boardOpen = false
  end
end

--- The world softens under the offer and the board.
function Quests:worldBlur()
  return (self.prompt or self.boardOpen) and 0.7 or 0
end

--- The ten corners of a five-point star, outer radius R, point up.
local function starPoints(cx, cy, R)
  local pts = {}
  for k = 0, 9 do
    local a = -math.pi / 2 + k * math.pi / 5
    local r = k % 2 == 0 and R or R * 0.42
    pts[#pts + 1] = cx + math.cos(a) * r
    pts[#pts + 1] = cy + math.sin(a) * r
  end
  return pts
end

--- A filled star: five tips, each a triangle, on a pentagon. LÖVE only
--- fills convex polygons, so the concave outline is drawn in pieces.
local function fillStar(cx, cy, R)
  local p = starPoints(cx, cy, R)
  local function at(j)
    j = j % 10
    return p[2 * j + 1], p[2 * j + 2]
  end
  local pentagon = {}
  for k = 0, 4 do
    local ox, oy = at(2 * k)
    local ax, ay = at(2 * k - 1)
    local bx, by = at(2 * k + 1)
    love.graphics.polygon("fill", ox, oy, ax, ay, bx, by)
    pentagon[#pentagon + 1], pentagon[#pentagon + 2] = bx, by
  end
  love.graphics.polygon("fill", pentagon)
  return p
end

--- The stars on the road: a soft glow the size of the trigger, the star
--- itself breathing slowly, and its name underneath.
function Quests:drawBelowCars()
  local city = cityMap()
  for _, quest in ipairs(self.list) do
    if city and quest.onMap == city.current then
      self:drawStar(quest)
    end
  end
  if city and self.exit and self.exit.onMap == city.current then
    self:drawStar(self.exit)
  end
  local jobs = self:jobs()
  if jobs then
    Jobs.drawBuilding(jobs, fillStar, self.doorRadius, self.atJobs, time)
  end
end

--- The Jobs building on the minimap: a gold star, so it can be found.
function Quests:drawOnMinimap(_client, toMap)
  local jobs = self:jobs()
  if not jobs then
    return
  end
  local x, y = toMap(jobs.x + jobs.w / 2, jobs.y + jobs.h / 2)
  love.graphics.setColor(0, 0, 0, 0.8)
  fillStar(x, y, 7)
  love.graphics.setColor(1, 0.85, 0.3)
  fillStar(x, y, 5.5)
  love.graphics.setColor(1, 1, 1)
end

function Quests:drawStar(quest)
  local pulse = 0.5 + 0.5 * math.sin(time * 2.5)
  local size = self.starSize * (0.92 + 0.08 * pulse)
  local c = quest.color or { 1, 0.85, 0.3 }
  local label = quest.label or "QUEST"
  love.graphics.setColor(c[1], c[2], c[3], 0.10 + 0.08 * pulse)
  love.graphics.circle("fill", quest.x, quest.y, self.starRadius)
  love.graphics.setColor(c[1], c[2], c[3], 0.35 + 0.25 * pulse)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", quest.x, quest.y, self.starRadius)
  love.graphics.setColor(0, 0, 0, 0.35)
  fillStar(quest.x + 4, quest.y + 4, size)
  love.graphics.setColor(c[1], c[2], c[3])
  local outline = fillStar(quest.x, quest.y, size)
  love.graphics.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
  love.graphics.setLineWidth(3)
  love.graphics.polygon("line", outline)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(label, quest.x - 59, quest.y + size + 7, 120, "center")
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.printf(label, quest.x - 60, quest.y + size + 6, 120, "center")
  love.graphics.setColor(1, 1, 1)
end

--- The offer: what the job is, and the keys to take it or leave it.
local function drawPrompt(quest)
  local w, h = love.graphics.getDimensions()
  local inner = PANEL_W - 48
  local _, lines = UI.fonts.body:getWrap(quest.text, inner)
  local textH = #lines * UI.fonts.body:getHeight()
  local _, titleLines = UI.fonts.heading:getWrap(quest.title, inner)
  local titleH = #titleLines * UI.fonts.heading:getHeight()
  local ph = 24 + UI.fonts.small:getHeight() + 8 + titleH + 14 + textH + 44 + 26
  local px, py = math.floor((w - PANEL_W) / 2), math.floor((h - ph) / 2)

  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.10, 0.10, 0.13, 0.96)
  love.graphics.rectangle("fill", px, py, PANEL_W, ph, 10)
  love.graphics.setColor(1, 0.85, 0.3, 0.8)
  love.graphics.rectangle("line", px, py, PANEL_W, ph, 10)

  local y = py + 24
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.printf("QUEST", px, y, PANEL_W, "center")
  y = y + UI.fonts.small:getHeight() + 8
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(quest.title, px + 24, y, inner, "center")
  y = y + titleH + 14
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0.85, 0.85, 0.88)
  love.graphics.printf(quest.text, px + 24, y, inner, "center")
  y = y + textH + 14

  love.graphics.setFont(UI.fonts.small)
  if noticeTimer > 0 then
    love.graphics.setColor(1, 0.45, 0.4, math.min(1, noticeTimer * 2))
    love.graphics.printf(notice, px, y, PANEL_W, "center")
  end
  y = y + 30
  local yes = Controls.name(Controls.bindings("quest-accept")[1])
  local no = Controls.name(Controls.bindings("quest-decline")[1])
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.printf(yes .. ": accept   " .. no .. ": decline", px, y, PANEL_W, "center")
  love.graphics.setColor(1, 1, 1)
end

function Quests:drawHUD(client)
  local w = love.graphics.getWidth()
  if self.active then
    local quest = self.byId[self.active]
    local city = cityMap()
    local where = city and city.map.title
    love.graphics.setFont(UI.fonts.small)
    local label = "Quest: " .. (quest and quest.title or self.active)
    if self.done == self.active then
      love.graphics.setColor(0.5, 1, 0.6)
      label = "Quest complete: " .. (quest and quest.title or self.active)
    else
      love.graphics.setColor(1, 0.85, 0.3)
    end
    if where then
      label = label .. "  (" .. where .. ")"
    end
    love.graphics.print(label, 10, 190)
  end
  if bannerTimer > 0 and banner then
    local a = math.min(1, bannerTimer * 2)
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.6 * a)
    love.graphics.printf(banner.title, 1, 111, w, "center")
    love.graphics.setColor(1, 0.85, 0.3, a)
    love.graphics.printf(banner.title, 0, 110, w, "center")
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0, 0, 0, 0.6 * a)
    love.graphics.printf(banner.text, 1, 145, w, "center")
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.printf(banner.text, 0, 144, w, "center")
  end
  if self.prompt and client then
    drawPrompt(self.prompt)
  end
  if self.boardOpen and client then
    local city = cityMap()
    local places = {}
    for _, q in ipairs(self.board) do
      places[q.id] = city and city.maps[q.map] and city.maps[q.map].title or q.map
    end
    local yes = Controls.name(Controls.bindings("quest-accept")[1])
    local no = Controls.name(Controls.bindings("jobs")[1])
    local shown = noticeTimer > 0 and { text = notice, alpha = math.min(1, noticeTimer * 2) } or nil
    Jobs.drawBoard(Jobs.layout(self.board, self.pick), self.pick, places, shown, { yes, no })
    local vision = Features.byName.vision
    if vision then
      vision:drawCursor(client) -- over the board, not under it
    end
  elseif self.atJobs and client then
    -- On the square with the board down: the offer, where the shop's stands.
    local h = love.graphics.getHeight()
    local text = "Jobs.  " .. Controls.name(Controls.bindings("jobs")[1]) .. ": open the job board"
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf(text, 1, h - 129, w, "center")
    love.graphics.setColor(1, 0.85, 0.3)
    love.graphics.printf(text, 0, h - 130, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

Quests.clientMessages = {
  QST_MAP = function(_client, args)
    local city = cityMap()
    if city and city.maps[args[1] or ""] then
      city:switchTo(args[1]) -- does nothing on the host's own client: the server already switched
    end
  end,
  QST_START = function(client, args)
    local quest, by = Quests.byId[args[1] or ""], tonumber(args[2])
    if args[1] == "exit" then
      quest = Quests.exit
    end
    if not quest then
      return
    end
    Quests.exit = nil -- any trip leaves the fallen boss's star behind
    local ended = Quests.active and Quests.byId[Quests.active]
    Quests.active = not quest.returns and quest.id or nil
    Quests.done = nil
    Quests.boardOpen = false
    Quests.prompt = nil -- `declined` is left alone: update sets it for the star we land next to
    local taker = client:nameOf(by) -- they may have left since (a latecomer hears this too)
    local city = cityMap()
    local where = city and city.maps[quest.map] and city.maps[quest.map].title or quest.map
    local text = quest.banner or ("%s took the job. Welcome to " .. where .. ".")
    banner = { title = quest.title:upper(), text = text:format(taker or "Someone") }
    bannerTimer = BANNER_TIME
    if quest.returns then
      if ended then
        Features.call("questEnded", client, ended)
      end
    else
      Features.call("questStarted", client, quest, by)
    end
  end,
  QST_DONE = function(_client, args)
    local quest = Quests.byId[args[1] or ""]
    if quest then
      Quests.done = quest.id
      banner = { title = "JOB DONE", text = quest.title }
      bannerTimer = BANNER_TIME
    end
  end,
  QST_EXIT = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    local city = cityMap()
    if x and y and city then
      Quests.exit = exitQuest(city.current, x, y)
    end
  end,
  QST_NO = function(_client, args)
    notice = REASONS[args[1]]
    noticeTimer = notice and NOTICE_TIME or 0
  end,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { active = quest id or nil, by = player id, done = quest id or nil, exit = EXIT star or nil }

-- City-map (lower priority) has put the default map back by now.
function Quests:serverStart()
  sv = { active = nil, by = nil, done = nil }
end

--- The job under way is finished (the karen feature says so when she goes
--- down). Everyone hears it; the star home is still the way back. Given
--- where the boss fell (x, y), an EXIT star home comes up there too.
function Quests:serverComplete(server, questId, x, y)
  if not (sv and sv.active == questId) then
    return false
  end
  sv.done = questId
  server:broadcast(Protocol.encode("QST_DONE", questId))
  local city = cityMap()
  if x and y and city then
    sv.exit = exitQuest(city.current, x, y)
    server:broadcast(Protocol.encode("QST_EXIT", ("%.1f"):format(x), ("%.1f"):format(y)))
  end
  return true
end

--- The quest under way on the host, for other features; nil between jobs.
function Quests:serverActive()
  return sv and sv.active and self.byId[sv.active] or nil
end

--- Anyone joining mid-game hears which map is in play and what job is on,
--- before real-estate (higher priority) tells them how it has grown. A
--- human joining the lobby hears nothing: `sv` may be the last game's.
function Quests:serverPlayerJoined(server, player)
  local city = cityMap()
  if not (sv and city and server.started) or player.bot then
    return
  end
  if city.current ~= city.DEFAULT then
    server:send(player, Protocol.encode("QST_MAP", city.current))
  end
  if sv.active then
    server:send(player, Protocol.encode("QST_START", sv.active, sv.by))
  end
  if sv.done then
    server:send(player, Protocol.encode("QST_DONE", sv.done))
  end
  if sv.exit then
    server:send(player, Protocol.encode("QST_EXIT", ("%.1f"):format(sv.exit.x), ("%.1f"):format(sv.exit.y)))
  end
end

--- Is the player's body (not a wreck) on the star, or for a job on the
--- board at the Jobs building's door?
local function onStar(server, player, quest)
  if not Features.present(player) then
    return false
  end
  local x, y = Features.bodyPose(server, player)
  if quest.board then
    local jobs = Quests:jobs()
    return jobs ~= nil and dist2(x, y, jobs.doorX, jobs.doorY) <= (Quests.doorRadius + SLACK) ^ 2
  end
  return dist2(x, y, quest.x, quest.y) <= (Quests.starRadius + SLACK) ^ 2
end

Quests.serverMessages = {
  QST_ACCEPT = function(server, player, args)
    local quest = Quests.byId[args[1] or ""]
    if args[1] == "exit" then
      quest = sv and sv.exit
    end
    local city = cityMap()
    if not (sv and quest and city and player.body) then
      return
    end
    local reason
    local here
    if quest.board then
      here = Quests:jobs() ~= nil -- the Jobs building is only in the default city
    else
      here = quest.onMap == city.current
    end
    if not here or not city.maps[quest.map] then
      reason = "gone" -- that star is not on this map (someone else's trip already happened)
    elseif not onStar(server, player, quest) then
      reason = "away"
    else
      local ended = sv.active and Quests.byId[sv.active]
      sv.exit = nil -- any trip leaves the fallen boss's star behind
      if quest.returns then
        sv.active, sv.by, sv.done = nil, nil, nil
      else
        sv.active, sv.by, sv.done = quest.id, player.id, nil
      end
      -- QST_MAP first: whatever features send from mapChanged is about the
      -- new map, so clients must be on it by then.
      server:broadcast(Protocol.encode("QST_MAP", quest.map))
      city:switchTo(quest.map, server) -- moves every car; features hear mapChanged
      server:broadcast(Protocol.encode("QST_START", quest.id, player.id))
      if quest.returns then
        if ended then
          Features.call("serverQuestEnded", server, ended)
        end
      else
        Features.call("serverQuestStarted", server, quest, player)
      end
      return
    end
    server:send(player, Protocol.encode("QST_NO", reason))
  end,
}

--- For tests.
function Quests.server()
  return sv
end

return Quests
