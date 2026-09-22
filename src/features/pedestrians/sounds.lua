-- Pedestrian sound effects, synthesised at load like the weapon ones. Every
-- play is a clone of a base source positioned in the world, so a splat on the
-- far side of the map pans and fades instead of going off in your ear (the
-- game state keeps the listener at your car).

local Synth = require("src.audio.synth")

local Sounds = {
  splatVolume = 0.7,
  yelpVolume = 0.4,
  refDistance = 260, -- px: full volume inside this radius
  maxDistance = 2000, -- px: quietest beyond this
}

local bank = {} -- name -> base Source

local function make(seconds, build)
  local buf = Synth.newBuffer(seconds)
  build(buf)
  local source = love.audio.newSource(buf:toSoundData(0.9), "static")
  source:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  return source
end

function Sounds.load()
  -- Splat: a wet burst over a short bony thud, all of it low and dull.
  bank.splat = make(0.34, function(buf)
    buf:sweep(0, 0.13, 240, 38, { wave = "sine", amp = 1.0, decay = 0.05 })
    buf:noiseBurst(0, 0.16, { amp = 0.85, decay = 0.035 })
    buf:noiseBurst(0.03, 0.22, { amp = 0.45, decay = 0.1 }) -- the splatter tail
    buf:lowpass(1500)
    buf:drive(2.2)
  end)

  -- Two panic cries. Sawtooth through a narrow band is about as close to a
  -- voice as this synth gets; the pitch they are played at does the rest.
  bank.yelp = make(0.3, function(buf)
    buf:sweep(0, 0.07, 340, 660, { wave = "saw", amp = 0.6, decay = 0.2 })
    buf:sweep(0.07, 0.16, 660, 300, { wave = "saw", amp = 0.6, decay = 0.11 })
    buf:tone(0, 0.2, 520, { wave = "sine", amp = 0.25, decay = 0.1, sustain = 0, vibRate = 9, vibDepth = 0.5 })
    buf:highpass(240)
    buf:lowpass(2600)
  end)

  bank.shout = make(0.26, function(buf)
    buf:tone(0, 0.16, 250, { wave = "saw", amp = 0.6, decay = 0.09, sustain = 0, vibRate = 6, vibDepth = 0.3 })
    buf:sweep(0.04, 0.14, 300, 190, { wave = "saw", amp = 0.4, decay = 0.08 })
    buf:highpass(180)
    buf:lowpass(2000)
  end)
end

--- Play `name` at world position (x, y). Extra arguments are optional.
function Sounds.play(name, x, y, pitch, volume)
  local base = bank[name]
  if not base then
    return nil
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setPitch(pitch or 1)
  s:setVolume(volume or Sounds.splatVolume)
  s:play()
  return s
end

local random = love.math.random

--- A pedestrian panicking at (x, y): one of the two cries, at a voice picked
--- from the pedestrian's id so the same person always sounds the same.
function Sounds.panic(id, x, y)
  local voice = id % 7
  local name = voice < 3 and "shout" or "yelp"
  local pitch = 0.78 + voice * 0.09 + random() * 0.08
  Sounds.play(name, x, y, pitch, Sounds.yelpVolume)
end

--- For tests.
function Sounds.bank()
  return bank
end

return Sounds
