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

  -- AK-47: a fuller crack than the pistol with a low thump behind it, so a
  -- burst reads as a rifle hammering rather than the uzi's rattle.
  bank.ak47 = make(0.14, function(buf)
    buf:noiseBurst(0, 0.1, { amp = 0.85, decay = 0.022 })
    buf:sweep(0, 0.06, 900, 110, { wave = "sine", amp = 0.9, decay = 0.02 })
    buf:sweep(0, 0.04, 2600, 500, { wave = "square", amp = 0.2, decay = 0.01 })
    buf:drive(3.2)
    buf:lowpass(3400)
  end)

  -- Shotgun: a deep boom and a long spray of noise, the loudest gun there is.
  bank.shotgun = make(0.32, function(buf)
    buf:sweep(0, 0.16, 420, 45, { wave = "sine", amp = 1.0, decay = 0.06 })
    buf:noiseBurst(0, 0.26, { amp = 0.95, decay = 0.07 })
    buf:noiseBurst(0, 0.03, { amp = 0.8, decay = 0.008 })
    buf:drive(3.5)
    buf:lowpass(2600)
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

  -- AK-47 reload (2.0 s): the banana magazine rocked out and a fresh one
  -- rocked in with a heavy clack, then the charging handle pulled and let go.
  bank["reload-ak47"] = make(2.0, function(buf)
    click(buf, 0.02, 1300, 0.5) -- catch
    rack(buf, 0.08, 0.2, 500, 260, 0.45) -- magazine rocks out
    click(buf, 0.95, 600, 1.0) -- new one rocked in
    click(buf, 1.0, 950, 0.5)
    rack(buf, 1.45, 0.16, 350, 1000, 0.6) -- charging handle back
    click(buf, 1.62, 1000, 0.7)
    click(buf, 1.75, 700, 1.0) -- bolt home
    buf:highpass(180)
    buf:drive(1.8)
    buf:lowpass(5000)
  end)

  -- Shotgun reload (2.4 s): shells thumbed into the tube one after another,
  -- then the pump racked back and forward.
  bank["reload-shotgun"] = make(2.4, function(buf)
    for i = 0, 5 do
      click(buf, 0.1 + i * 0.28, 1100 - i * 40, 0.55) -- a shell clicks past the loading gate
      click(buf, 0.13 + i * 0.28, 700, 0.3)
    end
    rack(buf, 1.85, 0.14, 300, 900, 0.7) -- pump back
    click(buf, 2.0, 900, 0.8)
    rack(buf, 2.1, 0.12, 900, 300, 0.7) -- and forward
    click(buf, 2.24, 600, 1.0)
    buf:highpass(160)
    buf:drive(1.8)
    buf:lowpass(5200)
  end)

  -- Rocket reload (2.2 s): a missile slid down the tube, seated with a
  -- heavy clunk, and the launcher armed.
  bank["reload-rocket"] = make(2.2, function(buf)
    click(buf, 0.05, 1200, 0.5) -- breech open
    rack(buf, 0.3, 0.5, 250, 160, 0.55) -- missile slides in
    click(buf, 0.95, 380, 1.0) -- seated
    click(buf, 1.0, 700, 0.5)
    click(buf, 1.7, 1500, 0.6) -- breech shut
    click(buf, 1.95, 2100, 0.45) -- armed
    buf:highpass(120)
    buf:drive(1.8)
    buf:lowpass(5000)
  end)

  -- Sniper reload (5 s): the bolt thrown open, five rounds pressed down
  -- into the box one at a time, a pause to settle, and the bolt run home.
  bank["reload-sniper"] = make(5.0, function(buf)
    click(buf, 0.1, 900, 0.7) -- bolt up
    rack(buf, 0.18, 0.18, 400, 1100, 0.6) -- and back
    for i = 0, 4 do
      local t = 0.9 + i * 0.62
      click(buf, t, 1300 - i * 30, 0.5) -- a round pressed down past the lips
      click(buf, t + 0.05, 650, 0.35)
    end
    rack(buf, 4.35, 0.16, 1100, 400, 0.7) -- bolt forward
    click(buf, 4.55, 700, 0.9) -- and down, locked
    buf:highpass(150)
    buf:drive(1.8)
    buf:lowpass(5200)
  end)

  -- Sniper: one huge flat crack with a long rolling echo behind it.
  bank.sniper = make(1.1, function(buf)
    buf:noiseBurst(0, 0.05, { amp = 1.0, decay = 0.01 })
    buf:sweep(0, 0.12, 1400, 90, { wave = "sine", amp = 1.0, decay = 0.05 })
    buf:sweep(0, 0.08, 3200, 600, { wave = "square", amp = 0.3, decay = 0.015 })
    buf:noiseBurst(0.04, 1.0, { amp = 0.45, decay = 0.35 })
    buf:sweep(0.1, 0.9, 140, 60, { wave = "sine", amp = 0.35, decay = 0.4 })
    buf:drive(3.5)
    buf:lowpass(3000)
  end)

  -- Rocket launch: a thump out of the tube and the motor hissing away.
  bank.rocket = make(0.8, function(buf)
    buf:sweep(0, 0.14, 190, 55, { wave = "sine", amp = 0.9, decay = 0.08 })
    buf:noiseBurst(0, 0.04, { amp = 0.7, decay = 0.01 })
    buf:noiseBurst(0.02, 0.75, { amp = 0.55, decay = 0.3 })
    buf:sweep(0.02, 0.6, 520, 260, { wave = "saw", amp = 0.12, decay = 0.3 })
    buf:drive(1.8)
    buf:lowpass(2800)
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
