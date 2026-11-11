-- Each tutorial level's checkpoint: where a player who dies on it comes
-- back, on foot, facing the way on. Shown on the ground as a lit flag the
-- whole level, so nobody wonders where they will land.
--
-- The tutorial feature answers weapons' `serverRespawnPoint` with
-- `Checkpoint.spot` while a level is being played, ahead of respawn-points
-- and the garage (its priority is under theirs). A level without an entry
-- leaves the respawn to them: level 4 will use the town's hospital
-- (stage 7).

local UI = require("src.ui")

local Checkpoint = {}

-- World px, on each map's start (city-map's `map.cx, map.cy`, between the
-- two rows of spawns; Shoeman's Road's in its school yard). Stages 5 to 7
-- move the rest with their maps.
Checkpoint.SPOTS = {
  ["tutorial-1"] = { x = 0, y = 768 },
  ["tutorial-2"] = { x = 0, y = -64 },
  ["tutorial-3"] = { x = 0, y = 64 },
  ["tutorial-4"] = { x = 0, y = 64 },
  ["tutorial-5"] = { x = 0, y = 64 },
}

-- Tuning ------------------------------------------------------------------
Checkpoint.radius = 34 -- px, the ring on the ground
Checkpoint.spread = 36 -- px between players coming back at once (five side by side)

local SLOTS = { 0, 1, -1, 2, -2 } -- by player id: the host in the middle, the rest either side

--- Where player `player` comes back on level `questId`: { x, y, angle },
--- a fresh table (weapons keeps it), or nil when the level has none.
--- Players stand side by side by id, so two deaths at once do not overlap.
function Checkpoint.spot(questId, player)
  local at = Checkpoint.SPOTS[questId]
  if not at then
    return nil
  end
  local slot = SLOTS[((tonumber(player.id) or 1) - 1) % #SLOTS + 1]
  return { x = at.x + slot * Checkpoint.spread, y = at.y, angle = -math.pi / 2 }
end

--- The checkpoint of level `questId` on the ground: a green ring and flag,
--- like a found respawn point, labelled. `time` drives the pulse.
function Checkpoint.draw(questId, time)
  local at = questId and Checkpoint.SPOTS[questId]
  if not at then
    return
  end
  local x, y, r = at.x, at.y, Checkpoint.radius
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
