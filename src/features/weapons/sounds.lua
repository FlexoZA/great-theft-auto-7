-- Weapon sound effects, synthesised at load. Every play is a clone of a base
-- source positioned in the world, so shots overlap freely and pan/fade
-- relative to the listener (which the game state keeps at your car).
--
-- A gun that fires too fast to hear as shots (the flamethrower, the minigun) loops
-- instead: each round only keeps that shooter's loop going (Sounds.hold),
-- it lights with a one-off sound, and it fades once the rounds stop.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "weapons" channel
  refDistance = 260,
  maxDistance = 2200,
}

local bank = {} -- name -> base Source
local loops = {} -- name -> { source = looping base, start = name of the sound it lights with }
local held = {} -- "<name>:<shooter>" -> { source, quiet = seconds since the last round, fade }

Sounds.HOLD = 0.2 -- s a loop keeps going after the last round (a round comes every 0.07 s)
Sounds.FADE = 0.15 -- s it takes to die away after that

--- A sound `seconds` long that `build` writes, normalised to `level` (0.9
--- by default; lower for something that should stay quiet).
local function make(seconds, build, level)
  local buf = Synth.newBuffer(seconds)
  build(buf)
  local source = love.audio.newSource(buf:toSoundData(level or 0.9), "static")
  source:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  return source
end

--- The flamethrower's roar, a second long and seamless: dark rumbling
--- noise breathing with the turbulence of the jet, a thinner hiss of gas on
--- top. The end is crossfaded into the start so it loops without a click.
local function flameRoar()
  local RATE = Synth.RATE
  local loopN, fadeN = RATE, math.floor(RATE * 0.12)
  local roar = Synth.newBuffer((loopN + fadeN) / RATE)
  local hiss = Synth.newBuffer((loopN + fadeN) / RATE)
  for i = 0, roar.n - 1 do
    roar.data[i] = Synth.noise()
    hiss.data[i] = Synth.noise()
  end
  roar:lowpass(260)
  roar:lowpass(520)
  hiss:highpass(1800)
  hiss:lowpass(5000)
  local TWO_PI = 2 * math.pi
  local mix = Synth.newBuffer((loopN + fadeN) / RATE)
  for i = 0, mix.n - 1 do
    local t = i / RATE -- whole cycles a second, so the breathing loops too
    local breath = 1 + 0.25 * math.sin(TWO_PI * 7 * t) + 0.15 * math.sin(TWO_PI * 11 * t + 1.3)
    mix.data[i] = (roar.data[i] * 4 + hiss.data[i] * 0.35) * breath
  end
  mix:drive(1.5)
  local loop = Synth.newBuffer(loopN / RATE)
  loop.n = loopN
  for i = 0, loopN - 1 do
    local v = mix.data[i]
    if i < fadeN then -- the tail fading out over the head fading in
      local a = i / fadeN
      v = v * math.sqrt(a) + mix.data[loopN + i] * math.sqrt(1 - a)
    end
    loop.data[i] = v
  end
  local source = love.audio.newSource(loop:toSoundData(0.8), "static")
  source:setLooping(true)
  source:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  return source
end

--- The minigun's roar, a second long and seamless: seventeen hard cracks
--- (its rate) run together over the motor's whine, every partial a whole
--- number of cycles a second so the end meets the start.
local function minigunRoar()
  local RATE = Synth.RATE
  local buf = Synth.newBuffer(1)
  buf.n = RATE
  local crack = Synth.newBuffer(1)
  local SHOTS = 17
  for k = 0, SHOTS - 1 do
    local t = k / SHOTS
    crack:noiseBurst(t, 0.03, { amp = 0.9, decay = 0.008 })
    crack:sweep(t, 0.05, 420, 90, { wave = "sine", amp = 0.8, decay = 0.015 })
  end
  crack:lowpass(4200)
  crack:mixInto(buf, 1)
  local TWO_PI = 2 * math.pi
  for i = 0, RATE - 1 do
    local t = i / RATE
    -- The motor: a saw-ish whine at 340 Hz and its octave, buzzing at the rate.
    local p = (340 * t) % 1
    buf.data[i] = buf.data[i] + (2 * p - 1) * 0.12 + math.sin(TWO_PI * 680 * t) * 0.05
      + math.sin(TWO_PI * 17 * t) * 0.06
  end
  buf:drive(2.2)
  local source = love.audio.newSource(buf:toSoundData(0.85), "static")
  source:setLooping(true)
  source:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  return source
