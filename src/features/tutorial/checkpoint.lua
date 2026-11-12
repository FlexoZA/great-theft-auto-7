-- Each tutorial level's checkpoint: where a player who dies on it comes
-- back, on foot, facing the way on. Shown on the ground as a lit flag the
-- whole level, so nobody wonders where they will land.
--
-- The tutorial feature answers weapons' `serverRespawnPoint` with
-- `Checkpoint.spot` while a level is being played, ahead of respawn-points
-- and the garage (its priority is under theirs). A level without an entry
-- leaves the respawn to them. On the town (levels 4 and 5) the checkpoint
-- is the hospital's door, as it is in the city for anyone without a
-- garage: `hospital = true`, the door asked of `garage:hospital()`, the
-- entry's own spot only if there is none.

local Features = require("src.features")
local UI = require("src.ui")

local Checkpoint = {}

-- World px, on each map's start (city-map's `map.cx, map.cy`, between the
-- two rows of spawns; Shoeman's Road's in its school yard, the park's at
-- the bottom of its lawn, the scrap yard's on its pad in the bottom-left
-- corner, the town's at the hospital's door, (0, 320) the road under it).
Checkpoint.SPOTS = {
  ["tutorial-1"] = { x = 0, y = 768 },
  ["tutorial-2"] = { x = 0, y = 768 },
  ["tutorial-3"] = { x = -896, y = 896 },
  ["tutorial-4"] = { x = 0, y = 320, hospital = true },
  ["tutorial-5"] = { x = 0, y = 320, hospital = true },
}

-- Tuning ------------------------------------------------------------------
Checkpoint.radius = 34 -- px, the ring on the ground
Checkpoint.spread = 36 -- px between players coming back at once (five side by side)

local SLOTS = { 0, 1, -1, 2, -2 } -- by player id: the host in the middle, the rest either side

--- Where level `questId`'s checkpoint stands: x, y and the way people
--- coming back face (up the map; out of the door, down, at a hospital), or
--- nil when the level has none.
local function place(questId)
  local at = questId and Checkpoint.SPOTS[questId]
  if not at then
    return nil
  end
  local garage = at.hospital and Features.byName.garage
  local h = garage and garage.hospital and garage:hospital()
  if h then
    return h.doorX, h.doorY, math.pi / 2
  end
  return at.x, at.y, -math.pi / 2
end

--- Where player `player` comes back on level `questId`: { x, y, angle },
--- a fresh table (weapons keeps it), or nil when the level has none.
--- Players stand side by side by id, so two deaths at once do not overlap.
function Checkpoint.spot(questId, player)
  local x, y, angle = place(questId)
  if not x then
    return nil
  end
  local slot = SLOTS[((tonumber(player.id) or 1) - 1) % #SLOTS + 1]
  return { x = x + slot * Checkpoint.spread, y = y, angle = angle }
end

--- The checkpoint of level `questId` on the ground: a green ring and flag,
--- like a found respawn point, labelled. `time` drives the pulse.
function Checkpoint.draw(questId, time)
  local x, y = place(questId)
  if not x then
    return
  end
  local r = Checkpoint.radius
  love.graphics.setColor(0.35, 1, 0.55, 0.16 + 0.08 * math.sin(time * 3))
  love.graphics.circle("fill", x, y, r)
  love.graphics.setColor(0.35, 1, 0.55, 0.9)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", x, y, r)
  love.graphics.setLineWidth(2)
  love.graphics.line(x, y + 8, x, y - 26) -- the pole
  love.graphics.polygon("fill", x, y - 26, x + 18, y - 20, x, y - 14) -- the flag
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf("CHECKPOINT", x - 59, y + r + 5, 120, "center")
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.printf("CHECKPOINT", x - 60, y + r + 4, 120, "center")
  love.graphics.setColor(1, 1, 1)
end

return Checkpoint
