-- Engine profiles: how each kind of vehicle sounds. A vehicle model picks one
-- with `engine = "<key>"` in its stats file (src/features/vehicles/models);
-- a model without one gets the profile its weight suggests, and the plain
-- starter cars get "classic".
--
-- Every profile but "classic" is built out of firing pulses: each cylinder
-- fires once per engine cycle and rings the exhaust like a struck pipe.
-- Cylinder count, uneven firing, ring pitch and diesel knock are what make
-- a hatchback buzz, a V8 burble and a truck clatter.
--
--   cycleHz     full engine cycles a second at pitch 1 (idle)
--   fires       where in the cycle each cylinder fires, 0..1
--   accents     loudness of each fire, repeating (uneven is lumpier)
--   ring        Hz the exhaust rings at, and `ringDecay` how fast it dies, /s
--   knock       diesel clatter: a click of noise on every fire
--   bed         a sine hum under the pulses at the firing rate
--   drive, lowpass   soft clipping and the low-pass cutoff in Hz
--
-- Then how it revs (see init.lua): `gears` (top of each as a fraction of top
-- speed), `idlePitch`, `revRange` (pitch rise across one gear), `gearStep`,
-- `idleVolume`, `gain` (loudness against the others) and `reach` (how far
-- it carries, times the base distances).

local Synth = require("src.audio.synth")

local TWO_PI = 2 * math.pi

--- `n` cylinders firing evenly through the cycle.
local function even(n)
  local t = {}
  for i = 1, n do
    t[i] = (i - 1) / n
  end
  return t
end

local Profiles = {}

Profiles.classic = {
  gears = { 0.22, 0.45, 0.72, 1.01 },
  idlePitch = 0.9,
  revRange = 1.5,
  gearStep = 0.1,
}

-- Small four-cylinder: high, buzzy, revs hard.
Profiles.compact = {
  cycleHz = 19,
  fires = even(4),
  accents = { 1, 0.85, 0.95, 0.8 },
  ring = 340,
  ringDecay = 70,
  knock = 0.05,
  bed = 0.3,
  drive = 2.4,
  lowpass = 1500,
  gears = { 0.2, 0.4, 0.62, 0.82, 1.01 },
  idlePitch = 0.95,
  revRange = 1.7,
  gearStep = 0.08,
  gain = 0.85,
}

-- Straight six: smooth and even, a touch deeper.
Profiles.sedan = {
  cycleHz = 13,
  fires = even(6),
  accents = { 1, 0.95, 1, 0.97, 1, 0.94 },
  ring = 230,
  ringDecay = 55,
  knock = 0.02,
  bed = 0.5,
  drive = 1.8,
  lowpass = 1100,
  gears = { 0.2, 0.4, 0.62, 0.82, 1.01 },
  idlePitch = 0.9,
  revRange = 1.5,
  gearStep = 0.1,
}

-- Cross-plane V8: two banks firing unevenly, the lumpy burble.
Profiles.v8 = {
  cycleHz = 9.5,
  fires = { 0, 0.11, 0.25, 0.36, 0.5, 0.64, 0.75, 0.86 },
  accents = { 1.25, 0.7, 1, 0.8, 1.15, 0.65, 0.95, 0.85 },
  ring = 150,
  ringDecay = 35,
  knock = 0.03,
  bed = 0.45,
  drive = 2.6,
  lowpass = 750,
  gears = { 0.25, 0.5, 0.76, 1.01 },
  idlePitch = 0.85,
  revRange = 1.4,
  gearStep = 0.12,
  gain = 1.1,
  reach = 1.2,
}

-- V-twin motorbike: potato-potato at idle, a scream at the top.
Profiles.bike = {
  cycleHz = 16,
  fires = { 0, 0.2 },
  accents = { 1, 0.85 },
  ring = 520,
  ringDecay = 90,
  knock = 0.08,
  bed = 0.2,
  drive = 3.0,
  lowpass = 2400,
  gears = { 0.16, 0.32, 0.5, 0.67, 0.84, 1.01 },
  idlePitch = 1.0,
  revRange = 2.1,
  gearStep = 0.1,
  idleVolume = 0.3,
  gain = 0.8,
}

-- Four-cylinder diesel van: clattery, low-revving.
Profiles.diesel = {
  cycleHz = 11,
  fires = even(4),
  accents = { 1, 0.9, 1, 0.85 },
  ring = 190,
  ringDecay = 50,
  knock = 0.45,
  bed = 0.4,
  drive = 2.2,
  lowpass = 1900,
  gears = { 0.18, 0.36, 0.56, 0.78, 1.01 },
  idlePitch = 0.85,
  revRange = 1.1,
  gearStep = 0.06,
  reach = 1.2,
}

