-- Engine sound: every car hums a looping synthesised engine note whose pitch
-- follows its speed through four gears. Sources are positional, so other
-- cars pan left/right and fade with distance from your car.
--
-- Purely local: nothing is sent to the server. The game state keeps the
-- audio listener at your car (world y -> audio z), so x pans left/right.

local Synth = require("src.audio.synth")
local Car = require("src.car")

local Engine = {
  name = "engine-sound",
  priority = 700,
}

-- Tuning ------------------------------------------------------------------
Engine.volume = 0.7 -- overall level
Engine.idleVolume = 0.35 -- fraction of volume at standstill
Engine.gears = { 0.22, 0.45, 0.72, 1.01 } -- top of each gear as a fraction of max speed
Engine.idlePitch = 0.9
Engine.revRange = 1.5 -- pitch rise across one gear
Engine.gearStep = 0.1 -- extra pitch per gear so top gear screams a little
Engine.refDistance = 220 -- px: full volume inside this radius
Engine.maxDistance = 1800 -- px: quietest beyond this

local LOOP_BASE = 56 -- Hz at pitch 1; loop length is a whole number of cycles
local LOOP_SECONDS = 0.5

local loopData = nil
local maxSpeed = Car.new(0, 0).maxSpeed
local sources = {} -- car id -> { source, gear, pitch }

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

function Engine:load()
  loopData = renderLoop()
  love.audio.setDistanceModel("inverseclamped")
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

local function ensureSource(id)
  local e = sources[id]
  if not e then
    local source = love.audio.newSource(loopData, "static")
    source:setLooping(true)
    source:setAttenuationDistances(Engine.refDistance, Engine.maxDistance)
    source:play()
    e = { source = source, gear = 1, pitch = Engine.idlePitch }
    sources[id] = e
  end
  return e
end

function Engine:update(dt, client)
  for id, c in pairs(client.cars) do
    local e = ensureSource(id)
    local frac = math.min(math.abs(c.speed) / maxSpeed, 1)

    -- Gear with a little hysteresis so it doesn't chatter at the boundary.
    local gears = self.gears
    while e.gear < #gears and frac > gears[e.gear] + 0.02 do
      e.gear = e.gear + 1
    end
    while e.gear > 1 and frac < gears[e.gear - 1] - 0.03 do
      e.gear = e.gear - 1
    end
    local lo = e.gear == 1 and 0 or gears[e.gear - 1]
    local within = math.max(0, math.min(1, (frac - lo) / (gears[e.gear] - lo)))

    local target = self.idlePitch + within * self.revRange + (e.gear - 1) * self.gearStep
    e.pitch = e.pitch + (target - e.pitch) * math.min(1, dt * 10)
    e.source:setPitch(e.pitch)
    e.source:setVolume(self.volume * (self.idleVolume + (1 - self.idleVolume) * frac))
    e.source:setPosition(c.dx, 0, c.dy)
  end

  for id, e in pairs(sources) do
    if not client.cars[id] then
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

return Engine
