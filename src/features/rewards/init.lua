-- Rewards: the screen that tells you you've unlocked something (Volt's
-- electric grenade, the grenades feature's GRN_UNLOCK, so far). Client only:
-- whatever unlocked it on the host tells the player, and the player's own
-- feature puts the card up here with `show`.
--
--   rewards:show({
--     kicker = "UNLOCKED", title = "ELECTRIC GRENADE", color = { r, g, b },
--     icon = function(cx, cy, scale) ... end, -- its picture, drawn about 22 px tall at scale 1
--     lines = { "what it does", ... },
--   })
--
-- A full-screen card over everything (`drawScreen`): the world dimmed
-- behind it, rays turning in the reward's colour, its picture big in the
-- middle and what it does under it. The game keeps running behind it; while
-- it is up it has the mouse and the keys (`pointerTaken`, `menuOpen`), and
-- Enter or a click puts it away once it has been up a moment. More than one
-- waits its turn.

local Controls = require("src.controls")
local UI = require("src.ui")

local Rewards = {
  name = "rewards",
  priority = 990, -- over the HUD
}

Rewards.minTime = 0.8 -- seconds a card stays before it can be put away (no clicking past it by accident)

local queue = {} -- cards waiting, the first one up
local t = 0 -- seconds the first has been up

--- Put a reward card up (after any already waiting).
function Rewards:show(spec)
  queue[#queue + 1] = spec
  if #queue == 1 then
    t = 0
  end
end

function Rewards:enterGame()
  queue, t = {}, 0
end

function Rewards:exitGame()
  queue, t = {}, 0
end

function Rewards:menuOpen()
  return queue[1] ~= nil
end

function Rewards:pointerTaken()
  return queue[1] ~= nil
end

function Rewards:update(dt)
  if queue[1] then
    t = t + dt
  end
end

local function dismiss()
  if queue[1] and t >= Rewards.minTime then
    table.remove(queue, 1)
    t = 0
  end
end

function Rewards:keypressed(key)
  if queue[1] and (key == "return" or key == "kpenter" or Controls.is("quest-accept", key)) then
    dismiss()
  end
end

function Rewards:mousepressed()
  dismiss()
end

function Rewards:drawScreen()
  local spec = queue[1]
  if not spec then
    return
  end
  local w, h = love.graphics.getDimensions()
  local c = spec.color or { 1, 0.85, 0.3 }
  local appear = math.min(1, t / 0.35)
  love.graphics.setColor(0.02, 0.03, 0.04, 0.82 * appear)
  love.graphics.rectangle("fill", 0, 0, w, h)
  -- Rays turning behind the picture.
  local cx, cy = w / 2, h * 0.42
  local rays, reach = 14, math.max(w, h)
  for i = 0, rays - 1 do
    local a = t * 0.25 + i * 2 * math.pi / rays
    love.graphics.setColor(c[1], c[2], c[3], 0.07 * appear)
    love.graphics.polygon("fill", cx, cy, cx + math.cos(a - 0.09) * reach, cy + math.sin(a - 0.09) * reach,
      cx + math.cos(a + 0.09) * reach, cy + math.sin(a + 0.09) * reach)
  end
  local pulse = 0.5 + 0.5 * math.sin(t * 3)
  love.graphics.setColor(c[1], c[2], c[3], (0.18 + 0.1 * pulse) * appear)
  love.graphics.circle("fill", cx, cy, 90 + 8 * pulse, 64)
  love.graphics.setColor(0.05, 0.06, 0.08, 0.9 * appear)
  love.graphics.circle("fill", cx, cy, 74, 64)
  UI.ring(cx, cy, 74, 1, { c[1], c[2], c[3], appear }, 4)
  if spec.icon then
    local pop = 1 + 0.25 * math.max(0, 1 - t / 0.4) -- it lands with a little bounce
    spec.icon(cx, cy + 4, 4 * pop)
  end
  -- The words.
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(c[1], c[2], c[3], appear)
  love.graphics.printf(spec.kicker or "UNLOCKED", 0, cy - 150, w, "center")
  love.graphics.setFont(UI.fonts.title)
  love.graphics.setColor(0, 0, 0, 0.6 * appear)
  love.graphics.printf(spec.title or "", 2, cy + 104, w, "center")
  love.graphics.setColor(1, 1, 1, appear)
  love.graphics.printf(spec.title or "", 0, cy + 102, w, "center")
  love.graphics.setFont(UI.fonts.body)
  local y = cy + 104 + (UI.fonts.title):getHeight() + 14
  for _, line in ipairs(spec.lines or {}) do
    love.graphics.setColor(0.85, 0.88, 0.92, appear)
    love.graphics.printf(line, 0, y, w, "center")
    y = y + UI.fonts.body:getHeight() + 2
  end
  if t >= Rewards.minTime then
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.45 + 0.35 * pulse)
    love.graphics.printf("Enter or click to carry on", 0, h - 60, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

return Rewards
