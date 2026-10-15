-- The beach landing's theme (D-Day), rendered by src/audio/synth.lua the way
-- Karen's is. A march at 112 BPM: a field snare with its flams and rolls,
-- timpani on the downbeats and a brass section of detuned saws. The snares
-- call everyone to the boats alone at first, then the horns give the
-- fanfare in D major; the middle turns to D minor under the guns, low brass
-- stabbing eighths while the trumpets hold on, and a long roll brings the
-- fanfare back once more, harmonised a third below, for the hill. ~60 s,
-- loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 112
local STEP = 60 / BPM / 4 -- a sixteenth
local SQUEEZE = 3 -- how hard the peaks (the snare, the timpani) are squeezed at the end: as loud as the others
local BAR = STEP * 16

-- The snare a bar at a time, sixteenth steps: x a hit, X an accent, f a
-- flam (a grace note just ahead), r a roll (two thirty-seconds), - nothing.
local CADENCE = {
  call = { "X--x-xx-X--x-xx-", "X--x-xx-X-x-rrrr" },
  march = { "X---f---X--x-x--", "X---f---X-xxrrrr" },
  roll = { "rrrrrrrrrrrrrrrr", "XrrrXrrrXrrrrrrr" },
}

local CHORD_TONES = { -- low to high
  D = { "D3", "F#3", "A3" },
  G = { "G2", "B2", "D3" },
  A = { "A2", "C#3", "E3" },
  Bm = { "B2", "D3", "F#3" },
  Dm = { "D3", "F3", "A3" },
  Bb = { "A#2", "D3", "F3" },
  C = { "C3", "E3", "G3" },
  Gm = { "G2", "A#2", "D3" },
}

-- The fanfare over D G D A Bm G A D: { note|false, sixteenths } a bar.
local FANFARE = {
  { { "A4", 3 }, { "A4", 1 }, { "D5", 4 }, { "F#5", 4 }, { "A5", 4 } },
  { { "B5", 6 }, { "A5", 2 }, { "G5", 4 }, { "B5", 4 } },
  { { "A5", 6 }, { "F#5", 2 }, { "D5", 4 }, { "F#5", 4 } },
  { { "E5", 12 }, { false, 4 } },
  { { "F#5", 3 }, { "F#5", 1 }, { "B5", 4 }, { "D6", 4 }, { "B5", 4 } },
  { { "G5", 6 }, { "A5", 2 }, { "B5", 4 }, { "G5", 4 } },
  { { "A5", 4 }, { "C#6", 4 }, { "E6", 4 }, { "C#6", 4 } },
  { { "D6", 12 }, { false, 4 } },
}
-- Under the guns the trumpets only hold on, over Dm Bb C A Dm Bb Gm A.
local HOLD = {
  { { "A5", 16 } },
  { { "A#5", 16 } },
  { { "G5", 16 } },
  { { "A5", 8 }, { "C#6", 8 } },
  { { "D6", 16 } },
  { { "D6", 8 }, { "F6", 8 } },
  { { "D6", 12 }, { "A#5", 4 } },
  { { "C#6", 8 }, { "E6", 8 } },
}

local D_MAJOR = { [2] = true, [4] = true, [6] = true, [7] = true, [9] = true, [11] = true, [1] = true }

local SECTIONS = {
  { chords = { "D", "D", "D", "A" }, snare = "call", timpani = true },
  { chords = { "D", "G", "D", "A", "Bm", "G", "A", "D" }, snare = "march", lead = FANFARE },
  { chords = { "Dm", "Bb", "C", "A", "Dm", "Bb", "Gm", "A" }, snare = "march", lead = HOLD, stabs = true,
    timpani = true, rollOut = true },
  { chords = { "D", "G", "D", "A", "Bm", "G", "A", "D" }, snare = "march", lead = FANFARE, harmony = true },
}

function Theme.duration()
  local bars = 0
  for _, s in ipairs(SECTIONS) do
    bars = bars + #s.chords
  end
  return bars * BAR
end

-- Voices ---------------------------------------------------------------------

--- The note a third below `m` in D major (two steps down the scale).
local function thirdBelow(m)
  local steps = 0
  repeat
    m = m - 1
    if D_MAJOR[m % 12] then
      steps = steps + 1
    end
  until steps == 2
  return m
end

--- One brass note: three saws a little apart, slow to speak and swelling.
local function horn(buf, t, dur, m, amp)
  local f = Synth.midiFreq(m)
  for _, cents in ipairs({ -8, 0, 8 }) do
    buf:tone(t, dur, f, {
      wave = "saw", amp = amp, detune = cents, attack = 0.035, decay = 1.5, sustain = 0.75, release = 0.08,
      vibRate = 5, vibDepth = dur > 0.5 and 0.12 or 0,
    })
  end
