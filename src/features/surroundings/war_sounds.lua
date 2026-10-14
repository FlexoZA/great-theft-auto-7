-- The sound of the turf war past the Market's walls (turf_war.lua), so the
-- fight out there is heard as well as seen. Synthesised at load, played in
-- the world where it happens, so it pans and fades with distance:
--
--   - A burst opening up from a barricade (TurfWar.events): the Static's
--     duller and heavier, Halcyon's crisper, six rounds as the tracers
--     show them.
--   - A shell coming down in no-man's-land: a deep thump and a long rumble.
--   - Now and then, further out than anything in sight, the same again,
--     quieter: the war is bigger than the streets you can see.
--
-- Everything far off is muffled more (a low-pass on the source, where the
-- system has one). Its own channel on the settings screen. Client only.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local WarSounds = {
  volume = 0.7, -- default of the "battle" channel
  reach = 3600, -- px from the listener that events are heard from
  refDistance = 350, -- px: full volume inside this
  maxDistance = 4500, -- px: quietest beyond this
  burstGap = 0.12, -- seconds at least between two bursts played
  shellGap = 1.1, -- seconds at least between two shells played (each rumbles on for two)
  farEvery = { 2, 5 }, -- seconds between the war further out (min, max)
  farAway = { 2600, 3800 }, -- px from the listener it is (min, max)
}

local BURST_ROUNDS = 6
local BURST_GAP = 0.07 -- seconds between rounds, as turf_war.lua's tracers

local bank = {} -- static, halcyon, shell: base Sources
local lastAt = { burst = -1, shell = -1 }
local farIn = 2
local time = 0
local random = love.math.random

function WarSounds.load()
  Audio.registerChannel("battle", "Grey City: the battle beyond the walls", WarSounds.volume, function()
    WarSounds.play("shell", nil, nil, 1)
  end)
  local function make(seconds, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(0.85), "static")
    src:setAttenuationDistances(WarSounds.refDistance, WarSounds.maxDistance)
    return src
  end
  -- A burst: each round a crack and a thump, the crack rolling off.
  local function burst(buf, crack, thumpFrom, thumpTo, cutoff)
    for i = 0, BURST_ROUNDS - 1 do
      local t = i * BURST_GAP + math.abs(Synth.noise()) * 0.008 -- never before the start
      buf:noiseBurst(t, 0.08, { amp = 0.9, decay = crack })
      buf:sweep(t, 0.12, thumpFrom, thumpTo, { wave = "sine", amp = 0.7, decay = 0.04 })
      buf:noiseBurst(t + 0.02, 0.25, { amp = 0.18, decay = 0.09 }) -- the echo off the towers
    end
    buf:lowpass(cutoff)
    buf:drive(1.6)
  end
  bank.static = make(0.75, function(buf)
    burst(buf, 0.025, 160, 55, 1800)
  end)
  bank.halcyon = make(0.75, function(buf)
    burst(buf, 0.014, 260, 90, 2800)
  end)
  -- A shell: a deep thump, a crack on top, and a long rumble rolling away.
  bank.shell = make(2.2, function(buf)
    buf:sweep(0, 0.5, 95, 26, { wave = "sine", amp = 1.0, decay = 0.22 })
    buf:noiseBurst(0, 0.12, { amp = 0.8, decay = 0.03 })
    buf:noiseBurst(0.02, 2.0, { amp = 0.55, decay = 0.6 })
    buf:lowpass(700)
    buf:lowpass(900)
    buf:drive(2.2)
  end)
end

--- Play `name` at (x, y) in the world (nil: in your ears), at `volume`.
--- `far` 0..1 muffles it, where the system can.
function WarSounds.play(name, x, y, volume, far)
  local base = bank[name]
  if not base then
    return
  end
  local s = base:clone()
  if x then
    s:setPosition(x, 0, y)
  else
    s:setRelative(true)
    s:setPosition(0, 0, 0)
  end
  s:setPitch(0.9 + random() * 0.2)
  s:setVolume(volume * Audio.volume("battle"))
  if far and far > 0 then
    pcall(s.setFilter, s, { type = "lowpass", volume = 1, highgain = math.max(0.08, 1 - far) })
  end
  s:play()
end

--- How far (0..1 of `reach`) (x, y) is from the listener at (lx, ly).
local function farness(lx, ly, x, y)
  return math.min(1, math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2) / WarSounds.reach)
end

--- One step: the events that started since `t0` (turf_war's clock, now `t1`)
--- near the listener at (lx, ly), and now and then the war further out.
--- `events(lx, ly, reach, t0, t1, fn)` is grey_city's: what started, where.
function WarSounds.update(dt, lx, ly, t0, t1, events)
  time = time + dt
  events(lx, ly, WarSounds.reach, t0, t1, function(kind, x, y)
    local far = farness(lx, ly, x, y)
    if far >= 1 then
      return
    end
    local key = kind == "shell" and "shell" or "burst"
    local gap = key == "shell" and WarSounds.shellGap or WarSounds.burstGap
    if time - lastAt[key] >= gap then
      lastAt[key] = time
      WarSounds.play(kind, x, y, key == "shell" and 0.9 or 0.7, far)
    end
  end)
  farIn = farIn - dt
  if farIn <= 0 then
    farIn = WarSounds.farEvery[1] + random() * (WarSounds.farEvery[2] - WarSounds.farEvery[1])
    local a = random() * 2 * math.pi
    local d = WarSounds.farAway[1] + random() * (WarSounds.farAway[2] - WarSounds.farAway[1])
    local kind = random() < 0.3 and "shell" or (random() < 0.5 and "static" or "halcyon")
    WarSounds.play(kind, lx + math.cos(a) * d, ly + math.sin(a) * d, 0.5, 0.85)
  end
end

return WarSounds
