-- The Colosseum's theme, rendered by src/audio/synth.lua the way the other
-- maps' are. A gladiators' march at 100 BPM in D minor: war drums and a
-- low string ostinato to walk out on; then the brass fanfare over them;
-- then the fanfare again a fourth up with the crowd roaring under it; last
-- the drums alone, building, a roar swelling up to the top of the loop.
-- ~38 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 100
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16
local SQUEEZE = 2 -- how hard the peaks are squeezed at the end, so it sits as loud as the other themes

local ROOTS = { Dm = "D2", Bb = "A#1", C = "C2", A = "A1", Gm = "G1", F = "F2" }
local TRIADS = {
  Dm = { "D4", "F4", "A4" },
  Bb = { "A#3", "D4", "F4" },
  C = { "C4", "E4", "G4" },
  A = { "A3", "C#4", "E4" },
  Gm = { "G3", "A#3", "D4" },
  F = { "F3", "A3", "C4" },
}

-- The fanfare: { note|false, sixteenths } a bar.
local FANFARE = {
  { { "D5", 2 }, { "D5", 2 }, { "D5", 2 }, { "A5", 10 } },
  { { "G5", 4 }, { "F5", 4 }, { "E5", 4 }, { "D5", 4 } },
  { { "C5", 2 }, { "C5", 2 }, { "C5", 2 }, { "G5", 10 } },
  { { "A5", 6 }, { "G5", 2 }, { "E5", 4 }, { "C#5", 4 } },
}
local FANFARE_UP = {
  { { "G5", 2 }, { "G5", 2 }, { "G5", 2 }, { "D6", 10 } },
  { { "C6", 4 }, { "A#5", 4 }, { "A5", 4 }, { "G5", 4 } },
  { { "F5", 2 }, { "F5", 2 }, { "F5", 2 }, { "C6", 10 } },
  { { "A5", 8 }, { "C#6", 4 }, { "E6", 4 } },
}

-- The march, four bars a part.
local PARTS = {
  { chords = { "Dm", "Bb", "C", "A" }, strings = true },
  { chords = { "Dm", "Gm", "C", "A" }, strings = true, tune = FANFARE, snare = true },
  { chords = { "Gm", "F", "C", "A" }, strings = true, tune = FANFARE_UP, snare = true, crowd = true, pad = true },
  { chords = { "Dm", "Dm", "A", "A" }, build = true },
}

function Theme.duration()
  return #PARTS * 4 * BAR
end

-- Voices ---------------------------------------------------------------------

--- A low tom: a pitched thud that falls away.
local function tom(buf, t, f, amp)
  buf:sweep(t, 0.45, f, f * 0.6, { amp = amp, decay = 0.16 })
  buf:noiseBurst(t, 0.03, { amp = amp * 0.25, decay = 0.01 })
end

--- The war drums: a kick on the beat, toms answering, the march rhythm.
local function drums(buf, t, amp)
  for beat = 0, 3 do
    local at = t + beat * SIXTEENTH * 4
    buf:kick(at, amp)
    if beat % 2 == 1 then
      tom(buf, at + SIXTEENTH * 2, 110, amp * 0.6)
      tom(buf, at + SIXTEENTH * 3, 90, amp * 0.6)
    end
  end
end

--- The low strings sawing eighths on the root, an octave jump on the off beats.
local function ostinato(buf, t, chord)
  local f = Synth.freq(ROOTS[chord]) * 2
  for k = 0, 7 do
    local up = k % 4 == 3 and 2 or 1
    buf:tone(t + k * SIXTEENTH * 2, SIXTEENTH * 1.8, f * up, { wave = "saw", amp = 0.16, attack = 0.01,
      decay = 0.4, sustain = 0.5, release = 0.05 })
  end
end

--- A brass section on the tune: two horns a little apart, bright and buzzing.
local function brass(buf, t, events)
  for _, ev in ipairs(events) do
    local note, len = ev[1], ev[2]
    if note then
      local dur, f = len * SIXTEENTH * 0.92, Synth.freq(note)
      buf:tone(t, dur, f, { wave = "saw", amp = 0.22, attack = 0.03, decay = 1.5, sustain = 0.75, release = 0.08,
        vibRate = 5.5, vibDepth = len >= 8 and 0.15 or 0 })
      buf:tone(t, dur, f, { wave = "square", amp = 0.07, detune = -8, attack = 0.04, decay = 1.5, sustain = 0.7 })
      buf:tone(t, dur, f / 2, { wave = "saw", amp = 0.09, attack = 0.05, decay = 1.5, sustain = 0.7 })
    end
    t = t + len * SIXTEENTH
  end
end

local function pad(buf, t, chord)
  for _, note in ipairs(TRIADS[chord]) do
    buf:tone(t, BAR, Synth.freq(note), { wave = "tri", amp = 0.09, attack = 0.4, decay = 4, sustain = 0.8,
      release = 0.4 })
  end
end

--- The crowd: a long rush of noise, swelling and falling.
local function roar(buf, t, dur, amp)
  for k = 0, math.floor(dur / 0.1) do
    local swell = math.sin(math.pi * k * 0.1 / dur)
    buf:noiseBurst(t + k * 0.1, 0.2, { amp = amp * swell, decay = 0.12 })
  end
end

local function partBar(bufs, part, b, t)
  local chord = part.chords[b]
  if part.build then
    for k = 0, 15 do -- the drums alone, every sixteenth by the end, louder and louder
      if k % 4 == 0 or (b >= 3 and k % 2 == 0) or b == 4 then
        tom(bufs.drums, t + k * SIXTEENTH, 80 + (b - 1) * 10, 0.3 + (b - 1) * 0.1 + k * 0.01)
      end
    end
    bufs.drums:kick(t, 0.8)
    if b == 3 then
      roar(bufs.crowd, t, BAR * 2, 0.22)
    end
    return
  end
  drums(bufs.drums, t, 0.8)
  if part.strings then
    ostinato(bufs.strings, t, chord)
  end
  if part.tune then
    brass(bufs.brass, t, part.tune[b])
  end
  if part.pad then
    pad(bufs.strings, t, chord)
  end
  if part.snare then
    for k = 0, 3 do
      bufs.drums:snare(t + (k * 4 + 2) * SIXTEENTH, 0.25)
    end
  end
  if part.crowd and b == 1 then
    roar(bufs.crowd, t, BAR * 4, 0.14)
  end
end

-- Render ---------------------------------------------------------------------

--- Renders the whole march. Returns a SoundData.
function Theme.render()
  local total = Theme.duration()
  local bufs = {}
  for _, name in ipairs({ "drums", "strings", "brass", "crowd" }) do
    bufs[name] = Synth.newBuffer(total + 0.5)
  end
  local t = 0
  for _, part in ipairs(PARTS) do
    for b = 1, #part.chords do
      partBar(bufs, part, b, t)
      t = t + BAR
    end
  end
  bufs.brass:drive(1.6)
  bufs.brass:lowpass(3600)
  bufs.strings:lowpass(1800)
  bufs.crowd:lowpass(1200)
  bufs.drums:highpass(30)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  bufs.drums:mixInto(master, 0.75)
  bufs.strings:mixInto(master, 0.6)
  bufs.brass:mixInto(master, 0.55)
  bufs.crowd:mixInto(master, 0.5)
  master:drive(SQUEEZE / math.max(master:peak(), 1e-6))
  return master:toSoundData(0.9)
end

return Theme
