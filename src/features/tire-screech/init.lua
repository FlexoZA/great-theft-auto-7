-- Tyre screech: a car sliding sideways (a handbrake turn, a corner taken too
-- fast) or braking hard at speed squeals, louder and higher the harder it
-- goes. On grass or sand it is the scrabble of tyres in dirt instead. A
-- motorbike squeals higher, a truck lower.
--
-- Purely local, like the skid marks it goes with: skidmarks works out how
-- fast each car slides and slows from the snapshots (Skidmarks.slip), and
-- this listens. Only the nearest few cars are heard.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Features = require("src.features")

local Screech = {
  name = "tire-screech",
}

-- Tuning ------------------------------------------------------------------
Screech.volume = 0.6 -- default level of the "tyres" channel
Screech.slideFrom = 90 -- px/s sideways before the tyres squeal (skid marks start at 110)
Screech.slideFull = 410 -- px/s sideways: the loudest squeal
Screech.brakeShare = 0.75 -- slowing at this share of the car's own brakes or more is braking hard...
Screech.brakeFrom = 140 -- ...and it only squeals going faster than this, px/s
Screech.brakeFull = 440 -- px/s: braking from this fast squeals loudest
Screech.brakeMost = 0.7 -- braking squeals at most this loud (a slide is louder)
Screech.startAt = 0.08 -- how hard (0..1) before a car starts screeching: not the odd wobble
Screech.heard = 6 -- the nearest few screeching cars
Screech.hearing = 1500 -- px: further than this isn't heard
Screech.refDistance = 200 -- px: full volume inside this radius
Screech.maxDistance = 2000 -- px: quietest beyond this

local loops = {} -- "squeal" | "dirt" -> looping base Source
local tyres = {} -- vid -> { k = how hard now 0..1, source, kind }

-- Sounds --------------------------------------------------------------------

local function between(lo, hi)
  return lo + (Synth.noise() * 0.5 + 0.5) * (hi - lo)
end

--- A seamless loop `seconds` long of what `fill(buf)` writes into a buffer a
--- little longer: the spare end is crossfaded over the start.
local function loop(fill, level)
  local RATE = Synth.RATE
  local loopN, fadeN = RATE, math.floor(RATE * 0.1)
  local buf = Synth.newBuffer((loopN + fadeN) / RATE)
  fill(buf)
  local out = Synth.newBuffer(loopN / RATE)
  out.n = loopN
  for i = 0, loopN - 1 do
    local v = buf.data[i]
    if i < fadeN then
      local a = i / fadeN
      v = v * math.sqrt(a) + buf.data[loopN + i] * math.sqrt(1 - a)
    end
    out.data[i] = v
  end
  local source = love.audio.newSource(out:toSoundData(level), "static")
  source:setLooping(true)
  source:setAttenuationDistances(Screech.refDistance, Screech.maxDistance)
  return source
end

--- Rubber squealing on tarmac: a wavering whine in a few partials over a
--- band of hiss, juddering as the tyre sticks and slips.
local function squeal(buf)
  local RATE = Synth.RATE
  local TWO_PI = 2 * math.pi
  local data = buf.data
  local f, df = 1100, 0
  local judder, target = 1, 1
  local phases = { 0, 0, 0 }
  local PARTS = { { 1, 0.5 }, { 1.47, 0.3 }, { 2.05, 0.15 } }
  for i = 0, buf.n - 1 do
    if i % 220 == 0 then -- the pitch wanders...
      df = df * 0.9 + Synth.noise() * 6
      target = between(0.55, 1) -- ...and the grip judders, about 100 times a second
    end
    f = math.max(980, math.min(1240, f + df / 220))
    judder = judder + (target - judder) * 0.02
    local v = 0
    for k, part in ipairs(PARTS) do
      phases[k] = (phases[k] + f * part[1] / RATE) % 1
      v = v + math.sin(TWO_PI * phases[k]) * part[2]
    end
    data[i] = v * judder
  end
  local hiss = Synth.newBuffer(buf.n / RATE)
  for i = 0, hiss.n - 1 do
    hiss.data[i] = Synth.noise()
  end
  hiss:highpass(900)
  hiss:lowpass(2600)
  hiss:mixInto(buf, 0.35)
  buf:drive(1.5)
end

--- Tyres tearing at dirt: a dull rumble and a spray of grit.
local function dirt(buf)
  for i = 0, buf.n - 1 do
    buf.data[i] = Synth.noise()
  end
  buf:lowpass(700)
  buf:lowpass(900)
  local grit = Synth.newBuffer(buf.n / Synth.RATE)
  for _ = 1, 220 do
    grit:noiseBurst(between(0, buf.n / Synth.RATE - 0.01), 0.008, { amp = between(0.2, 0.8), decay = 0.002 })
  end
  grit:highpass(1500)
  grit:lowpass(5000)
  grit:mixInto(buf, 0.5)
