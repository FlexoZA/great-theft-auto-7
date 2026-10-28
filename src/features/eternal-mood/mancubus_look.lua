-- How the Mancouchbus looks (mancubus.lua), seen from above at world size:
-- a brown leather recliner on a pair of tank treads, leant right back, its
-- footrest up, and in it a huge fat demon, belly first, his little horned
-- head on the headrest, his feet on the footrest. His arms end in rocket
-- launchers, one each side, as long as he is: steel tubes with twin
-- barrels, a hazard band and a rocket's red nose in each. The treads roll
-- as he drives and turns (each its own way when he turns on the spot).
-- When he raises the launchers to fire they come up and glow at the
-- muzzles, wide apart for a sweep; each kicks back as it fires. He leans
-- back before a bump. A TV remote on one armrest, a can in the cup holder.
--
--   Look.update(m, dt)      on the client, every frame
--   Look.draw(m, clock)     m: mancubus.lua's `shown` (dx, dy, facing, move, moveAt, stride, firedAt...)
--   Look.drawWreck(w, clock)  where he went down: w { x, y, angle }

local Look = {}

local C = {
  leather = { 0.50, 0.28, 0.17 },
  leatherDark = { 0.32, 0.17, 0.10 },
  leatherHi = { 0.66, 0.40, 0.26 },
  flesh = { 0.74, 0.52, 0.42 },
  fleshDark = { 0.50, 0.32, 0.26 },
  fleshHi = { 0.88, 0.68, 0.56 },
  scar = { 0.40, 0.14, 0.10 },
  horn = { 0.88, 0.82, 0.68 },
  eye = { 1.00, 0.80, 0.20 },
  tread = { 0.12, 0.11, 0.11 },
  link = { 0.28, 0.27, 0.26 },
  steel = { 0.42, 0.42, 0.44 },
  steelDark = { 0.22, 0.22, 0.24 },
  hazard = { 0.95, 0.75, 0.10 },
  rocket = { 0.85, 0.15, 0.10 },
  black = { 0.05, 0.05, 0.05 },
  shadow = { 0, 0, 0, 0.35 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local TREAD_Y, TREAD_W = 36, 22 -- the treads' middles either side, and how wide
local TREAD_X0, TREAD_X1 = -54, 44
local ARM_Y = 44 -- the launchers' middles either side (mancubus.lua's ARM)
local MUZZLE = 52 -- their ends (mancubus.lua's MUZZLE)

function Look.update(m, dt)
  m.time = (m.time or 0) + dt
end

--- A tread at local y `y`, rolled `rolled` px.
local function tread(y, rolled)
  color(C.tread)
  love.graphics.rectangle("fill", TREAD_X0, y - TREAD_W / 2, TREAD_X1 - TREAD_X0, TREAD_W, 6)
  color(C.link)
  local off = rolled % 9
  for x = TREAD_X0 + 3 + off, TREAD_X1 - 4, 9 do
    love.graphics.rectangle("fill", x, y - TREAD_W / 2 + 2, 4, TREAD_W - 4)
  end
  color(C.steelDark)
  for x = TREAD_X0 + 10, TREAD_X1 - 6, 20 do -- the road wheels' hubs, showing at the outer edge
    love.graphics.circle("fill", x, y + (y > 0 and 7 or -7), 3, 8)
  end
end

--- A launcher at side `side` (-1 left, 1 right): `up` 0..1 raised, `wide`
--- angled out for a sweep, `kick` 0..1 just fired.
local function launcher(side, up, wide, kick, clock)
  love.graphics.push()
  love.graphics.translate(-4, side * ARM_Y)
  love.graphics.rotate(side * wide * 0.25)
  local s = 1 + up * 0.12 -- raised, nearer the eye
  love.graphics.scale(s, s)
  love.graphics.translate(-kick * 8, 0)
  local len = MUZZLE + 4
  color(C.shadow)
  love.graphics.rectangle("fill", -6 + 4, -9 + 6, len + 2, 18, 4)
  color(C.steelDark)
  love.graphics.rectangle("fill", -6, -9, len + 2, 18, 4)
  color(C.steel)
  love.graphics.rectangle("fill", -4, -7, len - 2, 6, 2) -- light along the top tube
  color(C.hazard)
  love.graphics.rectangle("fill", len * 0.45, -9, 8, 18)
  color(C.black)
  for k = 0, 2 do
    love.graphics.rectangle("fill", len * 0.45 + 1 + k * 3, -9, 1.5, 18)
  end
  -- The twin barrels' mouths, a rocket's nose in each.
  for _, by in ipairs({ -4.5, 4.5 }) do
    color(C.black)
    love.graphics.circle("fill", len - 4, by, 4, 10)
    color(C.rocket)
    love.graphics.circle("fill", len - 5, by, 2.4, 8)
  end
  if up > 0 then -- warming: the muzzles glow
    local pulse = 0.6 + 0.4 * math.sin(clock * 24)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 0.5, 0.1, 0.55 * up * pulse)
    love.graphics.circle("fill", len - 3, 0, 14 * up, 14)
    love.graphics.setBlendMode("alpha")
  end
  if kick > 0 then -- the flash out of it
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 0.75, 0.3, kick)
    love.graphics.circle("fill", len + 10, 0, 16 * kick, 12)
    love.graphics.setBlendMode("alpha")
  end
  love.graphics.pop()
