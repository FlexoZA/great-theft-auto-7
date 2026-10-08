-- A player's body: where they are when they are not behind a wheel, and
-- what everyone sees of them then. The server keeps one per player in
-- `player.body` from the moment the game starts; while the player drives,
-- the body rides along inside the vehicle and is not drawn. `dead` is set
-- by whatever kills them (weapons) until they respawn.
--
-- Drawing is a person seen from above (`Body.person`): shoulders in their
-- shirt, feet that step as they walk, arms that swing or hold a gun out in
-- front, and a head with hair or a cap. Players wear their colour; the crowd
-- and the police officers draw the same figure in their own looks, so
-- everyone on foot reads as a person in the street, all the same size.

local Body = {}
Body.__index = Body

Body.RADIUS = 9 -- px; how fat a player is against walls and bullets
Body.SHOULDERS = 8.5 -- px from the middle to each shoulder: the figure is 17 across
Body.GUN = 9 -- px the barrel sticks out past the hands
Body.SKIN = { 0.92, 0.78, 0.63 }
Body.HAIR = { 0.2, 0.13, 0.08 }
Body.PANTS = { 0.22, 0.24, 0.32 }
Body.SHOES = { 0.12, 0.12, 0.14 }

function Body.new(x, y, facing)
  return setmetatable({
    x = x or 0,
    y = y or 0,
    facing = facing or 0, -- radians, the way they look
    dead = false,
  }, Body)
end

--- Is the point (px, py), padded by `radius`, on this body? Works on any
--- table with x, y (server bodies and client snapshots alike).
function Body.hitTest(body, px, py, radius)
  local r = Body.RADIUS + (radius or 0)
  return (px - body.x) ^ 2 + (py - body.y) ^ 2 <= r * r
end

local alpha = 1
local function set(c, k, a)
  k = k or 1
  love.graphics.setColor(math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k), (a or 1) * alpha)
end

