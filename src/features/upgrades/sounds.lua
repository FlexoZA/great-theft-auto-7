-- Upgrade sounds: a rising two-note chime when a purchase goes through and a
-- flat buzz when it doesn't. Synthesised once at load, not positional: they
-- are about your own wallet, so they play at the ear.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = { volume = 0.6 }
local chime, buzz

function Sounds.load()
  local buf = Synth.newBuffer(0.5)
  buf:tone(0, 0.12, 880, { wave = "square", amp = 0.22, attack = 0.003, decay = 0.12, sustain = 0.3, release = 0.03 })
  buf:tone(0.11, 0.3, 1318, {
    wave = "square", amp = 0.22, attack = 0.003, decay = 0.25, sustain = 0.2, release = 0.06,
  })
  buf:tone(0.11, 0.3, 2637, { wave = "sine", amp = 0.08, attack = 0.003, decay = 0.25, sustain = 0.2, release = 0.06 })
  buf:lowpass(6500)
  chime = love.audio.newSource(buf:toSoundData(0.8), "static")
  chime:setRelative(true)

  buf = Synth.newBuffer(0.25)
  buf:tone(0, 0.18, 110, { wave = "saw", amp = 0.3, attack = 0.005, decay = 0.2, sustain = 0.5, release = 0.04 })
  buf:tone(0, 0.18, 116, { wave = "saw", amp = 0.2, attack = 0.005, decay = 0.2, sustain = 0.5, release = 0.04 })
  buf:lowpass(1200)
  buzz = love.audio.newSource(buf:toSoundData(0.7), "static")
  buzz:setRelative(true)

  Audio.registerChannel("upgrades", "Upgrade shop", Sounds.volume, function()
    Sounds.play("chime")
  end)
end

--- "chime" or "buzz".
function Sounds.play(which)
  local base = which == "buzz" and buzz or chime
  if not base then
    return
  end
  local s = base:clone()
  s:setVolume(Audio.volume("upgrades"))
  s:play()
end

return Sounds
