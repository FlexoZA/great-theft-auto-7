-- Drawing the buildings, top down, inside the fence of the plot they stand
-- on, in the look the hospital and the storefronts have: roofs behind a
-- parapet lit from the top left, air conditioners with turning fans,
-- skylights, a name plate, and a yard with something going on in it. The
-- front, where the square is, is always the bottom edge.
--
-- What matters to play shows as it did: the yard holds what is waiting to
-- be collected (crates on pallets, barrels, piles, coins, or the cars
-- themselves), a factory's silos show how full each material is (the ring
-- round the top; faded when the product in hand doesn't use it), things
-- move while a batch is being made, a light by the gate says public (green)
-- or private (red), and a bar along the bottom fills with the batch. A
-- damaged building gets cracks, a health bar and a red flash when hit; a
-- destroyed one is a smoking heap of rubble in its own colours.

local Features = require("src.features")
local UI = require("src.ui")
local Kinds = require("src.features.buildings.kinds")
local Icons = require("src.features.weapons.icons")
local AbilityKinds = require("src.features.abilities.kinds")
local AbilityIcons = require("src.features.abilities.icons")
local Catalog = require("src.features.vehicles.catalog")
local Tiers = require("src.features.tiers")

local Render = {}

local COLORS = {
  iron = { 0.55, 0.6, 0.68 },
  sulfur = { 0.95, 0.85, 0.2 },
  minerals = { 0.3, 0.8, 0.75 },
  copper = { 0.85, 0.48, 0.25 },
  oil = { 0.12, 0.1, 0.14 },
  plastic = { 0.95, 0.55, 0.75 },
}
local AC = { 0.60, 0.62, 0.64 }
local GLASS = { 0.62, 0.85, 0.95 }
local CONCRETE = { 0.56, 0.56, 0.54 }
local HAZARD = { 0.95, 0.78, 0.15 }

local function shade(c, k)
  return { math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k), c[4] }
end

local function box(x, y, w, h, c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
  love.graphics.rectangle("fill", x, y, w, h)
end

--- The same number in 0..1 for `i` every frame, for speckles and scatter.
local function hash(i)
  local v = math.sin(i * 12.9898 + 78.233) * 43758.5453
  return v - math.floor(v)
end

--- A flat roof behind a darker parapet, with its shadow, lit along the top
--- and left the way the city draws its own buildings.
local function roof(x, y, w, h, c)
  box(x + 6, y + 6, w, h, { 0, 0, 0 }, 0.3)
  box(x, y, w, h, shade(c, 0.72))
  box(x + 5, y + 5, w - 10, h - 10, c)
  box(x + 5, y + 5, w - 10, 4, shade(c, 1.22))
  box(x + 5, y + 5, 4, h - 10, shade(c, 1.22))
end

--- An air conditioner, a box with a fan turning in it, centred on (x, y).
local function aircon(x, y, t)
  box(x - 11 + 3, y - 11 + 3, 22, 22, { 0, 0, 0 }, 0.3)
  love.graphics.setColor(AC)
  love.graphics.rectangle("fill", x - 11, y - 11, 22, 22, 2)
  love.graphics.setColor(shade(AC, 0.55))
  love.graphics.circle("fill", x, y, 8)
  love.graphics.setColor(shade(AC, 1.3))
  love.graphics.setLineWidth(2)
  for i = 0, 2 do
    local a = t * 9 + i * 2 * math.pi / 3
    love.graphics.line(x, y, x + math.cos(a) * 7, y + math.sin(a) * 7)
  end
  love.graphics.setLineWidth(1)
end

--- A row of skylight panes, `n` of them, from (x, y), `w` wide in all.
local function skylights(x, y, w, h, n)
  local pw = (w - (n - 1) * 4) / n
  for i = 0, n - 1 do
    local px = x + i * (pw + 4)
    box(px, y, pw, h, shade(GLASS, 0.55))
    box(px + 2, y + 2, pw - 4, h - 4, GLASS, 0.55)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.line(px + 3, y + 3, px + pw * 0.45, y + 3)
  end
end

--- A chimney that smokes while the building works.
local function chimney(x, y, running, time)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 4, y + 4, 12)
  love.graphics.setColor(0.55, 0.3, 0.24)
  love.graphics.circle("fill", x, y, 12)
  love.graphics.setColor(0.42, 0.22, 0.18)
  love.graphics.circle("line", x, y, 9)
  love.graphics.setColor(0.1, 0.1, 0.1)
  love.graphics.circle("fill", x, y, 6)
  if running then
    for i = 0, 3 do
      local t = (time * 0.5 + i / 4) % 1
      love.graphics.setColor(0.82, 0.82, 0.82, 0.55 * (1 - t))
      love.graphics.circle("fill", x + t * 34, y - t * 44, 6 + t * 14)
    end
  end
end

--- The place's name on a dark plate with a coloured rim, centred on (cx, cy).
local function namePlate(cx, cy, text, color, font)
  font = font or UI.fonts.small
  local tw, th = font:getWidth(text) + 16, font:getHeight() + 4
  local x, y = math.floor(cx - tw / 2), math.floor(cy - th / 2)
  love.graphics.setColor(0.06, 0.06, 0.08, 0.88)
  love.graphics.rectangle("fill", x, y, tw, th, 4)
  love.graphics.setColor(color[1], color[2], color[3], 0.85)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, tw, th, 4)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(font)
  love.graphics.setColor(color)
  love.graphics.printf(text, x, y + 2, tw, "center")
end

--- Diagonal yellow and black stripes filling (x, y, w, h).
local function hazard(x, y, w, h)
  box(x, y, w, h, { 0.12, 0.12, 0.12 })
  love.graphics.setColor(HAZARD)
  -- Clamped at the right-hand end rather than cut with a scissor, which
  -- would ignore the camera.
  local right = x + w
  for i = 0, w - 6, 10 do
    local x0 = x + i
    love.graphics.polygon("fill", x0, y + h, x0 + 5, y + h, math.min(right, x0 + 5 + h), y, math.min(right, x0 + h), y)
  end
end

--- A roll-up door in a front wall whose bottom edge is at y, `open` (0..1)
--- raised that far, with a light over it and a striped apron in front.
local function rollerDoor(x, y, w, open, lit)
  local h = 12
  box(x - 3, y - h - 3, w + 6, h + 3, { 0.2, 0.2, 0.22 })
  box(x, y - h, w, h, { 0.08, 0.08, 0.09 })
  if open > 0 then
    box(x + 2, y - h, w - 4, h, { 1, 0.85, 0.5 }, 0.25 * open)
  end
  local shut = h * (1 - open)
  box(x, y - h, w, shut, { 0.66, 0.67, 0.68 })
  love.graphics.setColor(0.5, 0.51, 0.52)
  for ly = y - h + 3, y - h + shut - 1, 3 do
    love.graphics.line(x + 1, ly, x + w - 1, ly)
  end
  hazard(x, y + 1, w, 5)
  love.graphics.setColor(1, 0.9, 0.55, lit and 0.9 or 0.35)
  love.graphics.rectangle("fill", x + w / 2 - 4, y - h - 6, 8, 3)
end

--- A crate on a wooden pallet, top-left at (x, y), 18 px square.
local function pallet(x, y, c)
  box(x + 3, y + 3, 18, 18, { 0, 0, 0 }, 0.3)
  box(x, y, 18, 18, { 0.6, 0.45, 0.28 })
  box(x + 2, y + 2, 14, 14, c)
  love.graphics.setColor(shade(c, 0.6))
  love.graphics.rectangle("line", x + 2, y + 2, 14, 14)
  love.graphics.line(x + 2, y + 2, x + 16, y + 16)
  love.graphics.line(x + 16, y + 2, x + 2, y + 16)
end

--- A steel drum from above, centred on (x, y).
local function barrel(x, y, c)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, 7)
  love.graphics.setColor(c)
  love.graphics.circle("fill", x, y, 7)
  love.graphics.setColor(shade(c, 1.8))
  love.graphics.circle("line", x, y, 5)
  love.graphics.circle("fill", x + 2, y - 2, 1.5)
