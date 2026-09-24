-- A fire on the ground, drawn fresh every frame: a scorch mark and a glow
-- under the cars, and over them flame tongues that flicker and sway (three
-- layers, red to yellow, each tongue's height driven by noise), embers
-- drifting up and a wisp of smoke. It flares up when lit and dies down
-- over its last few seconds. Plus the whoosh of one catching.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Fire = {}

Fire.GROW = 0.6 -- seconds a new fire takes to flare up
Fire.DIE = 4 -- seconds it takes to die down at the end
Fire.TONGUES = 5
Fire.EMBERS = 5

local LAYERS = {
  { scale = 1.0, color = { 0.85, 0.16, 0.04 } }, -- deep red outside
  { scale = 0.72, color = { 1.0, 0.48, 0.08 } }, -- orange
  { scale = 0.42, color = { 1.0, 0.88, 0.35 } }, -- yellow heart
}

local noise = love.math.noise
local sin, cos = math.sin, math.cos

--- How big the fire is right now, 0..1: flaring up, burning, dying down.
function Fire.strength(f)
  local grow = math.min(1, f.t / Fire.GROW)
  local die = math.max(0, math.min(1, (f.seconds - f.t) / Fire.DIE))
  return grow * (0.3 + 0.7 * die), die
end

--- Under the cars: blackened ground that stays to the end, and a warm glow
--- on it that breathes with the flames.
function Fire.drawGround(f, r, time)
  local k, die = Fire.strength(f)
  local fade = math.min(1, (f.seconds - f.t) / 1.0) -- the scorch goes in the last second
  love.graphics.setColor(0.08, 0.06, 0.05, 0.55 * fade)
  love.graphics.ellipse("fill", f.x, f.y + 2, r * 1.25, r * 0.95, 20)
  love.graphics.setColor(0.18, 0.1, 0.06, 0.45 * fade)
  love.graphics.ellipse("fill", f.x + 3, f.y + 4, r * 0.8, r * 0.6, 16)
  local flicker = 0.75 + 0.25 * noise(time * 4, f.seed)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 0.45, 0.08, 0.10 * k * flicker)
  love.graphics.circle("fill", f.x, f.y, r * (1.5 + 0.2 * flicker), 28)
  love.graphics.setColor(1, 0.6, 0.15, 0.16 * k * flicker * (0.5 + 0.5 * die))
  love.graphics.circle("fill", f.x, f.y, r * 1.05, 24)
  love.graphics.setBlendMode("alpha")
end

--- One flame tongue: a rounded base at (cx, by), `w` wide, rising `h` to a
--- tip that sways `sway` px sideways.
local function tongue(cx, by, w, h, sway)
  local pts = {}
  for i = 0, 6 do
    local a = i / 6 * math.pi
    pts[#pts + 1] = cx + cos(a) * w
    pts[#pts + 1] = by + sin(a) * w * 0.55
  end
  pts[#pts + 1] = cx - w * 0.8 + sway * 0.35
  pts[#pts + 1] = by - h * 0.4
  pts[#pts + 1] = cx + sway
  pts[#pts + 1] = by - h
  pts[#pts + 1] = cx + w * 0.8 + sway * 0.35
  pts[#pts + 1] = by - h * 0.4
  love.graphics.polygon("fill", pts)
end

--- Over the cars: the flames themselves, embers and smoke.
function Fire.drawFlames(f, r, time)
  local k = Fire.strength(f)
  if k <= 0.01 then
    return
  end
  local s = r * k
  local seed = f.seed
  -- Smoke first, so the flames stand in front of it.
  for i = 0, 2 do
    local phase = (time * 0.35 + i / 3 + seed) % 1
    local sx = f.x + sin(time * 0.8 + i * 2 + seed * 7) * s * 0.6 + phase * 10
    local sy = f.y - s * 1.4 - phase * s * 3.5
    love.graphics.setColor(0.2, 0.19, 0.19, 0.28 * (1 - phase) * k)
    love.graphics.circle("fill", sx, sy, s * (0.45 + phase * 0.9), 14)
  end
  love.graphics.setBlendMode("add")
  for _, layer in ipairs(LAYERS) do
    local c = layer.color
    love.graphics.setColor(c[1], c[2], c[3], 0.85)
    for t = 1, Fire.TONGUES do
      local off = (t - (Fire.TONGUES + 1) / 2) / Fire.TONGUES -- -0.4 .. 0.4
      local lick = noise(time * 3.2 + t * 1.7, seed * 10 + t)
      local middle = 1 - math.abs(off) * 1.4 -- the middle tongues stand tallest
      local w = s * 0.42 * layer.scale
      local h = s * (0.9 + 1.5 * lick) * middle * layer.scale + w
      local sway = sin(time * 7 + t * 1.3 + seed * 5) * w * 0.7
      local cx = f.x + off * s * 1.5 + sin(time * 2.1 + t) * s * 0.06
      tongue(cx, f.y + s * 0.25 - (1 - layer.scale) * s * 0.3, w, h, sway)
    end
  end
  -- Embers flicking up out of it.
  for i = 0, Fire.EMBERS - 1 do
    local phase = (time * 0.9 + i / Fire.EMBERS + seed) % 1
    local ex = f.x + sin(seed * 13 + i * 2.1) * s * 0.8 + sin(time * 3 + i) * 4
    local ey = f.y - s * 0.5 - phase * s * 3.2
    love.graphics.setColor(1, 0.7 - phase * 0.4, 0.2, (1 - phase) * k)
    love.graphics.circle("fill", ex, ey, 1.6 * (1 - phase * 0.5), 6)
  end
  love.graphics.setBlendMode("alpha")
end

-- Sound ---------------------------------------------------------------------

local whoosh

function Fire.load()
  Audio.registerChannel("fires", "Fires", 0.6, function()
    Fire.play(0, 0)
  end)
  -- A fire catching: a soft whoomp of air and a crackle.
  local buf = Synth.newBuffer(0.7)
  buf:sweep(0, 0.35, 90, 45, { wave = "sine", amp = 0.6, decay = 0.12 })
  buf:noiseBurst(0, 0.6, { amp = 0.45, decay = 0.18 })
  for i = 0, 5 do
    buf:noiseBurst(0.1 + i * 0.08, 0.03, { amp = 0.35, decay = 0.008 })
  end
  buf:lowpass(2400)
  whoosh = love.audio.newSource(buf:toSoundData(0.8), "static")
  whoosh:setAttenuationDistances(200, 1400)
end

--- A fire catching at world position (x, y).
function Fire.play(x, y)
  if not whoosh then
    return
  end
  local s = whoosh:clone()
  s:setPosition(x, 0, y)
  s:setPitch(0.85 + love.math.random() * 0.3)
  s:setVolume(Audio.volume("fires"))
  s:play()
end

return Fire
