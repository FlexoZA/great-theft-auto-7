-- Corpses: the dead who leave a body, as every screen draws them. A body
-- lies where it fell, knocked over the way the blow that dropped it was
-- going, in one of three poses picked at random -- sprawled on its back,
-- face down, or curled on its side -- arms and legs a little different each
-- time, in the look it wore alive (Body.person's: shirt, pants, skin, hair,
-- a hat, a hood, a vest, a pack, a gun; `mask` for the Combine's masked
-- heads, whose lenses go dark; `visor` for one slit across the mask instead
-- of two lenses, `minigun` for a minigun on the ground instead of a rifle and
-- `size` for a bigger figure, the Suppressors'), the gun dropped by its hand and a pool
-- spreading under it. They lie there for `LIE` seconds and fade, `MAX` at
-- most at once, and go when the map changes. Client only: nothing is sent.
--
-- Whoever runs the dead calls `Corpses.down(x, y, angle, look, cause)` on
-- each machine when one goes down: a body for a round, a blade, a fist or
-- poison; what the damage feature leaves for the rest (a splat for a car or
-- a blast, ash for fire or a shock: Damage:deathAt), or the pedestrians'
-- gibs without it. A-Man's Combine, D-Day's soldiers, the crowd and both
-- kinds of simps (Karen's, open borders') do. `Corpses.add` lays a body
-- down whatever killed it.

local Features = require("src.features")
local Body = require("src.body")

local Corpses = {
  name = "corpses",
  priority = 55, -- under the crowd (60), pickups (70) and cars; over the map (20)
}

local LIE = 40 -- seconds one lies there
local FADE = 4 -- the last of them fading out
local MAX = 60 -- at most, the oldest go first
local POOL_TIME = 6 -- seconds the pool takes to spread
local POOL = { 0.32, 0.03, 0.05 }
local LENS_DEAD = { 0.16, 0.22, 0.27 }
local EYES_SHUT = { 0.25, 0.16, 0.12 }
-- What kills without leaving a body: the damage feature's ash, scorch and splat.
local NO_BODY = { impact = true, explosive = true, fire = true, shock = true }
local SIZE = 1.2 -- a little bigger than a standing soldier's figure: lying flat, he is all there is of him

local list = {} -- { x, y, angle, look, seed, t }

local function set(c, a, k)
  k = k or 1
  love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k, a or 1)
end

local function hash(n)
  local v = math.sin(n * 12.9898) * 43758.5453
  return v - math.floor(v)
end

function Corpses.clear()
  list = {}
end

function Corpses:enterGame()
  list = {}
end

function Corpses:exitGame()
  list = {}
end

function Corpses:mapChanged()
  list = {}
end

--- A body at (x, y), the blow that did it going `angle`, in `look` (Body.person's).
function Corpses.add(x, y, angle, look)
  -- A copy, with Body's colours where it has none: the living figure's
  -- table may change after (a pedestrian's frost, a simp's punch).
  local own = {}
  for k, v in pairs(look or {}) do
    own[k] = v
  end
  own.shirt = own.shirt or { 0.6, 0.6, 0.65 }
  own.pants = own.pants or Body.PANTS
  own.skin = own.skin or Body.SKIN
  list[#list + 1] = { x = x, y = y, angle = (angle or 0) + (love.math.random() - 0.5) * 0.6, look = own,
    seed = love.math.random(1000), pose = love.math.random(3), t = 0 }
  while #list > MAX do
    table.remove(list, 1)
  end
end

--- Somebody went down at (x, y), the blow going `angle`, in `look`,
--- killed by damage type `cause` (nil for a plain round): a body, or what
--- the damage feature leaves instead (a car's or a blast's splat, ash), and
--- the splat's sound either way. True when it left a body.
function Corpses.down(x, y, angle, look, cause)
  angle = angle or 0
  local body = not NO_BODY[cause or ""]
  if body then
    Corpses.add(x, y, angle, look)
  else
    local damage = Features.byName.damage
    if damage and damage.deathAt then
      damage:deathAt(x, y, angle, cause)
      return false -- it plays the splat itself
    elseif Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle)
    end
  end
  if Features.byName.pedestrians then
    require("src.features.pedestrians.sounds").play("splat", x, y, 0.9 + love.math.random() * 0.2)
  end
  return body
