-- Drawing the buildings, top down, inside the fence of the plot they stand
-- on. Every kind is a few rectangles; the yard shows what is waiting to be
-- collected, a light by the gate says public (green) or private (red), and
-- a bar along the bottom fills while a batch is being made. A damaged
-- building gets cracks, a health bar and a red flash when hit; a destroyed
-- one is a smoking heap of rubble in its own colours.

local UI = require("src.ui")
local Kinds = require("src.features.buildings.kinds")
local Icons = require("src.features.weapons.icons")
local AbilityKinds = require("src.features.abilities.kinds")

local Render = {}

local COLORS = {
  iron = { 0.55, 0.6, 0.68 },
  sulfur = { 0.95, 0.85, 0.2 },
  minerals = { 0.3, 0.8, 0.75 },
  copper = { 0.85, 0.48, 0.25 },
  oil = { 0.12, 0.1, 0.14 },
  plastic = { 0.95, 0.55, 0.75 },
}

local function box(x, y, w, h, c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", x, y, w, h)
end

--- A roof with a darker rim and a few ridges.
local function roof(x, y, w, h, c)
  box(x + 6, y + 6, w, h, { 0, 0, 0 }, 0.35)
  box(x, y, w, h, c)
  love.graphics.setColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", x, y, w, h)
  love.graphics.setLineWidth(1)
  for i = 1, 3 do
    local ly = y + h * i / 4
    love.graphics.line(x + 6, ly, x + w - 6, ly)
  end
end

--- A chimney that smokes while the building works.
local function chimney(x, y, running, time)
  love.graphics.setColor(0.3, 0.28, 0.27)
  love.graphics.circle("fill", x, y, 11)
  love.graphics.setColor(0.12, 0.12, 0.12)
  love.graphics.circle("fill", x, y, 6)
  if running then
    for i = 0, 2 do
      local t = (time * 0.6 + i / 3) % 1
      love.graphics.setColor(0.8, 0.8, 0.8, 0.5 * (1 - t))
      love.graphics.circle("fill", x + t * 30, y - t * 40, 6 + t * 12)
    end
  end
end

--- Crates stacked in the yard, one per unit waiting (up to `most` shown).
local function crates(x, y, n, most, c)
  n = math.min(n, most)
  for i = 0, n - 1 do
    local cx, cy = x + (i % 5) * 20, y - math.floor(i / 5) * 20
    box(cx, cy, 16, 16, c)
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("line", cx, cy, 16, 16)
    love.graphics.line(cx, cy, cx + 16, cy + 16)
  end
end

local function parking(b, r)
  box(r.x, r.y, r.w, r.h, { 0.2, 0.2, 0.22 })
  love.graphics.setColor(0.9, 0.9, 0.85, 0.8)
  love.graphics.setLineWidth(3)
  local bays = 6
  local bw = r.w / bays
  for i = 0, bays do
    love.graphics.line(r.x + i * bw, r.y, r.x + i * bw, r.y + r.h * 0.3)
    love.graphics.line(r.x + i * bw, r.y + r.h, r.x + i * bw, r.y + r.h * 0.7)
  end
  -- The P sign in the middle and the takings beside it.
  local cx, cy = r.x + r.w / 2, r.y + r.h / 2
  box(cx - 22, cy - 22, 44, 44, { 0.15, 0.35, 0.8 })
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.printf("P", cx - 22, cy - 16, 44, "center")
  local stacks = math.min(10, math.ceil(b.output / 10))
  for i = 0, stacks - 1 do
    local kx = cx + 40 + (i % 5) * 16
    local ky = cy + 10 - math.floor(i / 5) * 16
    love.graphics.setColor(0.6, 0.45, 0.05)
    love.graphics.circle("fill", kx, ky, 7)
    love.graphics.setColor(1, 0.85, 0.2)
    love.graphics.circle("fill", kx, ky - 2, 7)
  end
end

local function quarry(b, kind, r, time)
  box(r.x, r.y, r.w, r.h, { 0.62, 0.5, 0.36 })
  -- The pit: terraces stepping down.
  local cx, cy = r.x + r.w * 0.42, r.y + r.h / 2
  for i = 0, 3 do
    local s = 1 - i * 0.22
    local shade = 0.55 - i * 0.1
    love.graphics.setColor(shade, shade * 0.8, shade * 0.6)
    love.graphics.ellipse("fill", cx, cy, r.w * 0.34 * s, r.h * 0.36 * s)
  end
  -- A digger that swings while it works.
  local a = b.running and math.sin(time * 2) * 0.6 or 0
  love.graphics.setColor(0.95, 0.7, 0.1)
  love.graphics.rectangle("fill", cx - 10, cy - 8, 20, 16)
  love.graphics.setLineWidth(4)
  love.graphics.line(cx, cy, cx + math.cos(a) * 34, cy + math.sin(a) * 34)
  -- A pile of each material; the one being dug is the big one.
  local n = #kind.products
  for i, m in ipairs(kind.products) do
    local px, py = r.x + r.w * 0.86, r.y + r.h * (i - 0.5) / n
    local c = COLORS[m]
    local size = (i == b.product and 10 + math.min(14, b.output * 0.5)) or 8
    love.graphics.setColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7)
    love.graphics.circle("fill", px + 2, py + 2, size)
    love.graphics.setColor(c)
    love.graphics.circle("fill", px, py, size)
  end