end

--- Him, in his own frame: +x ahead, +y his right.
local function body(lean, clock, hurt)
  -- The recliner: its base, the back leant right down behind him, the
  -- armrests, the footrest up in front.
  color(C.leatherDark)
  love.graphics.rectangle("fill", -50, -32, 88, 64, 12)
  color(C.leather)
  love.graphics.rectangle("fill", -47, -29, 82, 58, 10)
  color(C.leatherDark)
  love.graphics.rectangle("fill", -58, -30, 22, 60, 10) -- the back, leant down
  color(C.leatherHi)
  love.graphics.rectangle("fill", -55, -26, 15, 52, 8)
  color(C.leatherDark)
  for _, by in ipairs({ -14, 0, 14 }) do -- buttons in it
    love.graphics.circle("fill", -48, by, 2, 6)
  end
  for _, side in ipairs({ -1, 1 }) do -- the armrests
    color(C.leatherDark)
    love.graphics.rectangle("fill", -36, side * 30 - 6, 66, 12, 5)
    color(C.leatherHi)
    love.graphics.rectangle("fill", -34, side * 30 - 4, 62, 4, 3)
  end
  color(C.leatherDark)
  love.graphics.rectangle("fill", 32, -22, 26, 44, 8) -- the footrest
  color(C.leather)
  love.graphics.rectangle("fill", 34, -19, 22, 38, 6)
  -- A TV remote on the right armrest, a can in the cup holder on the left.
  color(C.black)
  love.graphics.rectangle("fill", 6, 26, 18, 7, 2)
  love.graphics.setColor(0.9, 0.2, 0.15)
  love.graphics.circle("fill", 9, 29.5, 1.4, 6)
  love.graphics.setColor(0.3, 0.6, 0.9)
  love.graphics.circle("fill", 14, 29.5, 1.2, 6)
  love.graphics.setColor(0.75, 0.12, 0.10)
  love.graphics.circle("fill", -24, -30, 4.5, 12)
  love.graphics.setColor(0.85, 0.85, 0.85)
  love.graphics.circle("fill", -24, -30, 2.2, 10)

  -- Him: feet up on the footrest, the belly, his head on the headrest.
  local bx = 4 - lean
  color(C.fleshDark)
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.ellipse("fill", 48 - lean * 0.5, side * 11, 9, 7, 10) -- the feet, three claws each
    color(C.horn)
    for k = -1, 1 do
      love.graphics.circle("fill", 56 - lean * 0.5, side * 11 + k * 3.5, 1.4, 5)
    end
    color(C.fleshDark)
  end
  love.graphics.ellipse("fill", bx + 2, 2, 36, 31, 28) -- the belly's shadow side
  color(C.flesh)
  love.graphics.ellipse("fill", bx, 0, 34, 29, 28)
  color(C.fleshHi)
  love.graphics.ellipse("fill", bx - 6, -8, 18, 13, 20)
  color(C.fleshDark) -- rolls, and the navel
  love.graphics.setLineWidth(2)
  love.graphics.arc("line", "open", bx - 10, 0, 30, -0.9, 0.9, 12)
  love.graphics.arc("line", "open", bx - 22, 0, 30, -0.7, 0.7, 12)
  love.graphics.setLineWidth(1)
  love.graphics.circle("fill", bx + 12, 2, 2.5, 8)
  color(C.scar) -- stitches across him
  love.graphics.setLineWidth(1.5)
  love.graphics.line(bx - 4, 14, bx + 20, 6)
  for k = 0, 4 do
    local sx, sy = bx - 2 + k * 5, 13.3 - k * 1.65
    love.graphics.line(sx - 1, sy - 3, sx + 1, sy + 3)
  end
  love.graphics.setLineWidth(1)
  -- His shoulders, bulging over the armrests, and the arms out to the launchers.
  for _, side in ipairs({ -1, 1 }) do
    color(C.fleshDark)
    love.graphics.ellipse("fill", -22 - lean, side * 27, 13, 10, 14)
    color(C.flesh)
    love.graphics.ellipse("fill", -23 - lean, side * 26, 11, 8, 14)
    love.graphics.setLineWidth(9)
    color(C.fleshDark)
    love.graphics.line(-22 - lean, side * 30, -10, side * ARM_Y)
    love.graphics.setLineWidth(1)
  end
  -- The head, small for the rest of him, on the headrest: horns, a heavy
  -- brow, yellow eyes, a grimace with tusks.
  local hx = -30 - lean
  color(C.horn)
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.polygon("fill", hx - 4, side * 7, hx - 2, side * 12, hx - 16, side * 16)
  end
  color(C.fleshDark)
  love.graphics.circle("fill", hx, 0, 14, 20)
  color(C.flesh)
  love.graphics.circle("fill", hx + 1, -1, 12, 20)
  color(C.fleshDark)
  love.graphics.rectangle("fill", hx + 4, -9, 4, 18, 2) -- the brow
  local blink = (math.floor(clock * 0.7) % 7 == 0 and (clock * 0.7) % 1 < 0.15) and 0.3 or 1
  love.graphics.setColor(C.eye[1], C.eye[2] * (hurt and 0.5 or 1), C.eye[3])
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.ellipse("fill", hx + 9, side * 5, 2, 2.6 * blink, 8)
  end
  color(C.scar)
  love.graphics.rectangle("fill", hx + 12, -6, 3, 12, 1) -- the mouth
  color(C.horn)
  love.graphics.polygon("fill", hx + 13, -6, hx + 17, -5, hx + 13, -3)
  love.graphics.polygon("fill", hx + 13, 6, hx + 17, 5, hx + 13, 3)
