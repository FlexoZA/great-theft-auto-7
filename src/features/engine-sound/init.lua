-- Engine sound: every car hums a looping synthesised engine note whose pitch
-- follows its speed through four gears. Sources are positional, so other
-- cars pan left/right and fade with distance from your car.
--
-- Purely local: nothing is sent to the server.

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

--- One seamless loop of engine rumble: saw + sub-octave square, a 4-stroke
--- amplitude wobble, soft drive, low-passed.
local function renderLoop()
  local buf = Synth.newBuffer(LOOP_SECONDS)
  local RATE = Synth.RATE
  local data = buf.data
  for i = 0, buf.n - 1 do
    local t = i / RATE
    local p = (LOOP_BASE * t) % 1
    local sub = (LOOP_BASE * t / 2) % 1
    local wobble = 1 + 0.35 * math.sin(2 * math.pi * LOOP_BASE / 2 * t)
    local v = (2 * p - 1) * 0.55 + (sub < 0.5 and 0.35 or -0.35)
    data[i] = v * wobble
  end
  buf:drive(2.2)
  buf:lowpass(900)
  return buf:toSoundData(0.8)
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
  love.audio.setPosition(0, 0, 0)
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
  local me = client:myCar()
  if me then
    -- Listener at my car; world y maps to audio z so x still pans left/right.
    love.audio.setPosition(me.dx, 0, me.dy)
  end

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

--- For tests.
function Engine.sources()
  return sources
end

return Engine
