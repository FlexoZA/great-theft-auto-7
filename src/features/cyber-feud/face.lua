-- VEX's face (docs/cyber-feud.md, "VEX"): a hologram on a dashboard screen,
-- head and shoulders. Drawn with primitives onto a 64x72 canvas and scaled
-- up with nearest filtering, the way A-Man's and Karen's are.
--
-- A hard-cut black bob with a green sheen, long on her left and shaved to
-- stubble on her right; a pale face, grey-green under the hologram; her left
-- eye natural and dark, her right a ring optic glowing green with a bright
-- pinpoint; a thin smile a little too wide; a green circuit line from the
-- corner of her mouth down to her chin; a high-necked jacket with glowing
-- seams. Over it all a green wash, rolling scanlines and now and then a
-- slice of her slipping sideways; while she talks, more of them.
--
-- `face:draw(x, y, scale, tell, opts)`: `tell` (a colour, optional) splits a
-- ghost of her off in it, her slices jittering harder: the tell, when she has
-- just sold you to someone (magenta for Halcyon, cyan for the Static).
-- `opts` (optional): `alpha` how solid she is (a projection over the Roof is
-- faint), `broken` 0..1 how far she is coming apart (the Roof's relays going
-- down): more slices slipping further, frames missing, her colour dropping out.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local C = {
  jacket = { 0.24, 0.29, 0.30 }, -- a hologram: even her darks carry some light
  jacketDark = { 0.17, 0.21, 0.22 },
  seam = { 0.43, 1.00, 0.60 },
  skin = { 0.72, 0.78, 0.74 },
  shade = { 0.55, 0.61, 0.57 },
  hair = { 0.11, 0.22, 0.18 },
  hairHi = { 0.24, 0.45, 0.37 },
  stubble = { 0.36, 0.44, 0.40 },
  white = { 0.85, 0.89, 0.86 },
  iris = { 0.10, 0.14, 0.13 },
  optic = { 0.43, 1.00, 0.60 },
  opticDark = { 0.11, 0.36, 0.21 },
  lip = { 0.49, 0.42, 0.45 },
  mouth = { 0.10, 0.08, 0.09 },
  tattoo = { 0.43, 1.00, 0.60 },
}

Face.GREEN = C.seam

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", x, y, w, h)
end

function Face.new()
  local self = setmetatable({}, Face)
  self.canvas = Pixel.canvas(Face.W, Face.H)
  self.t = 0
  self.blink = 0
  self.look = 0 -- where her natural eye glances, -1 to 1; the optic never moves
  self.lookTimer = 1
  self.talking = false -- set while her line is being typed out
  self.slips = {} -- { y, h, dx, t } slices of her slipping sideways
  self.freeze = 0 -- seconds she is stuck, buffering
  return self
end

function Face:update(dt)
  self.t = self.t + dt
  self.blink = math.max(0, self.blink - dt)
  if love.math.random() < dt * 0.35 then
    self.blink = 0.12
  end
  self.lookTimer = self.lookTimer - dt
  if self.lookTimer <= 0 then
    local r = love.math.random()
    self.look = r < 0.3 and -1 or r < 0.6 and 1 or 0
    self.lookTimer = 0.8 + love.math.random() * 2
  end
  self.freeze = math.max(0, self.freeze - dt)
  if self.freeze == 0 and love.math.random() < dt * 0.08 then
    self.freeze = 0.25 -- buffering
  end
  -- Slices slip now and then, more while she talks.
  for i = #self.slips, 1, -1 do
    local s = self.slips[i]
    s.t = s.t - dt
    if s.t <= 0 then
      table.remove(self.slips, i)
    end
  end
  if love.math.random() < dt * (self.talking and 4 or 0.7) then
    self.slips[#self.slips + 1] = {
      y = love.math.random(6, Face.H - 8), h = love.math.random(1, 3),
      dx = (love.math.random() < 0.5 and -1 or 1) * love.math.random(1, 3), t = 0.08 + love.math.random() * 0.12,
    }
  end
end

