-- Crash sounds: a car hitting a wall or another car is heard, as hard as it
-- hit. A tap is a thunk, a proper crash crunches metal, and a big smash
-- shatters glass and throws bits about. Into a wall it is a duller thud;
-- car on car it clangs. Trucks sound deeper, motorbikes lighter.
--
-- The host hears every impact through `serverCarImpact` (raised by
-- car-collisions for car on car, by the city map and buildings for walls),
-- leaves out gentle rubbing and pushing, and tells everyone; each client
-- plays it where it happened.
--
-- Messages
--   server -> all  CRS_HIT <vid> <x> <y> <speed> <w|c>   (a wall, or a car)

local Protocol = require("src.net.protocol")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Features = require("src.features")

local Crash = {
  name = "crash-sounds",
}

-- Tuning ------------------------------------------------------------------
Crash.volume = 0.8 -- default level of the "crashes" channel
Crash.minSpeed = 60 -- px/s into the wall or the other car: slower is a nudge, no sound
Crash.hardSpeed = 520 -- px/s: this or faster is the biggest smash
Crash.cooldown = 0.25 -- s before the same car makes another crash
Crash.refDistance = 220 -- px: full volume inside this radius
Crash.maxDistance = 2200 -- px: quietest beyond this
Crash.TIERS = { 0.25, 0.6 } -- strength 0..1: below the first a bump, below the second a crash, then a smash

-- Server --------------------------------------------------------------------

local sv = nil -- { time, last = { [vid] = time of its last crash } }

function Crash:serverStart()
  sv = { time = 0, last = {} }
end

function Crash:serverStep(_server, dt)
  if sv then
    sv.time = sv.time + dt
  end
end

function Crash:serverCarImpact(server, car, speed, x, y, what)
  if not sv or speed < self.minSpeed then
    return
  end
  local last = sv.last[car.id]
  if last and sv.time - last < self.cooldown then
    return
  end
  sv.last[car.id] = sv.time
  server:broadcast(Protocol.encode("CRS_HIT", car.id, math.floor(x), math.floor(y), math.floor(speed),
    what == "car" and "c" or "w"))
end

-- Sounds --------------------------------------------------------------------

local bank = {} -- "<tier>-<w|c>" -> list of Sources (takes)

local function between(lo, hi)
  return lo + (Synth.noise() * 0.5 + 0.5) * (hi - lo)
end

--- The body taking the blow: a low falling thump.
local function thump(buf, f0, amp, decay)
  buf:sweep(0, decay * 4, f0, f0 * 0.35, { wave = "sine", amp = amp, decay = decay })
end

--- Metal crumpling: a burst of crackling grains, thickest at the start.
local function crunch(buf, dur, count, amp)
  local grains = Synth.newBuffer(buf.n / Synth.RATE)
  for _ = 1, count do
    local t = dur * between(0, 1) ^ 2
    grains:noiseBurst(t, 0.01, { amp = amp * between(0.3, 1), decay = 0.003 })
  end
  grains:noiseBurst(0, dur, { amp = amp * 0.35, decay = dur / 3 })
  grains:highpass(700)
  grains:lowpass(4500)
  grains:mixInto(buf, 1)
end

--- Panels ringing out of tune with themselves (car on car).
local function clang(buf, count, amp)
  for _ = 1, count do
    local t, f = between(0, 0.05), between(280, 900)
    local o = { wave = "sine", amp = amp, attack = 0.001, sustain = 0, release = 0.02 }
    o.decay = between(0.08, 0.2)
    buf:tone(t, o.decay * 3, f, o)
    o.amp = amp * 0.5
    buf:tone(t, o.decay * 2.5, f * 2.76, o)
  end
end

--- A window going: a sharp shatter and shards tinkling down for a while.
local function glass(buf, dur, amp)
  local shards = Synth.newBuffer(buf.n / Synth.RATE)
  shards:noiseBurst(0.01, 0.08, { amp = amp, decay = 0.02 })
  for _ = 1, 28 do
    local t = 0.02 + dur * between(0, 1) ^ 1.5
    local o = { wave = "sine", amp = amp * between(0.15, 0.5), attack = 0.0005, sustain = 0, release = 0.01 }
    o.decay = between(0.01, 0.04)
    shards:tone(t, 0.08, between(3000, 7000), o)
  end
  shards:highpass(2500)
  shards:mixInto(buf, 1)
end

