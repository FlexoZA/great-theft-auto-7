-- Level 5's lesson as it happens (docs/tutorial.md, "Level 5: Build"),
-- and the rule for building anywhere in Shoeman's Town. Host only: the
-- buildings feature's `serverBuildingDone` event says what a player did
-- at their building, and this ticks the item of the section on screen it
-- answers (objectives.lua's `tutorial-5` list) and has Shoeman say the
-- next step (story.lua's `tutorial-5.<item id>` beats).
--
-- An item that asks for a building names its kind (`build = "quarry"`);
-- one that asks for a building set to make something names both (`kind =
-- "quarry", makes = "iron"`), and ticks when one goes up making it or is
-- set to it; `collect = item` ticks when someone collects that from a
-- building; `load = kind, items = { ... }` when every one of those
-- materials has gone into a building of that kind, in one load or several.
-- As each step ticks he says the item's beat, or the section's
-- (`beat`) when it was the last.
-- A building that no unticked item on screen asks for comes straight down
-- again, back to an empty lot that stays its owner's, with the
-- public-school line (`<level>.wrong`): on level 4 nothing is asked, so
-- nothing may stand.
--
-- The section with `dent` (repair): he throws a shoe at the nearest
-- building (shoe.lua, `serverThrowAt`, a dent of DENT), and once one is
-- damaged an item with `repair = true` ticks on a repair.
--
--   Build.serverStart(x, y)                               a level began, Shoeman at (x, y)
--   Build.serverStep(server, dt)
--   Build.serverDone(server, player, id, what, kind, item, n)  the event, on a town level

local Features = require("src.features")
local Comms = require("src.features.tutorial.comms")
local Objectives = require("src.features.tutorial.objectives")
local Shoe = require("src.features.tutorial.shoe")

local Build = {}

Build.insultEvery = 6 -- seconds at least between two public-school lines
Build.throwAfter = 2 -- seconds after the repair section comes up before he throws
Build.retryAfter = 3 -- seconds after a shoe that dented nothing before the next
Build.DENT = 300 -- hit points his shoe takes off a building (the weakest, a quarry, has 600)

-- t: seconds into the level; insultedAt: when the last public-school line
-- was said; loaded: kind -> material -> true, what anyone has put in a
-- building of that kind this level; x, y: where Shoeman stands; throwIn:
-- seconds to his next throw at a building, thrown: a throw went out since,
-- tried: plot id -> true for the buildings thrown at, dented: a shoe left
-- a building damaged (the repair may tick).
local sv = { t = 0, loaded = {}, tried = {} }

--- A town level began, with Shoeman standing at (x, y).
function Build.serverStart(x, y)
  sv = { t = 0, loaded = {}, tried = {}, x = x, y = y }
end

--- The standing building that shoes have dented, or nil.
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

--- The section with `dent` (level 5's repair) is up: he puts a shoe
--- through the nearest building, and again at the next one while no shoe
--- of his has left a dent (one stopped short on a hospital wall, a
--- passing car). Once one has, he says so and the repair may tick.
local function dent(server, dt)
  if sv.dented or Shoe.serverBusy() then
    return
  end
  local standing = Features.byName.buildings:serverStanding()
  if sv.thrown and damaged(standing) then
    sv.dented = true
    Comms.serverBeat(server, "dent")
    return
  end
  sv.throwIn = (sv.throwIn or Build.throwAfter) - dt
  local b = sv.throwIn <= 0 and sv.x and nearest(standing)
  if not b then
    return
  end
  sv.throwIn, sv.thrown, sv.tried[b.id] = Build.retryAfter, true, true
  Shoe.serverThrowAt(server, sv.x, sv.y, b.x + b.w / 2, b.y + b.h / 2, Build.DENT)
  Comms.serverBeat(server, "throw", true)
end

function Build.serverStep(server, dt)
  sv.t = sv.t + dt
  local section = Objectives.serverSection()
  if section and section.dent then
    dent(server, dt)
  end
end

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
  for _, item in ipairs(section.items) do
    if not Objectives.serverTicked(item.id) then
      Comms.serverBeat(server, ticked[#ticked])
      return
    end
  end
  Comms.serverBeat(server, section.beat or ticked[#ticked])
end

--- Items that ask for a `kind` set to make `item` (`kind`, `makes`).
local function setsTo(kind, item)
  return function(it)
    return it.kind == kind and it.makes == item
  end
end

--- Items that ask for `item` collected (`collect`).
local function collects(item)
  return function(it)
    return it.collect == item
  end
end

--- Items that ask for every one of `items` loaded into a `load` building,
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

--- What the buildings feature says `player` did at their building on plot
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
    tickWhere(server, collects(item), ticked)
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

return Build
