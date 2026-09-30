-- Bigfoot and the squirrels, drawn from above. The alien hunt draws them in
-- the forest and the events feature when Bigfoot comes to town, so both
-- look the same. Everything takes what to draw and the clock; nothing here
-- keeps state.

local Body = require("src.body")

local Render = {}

Render.FUR = { 0.42, 0.28, 0.16 }
Render.FUR_DARK = { 0.28, 0.18, 0.10 }
-- Bigfoot as the core's person, in fur from head to (big, bare) feet.
local FOOT_LOOK = {
  shirt = Render.FUR, pants = Render.FUR_DARK, skin = { 0.36, 0.26, 0.22 }, hair = Render.FUR_DARK,
  shoes = { 0.22, 0.15, 0.1 }, shadow = false, -- his own, which stays on the ground when he leaps
}
local SQUIRREL = { 0.55, 0.36, 0.22 }
local SQUIRREL_LIGHT = { 0.72, 0.52, 0.34 }

--- A small health bar centred on x, its top at y.
function Render.bar(x, y, w, frac)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - w / 2 - 1, y, w + 2, 6)
  love.graphics.setColor(1 - frac, frac, 0.2)
  love.graphics.rectangle("fill", x - w / 2, y + 1, w * frac, 4)
end

--- A squirrel from above: a small body, a head out front and a huge bushy
--- tail curling behind, twitching. `s` is { dx, dy, angle, hp, bob };
--- a bar shows under it once `hp` is below `maxHp`.
function Render.squirrel(s, time, maxHp)
  local x, y = s.dx, s.dy
  local fx, fy = math.cos(s.angle), math.sin(s.angle)
  local flick = math.sin(time * 12 + (s.bob or 0)) * 0.5
  local ta = s.angle + math.pi + flick
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, 5, 8)
  love.graphics.setColor(SQUIRREL_LIGHT)
  love.graphics.ellipse("fill", x + math.cos(ta) * 8, y + math.sin(ta) * 8, 6, 6)
  love.graphics.setColor(SQUIRREL)
  love.graphics.circle("fill", x + math.cos(ta) * 11 + math.cos(ta + 1.4) * 3,
    y + math.sin(ta) * 11 + math.sin(ta + 1.4) * 3, 4, 8)
  love.graphics.ellipse("fill", x, y, 5, 5)
  love.graphics.circle("fill", x + fx * 5, y + fy * 5, 3, 8)
  love.graphics.setColor(0, 0, 0)
  love.graphics.circle("fill", x + fx * 6.5 - fy * 1.5, y + fy * 6.5 + fx * 1.5, 0.8, 4)
  love.graphics.circle("fill", x + fx * 6.5 + fy * 1.5, y + fy * 6.5 - fx * 1.5, 0.8, 4)
  if maxHp and s.hp and s.hp < maxHp then
    Render.bar(x, y + 9, 16, math.max(0, s.hp / maxHp))
  end
end

