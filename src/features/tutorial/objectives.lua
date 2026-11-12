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
-- seconds to something beside it), each = true (every human in the game
-- must do it: counted per player with `serverTickPlayer`, its need the
-- number of humans, shown "(1/2)" when there is more than one; one who
-- leaves stops counting, one who joins must do it too) }. The way on stays
-- shut until every item of every section but the exit ones is ticked.
--
-- Messages
--   server -> all  TUT_OBJ <quest> <section> <counts> [<item> <seconds>]
--                  the list of level <quest> at section <section>, <counts>
--                  each item's count joined by "," ("<done>/<need>" for an
--                  `each` item); an item's timer when one is running. An
--                  empty <quest> takes the list down.

local Protocol = require("src.net.protocol")
local UI = require("src.ui")
local Waves = require("src.features.tutorial.waves")

local Objectives = {}

Objectives.NEXT_AFTER = 1.5 -- seconds a finished section stays up before the next one

-- Each level's list, in sections. Later stages add their levels' lists.
Objectives.lists = {
  ["tutorial-1"] = {
    { items = { { id = "cross", text = "Reach the other side", exit = true } } },
  },
  -- A dodge counts when the shoe thrown at a player misses them after they
  -- dodged it in the air (shoe.lua); the timer is the next throw.
  ["tutorial-2"] = {
    { items = { { id = "dodge", text = "Dodge Shoeman's shoes", need = 5, timer = true } } },
  },
  -- Everyone picks up their own pistol and equips it (gift.lua); then
  -- anyone empties a magazine and reloads (weapons' events); then three
  -- waves of six squirrels, each one shot ticking its wave (waves.lua).
  ["tutorial-3"] = {
    {
      items = {
        { id = "pickup", text = "Pick up the pistol", each = true },
        { id = "equip", text = "Equip it", each = true },
        { id = "empty", text = "Empty the magazine" },
        { id = "reload", text = "Reload" },
        { id = "wave1", text = "Defeat wave 1", need = Waves.SIZE },
        { id = "wave2", text = "Defeat wave 2", need = Waves.SIZE },
        { id = "wave3", text = "Defeat wave 3", need = Waves.SIZE },
      },
    },
  },
  -- Everyone picks up their own openborders and puts it in an ability
  -- slot (gift.lua); then anyone who has casts it (the
  -- `serverOpenBorders` event).
  ["tutorial-4"] = {
    {
      items = {
        { id = "pickup", text = "Pick up Open Borders", each = true },
        { id = "equip", text = "Equip it", each = true },
        { id = "use", text = "Use it" },
      },
    },
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

--- What item `i` needs: an `each` item's from `needs` (the humans in the
--- game), else its own.
local function needOf(item, needs, i)
  return needs and needs[i] or item.need or 1
end

--- Is every item of `section` ticked, given its `counts` (and `needs`)?
--- With `butExit` the exit items do not count.
local function finished(section, counts, butExit, needs)
  for i, item in ipairs(section.items) do
    if not (butExit and item.exit) and (counts[i] or 0) < needOf(item, needs, i) then
      return false
    end
  end
  return true
end

-- Server --------------------------------------------------------------------

-- While a level with a list is on: { quest, list, section, counts = { [i] = n },
-- nextIn (a finished section waiting to go), timer = { i, ends }, done = { [i] =
-- { [player id] = true } } and needs = { [i] = n } for `each` items }.
local sv = nil
local clock = 0 -- host seconds, for the timers

local function stateMessage()
  if not sv then
    return Protocol.encode("TUT_OBJ", "")
  end
  local section = sv.list[sv.section]
  local counts = {}
  for i, item in ipairs(section.items) do
    counts[i] = item.each and ("%d/%d"):format(sv.counts[i] or 0, needOf(item, sv.needs, i)) or (sv.counts[i] or 0)
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
  sv = list and { quest = questId, list = list, section = 1, counts = {}, done = {}, needs = {} } or nil
  if sv then
    Objectives.serverRecount(server, true)
  end
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
  if not i or section.items[i].each or have >= needOf(section.items[i]) then
    return false
  end
  sv.counts[i] = math.min(needOf(section.items[i]), have + (n or 1))
  if finished(section, sv.counts, false, sv.needs) and sv.section < #sv.list then
    sv.nextIn = Objectives.NEXT_AFTER
  end
  send(server)
  return true
end

--- The humans in the game, by id.
local function humans(server)
  local ids = {}
  for id, player in pairs(server.players) do
    if not player.bot then
      ids[id] = true
    end
  end
  return ids
end

--- Count every `each` item of the section on screen again over the humans
--- in the game now (someone joined, left, or did it). When a count or a
--- need changed, sends the list (unless `quiet`) and returns true.
function Objectives.serverRecount(server, quiet)
  if not sv or sv.nextIn then
    return false
  end
  local section = sv.list[sv.section]
  local people = humans(server)
  local changed = false
  for i, item in ipairs(section.items) do
    if item.each then
      local need, n = 0, 0
      for id in pairs(people) do
        need = need + 1
        if sv.done[i] and sv.done[i][id] then
          n = n + 1
        end
      end
      need = math.max(1, need)
      if sv.counts[i] ~= n or sv.needs[i] ~= need then
        sv.counts[i], sv.needs[i], changed = n, need, true
      end
    end
  end
  if changed and finished(section, sv.counts, false, sv.needs) and sv.section < #sv.list then
    sv.nextIn = Objectives.NEXT_AFTER
  end
  if changed and not quiet then
    send(server)
  end
  return changed
end

--- `player` did `each` item `id` of the section on screen. True when it
--- was new for them.
function Objectives.serverTickPlayer(server, id, player)
  if not sv or sv.nextIn or player.bot then
    return false
  end
  local i = indexOf(sv.list[sv.section], id)
  if not (i and sv.list[sv.section].items[i].each) then
    return false
  end
  sv.done[i] = sv.done[i] or {}
  if sv.done[i][player.id] then
    return false
  end
  sv.done[i][player.id] = true
  Objectives.serverRecount(server)
  return true
end

--- Has `player` done `each` item `id` of the section on screen?
function Objectives.serverDidPlayer(id, player)
  local i = sv and indexOf(sv.list[sv.section], id)
  return i ~= nil and sv.done[i] ~= nil and sv.done[i][player.id] == true
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

--- Every step: the `each` counts follow whoever is in the game (someone
--- left), and a finished section gives way to the next.
function Objectives.serverStep(server, dt)
  clock = clock + dt
  Objectives.serverRecount(server)
  if not (sv and sv.nextIn) then
    return
  end
  sv.nextIn = sv.nextIn - dt
  if sv.nextIn <= 0 then
    sv.section, sv.counts, sv.nextIn, sv.timer, sv.done, sv.needs = sv.section + 1, {}, nil, nil, {}, {}
    Objectives.serverRecount(server, true)
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
  return i ~= nil and (sv.counts[i] or 0) >= needOf(section.items[i], sv.needs, i)
end

--- May the way on be taken: the last section is up and everything in it
--- but the exit items is ticked? True for a level with no list.
function Objectives.serverOpen()
  if not sv then
    return true
  end
  return sv.section == #sv.list and not sv.nextIn and finished(sv.list[sv.section], sv.counts, true, sv.needs)
end

--- A newcomer must do the `each` items too: everyone hears the new count.
function Objectives.serverPlayerJoined(server, player)
  if sv and not Objectives.serverRecount(server) then
    server:send(player, stateMessage())
  end
end


-- Client --------------------------------------------------------------------

-- { quest, section, counts, needs, timer = { i, left } } as the host last sent it.
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
  return cl.section == #list and section ~= nil and finished(section, cl.counts, true, cl.needs)
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

--- An item's line: its text, its count (out of `need`, an `each` item's),
--- its timer.
function Objectives.label(item, count, timerLeft, need)
  local text = item.text
  need = need or item.need or 1
  if need > 1 then
    text = ("%s (%d/%d)"):format(text, math.min(count, need), need)
  end
  if timerLeft and count < need then
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
    local need = needOf(item, cl.needs, i)
    local done = count >= need
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
    local text = Objectives.label(item, count, timer, need)
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
    local counts, needs = {}, {}
    for n in (args[3] or ""):gmatch("[^,]+") do
      local done, need = n:match("^(%d+)/(%d+)$")
      counts[#counts + 1] = tonumber(done or n) or 0
      needs[#counts] = tonumber(need)
    end
    local ti, left = tonumber(args[4]), tonumber(args[5])
    cl = { quest = quest, section = section, counts = counts, needs = needs,
      timer = (ti and left) and { i = ti, left = left } or nil }
  end,
}

return Objectives
