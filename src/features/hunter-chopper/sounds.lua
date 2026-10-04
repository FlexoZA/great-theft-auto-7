-- The Hunter-Chopper's noises, synthesised at load: its rotor, a loop that
-- follows it about (positional, so it pans and fades with distance and you
-- hear it coming across the city), and the whine of its gun locking on.
-- The rounds themselves sound as the weapons feature's do.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "hunter-chopper" channel
  refDistance = 420, -- px: full volume inside this
  maxDistance = 3200, -- px: quietest beyond this
}

local RATE = Synth.RATE
local LOOP = 1.0 -- seconds in the rotor loop; everything in it repeats a whole number of times
local THUMPS = 20 -- blade passes a second: the wop-wop (even, so the strong and weak beats alternate across the seam)
local WHINE = 1320 -- Hz, the turbine

local bank = {} -- name -> base Source
local rotorData = nil

--- One seamless second of rotor: a heavy chop of low thumps, each a puff
--- of air and a low knock, over a rumble and the turbine's thin whine. The
--- filters run over it twice, so the end leads back into the start.
local function renderRotor()
  local buf = Synth.newBuffer(LOOP)
  local data, n = buf.data, buf.n
  local TWO_PI = 2 * math.pi
  local period = n / THUMPS
  local seed = 12345
  local function noise()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647 * 2 - 1
  end
  local raw = {}
  for i = 0, n - 1 do
    local t = i / RATE
    local ph = (i % period) / period -- 0..1 through one blade pass
    local env = math.exp(-ph * 9) -- the thump, dying away before the next
    local accent = (math.floor(i / period) % 2 == 0) and 1 or 0.8 -- blades are never quite alike
    local knock = math.sin(TWO_PI * 62 * ph * period / RATE) * env * accent
    raw[i] = noise() * (0.35 + env * 0.9 * accent) + knock * 0.9
      + math.sin(TWO_PI * WHINE * t) * 0.05 + math.sin(TWO_PI * WHINE * 2 * t) * 0.02
  end
  -- Low-pass the air (keeping the whine, added back after), twice round so it loops.
  local alpha = 1 - math.exp(-TWO_PI * 700 / RATE)
  local y = 0
  for pass = 1, 2 do
    for i = 0, n - 1 do
      y = y + alpha * (raw[i] - y)
      if pass == 2 then
        data[i] = y + math.sin(TWO_PI * WHINE * i / RATE) * 0.04
      end
    end
  end
  return buf:toSoundData(0.85)
end

local function make(seconds, build)
  local buf = Synth.newBuffer(seconds)
  build(buf)
  local source = love.audio.newSource(buf:toSoundData(0.9), "static")
  source:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  return source
end

function Sounds.load()
  Audio.registerChannel("hunter-chopper", "Hunter-Chopper", Sounds.volume, function()
    Sounds.play("lock", 0, 0)
  end)
  rotorData = renderRotor()
  -- The gun locking on: a whine climbing to a shriek over the second before it fires.
  bank.lock = make(1.1, function(buf)
    buf:sweep(0, 1.0, 400, 2400, { wave = "saw", amp = 0.35, decay = 99 })
    buf:sweep(0, 1.0, 404, 2420, { wave = "square", amp = 0.12, decay = 99 })
    for k = 0, 9 do -- beeps closing up
      local t = 1 - 1 / (1 + k * 0.45)
      buf:tone(t, 0.03, 2800, { wave = "sine", amp = 0.25, attack = 0.002, decay = 0.02, sustain = 0 })
    end
    buf:lowpass(5000)
  end)
end

--- Play `name` once at world position (x, y).
function Sounds.play(name, x, y)
  local base = bank[name]
  if not base then
    return nil
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setVolume(Audio.volume("hunter-chopper"))
  s:play()
  return s
end

--- A new rotor loop, playing, at (x, y). Move it with `Sounds.place`.
function Sounds.rotor(x, y)
  if not rotorData then
    return nil
  end
  local s = love.audio.newSource(rotorData, "static")
  s:setLooping(true)
  s:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  Sounds.place(s, x, y, 1)
  s:play()
  return s
end

--- Keep the rotor loop `s` with the chopper at (x, y), its pitch at `pitch`
--- and its volume at the channel's.
function Sounds.place(s, x, y, pitch)
  s:setPosition(x, 0, y)
  s:setPitch(pitch)
  s:setVolume(Audio.volume("hunter-chopper"))
end

return Sounds