end

--- An oil well: a pumpjack nodding over the wellhead, a storage tank, and
--- barrels of oil or bales of plastic by the gate.
local function oilWell(b, kind, r, time)
  box(r.x, r.y, r.w, r.h, { 0.42, 0.38, 0.3 }) -- packed dirt
  -- Oil stains around the wellhead.
  local wx, wy = r.x + r.w * 0.34, r.y + r.h * 0.45
  love.graphics.setColor(0.1, 0.09, 0.1, 0.5)
  love.graphics.ellipse("fill", wx, wy + 6, 34, 22)
  -- The pumpjack: a beam on an A-frame, its head bobbing while it works.
  local a = b.running and math.sin(time * 2.4) * 0.35 or 0
  love.graphics.setColor(0.25, 0.25, 0.28)
  love.graphics.polygon("fill", wx - 10, wy + 18, wx + 10, wy + 18, wx, wy - 4)
  love.graphics.push()
  love.graphics.translate(wx, wy - 4)
  love.graphics.rotate(a)
  love.graphics.setColor(0.95, 0.7, 0.1)
  love.graphics.rectangle("fill", -44, -5, 70, 10)
  love.graphics.setColor(0.2, 0.2, 0.22)
  love.graphics.rectangle("fill", -52, -10, 12, 20) -- horsehead
  love.graphics.rectangle("fill", 22, -8, 14, 16) -- counterweight
  love.graphics.pop()
  -- The tank: plastic comes out of the refinery drum on top of it.
  local tx, ty = r.x + r.w * 0.72, r.y + r.h * 0.38
  local tr = math.min(r.w, r.h) * 0.2
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", tx + 5, ty + 5, tr)
  love.graphics.setColor(0.78, 0.78, 0.76)
  love.graphics.circle("fill", tx, ty, tr)
  love.graphics.setColor(0.6, 0.6, 0.58)
  love.graphics.circle("line", tx, ty, tr * 0.7)
  local item = kind.products[b.product]
  if item == "plastic" then
    love.graphics.setColor(COLORS.plastic)
    love.graphics.circle("fill", tx, ty, tr * 0.4)
  end
  -- A flare stack that burns while it pumps.
  local fx, fy = r.x + r.w * 0.9, r.y + 24
  love.graphics.setColor(0.3, 0.3, 0.32)
  love.graphics.circle("fill", fx, fy, 6)
  if b.running then
    local flick = 0.7 + 0.3 * math.sin(time * 17)
    love.graphics.setColor(1, 0.55, 0.1, 0.8)
    love.graphics.circle("fill", fx, fy, 7 * flick)
    love.graphics.setColor(1, 0.9, 0.4)
    love.graphics.circle("fill", fx, fy, 3 * flick)
  end
  -- What is waiting to be collected.
  local units = math.floor(b.output / Kinds.recipe(kind, b.product).unit)
  crates(r.x + 20, r.y + r.h - 30, units, 10, COLORS[item] or COLORS.oil)
end

--- The emblem painted on a factory roof.
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
    love.graphics.setColor(0.85, 0.12, 0.12)
    love.graphics.rectangle("fill", cx - 8, cy - 24, 16, 48)
    love.graphics.rectangle("fill", cx - 24, cy - 8, 48, 16)
  end
end

local ROOFS = {
  ammo = { 0.45, 0.42, 0.35 },
  weapons = { 0.3, 0.32, 0.36 },
  health = { 0.92, 0.92, 0.9 },
}
local YARDS = {
  parking = { 0.2, 0.2, 0.22 },
  quarry = { 0.62, 0.5, 0.36 },
  oil = { 0.42, 0.38, 0.3 },
}
local CRATES = {
  ammo = { 0.45, 0.5, 0.25 },
  weapons = { 0.35, 0.3, 0.25 },
  health = { 0.95, 0.95, 0.95 },
}

