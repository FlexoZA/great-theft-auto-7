-- Crash sounds: a car hitting a wall or another car is heard, as hard as it
-- hit. A tap is a thunk, a proper crash crunches metal, and a big smash
-- shatters glass and throws bits about. Into a wall it is a duller thud;
-- car on car it clangs. Trucks sound deeper, motorbikes lighter.
--
-- A car sliding along a wall or another car grinds: a loop of screeching
-- metal and sparks that rises with the speed and follows the car until it
-- comes away.
--
-- The host hears every impact through `serverCarImpact` (raised by
-- car-collisions for car on car, by the city map and buildings for walls),
-- leaves out gentle rubbing and pushing, and tells everyone; each client
-- plays it where it happened. Scraping comes in through `serverCarScrape`
-- every step two things touch; the host only says when a car starts
-- grinding, gets noticeably louder or quieter, and stops.
--
-- Messages
--   server -> all  CRS_HIT <vid> <x> <y> <speed> <w|c>   (a wall, or a car)
--   server -> all  CRS_SCRAPE <vid> <level>             (0 stopped, 1..SCRAPE_LEVELS louder)

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
Crash.scrapeStart = 80 -- px/s sliding along something before it grinds...
Crash.scrapeStop = 50 -- ...and below this it stops (or after `scrapeLetGo` s without touching)
Crash.scrapeLetGo = 0.15
Crash.scrapeFull = 450 -- px/s: the loudest grind
Crash.scrapeEvery = 0.25 -- s between changes of a grind's level (starting and stopping go at once)
Crash.SCRAPE_LEVELS = 4

-- Server --------------------------------------------------------------------

local sv = nil -- { time, last = { [vid] = time of its last crash }, touch, scraping }

function Crash:serverStart()
  sv = {
    time = 0,
    last = {},
    touch = {}, -- vid -> { speed = fastest slide this step, t = when }
    scraping = {}, -- vid -> level the clients were last told
    told = {}, -- vid -> when they were told it
  }
end

--- The level a slide at `speed` grinds at, 1..SCRAPE_LEVELS.
local function scrapeLevel(speed)
  local k = (speed - Crash.scrapeStop) / (Crash.scrapeFull - Crash.scrapeStop)
  return math.max(1, math.min(Crash.SCRAPE_LEVELS, math.ceil(k * Crash.SCRAPE_LEVELS)))
end

function Crash:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  -- Tell everyone about grinds that start, change or stop.
  for vid, touch in pairs(sv.touch) do
    local level = sv.scraping[vid]
    local touching = sv.time - touch.t <= self.scrapeLetGo
    local want = nil
    if touching and (touch.speed >= self.scrapeStart or (level and touch.speed >= self.scrapeStop)) then
      want = scrapeLevel(touch.speed)
    end
    local settled = not (want and level) or sv.time - (sv.told[vid] or 0) >= Crash.scrapeEvery
    if want ~= level and settled then
      sv.scraping[vid], sv.told[vid] = want, sv.time
      server:broadcast(Protocol.encode("CRS_SCRAPE", vid, want or 0))
    end
    if not touching then
      sv.touch[vid] = nil
    end
    touch.speed = touching and touch.speed * 0.5 or 0 -- the next step's touches top it back up
  end
  for vid in pairs(sv.scraping) do
    if not (sv.touch[vid] and server.vehicles[vid]) then
      sv.scraping[vid], sv.told[vid] = nil, nil
      server:broadcast(Protocol.encode("CRS_SCRAPE", vid, 0))
    end
  end
end

function Crash:serverCarScrape(_server, car, speed)
  if not sv then
    return
  end
  local touch = sv.touch[car.id]
  if not touch then
    touch = { speed = 0 }
    sv.touch[car.id] = touch
  end
  touch.speed, touch.t = math.max(touch.speed, speed), sv.time
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
local grind = nil -- the scrape loop
local scrapes = {} -- vid -> { source, level = target 0..1, gain = now }

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