end

function Screech:load()
  loops.squeal = loop(squeal, 0.75)
  loops.dirt = loop(dirt, 0.8)
  Audio.registerChannel("tyres", "Tyre screech", self.volume, function()
    local s = loops.squeal:clone()
    s:setLooping(false)
    s:setRelative(true)
    s:setVolume(Audio.volume("tyres"))
    s:play()
  end)
end

function Screech:enterGame()
  tyres = {}
end

function Screech:exitGame()
  for vid, t in pairs(tyres) do
    if t.source then
      t.source:stop()
    end
    tyres[vid] = nil
  end
end

-- Listening ---------------------------------------------------------------

--- Car `vid`'s model, or nil for a starter car.
local function modelOf(vid)
  local vehicles = Features.byName.vehicles
  return vehicles and vehicles.catalog.byKey[vehicles.models[vid] or ""]
end

--- How hard car `c` is screeching, 0..1: sliding, or braking hard at speed.
function Screech.howHard(c)
  local skid = Features.byName.skidmarks
  if not (skid and skid.slip) then
    return 0
  end
  local lateral, decel = skid.slip(c.id)
  local slide = (lateral - Screech.slideFrom) / (Screech.slideFull - Screech.slideFrom)
  -- Braking hard is against the car's own brakes: heavy ones stop slower.
  local model = modelOf(c.id)
  local brakes = 700 / math.max(0.25, (model and model.weight or 1000) / 1000)
  local brake = 0
  if decel > brakes * Screech.brakeShare then
    brake = (math.abs(c.speed or 0) - Screech.brakeFrom) / (Screech.brakeFull - Screech.brakeFrom)
    brake = math.max(0, math.min(1, brake)) * Screech.brakeMost
  end
  return math.max(0, math.min(1, math.max(slide, brake)))
end

--- What car `c`'s tyres are on: tarmac squeals, anything else is dirt.
local function kindAt(c)
  local footsteps = Features.byName.footsteps
  local ground = footsteps and footsteps.surfaceAt and footsteps.surfaceAt(c.dx, c.dy) or "hard"
  return ground == "hard" and "squeal" or "dirt"
end

--- A heavier vehicle squeals lower.
local function pitchOf(vid)
  local model = modelOf(vid)
  return math.max(0.8, math.min(1.25, (1000 / (model and model.weight or 1000)) ^ 0.2))
end

function Screech:update(dt, client)
  local lx, ly = client:myPose()
  if not lx then
    return
  end
  -- Who is screeching, nearest first.
  local loud = {}
  for vid, c in pairs(client.vehicles) do
    local d2 = (c.dx - lx) ^ 2 + (c.dy - ly) ^ 2
    if d2 < self.hearing * self.hearing then
      local k = Screech.howHard(c)
      if k > self.startAt or tyres[vid] then
        loud[#loud + 1] = { vid = vid, c = c, k = k, d2 = d2 }
      end
    end
  end
  table.sort(loud, function(a, b)
    return a.d2 < b.d2
  end)

  local volume = Audio.volume("tyres")
  local seen = {}
  for i = 1, math.min(#loud, self.heard) do
    local e = loud[i]
    seen[e.vid] = true
    local t = tyres[e.vid] or { k = 0 }
    tyres[e.vid] = t
    -- Bite in fast, let go a little slower.
    t.k = t.k + (e.k - t.k) * math.min(1, dt * (e.k > t.k and 14 or 6))
    if t.k < 0.03 and e.k < self.startAt then
      if t.source then
        t.source:stop()
      end
      tyres[e.vid] = nil
    else
      local kind = kindAt(e.c)
      if t.kind ~= kind then -- onto grass, or back onto the road
        if t.source then
          t.source:stop()
        end
        t.source, t.kind = loops[kind]:clone(), kind
        t.source:seek(love.math.random() * 0.9)
        t.source:setVolume(0)
        t.source:play()
      end
      t.source:setPosition(e.c.dx, 0, e.c.dy)
      t.source:setPitch(pitchOf(e.vid) * (kind == "squeal" and (0.9 + 0.2 * t.k) or (0.85 + 0.3 * t.k)))
      t.source:setVolume(volume * (0.3 + 0.7 * t.k) * math.min(1, t.k * 5))
    end
  end
  -- Out of earshot, gone, or crowded out by nearer ones: hush.
  for vid, t in pairs(tyres) do
    if not seen[vid] then
      if t.source then
        t.source:stop()
      end
      tyres[vid] = nil
    end
  end
end

--- For tests.
function Screech.tyres()
  return tyres
end

return Screech
