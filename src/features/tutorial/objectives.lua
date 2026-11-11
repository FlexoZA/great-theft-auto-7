-- The tutorial's tick list, top left (docs/tutorial.md, "Systems"): what
-- the level asks for, a box per item, ticked as it is done. A level's list
-- comes in sections, shown one at a time; a finished section stays up a
-- moment, all ticked, then the next one replaces it. The look follows the
-- quests' one-line objective (borderline/hud.lua `drawObjective`).
--
-- The host keeps the state and sends it whole on every change, so a
-- player who joins mid-level gets the same list; clients only draw it.
--
-- An item is { id, text, need = n (a count, shown "(2/5)"), exit = true
-- (ticked by reaching the way on), timer = true (the host may show the
-- seconds to something beside it) }. The way on stays shut until every
-- item of every section but the exit ones is ticked.
--
-- Messages
--   server -> all  TUT_OBJ <quest> <section> <counts> [<item> <seconds>]
--                  the list of level <quest> at section <section>, <counts>
--                  each item's count joined by ","; an item's timer when
--                  one is running. An empty <quest> takes the list down.

local Protocol = require("src.net.protocol")
local UI = require("src.ui")

local Objectives = {}

Objectives.NEXT_AFTER = 1.5 -- seconds a finished section stays up before the next one

-- Each level's list, in sections. Later stages add their levels' lists.
Objectives.lists = {
  ["tutorial-1"] = {
    { items = { { id = "cross", text = "Reach the other side", exit = true } } },
  },
}

--- Index of item `id` in `section`, or nil.
local function indexOf(section, id)
  for i, item in ipairs(section.items) do
    if item.id == id then
      return i
    end
  end
  return nil
end

local function needOf(item)
  return item.need or 1
end

--- Is every item of `section` ticked, given its `counts`? With `butExit`
--- the exit items do not count.
local function finished(section, counts, butExit)
  for i, item in ipairs(section.items) do
    if not (butExit and item.exit) and (counts[i] or 0) < needOf(item) then
      return false
    end
  end
  return true
end

-- Server --------------------------------------------------------------------

-- While a level with a list is on: { quest, list, section, counts = { [i] = n },
-- nextIn (a finished section waiting to go), timer = { i, ends } }.
local sv = nil
local clock = 0 -- host seconds, for the timers

local function stateMessage()
  if not sv then
    return Protocol.encode("TUT_OBJ", "")
  end
  local section = sv.list[sv.section]
  local counts = {}
  for i in ipairs(section.items) do
    counts[i] = sv.counts[i] or 0
  end
  local timer = sv.timer
  if timer and timer.ends > clock then
    return Protocol.encode("TUT_OBJ", sv.quest, sv.section, table.concat(counts, ","), timer.i,
      ("%.2f"):format(timer.ends - clock))
  end
  return Protocol.encode("TUT_OBJ", sv.quest, sv.section, table.concat(counts, ","))
end

local function send(server)
  server:broadcast(stateMessage())
end

--- Level `questId` began: its list goes up at the first section (taken
--- down when the level has none).
function Objectives.serverStart(server, questId)
  local list = Objectives.lists[questId]
  sv = list and { quest = questId, list = list, section = 1, counts = {} } or nil
  send(server)
end

function Objectives.serverStop(server)
  local was = sv
  sv = nil
  if was then
    send(server)
  end
end

--- Item `id` of the section on screen done `n` more times (1 when not
--- given), capped at its need. Items of other sections are not counted:
--- returns false then, or when it was already ticked; true when it counted.
function Objectives.serverTick(server, id, n)
  if not sv or sv.nextIn then
    return false
  end
  local section = sv.list[sv.section]
  local i = indexOf(section, id)
  local have = i and (sv.counts[i] or 0)
  if not i or have >= needOf(section.items[i]) then
    return false
  end
  sv.counts[i] = math.min(needOf(section.items[i]), have + (n or 1))
  if finished(section, sv.counts) and sv.section < #sv.list then
    sv.nextIn = Objectives.NEXT_AFTER
  end
  send(server)
  return true
end

--- Show `seconds` counting down beside item `id` (the next throw); nil
--- takes it away.
function Objectives.serverTimer(server, id, seconds)
  if not sv then
    return
  end
  local i = indexOf(sv.list[sv.section], id)
  sv.timer = (i and seconds) and { i = i, ends = clock + seconds } or nil
  send(server)
end

function Objectives.serverStep(server, dt)
  clock = clock + dt
  if not (sv and sv.nextIn) then
    return
  end
  sv.nextIn = sv.nextIn - dt
  if sv.nextIn <= 0 then
    sv.section, sv.counts, sv.nextIn, sv.timer = sv.section + 1, {}, nil, nil
    send(server)
  end
end