end

--- A forklift from above, centred on (x, y), forks along `angle`.
local function forklift(x, y, angle, load)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  box(-9 + 2, -7 + 2, 18, 14, { 0, 0, 0 }, 0.3)
  box(9, -5, 10, 2, { 0.25, 0.25, 0.25 })
  box(9, 3, 10, 2, { 0.25, 0.25, 0.25 })
  if load then
    box(10, -6, 12, 12, load)
  end
  box(-9, -7, 18, 14, HAZARD)
  box(-7, -5, 9, 10, { 0.18, 0.18, 0.2 })
  box(6, -7, 3, 14, { 0.3, 0.3, 0.32 })
  love.graphics.pop()
end

--- A factory's silo for one material, centred on (x, y), radius `rad`: a
--- round steel bin with a hatch, and a ring round it in the material's
--- colour as full as the hopper. `a` fades one the product in hand doesn't use.
local function silo(x, y, rad, fill, c, a)
  love.graphics.setColor(0, 0, 0, 0.3 * a)
  love.graphics.circle("fill", x + 4, y + 4, rad)
  love.graphics.setColor(0.72, 0.74, 0.76, a)
  love.graphics.circle("fill", x, y, rad)
  love.graphics.setColor(0.86, 0.88, 0.9, a)
  love.graphics.circle("fill", x - rad * 0.2, y - rad * 0.2, rad * 0.62)
  love.graphics.setColor(0.5, 0.52, 0.55, a)
  love.graphics.circle("fill", x, y, rad * 0.28)
  love.graphics.setColor(0.2, 0.2, 0.22, a)
  love.graphics.setLineWidth(4)
  love.graphics.circle("line", x, y, rad + 3)
  if fill > 0 then
    love.graphics.setColor(c[1], c[2], c[3], a)
    love.graphics.arc("line", "open", x, y, rad + 3, -math.pi / 2, -math.pi / 2 + fill * 2 * math.pi, 24)
  end
  love.graphics.setLineWidth(1)
end

--- Concrete slabs: a fill and the joints every `step` px.
local function slabs(x, y, w, h, c, step)
  box(x, y, w, h, c)
  love.graphics.setColor(shade(c, 0.88))
  for sx = x + step, x + w - 1, step do
    love.graphics.line(sx, y, sx, y + h)
  end
  for sy = y + step, y + h - 1, step do
    love.graphics.line(x, sy, x + w, sy)
  end
end

-- Parking lot ------------------------------------------------------------------

