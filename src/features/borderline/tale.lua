-- The Borderline story as it plays (docs/borderline.md, "The story, beat
-- by beat"): what story.lua says, when, on every screen. init.lua passes
-- its hooks on to this module.
--
-- On the host, once each per level, the beats (Story.beats): "start" a
-- moment after arriving, a zone's when somebody first walks into it, "fight"
-- the first time the army spots anyone, "end" when the way on is reached.
-- Between them, chatter (Story.chatter): Max taunting now and then,
-- crowing when a player goes down, promising a bigger one when one of his
-- bigger robots does; Yappy cheering a kill now and then, and fussing over
-- the fallen.
--
-- On every screen: Max's intro screen on arriving (quests' `introLine`
-- picks his line; any key takes it down), then the map's banner; the name
-- of each part of the map walked into; the comms, Max's or Yappy's
-- portrait and their words typed out, one line at a time off a queue; and
-- the objective line.
--
-- Messages
--   server -> all  BRL_BEAT <key>                   a story beat (one of Story.beats)
--   server -> all  BRL_CHAT <who> <category> <index> a line of Story.chatter[who][category]

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Story = require("src.features.borderline.story")
local Terminals = require("src.features.terminals")
local Hold = require("src.features.borderline.hold")
local Wilbur = require("src.features.borderline.wilbur")
local Hud = require("src.features.borderline.hud")
local Faces = require("src.features.borderline.faces")

local Tale = {}

Tale.START_AFTER = 1.5 -- seconds after arriving the "start" beat comes
Tale.TAUNT_EVERY = { 35, 60 } -- seconds between Max's taunts
Tale.KILL_EVERY = 15 -- seconds at least between remarks on a kill
Tale.DOWN_EVERY = 10 -- ...and on a player going down
Tale.CHEER = 0.15 -- the chance Yappy cheers a small kill
Tale.INTRO_TIME = 9 -- seconds Max's screen stays up if nobody presses a key
-- Max notices these going down.
Tale.BIG = { RPG = true, PLZ = true, JET = true, DZR = true, ARC = true, BAD = true, DCK = true, STK = true }

local random = love.math.random

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

local function zoneAt(map, y)
  for _, z in ipairs(map and map.zones or {}) do
    if y >= z.y0 and y < z.y1 then
      return z
    end
  end
  return nil
end

-- Server --------------------------------------------------------------------

local sv = nil -- { map, beats, startIn, tauntIn, killAt, downAt, time }

function Tale.serverStart(map)
  sv = { map = map and map.name, beats = {}, startIn = Tale.START_AFTER, tauntIn = between(Tale.TAUNT_EVERY),
    killAt = -math.huge, downAt = -math.huge, time = 0 }
end

function Tale.serverStop()
  sv = nil
end

--- Raise beat "<map>.<what>" if there is one and this level hasn't had it.
function Tale.serverBeat(server, what)
  local key = sv and (sv.map .. "." .. what)
  if not key or not Story.beats[key] or sv.beats[key] then
    return
  end
  sv.beats[key] = true
  server:broadcast(Protocol.encode("BRL_BEAT", key))
end

