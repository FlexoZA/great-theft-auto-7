-- Shoeman on the comms: his portrait and his words typed out at the usual
-- panel spot (10, 250), one line at a time off a queue (docs/tutorial.md,
-- "Systems"). The look is borderline/hud.lua's `drawComms`; the queue is
-- borderline/tale.lua's.
--
-- The host raises a beat (a key of Story.beats) and every screen says the
-- same lines. `Comms.serverBeat` raises one once per level (the lessons);
-- with `again` it may come any number of times (mockery, the shout). A
-- beat that is only shouting cuts in at once (`Comms.queue`). The
-- level's "start" beat comes by itself a moment after the level begins.
--
-- Messages
--   server -> all  TUT_SAY <key>   say beat <key> (one of Story.beats)

local Protocol = require("src.net.protocol")
local Controls = require("src.controls")
local UI = require("src.ui")
local Story = require("src.features.tutorial.story")
local ShoemanFace = require("src.features.tutorial.shoeman_face")

local Comms = {}

Comms.START_AFTER = 1.5 -- seconds after a level begins its "start" beat comes
Comms.TYPE_RATE = 40 -- characters a second the words type out at
Comms.SAY_HOLD = 3.5 -- seconds a line stays up once it is all typed out
Comms.SHOUT_HOLD = 1.2 -- ...and a shouted one
Comms.QUEUE_MAX = 12 -- lines waiting at most; a repeatable beat past it is dropped

-- Server --------------------------------------------------------------------

local sv = nil -- { quest, said = { [key] = true }, startIn } while a level is on

--- Level `questId` began: forget what the last one said, and say its
--- "start" beat shortly.
function Comms.serverStart(questId)
  sv = { quest = questId, said = {}, startIn = Comms.START_AFTER }
end

function Comms.serverStop()
  sv = nil
end

--- Say beat "<level>.<what>" on every screen: once per level, or with
--- `again` each time it is asked for. Does nothing when there is no such beat.
function Comms.serverBeat(server, what, again)
  local key = sv and (sv.quest .. "." .. what)
  if not key or not Story.beats[key] or (sv.said[key] and not again) then
    return
  end
  sv.said[key] = true
  server:broadcast(Protocol.encode("TUT_SAY", key))
end

function Comms.serverStep(server, dt)
  if sv and sv.startIn then
    sv.startIn = sv.startIn - dt
    if sv.startIn <= 0 then
      sv.startIn = nil
      Comms.serverBeat(server, "start")
    end
  end
end

-- Client --------------------------------------------------------------------

local face = nil
local cl = {
  says = {}, -- lines still to say, in order: { text, shout, t (how far in, for a line cut short) }
  say = nil, -- { text, shout, t } being said
}

function Comms.clear()
  cl.says, cl.say = {}, nil
end

--- The keys for `{name}` in a line: the first key bound to control `name`,
--- or the four walking keys for `{move}`.
local function keysFor(name)
  if name == "move" then
    local keys = {}
    for i, c in ipairs({ "accelerate", "left", "brake", "right" }) do
      keys[i] = Controls.name(Controls.bindings(c)[1])
    end
    return table.concat(keys, " ")
  end
  if not Controls.byKey[name] then
    return nil -- not a control: leave the braces as they are
  end
  return Controls.name(Controls.bindings(name)[1])
end

--- A line of Story.beats as it is shown: its text with the player's keys
--- in, and whether he shouts it.
function Comms.line(line)
  local text = type(line) == "table" and line[1] or line
  text = text:gsub("{([%w%-]+)}", keysFor)
  return text, type(line) == "table" and line.shout == true
end

--- How much of `text` is typed `t` seconds in.
function Comms.typed(text, t)
  return text:sub(1, math.max(0, math.floor(t * Comms.TYPE_RATE)))
end

--- How long a line stays on the comms, typing and held.
function Comms.sayFor(text, shout)
  return #text / Comms.TYPE_RATE + (shout and Comms.SHOUT_HOLD or Comms.SAY_HOLD)
end

--- Is every line of `lines` shouted? Such a beat (the "DODGE!!!!" before
--- a throw) cuts in at once: a warning heard late is no warning.
local function allShouted(lines)
  for _, line in ipairs(lines) do
    if not (type(line) == "table" and line.shout) then
      return false
    end
  end
  return true