end

function Look.draw(m, clock)
  local into = clock - (m.moveAt or clock)
  local up, wide, lean = 0, 0, 0
  if m.move == 1 then
    up = math.min(1, into / 0.8)
  elseif m.move == 2 then
    up = 1
  elseif m.move == 3 then
    up, wide = math.min(1, into / 1.0), math.min(1, into / 1.0)
  elseif m.move == 4 then
    up, wide = 1, 1
  elseif m.move == 5 then
    lean = math.min(1, into / 0.55) * 8
  end
  love.graphics.push()
  love.graphics.translate(m.dx, m.dy)
  love.graphics.rotate(m.facing)
  color(C.shadow)
  love.graphics.ellipse("fill", 8, 10, 62, 56, 32)
  local rolled, turned = m.stride or 0, m.turnStride or 0
  tread(-TREAD_Y, rolled - turned)
  tread(TREAD_Y, rolled + turned)
  body(lean, clock, m.max and m.hp and m.hp < m.max * 0.25)
  for _, side in ipairs({ -1, 1 }) do
    local fired = m.firedAt and m.firedAt[side]
    local kick = fired and math.max(0, 1 - (clock - fired) / 0.15) or 0
    launcher(side, up, wide, kick, clock)
  end
  love.graphics.pop()
  if m.max and m.hp and m.hp < m.max * 0.5 then -- smoke off the launchers, hurt
    for k = 0, 2 do
      local phase = (clock * 0.8 + k / 3) % 1
      love.graphics.setColor(0.15, 0.12, 0.12, 0.45 * (1 - phase))
      love.graphics.circle("fill", m.dx + math.sin(clock + k) * 8, m.dy - 30 - phase * 50, 8 + phase * 14, 12)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- His wreck: the recliner on its back, treads still, him slumped in it
--- with the launchers dropped, smoke going up.
function Look.drawWreck(w, clock)
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.rotate(w.angle + 0.3)
  color(C.shadow)
  love.graphics.ellipse("fill", 6, 8, 64, 54, 30)
  love.graphics.setColor(0.25, 0.04, 0.03, 0.7) -- what came out of him
  love.graphics.ellipse("fill", 20, 10, 70, 44, 24)
  tread(-TREAD_Y, 0)
  tread(TREAD_Y, 0)
  body(10, 3, true)
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.push()
    love.graphics.translate(0, side * 12)
    love.graphics.rotate(side * 0.5)
    launcher(side, 0, 0, 0, clock)
    love.graphics.pop()
  end
  love.graphics.pop()
  for k = 0, 3 do
    local phase = (clock * 0.5 + k / 4) % 1
    love.graphics.setColor(0.12, 0.10, 0.10, 0.5 * (1 - phase))
    love.graphics.circle("fill", w.x + math.sin(clock * 0.7 + k) * 12, w.y - phase * 90, 12 + phase * 22, 14)
  end
  love.graphics.setColor(1, 1, 1)
end

return Look
