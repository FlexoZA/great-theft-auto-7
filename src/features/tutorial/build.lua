-- Level 5's lesson as it happens (docs/tutorial.md, "Level 5: Build"),
-- and the rule for building anywhere in Shoeman's Town. Host only: the
-- buildings feature's `serverBuildingDone` event and the shop's
-- `serverBought` and `serverSold` say what a player did, and this ticks the
-- item of the section on screen it answers (objectives.lua's `tutorial-5`
-- list) and has Shoeman say the next step (story.lua's `tutorial-5.*`).
--
-- What an item asks for:
--   build = kind            a building of that kind goes up
--   kind, makes = item      a building of `kind` goes up making `item`, or is set to it
--   collect = item          someone collects that from a building
--   load = kind, items      every one of `items` has gone into a building of
--                           `kind` this level, in one load or several
--   repair = true           someone repairs a building after his shoe dented one
--   buy = item              someone buys that at the shop (a hire)
--   sell = prefix           someone sells the shop an item whose name starts so
--   dented = true           (with one of those) needs a damaged building: see `dent`
-- As each step ticks he says the item's beat, or the section's (`beat`)
-- when it was the last.
--
-- A building that no unticked item on screen asks for comes straight down
-- again, back to an empty lot that stays its owner's, with the
-- public-school line (`<level>.wrong`): on level 4 nothing is asked, so
-- nothing may stand.
--
-- A section may also have `wages = n`: every human gets n Fcks from him as
-- it comes up (the `wages` beat), for what it asks them to buy; and `dent =
-- beat`: while an unticked item of it is `dented`, he keeps a building
-- damaged, throwing a shoe at the nearest one (shoe.lua's `serverThrowAt`,
-- a dent of DENT) whenever none is, and says `beat` after the first dent.
--
--   Build.serverStart(x, y)          a level began, Shoeman at (x, y)
--   Build.serverStep(server, dt)
--   Build.serverDone(server, player, id, what, kind, item)   buildings' event, on a town level
--   Build.serverBought(server, player, item)                 the shop's, on a town level
--   Build.serverSold(server, player, item)

local Features = require("src.features")
local Comms = require("src.features.tutorial.comms")
local Objectives = require("src.features.tutorial.objectives")
local Shoe = require("src.features.tutorial.shoe").tutorial

local Build = {}

Build.insultEvery = 6 -- seconds at least between two public-school lines
Build.throwAfter = 2 -- seconds after a dent section comes up (or its dent is mended) before he throws
Build.retryAfter = 3 -- seconds after a shoe that dented nothing before the next
Build.DENT = 300 -- hit points his shoe takes off a building (the weakest, a quarry, has 600)

-- t: seconds into the level; insultedAt: when the last public-school line
-- was said; loaded: kind -> material -> true, what anyone has put in a
-- building of that kind this level; x, y: where Shoeman stands; section:
-- the index of the section on screen, and for it: paid (player id -> true,
-- wages handed over), throwIn (seconds to his next throw), tried (plot id
-- -> true, the buildings thrown at), dented (a shoe of his has left a
-- building damaged).
local sv = { t = 0, loaded = {} }

--- A town level began, with Shoeman standing at (x, y).
function Build.serverStart(x, y)
  sv = { t = 0, loaded = {}, x = x, y = y }
end

-- Sections ------------------------------------------------------------------

--- Is every item of `section` (on screen) that `fits(item)` ticked?
local function allTicked(section, fits)
  for _, item in ipairs(section.items) do
    if (not fits or fits(item)) and not Objectives.serverTicked(item.id) then
      return false
    end
  end
  return true
end

--- Tick every unticked item on screen that `fits(item)`; the ids that
--- ticked are added to `ticked`.
local function tickWhere(server, fits, ticked)
  local section = Objectives.serverSection()
  for _, item in ipairs(section and section.items or {}) do
    if fits(item) and Objectives.serverTick(server, item.id) then
      ticked[#ticked + 1] = item.id
    end
  end
end

--- After `ticked` items ticked, he says what comes next: the section's
--- own beat (`beat`) when it is all done, else the last item's.
local function sayNext(server, ticked)
  if #ticked == 0 then
    return
  end
  local section = Objectives.serverSection()
  Comms.serverBeat(server, allTicked(section) and section.beat or ticked[#ticked])
end

-- Wages and dents -------------------------------------------------------------

--- Every human here gets the section's wages once.
local function pay(server, wages)
  local money = Features.byName.money
  for id, player in pairs(server.players) do
    if not player.bot and not sv.paid[id] and money then
      sv.paid[id] = true
      money:give(server, id, wages)
      Comms.serverBeat(server, "wages")
    end
  end
end

--- The standing building that is short of hit points, or nil.
local function damaged(standing)
  for _, b in ipairs(standing) do
    if b.hp < b.max then
      return b
    end
  end
  return nil
end

--- The standing building nearest Shoeman not thrown at yet (all of them
--- again once each has been), or nil when none stands.
local function nearest(standing)
  local best, bestD = nil, math.huge
  for _, b in ipairs(standing) do
    local d = (b.x + b.w / 2 - sv.x) ^ 2 + (b.y + b.h / 2 - sv.y) ^ 2
    if not sv.tried[b.id] and d < bestD then
      best, bestD = b, d
    end
  end
  if not best and next(sv.tried) then
    sv.tried = {}
    return nearest(standing)
  end
  return best
end

--- A section with `dent` is up and an item of it needs a dent: while no building is
--- damaged, he puts a shoe through the nearest one, and again at the next
--- while his shoes dent nothing (one stopped short on the hospital, a
--- passing car). After the first dent he says the section's `dent` beat.
local function dent(server, dt, beat)
  if Shoe:serverBusy() then
    return
  end
  local standing = Features.byName.buildings:serverStanding()
  if damaged(standing) then
    if sv.thrown and not sv.dented then
      sv.dented = true
      Comms.serverBeat(server, beat)
    end
    sv.throwIn = nil
    return
  end
  sv.throwIn = (sv.throwIn or Build.throwAfter) - dt
  local b = sv.throwIn <= 0 and sv.x and nearest(standing)
  if not b then
    return
  end
  sv.throwIn, sv.thrown, sv.tried[b.id] = Build.retryAfter, true, true
  Shoe:serverThrowAt(server, sv.x, sv.y, b.x + b.w / 2, b.y + b.h / 2, Build.DENT)
  Comms.serverBeat(server, "throw", true)
end

function Build.serverStep(server, dt)
  sv.t = sv.t + dt
  local section, index = Objectives.serverSection()
  if not section then
    return
  end
  if sv.section ~= index then
    sv.section, sv.paid, sv.tried, sv.throwIn, sv.thrown, sv.dented = index, {}, {}, nil, false, false
  end
  if section.wages then
    pay(server, section.wages)
  end
  if section.dent and not allTicked(section, function(item)
    return item.dented
  end) then
    dent(server, dt, section.dent)
  end
end

-- What players do ---------------------------------------------------------------

--- The unticked item of the section on screen that asks for a building of
--- `kind`, or nil.
local function asked(kind)
  local section = Objectives.serverSection()
  for _, item in ipairs(section and section.items or {}) do
    if item.build == kind and not Objectives.serverTicked(item.id) then
      return item
    end
  end
  return nil
end

--- Plot `id`'s new building was not on the list: down it comes, and he
--- says why (not more often than `insultEvery`; it comes down anyway).
local function wrong(server, id)
  Features.byName.buildings:serverRemove(server, id)
  if sv.insultedAt and sv.t - sv.insultedAt < Build.insultEvery then
    return
  end
  sv.insultedAt = sv.t
  Comms.serverBeat(server, "wrong", true)
end

--- Items that ask for a `kind` set to make `item`.
local function setsTo(kind, item)
  return function(it)
    return it.kind == kind and it.makes == item
  end
end

--- Items that ask for every one of their `items` loaded into a `kind`,
--- now that `sv.loaded` has them all.
local function loadsDone(kind)
  return function(it)
    if it.load ~= kind then
      return false
    end
    for _, item in ipairs(it.items) do
      if not sv.loaded[kind][item] then
        return false
      end
    end
    return true
  end
end

--- A building went up: what the list asked for ticks (and what it makes
--- from the start, a quarry's iron), and he says what comes next; anything
--- else is wrong.
local function built(server, id, kind, item)
  local wanted = asked(kind)
  if not (wanted and Objectives.serverTick(server, wanted.id)) then
    wrong(server, id)
    return
  end
  local ticked = { wanted.id }
  tickWhere(server, setsTo(kind, item), ticked)
  sayNext(server, ticked)
end

--- What the buildings feature says a player did at their building on plot
--- `id` (its `serverBuildingDone` event), on a town level.
function Build.serverDone(server, _player, id, what, kind, item)
  if what == "built" then
    built(server, id, kind, item)
    return
  end
  local ticked = {}
  if what == "product" then
    tickWhere(server, setsTo(kind, item), ticked)
  elseif what == "collected" then
    tickWhere(server, function(it)
      return it.collect == item
    end, ticked)
  elseif what == "loaded" then
    sv.loaded[kind] = sv.loaded[kind] or {}
    sv.loaded[kind][item] = true
    tickWhere(server, loadsDone(kind), ticked)
  elseif what == "repaired" and sv.dented then
    tickWhere(server, function(it)
      return it.repair
    end, ticked)
  end
  sayNext(server, ticked)
end

--- The shop sold a player `item` (a hire), on a town level.
function Build.serverBought(server, _player, item)
  local ticked = {}
  tickWhere(server, function(it)
    return it.buy == item
  end, ticked)
  sayNext(server, ticked)
end

--- A player sold the shop `item` ("gun-pistol@rare" for a tier), on a town level.
function Build.serverSold(server, _player, item)
  local ticked = {}
  tickWhere(server, function(it)
    return it.sell ~= nil and item:sub(1, #it.sell) == it.sell
  end, ticked)
  sayNext(server, ticked)
end

return Build
