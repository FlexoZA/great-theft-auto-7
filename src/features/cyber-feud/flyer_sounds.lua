-- The flying machines' engines (flyers.lua), synthesised at load the way the
-- Hunter-Chopper's rotor is: a seamless one-second loop for each, played
-- positionally so it pans and fades with distance and you hear it coming:
--
--   aerodyne  a turbine's whine over the hum of its four fans
--   hauler    the slow, deep thump of two big rotors over a rumble
--   adrone    a high buzz, four small rotors a little out of tune
--   dropship  Halcyon's dropship over the Roof (dropship.lua): two rockets'
--             roar, a crackle in it, over a low rumble
--
-- Everything in a loop repeats a whole number of times a second, and the
-- filters run round it twice, so the end leads back into the start. Their
-- own channel on the settings screen.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.7, -- default of the "flyovers" channel
  refDistance = 500, -- px: full volume inside this
  maxDistance = 2600, -- px: quietest beyond this
}

local RATE = Synth.RATE
local TWO_PI = 2 * math.pi
local data = {} -- kind -> SoundData

--- A second of `sample(i, t)`, low-passed at `cutoff` (twice round, so it
--- loops), plus `clean(i, t)` added after the filter.
local function render(sample, cutoff, clean)
  local buf = Synth.newBuffer(1)
  local n = buf.n
  local raw = {}
  for i = 0, n - 1 do
    raw[i] = sample(i, i / RATE)
  end
  local alpha = 1 - math.exp(-TWO_PI * cutoff / RATE)
  local y = 0
  for pass = 1, 2 do
    for i = 0, n - 1 do
      y = y + alpha * (raw[i] - y)
      if pass == 2 then
        buf.data[i] = y + (clean and clean(i, i / RATE) or 0)
      end
    end
  end
  return buf:toSoundData(0.85)
end

local seed = 4242
local function noise()
  seed = (seed * 16807) % 2147483647
  return seed / 2147483647 * 2 - 1
end

local function saw(f, t)
  local p = f * t
  return 2 * (p - math.floor(p)) - 1
end

function Sounds.load()
  Audio.registerChannel("flyovers", "Grey City: flying machines overhead", Sounds.volume, function()
    local s = Sounds.loop("aerodyne")
    if s then
      s:setRelative(true)
      s:setPosition(0, 0, 0)
      s:setLooping(false)
    end
  end)
  -- The aerodyne: air rushing through four fans, their hum pulsing with the
  -- blades, and over it the turbine's whine.
  data.aerodyne = render(function(_, t)
    local pulse = 0.75 + 0.25 * math.sin(TWO_PI * 40 * t)
    return noise() * 0.5 * pulse + saw(110, t) * 0.35 * pulse + saw(165, t) * 0.12
  end, 1400, function(_, t)
    return math.sin(TWO_PI * 880 * t) * 0.05 + math.sin(TWO_PI * 1320 * t) * 0.035
      + math.sin(TWO_PI * 1763 * t) * 0.015
  end)
  -- The hauler: two big rotors, a deep thump every blade pass, the strong and
  -- weak ones taking turns, over a rumble.
  local THUMPS = 12
  data.hauler = render(function(i, t)
    local n = RATE / THUMPS
    local ph = (i % n) / n
    local env = math.exp(-ph * 6)
    local accent = (math.floor(i / n) % 2 == 0) and 1 or 0.75
    local knock = math.sin(TWO_PI * 48 * ph * n / RATE) * env * accent
    return noise() * (0.25 + env * 0.8 * accent) + knock * 1.1 + saw(55, t) * 0.2
  end, 520)
  -- The ad drone: four small rotors buzzing, each a little off the others,
  -- so the buzz beats and wobbles.
  data.adrone = render(function(_, t)
    local v = 0
    for _, f in ipairs({ 220, 223, 227, 231 }) do
      local p = f * t
      v = v + ((p - math.floor(p)) < 0.5 and 0.18 or -0.18)
    end
    return v + noise() * 0.12
  end, 2600)
  -- The dropship: two rockets roaring, a crackle running through the roar,
  -- over a deep rumble.
  data.dropship = render(function(_, t)
    local crackle = noise() > 0.93 and 0.6 or 0
    return noise() * 0.7 + crackle + saw(41, t) * 0.25 + saw(62, t) * 0.12
  end, 900)
end

--- A new engine loop for `kind`, playing. Move it with `Sounds.place`.
function Sounds.loop(kind)
  local d = data[kind]
  if not d then
    return nil
  end
  local s = love.audio.newSource(d, "static")
  s:setLooping(true)
  s:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  s:setVolume(Audio.volume("flyovers"))
  s:play()
  return s
end

--- Keep loop `s` with its machine at (x, y), at `pitch`, at the channel's volume.
function Sounds.place(s, x, y, pitch)
  s:setPosition(x, 0, y)
  s:setPitch(pitch)
  s:setVolume(Audio.volume("flyovers"))
end

return Sounds