end

function Corpses:update(dt)
  for i = #list, 1, -1 do
    list[i].t = list[i].t + dt
    if list[i].t > LIE then
      table.remove(list, i)
    end
  end
end

--- What covers the back of the head: a hood, a hat or helmet, or hair.
local function cover(look)
  if look.mask then
    return look.hood or look.skin
  end
  return look.hood or look.hat or look.hair or Body.HAIR
end

local function limb(x0, y0, x1, y1, w, col, alpha, k)
  set(col, alpha, k)
  love.graphics.setLineWidth(w)
  love.graphics.line(x0, y0, x1, y1)
end

--- A boot at (x, y), its toe pointing `a`.
local function boot(look, x, y, a, alpha)
  set(look.shoes or Body.SHOES, alpha)
  love.graphics.ellipse("fill", x + math.cos(a) * 1.5, y + math.sin(a) * 1.5, 2.6, 1.9, 8)
end

--- A minigun on the ground at (gx, gy), lying `ga`: the housing, the six
--- barrels still, the belt trailing off it.
local function minigun(gx, gy, ga, alpha)
  love.graphics.push()
  love.graphics.translate(gx, gy)
  love.graphics.rotate(ga)
  set({ 0.55, 0.45, 0.2 }, alpha)
  love.graphics.setLineWidth(1.4)
  love.graphics.line(-1, 1.5, -5, 4, -8, 3.5) -- the belt, torn off the drum
  set({ 0.2, 0.21, 0.23 }, alpha)
  love.graphics.rectangle("fill", -1, -2.6, 7, 5.2, 1)
  love.graphics.setLineWidth(1.1)
  for k = -1, 1 do
    set(k == 0 and { 0.4, 0.42, 0.46 } or { 0.14, 0.14, 0.16 }, alpha)
    love.graphics.line(6, k * 1.4, 16, k * 1.4)
  end
  set({ 0.3, 0.31, 0.34 }, alpha)
  love.graphics.rectangle("fill", 10, -2.2, 1.3, 4.4)
  love.graphics.rectangle("fill", 15, -2.2, 1.2, 4.4)
  love.graphics.pop()
end

--- His gun on the ground at (gx, gy), lying `ga`: only for one who carried one.
local function gun(look, gx, gy, ga, alpha)
  if not look.gun then
    return
  end
  if look.minigun then
    minigun(gx, gy, ga, alpha)
    return
  end
  set({ 0.1, 0.1, 0.12 }, alpha)
  love.graphics.setLineWidth(2.6)
  love.graphics.line(gx, gy, gx + math.cos(ga) * 14, gy + math.sin(ga) * 14)
  set({ 0.35, 0.36, 0.42 }, alpha)
  love.graphics.setLineWidth(1)
  love.graphics.line(gx + math.cos(ga) * 4, gy + math.sin(ga) * 4 - 0.8, gx + math.cos(ga) * 14,
    gy + math.sin(ga) * 14 - 0.8)
end

