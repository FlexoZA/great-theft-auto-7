-- Tiny offline synthesiser. Renders into float buffers, then converts to a
-- LÖVE SoundData. Everything is deterministic so the song is the same on
-- every machine. Used by src/audio/menu_theme.lua.

local Synth = {}

Synth.RATE = 22050 -- lo-fi on purpose: retro flavour and half the render time
local RATE = Synth.RATE

local hasFFI, ffi = pcall(require, "ffi")

-- Buffers -------------------------------------------------------------------

local Buffer = {}
Buffer.__index = Buffer

function Synth.newBuffer(seconds)
  local n = math.ceil(seconds * RATE)
  local data
  if hasFFI then
    data = ffi.new("float[?]", n) -- zero-initialised, 0-indexed
  else
    data = {}
    for i = 0, n - 1 do
      data[i] = 0
    end
  end
  return setmetatable({ data = data, n = n }, Buffer)
end

-- Notes -----------------------------------------------------------------------

local SEMITONE = {
  C = 0, ["C#"] = 1, D = 2, ["D#"] = 3, E = 4, F = 5, ["F#"] = 6, G = 7, ["G#"] = 8, A = 9, ["A#"] = 10, B = 11,
}

function Synth.midi(name) -- "E2", "F#4" -> MIDI number
  local letter, sharp, octave = name:match("^([A-G])(#?)(%d)$")
  assert(letter, "bad note name " .. tostring(name))
  return 12 * (tonumber(octave) + 1) + SEMITONE[letter .. sharp]
end

function Synth.midiFreq(m)
  return 440 * 2 ^ ((m - 69) / 12)
end

function Synth.freq(name)
  return Synth.midiFreq(Synth.midi(name))
end

-- Deterministic noise (Park-Miller) ------------------------------------------

local seed = 12345
local function noise()
  seed = (seed * 16807) % 2147483647
  return seed / 2147483647 * 2 - 1
end

-- Oscillators -----------------------------------------------------------------

local TWO_PI = 2 * math.pi
local WAVES = {
  saw = function(p)
    return 2 * p - 1
  end,
  square = function(p)
    return p < 0.5 and 1 or -1
  end,
  tri = function(p)
    return p < 0.5 and (4 * p - 1) or (3 - 4 * p)
  end,
  sine = function(p)
    return math.sin(TWO_PI * p)
  end,
}

--- Add a note starting at t0 seconds for dur seconds.
--- o: wave, amp, attack, decay, sustain, release (seconds / level),
---    detune (cents), vibRate (Hz), vibDepth (semitones)
function Buffer:tone(t0, dur, freq, o)
  local wave = WAVES[o.wave or "saw"]
  local amp = o.amp or 0.3
  local a, d, s, r = o.attack or 0.004, o.decay or 0.3, o.sustain or 0.6, o.release or 0.04
  local vibRate, vibDepth = o.vibRate or 0, o.vibDepth or 0
  local f = freq * 2 ^ ((o.detune or 0) / 1200)
  local s0 = math.floor(t0 * RATE)
  local s1 = math.min(self.n - 1, math.floor((t0 + dur + r) * RATE))
  local data = self.data
  local phase = 0
  local endEnv = math.max(s, math.exp(-dur / d))
  for i = s0, s1 do
    local t = (i - s0) / RATE
    local env
    if t < dur then
      env = math.min(t / a, 1) * math.max(s, math.exp(-t / d))
    else
      env = endEnv * (1 - (t - dur) / r)
    end
    local fi = f
    if vibDepth > 0 then
      fi = f * 2 ^ (math.sin(TWO_PI * vibRate * t) * vibDepth / 12)
    end
    phase = phase + fi / RATE
    if phase >= 1 then
      phase = phase - 1
    end
    data[i] = data[i] + wave(phase) * amp * env
  end
end

-- Drums -----------------------------------------------------------------------

function Buffer:kick(t0, amp)
  local s0 = math.floor(t0 * RATE)
  local s1 = math.min(self.n - 1, s0 + math.floor(0.25 * RATE))
  local data = self.data
  local phase = 0
  for i = s0, s1 do
    local t = (i - s0) / RATE
    local f = 45 + 130 * math.exp(-t / 0.03) -- pitch sweep down
    phase = phase + f / RATE
    local v = math.sin(TWO_PI * phase) * math.exp(-t / 0.11)
    if t < 0.004 then
      v = v + noise() * 0.5 -- click
    end
    data[i] = data[i] + v * amp
  end
end

function Buffer:snare(t0, amp)
  local s0 = math.floor(t0 * RATE)
  local s1 = math.min(self.n - 1, s0 + math.floor(0.2 * RATE))
  local data = self.data
  for i = s0, s1 do
    local t = (i - s0) / RATE
    local v = noise() * math.exp(-t / 0.07) * 0.8 + math.sin(TWO_PI * 190 * t) * math.exp(-t / 0.04) * 0.5
    data[i] = data[i] + v * amp
  end
end

function Buffer:hat(t0, amp, open)
  local len, decay = 0.05, 0.015
  if open then
    len, decay = 0.3, 0.09
  end
  local s0 = math.floor(t0 * RATE)
  local s1 = math.min(self.n - 1, s0 + math.floor(len * RATE))
  local data = self.data
  local last = 0
  for i = s0, s1 do
    local t = (i - s0) / RATE
    local n = noise()
    local v = (n - last) * math.exp(-t / decay) -- differenced noise = crude high-pass
    last = n
    data[i] = data[i] + v * amp
  end
end

-- Effects ---------------------------------------------------------------------

--- Soft-clip the whole buffer (tanh). gain 1 = clean, 8 = fuzz.
function Buffer:drive(gain)
  local data = self.data
  for i = 0, self.n - 1 do
    local x = data[i] * gain
    if x > 12 then
      x = 12
    elseif x < -12 then
      x = -12
    end
    local e = math.exp(2 * x)
    data[i] = (e - 1) / (e + 1)
  end
end

function Buffer:lowpass(cutoff)
  local alpha = 1 - math.exp(-TWO_PI * cutoff / RATE)
  local data = self.data
  local y = 0
  for i = 0, self.n - 1 do
    y = y + alpha * (data[i] - y)
    data[i] = y
  end
end

function Buffer:highpass(cutoff)
  local alpha = 1 - math.exp(-TWO_PI * cutoff / RATE)
  local data = self.data
  local lp = 0
  for i = 0, self.n - 1 do
    lp = lp + alpha * (data[i] - lp)
    data[i] = data[i] - lp
  end
end

function Buffer:mixInto(dst, gain)
  local a, b = self.data, dst.data
  for i = 0, math.min(self.n, dst.n) - 1 do
    b[i] = b[i] + a[i] * gain
  end
end

function Buffer:peak()
  local p = 0
  local data = self.data
  for i = 0, self.n - 1 do
    local v = math.abs(data[i])
    if v > p then
      p = v
    end
  end
  return p
end

--- Normalise to `level` and convert to 16-bit mono SoundData.
function Buffer:toSoundData(level)
  local scale = (level or 0.9) / math.max(self:peak(), 1e-6)
  local sd = love.sound.newSoundData(self.n, RATE, 16, 1)
  local data = self.data
  local ptr = hasFFI and sd.getFFIPointer and ffi.cast("int16_t*", sd:getFFIPointer())
  for i = 0, self.n - 1 do
    local v = data[i] * scale
    if v > 1 then
      v = 1
    elseif v < -1 then
      v = -1
    end
    if ptr then
      ptr[i] = math.floor(v * 32767 + 0.5)
    else
      sd:setSample(i, v)
    end
  end
  return sd
end

return Synth