end

local function snareBar(buf, t, pattern, amp)
  for i = 1, 16 do
    local at = t + (i - 1) * STEP
    local c = pattern:sub(i, i)
    if c == "x" then
      buf:snare(at, amp * 0.7)
    elseif c == "X" then
      buf:snare(at, amp)
    elseif c == "f" then
      buf:snare(at - 0.025, amp * 0.35)
      buf:snare(at, amp)
    elseif c == "r" then
      buf:snare(at, amp * 0.45)
      buf:snare(at + STEP / 2, amp * 0.4)
    end
  end
end

local function timpani(buf, t, note, amp)
  local f = Synth.freq(note)
  buf:sweep(t, 0.9, f * 1.06, f, { amp = amp, decay = 0.35 })
  buf:noiseBurst(t, 0.03, { amp = amp * 0.3, decay = 0.01 })
end

--- The band behind the tune: bass drum and a bass on the march's one and
--- three (root, then fifth), chords on two and four.
local function marchBar(brass, low, drums, t, chord, stabs)
  local tones = CHORD_TONES[chord]
  local root = Synth.midi(tones[1])
  drums:kick(t, 0.8)
  drums:kick(t + STEP * 8, 0.7)
  low:tone(t, STEP * 7, Synth.midiFreq(root - 12), { wave = "tri", amp = 0.6, decay = 0.6, sustain = 0.4 })
  low:tone(t + STEP * 8, STEP * 7, Synth.midiFreq(root - 5), { wave = "tri", amp = 0.6, decay = 0.6, sustain = 0.4 })
  if stabs then
    for i = 0, 7 do -- staccato eighths in the low brass
      horn(brass, t + i * STEP * 2, STEP * 1.1, root + (i == 7 and 7 or 0), 0.07)
    end
  else
    for _, beat in ipairs({ 4, 12 }) do
      for _, note in ipairs(tones) do
        horn(brass, t + beat * STEP, STEP * 2.5, Synth.midi(note) + 12, 0.04)
      end
    end
  end
end

-- Render ---------------------------------------------------------------------

--- Renders the whole song. Returns a SoundData.
function Theme.render()
  local total = Theme.duration()
  local trumpets = Synth.newBuffer(total + 0.5)
  local brass = Synth.newBuffer(total + 0.5)
  local low = Synth.newBuffer(total + 0.5)
  local drums = Synth.newBuffer(total + 0.5)

  local t = 0
  for _, s in ipairs(SECTIONS) do
    local cadence = CADENCE[s.snare]
    for b, chord in ipairs(s.chords) do
      local last = b == #s.chords
      local pattern = (s.rollOut and b > #s.chords - 2) and CADENCE.roll[b - #s.chords + 2] or cadence[2 - b % 2]
      snareBar(drums, t, pattern, s.lead and 0.55 or 0.7)
      if s.timpani and (b % 2 == 1 or last) then
        timpani(drums, t, CHORD_TONES[chord][1], 0.8)
      end
      if s.lead then
        marchBar(brass, low, drums, t, chord, s.stabs)
        local cursor = t
        for _, ev in ipairs(s.lead[b]) do
          local note, len = ev[1], ev[2]
          if note then
            local m = Synth.midi(note)
            horn(trumpets, cursor, len * STEP * 0.9, m, 0.1)
            if s.harmony then
              horn(trumpets, cursor, len * STEP * 0.9, thirdBelow(m), 0.065)
            end
          end
          cursor = cursor + len * STEP
        end
      elseif b >= 3 then -- the horns gathering under the call
        horn(brass, t, BAR * 0.95, Synth.midi(CHORD_TONES[chord][1]), 0.06)
        horn(brass, t, BAR * 0.95, Synth.midi(CHORD_TONES[chord][3]), 0.05)
      end
      if b == 1 then
        drums:hat(t, 0.5, true) -- a cymbal clash to open each part
      end
      t = t + BAR
    end
  end

  trumpets:drive(1.6)
  trumpets:lowpass(2600)
  brass:drive(1.4)
  brass:lowpass(1500)
  low:lowpass(400)
  drums:highpass(40)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  trumpets:mixInto(master, 0.5)
  brass:mixInto(master, 0.45)
  low:mixInto(master, 0.5)
  drums:mixInto(master, 0.8)
  master:drive(SQUEEZE / math.max(master:peak(), 1e-6))
  return master:toSoundData(0.9)
end

return Theme
