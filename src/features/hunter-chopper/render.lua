-- The Hunter-Chopper, drawn from above: the Combine's gunship-helicopter,
-- a long insect of dark armour. An armoured head with a faceted canopy
-- and one cold eye at the nose, the pulse gun slung under the chin and
-- swinging to its aim, a broad belly with stub wings out to an engine pod
-- either side glowing at the back, and a long thin tail out to a
-- stabiliser and the tail rotor. The main rotor turns over all of it, a
-- blur with the blades flicking through. It flies, so its shadow falls well
-- off to the side, further the higher it is, and its rotor's with it.
--
-- Nothing here keeps state: everything takes what to draw and the clock,
-- so the fight and anything else that shows a chopper draw the same thing.

local Render = {}

-- Look ---------------------------------------------------------------------

Render.HULL = { 0.25, 0.28, 0.32 }
Render.HULL_DARK = { 0.14, 0.16, 0.19 }
Render.HULL_LIGHT = { 0.40, 0.44, 0.49 }
Render.GLOW = { 0.50, 0.88, 1.00 }
local SEAM = { 0.08, 0.09, 0.11 }
local GLASS = { 0.10, 0.14, 0.17 }
local GLASS_SHINE = { 0.55, 0.70, 0.78 }
local GUN = { 0.12, 0.13, 0.15 }
local FLASH = { 0.75, 0.95, 1.00 }
local BLADE = { 0.10, 0.11, 0.12 }
local SMOKE = { 0.12, 0.12, 0.12 }
local FIRE = { 1.00, 0.55, 0.15 }

-- Size ---------------------------------------------------------------------
-- Everything below is in px, nose along +x, starboard along +y. A car is
-- 40 x 20 and a person 17 across; the chopper is 175 nose to tail.

Render.RADIUS = 34 -- px round the middle of it, for hitting it
Render.ROTOR = 96 -- px from the hub to a blade tip
Render.ALTITUDE = 80 -- px its shadow falls away when it is up at its usual height
local HUB = { -6, 0 } -- where the rotor turns
local BLADES = 4
local ROTOR_SPEED = 26 -- radians a second
local GUN_ARC = math.rad(70) -- how far either way of the nose the gun swings
local GUN_AT = { 50, 0 } -- the turret under the chin
local GUN_LENGTH = 34

-- Outlines (convex, so each fills in one go).
local HEAD = { { 64, 0 }, { 59, 11 }, { 46, 19 }, { 28, 22 }, { 18, 19 }, { 18, -19 }, { 28, -22 }, { 46, -19 },
  { 59, -11 } }
local BELLY = { { 26, 20 }, { 4, 27 }, { -28, 25 }, { -46, 13 }, { -52, 0 }, { -46, -13 }, { -28, -25 }, { 4, -27 },
  { 26, -20 } }
local CANOPY = { { 60, 0 }, { 55, 8 }, { 42, 14 }, { 30, 15 }, { 30, -15 }, { 42, -14 }, { 55, -8 } }
local BOOM = { { -44, 7 }, { -106, 3 }, { -106, -3 }, { -44, -7 } }
local TAILPLANE = { { -96, 4 }, { -100, 20 }, { -110, 20 }, { -112, 4 }, { -112, -4 }, { -110, -20 }, { -100, -20 },
  { -96, -4 } }
