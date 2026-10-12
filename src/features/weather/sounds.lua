-- The weather's noises, synthesised at load: rain as a hiss that loops
-- under everything, and thunder, a crack and a long rumble played where the
-- lightning is (close) or quietly from far off (a flash in the sky).

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.7, -- default of the "weather" channel
  refDistance = 500,
  maxDistance = 4000,
}

local bank = {} -- name -> base Source
local rain = nil -- the looping rain, while it rains

local function make(seconds, build)
  local buf = Synth.newBuffer(seconds)
  build(buf)
  return love.audio.newSource(buf:toSoundData(0.9), "static")
end

function Sounds.load()
  Audio.registerChannel("weather", "Weather: rain and thunder", Sounds.volume, function()
    Sounds.play("thunder")
  end)

  -- Thunder: a crack right overhead and a long rumble rolling away.
  bank.thunder = make(2.8, function(buf)
    buf:noiseBurst(0, 0.08, { amp = 1.0, decay = 0.02 })
    buf:sweep(0, 0.2, 900, 120, { wave = "saw", amp = 0.5, decay = 0.06 })
    buf:noiseBurst(0.03, 2.7, { amp = 0.8, decay = 0.9 })
    buf:sweep(0.05, 2.5, 90, 35, { wave = "sine", amp = 0.6, decay = 1.0 })
    buf:drive(2.4)
    buf:lowpass(1600)
  end)
  bank.thunder:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)

  -- Rolling thunder far off: no crack, just the rumble.
  bank.rumble = make(3.2, function(buf)
    buf:noiseBurst(0, 3.1, { amp = 0.7, decay = 1.2 })
    buf:sweep(0, 3.0, 70, 30, { wave = "sine", amp = 0.7, decay = 1.3 })
    buf:lowpass(500)
  end)

  -- Rain: two seconds of steady hiss (white noise loops without a seam).
  bank.rain = make(2, function(buf)
    buf:noiseBurst(0, 2, { amp = 0.6, decay = 1e9 })
    buf:highpass(400)
    buf:lowpass(5000)
  end)
end

--- Play `name`: at (x, y) when given, else from everywhere (a far rumble).
function Sounds.play(name, x, y, pitch, volume)
  local base = bank[name]
  if not base then
    return
  end
  local s = base:clone()
  if x then
    s:setPosition(x, 0, y)
  else
    s:setRelative(true)
  end
  s:setPitch(pitch or 1)
  s:setVolume((volume or 1) * Audio.volume("weather"))
  s:play()
end

--- The rain's loop at `level` (0 stops it), every frame.
function Sounds.rain(level)
  if level <= 0.001 then
    if rain then
      rain:stop()
      rain = nil
    end
    return
  end
  if not rain and bank.rain then
    rain = bank.rain:clone()
    rain:setRelative(true)
    rain:setLooping(true)
    rain:play()
  end
  if rain then
    rain:setVolume(0.35 * level * Audio.volume("weather"))
  end
end

return Sounds
