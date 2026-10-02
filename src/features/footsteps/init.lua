-- Footsteps: everyone on foot steps audibly, in time with the stride their
-- body is drawn with (src/states/game.lua for players, the pedestrians'
-- own render for the crowd): a step each time a foot comes down, twice as
-- often at a run, none standing still.
--
-- What a step sounds like depends on the ground under it (the city map's
-- tiles): a click on road and pavement, a swish on grass, a crunch on the
-- beach's sand, a splash in water. Running steps are louder.
--
-- Purely local: nothing is sent to the server. Steps are positional around
-- the listener the game state keeps at you, and only heard close by (the
-- distance model never fades a sound out completely, so far ones are skipped).

local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Features = require("src.features")
local Layout = require("src.features.city-map.layout")
local hasCrowd, Crowd = pcall(require, "src.features.pedestrians.render") -- the crowd's drawn stride

local Footsteps = {
  name = "footsteps",
}

-- Tuning ------------------------------------------------------------------
Footsteps.volume = 0.6 -- default level of the "footsteps" channel
Footsteps.refDistance = 70 -- px: full volume inside this radius
Footsteps.maxDistance = 600 -- px: quietest at this distance
Footsteps.hearing = 520 -- px: steps further away than this aren't played
Footsteps.moving = 25 -- px/s: slower than this is standing still
Footsteps.running = 95 -- px/s: faster than this is a run (walk 45, sprint 170)
Footsteps.walkGain = 0.55
Footsteps.runGain = 0.9
Footsteps.crowdGain = 0.6 -- a pedestrian's steps against a player's
Footsteps.crowdHeard = 4 -- only the nearest few pedestrians, or a crowd is a din

-- What the ground is, by map kind, where the tile is plain "ground".
local GROUND = { beach = "sand", forest = "grass", cliff = "grass", culdesac = "grass", city17 = "hard" }
-- And inside a city block, by the kind of block.
local BLOCK_GROUND = { park = "grass" }

local bank = {} -- surface -> list of Sources (takes)
local walkers = {} -- key -> { x, y, speed, step }

-- Sounds --------------------------------------------------------------------

local function between(lo, hi)
  return lo + (Synth.noise() * 0.5 + 0.5) * (hi - lo)
end

local function make(seconds, build)
  local buf = Synth.newBuffer(seconds)
  build(buf)
  local source = love.audio.newSource(buf:toSoundData(0.9), "static")
  source:setAttenuationDistances(Footsteps.refDistance, Footsteps.maxDistance)
  return source
end

local SURFACES = {
  -- A shoe on concrete: a heel's dull knock and a short scuff.
  hard = function(buf)
    buf:sweep(0, 0.05, between(150, 190), 80, { wave = "sine", amp = 0.8, decay = 0.012 })
    local scuff = Synth.newBuffer(0.12)
    scuff:noiseBurst(0, 0.06, { amp = 0.6, decay = 0.01 })
    scuff:noiseBurst(between(0.02, 0.035), 0.04, { amp = 0.3, decay = 0.012 }) -- the toe coming down
    scuff:highpass(900)
    scuff:lowpass(5000)
    scuff:mixInto(buf, 1)
  end,
  -- Grass: a soft swish of blades and a muffled thud.
  grass = function(buf)
    buf:sweep(0, 0.06, 120, 60, { wave = "sine", amp = 0.4, decay = 0.02 })
    local swish = Synth.newBuffer(0.12)
    swish:noiseBurst(0, 0.1, { amp = 0.5, decay = 0.035 })
    swish:highpass(1200)
    swish:lowpass(4000)
    swish:mixInto(buf, 1)
  end,
  -- Sand: a crunch of grains under a soft heel.
  sand = function(buf)
    buf:sweep(0, 0.06, 100, 55, { wave = "sine", amp = 0.45, decay = 0.02 })
    local crunch = Synth.newBuffer(0.12)
    for _ = 1, 26 do
      crunch:noiseBurst(between(0, 0.08) ^ 1.3 * 2, 0.004, { amp = between(0.2, 0.6), decay = 0.0015 })
    end
    crunch:noiseBurst(0, 0.08, { amp = 0.2, decay = 0.03 })
    crunch:highpass(700)
    crunch:lowpass(3200)
    crunch:mixInto(buf, 1)
  end,
  -- Shallow water: a slap and a splash, a bubble or two.
  water = function(buf)
    buf:noiseBurst(0, 0.1, { amp = 0.7, decay = 0.035 })
    buf:highpass(600)
    buf:sweep(between(0.01, 0.03), 0.04, between(400, 600), 1100, { wave = "sine", amp = 0.25, decay = 0.015 })
    buf:sweep(between(0.04, 0.07), 0.03, between(500, 700), 1300, { wave = "sine", amp = 0.15, decay = 0.012 })
  end,
}

