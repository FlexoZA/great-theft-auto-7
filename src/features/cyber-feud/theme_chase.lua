-- The Drop's chase theme (init.lua plays it from the moment someone takes
-- the Shard), rendered by src/audio/synth.lua the way A-Man's themes are.
-- Driving rock with neon on it: it opens on a synth arpeggio alone with a
-- riser under it, the pickup's sting, and a snare roll in; then a
-- palm-muted riff on the low A with power-chord stabs, a chorus of open
-- chords (A minor, F, C, G) on every eighth under a square-wave lead, a
-- half-time break where the arpeggio comes forward and the guitar only
-- hits the downbeats, and the chorus once more with the lead an octave up.
-- The arpeggio runs in sixteenths through all of it. 150 BPM in A minor,
-- ~48 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 150
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- The verse riff, a bar at a time: sixteenth steps. `x` a palm-muted chug on
-- the low A, `-` nothing, and { step, root, sixteenths } a power chord rung out.
local VERSE = {
  { chugs = "x-xx-xx-x-xx-x--", chords = { { 14, "C3", 2 } } },
  { chugs = "x-xx-xx-x-xx----", chords = { { 12, "D3", 2 }, { 14, "E3", 2 } } },
  { chugs = "x-xx-xx-x-xx-x--", chords = { { 14, "G2", 2 } } },
  { chugs = "x-xx-xx---------", chords = { { 8, "F2", 4 }, { 12, "G2", 4 } } },
}

-- The chorus: a chord a bar, rung on every eighth.
local CHORUS = { "A2", "F2", "C3", "G2" }

-- The lead over the chorus: four bars of { note|false, sixteenths }.
local LEAD = {
  { { "E5", 4 }, { "D5", 2 }, { "C5", 2 }, { "A4", 4 }, { "C5", 4 } },
  { { "D5", 6 }, { "C5", 2 }, { "A4", 8 } },
  { { "G5", 4 }, { "E5", 4 }, { "C5", 4 }, { "D5", 4 } },
  { { "E5", 8 }, { "D5", 4 }, { "B4", 4 } },
}

-- The arpeggio's chord a bar: four notes, played up and back in sixteenths.
local ARP = {
  Am = { "A3", "C4", "E4", "A4" },
  F = { "F3", "A3", "C4", "F4" },
  C = { "C4", "E4", "G4", "C5" },
  G = { "G3", "B3", "D4", "G4" },
}
local ARP_VERSE = { "Am", "Am", "Am", "F" }
local ARP_CHORUS = { "Am", "F", "C", "G" }
local ARP_STEPS = { 1, 2, 3, 4, 3, 2, 3, 4, 1, 2, 3, 4, 3, 4, 3, 2 }

-- Arrangement -----------------------------------------------------------------

local SECTIONS = {
  { bars = 2, kind = "intro" },
  { bars = 8, kind = "verse" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "break" },
  { bars = 8, kind = "chorus", high = true },
}

-- Voices ------------------------------------------------------------------------

local function powerChord(buf, t, dur, root, muted)
  local f = freq(root)
  local o = muted and { amp = 0.32, decay = 0.05, sustain = 0 } or { amp = 0.26, decay = 0.5, sustain = 0.45 }
  o.wave = "saw"
  for _, d in ipairs({ -8, 8 }) do
    o.detune = d
    buf:tone(t, dur, f, o)
  end
  o.detune = 0
  buf:tone(t, dur, f * 1.5, o)
  o.amp = o.amp * 0.5
  buf:tone(t, dur, f * 2, o)
end

local function bassNote(buf, t, dur, root, muted)
  buf:tone(t, dur, freq(root) / 2, { wave = "square", amp = 0.5, decay = muted and 0.1 or 0.4,
    sustain = muted and 0 or 0.5 })
end

local function leadNote(buf, t, dur, note, up)
  local f = freq(note, up and 12 or 0)
  buf:tone(t, dur * 0.95, f, { wave = "square", amp = 0.2, attack = 0.01, decay = 0.6, sustain = 0.7,
    release = 0.05, vibRate = 5.5, vibDepth = dur > SIXTEENTH * 3 and 0.25 or 0.05 })
  buf:tone(t, dur * 0.95, f, { wave = "saw", amp = 0.1, attack = 0.01, decay = 0.6, sustain = 0.7,
    release = 0.05, detune = 9 })
end

--- One bar of the arpeggio over `chord`, at `amp`.
local function arpBar(buf, t, chord, amp)
  local notes = ARP[chord]
  for i, step in ipairs(ARP_STEPS) do
    buf:tone(t + (i - 1) * SIXTEENTH, SIXTEENTH * 0.8, freq(notes[step], 12), { wave = "square", amp = amp,
      attack = 0.002, decay = 0.07, sustain = 0.1, release = 0.02 })
  end