end

--- Queue beat `key`'s lines. A repeatable beat that finds the queue full
--- is dropped rather than pile up behind the lesson. A beat that is all
--- shouting cuts in instead: it is said now, and the line it interrupted
--- carries on from where it was afterwards.
function Comms.queue(key)
  local lines = Story.beats[key]
  if not lines then
    return
  end
  if allShouted(lines) then
    if cl.say and not cl.say.shout then
      table.insert(cl.says, 1, cl.say)
    end
    cl.say = nil
    for i = #lines, 1, -1 do
      local text = Comms.line(lines[i])
      table.insert(cl.says, 1, { text = text, shout = true })
    end
    return
  end
  if #cl.says >= Comms.QUEUE_MAX then
    return
  end
  for _, line in ipairs(lines) do
    local text, shout = Comms.line(line)
    cl.says[#cl.says + 1] = { text = text, shout = shout }
  end
end

--- Is anything being said or waiting to be?
function Comms.busy()
  return cl.say ~= nil or #cl.says > 0
end

function Comms.update(dt)
  if not face then
    if not Comms.busy() then
      return
    end
    face = ShoemanFace.new()
  end
  face:update(dt)
  if cl.say then
    cl.say.t = cl.say.t + dt
    if cl.say.t >= Comms.sayFor(cl.say.text, cl.say.shout) then
      cl.say = nil
    end
  end
  if not cl.say and #cl.says > 0 then
    local nextLine = table.remove(cl.says, 1)
    cl.say = { text = nextLine.text, shout = nextLine.shout, t = nextLine.t or 0 } -- t: a line cut short goes on
  end
  face.shouting = cl.say ~= nil and cl.say.shout
  face.talking = cl.say ~= nil and #Comms.typed(cl.say.text, cl.say.t) < #cl.say.text
end

local PANEL_X, PANEL_Y, PANEL_W = 10, 250, 470
local INK = { 0.06, 0.06, 0.07 }
local BG = { 0.14, 0.15, 0.17 }
local SHOUT = { 1.00, 0.42, 0.36 } -- the name and the words while he shouts

--- The comms panel: his portrait, his name and the line typed out.
function Comms.drawHUD()
  local say = cl.say
  if not (say and face) then
    return
  end
  local a = math.min(1, (Comms.sayFor(say.text, say.shout) - say.t) / 0.5)
  local font = say.shout and UI.fonts.heading or UI.fonts.small
  local textX = PANEL_X + ShoemanFace.W + 22
  local textW = PANEL_W - (textX - PANEL_X) - 12
  local _, lines = font:getWrap(say.text, textW)
  local ph = math.max(ShoemanFace.H + 16, #lines * font:getHeight() + 40)
  local color = say.shout and SHOUT or Story.speaker.color
  love.graphics.setColor(INK[1], INK[2], INK[3], 0.9 * a)
  love.graphics.rectangle("fill", PANEL_X - 3, PANEL_Y - 3, PANEL_W + 6, ph + 6, 6)
  love.graphics.setColor(BG[1], BG[2], BG[3], 0.92 * a)
  love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, ph, 4)
  love.graphics.setColor(color[1], color[2], color[3], a)
  love.graphics.rectangle("fill", PANEL_X, PANEL_Y, 4, ph)
  face:draw(PANEL_X + 10 + ShoemanFace.W / 2, PANEL_Y + 8 + ShoemanFace.H / 2, 1)
  love.graphics.setColor(color[1], color[2], color[3], a)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.print(Story.speaker.name, textX, PANEL_Y + 8)
  if say.shout then
    love.graphics.setColor(SHOUT[1], SHOUT[2], SHOUT[3], a)
  else
    love.graphics.setColor(0.95, 0.95, 0.92, a)
  end
  love.graphics.setFont(font)
  love.graphics.printf(Comms.typed(say.text, say.t), textX, PANEL_Y + 28, textW, "left")
  love.graphics.setColor(1, 1, 1)
end

Comms.clientMessages = {
  TUT_SAY = function(_client, args)
    Comms.queue(args[1] or "")
  end,
}

return Comms
