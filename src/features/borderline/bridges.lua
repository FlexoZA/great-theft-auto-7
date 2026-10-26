-- The Refinery's bridges (docs/borderline.md, "5. The Refinery"): every
-- one over the river stands drawn up until its lock opens (the terminals
-- feature: the bridge control on the bank below hacked), then swings down
-- and lies across. From the map (`map.drawbridges`, each naming its lock in
-- `map.locks`); the lock's wall over the gap is what stops anyone crossing
-- (`water`: rounds and sight still go over), so this only draws. Each
-- screen sees a lock open (TRM_OPEN) and lowers that lock's bridges then.
--
-- A bridge is a bascule leaf hinged on the south bank, the way everyone
-- comes: up, it stands over the river showing its deck, its shadow thrown
-- across the molten Bragium, a red lamp blinking on its machinery; down,
-- a steel deck of grating between yellow girders, bank to bank.

local Hauler = require("src.features.borderline.hauler_look")

local Bridges = {}

local C = Hauler.C
local LOWER = 1.6 -- seconds a bridge takes to come down
local HINGE = 16 -- px in from the deck's south end, where it pivots
local TILT = 0.55 -- how much of a raised leaf's height shows from above

local clock = 0
local opened = setmetatable({}, { __mode = "k" }) -- lock -> the clock when this screen saw it open

function Bridges.update(dt)
  clock = clock + dt
end

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function lockNamed(map, name)
  for _, l in ipairs(map.locks or {}) do
    if l.name == name then
      return l
    end
  end
end

--- How far down bridge `d` on `map` is: 0 drawn up, 1 lying across.
local function down(map, d)
  local l = lockNamed(map, d.lock)
  if not (l and l.open) then
    return 0
  end
  opened[l] = opened[l] or clock
  local k = math.min(1, (clock - opened[l]) / LOWER)
  return k * k * (3 - 2 * k)
end

--- The deck from (x, y) `w` wide and `len` long going north: grating
--- between two yellow girders, plates across it, hazard bands at its ends.
--- `shade` darkens it (a leaf standing up shows its deck in its own shade).
local function deck(x, y, w, len, shade)
  local k = shade or 1
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", x - 3, y - len - 3, w + 6, len + 6)
  love.graphics.setColor(C.gunmetal[1] * k, C.gunmetal[2] * k, C.gunmetal[3] * k)
  love.graphics.rectangle("fill", x, y - len, w, len)
  love.graphics.setColor(C.gunmetalLight[1] * k, C.gunmetalLight[2] * k, C.gunmetalLight[3] * k)
  for a = x + 22, x + w - 26, 7 do -- the grating
    love.graphics.rectangle("fill", a, y - len, 3, len)
  end
  color(C.ink, 0.5)
  for a = y - len + 30, y - 10, 36 do -- the plates' joints across it
    love.graphics.rectangle("fill", x + 18, a, w - 36, 3)
  end
  for _, gx in ipairs({ x, x + w - 18 }) do -- the girders
    love.graphics.setColor(C.yellow[1] * k, C.yellow[2] * k, C.yellow[3] * k)
    love.graphics.rectangle("fill", gx, y - len, 18, len)
    color(C.ink, 0.45)
    for a = y - len + 6, y - 14, 24 do -- the truss in it
      love.graphics.line(gx + 2, a, gx + 16, a + 12)
      love.graphics.line(gx + 16, a + 12, gx + 2, a + 24)
    end
  end
  for _, hy in ipairs({ y - len, y - 10 }) do -- hazard at the ends
    for i = 0, math.ceil(w / 20) - 1 do
      color(i % 2 == 0 and C.yellow or C.ink, k)
      love.graphics.rectangle("fill", x + i * 20, hy, math.min(20, w - i * 20), 10)
    end
  end
end

--- One bridge, `k` of the way down.
local function draw(d, k)
  local hy = d.y + d.h - HINGE -- the hinge line
  local L = d.h - HINGE
  local up = (1 - k) * math.pi / 2 -- how far up it stands
  local len = L * (math.cos(up) + TILT * math.sin(up)) -- how long it shows going north
  if k < 1 then -- its shadow, across the river
    love.graphics.setColor(0, 0, 0, 0.3 * math.sin(up))
    love.graphics.rectangle("fill", d.x + 18, hy - L * math.cos(up), d.w, L * math.sin(up) * 0.5 + 10)
  end
  deck(d.x, hy, d.w, len, 0.75 + 0.25 * k)
  -- The machinery on the bank at its foot: the rams either side, the
  -- counterweight's housing under the hinge, its lamp.
  for _, rx in ipairs({ d.x - 14, d.x + d.w + 2 }) do
    love.graphics.setColor(C.ink)
    love.graphics.rectangle("fill", rx - 2, hy - 2, 16, HINGE + 30)
    color(C.yellow)
    love.graphics.rectangle("fill", rx, hy, 12, HINGE + 26)
    color(C.steel) -- the ram's rod, out while it stands up
    love.graphics.rectangle("fill", rx + 3, hy - len * 0.4, 6, len * 0.4)
  end
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", d.x + d.w / 2 - 34, hy + 4, 68, 22)
  color(C.gunmetal)
  love.graphics.rectangle("fill", d.x + d.w / 2 - 32, hy + 6, 64, 18)
  local lit = k < 1 and math.floor(clock * 2.5) % 2 == 0
  color(lit and C.eye or (k >= 1 and { 0.35, 0.95, 0.45 } or C.black))
  love.graphics.circle("fill", d.x + d.w / 2, hy + 15, 6, 10)
end

--- Every bridge on `map`, where it stands now (over the river, under the army).
function Bridges.drawBelowCars(map)
  for _, d in ipairs(map and map.drawbridges or {}) do
    draw(d, down(map, d))
  end
  love.graphics.setColor(1, 1, 1)
end

--- At night, a raised bridge's lamp blinks red.
function Bridges.drawNightLights(map, glow)
  for _, d in ipairs(map and map.drawbridges or {}) do
    if down(map, d) < 1 and math.floor(clock * 2.5) % 2 == 0 then
      glow(d.x + d.w / 2, d.y + d.h - HINGE + 15, 90, C.eye, 0.8)
    end
  end
end

--- On the minimap and the big map: a bridge down across the river, or a
--- red bar on the bank where one stands up.
function Bridges.drawOnMinimap(map, toMap)
  for _, d in ipairs(map and map.drawbridges or {}) do
    local x0, y0 = toMap(d.x, d.y)
    local x1, y1 = toMap(d.x + d.w, d.y + d.h)
    if down(map, d) >= 1 then
      love.graphics.setColor(0.45, 0.47, 0.51)
      love.graphics.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
    else
      color(C.eye)
      love.graphics.rectangle("fill", x0, y1 - 2, x1 - x0, 2)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Bridges
