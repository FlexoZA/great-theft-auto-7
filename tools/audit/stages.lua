-- How the audit gets each quest to its fight. Many enemies only come out
-- later in a quest (the Major at the flag, Bigfoot after the trail, the
-- Antlion Guard once the beach is clear), so after a quest starts the
-- audit tours it: it puts the player (who can't die in the audit) on each
-- spot below, plays a few seconds there, and lists the enemies again.
--
-- Every quest gets the generic tour: the spots its map names (the boss's,
-- a flag, a finale). A quest whose fight needs more than walking there gets
-- an entry in `Stages.byQuest`: a function that is given the game and a
-- `visit(x, y, seconds)` and drives it on. A new quest whose enemies never
-- show up in the audit wants one here; the report says which.

local Stages = { byQuest = {} }

local SECONDS = 3 -- played at each spot

--- The spots a map marks that are worth standing on.
function Stages.spots(map)
  local spots = {}
  local function add(x, y)
    if type(x) == "number" and type(y) == "number" then
      spots[#spots + 1] = { x = x, y = y }
    end
  end
  add(map.flagX, map.flagY)
  if type(map.finale) == "table" then
    add(map.finale.x, map.finale.y)
  end
  add(map.bossX, map.bossY)
  if type(map.lair) == "table" then
    add(map.lair.x, map.lair.y)
  end
  return spots
end

-- Whispering Pines: the wild man walks the trail and the fight comes at
-- its end. Walk with him (stay at his side) until Bigfoot is out.
Stages.byQuest["alien-hunt"] = function(game, visit)
  local Hunt = require("src.features.alien-hunt")
  for _ = 1, 40 do
    local sv = Hunt.server and Hunt.server()
    if not sv or sv.stage == "fight" or sv.stage == "done" then
      return
    end
    local man = sv.man
    if man then
      visit(man.x + 30, man.y, 1)
    else
      game:run(1)
    end
  end
end

--- Tour quest `id` on `game`: its own script if it has one, then the
--- generic spots. `visit(x, y, seconds)` is the audit's.
function Stages.tour(game, id, visit)
  local script = Stages.byQuest[id]
  if script then
    script(game, visit)
  end
  local map = game:map()
  for _, spot in ipairs(map and Stages.spots(map) or {}) do
    visit(spot.x, spot.y, SECONDS)
  end
end

return Stages
