-- Weapon sound effects, synthesised at load. Every play is a clone of a base
-- source positioned in the world, so shots overlap freely and pan/fade
-- relative to the listener (which the game state keeps at your car).

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "weapons" channel
  refDistance = 260,
  maxDistance = 2200,
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
  Audio.registerChannel("weapons", "Guns and explosions", Sounds.volume, function()
    Sounds.play("shot", 0, 0, 1)
  end)

  -- Shot: a sharp crack. Noise snap plus a fast downward zap, driven for punch.
  bank.shot = make(0.16, function(buf)
    buf:noiseBurst(0, 0.12, { amp = 0.8, decay = 0.03 })
    buf:sweep(0, 0.07, 1100, 120, { wave = "sine", amp = 0.9, decay = 0.025 })
    buf:sweep(0, 0.05, 2200, 400, { wave = "square", amp = 0.25, decay = 0.012 })
    buf:drive(3)
    buf:lowpass(3800)
  end)

  -- Uzi: a shorter, thinner snap than the pistol, so a burst reads as a
  -- rattle rather than a row of shots.
  bank.uzi = make(0.09, function(buf)
    buf:noiseBurst(0, 0.06, { amp = 0.7, decay = 0.012 })
    buf:sweep(0, 0.04, 1600, 300, { wave = "sine", amp = 0.7, decay = 0.012 })
    buf:sweep(0, 0.03, 3000, 700, { wave = "square", amp = 0.2, decay = 0.008 })
    buf:drive(2.5)
    buf:highpass(300)
    buf:lowpass(5000)
  end)

  -- Reloads are built from small metal clicks: a sharp tick of noise over a
  -- short ring, lower and duller for heavier parts.
  local function click(buf, t, freq, amp)
    buf:noiseBurst(t, 0.03, { amp = amp, decay = 0.006 })
    buf:tone(t, 0.04, freq, { wave = "square", amp = amp * 0.35, attack = 0.001, decay = 0.012, sustain = 0 })
  end
  --- A slide or bolt dragged back: a rising scrape.
  local function rack(buf, t, dur, f0, f1, amp)
    buf:noiseBurst(t, dur, { amp = amp * 0.5, decay = dur })
    buf:sweep(t, dur, f0, f1, { wave = "saw", amp = amp * 0.25, decay = dur })
  end

  -- Pistol reload (1.2 s): magazine out, magazine slapped in, slide racked
  -- and let go.
  bank["reload-pistol"] = make(1.2, function(buf)
    click(buf, 0.02, 1900, 0.5) -- release catch
    rack(buf, 0.08, 0.1, 700, 400, 0.4) -- magazine slides out
    click(buf, 0.55, 900, 0.8) -- new magazine seated
    click(buf, 0.58, 1300, 0.4)
    rack(buf, 0.85, 0.12, 500, 1400, 0.6) -- slide back
    click(buf, 0.99, 1700, 0.8) -- and home
    buf:highpass(250)
    buf:drive(1.6)
    buf:lowpass(6000)
  end)

  -- Uzi reload (1.8 s): a longer magazine, a heavier seat, then the bolt
  -- pulled back and snapped forward.
  bank["reload-uzi"] = make(1.8, function(buf)
    click(buf, 0.02, 1500, 0.5)
    rack(buf, 0.08, 0.16, 600, 300, 0.45)
    click(buf, 0.85, 700, 0.9) -- magazine rocked in
    click(buf, 0.9, 1100, 0.5)
    rack(buf, 1.3, 0.14, 400, 1100, 0.6) -- bolt back
    click(buf, 1.45, 1200, 0.7)
    click(buf, 1.58, 800, 0.9) -- bolt slams forward
    buf:highpass(200)
    buf:drive(1.8)
    buf:lowpass(5500)
  end)

  -- Dry fire: the trigger clicking on an empty chamber.
  bank.dry = make(0.06, function(buf)
    click(buf, 0, 2400, 0.45)
    buf:highpass(800)
  end)

  -- Hit: a metallic clank on the target's bodywork.
  bank.hit = make(0.14, function(buf)
    buf:tone(0, 0.1, 1250, { wave = "sine", amp = 0.5, attack = 0.001, decay = 0.045, sustain = 0, release = 0.01 })
    buf:tone(0, 0.08, 1870, { wave = "sine", amp = 0.3, attack = 0.001, decay = 0.03, sustain = 0, release = 0.01 })
    buf:noiseBurst(0, 0.06, { amp = 0.45, decay = 0.015 })
    buf:highpass(500)
    buf:drive(1.8)
  end)

  -- Explosion: a low boom under a long rolling noise tail.
  bank.explosion = make(0.9, function(buf)
    buf:sweep(0, 0.45, 160, 32, { wave = "sine", amp = 1.0, decay = 0.28 })
    buf:noiseBurst(0, 0.85, { amp = 0.9, decay = 0.22 })
    buf:noiseBurst(0, 0.05, { amp = 0.8, decay = 0.01 })
    buf:lowpass(1100)
    buf:drive(2.2)
  end)
end

--- Play `name` at world position (x, y). pitch defaults to 1.
function Sounds.play(name, x, y, pitch)
  local base = bank[name]
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setPitch(pitch or 1)
  s:setVolume(Audio.volume("weapons"))
  s:play()
  return s
end

--- For tests.
function Sounds.bank()
  return bank
end

return Sounds
