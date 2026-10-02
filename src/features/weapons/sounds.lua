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

--- A layer of a gunshot: built, then filtered on its own.
local function layer(seconds, build, hp, lp)
  local buf = Synth.newBuffer(seconds)
  build(buf)
  if hp then
    buf:highpass(hp)
  end
  if lp then
    buf:lowpass(lp)
  end
  return buf
end

--- Add a quieter copy of the whole buffer `delay` seconds later (walking
--- backwards so the copy doesn't echo itself).
local function echo(buf, delay, gain)
  local d = math.floor(delay * Synth.RATE)
  local data = buf.data
  for i = buf.n - 1, d, -1 do
    data[i] = data[i] + data[i - d] * gain
  end
end

--- A gunshot `seconds` long out of layers, each optional:
---   click  { freq, amp }                    the action, a tick before the bang
---   crack  { dur, decay, amp, hp, lp }      the muzzle blast, bright noise
---   body   { f0, f1, dur, decay, amp }      a falling tone that gives the size
---   thump  { f0, f1, dur, decay, amp }      the low end you feel
---   tail   { at, dur, decay, amp, lp }      dark noise dying away
---   echoes { { delay, gain }, ... }         slaps back off the buildings
---   drive                                   soft clipping of the mix
local function gunshot(seconds, o)
  local mix = Synth.newBuffer(seconds)
  if o.click then
    local c = o.click
    layer(seconds, function(buf)
      buf:noiseBurst(0, 0.01, { amp = c.amp, decay = 0.002 })
      buf:tone(0, 0.015, c.freq, { wave = "square", amp = c.amp * 0.5, attack = 0.0005, decay = 0.004, sustain = 0 })
    end, 1500):mixInto(mix, 1)
  end
  local start = o.click and 0.004 or 0 -- the bang comes just after the click
  if o.crack then
    local c = o.crack
    layer(seconds, function(buf)
      buf:noiseBurst(start, c.dur, { amp = c.amp, decay = c.decay })
    end, c.hp, c.lp):mixInto(mix, 1)
  end
  for _, key in ipairs({ "body", "thump" }) do
    local part = o[key]
    if part then
      layer(seconds, function(buf)
        buf:sweep(start, part.dur, part.f0, part.f1, { wave = "sine", amp = part.amp, decay = part.decay })
      end):mixInto(mix, 1)
    end
  end
  if o.tail then
    local t = o.tail
    layer(seconds, function(buf)
      buf:noiseBurst(start + (t.at or 0.01), t.dur, { amp = t.amp, decay = t.decay })
    end, nil, t.lp):mixInto(mix, 1)
  end
  for _, e in ipairs(o.echoes or {}) do
    echo(mix, e[1], e[2])
  end
  mix:drive(o.drive or 2.5)
  mix:highpass(30)
  local source = love.audio.newSource(mix:toSoundData(0.9), "static")
  source:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  return source
end

function Sounds.load()
  Audio.registerChannel("weapons", "Guns and explosions", Sounds.volume, function()
    Sounds.play("shot", 0, 0, 1)
  end)

  -- Gunshots are built in layers, each filtered on its own before they are
  -- mixed (see gunshot() below): the action's click, the muzzle crack, the
  -- body that gives a gun its size, a low thump you feel, then a dark tail
  -- and an echo or two off the buildings.

  -- Pistol: a tight crack with a little weight and a short slap back.
  bank.shot = gunshot(0.4, {
    click = { freq = 3600, amp = 0.25 },
    crack = { dur = 0.05, decay = 0.009, amp = 0.9, hp = 1500, lp = 7000 },
    body = { f0 = 700, f1 = 90, dur = 0.08, decay = 0.028, amp = 0.9 },
    thump = { f0 = 130, f1 = 50, dur = 0.12, decay = 0.04, amp = 0.6 },
    tail = { dur = 0.32, decay = 0.08, amp = 0.3, lp = 1300 },
    echoes = { { 0.075, 0.22 } },
    drive = 2.6,
  })

  -- Uzi: short and snappy with hardly any tail, so fourteen a second read
  -- as a rattle rather than a smear.
  bank.uzi = gunshot(0.17, {
    click = { freq = 4200, amp = 0.3 },
    crack = { dur = 0.035, decay = 0.006, amp = 0.85, hp = 1800, lp = 8000 },
    body = { f0 = 1000, f1 = 180, dur = 0.045, decay = 0.013, amp = 0.75 },
    thump = { f0 = 160, f1 = 70, dur = 0.06, decay = 0.018, amp = 0.35 },
    tail = { dur = 0.13, decay = 0.035, amp = 0.18, lp = 1800 },
    drive = 2.4,
  })

  -- AK-47: a harder crack over a deep body, so a burst hammers rather than
  -- rattles like the uzi.
  bank.ak47 = gunshot(0.32, {
    click = { freq = 3000, amp = 0.3 },
    crack = { dur = 0.05, decay = 0.01, amp = 1.0, hp = 1200, lp = 6500 },
    body = { f0 = 550, f1 = 70, dur = 0.08, decay = 0.026, amp = 1.0 },
    thump = { f0 = 115, f1 = 42, dur = 0.12, decay = 0.045, amp = 0.75 },
    tail = { dur = 0.26, decay = 0.07, amp = 0.3, lp = 1100 },
    echoes = { { 0.06, 0.2 } },
    drive = 3.0,
  })

  -- Shotgun: a wide blast and a deep boom that rolls away, the loudest
  -- gun there is.
  bank.shotgun = gunshot(0.7, {
    click = { freq = 2200, amp = 0.3 },
    crack = { dur = 0.1, decay = 0.022, amp = 1.0, hp = 700, lp = 5000 },
    body = { f0 = 420, f1 = 50, dur = 0.16, decay = 0.05, amp = 1.0 },
    thump = { f0 = 140, f1 = 32, dur = 0.24, decay = 0.09, amp = 1.1 },
    tail = { dur = 0.6, decay = 0.17, amp = 0.45, lp = 900 },
    echoes = { { 0.09, 0.3 }, { 0.23, 0.14 } },
    drive = 3.4,
  })

  -- Sniper: a supersonic snap, a huge flat crack and a long echo rolling
  -- off the city.
  bank.sniper = gunshot(1.4, {
    click = { freq = 5000, amp = 0.35 },
    crack = { dur = 0.04, decay = 0.006, amp = 1.0, hp = 2500, lp = 9000 },
    body = { f0 = 1200, f1 = 80, dur = 0.14, decay = 0.045, amp = 1.0 },
    thump = { f0 = 100, f1 = 30, dur = 0.3, decay = 0.11, amp = 1.0 },
    tail = { at = 0.03, dur = 1.1, decay = 0.35, amp = 0.4, lp = 800 },
    echoes = { { 0.18, 0.3 }, { 0.43, 0.18 }, { 0.8, 0.09 } },
    drive = 3.4,
  })

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

  -- Rocket launch: a thump out of the tube and the motor hissing away.
  bank.rocket = make(0.8, function(buf)
    buf:sweep(0, 0.14, 190, 55, { wave = "sine", amp = 0.9, decay = 0.08 })
    buf:sweep(0, 0.22, 110, 35, { wave = "sine", amp = 0.8, decay = 0.09 }) -- the kick of the back-blast
    buf:noiseBurst(0, 0.04, { amp = 0.7, decay = 0.01 })
    buf:noiseBurst(0.02, 0.75, { amp = 0.55, decay = 0.3 })
    buf:sweep(0.02, 0.6, 520, 260, { wave = "saw", amp = 0.12, decay = 0.3 })
    buf:drive(1.8)
    buf:lowpass(2800)
  end)

  -- Flamethrower: a soft roaring whoosh, low and dull, fourteen of them a
  -- second overlapping into one roar while the trigger is held.
  bank.flame = make(0.2, function(buf)
    buf:noiseBurst(0, 0.2, { amp = 0.55, decay = 0.09 })
    buf:sweep(0, 0.18, 180, 90, { wave = "saw", amp = 0.12, decay = 0.08 })
    buf:lowpass(900)
    buf:drive(1.4)
  end)

  -- Flamethrower reload (2.5 s): the empty tank unscrewed and knocked off, a
  -- full one clanked on and screwed home, a hiss as the line fills.
  bank["reload-flamethrower"] = make(2.5, function(buf)
    rack(buf, 0.05, 0.25, 500, 300, 0.4) -- the cap unscrewed
    click(buf, 0.4, 500, 0.8) -- the empty can knocked off
    click(buf, 1.1, 420, 1.0) -- the full one set on, heavy
    rack(buf, 1.3, 0.35, 300, 600, 0.45) -- screwed home
    click(buf, 1.7, 900, 0.6)
    buf:noiseBurst(1.9, 0.5, { amp = 0.3, decay = 0.2 }) -- the line fills
    buf:highpass(150)
    buf:drive(1.6)
    buf:lowpass(5000)
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