local function parking(b, r, time)
  box(r.x, r.y, r.w, r.h, { 0.62, 0.62, 0.6 }) -- the kerb all round
  box(r.x + 4, r.y + 4, r.w - 8, r.h - 8, { 0.2, 0.2, 0.22 })
  -- Worn patches in the tarmac.
  for i = 1, 6 do
    love.graphics.setColor(0.24, 0.24, 0.26)
    love.graphics.ellipse("fill", r.x + 20 + hash(i) * (r.w - 40), r.y + 20 + hash(i + 9) * (r.h - 40),
      14 + hash(i + 3) * 20, 8 + hash(i + 5) * 10)
  end
  local depth = math.min(70, r.h * 0.3)
  local bays = math.max(3, math.floor((r.w - 16) / 40))
  local bw = (r.w - 16) / bays
  local gate = math.floor(bays / 2) -- the bottom row leaves a gap here for the way in
  love.graphics.setColor(0.92, 0.92, 0.88, 0.85)
  love.graphics.setLineWidth(2)
  for i = 0, bays do
    local x = r.x + 8 + i * bw
    love.graphics.line(x, r.y + 6, x, r.y + 6 + depth)
    if i ~= gate and i ~= gate + 1 then
      love.graphics.line(x, r.y + r.h - 6, x, r.y + r.h - 6 - depth)
    end
  end
  love.graphics.setLineWidth(1)
  -- Arrows painted along the aisle.
  local my = r.y + r.h / 2
  love.graphics.setColor(0.92, 0.92, 0.88, 0.6)
  for x = r.x + 40, r.x + r.w - 40, 80 do
    love.graphics.polygon("fill", x, my - 3, x + 16, my - 3, x + 16, my - 8, x + 26, my, x + 16, my + 8, x + 16, my + 3,
      x, my + 3)
  end
  -- Cars in some of the bays, nose in.
  local list = Catalog.list
  if #list > 0 then
    for i = 0, bays - 1 do
      local x = r.x + 8 + (i + 0.5) * bw
      local length = math.min(depth - 8, bw * 1.6)
      if hash(i + 20) < 0.55 then
        Catalog.draw(list[1 + math.floor(hash(i + 40) * math.min(#list, 6))], x, r.y + 6 + depth / 2, -math.pi / 2,
          length)
      end
      if (i < gate - 1 or i > gate + 1) and hash(i + 60) < 0.45 then
        Catalog.draw(list[1 + math.floor(hash(i + 80) * math.min(#list, 6))], x, r.y + r.h - 6 - depth / 2,
          math.pi / 2, length)
      end
    end
  end
  -- The ticket booth by the way in, its barrier lifting now and then.
  local gx = r.x + 8 + (gate + 2) * bw - 16
  local by = r.y + r.h - 30
  box(gx - 12 + 3, by - 12 + 3, 24, 24, { 0, 0, 0 }, 0.3)
  box(gx - 12, by - 12, 24, 24, { 0.9, 0.9, 0.88 })
  box(gx - 12, by - 12, 24, 5, { 0.15, 0.35, 0.8 })
  box(gx - 8, by - 2, 16, 6, GLASS, 0.9)
  local lift = math.max(0, math.sin(time * 0.8)) ^ 3
  love.graphics.push()
  love.graphics.translate(gx - 12, by + 4)
  love.graphics.rotate(math.pi + lift * 1.3)
  box(0, -2, bw * 3 - 30, 4, { 0.95, 0.95, 0.95 })
  for sx = 6, bw * 3 - 36, 12 do
    box(sx, -2, 6, 4, { 0.85, 0.15, 0.15 })
  end
  love.graphics.pop()
  -- The P sign on its post in the back corner.
  local px, py = r.x + r.w - 30, r.y + depth + 20
  box(px - 14 + 4, py - 14 + 4, 28, 28, { 0, 0, 0 }, 0.3)
  love.graphics.setColor(0.15, 0.35, 0.8)
  love.graphics.rectangle("fill", px - 14, py - 14, 28, 28, 4)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", px - 11, py - 11, 22, 22, 3)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.body)
  love.graphics.printf("P", px - 14, py - UI.fonts.body:getHeight() / 2, 28, "center")
  -- The takings: stacks of koins by the booth, one per ten.
  local stacks = math.min(10, math.ceil(b.output / 10))
  for i = 0, stacks - 1 do
    local kx = gx - 6 - (i % 5) * 12
    local ky = by - 26 - math.floor(i / 5) * 12
    love.graphics.setColor(0.6, 0.45, 0.05)
    love.graphics.circle("fill", kx, ky, 5)
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.circle("fill", kx, ky - 2, 5)
  end
end

-- Quarry -------------------------------------------------------------------------

local DUMP_TRUCK = "mining-dump-truck-yellow"

--- A heap of `c` centred on (x, y), `s` px across.
local function pile(x, y, s, c)
  love.graphics.setColor(0, 0, 0, 0.25)
  love.graphics.ellipse("fill", x + 3, y + 4, s * 0.55, s * 0.42)
  love.graphics.setColor(shade(c, 0.65))
  love.graphics.ellipse("fill", x, y, s * 0.55, s * 0.42)
  love.graphics.setColor(c)
  love.graphics.ellipse("fill", x - s * 0.08, y - s * 0.08, s * 0.38, s * 0.28)
  love.graphics.setColor(shade(c, 1.3))
  love.graphics.ellipse("fill", x - s * 0.16, y - s * 0.14, s * 0.14, s * 0.1)
end

local function quarry(b, kind, r, time)
  local ground = { 0.62, 0.5, 0.36 }
  box(r.x, r.y, r.w, r.h, ground)
  for i = 1, 40 do
    love.graphics.setColor(shade(ground, 0.8 + hash(i) * 0.35))
    love.graphics.circle("fill", r.x + hash(i + 100) * r.w, r.y + hash(i + 200) * r.h, 1.5 + hash(i + 300) * 2)
  end
  local pileW = math.min(60, r.w * 0.22)
  -- The pit: terraces stepping down, each lit on its far rim.
  local cx, cy = r.x + (r.w - pileW) * 0.46, r.y + r.h * 0.44
  local rx, ry = (r.w - pileW) * 0.4, r.h * 0.36
  for i = 0, 4 do
    local s = 1 - i * 0.19
    local c = shade(ground, 0.92 - i * 0.12)
    love.graphics.setColor(shade(c, 1.2))
    love.graphics.ellipse("fill", cx - 2, cy - 2, rx * s, ry * s)
    love.graphics.setColor(c)
    love.graphics.ellipse("fill", cx + 1, cy + 1, rx * s - 2, ry * s - 2)
  end
  love.graphics.setColor(0.3, 0.38, 0.42, 0.8) -- a puddle at the bottom
  love.graphics.ellipse("fill", cx + rx * 0.08, cy + ry * 0.06, rx * 0.14, ry * 0.1)
  -- The haul road climbing out of the pit towards the front.
  local road = { cx, cy + ry * 0.3, cx + rx * 0.5, cy + ry * 0.55, cx + rx * 0.35, cy + ry * 0.95,
    cx - rx * 0.1, r.y + r.h - 16 }
  love.graphics.setColor(shade(ground, 1.12))
  love.graphics.setLineWidth(12)
  love.graphics.line(road)
  love.graphics.setLineWidth(1)
  -- A digger in the pit, its arm swinging while it works.
  local a = b.running and math.sin(time * 2) * 0.6 or 0
  local dx, dy = cx - rx * 0.2, cy - ry * 0.05
  box(dx - 12, dy - 12, 5, 24, { 0.18, 0.18, 0.18 })
  box(dx + 7, dy - 12, 5, 24, { 0.18, 0.18, 0.18 })
  love.graphics.setColor(HAZARD)
  love.graphics.rectangle("fill", dx - 8, dy - 9, 16, 18, 2)
  box(dx - 6, dy - 7, 6, 6, GLASS)
  love.graphics.setColor(0.85, 0.62, 0.1)
  love.graphics.setLineWidth(5)
  love.graphics.line(dx, dy, dx + math.cos(a - 0.6) * 30, dy + math.sin(a - 0.6) * 30)
  love.graphics.setLineWidth(1)
  box(dx + math.cos(a - 0.6) * 30 - 4, dy + math.sin(a - 0.6) * 30 - 4, 8, 8, { 0.3, 0.3, 0.3 })
  -- A conveyor from the pit's rim up to the piles, its belt moving with the work.
  local x1, y1 = cx + rx * 0.75, cy - ry * 0.3
  local x2 = r.x + r.w - pileW - 4
  box(x1, y1 - 4, x2 - x1, 8, { 0.3, 0.3, 0.32 })
  love.graphics.setColor(0.15, 0.15, 0.16)
  local shift = b.running and (time * 30) % 10 or 0
  for x = x1 + shift, x2 - 4, 10 do
    love.graphics.rectangle("fill", x, y1 - 3, 4, 6)
  end
  -- A pile of each material along the side; the one being dug grows.
  local n = #kind.products
  for i, m in ipairs(kind.products) do
    local py = r.y + 14 + (r.h - 60) * (i - 0.5) / n
    local size = i == b.product and 26 + math.min(22, b.output * 0.5) or 22
    pile(r.x + r.w - pileW / 2 - 4, py, math.min(size, pileW + 8), COLORS[m])
  end
  -- The site office by the gate.
  local ox, oy = r.x + 12, r.y + r.h - 34
  box(ox + 3, oy + 3, 46, 24, { 0, 0, 0 }, 0.3)
  box(ox, oy, 46, 24, { 0.92, 0.92, 0.88 })
  love.graphics.setColor(0.8, 0.8, 0.76)
  for x = ox + 6, ox + 40, 6 do
    love.graphics.line(x, oy + 2, x, oy + 22)
  end
  box(ox + 6, oy + 17, 10, 5, GLASS)
  box(ox + 28, oy + 17, 10, 5, GLASS)
  -- The dump truck, running loads from the pit to the piles while it works.
  local truck = Catalog.byKey[DUMP_TRUCK]
  if truck then
    local p = b.running and (time * 0.12) % 1 or 0.25
    local k = p < 0.5 and p * 2 or (1 - p) * 2
    local tx, ty = cx + rx * 0.5 + k * (x2 - cx - rx * 0.5 - 20), cy + ry * 0.55 - k * (ry * 0.85)
    Catalog.draw(truck, tx, ty, p < 0.5 and -0.6 or math.pi - 0.6, 46)
  end
end

-- Oil well -------------------------------------------------------------------------

--- A storage tank from above, centred on (x, y): a white drum with a ring,
--- a hatch and a ladder winding up it, a band in `band` colour.
local function tank(x, y, rad, band)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 5, y + 5, rad)
  love.graphics.setColor(0.8, 0.8, 0.78)
  love.graphics.circle("fill", x, y, rad)
  love.graphics.setColor(0.9, 0.9, 0.88)
  love.graphics.circle("fill", x - rad * 0.15, y - rad * 0.15, rad * 0.75)
  love.graphics.setColor(band)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", x, y, rad - 2)
  love.graphics.setColor(0.55, 0.55, 0.53)
  love.graphics.setLineWidth(1)
  love.graphics.circle("line", x, y, rad * 0.5)
  love.graphics.circle("fill", x + rad * 0.3, y - rad * 0.3, 3)
  love.graphics.setColor(0.4, 0.4, 0.42)
  love.graphics.setLineWidth(2)
  love.graphics.arc("line", "open", x, y, rad + 3, 0.2, 1.3, 10)
  love.graphics.setLineWidth(1)
end

local function oilWell(b, kind, r, time)
  local ground = { 0.46, 0.42, 0.34 }
  box(r.x, r.y, r.w, r.h, ground)
  for i = 1, 50 do
    love.graphics.setColor(shade(ground, 0.8 + hash(i + 7) * 0.4))
    love.graphics.circle("fill", r.x + hash(i + 500) * r.w, r.y + hash(i + 600) * r.h, 1.5)
  end
  local item = kind.products[b.product]
  local plastic = item == "plastic"
  -- The pad the pumpjack stands on, and oil spilt round the wellhead.
  local wx, wy = r.x + r.w * 0.34, r.y + r.h * 0.42
  local padX = math.max(r.x + 4, wx - 70)
  slabs(padX, wy - 30, wx + 50 - padX, 60, CONCRETE, 30)
  love.graphics.setColor(0.08, 0.07, 0.08, 0.5)
  love.graphics.ellipse("fill", wx - 52, wy + 8, 16, 11)
  -- The pumpjack: a skid, the samson post, the walking beam nodding on it,
  -- the horsehead over the well and the crank turning its weights.
  local turn = b.running and time * 2.4 or 0
  local a = math.sin(turn) * 0.28
  box(wx - 40, wy + 12, 80, 8, { 0.3, 0.3, 0.32 })
  love.graphics.setColor(0.35, 0.35, 0.38)
  love.graphics.polygon("fill", wx - 8, wy + 16, wx + 8, wy + 16, wx, wy - 4)
  love.graphics.setColor(0.2, 0.2, 0.22)
  love.graphics.circle("fill", wx + 26, wy + 6, 7)
  love.graphics.setColor(0.72, 0.18, 0.15)
  love.graphics.circle("fill", wx + 26 + math.cos(turn) * 9, wy + 6 + math.sin(turn) * 9, 7)
  love.graphics.push()
  love.graphics.translate(wx, wy - 4)
  love.graphics.rotate(a)
  box(-44, -4, 72, 8, HAZARD)
  box(-44, -4, 72, 2, shade(HAZARD, 1.15))
  love.graphics.setColor(0.2, 0.2, 0.22)
  love.graphics.arc("fill", "pie", -46, 0, 11, math.pi * 0.5, math.pi * 1.5, 10) -- horsehead
  box(22, -7, 12, 14, { 0.25, 0.25, 0.27 })
  love.graphics.pop()
  -- The bridle down to the wellhead.
  local hx = wx - 57 * math.cos(a)
  love.graphics.setColor(0.15, 0.15, 0.15)
  love.graphics.line(hx, wy - 4 - 46 * math.sin(a), wx - 52, wy + 8)
  love.graphics.setColor(0.35, 0.35, 0.38)
  love.graphics.circle("fill", wx - 52, wy + 8, 5)
  -- Tanks down the side, piped from the wellhead; plastic comes from a
  -- refinery drum beside them.
  local tr = math.min(r.w, r.h) * 0.13
  local tx = r.x + r.w - tr - 14
  local t1, t2 = r.y + tr + 14, r.y + tr * 3 + 26
  love.graphics.setColor(0.4, 0.4, 0.42)
  love.graphics.setLineWidth(3)
  love.graphics.line(wx - 52, wy + 8, wx - 52, wy + 34, tx - tr - 8, wy + 34, tx - tr - 8, t1, tx - tr, t1)
  love.graphics.line(tx - tr - 8, t2, tx - tr, t2)
  love.graphics.setLineWidth(1)
  tank(tx, t1, tr, COLORS.oil)
  tank(tx, t2, tr, plastic and COLORS.plastic or COLORS.oil)
  if plastic then
    local rx, ry = tx - tr * 2 - 18, t2
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.circle("fill", rx + 4, ry + 4, 10)
    love.graphics.setColor(0.6, 0.62, 0.64)
    love.graphics.circle("fill", rx, ry, 10)
    love.graphics.setColor(COLORS.plastic)
    love.graphics.circle("fill", rx, ry, 5)
  end
  -- A flare stack in the back corner that burns while it pumps.
  local fx, fy = r.x + 18, r.y + 18
  love.graphics.setColor(0.3, 0.3, 0.32)
  love.graphics.circle("fill", fx, fy, 6)
  if b.running then
    local flick = 0.7 + 0.3 * math.sin(time * 17)
    love.graphics.setColor(1, 0.5, 0.1, 0.25)
    love.graphics.circle("fill", fx, fy, 16 * flick)
    love.graphics.setColor(1, 0.55, 0.1, 0.85)
    love.graphics.circle("fill", fx, fy, 8 * flick)
    love.graphics.setColor(1, 0.95, 0.5)
    love.graphics.circle("fill", fx, fy, 3 * flick)
  end
  -- What is waiting to be collected by the gate: drums of oil, bales of plastic.
  local units = math.min(12, math.floor(b.output / Kinds.recipe(kind, b.product).unit))
  for i = 0, units - 1 do
    local x, y = r.x + 22 + (i % 6) * 17, r.y + r.h - 16 - math.floor(i / 6) * 17
    if plastic then
      box(x - 7 + 2, y - 6 + 2, 14, 12, { 0, 0, 0 }, 0.3)
      box(x - 7, y - 6, 14, 12, COLORS.plastic)
      love.graphics.setColor(shade(COLORS.plastic, 0.7))
      love.graphics.line(x - 7, y, x + 7, y)
    else
      barrel(x, y, { 0.2, 0.2, 0.24 })
    end
  end
end

-- Factories ------------------------------------------------------------------------

--- The emblem painted on a factory roof, about 50 px across at scale 1.
local function emblem(key, cx, cy)
  if key == "ammo" then
    for i = -1, 1 do
      local x = cx + i * 18
      love.graphics.setColor(0.8, 0.6, 0.2)
      love.graphics.rectangle("fill", x - 5, cy - 6, 10, 22)
      love.graphics.setColor(0.7, 0.45, 0.2)
      love.graphics.polygon("fill", x - 5, cy - 6, x + 5, cy - 6, x, cy - 18)
    end
  elseif key == "weapons" then
    love.graphics.setColor(0.15, 0.15, 0.17)
    love.graphics.rectangle("fill", cx - 26, cy - 8, 52, 12)
    love.graphics.rectangle("fill", cx + 8, cy + 2, 12, 18)
    love.graphics.rectangle("fill", cx - 6, cy + 2, 6, 10)
  elseif key == "health" then
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", cx - 12, cy - 28, 24, 56)
    love.graphics.rectangle("fill", cx - 28, cy - 12, 56, 24)
    love.graphics.setColor(0.85, 0.12, 0.12)
    love.graphics.rectangle("fill", cx - 8, cy - 24, 16, 48)
    love.graphics.rectangle("fill", cx - 24, cy - 8, 48, 16)
  elseif key == "vehicles" then
    -- A steering wheel.
    love.graphics.setColor(0.15, 0.15, 0.17)
    love.graphics.setLineWidth(6)
    love.graphics.circle("line", cx, cy, 20)
    love.graphics.line(cx - 20, cy, cx + 20, cy)
    love.graphics.line(cx, cy, cx, cy + 20)
    love.graphics.setLineWidth(1)
    love.graphics.circle("fill", cx, cy, 6)
  end
end

-- Each factory's look: its roof, the plate over the doors and its colour,
-- the disc its emblem is painted on, and its crates.
local FACTORIES = {
  ammo = { roof = { 0.45, 0.42, 0.35 }, name = "AMMO", accent = { 0.95, 0.7, 0.25 }, disc = { 0.3, 0.28, 0.24 },
    crate = { 0.45, 0.5, 0.25 } },
  weapons = { roof = { 0.3, 0.32, 0.36 }, name = "ARMS", accent = { 0.95, 0.35, 0.3 }, disc = { 0.6, 0.62, 0.66 },
    crate = { 0.35, 0.3, 0.25 } },
  health = { roof = { 0.93, 0.94, 0.95 }, name = "MEDICAL", accent = { 0.9, 0.15, 0.16 },
    crate = { 0.95, 0.95, 0.95 } },
  vehicles = { roof = { 0.7, 0.3, 0.22 }, name = "MOTORS", accent = { 0.95, 0.8, 0.3 }, disc = { 0.9, 0.88, 0.84 },
    crate = { 0.5, 0.5, 0.5 } },
}

--- Where a building of `kind` inside `r` has its hall (x, y, w, h), and
--- how wide the column of silos beside it is: the same for the building
--- and for its ruin.
local function hallOf(kind, r)
  if kind.service then -- the garage: the whole width, an apron in front
    return r.x + 6, r.y + 6, r.w - 12, r.h - math.min(46, r.h * 0.3) - 6, 0
  end
  local siloW = #Kinds.hopperList(kind) > 0 and math.min(56, r.w * 0.2) or 0
  return r.x + 12, r.y + 12, r.w - 24 - (siloW > 0 and siloW + 12 or 0), math.floor(r.h * 0.58), siloW
end

local function factory(b, kind, r, time)
  local look = FACTORIES[kind.key] or FACTORIES.ammo
  local list = Kinds.hopperList(kind)
  slabs(r.x, r.y, r.w, r.h, CONCRETE, 32)
  box(r.x, r.y, r.w, 3, shade(CONCRETE, 1.15))
  box(r.x, r.y, 3, r.h, shade(CONCRETE, 1.15))

  -- The hall, with room down the right for the silos.
  local hx, hy, hw, hh, siloW = hallOf(kind, r)
  roof(hx, hy, hw, hh, look.roof)
  -- Skylights along the back, the units beside them and the chimney.
  local n = math.max(2, math.floor((hw - 90) / 44))
  skylights(hx + 40, hy + 12, hw - 110, 14, n)
  aircon(hx + 22, hy + 22, time)
  aircon(hx + 22, hy + 48, time * 0.8 + 1)
  chimney(hx + hw - 26, hy + 24, b.running, time)
  -- The emblem on a disc, and the name on a plate over the doors.
  -- Between the skylights and the plate, as big as fits.
  local s = math.max(0.4, math.min(1, (hh - 72) / 72, (hw - 80) / 100))
  local ex, ey = hx + hw / 2, hy + (30 + hh - 42) / 2
  if look.disc then
    love.graphics.setColor(look.disc)
    love.graphics.circle("fill", ex, ey, 34 * s)
    love.graphics.setColor(shade(look.disc, 0.75))
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", ex, ey, 34 * s)
    love.graphics.setLineWidth(1)
  end
  love.graphics.push()
  love.graphics.translate(ex, ey)
  love.graphics.scale(s)
  emblem(kind.key, 0, 0)
  love.graphics.pop()
  namePlate(ex, hy + hh - 30, look.name, look.accent)
  -- The loading dock along the front: doors, open while a batch is on.
  local front = hy + hh
  local doors = math.max(2, math.min(4, math.floor(hw / 70)))
  local dw = math.min(44, (hw - 30) / doors - 10)
  local gap = (hw - doors * dw) / (doors + 1)
  for i = 0, doors - 1 do
    local open = b.running and (i == 0 and 1 or 0.25) or 0
    rollerDoor(hx + gap + i * (dw + gap), front, dw, open, b.running)
  end

  -- The silos down the side, piped into the hall: one per material, faded
  -- when the product in hand doesn't use it.
  if #list > 0 then
    local inputs = Kinds.recipe(kind, b.product).inputs
    local pitch = math.min(siloW + 6, (r.h - 24) / #list)
    local rad = math.max(8, math.min(siloW / 2 - 4, pitch / 2 - 5))
    local sx = r.x + r.w - 12 - siloW / 2
    for i, m in ipairs(list) do
      local sy = r.y + 12 + (i - 0.5) * pitch
      love.graphics.setColor(0.4, 0.4, 0.42)
      love.graphics.setLineWidth(3)
      love.graphics.line(sx - rad, sy, hx + hw + 2, sy)
      love.graphics.setLineWidth(1)
      silo(sx, sy, rad, (b.hopper[m] or 0) / Kinds.HOPPER, COLORS[m], inputs[m] and 1 or 0.35)
    end
  end

  -- The yard: what is waiting to be collected, the cars themselves parked
  -- in painted bays or crates on pallets, and a forklift at work.
  local units = math.floor(b.output / Kinds.recipe(kind, b.product).unit)
  local model = Catalog.fromItem(kind.products[b.product])
  local yardY = front + 12
  local yardH = r.y + r.h - yardY
  if model then
    local bay = 32
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.setLineWidth(2)
    for i = 0, kind.cap do
      local x = r.x + 16 + i * bay
      love.graphics.line(x, r.y + r.h - 6, x, r.y + r.h - 6 - math.min(44, yardH - 4))
    end
    love.graphics.setLineWidth(1)
    for i = 0, math.min(units, kind.cap) - 1 do
      Catalog.draw(model, r.x + 16 + (i + 0.5) * bay, r.y + r.h - 6 - math.min(44, yardH - 4) / 2, -math.pi / 2,
        math.min(40, yardH - 8))
    end
  else
    for i = 0, math.min(units, 12) - 1 do
      pallet(r.x + 16 + (i % 6) * 22, r.y + r.h - 26 - math.floor(i / 6) * 22, look.crate)
    end
  end
  -- The forklift runs between the open door and the yard while the work goes on.
  if not model then
    local fx0, fx1 = hx + gap + dw / 2, r.x + r.w * 0.62
    local p = b.running and (time * 0.25) % 1 or 0
    local k = p < 0.5 and p * 2 or (1 - p) * 2
    local fy = yardY + math.min(24, yardH * 0.35)
    forklift(fx0 + (fx1 - fx0) * k, fy, p < 0.5 and 0 or math.pi, b.running and p >= 0.5 and look.crate or nil)
  end
end

-- The pieces, for a feature that draws a building kind of its own (the
-- garage, `service` in kinds.lua) in the same look.
Render.parts = {
  roof = roof, aircon = aircon, skylights = skylights, namePlate = namePlate, rollerDoor = rollerDoor,
  slabs = slabs, hazard = hazard, shade = shade,
}

local ROOFS = {
  vehicles = FACTORIES.vehicles.roof,
  ammo = FACTORIES.ammo.roof,
  weapons = FACTORIES.weapons.roof,
  health = FACTORIES.health.roof,
  garage = { 0.52, 0.54, 0.57 },
}
local YARDS = {
  parking = { 0.2, 0.2, 0.22 },
  quarry = { 0.62, 0.5, 0.36 },
  oil = { 0.42, 0.38, 0.3 },
}

--- A building's mark on the big map, centred on (cx, cy), about `size` px
--- across: a disc in its colour with its sign on it (the P, a heap, a drum,
--- its roof emblem, a roll-up door), or a red cross over a dark one for a ruin.
function Render.mapMark(kind, cx, cy, size, isRuin)
  local rad = size / 2
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.circle("fill", cx, cy, rad + 1.5)
  if isRuin then
    love.graphics.setColor(0.22, 0.2, 0.19)
    love.graphics.circle("fill", cx, cy, rad)
    love.graphics.setColor(1, 0.35, 0.3)
    love.graphics.setLineWidth(2)
    love.graphics.line(cx - rad * 0.45, cy - rad * 0.45, cx + rad * 0.45, cy + rad * 0.45)
    love.graphics.line(cx - rad * 0.45, cy + rad * 0.45, cx + rad * 0.45, cy - rad * 0.45)
    love.graphics.setLineWidth(1)
    return
  end
  local look = FACTORIES[kind.key]
  local c = kind.key == "parking" and { 0.15, 0.35, 0.8 } or (look and (look.disc or look.roof))
    or Render.rubbleColor(kind)
  love.graphics.setColor(c)
  love.graphics.circle("fill", cx, cy, rad)
  love.graphics.push()
  love.graphics.translate(cx, cy)
  local k = size / 64 -- the signs are drawn about 50 px across
  love.graphics.scale(k)
  if kind.key == "parking" then
    love.graphics.scale(1 / k)
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("P", -rad, -UI.fonts.small:getHeight() / 2, size, "center")
  elseif kind.key == "quarry" then
    pile(-6, 6, 30, COLORS.iron)
    pile(10, 2, 24, COLORS.copper)
  elseif kind.key == "oil" then
    love.graphics.setColor(0.1, 0.1, 0.12)
    love.graphics.circle("fill", 0, 6, 14)
    love.graphics.polygon("fill", -12, 0, 12, 0, 0, -22)
  elseif kind.service and Features.byName[kind.service] and Features.byName[kind.service].drawMapMark then
    Features.byName[kind.service]:drawMapMark()
  elseif kind.service then
    box(-20, -16, 40, 32, { 0.72, 0.62, 0.3 })
    love.graphics.setColor(0.5, 0.42, 0.18)
    love.graphics.setLineWidth(3)
    for y = -10, 12, 7 do
      love.graphics.line(-18, y, 18, y)
    end
    love.graphics.setLineWidth(1)
  else
    emblem(kind.key, 0, 0)
  end
  love.graphics.pop()
end

--- A small picture of an item, centred on (cx, cy), for the inventory.
function Render.itemIcon(item, cx, cy)
  item = Tiers.base(item) -- every tier looks the same; the box around it says which
  local c = COLORS[item]
  if item == "oil" then
    -- A barrel.
    love.graphics.setColor(0.2, 0.2, 0.24)
    love.graphics.rectangle("fill", cx - 9, cy - 12, 18, 24, 3)
    love.graphics.setColor(0.55, 0.5, 0.2)
    love.graphics.rectangle("fill", cx - 9, cy - 5, 18, 3)
    love.graphics.rectangle("fill", cx - 9, cy + 4, 18, 3)
  elseif item == "plastic" then
    -- A stack of sheets.
    for i = 0, 2 do
      love.graphics.setColor(c[1] * (0.7 + i * 0.15), c[2] * (0.7 + i * 0.15), c[3] * (0.7 + i * 0.15))
      love.graphics.rectangle("fill", cx - 12 + i * 2, cy + 6 - i * 6, 22, 5, 2)
    end
  elseif item == "ammo-rocket" then
    for i = -1, 1, 2 do
      local x = cx + i * 7
      love.graphics.setColor(0.4, 0.45, 0.3)
      love.graphics.rectangle("fill", x - 3, cy - 8, 6, 18)
      love.graphics.setColor(0.85, 0.2, 0.15)
      love.graphics.polygon("fill", x - 3, cy - 8, x + 3, cy - 8, x, cy - 14)
      love.graphics.setColor(0.3, 0.3, 0.3)
      love.graphics.polygon("fill", x - 3, cy + 10, x - 6, cy + 13, x - 3, cy + 6)
      love.graphics.polygon("fill", x + 3, cy + 10, x + 6, cy + 13, x + 3, cy + 6)
    end
  elseif c then
    -- A heap of ore.
    love.graphics.setColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6)
    love.graphics.circle("fill", cx - 6, cy + 4, 9)
    love.graphics.circle("fill", cx + 7, cy + 5, 8)
    love.graphics.setColor(c)
    love.graphics.circle("fill", cx, cy - 2, 10)
  elseif item == "ammo-shotgun" then
    -- Shells: red tubes with brass heads.
    for i = -1, 1 do
      local x = cx + i * 9
      love.graphics.setColor(0.8, 0.15, 0.12)
      love.graphics.rectangle("fill", x - 3, cy - 11, 6, 15, 1)
      love.graphics.setColor(0.8, 0.6, 0.2)
      love.graphics.rectangle("fill", x - 3, cy + 4, 6, 6)
    end
  elseif item == "ammo-flamethrower" then
    -- A jerry can: red, a handle across the top, the spout at a corner.
    love.graphics.setColor(0.8, 0.15, 0.12)
    love.graphics.rectangle("fill", cx - 10, cy - 9, 20, 22, 2)
    love.graphics.setColor(0.6, 0.1, 0.08)
    love.graphics.line(cx - 8, cy - 7, cx + 8, cy + 11)
    love.graphics.line(cx + 8, cy - 7, cx - 8, cy + 11)
    love.graphics.setColor(0.25, 0.25, 0.28)
    love.graphics.rectangle("fill", cx - 6, cy - 14, 9, 4, 1) -- handle
    love.graphics.rectangle("fill", cx + 5, cy - 14, 4, 6) -- spout
  elseif item:match("^ammo%-") then
    for i = -1, 1 do
      local x = cx + i * 9
      love.graphics.setColor(0.8, 0.6, 0.2)
      love.graphics.rectangle("fill", x - 3, cy - 4, 6, 14)
      love.graphics.setColor(0.7, 0.45, 0.2)
      love.graphics.polygon("fill", x - 3, cy - 4, x + 3, cy - 4, x, cy - 11)
    end
  elseif item:match("^gun%-") then
    -- The same drawing the inventory's weapon slots use, at item size.
    Icons.draw(item:sub(5), cx, cy, 0.6)
  elseif item:match("^ability%-") then
    Render.abilityIcon(item:sub(9), cx, cy, 15)
  elseif item:match("^gear%-") then
    -- Clothes: each piece its own drawing, in its colour (gear/icons.lua).
    require("src.features.gear.icons").draw(item:sub(6), cx, cy)
  elseif item:match("^armor%-") then
    require("src.features.armor.icons").draw(item:sub(7), cx, cy)
  elseif item == "drink" then
    -- A can with a bolt on it.
    love.graphics.setColor(0.2, 0.5, 0.9)
    love.graphics.rectangle("fill", cx - 7, cy - 12, 14, 24, 3)
    love.graphics.setColor(0.78, 0.8, 0.85)
    love.graphics.rectangle("fill", cx - 7, cy - 12, 14, 4, 2)
    love.graphics.setColor(1, 0.9, 0.2)
    love.graphics.polygon("fill", cx + 1, cy - 6, cx - 4, cy + 1, cx, cy + 1, cx - 2, cy + 8, cx + 4, cy - 1,
      cx, cy - 1)
  elseif item == "grenade" then
    Render.grenade(cx, cy + 2, 1)
  elseif item == "medkit" then
    love.graphics.setColor(0.95, 0.95, 0.95)
    love.graphics.rectangle("fill", cx - 12, cy - 10, 24, 20, 3)
    love.graphics.setColor(0.85, 0.12, 0.12)
    love.graphics.rectangle("fill", cx - 3, cy - 7, 6, 14)
    love.graphics.rectangle("fill", cx - 7, cy - 3, 14, 6)
  end
end

--- A hand grenade, about 22 px tall at `scale` 1: an olive body with its
--- ridges, the lever and the ring on top. The bag, the quick slot, the HUD
--- and one flying through the air (grenades) all draw it with this.
function Render.grenade(cx, cy, scale)
  local s = scale or 1
  love.graphics.setColor(0.33, 0.4, 0.22)
  love.graphics.ellipse("fill", cx, cy + 2 * s, 8 * s, 10 * s)
  love.graphics.setColor(0.24, 0.29, 0.15)
  love.graphics.setLineWidth(math.max(1, s))
  love.graphics.line(cx - 8 * s, cy + 2 * s, cx + 8 * s, cy + 2 * s)
  love.graphics.line(cx, cy - 8 * s, cx, cy + 12 * s)
  love.graphics.setColor(0.6, 0.6, 0.63)
  love.graphics.rectangle("fill", cx - 3 * s, cy - 11 * s, 6 * s, 4 * s) -- the fuse
  love.graphics.polygon("fill", cx + 3 * s, cy - 11 * s, cx + 7 * s, cy - 10 * s, cx + 6 * s, cy + 2 * s,
    cx + 3 * s, cy - 7 * s) -- the lever down its side
  love.graphics.setColor(0.8, 0.75, 0.4)
  love.graphics.circle("line", cx - 5 * s, cy - 11 * s, 3 * s, 12) -- the pin's ring
  love.graphics.setLineWidth(1)
end

--- An ability as a thing: its ring, in its colour, around its icon
--- (abilities/icons.lua) on a dark disc, radius `r`. The inventory screen
--- draws one under the cursor with this.
function Render.abilityIcon(key, cx, cy, r)
  key = Tiers.base(key)
  local a = AbilityKinds.byKey[key]
  local c = a and a.color or { 0.8, 0.8, 0.85 }
  love.graphics.setColor(c[1], c[2], c[3], 0.25)
  love.graphics.circle("fill", cx, cy, r + 3, 32)
  love.graphics.setColor(0.05, 0.05, 0.07, 0.85)
  love.graphics.circle("fill", cx, cy, r, 32)
  UI.ring(cx, cy, r, 1, c, math.max(2, r / 6))
  AbilityIcons.draw(key, cx, cy, r * 0.72)
end

--- The main colour of `kind`'s building, for rubble and flying debris.
function Render.rubbleColor(kind)
  return ROOFS[kind.key] or YARDS[kind.key] or kind.color or { 0.5, 0.5, 0.5 }
end

--- A little random-number generator seeded by the plot, so a ruin is the
--- same heap every frame and on every machine.
local function seeded(seed)
  local state = seed * 7919 % 2147483647 + 1
  return function()
    state = state * 16807 % 2147483647
    return state / 2147483647
  end
end

--- Scorch marks across `r`.
local function scorch(r, rnd, n)
  for _ = 1, n do
    love.graphics.setColor(0.04, 0.04, 0.04, 0.45)
    local rx, ry = 14 + rnd() * math.min(30, r.w * 0.12), 10 + rnd() * math.min(18, r.h * 0.08)
    love.graphics.ellipse("fill", r.x + rx + rnd() * (r.w - 2 * rx), r.y + ry + rnd() * (r.h - 2 * ry), rx, ry)
  end
end

--- What stands of a wall round (x, y, w, h): stumps along every side,
--- `c` the parapet's colour.
local function stumps(x, y, w, h, c, rnd)
  love.graphics.setColor(c)
  love.graphics.setLineWidth(6)
  local pieces = 7
  for i = 0, pieces - 1 do
    local a, e = i / pieces, (i + 0.35 + rnd() * 0.5) / pieces
    if rnd() < 0.55 then
      love.graphics.line(x + a * w, y + 3, x + e * w, y + 3)
    end
    if rnd() < 0.55 then
      love.graphics.line(x + a * w, y + h - 3, x + e * w, y + h - 3)
    end
    if rnd() < 0.55 then
      love.graphics.line(x + 3, y + a * h, x + 3, y + e * h)
    end
    if rnd() < 0.55 then
      love.graphics.line(x + w - 3, y + a * h, x + w - 3, y + e * h)
    end
  end
  love.graphics.setLineWidth(1)
end

--- `n` slabs of `c` (or grey concrete) strewn over (x, y, w, h), tilted every way.
local function slabsDown(x, y, w, h, c, rnd, n)
  for _ = 1, n do
    local sx, sy = x + rnd() * w, y + rnd() * h
    local pw, ph = 8 + rnd() * 24, 6 + rnd() * 14
    local k = 0.55 + rnd() * 0.45
    love.graphics.push()
    love.graphics.translate(sx, sy)
    love.graphics.rotate(rnd() * math.pi)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", -pw / 2 + 3, -ph / 2 + 3, pw, ph)
    if rnd() < 0.65 then
      love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k)
    else
      love.graphics.setColor(0.45 * k, 0.44 * k, 0.42 * k)
    end
    love.graphics.rectangle("fill", -pw / 2, -ph / 2, pw, ph)
    love.graphics.pop()
  end
end

--- Broken skylight glass: pale slivers over (x, y, w, h).
local function shards(x, y, w, h, rnd, n)
  for _ = 1, n do
    local sx, sy, a = x + rnd() * w, y + rnd() * h, rnd() * math.pi * 2
    love.graphics.setColor(GLASS[1], GLASS[2], GLASS[3], 0.7)
    love.graphics.polygon("fill", sx, sy, sx + math.cos(a) * 7, sy + math.sin(a) * 7, sx + math.cos(a + 0.5) * 4,
      sy + math.sin(a + 0.5) * 4)
  end
end

--- A toppled box of `c` at (x, y), `w` by `h`, lying at `angle`, blackened.
local function toppled(x, y, w, h, angle, c)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  box(-w / 2 + 3, -h / 2 + 3, w, h, { 0, 0, 0 }, 0.35)
  box(-w / 2, -h / 2, w, h, shade(c, 0.6))
  box(-w / 2, -h / 2, w * 0.5, h, { 0.08, 0.08, 0.08 }, 0.45)
  love.graphics.pop()
end

--- A burnt-out car at (x, y) along `angle`, `len` px long: a charred shell.
local function wreck(x, y, angle, len)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  local w = len * 0.46
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", -len / 2 + 3, -w / 2 + 3, len, w, 5)
  love.graphics.setColor(0.2, 0.18, 0.17)
  love.graphics.rectangle("fill", -len / 2, -w / 2, len, w, 5)
  love.graphics.setColor(0.36, 0.26, 0.2)
  love.graphics.rectangle("fill", -len * 0.22, -w / 2 + 3, len * 0.44, w - 6, 3)
  love.graphics.setColor(0.08, 0.08, 0.08)
  love.graphics.rectangle("fill", -len * 0.12, -w / 2 + 5, len * 0.24, w - 10, 2)
  love.graphics.pop()
end

--- Flames licking at (x, y), `s` across; `i` staggers them.
local function flames(x, y, s, time, i)
  local f = 0.75 + 0.25 * math.sin(time * 11 + i * 1.7)
  love.graphics.setColor(1, 0.45, 0.1, 0.25)
  love.graphics.circle("fill", x, y, s * 1.6 * f)
  love.graphics.setColor(1, 0.5, 0.1, 0.85)
  love.graphics.circle("fill", x, y, s * f)
  love.graphics.setColor(1, 0.9, 0.4)
  love.graphics.circle("fill", x - s * 0.15, y - s * 0.2, s * 0.45 * f)
end

--- Embers glowing in the heap and smoke drifting off it, `n` places.
local function smoulder(r, rnd, time, n)
  for i = 1, n do
    local ex, ey = r.x + r.w * (0.2 + rnd() * 0.6), r.y + r.h * (0.2 + rnd() * 0.6)
    local glow = 0.5 + 0.5 * math.sin(time * 3 + i * 2)
    love.graphics.setColor(1, 0.4, 0.1, 0.35 + 0.35 * glow)
    love.graphics.circle("fill", ex, ey, 4 + 2 * glow)
    for k = 0, 2 do
      local t = (time * 0.35 + k / 3 + i * 0.29) % 1
      love.graphics.setColor(0.25, 0.25, 0.25, 0.45 * (1 - t))
      love.graphics.circle("fill", ex + t * 36, ey - t * 60, 8 + t * 18)
    end
  end
end

--- What is left of a building of `kind` inside `r`, in the look it had:
--- a gutted hall with its parapet in stumps, its roof fallen in, glass and
--- units strewn about and its silos crumpled (factories and the garage);
--- burnt-out wrecks in a cracked car park; a toppled digger over the pit;
--- burst tanks and an oil fire. Smoke still rises from all of them.
--- `seed` (the plot id) decides where the pieces lie.
function Render.ruin(kind, r, seed, time)
  local rnd = seeded(seed)
  local c = Render.rubbleColor(kind)
  if kind.key == "parking" then
    box(r.x, r.y, r.w, r.h, { 0.3, 0.3, 0.3 })
    box(r.x + 4, r.y + 4, r.w - 8, r.h - 8, { 0.14, 0.14, 0.15 })
    love.graphics.setColor(0.05, 0.05, 0.05, 0.8)
    for _ = 1, 6 do -- cracks
      local x, y = r.x + rnd() * r.w, r.y + rnd() * r.h
      love.graphics.line(x, y, x + 18 - rnd() * 36, y + 12, x + 26 - rnd() * 52, y + 30)
    end
    love.graphics.setColor(0.8, 0.8, 0.75, 0.35) -- what is left of the bays
    love.graphics.setLineWidth(2)
    for x = r.x + 8, r.x + r.w - 8, 40 do
      if rnd() < 0.6 then
        love.graphics.line(x, r.y + 6, x, r.y + 6 + r.h * 0.2)
      end
    end
    love.graphics.setLineWidth(1)
    scorch(r, rnd, 5)
    for i = 1, 3 do
      local x = r.x + r.w * (0.15 + 0.3 * (i - 1) + rnd() * 0.1)
      wreck(x, r.y + r.h * (0.25 + rnd() * 0.5), rnd() * math.pi, 44)
      flames(x, r.y + r.h * 0.3 + rnd() * r.h * 0.3, 5, time, i)
    end
    toppled(r.x + r.w * 0.55, r.y + r.h - 28, 24, 24, 0.7, { 0.9, 0.9, 0.88 })
    box(r.x + r.w * 0.3, r.y + r.h - 22, r.w * 0.2, 4, { 0.9, 0.9, 0.9 }, 0.8) -- the barrier, down
  elseif kind.key == "quarry" then
    box(r.x, r.y, r.w, r.h, { 0.44, 0.36, 0.27 })
    local cx, cy, rx, ry = r.x + r.w * 0.38, r.y + r.h * 0.44, r.w * 0.32, r.h * 0.36
    for i = 0, 3 do
      love.graphics.setColor(0.4 - i * 0.07, 0.32 - i * 0.06, 0.24 - i * 0.05)
      love.graphics.ellipse("fill", cx, cy, rx * (1 - i * 0.22), ry * (1 - i * 0.22))
    end
    scorch(r, rnd, 5)
    toppled(cx - rx * 0.2, cy, 26, 18, 1.1, HAZARD) -- the digger, on its side
    for i = 0, 3 do -- the conveyor, in pieces
      toppled(cx + rx + i * 16, cy - ry * 0.3 + rnd() * 10, 14, 7, rnd() - 0.5, { 0.3, 0.3, 0.32 })
    end
    for i, m in ipairs(kind.products) do
      pile(r.x + r.w - 30 + rnd() * 10, r.y + 20 + (r.h - 60) * (i - 0.5) / #kind.products, 16, shade(COLORS[m], 0.6))
    end
    slabsDown(r.x + 8, r.y + r.h - 44, 60, 36, { 0.92, 0.92, 0.88 }, rnd, 8) -- the office
  elseif kind.key == "oil" then
    box(r.x, r.y, r.w, r.h, { 0.3, 0.28, 0.24 })
    local wx, wy = r.x + r.w * 0.34, r.y + r.h * 0.42
    love.graphics.setColor(0.04, 0.03, 0.04, 0.7) -- the spill
    love.graphics.ellipse("fill", wx, wy + 10, r.w * 0.24, r.h * 0.17)
    scorch(r, rnd, 4)
    toppled(wx - 6, wy - 2, 72, 8, 0.35, HAZARD) -- the beam, fallen
    local tr = math.min(r.w, r.h) * 0.13
    local tx = r.x + r.w - tr - 14
    for i, ty in ipairs({ r.y + tr + 14, r.y + tr * 3 + 26 }) do
      love.graphics.setColor(0.35, 0.34, 0.32)
      love.graphics.circle("fill", tx, ty, tr)
      love.graphics.setColor(0.08, 0.07, 0.07)
      local pts = {}
      for k = 0, 9 do
        local a = k / 10 * math.pi * 2
        local rr = tr * (0.45 + rnd() * 0.45)
        pts[#pts + 1] = tx + math.cos(a) * rr
        pts[#pts + 1] = ty + math.sin(a) * rr
      end
      love.graphics.polygon("line", pts)
      love.graphics.circle("fill", tx, ty, tr * 0.45)
      flames(tx, ty, tr * 0.35, time, i)
    end
    for i = 1, 3 do -- the slick is still burning
      flames(wx - r.w * 0.2 + i * r.w * 0.1, wy + 10 + (rnd() - 0.5) * 20, 7, time, i + 3)
    end
  else
    -- Factories and the garage: the hall gutted to its floor.
    slabs(r.x, r.y, r.w, r.h, { 0.36, 0.35, 0.34 }, 32)
    scorch(r, rnd, 6)
    local hx, hy, hw, hh, siloW = hallOf(kind, r)
    local floor = { 0.2, 0.18, 0.16 }
    box(hx, hy, hw, hh, floor)
    -- A corner of the roof still up, broken off on a slant, one skylight left in it.
    local cw, ch = hw * 0.42, hh * 0.5
    roof(hx, hy, cw, ch, c)
    skylights(hx + 14, hy + 12, math.max(20, cw * 0.4), 12, 1)
    love.graphics.setColor(floor)
    love.graphics.polygon("fill", hx + cw * 0.55, hy + ch + 7, hx + cw + 7, hy + ch * 0.35, hx + cw + 7, hy + ch + 7)
    stumps(hx, hy, hw, hh, shade(c, 0.6), rnd)
    slabsDown(hx + 8, hy + 8, hw - 16, hh - 16, c, rnd, 26)
    shards(hx + 10, hy + 10, hw - 20, hh * 0.5, rnd, 14)
    toppled(hx + 20 + rnd() * 20, hy + hh * 0.3, 22, 22, rnd(), AC)
    toppled(hx + hw * 0.5, hy + hh + 10, math.min(44, hw * 0.25), 10, 0.25, { 0.66, 0.67, 0.68 }) -- a door
    -- Its name plate, fallen on the floor.
    local look = FACTORIES[kind.key]
    love.graphics.push()
    love.graphics.translate(hx + hw * 0.66, hy + hh * 0.72)
    love.graphics.rotate(0.3 - rnd() * 0.6)
    namePlate(0, 0, look and look.name or kind.name:upper(), look and look.accent or { 1, 0.85, 0.3 })
    love.graphics.pop()
    -- The silos, crumpled where they stood.
    local list = Kinds.hopperList(kind)
    if siloW > 0 and #list > 0 then
      local pitch = math.min(siloW + 6, (r.h - 24) / #list)
      local rad = math.max(8, math.min(siloW / 2 - 4, pitch / 2 - 5))
      local sx = r.x + r.w - 12 - siloW / 2
      for i, m in ipairs(list) do
        local sy = r.y + 12 + (i - 0.5) * pitch
        love.graphics.push()
        love.graphics.translate(sx, sy)
        love.graphics.rotate(rnd() * math.pi)
        love.graphics.setColor(0, 0, 0, 0.3)
        love.graphics.ellipse("fill", 3, 3, rad, rad * 0.6)
        love.graphics.setColor(0.42, 0.43, 0.44)
        love.graphics.ellipse("fill", 0, 0, rad, rad * 0.6)
        love.graphics.setColor(shade(COLORS[m], 0.6))
        love.graphics.ellipse("fill", rad * 0.3, rad * 0.2, rad * 0.45, rad * 0.25)
        love.graphics.pop()
      end
    end
  end
  smoulder(r, rnd, time, 3)
end

--- Cracks, a red flash for `since` seconds after a hit and a health bar
--- along the top of `r`, while a building stands at `frac` of its hit points.
function Render.damage(r, frac, since)
  if frac >= 1 then
    return
  end
  if since >= 0 and since < 0.15 then
    box(r.x, r.y, r.w, r.h, { 1, 0.2, 0.1 }, 0.35 * (1 - since / 0.15))
  end
  -- More cracks the more it has taken.
  local cracks = math.floor((1 - frac) * 6 + 0.5)
  love.graphics.setColor(0.08, 0.07, 0.07, 0.75)
  love.graphics.setLineWidth(2)
  for i = 1, cracks do
    local x = r.x + r.w * ((i * 0.37) % 1)
    local y = r.y + r.h * ((i * 0.61) % 1)
    love.graphics.line(x, y, x + 14, y + 9, x + 8, y + 22, x + 20, y + 30)
  end
  love.graphics.setLineWidth(1)
  box(r.x, r.y - 12, r.w, 7, { 0, 0, 0 }, 0.6)
  box(r.x + 1, r.y - 11, (r.w - 2) * math.max(0, frac), 5, UI.rampColor(frac))
end

--- Draw building `b` (the client's record) of `kind` inside rectangle `r`.
function Render.building(b, kind, r, time)
  if kind.key == "parking" then
    parking(b, r, time)
  elseif kind.key == "quarry" then
    quarry(b, kind, r, time)
  elseif kind.key == "oil" then
    oilWell(b, kind, r, time)
  else
    factory(b, kind, r, time)
  end
  -- The gate light, for anything that can be opened to the public.
  if not kind.private then
    local on = b.public
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.circle("fill", r.x + r.w - 14, r.y + r.h - 14, 9)
    if on then
      love.graphics.setColor(0.3, 1, 0.4)
    else
      love.graphics.setColor(1, 0.25, 0.2)
    end
    love.graphics.circle("fill", r.x + r.w - 14, r.y + r.h - 14, 6)
  end
  -- Progress on the batch under way.
  if b.running and kind.time then
    box(r.x, r.y + r.h + 4, r.w, 5, { 0, 0, 0 }, 0.5)
    box(r.x, r.y + r.h + 4, r.w * math.min(1, b.progress), 5, { 1, 0.85, 0.3 })
  end
  love.graphics.setLineWidth(1)
end

return Render