--- Flat on his back, lying along +x (the head that way), from above.
local function sprawl(c, alpha)
  local look, s = c.look, c.seed
  local shirt, pants = look.shirt, look.pants
  -- How this one fell: which arm went up, how far the legs splayed.
  local flip = hash(s) < 0.5 and 1 or -1
  local splay = 2 + hash(s + 1) * 5
  local reach = hash(s + 2)
  -- Shadow.
  love.graphics.setColor(0, 0, 0, 0.25 * alpha)
  love.graphics.ellipse("fill", -2, 1.5, 15, 7, 16)
  -- Legs, bent a little at the knee, boots at the ends.
  for _, side in ipairs({ -1, 1 }) do
    local kx, ky = -9, side * (3 + splay * 0.4)
    local fx, fy = -16 + (side == flip and 2 or 0), side * (3.5 + splay)
    limb(-4, side * 2.4, kx, ky, 3.8, pants, alpha, 1.6)
    limb(kx, ky, fx, fy, 3.4, pants, alpha, 1.4)
    boot(look, fx, fy, math.pi, alpha)
  end
  -- Arms: one flung up past the head, the other out to the side.
  local up = { 9 + reach * 3, flip * -(8 + reach * 3) }
  local out = { 1 - reach * 4, -flip * (11 + reach * 2) }
  limb(3, flip * -4.6, up[1], up[2], 3, shirt, alpha, 1.1)
  limb(3, -flip * -4.6, out[1], out[2], 3, shirt, alpha, 1.1)
  set(look.skin, alpha) -- gloved hands
  love.graphics.circle("fill", up[1], up[2], 1.9, 8)
  love.graphics.circle("fill", out[1], out[2], 1.9, 8)
  -- The torso, flat on the ground: fatigues and the armoured vest over them.
  set(shirt, alpha)
  love.graphics.ellipse("fill", 0, 0, 6.5, 5.6, 16)
  set(shirt, alpha * 0.8, 0.45)
  love.graphics.setLineWidth(1)
  love.graphics.ellipse("line", 0, 0, 6.5, 5.6, 16)
  if look.vest then
    set(look.vest, alpha)
    love.graphics.ellipse("fill", 0.5, 0, 4.8, 4.2, 14)
    set(look.vest, alpha, 0.75)
    love.graphics.setLineWidth(1)
    love.graphics.line(-3, 0, 4, 0) -- the vest's seam
  end
  set(pants, alpha, 1.5)
  love.graphics.ellipse("fill", -4.5, 0, 3, 4.4, 10) -- the belt and hips
  -- The head, turned a little aside, face up: the hood and the mask with
  -- two dead lenses, or a face with its eyes shut under hair, a hat or a hood.
  local tilt = flip * 0.4
  love.graphics.push()
  love.graphics.translate(9.5, 0)
  love.graphics.rotate(tilt)
  if look.mask then
    set(cover(look), alpha)
    love.graphics.circle("fill", -0.6, 0, 4.2, 12)
    set(look.skin, alpha)
    love.graphics.circle("fill", 0.8, 0, 3.3, 12)
    set(LENS_DEAD, alpha)
    if look.visor then
      love.graphics.setLineWidth(1.2)
      love.graphics.line(2.7, -2.2, 2.7, 2.2) -- the one slit, dark now
    else
      love.graphics.circle("fill", 2.6, -1.5, 1, 6)
      love.graphics.circle("fill", 2.6, 1.5, 1, 6)
    end
  else
    set(cover(look), alpha)
    love.graphics.circle("fill", 0.8, 0, 4.2, 12)
    set(look.skin or Body.SKIN, alpha)
    love.graphics.circle("fill", -0.4, 0, 3.2, 12)
    set(EYES_SHUT, alpha)
    love.graphics.setLineWidth(0.7)
    love.graphics.line(0.1, -0.7, 0.1, -1.9) -- the lids, shut
    love.graphics.line(0.1, 0.7, 0.1, 1.9)
  end
  love.graphics.pop()
  -- His gun, dropped by the hand that was out.
  gun(look, out[1] + 3, out[2] + flip * 3, flip * (0.8 + reach), alpha)
end

