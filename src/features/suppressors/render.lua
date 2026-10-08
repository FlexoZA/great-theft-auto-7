-- A Suppressor drawn from above: a Combine soldier a size up, in heavy
-- black plate with an ammo drum on his back, one orange visor slit across
-- his mask, and a minigun at his hip fed by a belt from the drum. Its six
-- barrels turn as fast as the gun does (the host's spin), with a flash at
-- the end while it fires. Around him his shield: a faint blue skin that
-- lights up where a round lands on it and is gone while it is down.

local Body = require("src.body")

local Render = {}

Render.SIZE = 1.3 -- times a soldier's figure
Render.RADIUS = 12 -- px: how fat he is against walls and rounds
Render.SHIELD = { 0.35, 0.75, 1.0 }
Render.VISOR = { 1.0, 0.55, 0.15 }
Render.VISOR_ALERT = { 1.0, 0.2, 0.1 }

-- Heavy plate over dark fatigues; Body.person's look (and the corpses').
Render.LOOK = {
  shirt = { 0.16, 0.17, 0.19 }, pants = { 0.11, 0.12, 0.13 }, skin = { 0.09, 0.09, 0.1 },
  hood = { 0.12, 0.13, 0.15 }, shoes = { 0.05, 0.05, 0.05 }, vest = { 0.27, 0.29, 0.32 },
  pack = { 0.22, 0.24, 0.20 }, gun = true, gunLength = 0,
  mask = true, visor = true, minigun = true, size = Render.SIZE, -- the corpses feature reads these
}

local function set(c, a, k)
  k = k or 1
  love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k, a or 1)
end

--- The minigun in his figure's own frame (facing +x, before the size up):
--- the housing at his right hip, six barrels round `turn` radians, a flash.
function Render.minigun(turn, flash, alpha)
  alpha = alpha or 1
  local cy = 5 -- it hangs at his right hip, clear of his visor
  -- The belt from the drum on his back round to the housing.
  set({ 0.55, 0.45, 0.2 }, alpha)
  love.graphics.setLineWidth(1.4)
  love.graphics.line(-5.5, 3.5, -1.5, 8, 3, 8.5, 5, cy + 1.5)
  -- The housing.
  set({ 0.2, 0.21, 0.23 }, alpha)
  love.graphics.rectangle("fill", 4.5, cy - 2.6, 6.5, 5.2, 1)
  set({ 0.4, 0.42, 0.46 }, alpha)
  love.graphics.setLineWidth(0.7)
  love.graphics.rectangle("line", 4.5, cy - 2.6, 6.5, 5.2, 1)
  -- The barrels: six round the spindle, the ones turned away darker.
  love.graphics.setLineWidth(1.1)
  for k = 0, 5 do
    local a = turn + k * math.pi / 3
    local off = math.cos(a) * 1.6
    set(math.sin(a) > 0 and { 0.42, 0.44, 0.48 } or { 0.12, 0.12, 0.14 }, alpha)
    love.graphics.line(11, cy + off, 20.5, cy + off)
  end
  set({ 0.3, 0.31, 0.34 }, alpha)
  love.graphics.rectangle("fill", 15, cy - 2.2, 1.4, 4.4) -- the clamp round them
  love.graphics.rectangle("fill", 19.5, cy - 2.2, 1.2, 4.4) -- and the muzzle ring
  if flash then
    love.graphics.setColor(1, 0.85, 0.35, 0.9 * alpha)
    love.graphics.polygon("fill", 21, cy - 1.8, 26.5, cy, 21, cy + 1.8)
    love.graphics.setColor(1, 1, 0.7, alpha)
    love.graphics.circle("fill", 21.4, cy, 1.4, 8)
  end
  love.graphics.setLineWidth(1)
end

--- One at (x, y) facing `facing`. `o`: swing (the stride), turn (barrel
--- angle), flash, alert, hurt (0..1 white flash), shield (0..1 of full),
--- glow (0..1 a hit on the shield), venting (0..1 heat).
function Render.draw(x, y, facing, o, time)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(Render.SIZE)
  Body.person(0, 0, facing, o.swing or 0, Render.LOOK)
  love.graphics.rotate(facing)
  -- The visor: one slit across the mask, brighter when he has somebody.
  local v = o.alert and Render.VISOR_ALERT or Render.VISOR
  set(v, 0.35)
  love.graphics.setLineWidth(3)
  love.graphics.line(3.5, -2.4, 3.5, 2.4)
  set(v)
  love.graphics.setLineWidth(1.2)
  love.graphics.line(3.6, -2.2, 3.6, 2.2)
  Render.minigun(o.turn or 0, o.flash)
  if (o.venting or 0) > 0 then -- heat off the barrels while it vents
    for k = 0, 2 do
      local t = (time * 0.9 + k / 3) % 1
      love.graphics.setColor(0.8, 0.8, 0.85, 0.35 * (1 - t) * o.venting)
      love.graphics.circle("fill", 18 + t * 6, 5 - t * 9 + k, 1.5 + t * 3, 8)
    end
  end
  if (o.hurt or 0) > 0 then
    love.graphics.setColor(1, 1, 1, 0.6 * o.hurt)
    love.graphics.circle("fill", 0, 0, 9, 16)
  end
  love.graphics.pop()
  -- The shield round him, while it holds.
  local sh = o.shield or 0
  if sh > 0 then
    local r = Render.RADIUS + 7
    local glow = o.glow or 0
    local s = Render.SHIELD
    love.graphics.setColor(s[1], s[2], s[3], 0.06 + 0.06 * sh + 0.3 * glow)
    love.graphics.circle("fill", x, y, r, 28)
    love.graphics.setLineWidth(1.5)
    for k = 0, 2 do -- arcs drifting round it, the skin of the field
      local a = time * (0.8 + k * 0.3) + k * 2.1
      love.graphics.setColor(s[1], s[2], s[3], (0.25 + 0.5 * glow) * (0.4 + 0.6 * sh))
      love.graphics.arc("line", "open", x, y, r, a, a + 1.2, 10)
    end
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Sparks flying off a shield that just went down: `k` 0..1 through it.
function Render.shieldBreak(x, y, k, seed)
  local s = Render.SHIELD
  for i = 1, 10 do
    local a = seed + i * 0.63
    local d = Render.RADIUS + 6 + k * 30
    love.graphics.setColor(s[1], s[2], s[3], 0.9 * (1 - k))
    love.graphics.circle("fill", x + math.cos(a) * d, y + math.sin(a) * d, 2 * (1 - k) + 0.5, 6)
  end
  love.graphics.setColor(s[1], s[2], s[3], 0.5 * (1 - k))
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", x, y, Render.RADIUS + 7 + k * 20, 28)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Render