end

--- A random-ish number in [lo, hi) from the synth's own deterministic noise,
--- so every machine renders the same explosions.
local function between(lo, hi)
  return lo + (Synth.noise() * 0.5 + 0.5) * (hi - lo)
end

local TAKES = {} -- metatable marking a list of takes

--- `n` takes of a sound, `build` rendering each; Sounds.play picks one.
local function takes(n, build)
  local list = {}
  for i = 1, n do
    list[i] = build()
  end
  return setmetatable(list, TAKES)
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

--- An explosion `seconds` long out of layers, each optional:
---   crack   { amp, decay }                       the blast front, a split second of bright noise
---   sub     { f0, f1, dur, decay, amp }          the boom you feel, a falling sine
---   body    { f0, f1, dur, decay, amp }          a higher falling tone over it
---   roar    { dur, decay, amp, lp }              dark noise rolling away
---   whoosh  { at, dur, amp }                     fuel catching: a swell of noise
---   crackle { count, from, to, amp, lp }         debris: tiny ticks scattered from..to s
---   clangs  { count, from, to, amp }             metal parts landing, ringing
---   thuds   { count, from, to, amp }             heavy chunks landing
---   echoes, drive                                as gunshot() below
local function blast(seconds, o)
  local mix = Synth.newBuffer(seconds)
  if o.crack then
    layer(seconds, function(buf)
      buf:noiseBurst(0, 0.08, { amp = o.crack.amp, decay = o.crack.decay })
    end, 600, 7000):mixInto(mix, 1)
  end
  for _, key in ipairs({ "sub", "body" }) do
    local part = o[key]
    if part then
      local f0 = part.f0 * between(0.9, 1.1) -- no two booms quite the same size
      layer(seconds, function(buf)
        buf:sweep(0, part.dur, f0, part.f1, { wave = "sine", amp = part.amp, decay = part.decay })
      end):mixInto(mix, 1)
    end
  end
  if o.roar then
    local r = o.roar
    layer(seconds, function(buf)
      buf:noiseBurst(0.005, r.dur, { amp = r.amp, decay = r.decay })
    end, nil, r.lp):mixInto(mix, 1)
  end
  if o.whoosh then
    local w = o.whoosh
    layer(seconds, function(buf)
      local s0, n = math.floor(w.at * Synth.RATE), math.floor(w.dur * Synth.RATE)
      for i = 0, math.min(n, buf.n - s0) - 1 do
        local t = i / n
        buf.data[s0 + i] = Synth.noise() * w.amp * math.sin(math.pi * t) ^ 2 -- swell and die
      end
    end, 200, 1400):mixInto(mix, 1)
  end
  if o.crackle then
    local c = o.crackle
    layer(seconds, function(buf)
      for _ = 1, c.count do
        local t = c.from + (c.to - c.from) * between(0, 1) ^ 1.6 -- thickest early
        buf:noiseBurst(t, 0.012, { amp = c.amp * between(0.3, 1), decay = 0.003 })
      end
    end, 1800, c.lp or 6000):mixInto(mix, 1)
  end
  if o.clangs then
    local c = o.clangs
    layer(seconds, function(buf)
      for _ = 1, c.count do
        local t, f = between(c.from, c.to), between(500, 2200)
        local amp = c.amp * between(0.4, 1)
        local ring = { wave = "sine", amp = amp, attack = 0.001, sustain = 0, release = 0.02 }
        ring.decay = between(0.06, 0.18)
        buf:tone(t, 0.25, f, ring)
        ring.amp = amp * 0.5
        buf:tone(t, 0.2, f * 2.76, ring) -- a struck panel rings out of tune with itself
        buf:noiseBurst(t, 0.02, { amp = amp * 0.6, decay = 0.004 })
      end
    end, 300):mixInto(mix, 1)
  end
  if o.thuds then
    local c = o.thuds
    layer(seconds, function(buf)
      for _ = 1, c.count do
        local t = between(c.from, c.to)
        buf:sweep(t, 0.18, between(110, 170), 45, { wave = "sine", amp = c.amp * between(0.4, 1), decay = 0.06 })
        buf:noiseBurst(t, 0.06, { amp = c.amp * 0.3, decay = 0.02 })
      end
    end, nil, 1500):mixInto(mix, 1)
  end
  for _, e in ipairs(o.echoes or {}) do
    echo(mix, e[1], e[2])
  end
  mix:drive(o.drive or 2.5)
  mix:highpass(20)
  local source = love.audio.newSource(mix:toSoundData(0.9), "static")
  source:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  return source
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

  -- Flamethrower: a steady roar while the trigger is held, one loop per
  -- shooter, lit with a whoomp.
  loops.flame = { source = flameRoar(), start = "flame-light" }

  -- Minigun: one roar while it fires, one loop per shooter, wound up first
  -- (weapons plays "minigun-spin" as the barrels start, before any round).
  loops.minigun = { source = minigunRoar() }

  -- Its barrels winding up: a motor's whine climbing, a rattle of the
  -- barrels coming round under it, 0.8 s (pitched to a faster spin-up).
  bank["minigun-spin"] = make(0.85, function(buf)
    buf:sweep(0, 0.8, 80, 340, { wave = "saw", amp = 0.22, decay = 4 })
    buf:sweep(0, 0.8, 160, 680, { wave = "square", amp = 0.05, decay = 4 })
    for i = 0, 13 do
      buf:noiseBurst(0.8 * (i / 14) ^ 0.7, 0.012, { amp = 0.15, decay = 0.006 })
    end
    buf:lowpass(3400)
  end)

  -- Lighting it: a soft low whoomp as the gas catches, and a hiss.
  bank["flame-light"] = make(0.45, function(buf)
    buf:sweep(0, 0.3, 90, 160, { wave = "sine", amp = 0.9, decay = 0.12 })
    buf:noiseBurst(0, 0.4, { amp = 0.7, decay = 0.13 })
    buf:lowpass(900)
    buf:drive(1.6)
  end)

  -- Hits sound like what was hit and what hit it (Sounds.hitName picks).

  --- A struck panel: a ring with an out-of-tune overtone, and a tick.
  local function ring(buf, t, f, amp, decay)
    local o = { wave = "sine", amp = amp, attack = 0.001, decay = decay, sustain = 0, release = 0.01 }
    buf:tone(t, decay * 3, f, o)
    o.amp = amp * 0.55
    buf:tone(t, decay * 2.5, f * 1.53, o)
    o.amp = amp * 0.3
    buf:tone(t, decay * 2, f * 2.76, o)
  end

  -- A bullet in a car: a clank and the panel ringing.
  bank["hit-metal"] = takes(3, function()
    return make(0.25, function(buf)
      ring(buf, 0, between(950, 1500), 0.6, between(0.035, 0.06))
      buf:noiseBurst(0, 0.04, { amp = 0.6, decay = 0.008 })
      buf:sweep(0, 0.05, 500, 160, { wave = "sine", amp = 0.4, decay = 0.015 }) -- the dent
      buf:highpass(350)
      buf:drive(1.8)
    end)
  end)

  -- A bullet in someone: a dull wet thud, nothing bright about it.
  bank["hit-flesh"] = takes(3, function()
    return make(0.16, function(buf)
      buf:sweep(0, 0.08, between(170, 210), 60, { wave = "sine", amp = 1.0, decay = 0.028 })
      local slap = Synth.newBuffer(0.16)
      slap:noiseBurst(0, 0.05, { amp = 0.7, decay = 0.014 })
      slap:lowpass(1100)
      slap:lowpass(1100)
      slap:mixInto(buf, 1)
      buf:drive(2.0)
    end, 0.8)
  end)

  -- A fist, a club or a car knocking someone over: a heavier, rounder thump.
  bank["hit-punch"] = takes(2, function()
    return make(0.22, function(buf)
      buf:noiseBurst(0, 0.008, { amp = 0.5, decay = 0.002 }) -- the smack
      buf:sweep(0, 0.13, between(120, 150), 42, { wave = "sine", amp = 1.0, decay = 0.045 })
      buf:noiseBurst(0, 0.06, { amp = 0.5, decay = 0.016 })
      buf:lowpass(1600)
      buf:drive(2.2)
    end, 0.85)
  end)

  -- Fire licking something: a quiet sizzle. The flamethrower lands fourteen
  -- of these a second, so they blur into one hiss.
  bank["hit-fire"] = make(0.2, function(buf)
    buf:noiseBurst(0, 0.18, { amp = 0.5, decay = 0.06 })
    for _ = 1, 4 do
      buf:noiseBurst(between(0, 0.15), 0.01, { amp = 0.8, decay = 0.002 }) -- spits
    end
    buf:highpass(2200)
    buf:lowpass(7000)
  end, 0.3)

  -- A shock: a buzzing zap and a crackle of sparks.
  bank["hit-shock"] = takes(2, function()
    return make(0.3, function(buf)
      buf:tone(0, 0.2, between(55, 70), { wave = "square", amp = 0.5, attack = 0.002, decay = 0.08, sustain = 0 })
      buf:sweep(0, 0.12, 2600, 500, { wave = "square", amp = 0.3, decay = 0.05 })
      for _ = 1, 10 do
        buf:noiseBurst(between(0, 0.22), 0.012, { amp = between(0.4, 0.9), decay = 0.003 })
      end
      buf:highpass(150)
      buf:drive(2.0)
    end, 0.7)
  end)

  -- A bullet into a wall: a chip of concrete, and now and then the whine of
  -- a ricochet going off somewhere else.
  bank["hit-wall"] = takes(4, function()
    local whine = Synth.noise() > -0.1 -- a little over half of them
    return make(0.45, function(buf)
      local chip = Synth.newBuffer(0.45)
      chip:noiseBurst(0, 0.03, { amp = 0.9, decay = 0.006 })
      chip:highpass(1300)
      chip:lowpass(5500)
      chip:mixInto(buf, 1)
      buf:sweep(0, 0.04, 420, 150, { wave = "sine", amp = 0.45, decay = 0.012 })
      if whine then
        local f = between(2600, 3600)
        buf:sweep(0.015, 0.4, f, f * 0.55, { wave = "sine", amp = 0.35, decay = 0.14 })
      end
      buf:drive(1.6)
    end, 0.6)
  end)

  -- Explosions are built in layers like the gunshots (see blast() below),
  -- three takes of each so a string of them never repeats one sample.

  -- A blast (rockets, mortars, whatever else blows up): a sharp crack, a
  -- deep boom, debris crackling down and a roar rolling off the buildings.
  bank.explosion = takes(3, function()
    return blast(1.6, {
      crack = { amp = 1.0, decay = 0.014 },
      sub = { f0 = 95, f1 = 26, dur = 0.9, decay = 0.32, amp = 1.2 },
      body = { f0 = 280, f1 = 55, dur = 0.35, decay = 0.1, amp = 0.8 },
      roar = { dur = 1.4, decay = 0.38, amp = 0.9, lp = 900 },
      crackle = { count = 40, from = 0.05, to = 0.9, amp = 0.35 },
      echoes = { { 0.16, 0.3 }, { 0.38, 0.15 } },
      drive = 2.6,
    })
  end)

  -- A car going up: the blast, then the fuel catching with a whoosh and its
  -- panels and parts clanging down round it.
  bank["explosion-car"] = takes(3, function()
    return blast(2.0, {
      crack = { amp = 1.0, decay = 0.016 },
      sub = { f0 = 85, f1 = 24, dur = 1.0, decay = 0.36, amp = 1.2 },
      body = { f0 = 240, f1 = 50, dur = 0.4, decay = 0.12, amp = 0.9 },
      roar = { dur = 1.8, decay = 0.5, amp = 0.85, lp = 800 },
      whoosh = { at = 0.06, dur = 0.9, amp = 0.55 },
      crackle = { count = 30, from = 0.05, to = 1.0, amp = 0.3 },
      clangs = { count = 7, from = 0.25, to = 1.5, amp = 0.45 },
      echoes = { { 0.18, 0.28 }, { 0.42, 0.13 } },
      drive = 2.6,
    })
  end)

  -- A building coming down: a blast that turns into a long rumble, rubble
  -- pouring and chunks thudding down for a couple of seconds.
  bank["explosion-building"] = takes(2, function()
    return blast(3.2, {
      crack = { amp = 0.9, decay = 0.02 },
      sub = { f0 = 75, f1 = 22, dur = 2.4, decay = 0.9, amp = 1.2 },
      body = { f0 = 200, f1 = 45, dur = 0.5, decay = 0.18, amp = 0.8 },
      roar = { dur = 3.0, decay = 1.0, amp = 0.9, lp = 650 },
      crackle = { count = 140, from = 0.1, to = 2.8, amp = 0.3, lp = 2600 },
      thuds = { count = 9, from = 0.3, to = 2.6, amp = 0.7 },
      echoes = { { 0.22, 0.25 } },
      drive = 2.4,
    })
  end)
