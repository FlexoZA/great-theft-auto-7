-- The Mood Slayer's face for the Voice's intro screen (docs/eternal-mood.md,
-- "The cast"): his helmet, head and shoulders, since the Voice is his own.
-- Drawn with primitives onto a 64x72 canvas and scaled up with nearest
-- filtering, the way VEX's (cyber-feud/face.lua) and A-Man's are.
--
-- A green helmet with a crest, a wide amber visor, a jaw guard with vents,
-- big scuffed pauldrons. Behind the visor one eye shows, and it is not as
-- awake as the Voice: heavy-lidded, it blinks slowly, and now and then he
-- nods off, the lid sliding shut and the helmet sinking, until he jerks
-- awake, eye wide. `drowsy` (0..1) is how far gone he is: the further down
-- the dream, the more he nods (the Snooze Gate's screen is all but asleep).
--
-- `face:draw(x, y, scale)`, after `face:update(dt)`.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local C = {
  armour = { 0.30, 0.42, 0.20 },
  armourHi = { 0.44, 0.58, 0.28 },
  armourDark = { 0.18, 0.26, 0.12 },
  steel = { 0.30, 0.30, 0.32 },
  visor = { 0.10, 0.07, 0.03 },
  glass = { 0.95, 0.62, 0.15 },
  skin = { 0.62, 0.45, 0.36 },
  white = { 0.88, 0.85, 0.80 },
  iris = { 0.25, 0.42, 0.20 },
  scratch = { 0.55, 0.62, 0.45 },
}

Face.AMBER = C.glass

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", x, y, w, h)
end

--- A face. `drowsy` 0..1: how often he nods off.
function Face.new(drowsy)
  local self = setmetatable({}, Face)
  self.canvas = Pixel.canvas(Face.W, Face.H)
  self.drowsy = drowsy or 0.3
  self.t = 0
  self.lid = 0.45 -- how far down the eyelid is, 0 wide open to 1 shut
  self.blink = 0 -- seconds left of a slow blink
  self.blinkIn = 2
  self.nod = 0 -- 0..1 how far he has nodded off
  self.nodding = false
  self.nodIn = 5 - self.drowsy * 3
  self.jolt = 0 -- seconds since he jerked awake (wide-eyed for a moment)
  return self
end

function Face:update(dt)
  self.t = self.t + dt
  self.jolt = self.jolt + dt
  local random = love.math.random
  -- Nodding off: the lid slides shut and the helmet sinks, then he jerks up.
  self.nodIn = self.nodIn - dt
  if not self.nodding and self.nodIn <= 0 then
    self.nodding = true
  end
  if self.nodding then
    self.nod = math.min(1, self.nod + dt / (1.6 - self.drowsy * 0.6))
    if self.nod >= 1 then
      self.nodding, self.nod, self.jolt = false, 0, 0
      self.nodIn = (7 + random() * 5) * (1.2 - self.drowsy)
    end
  end
  -- A slow blink now and then.
  self.blinkIn = self.blinkIn - dt
  if self.blinkIn <= 0 then
    self.blink, self.blinkIn = 0.45, 2.5 + random() * 3
  end
  self.blink = math.max(0, self.blink - dt)
  local heavy = 0.4 + self.drowsy * 0.3 + 0.08 * math.sin(self.t * 0.9) -- the lid drifts
  if self.jolt < 0.6 then
    heavy = 0.05 -- wide awake, for a moment
  end
  local want = math.max(heavy, self.nod, self.blink > 0 and 1 or 0)
  self.lid = self.lid + (want - self.lid) * math.min(1, dt * (self.blink > 0 and 10 or 6))
end

--- How far the helmet has sunk (art pixels), and its jerk back up.
function Face:sink()
  if self.jolt < 0.25 then
    return -1 -- jerked up
  end
  return math.floor(self.nod * 3 + 0.5)
end

function Face:render()
  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  local s = self:sink()

  -- Pauldrons and chest plate (they don't nod).
  color(C.armourDark)
  rect(0, 54, 22, 18)
  rect(42, 54, 22, 18)
  color(C.armour)
  rect(1, 53, 20, 15)
  rect(43, 53, 20, 15)
  rect(18, 56, 28, 16)
  color(C.armourHi)
  rect(3, 54, 16, 2)
  rect(45, 54, 16, 2)
  color(C.armourDark)
  rect(31, 58, 2, 14) -- the plate's seam
  rect(20, 62, 8, 1)
  rect(36, 62, 8, 1)
  color(C.scratch) -- scratches and a dent
  rect(6, 59, 5, 1)
  rect(8, 60, 4, 1)
  rect(50, 63, 1, 4)
  rect(49, 64, 3, 1)
  color(C.steel)
  rect(26, 50, 12, 6) -- the neck seal

  -- The helmet, sinking as he nods off.
  local y = s
  color(C.armourDark)
  rect(14, 9 + y, 36, 44)
  color(C.armour)
  rect(16, 8 + y, 32, 42)
  rect(14, 14 + y, 36, 30)
  color(C.armourHi)
  rect(18, 9 + y, 12, 2) -- light on the dome
  rect(15, 15 + y, 2, 10)
  color(C.armourDark)
  rect(30, 4 + y, 4, 12) -- the crest
  color(C.armour)
  rect(31, 4 + y, 2, 11)
  -- The visor: a wide band, amber glass over the dark, his eye in it.
  color(C.visor)
  rect(17, 24 + y, 30, 12)
  rect(19, 23 + y, 26, 14)
  -- The eye behind it (his left, our right), lit amber by the glass.
  color(C.skin)
  rect(33, 26 + y, 10, 8)
  color(C.white)
  rect(35, 28 + y, 6, 3)
  color(C.iris)
  rect(37, 28 + y, 2, 3)
  -- The lid, coming down over it.
  local lidRows = math.floor(self.lid * 4 + 0.5)
  if lidRows > 0 then
    color(C.skin)
    rect(34, 27 + y, 8, math.min(4, lidRows))
    color({ 0.35, 0.22, 0.17 })
    rect(34, 27 + y + math.min(4, lidRows) - 1, 8, 1) -- its edge, lashes
  end
  -- The glass over it all, and a streak of light across it.
  love.graphics.setColor(C.glass[1], C.glass[2], C.glass[3], 0.35)
  rect(17, 24 + y, 30, 12)
  rect(19, 23 + y, 26, 14)
  love.graphics.setColor(1, 0.9, 0.6, 0.55)
  rect(20, 25 + y, 6, 1)
  rect(22, 26 + y, 4, 1)
  -- The jaw guard and its vents.
  color(C.armourDark)
  rect(20, 38 + y, 24, 13)
  color(C.armour)
  rect(21, 38 + y, 22, 11)
  color(C.armourDark)
  for k = 0, 3 do
    rect(25 + k * 4, 42 + y, 2, 5)
  end
  color(C.scratch)
  rect(40, 18 + y, 1, 5) -- a gouge on the dome
  rect(41, 17 + y, 1, 2)

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

local quads = {}
local function quad(y, h)
  local key = y * 128 + h
  quads[key] = quads[key] or love.graphics.newQuad(0, y, Face.W, h, Face.W, Face.H)
  return quads[key]
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel.
function Face:draw(x, y, scale)
  local canvas = self:render()
  local ox, oy = x - Face.W / 2 * scale, y - Face.H / 2 * scale
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, ox, oy, 0, scale, scale)
  -- Heck's light on him from below: the lower part of him again, added in
  -- red, stronger towards the bottom (only where he is, not round him).
  love.graphics.setBlendMode("add")
  local flicker = 0.9 + 0.1 * math.sin(self.t * 2.3)
  for k = 0, 3 do
    local row = math.floor(Face.H * (0.55 + k * 0.1))
    love.graphics.setColor(1, 0.25, 0.04, (0.05 + k * 0.05) * flicker)
    love.graphics.draw(canvas, quad(row, Face.H - row), ox, oy + row * scale, 0, scale, scale)
  end
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1)
end

return Face