-- Big six-cylinder truck diesel: deep, heavy, lots of short gears.
Profiles.truck = {
  cycleHz = 7,
  fires = even(6),
  accents = { 1, 0.9, 1, 0.92, 1, 0.88 },
  ring = 105,
  ringDecay = 28,
  knock = 0.3,
  bed = 0.6,
  drive = 2.4,
  lowpass = 900,
  gears = { 0.12, 0.25, 0.39, 0.54, 0.7, 0.85, 1.01 },
  idlePitch = 0.8,
  revRange = 0.8,
  gearStep = 0.05,
  idleVolume = 0.45,
  gain = 1.2,
  reach = 1.5,
}

-- Mining hauler: a slow, enormous V12 thump you feel more than hear.
Profiles.hauler = {
  cycleHz = 4.5,
  fires = { 0, 0.07, 0.17, 0.24, 0.33, 0.41, 0.5, 0.57, 0.67, 0.74, 0.83, 0.91 },
  accents = { 1.2, 0.8, 1, 0.75, 1.1, 0.85 },
  ring = 75,
  ringDecay = 18,
  knock = 0.25,
  bed = 0.75,
  drive = 2.8,
  lowpass = 650,
  gears = { 0.15, 0.3, 0.47, 0.64, 0.82, 1.01 },
  idlePitch = 0.8,
  revRange = 0.75,
  gearStep = 0.04,
  idleVolume = 0.5,
  gain = 1.3,
  reach = 1.7,
}

--- The profile for a vehicles-catalog model (nil for a starter car): the
--- one it names, else one by weight.
function Profiles.forModel(model)
  if not model then
    return "classic"
  end
  if Profiles[model.engine] then
    return model.engine
  end
  local kg = model.weight or 1000
  if kg < 500 then
    return "bike"
  elseif kg < 1000 then
    return "compact"
  elseif kg < 1500 then
    return "sedan"
  elseif kg < 2200 then
    return "diesel"
  elseif kg < 2950 then
    return "truck"
  end
  return "hauler"
end

--- One seamless loop of profile `p`'s engine at idle. Two loops are
--- rendered and the second kept, so the rings and filters that spill over
--- the seam are already there when it wraps round.
function Profiles.render(p)
  local RATE = Synth.RATE
  local cycles = math.max(1, math.floor(p.cycleHz * 0.5 + 0.5)) -- about half a second
  local loopN = math.floor(cycles / p.cycleHz * RATE + 0.5)
  local cycleHz = cycles * RATE / loopN -- nudged so the loop holds whole cycles
  local buf = Synth.newBuffer(2 * loopN / RATE)
  local data, n = buf.data, buf.n
  local ringN = math.floor(RATE * 4.6 / p.ringDecay) -- down to 1%
  local knockDecay = p.ringDecay * 6

  local fire = 0
  for cycle = 0, 2 * cycles - 1 do
    for _, at in ipairs(p.fires) do
      fire = fire + 1
      local amp = p.accents[(fire - 1) % #p.accents + 1]
      local s0 = math.floor((cycle + at) / cycleHz * RATE + 0.5)
      for k = 0, ringN do
        local i = s0 + k
        if i >= n then
          break
        end
        local tau = k / RATE
        local ring = math.exp(-p.ringDecay * tau)
          * (math.sin(TWO_PI * p.ring * tau) + 0.4 * math.sin(TWO_PI * p.ring * 2.7 * tau))
        local knock = p.knock * math.exp(-knockDecay * tau) * Synth.noise()
        data[i] = data[i] + amp * (ring + knock)
      end
    end
  end

  local firing = cycleHz * #p.fires
  for i = 0, n - 1 do
    local t = i / RATE
    data[i] = data[i] + p.bed * (math.sin(TWO_PI * firing * t) + 0.5 * math.sin(TWO_PI * cycleHz * t))
  end

  buf:drive(p.drive)
  buf:lowpass(p.lowpass)
  buf:highpass(20)

  local loop = Synth.newBuffer(loopN / RATE)
  loop.n = loopN -- exactly, whatever the rounding in newBuffer
  for i = 0, loopN - 1 do
    loop.data[i] = data[loopN + i]
  end
  return loop:toSoundData(0.85)
end

return Profiles