--- The grind, a second long and seamless: metal screeching in a few
--- out-of-tune partials that wobble, juddering noise as it sticks and slips,
--- and sparks crackling. Crossfaded end into start so it loops cleanly.
local function renderGrind()
  local RATE = Synth.RATE
  local loopN, fadeN = RATE, math.floor(RATE * 0.1)
  local seconds = (loopN + fadeN) / RATE
  local TWO_PI = 2 * math.pi
  local rasp = Synth.newBuffer(seconds)
  local judder = 0
  for i = 0, rasp.n - 1 do
    if i % 600 == 0 then -- stick and slip, about 37 times a second
      judder = 0.4 + 0.6 * (Synth.noise() * 0.5 + 0.5)
    end
    rasp.data[i] = Synth.noise() * judder
  end
  rasp:highpass(900)
  rasp:lowpass(5000)
  local screech = Synth.newBuffer(seconds)
  for _, part in ipairs({ { 1180, 0.3, 3 }, { 1930, 0.22, 5 }, { 3270, 0.12, 7 } }) do
    local phase = 0
    for i = 0, screech.n - 1 do
      local t = i / RATE
      local f = part[1] * (1 + 0.03 * math.sin(TWO_PI * part[3] * t)) -- whole cycles a second: it loops
      phase = phase + f / RATE
      screech.data[i] = screech.data[i] + math.sin(TWO_PI * phase) * part[2] * (0.6 + 0.4 * math.sin(TWO_PI * 2 * t))
    end
  end
  local sparks = Synth.newBuffer(seconds)
  for _ = 1, 90 do
    sparks:noiseBurst(between(0, seconds - 0.01), 0.006, { amp = between(0.3, 0.9), decay = 0.0015 })
  end
  sparks:highpass(3000)
  local mix = Synth.newBuffer(seconds)
  rasp:mixInto(mix, 0.8)
  screech:mixInto(mix, 1)
  sparks:mixInto(mix, 0.5)
  mix:drive(1.6)
  local loop = Synth.newBuffer(loopN / RATE)
  loop.n = loopN
  for i = 0, loopN - 1 do
    local v = mix.data[i]
    if i < fadeN then
      local a = i / fadeN
      v = v * math.sqrt(a) + mix.data[loopN + i] * math.sqrt(1 - a)
    end
    loop.data[i] = v
  end
  local source = love.audio.newSource(loop:toSoundData(0.8), "static")
  source:setLooping(true)
  source:setAttenuationDistances(Crash.refDistance, Crash.maxDistance)
  return source
end

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
  grind = renderGrind()
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

--- Car `vid` grinds at `level` (0 stops it).
function Crash.scrape(vid, level)
  local e = scrapes[vid]
  if level <= 0 then
    if e then
      e.level = 0
    end
    return
  end
  if not e then
    e = { source = grind:clone(), level = 0, gain = 0 }
    e.source:seek(love.math.random() * 0.9) -- not every grind in step
    e.source:setVolume(0)
    e.source:play()
    scrapes[vid] = e
  end
  e.level = level / Crash.SCRAPE_LEVELS
end

--- Grinds follow their cars, swell and die away smoothly, and stop when the
--- car is gone or (should the stop never come) stands still.
function Crash:update(dt, client)
  local volume = Audio.volume("crashes")
  for vid, e in pairs(scrapes) do
    local c = client.vehicles[vid]
    local target = e.level
    if not c or math.abs(c.speed or 0) < 25 then
      target = 0
    end
    e.gain = e.gain + (target - e.gain) * math.min(1, dt * (target > e.gain and 18 or 8))
    if target == 0 and e.gain < 0.02 then
      e.source:stop()
      scrapes[vid] = nil
    else
      if c then
        e.source:setPosition(c.dx, 0, c.dy)
      end
      e.source:setPitch(0.8 + 0.4 * e.gain)
      e.source:setVolume(volume * (0.25 + 0.75 * e.gain) * math.min(1, e.gain * 4))
    end
  end
end

function Crash:exitGame()
  for vid, e in pairs(scrapes) do
    e.source:stop()
    scrapes[vid] = nil
  end
end

--- For tests.
function Crash.scrapes()
  return scrapes
end

Crash.clientMessages = {
  CRS_HIT = function(_client, args)
    local vid, x, y, speed = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if vid and x and y and speed then
      Crash.play(vid, x, y, speed, args[5])
    end
  end,
  CRS_SCRAPE = function(_client, args)
    local vid, level = tonumber(args[1]), tonumber(args[2])
    if vid and level then
      Crash.scrape(vid, level)
    end
  end,
}

return Crash