function Footsteps:load()
  for surface, build in pairs(SURFACES) do
    bank[surface] = {}
    for i = 1, 4 do
      bank[surface][i] = make(0.14, build)
    end
  end
  Audio.registerChannel("footsteps", "Footsteps", self.volume, function()
    for i, surface in ipairs({ "hard", "hard", "grass", "grass" }) do
      local s = bank[surface][i]:clone()
      s:setRelative(true)
      s:setVolume(Audio.volume("footsteps"))
      s:play()
    end
  end)
end

function Footsteps:enterGame()
  walkers = {}
end

function Footsteps:exitGame()
  walkers = {}
end

-- The ground --------------------------------------------------------------

--- What is underfoot at (x, y): "hard", "grass", "sand" or "water".
function Footsteps.surfaceAt(x, y)
  local city = Features.byName["city-map"]
  local map = city and city.map
  if not (map and map.tiles) then
    return "hard"
  end
  local tile = Layout.tileAt(map, x, y)
  if tile == "water" then
    return "water"
  elseif tile ~= "ground" and tile ~= "core" then
    return "hard" -- road, pavement, and anything built
  elseif tile == "ground" and GROUND[map.kind] then
    return GROUND[map.kind]
  end
  -- A city block's inside ("core"): grass in a park, else paved.
  local c = math.floor((x - map.x0) / Layout.TILE)
  local r = math.floor((y - map.y0) / Layout.TILE)
  for _, b in ipairs(map.blocks or {}) do
    if c >= b.tx and c < b.tx + b.tw and r >= b.ty and r < b.ty + b.th then
      return BLOCK_GROUND[b.kind] or "hard"
    end
  end
  return "hard"
end

-- Stepping ----------------------------------------------------------------

local function step(x, y, gain, running)
  local takes = bank[Footsteps.surfaceAt(x, y)]
  local s = takes[love.math.random(#takes)]:clone()
  s:setPosition(x, 0, y)
  s:setPitch((running and 1.06 or 1) * (0.92 + love.math.random() * 0.16))
  s:setVolume(Audio.volume("footsteps") * gain * (running and Footsteps.runGain or Footsteps.walkGain))
  s:play()
end

--- One walker `key` at (x, y) this frame: track its speed, and step when
--- its drawn stride brings a foot down. `phaseOf(running)` is that stride's
--- phase in radians (sin of it is the swing); (lx, ly) is the listener.
local function walk(self, key, x, y, dt, gain, phaseOf, lx, ly)
  local w = walkers[key]
  if not w then
    walkers[key] = { x = x, y = y, speed = 0, seen = true }
    return
  end
  w.seen = true
  local moved = math.sqrt((x - w.x) ^ 2 + (y - w.y) ^ 2)
  w.x, w.y = x, y
  if moved > 60 then -- a teleport, a respawn, getting out of a car: not a step
    w.speed = 0
    return
  end
  w.speed = w.speed + (moved / math.max(dt, 1e-3) - w.speed) * math.min(1, dt * 15)
  local running = w.speed > self.running
  -- A foot is down at each peak of the swing: phase pi/2, 3pi/2, ...
  local index = math.floor(phaseOf(running) / math.pi + 0.5)
  local due = w.step and index ~= w.step
  w.step = index
  if due and w.speed > self.moving and (x - lx) ^ 2 + (y - ly) ^ 2 < self.hearing * self.hearing then
    step(x, y, gain, running)
  end
end

function Footsteps:update(dt, client)
  local lx, ly = client:myPose()
  if not lx then
    return
  end
  for _, w in pairs(walkers) do
    w.seen = false
  end

  -- Players on foot, on the same stride the game state draws them with.
  local t = love.timer.getTime()
  for id, b in pairs(client.bodies) do
    if not b.dead then
      walk(self, id, b.dx, b.dy, dt, 1, function(running)
        return t * ((b.running or running) and 16 or 8) + (b.bob or 0)
      end, lx, ly)
    end
  end

  -- The crowd, on theirs (pedestrians/render.lua). Frozen ones stand still.
  if hasCrowd and Features.byName.pedestrians and Crowd.peds then
    local near = {}
    for id, p in pairs(Crowd.peds) do
      local d2 = (p.dx - lx) ^ 2 + (p.dy - ly) ^ 2
      if not p.frozen and d2 < self.hearing * self.hearing then
        near[#near + 1] = { id = id, p = p, d2 = d2 }
      end
    end
    table.sort(near, function(a, b)
      return a.d2 < b.d2
    end)
    local pt = Crowd.time or 0
    for i = 1, math.min(#near, self.crowdHeard) do
      local p = near[i].p
      walk(self, "ped" .. near[i].id, p.dx, p.dy, dt, self.crowdGain, function()
        return pt * (p.flee and 16 or 7) + (p.bob or 0)
      end, lx, ly)
    end
  end

  for key, w in pairs(walkers) do
    if not w.seen then
      walkers[key] = nil
    end
  end
end

--- For tests.
function Footsteps.walkers()
  return walkers
end

return Footsteps
