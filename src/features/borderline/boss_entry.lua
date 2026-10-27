-- How a boss of the line comes in and lets the way on go (scrapper.lua,
-- smelter.lua, foreman.lua, bnk9.lua). One that waits for a lock waits
-- ("waiting") until lock `spec.after` opens (the level's goal done: the
-- terminals hacked, the last bridge lowered, the last rim cannon down),
-- then spends a few seconds coming in ("coming": building itself,
-- climbing out, rising), then stands up and fights (its own phases from
-- there). Down, it opens lock `spec.unlocks`, the level's way on (a lock of
-- the terminals feature with no terminals). `sv` is the boss's own state.

local Features = require("src.features")
local Terminals = require("src.features.terminals")

local Entry = {}

--- Coming in for `seconds` from now.
function Entry.come(sv, seconds)
  sv.phase, sv.comeIn = "coming", seconds
end

--- One step of it: `start()` the moment the lock opens (it calls
--- `Entry.come`), `stand()` once it has come in. Returns true while it is
--- still waiting or coming.
function Entry.step(sv, dt, start, stand)
  if sv.phase == "waiting" then
    if Terminals.opened(sv.spec.after) then
      start()
    end
    return true
  elseif sv.phase == "coming" then
    sv.comeIn = sv.comeIn - dt
    if sv.comeIn <= 0 then
      stand()
    end
    return true
  end
  return false
end

--- It is down (or there is no army to put it on): the way on opens.
function Entry.open(server, sv)
  Terminals.serverUnlock(server, sv.spec.unlocks)
end

--- The launch's --boss: every lock of the map in play open but the way on,
--- as though the level's goal were done.
function Entry.skip(server, sv)
  local city = Features.byName["city-map"]
  for _, l in ipairs(city and city.map and city.map.locks or {}) do
    if l.name ~= sv.spec.unlocks then
      Terminals.serverUnlock(server, l.name)
    end
  end
end

return Entry