local function chat(server, who, category)
  local lines = Story.chatter[who][category]
  server:broadcast(Protocol.encode("BRL_CHAT", who, category, random(#lines)))
end

--- A line of `who`'s chatter in `category`, picked now (hold.lua's fretting).
function Tale.serverChat(server, who, category)
  if sv then
    chat(server, who, category)
  end
end

function Tale.serverStep(server, map, alerted, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  if sv.startIn then
    sv.startIn = sv.startIn - dt
    if sv.startIn <= 0 then
      sv.startIn = nil
      Tale.serverBeat(server, "start")
    end
    return -- nothing else before it
  end
  if alerted then
    Tale.serverBeat(server, "fight")
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local _, y = Features.bodyPose(server, p)
      local z = zoneAt(map, y)
      if z then
        Tale.serverBeat(server, z.name)
      end
    end
  end
  sv.tauntIn = sv.tauntIn - dt
  if sv.tauntIn <= 0 then
    sv.tauntIn = between(Tale.TAUNT_EVERY)
    chat(server, "max", "taunt")
  end
end

--- The `serverKill` event: a robot down, or a player.
function Tale.serverKill(server, kill)
  if not sv then
    return
  end
  if kill.kind == "robot" and sv.time - sv.killAt >= Tale.KILL_EVERY then
    if Tale.BIG[kill.what] then
      sv.killAt = sv.time
      chat(server, "max", "kill")
    elseif random() < Tale.CHEER then
      sv.killAt = sv.time
      chat(server, "yappy", "win")
    end
  elseif kill.victim and kill.onFoot and sv.time - sv.downAt >= Tale.DOWN_EVERY then
    sv.downAt = sv.time
    chat(server, random() < 0.5 and "max" or "yappy", "down")
  end
end

-- Client --------------------------------------------------------------------

local faces = nil -- { max, yappy }
local clock = 0
local cl = {
  level = nil, -- the map name of the level on, while one is
  page = nil, -- { line, t } while Max's intro screen is up
  banner = nil, -- { spec, t }
  zone = nil, -- { name, t }
  myZone = false, -- the name of the part I am in; false until the first look
  says = {}, -- { who, text } still to say, in order
  say = nil, -- { who, text, t } being said
}

function Tale.clear()
  cl.level, cl.page, cl.banner, cl.zone, cl.myZone, cl.says, cl.say = nil, nil, nil, nil, false, {}, nil
end

--- Everyone arrived on one of the maps: Max's screen, then the banner.
function Tale.questStarted(quest)
  faces = faces or { max = Faces.new("max"), yappy = Faces.new("yappy") }
  Tale.clear()
  cl.level = quest.map
  if quest.introLine then
    cl.page = { line = Story.lines[quest.introLine] or Story.lines[1], t = 0 }
  end
  local b = Story.banners[quest.map]
  if b then
    cl.banner = { spec = b, t = 0 }
  end
end

--- Is the level on this screen the map in play?
local function onLevel(map)
  return cl.level ~= nil and map ~= nil and map.name == cl.level
end

function Tale.update(dt, map, y)
  clock = clock + dt
  if not (faces and onLevel(map)) then
    return
  end
  faces.max:update(dt)
  faces.yappy:update(dt)
  if cl.page then
    cl.page.t = cl.page.t + dt
    if cl.page.t >= Tale.INTRO_TIME then
      cl.page = nil
    end
    return -- the rest waits for his screen to go
  end
  for _, k in ipairs({ "banner", "zone" }) do
    local b = cl[k]
    if b then
      b.t = b.t + dt
      if b.t >= (k == "banner" and Hud.BANNER_TIME or Hud.ZONE_TIME) then
        cl[k] = nil
      end
    end
  end
  if cl.say then
    cl.say.t = cl.say.t + dt
    if cl.say.t >= Hud.sayFor(cl.say.text) then
      cl.say = nil
    end
  elseif #cl.says > 0 then
    local nextLine = table.remove(cl.says, 1)
    cl.say = { who = nextLine[1], text = nextLine[2], t = 0 }
  end
  -- A new part of the map puts its name up (not the first: the banner says where I am).
  if y then
    local z = zoneAt(map, y)
    local name = z and z.name or nil
    if cl.myZone ~= false and name and name ~= cl.myZone and not cl.banner then
      cl.zone = { name = name, t = 0 }
    end
    if name or cl.myZone == false then
      cl.myZone = name
    end
  end
end

--- Any key takes Max's screen down. Returns true when it did.
function Tale.keypressed()
  if cl.page then
    cl.page = nil
    return true
  end
  return false
end

--- Is this screen on one of the line's levels, the map in play?
function Tale.onLevel(map)
  return onLevel(map)
end

function Tale.blurring(map)
  return cl.page ~= nil and onLevel(map)
end

--- `done`: the level is finished. (x, y): where I am.
function Tale.drawHUD(map, done, x, y)
  if not (faces and onLevel(map)) then
    return
  end
  if cl.page then
    return -- his screen covers it all (`drawScreen`)
  end
  local state = { done = done }
  state.waiting, state.nearest = Terminals.nearestWaiting(x, y)
  state.held, state.on = Hold.shown()
  state.boss, state.bossX, state.bossY = Wilbur.objective(map)
  local text, tx, ty = Story.objective(cl.level, map, state)
  if text then
    Hud.drawObjective(text, tx and x and math.sqrt((x - tx) ^ 2 + (y - ty) ^ 2) or nil)
  end
  if not done and Story.hold[cl.level] then
    Hold.drawHUD(Story.hold[cl.level].bar)
  end
  Wilbur.drawHUD()
  if cl.say then
    local left = Hud.sayFor(cl.say.text) - cl.say.t
    Hud.drawComms(faces[cl.say.who], cl.say.who, cl.say.text, cl.say.t, math.min(1, left / 0.5))
  end
  if cl.banner then
    Hud.drawBanner(cl.banner.spec, cl.banner.t)
  elseif cl.zone then
    Hud.drawZone(cl.zone.name, cl.zone.t)
  end
end

--- Max's intro screen, over the whole HUD.
function Tale.drawScreen(map)
  if cl.page and faces and onLevel(map) then
    Hud.drawScreen(faces.max, cl.page.line, cl.page.t, clock)
  end
end

Tale.clientMessages = {
  BRL_BEAT = function(_client, args)
    for _, line in ipairs(Story.beats[args[1] or ""] or {}) do
      cl.says[#cl.says + 1] = line
    end
  end,
  BRL_CHAT = function(_client, args)
    local who = Story.chatter[args[1] or ""] and args[1]
    local lines = who and Story.chatter[who][args[2] or ""]
    local text = lines and lines[tonumber(args[3]) or 0]
    if text and #cl.says < 3 then -- (chatter never piles up behind the story)
      cl.says[#cl.says + 1] = { who, text }
    end
  end,
}

return Tale
