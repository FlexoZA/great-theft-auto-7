-- Engine sound: every car hums a looping synthesised engine note whose pitch
-- follows its speed through the gears. Each kind of vehicle has an engine of
-- its own (profiles.lua): a hatchback buzzes, a V8 burbles, a motorbike
-- screams through six gears and a truck clatters through seven. The model
-- picks one with `engine = "<profile>"`; the plain starter cars keep the
-- classic hum. Sources are positional, so other
-- cars pan left/right and fade with distance from your car.
--
-- Purely local: nothing is sent to the server. The game state keeps the
-- audio listener at your car (world y -> audio z), so x pans left/right.

local Synth = require("src.audio.synth")
local Car = require("src.car")
local Audio = require("src.audio")
local Features = require("src.features")
local Profiles = require("src.features.engine-sound.profiles")

local Engine = {
  name = "engine-sound",
  priority = 700,
}

-- Tuning ------------------------------------------------------------------
Engine.volume = 0.7 -- default level of the "engine" volume channel (settings can change it)
Engine.idleVolume = 0.35 -- fraction of volume at standstill, unless the profile says
Engine.refDistance = 220 -- px: full volume inside this radius
Engine.maxDistance = 1800 -- px: quietest beyond this

local LOOP_BASE = 56 -- Hz at pitch 1; loop length is a whole number of cycles
local LOOP_SECONDS = 0.5

-- Profiles in the order the settings preview cycles through them.
Engine.ORDER = { "classic", "compact", "sedan", "v8", "bike", "diesel", "truck", "hauler" }

local loops = {} -- profile key -> SoundData
local previews = {} -- profile key -> SoundData
local previewNext = 1
local maxSpeed = Car.new(0, 0).maxSpeed
local sources = {} -- car id -> { source, profile, gear, pitch }

--- One seamless loop of engine rumble: saw for the rasp, a sub-octave square
--- and two sine fundamentals for the bass, a 4-stroke amplitude wobble, soft
--- drive, low-passed.
local function renderLoop()
  local buf = Synth.newBuffer(LOOP_SECONDS)
  local RATE = Synth.RATE
  local data = buf.data
  local TWO_PI = 2 * math.pi
  for i = 0, buf.n - 1 do
    local t = i / RATE
    local p = (LOOP_BASE * t) % 1
    local sub = (LOOP_BASE * t / 2) % 1
    local wobble = 1 + 0.35 * math.sin(TWO_PI * LOOP_BASE / 2 * t)
    local rasp = (2 * p - 1) * 0.4
    local bass = (sub < 0.5 and 0.4 or -0.4) -- sub-octave square, 28 Hz
      + math.sin(TWO_PI * LOOP_BASE * t) * 0.6 -- fundamental, 56 Hz
      + math.sin(TWO_PI * LOOP_BASE / 2 * t) * 0.35 -- sub sine, 28 Hz
    data[i] = (rasp + bass) * wobble
  end
  buf:drive(2.0)
  buf:lowpass(800)
  return buf:toSoundData(0.85)
end

--- A second of revving for the settings screen, cut from a loop.
local function renderPreview(loopData)
  local buf = Synth.newBuffer(0.9)
  local n = loopData:getSampleCount()
  local pos = 0
  for i = 0, buf.n - 1 do
    local t = i / Synth.RATE
    local pitch = 1.0 + t * 1.4
    pos = (pos + pitch) % n
    local fade = math.min(1, t * 20, (0.9 - t) * 6)
    buf.data[i] = loopData:getSample(math.floor(pos)) * fade
  end
  return buf:toSoundData(0.8)
end

function Engine:load()
  for _, key in ipairs(self.ORDER) do
    loops[key] = key == "classic" and renderLoop() or Profiles.render(Profiles[key])
    previews[key] = renderPreview(loops[key])
  end
  love.audio.setDistanceModel("inverseclamped")
  -- Each press of the preview revs the next kind of engine.
  Audio.registerChannel("engine", "Vehicle engine", self.volume, function()
    local key = self.ORDER[previewNext]
    previewNext = previewNext % #self.ORDER + 1
    local s = love.audio.newSource(previews[key], "static")
    s:setRelative(true)
    s:setVolume(Audio.volume("engine"))
    s:play()
  end)
end

function Engine:enterGame()
  sources = {}
end

function Engine:exitGame()
  for _, e in pairs(sources) do
    e.source:stop()
  end
  sources = {}
end

--- Car `id`'s vehicles-catalog model as the host told us, or nil for a
--- starter car.
local function modelOf(id)
  local vehicles = Features.byName.vehicles
  return vehicles and vehicles.catalog.byKey[vehicles.models[id] or ""]
end

--- Car `id`'s engine, started (or swapped, when its model arrived late)
--- to sound like `key`.
local function ensureSource(id, key)
  local e = sources[id]
  if e and e.profile ~= key then
    e.source:stop()
    e = nil
  end
  if not e then
    local p = Profiles[key]
    local reach = p.reach or 1
    local source = love.audio.newSource(loops[key], "static")
    source:setLooping(true)
    source:setAttenuationDistances(Engine.refDistance * reach, Engine.maxDistance * reach)
    source:play()
    e = { source = source, profile = key, p = p, gear = 1, pitch = p.idlePitch }
    sources[id] = e
  end
  return e
end

function Engine:update(dt, client)
  for id, c in pairs(client.vehicles) do
    if c.driver then -- a parked car's engine is off
    local model = modelOf(id)
    local e = ensureSource(id, Profiles.forModel(model))
    local p = e.p
    local frac = math.min(math.abs(c.speed) / (model and model.topSpeed or maxSpeed), 1)

    -- Gear with a little hysteresis so it doesn't chatter at the boundary.
    local gears = p.gears
    while e.gear < #gears and frac > gears[e.gear] + 0.02 do
      e.gear = e.gear + 1
    end
    while e.gear > 1 and frac < gears[e.gear - 1] - 0.03 do
      e.gear = e.gear - 1
    end
    local lo = e.gear == 1 and 0 or gears[e.gear - 1]
    local within = math.max(0, math.min(1, (frac - lo) / (gears[e.gear] - lo)))

    local target = p.idlePitch + within * p.revRange + (e.gear - 1) * p.gearStep
    e.pitch = e.pitch + (target - e.pitch) * math.min(1, dt * 10)
    e.source:setPitch(e.pitch)
    local idle = p.idleVolume or self.idleVolume
    e.source:setVolume(math.min(1, Audio.volume("engine") * (p.gain or 1) * (idle + (1 - idle) * frac)))
    e.source:setPosition(c.dx, 0, c.dy)
    end
  end

  for id, e in pairs(sources) do
    local c = client.vehicles[id]
    if not (c and c.driver) then
      e.source:stop()
      sources[id] = nil
    end
  end
end

--- For tests and offline demos.
function Engine.sources()
  return sources
end
Engine.renderLoop = renderLoop
Engine.profiles = Profiles

return Engine