function Face:render()
  if self.freeze > 0 and self.rendered then
    return self.canvas -- stuck on the last frame
  end
  self.rendered = true
  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.origin() -- (drawn in the world too, under the camera: the art is in canvas pixels)
  love.graphics.clear(0, 0, 0, 0)

  -- Shoulders and the high collar, its seams lit.
  color(C.jacketDark)
  rect(8, 60, 48, 12)
  color(C.jacket)
  rect(12, 58, 40, 14)
  rect(22, 54, 20, 6)
  color(C.seam)
  rect(22, 55, 1, 5)
  rect(41, 55, 1, 5)
  rect(31, 60, 2, 12)
  -- Neck, face and jaw.
  color(C.shade)
  rect(27, 48, 10, 7)
  color(C.skin)
  rect(22, 20, 20, 26)
  rect(24, 46, 16, 3)
  rect(26, 49, 12, 2)
  rect(21, 26, 1, 14)
  rect(42, 26, 1, 14)
  color(C.shade)
  rect(22, 40, 2, 6)
  rect(40, 40, 2, 6)
  rect(26, 50, 12, 1)
  -- The shaved side, then the bob: long down her left, the fringe cut blunt.
  color(C.stubble)
  rect(39, 17, 5, 14)
  color(C.hair)
  rect(18, 14, 24, 8)
  rect(16, 18, 8, 32)
  rect(18, 22, 20, 4)
  rect(14, 28, 4, 22)
  color(C.hairHi)
  rect(20, 15, 10, 1)
  rect(16, 24, 1, 20)
  -- Eyes: the natural one glancing about, the optic staring.
  if self.blink > 0 then
    color(C.shade)
    rect(25, 33, 6, 1)
  else
    color(C.white)
    rect(25, 32, 6, 3)
    color(C.iris)
    rect(27 + self.look, 32, 3, 3)
  end
  color(C.opticDark)
  rect(34, 31, 7, 5)
  color(C.optic)
  rect(35, 31, 5, 1)
  rect(35, 35, 5, 1)
  rect(34, 32, 1, 3)
  rect(40, 32, 1, 3)
  love.graphics.setColor(1, 1, 1, 0.6 + 0.4 * math.sin(self.t * 6))
  rect(37, 33, 1, 1)
  color(C.hair) -- brows
  rect(25, 30, 6, 1)
  rect(34, 29, 6, 1)
  -- The smile, a little too wide; it opens while she talks.
  color(C.lip)
  rect(27, 43, 10, 1)
  rect(26, 42, 1, 1)
  rect(37, 42, 1, 1)
  rect(25, 41, 1, 1)
  rect(38, 41, 1, 1)
  if self.talking and math.floor(self.t * 9) % 2 == 0 then
    color(C.mouth)
    rect(28, 43, 8, 2)
  end
  -- The data port's circuit line, mouth to chin.
  color(C.tattoo)
  rect(38, 44, 1, 3)
  rect(37, 47, 1, 3)
  rect(36, 50, 2, 1)
  rect(39, 44, 1, 1)

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

local quads = {}
local function quad(y, h)
  local key = y * 8 + h
  quads[key] = quads[key] or love.graphics.newQuad(0, y, Face.W, h, Face.W, Face.H)
  return quads[key]
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel; `tell` a
--- colour for the ghost that splits off her when she sells you; `opts` how
--- solid and how broken she is (see the top).
function Face:draw(x, y, scale, tell, opts)
  local alpha = opts and opts.alpha or 1
  local broken = opts and opts.broken or 0
  if broken > 0 and love.math.random() < broken * 0.25 then
    return -- a frame missing
  end
  local canvas = self:render()
  local ox, oy = x - Face.W / 2 * scale, y - Face.H / 2 * scale
  if tell then
    local j = 2 + math.floor(math.sin(self.t * 23) * 1.5 + 0.5)
    love.graphics.setColor(tell[1], tell[2], tell[3], 0.55 * alpha)
    love.graphics.draw(canvas, ox - j * scale, oy, 0, scale, scale)
    love.graphics.draw(canvas, ox + (j - 1) * scale, oy + scale, 0, scale, scale)
  end
  local grey = broken * 0.6 -- her colour dropping out
  local r, g, b = 0.85 + (0.7 - 0.85) * grey, 1 + (0.7 - 1) * grey, 0.9 + (0.7 - 0.9) * grey
  love.graphics.setColor(r, g, b, 0.92 * alpha)
  love.graphics.draw(canvas, ox, oy, 0, scale, scale)
  -- Slices slipping sideways; with the tell, a few more every frame; broken, more and further.
  local slips = self.slips
  if tell or broken > 0 then
    slips = {}
    for i = 1, (tell and 3 or 0) + math.floor(broken * 8 + 0.5) do
      local reach = 5 + math.floor(broken * 10)
      local dx = love.math.random(-reach, reach)
      slips[i] = { y = love.math.random(6, Face.H - 8), h = love.math.random(1, 3), dx = dx }
    end
  end
  for _, s in ipairs(slips) do
    love.graphics.setColor(r, g, b, 0.95 * alpha)
    love.graphics.draw(canvas, quad(s.y, s.h), ox + s.dx * scale, oy + s.y * scale, 0, scale, scale)
  end
  -- The hologram: a green wash and scanlines rolling down.
  love.graphics.setColor(Face.GREEN[1], Face.GREEN[2], Face.GREEN[3], 0.07 * alpha)
  love.graphics.rectangle("fill", ox, oy, Face.W * scale, Face.H * scale)
  love.graphics.setColor(0, 0, 0, 0.28 * alpha)
  local roll = math.floor(self.t * 20) % 4
  for sy = 0, Face.H - 1, 4 do
    love.graphics.rectangle("fill", ox, oy + (sy + roll) % Face.H * scale, Face.W * scale, scale)
  end
  love.graphics.setColor(1, 1, 1)
end

return Face
