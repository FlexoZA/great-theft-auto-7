-- Level 5's lesson as it happens (docs/tutorial.md, "Level 5: Build"),
-- and the rule for building anywhere in Shoeman's Town. Host only: the
-- buildings feature's `serverBuildingDone` event says what a player did
-- at their building, and this ticks the item of the section on screen it
-- answers (objectives.lua's `tutorial-5` list) and has Shoeman say the
-- next step (story.lua's `tutorial-5.<item id>` beats).
--
-- An item that asks for a building names its kind (`build = "quarry"`).
-- A building that no unticked item on screen asks for comes straight down
-- again, back to an empty lot that stays its owner's, with the
-- public-school line (`<level>.wrong`): on level 4 nothing is asked, so
-- nothing may stand.
--
--   Build.serverStart()                                   a town level began
--   Build.serverStep(dt)
--   Build.serverDone(server, player, id, what, kind, item, n)  the event, on a town level

local Features = require("src.features")
local Comms = require("src.features.tutorial.comms")
local Objectives = require("src.features.tutorial.objectives")

local Build = {}

Build.insultEvery = 6 -- seconds at least between two public-school lines

local sv = { t = 0, insultedAt = nil }

function Build.serverStart()
  sv = { t = 0, insultedAt = nil }
end

function Build.serverStep(dt)
  sv.t = sv.t + dt
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

--- A building went up: what the list asked for ticks and he says what
--- comes next; anything else is wrong.
local function built(server, id, kind)
  local item = asked(kind)
  if not (item and Objectives.serverTick(server, item.id)) then
    wrong(server, id)
    return
  end
  Comms.serverBeat(server, item.id)
end

--- What the buildings feature says `player` did at their building on plot
--- `id` (its `serverBuildingDone` event), on a town level.
function Build.serverDone(server, _player, id, what, kind)
  if what == "built" then
    built(server, id, kind)
  end
end

return Build