--- The section on screen (its `items`; level 5 judges a building against
--- them) and its index; nil when no list is up.
function Objectives.serverSection()
  if not sv then
    return nil
  end
  return sv.list[sv.section], sv.section
end

--- Is item `id` of the section on screen ticked?
function Objectives.serverTicked(id)
  local section = sv and sv.list[sv.section]
  local i = section and indexOf(section, id)
  return i ~= nil and (sv.counts[i] or 0) >= needOf(section.items[i])
end

--- May the way on be taken: the last section is up and everything in it
--- but the exit items is ticked? True for a level with no list.
function Objectives.serverOpen()
  if not sv then
    return true
  end
  return sv.section == #sv.list and not sv.nextIn and finished(sv.list[sv.section], sv.counts, true)
end

function Objectives.serverPlayerJoined(server, player)
  if sv then
    server:send(player, stateMessage())
  end
end

-- Client --------------------------------------------------------------------

-- { quest, section, counts, timer = { i, left } } as the host last sent it.
local cl = nil

function Objectives.clear()
  cl = nil
end

--- Is the way on of level `quest` open, as far as this screen knows?
--- Hides the ring while it is shut. True when no list for it is up.
function Objectives.open(quest)
  local list = Objectives.lists[quest]
  if not (cl and cl.quest == quest and list) then
    return true
  end
  local section = list[cl.section]
  return cl.section == #list and section ~= nil and finished(section, cl.counts, true)
end

function Objectives.update(dt)
  local timer = cl and cl.timer
  if timer then
    timer.left = math.max(0, timer.left - dt)
  end
end

local X, Y = 10, 40 -- under the FPS counter, clear of the comms at y 250
local ROW = 18 -- seven items (level 3) end above the quests feature's line at y 197
local BOX = 12
local GOLD = { 1.00, 0.85, 0.35 } -- the header
local TICK = { 0.45, 0.95, 0.55 }

local function shadowed(text, x, y, color, a)
  love.graphics.setColor(0, 0, 0, 0.6 * a)
  love.graphics.print(text, x + 1, y + 1)
  love.graphics.setColor(color[1], color[2], color[3], a)
  love.graphics.print(text, x, y)
end

--- An item's line: its text, its count, its timer.
function Objectives.label(item, count, timerLeft)
  local text = item.text
  if item.need and item.need > 1 then
    text = ("%s (%d/%d)"):format(text, math.min(count, item.need), item.need)
  end
  if timerLeft and count < needOf(item) then
    text = ("%s  next in %d s"):format(text, math.ceil(timerLeft))
  end
  return text
end

--- The section on screen, when it belongs to the job under way.
function Objectives.drawHUD(active)
  local list = cl and cl.quest == active and Objectives.lists[cl.quest]
  local section = list and list[cl.section]
  if not section then
    return
  end
  love.graphics.setFont(UI.fonts.small)
  local header = section.title and ("OBJECTIVES %d/%d: %s"):format(cl.section, #list, section.title:upper())
    or "OBJECTIVES"
  shadowed(header, X, Y, GOLD, 1)
  local fh = UI.fonts.small:getHeight()
  for i, item in ipairs(section.items) do
    local y = Y + 4 + i * ROW
    local count = cl.counts[i] or 0
    local done = count >= needOf(item)
    local by = y + math.floor((fh - BOX) / 2)
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", X, by, BOX, BOX, 2)
    love.graphics.setLineWidth(2)
    if done then
      love.graphics.setColor(TICK)
      love.graphics.rectangle("line", X, by, BOX, BOX, 2)
      love.graphics.line(X + 2, by + BOX / 2, X + BOX / 2 - 1, by + BOX - 3, X + BOX + 2, by - 3)
    else
      love.graphics.setColor(0.92, 0.92, 0.88)
      love.graphics.rectangle("line", X, by, BOX, BOX, 2)
    end
    local timer = cl.timer and cl.timer.i == i and cl.timer.left or nil
    local text = Objectives.label(item, count, timer)
    if done then
      shadowed(text, X + BOX + 8, y, TICK, 0.75)
    else
      shadowed(text, X + BOX + 8, y, { 0.95, 0.95, 0.92 }, 1)
    end
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

Objectives.clientMessages = {
  TUT_OBJ = function(_client, args)
    local quest = args[1] or ""
    local list = Objectives.lists[quest]
    local section = tonumber(args[2])
    if not (list and section and list[section]) then
      cl = nil
      return
    end
    local counts = {}
    for n in (args[3] or ""):gmatch("[^,]+") do
      counts[#counts + 1] = tonumber(n) or 0
    end
    local ti, left = tonumber(args[4]), tonumber(args[5])
    cl = { quest = quest, section = section, counts = counts, timer = (ti and left) and { i = ti, left = left } or nil }
  end,
}

return Objectives