local WING = { { 0, 22 }, { -4, 42 }, { -20, 42 }, { -26, 22 } } -- starboard; port is the mirror
local POD = { x0 = -36, x1 = 12, y = 47, r = 8 } -- each engine pod, a capsule along the wing tip

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function flat(points, mirror)
  local out = {}
  for _, p in ipairs(points) do
    out[#out + 1] = p[1]
    out[#out + 1] = mirror and -p[2] or p[2]
  end
  return out
end

local function capsule(mode, x0, x1, y, r)
  love.graphics.rectangle(mode, x0, y - r, x1 - x0, r * 2, r, r)
end

--- Every solid part in one colour: the shadow, and the dark rim under the hull.
local function silhouette(grow)
  love.graphics.push()
  love.graphics.scale(grow, grow)
  love.graphics.polygon("fill", flat(HEAD))
  love.graphics.polygon("fill", flat(BELLY))
  love.graphics.polygon("fill", flat(BOOM))
  love.graphics.polygon("fill", flat(TAILPLANE))
  for _, m in ipairs({ false, true }) do
    love.graphics.polygon("fill", flat(WING, m))
    capsule("fill", POD.x0, POD.x1, m and -POD.y or POD.y, POD.r)
  end
  love.graphics.pop()
end

--- The rotor seen from above: a faint disc, the blades flicking round it.
local function drawRotor(time, spin, shadow)
  local r = Render.ROTOR
  if shadow then
    love.graphics.setColor(0, 0, 0, 0.07 * spin)
    love.graphics.circle("fill", HUB[1], HUB[2], r, 40)
    return
  end
  -- The faster it turns, the more the blades blur into a disc.
  color(BLADE, 0.10 * spin)
  love.graphics.circle("fill", HUB[1], HUB[2], r, 48)
  color(BLADE, 0.16 * spin)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", HUB[1], HUB[2], r, 48)
  local turn = time * ROTOR_SPEED * spin + 0.4
  for b = 0, BLADES - 1 do
    local a = turn + b * 2 * math.pi / BLADES
    -- Each blade with a smear behind it, fading; a stopped one solid.
    for k = spin > 0.05 and 3 or 0, 0, -1 do
      local ak = a - k * 0.09 * spin
      color(BLADE, spin > 0.05 and 0.55 - k * 0.13 or 1)
      love.graphics.setLineWidth(7 - k)
      love.graphics.line(HUB[1] + math.cos(ak) * 10, HUB[2] + math.sin(ak) * 10, HUB[1] + math.cos(ak) * r,
        HUB[2] + math.sin(ak) * r)
    end
    color(Render.HULL_LIGHT, 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.line(HUB[1] + math.cos(a) * 10, HUB[2] + math.sin(a) * 10, HUB[1] + math.cos(a) * r,
      HUB[2] + math.sin(a) * r)
  end
  love.graphics.setLineWidth(1)
  color(SEAM)
  love.graphics.circle("fill", HUB[1], HUB[2], 9, 16)
  color(Render.HULL_LIGHT)
  love.graphics.circle("fill", HUB[1], HUB[2], 6, 14)
  color(SEAM)
  love.graphics.circle("fill", HUB[1], HUB[2], 2.5, 8)
end

--- The tail rotor: side on from above, a thin blur on the starboard side of the tail.
local function drawTailRotor(time, spin)
  local flick = (math.sin(time * 60 * spin) + 1) / 2
  color(BLADE, 0.25 + flick * 0.3)
  love.graphics.setLineWidth(3)
  love.graphics.line(-116, 6, -92, 6)
  love.graphics.setLineWidth(1)
  color(SEAM)
  love.graphics.circle("fill", -104, 6, 3, 8)
end

--- The pulse gun under the chin, turned to `aim` (radians off the nose),
--- flashing while it fires. Returns the muzzle, in the chopper's own frame.
local function drawGun(aim, firing, time)
  love.graphics.push()
  love.graphics.translate(GUN_AT[1], GUN_AT[2])
  love.graphics.rotate(aim)
  color(GUN)
  love.graphics.rectangle("fill", 0, -5, GUN_LENGTH, 4, 1)
  love.graphics.rectangle("fill", 0, 1, GUN_LENGTH, 4, 1)
  color(Render.HULL_DARK)
  love.graphics.rectangle("fill", 4, -6, 12, 12, 3)
  color(Render.GLOW, 0.6)
  love.graphics.rectangle("fill", 6, -1, 8, 2)
  if firing then
    local f = 0.6 + 0.4 * math.abs(math.sin(time * 70))
    color(FLASH, 0.35 * f)
    love.graphics.circle("fill", GUN_LENGTH + 8, 0, 13 * f, 12)
    color(FLASH, 0.9)
    love.graphics.polygon("fill", GUN_LENGTH, -4, GUN_LENGTH + 18 * f, 0, GUN_LENGTH, 4)
  end
  love.graphics.pop()
  local c, s = math.cos(aim), math.sin(aim)
  return GUN_AT[1] + c * (GUN_LENGTH + 4), GUN_AT[2] + s * (GUN_LENGTH + 4)
end

--- The hull, nose to tail, with its seams, vents, lights and canopy.
local function drawHull(time, bank, spin)
  -- The dark rim, then the plates, lit from the top left; banking tips the
  -- light across (the high side catches it).
  color(SEAM)
  silhouette(1.03)
  color(Render.HULL_DARK)
  love.graphics.polygon("fill", flat(BOOM))
  love.graphics.polygon("fill", flat(TAILPLANE))
  for _, m in ipairs({ false, true }) do
    color(Render.HULL_DARK)
    love.graphics.polygon("fill", flat(WING, m))
    local y = m and -POD.y or POD.y
    color(Render.HULL)
    capsule("fill", POD.x0, POD.x1, y, POD.r)
    color(Render.HULL_LIGHT, 0.6)
    capsule("fill", POD.x0 + 4, POD.x1 - 4, y - 3, POD.r * 0.4)
    -- The intake at the front, the exhaust glowing at the back.
    color(SEAM)
    love.graphics.circle("fill", POD.x1 - 2, y, POD.r * 0.6, 10)
    local glow = (0.65 + 0.25 * math.sin(time * 9 + (m and 1 or 0))) * (0.15 + 0.85 * spin) -- dark, stopped
    color(Render.GLOW, 0.25 * glow)
    love.graphics.circle("fill", POD.x0 - 4, y, POD.r * 1.3, 12)
    color(Render.GLOW, glow)
    love.graphics.circle("fill", POD.x0 + 2, y, POD.r * 0.55, 10)
  end
  color(Render.HULL)
  love.graphics.polygon("fill", flat(BELLY))
  love.graphics.polygon("fill", flat(HEAD))
  local lit = 0.35 - (bank or 0) * 0.2
  color(Render.HULL_LIGHT, 0.55)
  love.graphics.push()
  love.graphics.translate(-2, -6 * (1 + lit))
  love.graphics.scale(0.8, 0.45)
  love.graphics.polygon("fill", flat(BELLY))
  love.graphics.pop()
  -- Seams: across the belly in bands, and down the spine.
  color(SEAM, 0.85)
  love.graphics.setLineWidth(1.5)
  for _, x in ipairs({ 18, -8, -32 }) do
    love.graphics.line(x, -22, x, 22)
  end
  love.graphics.line(18, 0, -46, 0)
  love.graphics.line(-50, 0, -100, 0)
  -- The tail in segments, like an insect's.
  for x = -56, -92, -9 do
    local half = 7 - (x + 44) / -62 * 4
    color(SEAM)
    love.graphics.line(x, -half, x, half)
    color(Render.HULL_LIGHT, 0.5)
    love.graphics.line(x - 2, -half + 1, x - 2, -1)
  end
  -- Vents either side of the spine, breathing.
  local breathe = 0.35 + 0.25 * math.sin(time * 3)
  for v = -1, 1, 2 do
    for k = 0, 3 do
      local x = -14 - k * 4
      color(SEAM)
      love.graphics.setLineWidth(2)
      love.graphics.line(x, v * 8, x, v * 17)
      color(Render.GLOW, breathe * 0.4)
      love.graphics.setLineWidth(1)
      love.graphics.line(x, v * 8, x, v * 17)
    end
  end
  -- The canopy: dark faceted glass with a shine, and the eye in the nose.
  color(GLASS)
  love.graphics.polygon("fill", flat(CANOPY))
  color(SEAM)
  love.graphics.setLineWidth(1.5)
  love.graphics.line(30, 0, 56, 0)
  love.graphics.line(42, -14, 46, 0, 42, 14)
  color(GLASS_SHINE, 0.45)
  love.graphics.polygon("fill", 52, -6, 44, -12, 36, -12, 44, -6)
  local eye = 0.7 + 0.3 * math.sin(time * 4)
  color(Render.GLOW, 0.3 * eye)
  love.graphics.circle("fill", 61, 0, 7, 12)
  color(Render.GLOW, eye)
  love.graphics.circle("fill", 61, 0, 3, 10)
  -- Running lights on the tailplane tips, blinking.
  local blink = math.sin(time * 5) > 0.6
  color(blink and { 1, 0.3, 0.25 } or SEAM)
  love.graphics.circle("fill", -106, -19, 2.5, 6)
  color(blink and { 0.4, 1, 0.5 } or SEAM)
  love.graphics.circle("fill", -106, 19, 2.5, 6)
  love.graphics.setLineWidth(1)
end

--- Damage: scorch, sparks, and smoke pouring off it when it is badly hurt.
local function drawHurt(hurt, time)
  if hurt <= 0 then
    return
  end
  local spots = { { 30, 10 }, { -20, -18 }, { 6, 16 }, { -38, 6 }, { -10, -42 }, { 44, -12 }, { -70, 0 } }
  for k = 1, math.min(#spots, math.floor(hurt * 8)) do
    local p = spots[k]
    love.graphics.setColor(0.04, 0.04, 0.04, 0.65)
    love.graphics.circle("fill", p[1], p[2], 4 + k % 3, 8)
    if math.sin(time * 17 + k * 2.3) > 0.75 then
      color(FIRE)
      love.graphics.circle("fill", p[1] + 1, p[2] - 1, 2, 6)
    end
  end
  if hurt > 0.6 then -- the starboard engine on fire, smoke streaming back off it
    for k = 0, 5 do
      local t = (time * 1.6 + k / 6) % 1
      color(SMOKE, 0.45 * (1 - t))
      love.graphics.circle("fill", POD.x0 - 6 - t * 70, POD.y + math.sin(k * 1.7 + time) * 6 * t, 6 + t * 16, 10)
    end
    local f = 0.6 + 0.4 * math.sin(time * 23)
    color(FIRE, 0.8)
    love.graphics.circle("fill", POD.x0 + 4, POD.y, 5 * f, 8)
  end
end

-- Drawing it -----------------------------------------------------------------

--- The gun's aim off the nose, clamped to how far it swings, for a chopper
--- facing `angle` aiming at world angle `aim`.
local function gunAim(angle, aim)
  local a = ((aim or angle) - angle + math.pi) % (2 * math.pi) - math.pi
  return math.max(-GUN_ARC, math.min(GUN_ARC, a))
end

--- Can the gun of a chopper facing `angle` swing round to world angle `aim`?
function Render.canAim(angle, aim)
  local a = (aim - angle + math.pi) % (2 * math.pi) - math.pi
  return math.abs(a) <= GUN_ARC
end

--- One of its bombs from above, `height` px up over (x, y): a dark finned
--- casing with a light blinking on its nose, its shadow off to the side
--- by its height the way the chopper's is, closing in as it falls.
function Render.bomb(x, y, height, time)
  local size = 1 + height / 300
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", x + height * 0.75, y + height, 6, 10)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(size, size)
  love.graphics.rotate(time * 3)
  color(SEAM)
  for k = 0, 3 do -- the fins, a cross seen from above
    local a = k * math.pi / 2
    love.graphics.polygon("fill", math.cos(a) * 4, math.sin(a) * 4, math.cos(a + 0.35) * 11, math.sin(a + 0.35) * 11,
      math.cos(a - 0.35) * 11, math.sin(a - 0.35) * 11)
  end
  color(Render.HULL_DARK)
  love.graphics.circle("fill", 0, 0, 7, 12)
  color(Render.HULL_LIGHT, 0.7)
  love.graphics.circle("fill", -2, -2, 3, 8)
  local blink = math.sin(time * 18) > 0
  love.graphics.setColor(1, 0.2, 0.15, blink and 1 or 0.35)
  love.graphics.circle("fill", 0, 0, 2.5, 8)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Does a round of `radius` at (px, py) hit a chopper at (x, y) facing
--- `angle`, `altitude` up? Its hull from nose to tail-root, and the pods.
function Render.hits(x, y, angle, altitude, px, py, radius)
  local size = 1 + (altitude or Render.ALTITUDE) / 900
  local ca, sa = math.cos(angle), math.sin(angle)
  local dx, dy = px - x, py - y
  local u, v = (dx * ca + dy * sa) / size, (-dx * sa + dy * ca) / size -- into its own frame
  local r = radius / size
  local along = math.max(-50, math.min(62, u))
  if (u - along) ^ 2 + v ^ 2 <= (24 + r) ^ 2 then
    return true
  end
  for _, side in ipairs({ -1, 1 }) do
    local pu = math.max(POD.x0, math.min(POD.x1, u))
    if (u - pu) ^ 2 + (v - side * POD.y) ^ 2 <= (POD.r + r) ^ 2 then
      return true
    end
  end
  return false
end

--- What is left of it where it came down: a black scorch, the hull broken
--- and burnt, the tail torn off and lying askew, two blades bent out of the
--- hub, fire still licking at it and smoke going up. `w` is { x, y, angle }.
function Render.wreck(w, time)
  love.graphics.setColor(0.04, 0.04, 0.04, 0.3)
  love.graphics.circle("fill", w.x, w.y, 110, 28)
  love.graphics.setColor(0.04, 0.04, 0.04, 0.25)
  love.graphics.circle("fill", w.x + 40, w.y - 20, 60, 20)
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.rotate(w.angle)
  love.graphics.setColor(0, 0, 0, 0.4)
  love.graphics.push()
  love.graphics.translate(6, 8)
  silhouette(1)
  love.graphics.pop()
  -- The tail, broken off at the root and lying at an angle.
  love.graphics.push()
  love.graphics.translate(-46, 0)
  love.graphics.rotate(0.6)
  love.graphics.translate(46, 0)
  color(Render.HULL_DARK, 1)
  love.graphics.polygon("fill", flat(BOOM))
  love.graphics.polygon("fill", flat(TAILPLANE))
  love.graphics.pop()
  color({ 0.20, 0.20, 0.21 })
  love.graphics.polygon("fill", flat(BELLY))
  love.graphics.polygon("fill", flat(HEAD))
  for _, m in ipairs({ false, true }) do
    love.graphics.polygon("fill", flat(WING, m))
    capsule("fill", POD.x0, POD.x1, m and -POD.y or POD.y, POD.r)
  end
  color(Render.HULL_LIGHT, 0.8) -- what paint is left
  love.graphics.polygon("fill", 20, -12, 4, -20, -20, -16, -10, 4)
  love.graphics.polygon("fill", 40, 6, 30, 16, 22, 12, 30, 2)
  color(GLASS)
  love.graphics.polygon("fill", flat(CANOPY))
  color(BLADE)
  love.graphics.setLineWidth(6)
  love.graphics.line(HUB[1], HUB[2], HUB[1] + 70, HUB[2] + 30, HUB[1] + 92, HUB[2] + 60) -- bent down at the tip
  love.graphics.line(HUB[1], HUB[2], HUB[1] - 40, HUB[2] - 60)
  love.graphics.setLineWidth(1)
  color(SEAM)
  love.graphics.circle("fill", HUB[1], HUB[2], 8, 12)
  love.graphics.pop()
  -- Fire, and the smoke going up from it.
  for k = 0, 5 do
    local f = 0.6 + 0.4 * math.sin(time * (9 + k) + k * 1.7)
    local fx, fy = w.x + math.cos(k * 1.9) * 34, w.y + math.sin(k * 1.9) * 24
    color(FIRE, 0.45 * f)
    love.graphics.circle("fill", fx, fy, 8 * f, 10)
    love.graphics.setColor(1, 0.85, 0.4, 0.7 * f)
    love.graphics.circle("fill", fx, fy - 1, 3.5 * f, 8)
  end
  for k = 0, 7 do
    local t = (time * 0.35 + k / 8) % 1
    color(SMOKE, 0.25 * (1 - t))
    love.graphics.circle("fill", w.x + 20 + t * 110 + math.sin(k * 2.1 + time * 0.5) * 12, w.y - 20 - t * 180,
      10 + t * 34, 14)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Where the muzzle is, in world px, and the way it points: the host fires
--- from here, so its rounds leave from where every screen draws the gun.
function Render.muzzle(x, y, angle, aim, altitude)
  local size = 1 + (altitude or Render.ALTITUDE) / 900
  local a = gunAim(angle, aim)
  local mx = GUN_AT[1] + math.cos(a) * (GUN_LENGTH + 4)
  local my = GUN_AT[2] + math.sin(a) * (GUN_LENGTH + 4)
  local ca, sa = math.cos(angle), math.sin(angle)
  return x + (ca * mx - sa * my) * size, y + (sa * mx + ca * my) * size, angle + a
end

--- The gun locking on: a thin beam along its aim from the muzzle, pulsing
--- faster as `k` (0..1) runs up to the first round.
local function drawLock(mx, my, aim, k, time)
  local pulse = 0.5 + 0.5 * math.sin(time * (10 + k * 30))
  local len = 900
  local ex, ey = mx + math.cos(aim) * len, my + math.sin(aim) * len
  love.graphics.setColor(1, 0.2, 0.15, (0.12 + 0.2 * k) * (0.5 + 0.5 * pulse))
  love.graphics.setLineWidth(5 + k * 5)
  love.graphics.line(mx, my, ex, ey)
  love.graphics.setColor(1, 0.35, 0.3, (0.45 + 0.45 * k) * (0.6 + 0.4 * pulse))
  love.graphics.setLineWidth(1.5 + k * 1.5)
  love.graphics.line(mx, my, ex, ey)
  love.graphics.setColor(1, 0.5, 0.4, 0.6 * pulse)
  love.graphics.circle("fill", mx, my, 3 + k * 4, 10)
  love.graphics.setLineWidth(1)
end

--- The chopper from above. `c` is:
---   x, y, angle   where it is and which way the nose points
---   altitude      px up: how far its shadow falls (defaults to ALTITUDE; 0 on the ground)
---   aim           where the gun points, in the world (defaults to `angle`); it
---                 swings only so far either way of the nose
---   firing        true while the gun fires (the muzzle flashes)
---   lock          0..1 the gun locking on (a beam down its aim), nil or 0 when not
---   bank          -1..1 leaning into a turn (port down .. starboard down)
---   spin          0..1 how fast the rotors turn (defaults to 1; 0 stopped)
---   hp, max       health: below 40% scorched, sparking, an engine on fire
---   bar           true: a health bar over it too (the fight has the boss bar instead)
---   flash         0..1 just hit: the hull flashes white
---   down          true: going down, smoke pouring off all of it
--- Returns the muzzle in world px, where its rounds leave from.
function Render.chopper(c, time)
  local altitude = c.altitude or Render.ALTITUDE
  local spin = c.spin or 1
  local bank = c.bank or 0
  local aim = gunAim(c.angle, c.aim)
  local hurt = (c.hp and c.max) and (1 - math.max(0, c.hp / c.max)) or 0
  -- Up close to the camera it looks a touch bigger; its shadow a touch smaller.
  local size = 1 + altitude / 900

  -- The shadow, down and to the right, the rotor's faint disc with it.
  love.graphics.push()
  love.graphics.translate(c.x + altitude * 0.75, c.y + altitude)
  love.graphics.rotate(c.angle)
  love.graphics.scale(1 / size, 1 / size)
  love.graphics.setColor(0, 0, 0, 0.3)
  silhouette(1)
  drawRotor(time, spin, true)
  love.graphics.pop()

  love.graphics.push()
  love.graphics.translate(c.x, c.y)
  love.graphics.rotate(c.angle)
  love.graphics.scale(size, size * (1 - math.abs(bank) * 0.12)) -- banked, it looks narrower
  drawTailRotor(time, spin)
  local mx, my = drawGun(aim, c.firing, time)
  drawHull(time, bank, spin)
  drawHurt(hurt, time)
  if c.flash and c.flash > 0 then
    love.graphics.setColor(1, 1, 1, math.min(0.7, c.flash * 4))
    silhouette(1)
  end
  drawRotor(time, spin, false)
  love.graphics.pop()
  if c.down then -- smoke billowing off it all as it goes down, left behind as it spins
    for k = 0, 9 do
      local t = (time * 1.3 + k / 10) % 1
      local a = k * 2.4
      love.graphics.setColor(0.10, 0.10, 0.10, 0.5 * (1 - t))
      love.graphics.circle("fill", c.x + math.cos(a) * (20 + t * 60), c.y + math.sin(a) * (20 + t * 60) - t * 40,
        10 + t * 26, 12)
    end
  end

  if c.bar and c.hp and c.max then
    local bw = 120
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", c.x - bw / 2 - 1, c.y - Render.ROTOR - 14, bw + 2, 6)
    local f = math.max(0, c.hp / c.max)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", c.x - bw / 2, c.y - Render.ROTOR - 13, bw * f, 4)
  end
  love.graphics.setColor(1, 1, 1)
  local ca, sa = math.cos(c.angle), math.sin(c.angle)
  local wx, wy = c.x + (ca * mx - sa * my) * size, c.y + (sa * mx + ca * my) * size
  if c.lock and c.lock > 0 then
    drawLock(wx, wy, c.angle + aim, c.lock, time)
  end
  love.graphics.setColor(1, 1, 1)
  return wx, wy
end

return Render