--- Bigfoot from above: a big shaggy body, long arms, a head sunk into the
--- shoulders. He squashes down to crouch, swells up in the air (his shadow
--- stays on the ground), and an arm swings out on a swipe. `f` is { dx, dy,
--- angle, hp, mode, swipe, bob }, `leap` { fx, fy, tx, ty, t, total } while
--- he is in the air (or nil), `r` his radius.
function Render.foot(f, leap, time, maxHp, r)
  local x, y = f.dx, f.dy
  local lift, scale = 0, 1
  if leap and f.mode == "air" then
    local k = math.min(1, leap.t / leap.total)
    x, y = leap.fx + (leap.tx - leap.fx) * k, leap.fy + (leap.ty - leap.fy) * k
    lift = math.sin(k * math.pi) * 90
    scale = 1 + math.sin(k * math.pi) * 0.45
  elseif f.mode == "crouch" then
    scale = 0.88
  end
  -- His shadow stays on the ground, shrinking as he goes up.
  love.graphics.setColor(0, 0, 0, 0.35 - lift / 400)
  love.graphics.circle("fill", x + 5, y + 5, r * (1 - lift / 300), 20)
  y = y - lift
  local walking = f.mode == "walk"
  local swing = math.sin(time * (walking and 9 or 3) + f.bob) * (walking and 1.4 or 0.5)
  -- The core's person (src/body.lua) his size, in fur, then what makes him
  -- Bigfoot over it: a shaggy fringe, a leathery face, red eyes.
  local k = r * scale / Body.SHOULDERS
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(k)
  FOOT_LOOK.punch = f.swipe
  Body.person(0, 0, f.angle, swing, FOOT_LOOK)
  love.graphics.rotate(f.angle)
  love.graphics.setColor(Render.FUR_DARK)
  for i = 0, 13 do -- tufts all round the shoulders
    local a = i / 14 * math.pi * 2
    love.graphics.ellipse("fill", math.cos(a) * 4.3, math.sin(a) * 8.3, 1.1, 1.3, 6)
  end
  love.graphics.setColor(0.36, 0.26, 0.22)
  love.graphics.ellipse("fill", 3, 0, 1.6, 2.6, 10) -- the face, under the fur
  love.graphics.setColor(0.85, 0.12, 0.08)
  love.graphics.circle("fill", 3.6, -1.1, 0.55, 6) -- red eyes
  love.graphics.circle("fill", 3.6, 1.1, 0.45, 6)
  love.graphics.pop()
  local bw = 60
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - bw / 2 - 1, y - r - 16, bw + 2, 6)
  local frac = math.max(0, f.hp / maxHp)
  love.graphics.setColor(1 - frac, frac, 0.2)
  love.graphics.rectangle("fill", x - bw / 2, y - r - 15, bw * frac, 4)
end

--- Where Bigfoot is about to come down: a ring on the ground, filling as
--- he falls. `leap` is { tx, ty, t, total, r }.
function Render.landing(leap, time)
  local k = math.min(1, leap.t / leap.total)
  local pulse = 0.5 + 0.5 * math.sin(time * 14)
  love.graphics.setColor(0.95, 0.35, 0.15, 0.12 + 0.08 * pulse)
  love.graphics.circle("fill", leap.tx, leap.ty, leap.r, 48)
  love.graphics.setColor(0.95, 0.35, 0.15, 0.35)
  love.graphics.circle("fill", leap.tx, leap.ty, leap.r * k, 48)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 0.5, 0.25, 0.6 + 0.4 * pulse)
  love.graphics.circle("line", leap.tx, leap.ty, leap.r, 48)
  love.graphics.setLineWidth(1)
end

--- A slam that just landed: dust rings spreading out. `ring` is
--- { x, y, r, t } with `t` counting up to 0.8.
function Render.slamRing(ring)
  local k = ring.t / 0.8
  love.graphics.setLineWidth(4)
  for i = 0, 2 do
    local kk = k - i * 0.15
    if kk > 0 and kk < 1 then
      love.graphics.setColor(0.65, 0.50, 0.32, (1 - kk) * 0.9)
      love.graphics.circle("line", ring.x, ring.y, ring.r * (0.2 + 0.9 * kk), 48)
    end
  end
  love.graphics.setLineWidth(1)
end

--- Where Bigfoot went down: a heap of fur on a dark patch.
function Render.stain(s)
  love.graphics.setColor(0.35, 0.06, 0.06, 0.8)
  love.graphics.ellipse("fill", s.x, s.y, 40, 30)
  love.graphics.setColor(Render.FUR_DARK)
  love.graphics.ellipse("fill", s.x, s.y, 26, 18)
  love.graphics.setColor(Render.FUR)
  for k = 0, 5 do
    local a = s.angle + k
    love.graphics.circle("fill", s.x + math.cos(a) * 14, s.y + math.sin(a) * 10, 7)
  end
end

return Render
