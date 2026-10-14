-- The Market's theme (init.lua plays it from the moment the Market wakes,
-- a player walking up out of the tunnel), rendered by src/audio/synth.lua
-- the way the Drop's chase theme is. Heavy metal, thrash-fast: it opens on
-- one low E ringing out with a pinch squeal over it and the drums rolling
-- in; then a palm-muted gallop on the low E with chromatic stabs (F, G,
-- F#, and the tritone, A#), a tremolo-picked riff crawling round the E over
-- a thrash beat, a chorus of open chords (E minor, C, D, B) over double
-- kick under a twin lead harmonised in thirds, a half-time breakdown of
-- chugs and silence, and the gallop again into the top. 170 BPM in E
-- minor (Phrygian at the bottom), ~48 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 170
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- The gallop, a bar at a time: four beats, each a note on the low string
-- played as an eighth and two sixteenths (palm-muted), or { note, sixteenths }
-- rung out open.
local GALLOP = {
  { "E2", "E2", "E2", "E2" },
  { "E2", "E2", "E2", { "F2", 4 } },
  { "E2", "E2", "E2", "E2" },
  { "E2", "E2", { "G2", 2, "F#2", 2 }, { "F2", 4 } },
  { "E2", "E2", "E2", "E2" },
  { "E2", "E2", "E2", { "F2", 4 } },
  { "E2", "E2", "E2", "E2" },
  { "E2", "E2", { "A#2", 4 }, { "A2", 4 } },
}

-- The tremolo riff: a bar of four notes, each picked in four sixteenths.
local TREMOLO = {
  { "E2", "F2", "E2", "G2" },
  { "E2", "F#2", "E2", "D2" },
  { "E2", "F2", "E2", "G2" },
  { "E2", "A#2", "A2", "G2" },
}

-- The chorus: a chord a bar, rung on every beat with a push on the "and" of three.
local CHORUS = { "E2", "C3", "D3", "B2" }

-- The twin lead over the chorus: eight bars of { note|false, sixteenths }.
local LEAD = {
  { { "B4", 4 }, { "E5", 4 }, { "G5", 4 }, { "F#5", 4 } },
  { { "E5", 6 }, { "D5", 2 }, { "C5", 4 }, { "B4", 4 } },
  { { "A4", 4 }, { "D5", 4 }, { "F#5", 4 }, { "A5", 4 } },
  { { "G5", 6 }, { "F#5", 2 }, { "D#5", 8 } },
  { { "B5", 4 }, { "A5", 2 }, { "G5", 2 }, { "F#5", 4 }, { "E5", 4 } },
  { { "G5", 4 }, { "E5", 4 }, { "C5", 4 }, { "E5", 4 } },
  { { "F#5", 4 }, { "A5", 4 }, { "D6", 4 }, { "C6", 2 }, { "A5", 2 } },
  { { "B5", 12 }, { false, 4 } },
}

-- The breakdown: chugs (x) and silence (-), half-time.
local BREAKDOWN = { "x--x--x---x-x---", "x--x--x---x-xxxx", "x--x--x---x-x---", "x-x-x-x-xxxxxxxx" }

local SECTIONS = {
  { bars = 2, kind = "intro" },
  { bars = 8, kind = "gallop" },
  { bars = 8, kind = "tremolo" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "breakdown" },
  { bars = 4, kind = "gallop", last = true },
}

-- E minor's notes, for the harmony a third under the lead.
local SCALE = { [4] = true, [6] = true, [7] = true, [9] = true, [11] = true, [0] = true, [2] = true }

--- The note a diatonic third under `note` (a MIDI number) in E minor.
local function thirdUnder(m)
  local steps, k = 0, m
  while steps < 2 do
    k = k - 1
    if SCALE[k % 12] then
      steps = steps + 1
    end
  end
  return k
end

-- Voices ------------------------------------------------------------------------

--- A power chord on `root` (root, fifth, octave), detuned wide. Muted: a
--- short thump for the chugs; open: rung out.
local function powerChord(buf, t, dur, root, muted)
  local f = freq(root)
  local o = muted and { amp = 0.34, decay = 0.045, sustain = 0 } or { amp = 0.26, decay = 0.7, sustain = 0.55 }
  o.wave = "saw"
  for _, d in ipairs({ -12, 12 }) do
    o.detune = d
    buf:tone(t, dur, f, o)
    buf:tone(t, dur, f * 1.5, o)
  end
  o.detune = 0
  o.amp = o.amp * 0.6
  buf:tone(t, dur, f * 2, o)
  buf:tone(t, dur, f / 2, o) -- the low string under it, down-tuned weight
end

local function bassNote(buf, t, dur, root, muted)
  buf:tone(t, dur, freq(root) / 2, { wave = "square", amp = 0.5, decay = muted and 0.08 or 0.5,
    sustain = muted and 0 or 0.6 })
end

--- A pinch harmonic: a squeal high over the chord, bent up and shaking.
local function squeal(buf, t, dur, note)
  buf:sweep(t, 0.08, freq(note) * 0.9, freq(note), { wave = "square", amp = 0.18, decay = 99 })
  buf:tone(t + 0.08, dur, freq(note), { wave = "square", amp = 0.18, attack = 0.002, decay = 1.2, sustain = 0.5,
    vibRate = 7, vibDepth = 0.6 })
end

--- One note of the twin lead: the melody, and the harmony a third under it.
local function leadNote(buf, t, dur, note)
  local m = Synth.midi(note)
  local long = dur > SIXTEENTH * 5
  for _, mm in ipairs({ m, thirdUnder(m) }) do
    local f = Synth.midiFreq(mm)
    buf:tone(t, dur * 0.95, f, { wave = "saw", amp = 0.13, attack = 0.008, decay = 0.8, sustain = 0.75,
      release = 0.05, vibRate = 6, vibDepth = long and 0.35 or 0.06, detune = mm == m and 0 or -6 })
    buf:tone(t, dur * 0.95, f, { wave = "square", amp = 0.06, attack = 0.008, decay = 0.8, sustain = 0.75,
      release = 0.05, detune = 7 })
  end
end

local function drumBar(buf, t, style, fill)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 8 then
      buf:snare(ti, 0.45 + (i - 8) * 0.07) -- the roll into what comes next
      if i % 2 == 0 then
        buf:kick(ti, 0.9)
      end
    elseif style == "gallop" then -- the kicks ride the gallop
      if i % 4 ~= 1 then
        buf:kick(ti, i % 4 == 0 and 1 or 0.75)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.25, true)
      end
    elseif style == "thrash" then -- kick on the beat, snare on the off-beat
      if i % 4 == 0 then
        buf:kick(ti, 1)
      elseif i % 4 == 2 then
        buf:snare(ti, 0.85)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.22)
      end
    elseif style == "double" then -- double kick under everything
      buf:kick(ti, i % 4 == 0 and 0.95 or 0.65)
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.24, i % 4 == 2)
      end
    elseif style == "half" then
      if i == 0 or i == 3 or i == 10 then
        buf:kick(ti, 1)
      end
      if i == 8 then
        buf:snare(ti, 1)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.32, true)
      end
    end
  end