--- Bits of the car landing round it.
local function debris(buf, from, to, count, amp)
  for _ = 1, count do
    local t = between(from, to)
    buf:sweep(t, 0.05, between(300, 700), 150, { wave = "sine", amp = amp * between(0.3, 1), decay = 0.012 })
    buf:noiseBurst(t, 0.02, { amp = amp * 0.4, decay = 0.004 })
  end
end

local BUILD = {
  -- A tap: one dull thunk.
  ["bump-w"] = { 0.25, function(buf)
    thump(buf, between(130, 160), 1.0, 0.035)
    crunch(buf, 0.04, 6, 0.25)
    buf:lowpass(2500)
  end },
  ["bump-c"] = { 0.3, function(buf)
    thump(buf, between(150, 190), 0.9, 0.03)
    clang(buf, 1, 0.25)
    crunch(buf, 0.04, 6, 0.25)
  end },
  -- A crash: a heavy thud and the metal folding.
  ["crash-w"] = { 0.6, function(buf)
    thump(buf, between(110, 135), 1.0, 0.07)
    crunch(buf, 0.22, 60, 0.7)
    debris(buf, 0.15, 0.45, 3, 0.4)
    buf:drive(1.8)
  end },
  ["crash-c"] = { 0.7, function(buf)
    thump(buf, between(120, 150), 1.0, 0.06)
    clang(buf, 3, 0.4)
    crunch(buf, 0.2, 60, 0.7)
    debris(buf, 0.15, 0.5, 3, 0.4)
    buf:drive(1.8)
  end },
  -- A smash: everything at once, glass going and bits raining down.
  ["smash-w"] = { 1.2, function(buf)
    thump(buf, between(90, 110), 1.0, 0.12)
    crunch(buf, 0.35, 120, 0.9)
    glass(buf, 0.6, 0.7)
    debris(buf, 0.2, 0.9, 7, 0.5)
    buf:drive(2.2)
  end },
  ["smash-c"] = { 1.2, function(buf)
    thump(buf, between(100, 125), 1.0, 0.1)
    clang(buf, 5, 0.45)
    crunch(buf, 0.3, 120, 0.9)
    glass(buf, 0.6, 0.7)
    debris(buf, 0.2, 0.9, 7, 0.5)
    buf:drive(2.2)
  end },
}

function Crash:load()
  for name, b in pairs(BUILD) do
    bank[name] = {}
    for i = 1, 3 do
      local buf = Synth.newBuffer(b[1])
      b[2](buf)
      buf:highpass(30)
      local source = love.audio.newSource(buf:toSoundData(0.9), "static")
      source:setAttenuationDistances(self.refDistance, self.maxDistance)
      bank[name][i] = source
    end
  end
  Audio.registerChannel("crashes", "Car crashes", self.volume, function()
    local s = bank["crash-c"][1]:clone()
    s:setRelative(true)
    s:setVolume(Audio.volume("crashes"))
    s:play()
  end)
end

-- Client --------------------------------------------------------------------

--- Which sound a crash at `speed` makes ("bump", "crash" or "smash") and how
--- strong it is, 0..1.
function Crash.tierOf(speed)
  local k = math.max(0, math.min(1, (speed - Crash.minSpeed) / (Crash.hardSpeed - Crash.minSpeed)))
  if k < Crash.TIERS[1] then
    return "bump", k
  elseif k < Crash.TIERS[2] then
    return "crash", k
  end
  return "smash", k
end

--- Heavier vehicles crash deeper: car `vid`'s weight as a pitch.
local function pitchOf(vid)
  local vehicles = Features.byName.vehicles
  local model = vehicles and vehicles.catalog.byKey[vehicles.models[vid] or ""]
  local weight = model and model.weight or 1000
  return math.max(0.72, math.min(1.3, (1000 / weight) ^ 0.3))
end

function Crash.play(vid, x, y, speed, what)
  local tier, k = Crash.tierOf(speed)
  local takes = bank[tier .. "-" .. (what == "c" and "c" or "w")]
  if not takes then
    return
  end
  local s = takes[love.math.random(#takes)]:clone()
  s:setPosition(x, 0, y)
  s:setPitch(pitchOf(vid) * (0.93 + love.math.random() * 0.14))
  s:setVolume(Audio.volume("crashes") * (0.45 + 0.55 * k))
  s:play()
  return s
end

Crash.clientMessages = {
  CRS_HIT = function(_client, args)
    local vid, x, y, speed = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if vid and x and y and speed then
      Crash.play(vid, x, y, speed, args[5])
    end
  end,
}

return Crash