local function factory(b, kind, r, time)
  box(r.x, r.y, r.w, r.h, { 0.55, 0.55, 0.52 }) -- concrete yard
  local bx, by, bw, bh = r.x + 16, r.y + 10, r.w * 0.62, r.h * 0.62
  roof(bx, by, bw, bh, ROOFS[kind.key])
  emblem(kind.key, bx + bw / 2, by + bh / 2)
  chimney(bx + bw - 22, by + 22, b.running, time)
  -- Hoppers along the side, filled as far as they are loaded; squeezed
  -- shorter when a factory takes more materials than fit at full size.
  local list = Kinds.hopperList(kind)
  local pitch = math.min(56, (r.h - 60) / math.max(1, #list))
  local hh = pitch - 12
  for i, m in ipairs(list) do
    local hx, hy = r.x + r.w - 46, r.y + 16 + (i - 1) * pitch
    local fill = (b.hopper[m] or 0) / Kinds.HOPPER
    box(hx, hy, 30, hh, { 0.2, 0.2, 0.22 })
    box(hx + 3, hy + 3 + (hh - 6) * (1 - fill), 24, (hh - 6) * fill, COLORS[m])
  end
  -- What is waiting to be collected, in crates by the gate.
  local units = math.floor(b.output / Kinds.recipe(kind, b.product).unit)
  crates(r.x + 20, r.y + r.h - 30, units, 10, CRATES[kind.key])
end

--- A small picture of an item, centred on (cx, cy), for the inventory.
function Render.itemIcon(item, cx, cy)
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
    Render.abilityIcon(item:sub(9), cx, cy, 11)
  elseif item == "medkit" then
    love.graphics.setColor(0.95, 0.95, 0.95)
    love.graphics.rectangle("fill", cx - 12, cy - 10, 24, 20, 3)
    love.graphics.setColor(0.85, 0.12, 0.12)
    love.graphics.rectangle("fill", cx - 3, cy - 7, 6, 14)
    love.graphics.rectangle("fill", cx - 7, cy - 3, 14, 6)
  end
end

--- An ability as a thing: its ring, in its colour, with a glow inside,
--- radius `r`. The inventory screen draws one under the cursor with this.
function Render.abilityIcon(key, cx, cy, r)
  local a = AbilityKinds.byKey[key]
  local c = a and a.color or { 0.8, 0.8, 0.85 }
  love.graphics.setColor(c[1], c[2], c[3], 0.25)
  love.graphics.circle("fill", cx, cy, r + 3, 32)
  love.graphics.setColor(c[1], c[2], c[3], 0.6)
  love.graphics.circle("fill", cx, cy, r * 0.45, 24)
  UI.ring(cx, cy, r, 1, c, 3)
end

--- The main colour of `kind`'s building, for rubble and flying debris.
function Render.rubbleColor(kind)
  return ROOFS[kind.key] or YARDS[kind.key] or { 0.5, 0.5, 0.5 }
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

--- What is left of a building of `kind` inside `r`: scorched ground, the
--- stumps of its walls, rubble in its colours and smoke still rising.
--- `seed` (the plot id) decides where the pieces lie.
function Render.ruin(kind, r, seed, time)
  local rnd = seeded(seed)
  local c = Render.rubbleColor(kind)
  box(r.x, r.y, r.w, r.h, { 0.16, 0.14, 0.13 })
  -- Scorch marks.
  for _ = 1, 5 do
    love.graphics.setColor(0.05, 0.05, 0.05, 0.5)
    love.graphics.ellipse("fill", r.x + rnd() * r.w, r.y + rnd() * r.h, 20 + rnd() * 40, 14 + rnd() * 26)
  end
  -- Broken stumps of the outer wall: every other stretch still standing.
  love.graphics.setColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6)
  love.graphics.setLineWidth(6)
  local pieces = 8
  for i = 0, pieces - 1 do
    if rnd() < 0.55 then
      local a, b = i / pieces, (i + 0.4 + rnd() * 0.5) / pieces
      love.graphics.line(r.x + a * r.w, r.y + 3, r.x + b * r.w, r.y + 3)
    end
    if rnd() < 0.55 then
      local a, b = i / pieces, (i + 0.4 + rnd() * 0.5) / pieces
      love.graphics.line(r.x + a * r.w, r.y + r.h - 3, r.x + b * r.w, r.y + r.h - 3)
    end
    if rnd() < 0.55 then
      local a, b = i / pieces, (i + 0.4 + rnd() * 0.5) / pieces
      love.graphics.line(r.x + 3, r.y + a * r.h, r.x + 3, r.y + b * r.h)
    end
    if rnd() < 0.55 then
      local a, b = i / pieces, (i + 0.4 + rnd() * 0.5) / pieces
      love.graphics.line(r.x + r.w - 3, r.y + a * r.h, r.x + r.w - 3, r.y + b * r.h)
    end
  end
  love.graphics.setLineWidth(1)
  -- Rubble: slabs of roof and chunks of grey concrete, tilted every way.
  for _ = 1, 40 do
    local x, y = r.x + 12 + rnd() * (r.w - 24), r.y + 12 + rnd() * (r.h - 24)
    local w, h = 6 + rnd() * 22, 5 + rnd() * 14
    local shade = 0.55 + rnd() * 0.45
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(rnd() * math.pi)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", -w / 2 + 3, -h / 2 + 3, w, h)
    if rnd() < 0.6 then
      love.graphics.setColor(c[1] * shade, c[2] * shade, c[3] * shade)
    else
      love.graphics.setColor(0.45 * shade, 0.44 * shade, 0.42 * shade)
    end
    love.graphics.rectangle("fill", -w / 2, -h / 2, w, h)
    love.graphics.pop()
  end
  -- Embers glowing in the heap, and smoke drifting off it.
  for i = 1, 3 do
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
    parking(b, r)
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