end

-- Render ----------------------------------------------------------------------

function Theme.duration()
  local bars = 0
  for _, s in ipairs(SECTIONS) do
    bars = bars + s.bars
  end
  return bars * BAR
end

--- Renders the whole loop. Returns a SoundData.
function Theme.render()
  local total = Theme.duration()
  local rhythm = Synth.newBuffer(total + 1) -- open chords
  local chug = Synth.newBuffer(total + 1) -- palm-muted, darker
  local bass = Synth.newBuffer(total + 1)
  local lead = Synth.newBuffer(total + 1)
  local drums = Synth.newBuffer(total + 1)
  local fx = Synth.newBuffer(total + 1)

  local function mute(ti, len, note)
    powerChord(chug, ti, len, note, true)
    bassNote(bass, ti, len, note, true)
  end
  local function ring(ti, len, note)
    powerChord(rhythm, ti, len, note, false)
    bassNote(bass, ti, len, note, false)
  end

  local t = 0
  for _, s in ipairs(SECTIONS) do
    for b = 1, s.bars do
      local last = b == s.bars
      if s.kind == "intro" then
        if b == 1 then -- one low E rung out, a squeal over it, feedback rising
          ring(t, BAR * 0.95, "E2")
          squeal(fx, t + SIXTEENTH * 2, BAR * 0.7, "B5")
          fx:sweep(t, BAR * 2, 120, 1400, { wave = "saw", amp = 0.08, decay = 99 })
          drums:hat(t, 0.6, true)
          drums:kick(t, 1)
        else -- chugs on the eighths, the drums rolling in
          for e = 0, 7 do
            mute(t + e * 2 * SIXTEENTH, SIXTEENTH * 1.6, "E2")
          end
          drumBar(drums, t, "gallop", true)
        end
      elseif s.kind == "gallop" then
        local bar = GALLOP[(b - 1) % #GALLOP + 1]
        if s.last and b == s.bars then
          bar = GALLOP[8]
        end
        for beat, n in ipairs(bar) do
          local tb = t + (beat - 1) * 4 * SIXTEENTH
          if type(n) == "string" then
            mute(tb, SIXTEENTH * 1.7, n)
            mute(tb + 2 * SIXTEENTH, SIXTEENTH * 0.85, n)
            mute(tb + 3 * SIXTEENTH, SIXTEENTH * 0.85, n)
          else
            local off = 0
            for k = 1, #n, 2 do
              ring(tb + off * SIXTEENTH, n[k + 1] * SIXTEENTH * 0.97, n[k])
              off = off + n[k + 1]
            end
          end
        end
        drumBar(drums, t, "gallop", last)
        if b == 1 then
          drums:hat(t, 0.6, true) -- a crash on the way in
        end
      elseif s.kind == "tremolo" then
        local bar = TREMOLO[(b - 1) % #TREMOLO + 1]
        for beat, note in ipairs(bar) do
          for k = 0, 3 do
            local ti = t + ((beat - 1) * 4 + k) * SIXTEENTH
            powerChord(chug, ti, SIXTEENTH * 0.9, note, true)
          end
          bassNote(bass, t + (beat - 1) * 4 * SIXTEENTH, 4 * SIXTEENTH * 0.95, note, false)
        end
        drumBar(drums, t, "thrash", last)
        if b == 1 or b == 5 then
          drums:hat(t, 0.6, true)
        end
      elseif s.kind == "chorus" then
        local root = CHORUS[(b - 1) % #CHORUS + 1]
        for _, h in ipairs({ { 0, 4 }, { 4, 4 }, { 8, 2 }, { 10, 2 }, { 12, 4 } }) do
          ring(t + h[1] * SIXTEENTH, h[2] * SIXTEENTH * 0.95, root)
        end
        local cursor = t
        for _, n in ipairs(LEAD[b]) do
          if n[1] then
            leadNote(lead, cursor, n[2] * SIXTEENTH, n[1])
          end
          cursor = cursor + n[2] * SIXTEENTH
        end
        drumBar(drums, t, "double", last)
        if b % 2 == 1 then
          drums:hat(t, 0.6, true)
        end
      else -- the breakdown
        local pattern = BREAKDOWN[b]
        for i = 1, 16 do
          if pattern:sub(i, i) == "x" then
            mute(t + (i - 1) * SIXTEENTH, SIXTEENTH * 0.9, "E2")
            drums:kick(t + (i - 1) * SIXTEENTH, 0.9)
          end
        end
        drumBar(drums, t, "half", false)
        if b == 1 then
          drums:hat(t, 0.7, true)
          squeal(fx, t, BAR * 0.5, "E6")
        end
        if last then
          fx:sweep(t, BAR, 160, 1800, { wave = "saw", amp = 0.09, decay = 99 })
        end
      end
      t = t + BAR
    end
  end

  rhythm:drive(12)
  rhythm:lowpass(3200)
  chug:drive(10)
  chug:lowpass(1900)
  bass:drive(3)
  bass:lowpass(600)
  lead:drive(3)
  lead:lowpass(5200)
  fx:drive(4)
  fx:lowpass(4500)
  drums:drive(1.5)
  drums:highpass(30)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  rhythm:mixInto(master, 0.42)
  chug:mixInto(master, 0.55)
  bass:mixInto(master, 0.45)
  lead:mixInto(master, 0.34)
  fx:mixInto(master, 0.22)
  drums:mixInto(master, 0.8)
  return master:toSoundData(0.9)
end

return Theme