--- Face down, lying along +x: the back of his vest and hood up, both arms
--- bent up by his head, one knee drawn up, the gun by his hand.
local function prone(c, alpha)
  local look, s = c.look, c.seed
  local shirt, pants = look.shirt, look.pants
  local flip = hash(s) < 0.5 and 1 or -1
  local bend = hash(s + 1)
  local reach = hash(s + 2)
  love.graphics.setColor(0, 0, 0, 0.25 * alpha)
  love.graphics.ellipse("fill", -2, 1.5, 15, 6.5, 16)
  -- Legs: one straight out behind, the other bent up at the knee.
  local sx, sy = -17, -flip * (3 + bend * 2)
  limb(-4, -flip * 2.2, -10, -flip * 2.8, 3.8, pants, alpha, 1.25)
  limb(-10, -flip * 2.8, sx, sy, 3.4, pants, alpha, 1.15)
  boot(look, sx, sy, math.pi, alpha)
  local kx, ky = -8 + bend * 2, flip * (8 + bend * 3)
  local fx, fy = -15, flip * (6 + bend * 2)
  limb(-4, flip * 2.2, kx, ky, 3.8, pants, alpha, 1.25)
  limb(kx, ky, fx, fy, 3.4, pants, alpha, 1.15)
  boot(look, fx, fy, math.pi + flip * 0.6, alpha)
  -- Arms bent up beside his head, elbows out, gloved hands by the hood.
  for _, side in ipairs({ -1, 1 }) do
    local far = side == flip and reach * 3 or 0
    local ex, ey = 3 + far, side * (9 + far)
    local hx, hy = 11 + far * 1.5, side * (5.5 + far * 0.6)
    limb(3, side * 4.6, ex, ey, 3, shirt, alpha, 0.9)
    limb(ex, ey, hx, hy, 2.8, shirt, alpha, 0.85)
    set(look.skin, alpha)
    love.graphics.circle("fill", hx, hy, 1.9, 8)
  end
  -- The torso from behind: the vest's back plate and the webbing over it.
  set(shirt, alpha, 0.85)
  love.graphics.ellipse("fill", 0, 0, 6.6, 5.6, 16)
  set(shirt, alpha * 0.8, 0.4)
  love.graphics.setLineWidth(1)
  love.graphics.ellipse("line", 0, 0, 6.6, 5.6, 16)
  if look.vest then
    set(look.vest, alpha, 0.85)
    love.graphics.rectangle("fill", -3.5, -3.8, 7.5, 7.6, 2)
    set(look.vest, alpha, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.line(-3.5, -1.2, 4, -1.2) -- the straps across it
    love.graphics.line(-3.5, 1.4, 4, 1.4)
  end
  set(pants, alpha, 1.5)
  love.graphics.ellipse("fill", -4.5, 0, 3, 4.4, 10)
  if look.pack then -- his pack, still on his back
    set(look.pack, alpha)
    love.graphics.rectangle("fill", -5.5, -3.6, 6, 7.2, 1.5)
    set(look.pack, alpha, 0.6)
    love.graphics.setLineWidth(1)
    love.graphics.line(-2.5, -3.6, -2.5, 3.6) -- the flap
  end
  -- The back of his head, face in the dirt: no face or lenses to see.
  local back = cover(look)
  set(back, alpha)
  love.graphics.circle("fill", 9.5, flip * 0.6, 4.2, 12)
  love.graphics.setLineWidth(1)
  if look.mask or look.hood then
    set(back, alpha, 0.7)
    love.graphics.line(7, flip * 0.6, 12.5, flip * 0.6) -- the seam over the crown
  else
    set(back, alpha, 1.4)
    love.graphics.circle("fill", 8.6, flip * 0.6 - 1.2, 1.2, 6) -- the light on the crown
  end
  -- The gun, just past the hand that was furthest out.
  gun(look, 12 + reach * 3, flip * (7 + reach), flip * (0.05 + reach * 0.15), alpha)
end

--- Curled on his side, lying along +x, his back to -y (flip mirrors him):
--- knees drawn up, one arm across his chest, the other out on the ground,
--- his mask side on with the one lens showing.
local function curled(c, alpha)
  local look, s = c.look, c.seed
  local shirt, pants = look.shirt, look.pants
  local flip = hash(s) < 0.5 and 1 or -1
  local tuck = hash(s + 1)
  local reach = hash(s + 2)
  love.graphics.setColor(0, 0, 0, 0.25 * alpha)
  love.graphics.ellipse("fill", -1, flip * 1.5, 12, 7, 16)
  -- Legs drawn up towards his chest, the knees forward (+y side), one leg
  -- over the other.
  for k, lift in ipairs({ 0, 1 }) do
    local kx, ky = -4 + tuck * 2 + lift * 1.5, flip * (8 + tuck * 3 - lift * 1.5)
    local fx, fy = -12 + lift * 1.5, flip * (5 + tuck * 2 - lift * 2)
    local k2 = k == 1 and 1.05 or 1.3 -- the one underneath darker
    limb(-4, flip * (0.5 + lift), kx, ky, 3.8, pants, alpha, k2)
    limb(kx, ky, fx, fy, 3.4, pants, alpha, k2 * 0.9)
    boot(look, fx, fy, math.pi - flip * 0.8, alpha)
  end
  -- The arm underneath, out along the ground past his head.
  local ox, oy = 14 + reach * 3, flip * (4 + reach * 3)
  limb(3, flip * 1.5, ox, oy, 3, shirt, alpha, 0.8)
  set(look.skin, alpha)
  love.graphics.circle("fill", ox, oy, 1.9, 8)
  -- The torso side on: narrower, his back a curve to -y.
  set(shirt, alpha)
  love.graphics.ellipse("fill", 0, 0, 6.8, 4.2, 16)
  set(shirt, alpha * 0.8, 0.45)
  love.graphics.setLineWidth(1)
  love.graphics.ellipse("line", 0, 0, 6.8, 4.2, 16)
  if look.vest then
    set(look.vest, alpha)
    love.graphics.ellipse("fill", 0.8, flip * 0.8, 4.6, 2.8, 14)
  end
  set(pants, alpha, 1.5)
  love.graphics.ellipse("fill", -4.8, 0, 2.8, 3.6, 10)
  -- The arm on top, bent across his chest, the hand by his knees.
  local ex, ey = 3.5, flip * 5.5
  limb(1.5, -flip * 1, ex, ey, 3, shirt, alpha, 1.15)
  limb(ex, ey, -2, flip * 6.5, 2.8, shirt, alpha, 1.1)
  set(look.skin, alpha)
  love.graphics.circle("fill", -2, flip * 6.5, 1.9, 8)
  -- The head tucked down, side on: the back of it, the face (or mask) to
  -- the front, one dead lens or one shut eye.
  love.graphics.push()
  love.graphics.translate(9, flip * 1.5)
  love.graphics.rotate(flip * (0.5 + tuck * 0.3))
  set(cover(look), alpha)
  love.graphics.circle("fill", -0.4, -flip * 0.6, 4.1, 12)
  set(look.skin or Body.SKIN, alpha)
  love.graphics.ellipse("fill", 1.2, flip * 0.9, 3, 2.6, 12)
  if look.mask then
    set(LENS_DEAD, alpha)
    love.graphics.circle("fill", 2.8, flip * 1.5, 1, 6)
  else
    set(EYES_SHUT, alpha)
    love.graphics.setLineWidth(0.7)
    love.graphics.line(2, flip * 1.4, 2.9, flip * 1.4)
  end
  love.graphics.pop()
  -- His gun, lying beside him where it slipped from his hand.
  gun(look, -6 - reach * 4, -flip * (8 + reach * 2), flip * (0.15 + reach * 0.3), alpha)
end

local POSES = { sprawl, prone, curled }

function Corpses:drawBelowCars()
  for _, c in ipairs(list) do
    local alpha = math.min(1, (LIE - c.t) / FADE)
    -- The pool under him, spreading out to one side.
    local k = math.min(1, c.t / POOL_TIME)
    local side = c.seed % 2 == 0 and 1 or -1
    local px, py = c.x - math.sin(c.angle) * side * 6 * k, c.y + math.cos(c.angle) * side * 6 * k
    love.graphics.setColor(POOL[1], POOL[2], POOL[3], 0.7 * alpha)
    for b = 0, 2 do
      local a = c.seed + b * 2.1
      love.graphics.circle("fill", px + math.cos(a) * 4 * k, py + math.sin(a) * 4 * k, (3 + b * 1.5) * k + 1.5, 14)
    end
    love.graphics.push()
    love.graphics.translate(c.x, c.y)
    love.graphics.rotate(c.angle)
    love.graphics.scale(SIZE * (c.look.size or 1))
    POSES[c.pose or 1](c, alpha)
    love.graphics.pop()
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Corpses
