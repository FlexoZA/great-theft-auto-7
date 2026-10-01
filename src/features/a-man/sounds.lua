-- A-Man's noises, synthesised at load and played where they happen, the
-- way the other bosses' are: a base source per sound, cloned per play. His
-- music is theme.lua.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "a-man" channel
  refDistance = 360,
  maxDistance = 2800,
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
  Audio.registerChannel("a-man", "A-Man: the man in the disguise", Sounds.volume, function()
    Sounds.play("appear", 0, 0)
  end)

  -- He is suddenly there: the world's sound sinks away into a deep hum
  -- with something high and thin wavering over it, then cuts off.
  bank.appear = make(1.8, function(buf)
    buf:sweep(0, 1.7, 220, 45, { wave = "sine", amp = 0.8, decay = 1.2 })
    buf:sweep(0, 1.7, 225, 46, { wave = "tri", amp = 0.25, decay = 1.0 })
    buf:tone(0.15, 1.3, 1760, { wave = "sine", amp = 0.08, attack = 0.5, decay = 99, sustain = 1, release = 0.05,
      vibRate = 9, vibDepth = 0.4 })
    buf:noiseBurst(0, 0.5, { amp = 0.2, decay = 0.25 })
    buf:lowpass(2500)
  end)

  -- He is suddenly gone: a quick rising whoop and a click, like a door
  -- shutting somewhere you can't see.
  bank.vanish = make(0.6, function(buf)
    buf:sweep(0, 0.35, 90, 1400, { wave = "sine", amp = 0.6, decay = 0.25 })
    buf:sweep(0, 0.35, 91, 1420, { wave = "tri", amp = 0.2, decay = 0.2 })
    buf:noiseBurst(0.36, 0.02, { amp = 0.5, decay = 0.005 })
    buf:tone(0.36, 0.03, 2200, { wave = "sine", amp = 0.3, attack = 0.001, decay = 0.01, sustain = 0 })
  end)

  -- The briefcase's clasps, snapped open one after the other.
  bank.clasp = make(0.4, function(buf)
    for i = 0, 1 do
      local t = i * 0.16
      buf:noiseBurst(t, 0.015, { amp = 0.7, decay = 0.003 })
      buf:tone(t, 0.04, 2600 - i * 300, { wave = "square", amp = 0.18, attack = 0.001, decay = 0.012, sustain = 0 })
      buf:tone(t, 0.06, 900, { wave = "sine", amp = 0.2, attack = 0.001, decay = 0.02, sustain = 0 })
    end
    buf:highpass(300)
  end)

  -- The tape giving way and the moustache coming off: a ragged rip.
  bank.rip = make(0.5, function(buf)
    local t = 0
    for k = 0, 13 do
      buf:noiseBurst(t, 0.03, { amp = 0.35 + (k % 3) * 0.15, decay = 0.012 })
      t = t + 0.018 + (k % 4) * 0.007
    end
    buf:highpass(1200)
  end)

  -- The turrets waking up: two bright, friendly chirps going up.
  bank.turret = make(0.45, function(buf)
    buf:tone(0, 0.09, 1320, { wave = "sine", amp = 0.5, attack = 0.005, decay = 0.08, sustain = 0.6 })
    buf:tone(0.13, 0.14, 1760, { wave = "sine", amp = 0.5, attack = 0.005, decay = 0.1, sustain = 0.6,
      vibRate = 18, vibDepth = 0.3 })
    buf:tone(0, 0.27, 2640, { wave = "tri", amp = 0.06, attack = 0.005, decay = 0.1, sustain = 0.3 })
  end)

  -- A turret going over: a clatter and a sad whine winding down.
  bank.pop = make(0.7, function(buf)
    buf:noiseBurst(0, 0.05, { amp = 0.5, decay = 0.015 })
    buf:sweep(0.03, 0.6, 1500, 300, { wave = "sine", amp = 0.35, decay = 0.3 })
    buf:highpass(200)
  end)

  -- One step on tiptoe, for when he creeps up on someone.
  bank.tiptoe = make(0.25, function(buf)
    buf:tone(0, 0.08, Synth.freq("E3"), { wave = "tri", amp = 0.6, attack = 0.003, decay = 0.06, sustain = 0 })
    buf:tone(0, 0.02, Synth.freq("E4"), { wave = "square", amp = 0.1, attack = 0.001, decay = 0.01, sustain = 0 })
    buf:lowpass(1800)
  end)
end

--- Play `name` at world position (x, y).
function Sounds.play(name, x, y, pitch)
  local base = bank[name]
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setPitch(pitch or 1)
  s:setVolume(Audio.volume("a-man"))
  s:play()
  return s
end

return Sounds
