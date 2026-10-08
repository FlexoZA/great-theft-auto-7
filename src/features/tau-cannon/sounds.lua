-- The tau cannon's noises, synthesised at load and added to the weapons'
-- sound bank, so they play in the world on the "weapons" channel like any
-- gun's:
--   tau-zap     a quick bolt: a bright electric crack falling away
--   tau-blast   a charged shot: the crack with a heavy thump and a ringing tail
--   tau-charge  the whine of it charging, climbing for the full charge and
--               then warbling, louder and higher, as it overloads

local Sounds = require("src.features.weapons.sounds")

local TauSounds = {}

function TauSounds.load(chargeTime, overload)
  Sounds.add("tau-zap", Sounds.make(0.3, function(buf)
    buf:sweep(0, 0.18, 2600, 420, { wave = "square", amp = 0.35, decay = 0.05 })
    buf:sweep(0, 0.12, 5200, 1400, { wave = "saw", amp = 0.18, decay = 0.03 })
    buf:noiseBurst(0, 0.08, { amp = 0.4, decay = 0.015 })
    buf:highpass(500)
  end, 0.75))

  Sounds.add("tau-blast", Sounds.make(1.1, function(buf)
    buf:sweep(0, 0.5, 1800, 140, { wave = "square", amp = 0.45, decay = 0.12 })
    buf:sweep(0, 0.6, 160, 38, { wave = "sine", amp = 0.9, decay = 0.2 })
    buf:noiseBurst(0, 0.4, { amp = 0.6, decay = 0.06 })
    buf:tone(0.02, 0.6, 1320, { wave = "sine", amp = 0.12, attack = 0.002, decay = 0.25, sustain = 0 })
    buf:drive(1.4)
  end, 0.95))

  local total = chargeTime + overload
  Sounds.add("tau-charge", Sounds.make(total, function(buf)
    -- Climbing to the full charge...
    buf:sweep(0, chargeTime, 180, 1100, { wave = "saw", amp = 0.22, decay = 1e6 })
    buf:sweep(0, chargeTime, 360, 2200, { wave = "square", amp = 0.06, decay = 1e6 })
    -- ...then held there, warbling harder until it lets go.
    buf:tone(chargeTime, overload, 1100, { wave = "saw", amp = 0.24, attack = 0.01, decay = 1e6, sustain = 1,
      release = 0.01, vibRate = 9, vibDepth = 1.5 })
    buf:tone(chargeTime + overload * 0.5, overload * 0.5, 1650, { wave = "square", amp = 0.08, attack = 0.3,
      decay = 1e6, sustain = 1, release = 0.01, vibRate = 14, vibDepth = 2 })
    buf:lowpass(4200)
  end, 0.6))
end

return TauSounds