--- A person at (x, y) looking along `angle`, seen from above. `swing` is
--- this frame's stride (px, signed: which foot is ahead). `look` is what
--- they look like, every field optional:
---   shirt, pants, skin, hair, shoes   colours (a player's colour, the crowd's shirts)
---   hat          a cap's colour, instead of hair on show; `brim` gives it a peak
---   hood         a hood's colour, up over the head (a simp's hoodie)
---   vest         a vest's colour over the shirt (a police officer's)
---   pack         a backpack's colour, on their back (a soldier's)
---   gun          true: both hands hold a gun out in front; `gunLength` how
---                far the barrel reaches past the hands (Body.GUN; a rifle's longer)
---   punch        true: the right fist thrown out in front
---   panic        true: arms flung out (fleeing the crowd)
---   alpha        how solid (the edge arrows draw a faded one)
---   shadow       false: no shadow (the caller draws its own: Bigfoot in the air)
--- Returns where the left and the right hand are, in the world (x1, y1,
--- x2, y2), for something held (a simp's torch).
function Body.person(x, y, angle, swing, look)
  swing = swing or 0
  alpha = look.alpha or 1
  local shirt = look.shirt or { 0.6, 0.6, 0.65 }
  local skin = look.skin or Body.SKIN
  local sh = Body.SHOULDERS
  love.graphics.push()
  love.graphics.translate(x, y)
  -- A shadow, cast down and right whichever way they face.
  if look.shadow ~= false then
    love.graphics.setColor(0, 0, 0, 0.3 * alpha)
    love.graphics.ellipse("fill", 2.5, 2.5, sh, sh, 14)
  end
  love.graphics.rotate(angle)
  -- Feet, one ahead as the other falls behind.
  local step = swing * 2.6
  set(look.shoes or Body.SHOES)
  love.graphics.ellipse("fill", step + 1.5, -3.6, 3.4, 2.1, 8)
  love.graphics.ellipse("fill", -step + 1.5, 3.6, 3.4, 2.1, 8)
  -- Hips, just showing behind the shoulders.
  set(look.pants or Body.PANTS)
  love.graphics.ellipse("fill", -1.5, 0, 3.4, 5.6, 10)
  -- Arms at their sides swing against the stride, under the shoulders; arms
  -- held out in front (a gun, a panic) go over them.
  local forward = look.gun or look.panic or look.punch
  local hands
  if look.gun then
    hands = { 8, -2.2, 8, 2.2 }
  elseif look.panic then
    hands = { 4.5, -sh - 3.5, 4.5, sh + 3.5 }
  elseif look.punch then
    hands = { -step * 0.9, -sh - 1, sh + 5, 2 } -- the right fist out in front
  else
    hands = { -step * 0.9, -sh - 1, step * 0.9, sh + 1 }
  end
  local function arms()
    set(skin, 0.92)
    love.graphics.setLineWidth(2.6)
    love.graphics.line(0.5, -sh + 1.5, hands[1], hands[2])
    love.graphics.line(0.5, sh - 1.5, hands[3], hands[4])
    love.graphics.setLineWidth(1)
  end
  local function handsAndGun()
    if look.gun then
      set({ 0.1, 0.1, 0.12 })
      love.graphics.setLineWidth(3)
      local tip = 8 + (look.gunLength or Body.GUN)
      love.graphics.line(6, 0, tip, 0)
      set({ 0.35, 0.36, 0.42 })
      love.graphics.setLineWidth(1)
      love.graphics.line(7, -0.8, tip, -0.8) -- the light along the barrel
    end
    set(skin)
    love.graphics.circle("fill", hands[1], hands[2], 2, 8)
    love.graphics.circle("fill", hands[3], hands[4], look.punch and 2.6 or 2, 8)
  end
  if not forward then
    arms()
    handsAndGun()
  end
  -- Shoulders: the shirt, lit from the front, with sleeves capping each end.
  set(shirt)
  love.graphics.ellipse("fill", 0, 0, 4.4, sh, 16)
  set(shirt, 0.82)
  love.graphics.ellipse("fill", 0.3, -sh + 0.8, 2.8, 2.4, 8)
  love.graphics.ellipse("fill", 0.3, sh - 0.8, 2.8, 2.4, 8)
  set(shirt, 1.3)
  love.graphics.ellipse("fill", 1.2, -2.5, 1.8, 3, 10)
  if look.vest then
    set(look.vest)
    love.graphics.ellipse("fill", -0.3, 0, 3.2, sh - 2.8, 12)
  end
  set(shirt, 0.4, 0.8)
  love.graphics.ellipse("line", 0, 0, 4.4, sh, 16)
  if look.pack then
    set(look.pack)
    love.graphics.rectangle("fill", -7.5, -4.5, 5, 9, 1.5)
    set(look.pack, 0.6)
    love.graphics.rectangle("line", -7.5, -4.5, 5, 9, 1.5)
    love.graphics.line(-5, -4.5, -5, 4.5) -- the flap
  end
  if forward then
    arms()
    handsAndGun()
  end
  -- The head: a face looking forward, hair (or a cap) over the back of it.
  set(skin)
  love.graphics.circle("fill", 1, 0, 3.7, 12)
  if look.hood then
    set(look.hood)
    love.graphics.circle("fill", -0.6, 0, 4.4, 12)
    set(look.hood, 1.25)
    love.graphics.circle("fill", -1.5, -1.5, 1.4, 6)
  elseif look.hat then
    set(look.hat)
    love.graphics.circle("fill", 0.1, 0, 3.8, 12)
    if look.brim then
      set(look.hat, 0.8)
      love.graphics.ellipse("fill", 3.8, 0, 1.6, 3, 8)
    end
    set(look.hat, 1.4)
    love.graphics.circle("fill", -0.6, -1.1, 1.2, 6)
  else
    set(look.hair or Body.HAIR)
    love.graphics.circle("fill", -0.4, 0, 3.5, 12)
    set(look.hair or Body.HAIR, 1.7)
    love.graphics.circle("fill", -0.9, -1.2, 1.1, 6)
  end
  if look.hood then
    set(look.hood, 0.55, 0.9)
    love.graphics.circle("line", -0.6, 0, 4.4, 12) -- the hood's edge; the face peeps out in front
  else
    set(skin, 0.45, 0.8)
    love.graphics.circle("line", 1, 0, 3.7, 12)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
  alpha = 1
  local c, s = math.cos(angle), math.sin(angle)
  return x + hands[1] * c - hands[2] * s, y + hands[1] * s + hands[2] * c,
    x + hands[3] * c - hands[4] * s, y + hands[3] * s + hands[4] * c
end

--- A player on foot at (x, y) looking along `angle`, in `color` (its fourth
--- value, if any, how solid), gun in hand; `swing` is the stride.
function Body.draw(x, y, angle, color, swing)
  Body.person(x, y, angle, swing, { shirt = color, gun = true, alpha = color[4] })
end

return Body