end

--- Add sound `name` to the bank: a Source, or a list of takes. For other
--- weapon sound files (reloads.lua), with Sounds.make and Sounds.takes.
function Sounds.add(name, source)
  bank[name] = source
end
Sounds.make = make
Sounds.takes = takes

--- Play `name` right in my ears rather than out in the world.
function Sounds.playHere(name, pitch)
  local s = Sounds.play(name, 0, 0, pitch)
  if s then
    s:setRelative(true)
  end
  return s
end

--- Play `name` at world position (x, y). pitch defaults to 1. A sound
--- with several takes plays one of them at random.
function Sounds.play(name, x, y, pitch)
  local base = bank[name]
  if getmetatable(base) == TAKES then
    base = base[love.math.random(#base)]
  end
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

-- Which hit sound plays: by what was hit ("foot" or "car") and the damage
-- type. Missing means silent (an explosion already makes its own noise).
local HITS = {
  foot = { bullet = "hit-flesh", melee = "hit-punch", impact = "hit-punch", fire = "hit-fire", shock = "hit-shock" },
  car = { bullet = "hit-metal", melee = "hit-metal", impact = "hit-metal", fire = "hit-fire", shock = "hit-shock" },
}

--- The sound a hit on `target` ("foot" or "car") of damage type `dtype`
--- makes, or nil for none. An unknown type sounds like a bullet.
function Sounds.hitName(target, dtype)
  local byType = HITS[target] or HITS.foot
  if dtype == "explosive" then
    return nil
  end
  return byType[dtype] or byType.bullet
end

--- True when `name` loops while held rather than playing once a round.
function Sounds.loops(name)
  return loops[name] ~= nil
end

--- A round of looping sound `name` from `shooter` at (x, y): start that
--- shooter's loop (lit with its start sound), or keep it going and move it.
function Sounds.hold(name, shooter, x, y)
  local loop = loops[name]
  if not loop then
    return
  end
  local key = name .. ":" .. tostring(shooter)
  local h = held[key]
  if not h then
    h = { source = loop.source:clone() }
    held[key] = h
    h.source:setVolume(Audio.volume("weapons"))
    h.source:play()
    Sounds.play(loop.start, x, y)
  end
  h.quiet, h.fade = 0, 1
  h.source:setPosition(x, 0, y)
end

--- Fade out loops whose rounds have stopped. Call every frame.
function Sounds.update(dt)
  local volume = Audio.volume("weapons")
  for key, h in pairs(held) do
    h.quiet = h.quiet + dt
    if h.quiet > Sounds.HOLD then
      h.fade = h.fade - dt / Sounds.FADE
    end
    if h.fade <= 0 then
      h.source:stop()
      held[key] = nil
    else
      h.source:setVolume(volume * h.fade)
    end
  end
end

--- Silence every loop (leaving the game).
function Sounds.stopAll()
  for key, h in pairs(held) do
    h.source:stop()
    held[key] = nil
  end
end

--- For tests.
function Sounds.held()
  return held
end

--- For tests.
function Sounds.bank()
  return bank
end

return Sounds
