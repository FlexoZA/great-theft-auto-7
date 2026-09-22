-- Menu theme for inclusive mode: a boom-bap hip-hop loop, rendered by
-- src/audio/synth.lua. 90 BPM in E minor over an Em7 - Am7 - Cmaj7 - B7
-- turnaround. Sub bass and Rhodes-ish stabs under swung drums, a pentatonic
-- hook from the second phrase on, a scratch on each turnaround and vinyl
-- crackle over the lot. ~32 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 90
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16
local SWING = SIXTEENTH * 0.16 -- offbeat sixteenths land late
local PHRASES = 3 -- of four bars each

--- Start of sixteenth `i` in the bar at `t`, swung.
local function at(t, i)
  return t + i * SIXTEENTH + (i % 2 == 1 and SWING or 0)
end

-- Notation helpers: a bar is a list of { note|false, sixteenths } summing to 16.
local function bar(...)
  local out = {}
  for _, group in ipairs({ ... }) do
    for _, ev in ipairs(group) do
      out[#out + 1] = ev
    end
  end
  return out
end
local function hit(n, len)
  return { { n, len } }
end
local function rest(len)
  return { { false, len } }
end

-- Progression ----------------------------------------------------------------

local PROGRESSION = {
  { bass = "E2", keys = { "E3", "G3", "B3", "D4" } },
  { bass = "A2", keys = { "A3", "C4", "E4", "G4" } },
  { bass = "C3", keys = { "C4", "E4", "G4", "B4" } },
  { bass = "B2", keys = { "B3", "D#4", "F#4", "A4" } },
}

-- Stab placements, { sixteenth, length }. Odd bars push, even bars answer.
local KEYS = {
  { { 0, 4 }, { 6, 3 }, { 10, 5 } },
  { { 0, 3 }, { 3, 3 }, { 8, 3 }, { 12, 4 } },
}

-- Bass placements, { sixteenth, length, semitones above the root }.
local BASS = {
  { { 0, 5, 0 }, { 6, 2, 0 }, { 10, 3, 12 }, { 14, 2, 0 } },
  { { 0, 4, 0 }, { 6, 3, 12 }, { 11, 3, 0 }, { 14, 2, 7 } },
}

-- Hook: E minor pentatonic, four bars.
local hook = {
  bar(hit("B4", 3), hit("A4", 3), hit("G4", 2), rest(2), hit("E4", 6)),
  bar(rest(2), hit("G4", 2), hit("A4", 4), hit("G4", 2), hit("E4", 6)),
  bar(hit("E5", 3), hit("D5", 3), hit("B4", 2), rest(2), hit("G4", 6)),
  bar(hit("A4", 4), hit("B4", 4), hit("E4", 8)),
}

-- Voices ------------------------------------------------------------------------

--- Electric-piano stab: sine body, a detuned triangle for the tine buzz and a
--- quiet octave that dies away straight off.
local function keyStab(buf, t, len, note)
  local f = Synth.freq(note)
  local dur = len * SIXTEENTH * 0.95
  buf:tone(t, dur, f, { wave = "sine", amp = 0.26, attack = 0.006, decay = 0.35, sustain = 0.18, release = 0.09 })
  buf:tone(t, dur, f, { wave = "tri", amp = 0.13, detune = 6, decay = 0.28, sustain = 0.10 })
  buf:tone(t, dur, f * 2, { wave = "sine", amp = 0.05, decay = 0.12, sustain = 0 })
end

--- Sub an octave below the written note, with a triangle on top so it still
--- reads on small speakers.
local function subBass(buf, t, len, midi)
  local f = Synth.midiFreq(midi)
  local dur = len * SIXTEENTH * 0.98
  buf:tone(t, dur, f / 2, { wave = "sine", amp = 0.85, attack = 0.008, decay = 0.9, sustain = 0.75, release = 0.06 })
  buf:tone(t, dur, f, { wave = "tri", amp = 0.16, decay = 0.3, sustain = 0.2 })
end

local function hookNote(buf, t, len, note)
  local dur = len * SIXTEENTH * 0.9
  buf:tone(t, dur, Synth.freq(note), {
    wave = "tri",
    amp = 0.30,
    attack = 0.02,
    decay = 0.8,
    sustain = 0.6,
    release = 0.07,
    vibRate = 5,
    vibDepth = len >= 4 and 0.25 or 0,
  })
end

--- Boom-bap kit. `b` is the bar within the phrase; the fourth bar gets a fill.
local function drumBar(buf, t, b)
  local kicks = b % 2 == 1 and { 0, 6, 10 } or { 0, 3, 10, 11 }
  for _, i in ipairs(kicks) do
    buf:kick(at(t, i), 1.0)
  end
  buf:snare(at(t, 4), 0.85)
  buf:snare(at(t, 12), 0.85)
  for i = 0, 15, 2 do
    buf:hat(at(t, i), i % 4 == 0 and 0.30 or 0.22, false)
  end
  buf:hat(at(t, 7), 0.16, false)
  buf:hat(at(t, 15), 0.18, false)
  if b == 4 then
    buf:snare(at(t, 14), 0.45)
    buf:snare(at(t, 15), 0.7)
    buf:hat(at(t, 14), 0.35, true)
  end
end

--- Turntable scratch: a pitch drop and the push back up.
local function scratch(buf, t)
  buf:sweep(t, 0.09, 900, 260, { wave = "saw", amp = 0.22, decay = 0.05 })
  buf:sweep(t + 0.10, 0.07, 300, 820, { wave = "saw", amp = 0.18, decay = 0.04 })
end

--- Surface noise: sparse clicks at deterministic but uneven spacing.
local function vinyl(buf, total)
  local t = 0
  while t < total do
    buf:noiseBurst(t, 0.006, { amp = 0.05 + (Synth.noise() + 1) * 0.03, decay = 0.0015 })
    t = t + 0.02 + (Synth.noise() + 1) * 0.045
  end
end

-- Render ----------------------------------------------------------------------

function Theme.duration()
  return PHRASES * 4 * BAR
end

--- Renders the whole loop. Returns a SoundData.
function Theme.render()
  local total = Theme.duration()
  local keys = Synth.newBuffer(total + 0.5)
  local bass = Synth.newBuffer(total + 0.5)
  local lead = Synth.newBuffer(total + 0.5)
  local drums = Synth.newBuffer(total + 0.5)
  local crackle = Synth.newBuffer(total + 0.5)

  local t = 0
  for phrase = 1, PHRASES do
    for b = 1, 4 do
      local chord = PROGRESSION[b]
      local alt = (b - 1) % 2 + 1

      for _, stab in ipairs(KEYS[alt]) do
        for _, note in ipairs(chord.keys) do
          keyStab(keys, at(t, stab[1]), stab[2], note)
        end
      end

      local root = Synth.midi(chord.bass)
      for _, note in ipairs(BASS[alt]) do
        subBass(bass, at(t, note[1]), note[2], root + note[3])
      end

      drumBar(drums, t, b)

      if phrase > 1 then
        local cursor = 0
        for _, ev in ipairs(hook[b]) do
          if ev[1] then
            hookNote(lead, at(t, cursor), ev[2], ev[1])
          end
          cursor = cursor + ev[2]
        end
      end

      if b == 4 and phrase < PHRASES then
        scratch(lead, at(t, 8))
      end

      t = t + BAR
    end
  end

  vinyl(crackle, total)

  keys:drive(1.6)
  keys:lowpass(2600)
  bass:lowpass(320)
  lead:lowpass(3000)
  drums:highpass(25)
  crackle:highpass(1800)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  keys:mixInto(master, 0.50)
  bass:mixInto(master, 0.55)
  lead:mixInto(master, 0.32)
  drums:mixInto(master, 0.70)
  crackle:mixInto(master, 0.25)
  return master:toSoundData(0.9)
end

return Theme