end

local function drumBar(buf, t, style, fill)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 8 then
      buf:snare(ti, 0.4 + (i - 8) * 0.07) -- the roll into the next section
    elseif style == "drive" then
      if i == 0 or i == 7 or i == 8 or i == 10 then
        buf:kick(ti, 1)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 0.95)
      end
      if i % 2 == 0 then
        buf:hat(ti, i % 4 == 2 and 0.3 or 0.2)
      end
    elseif style == "chorus" then
      if i % 4 == 0 or i == 10 then
        buf:kick(ti, 1)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.26, i % 4 == 2)
      end
    elseif style == "half" then
      if i == 0 or i == 6 or i == 10 then
        buf:kick(ti, 1)
      end
      if i == 8 then
        buf:snare(ti, 1)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.3, true)
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
  local guitar = Synth.newBuffer(total + 0.5)
  local bass = Synth.newBuffer(total + 0.5)
  local lead = Synth.newBuffer(total + 0.5)
  local synth = Synth.newBuffer(total + 0.5)
  local drums = Synth.newBuffer(total + 0.5)
  local fx = Synth.newBuffer(total + 0.5)

  local t = 0
  for _, s in ipairs(SECTIONS) do
    for b = 1, s.bars do
      local phrase = (b - 1) % 4 + 1
      local last = b == s.bars
      if s.kind == "intro" then
        -- The sting: the arpeggio alone, a riser under it, the roll in.
        arpBar(synth, t, "Am", b == 1 and 0.16 or 0.2)
        if b == 1 then
          fx:sweep(t, BAR * 2, 180, 1600, { wave = "saw", amp = 0.12, decay = 99 })
          bassNote(bass, t, BAR * 2, "A2", false)
        else
          drumBar(drums, t, "drive", true)
        end
      elseif s.kind == "verse" then
        local v = VERSE[phrase]
        for i = 1, 16 do
          if v.chugs:sub(i, i) == "x" then
            local ti = t + (i - 1) * SIXTEENTH
            powerChord(guitar, ti, SIXTEENTH * 0.85, "A2", true)
            bassNote(bass, ti, SIXTEENTH * 0.8, "A2", true)
          end
        end
        for _, c in ipairs(v.chords) do
          local ti = t + c[1] * SIXTEENTH
          powerChord(guitar, ti, c[3] * SIXTEENTH * 0.98, c[2], false)
          bassNote(bass, ti, c[3] * SIXTEENTH * 0.98, c[2], false)
        end
        arpBar(synth, t, ARP_VERSE[phrase], 0.08)
        drumBar(drums, t, "drive", last)
      elseif s.kind == "chorus" then
        local root = CHORUS[phrase]
        for e = 0, 7 do
          local ti = t + e * 2 * SIXTEENTH
          powerChord(guitar, ti, SIXTEENTH * 1.9, root, false)
          bassNote(bass, ti, SIXTEENTH * 1.8, root, false)
        end
        local cursor = t
        for _, n in ipairs(LEAD[phrase]) do
          if n[1] then
            leadNote(lead, cursor, n[2] * SIXTEENTH, n[1], s.high)
          end
          cursor = cursor + n[2] * SIXTEENTH
        end
        arpBar(synth, t, ARP_CHORUS[phrase], 0.07)
        drumBar(drums, t, "chorus", last and not s.high)
        if phrase == 1 then
          drums:hat(t, 0.55, true) -- a crash on each time round
        end
      else -- the break
        local root = CHORUS[phrase]
        powerChord(guitar, t, BAR * 0.45, root, false)
        bassNote(bass, t, BAR * 0.9, root, false)
        arpBar(synth, t, ARP_CHORUS[phrase], 0.17)
        drumBar(drums, t, "half", last)
        if last then
          fx:sweep(t, BAR, 220, 1800, { wave = "saw", amp = 0.1, decay = 99 })
        end
      end
      t = t + BAR
    end
  end

  guitar:drive(7)
  guitar:lowpass(3400)
  bass:drive(2.5)
  bass:lowpass(700)
  lead:drive(2)
  lead:lowpass(5000)
  synth:lowpass(5200)
  drums:drive(1.4)
  drums:highpass(30)
  fx:lowpass(3000)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  guitar:mixInto(master, 0.48)
  bass:mixInto(master, 0.45)
  lead:mixInto(master, 0.32)
  synth:mixInto(master, 0.4)
  drums:mixInto(master, 0.75)
  fx:mixInto(master, 0.3)
  return master:toSoundData(0.9)
end

return Theme
