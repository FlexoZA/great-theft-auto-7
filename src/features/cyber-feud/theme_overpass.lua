-- The Overpass's theme (init.lua plays it from the moment Kilowatt's rig
-- roars past), rendered by src/audio/synth.lua the way the other levels'
-- themes are. Darksynth, a night drive: it opens on a pad and an arpeggio
-- alone with a riser under them; then a rolling octave bass in sixteenths
-- under a four-on-the-floor kick and a big gated snare, the arpeggio
-- running over a chord a bar (D minor, B flat, F, C); a chorus with a
-- detuned saw lead on top; a break where the kick drops out and the lead
-- echoes over the pad; and the chorus again with the lead an octave up.
-- 124 BPM in D minor, ~58 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 124
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- The chords a bar at a time: their notes for the pad, and the bass's root.
local CHORDS = {
  { root = "D2", pad = { "D3", "F3", "A3", "D4" }, arp = { "D4", "F4", "A4", "D5" } },
  { root = "A#1", pad = { "A#2", "D3", "F3", "A#3" }, arp = { "A#3", "D4", "F4", "A#4" } },
  { root = "F2", pad = { "F3", "A3", "C4", "F4" }, arp = { "F4", "A4", "C5", "F5" } },
  { root = "C2", pad = { "C3", "E3", "G3", "C4" }, arp = { "C4", "E4", "G4", "C5" } },
}
local ARP_STEPS = { 1, 2, 3, 4, 3, 2, 1, 2, 3, 4, 3, 4, 3, 2, 3, 4 }

-- The lead over the chorus: eight bars of { note|false, sixteenths }.
local LEAD = {
  { { "A4", 4 }, { "D5", 4 }, { "F5", 4 }, { "E5", 4 } },
  { { "D5", 6 }, { "C5", 2 }, { "A#4", 4 }, { "A4", 4 } },
  { { "C5", 4 }, { "F5", 4 }, { "A5", 4 }, { "G5", 4 } },
  { { "E5", 8 }, { "D5", 4 }, { "C5", 4 } },
  { { "A5", 4 }, { "G5", 2 }, { "F5", 2 }, { "E5", 4 }, { "D5", 4 } },
  { { "F5", 4 }, { "D5", 4 }, { "A#4", 4 }, { "D5", 4 } },
  { { "C5", 4 }, { "F5", 4 }, { "G5", 4 }, { "A5", 4 } },
  { { "E5", 12 }, { false, 4 } },
}

local SECTIONS = {
  { bars = 2, kind = "intro" },
  { bars = 8, kind = "drive" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "break" },
  { bars = 8, kind = "chorus", high = true },
}

-- Voices ------------------------------------------------------------------------

--- A chord held for `dur`: detuned saws, soft in and out.
local function pad(buf, t, dur, notes, amp)
  for _, n in ipairs(notes) do
    for _, d in ipairs({ -10, 0, 10 }) do
      buf:tone(t, dur, freq(n), { wave = "saw", amp = amp, attack = 0.25, decay = 99, sustain = 1, release = 0.3,
        detune = d })
    end
  end
end

--- The rolling bass: the root and its octave in turn, every sixteenth.
local function bassBar(buf, t, root)
  for i = 0, 15 do
    local f = freq(root) * (i % 2 == 1 and 2 or 1)
    buf:tone(t + i * SIXTEENTH, SIXTEENTH * 0.85, f, { wave = "saw", amp = 0.42, attack = 0.003, decay = 0.09,
      sustain = 0.25, release = 0.02 })
  end
end

local function arpBar(buf, t, notes, amp)
  for i, step in ipairs(ARP_STEPS) do
    buf:tone(t + (i - 1) * SIXTEENTH, SIXTEENTH * 0.7, freq(notes[step]), { wave = "square", amp = amp,
      attack = 0.002, decay = 0.06, sustain = 0.15, release = 0.03 })
  end
end

local function leadNote(buf, t, dur, note, up)
  local f = freq(note, up and 12 or 0)
  local long = dur > SIXTEENTH * 5
  for _, d in ipairs({ -12, 12 }) do
    buf:tone(t, dur * 0.96, f, { wave = "saw", amp = 0.14, attack = 0.015, decay = 0.9, sustain = 0.8,
      release = 0.08, detune = d, vibRate = 5.5, vibDepth = long and 0.25 or 0.04 })
  end
  buf:tone(t, dur * 0.96, f / 2, { wave = "square", amp = 0.05, attack = 0.015, decay = 0.9, sustain = 0.8,
    release = 0.08 })
end

--- The big snare of the eighties: the hit, and a burst of noise cut off short (the gate).
local function gatedSnare(buf, t, amp)
  buf:snare(t, amp)
  buf:noiseBurst(t, 0.22, { amp = amp * 0.55, decay = 0.5 })
end

local function drumBar(buf, verb, t, style, fill)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      gatedSnare(buf, ti, 0.4 + (i - 12) * 0.12) -- a roll into what comes next
    elseif style == "four" then
      if i % 4 == 0 then
        buf:kick(ti, 1)
      end
      if i == 4 or i == 12 then
        gatedSnare(buf, ti, 0.9)
        gatedSnare(verb, ti, 0.9)
      end
      buf:hat(ti, i % 4 == 2 and 0.28 or 0.14, i % 4 == 2)
    elseif style == "break" then
      if i == 4 or i == 12 then
        gatedSnare(buf, ti, 0.6)
        gatedSnare(verb, ti, 0.8)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.12)
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
  local pads = Synth.newBuffer(total + 1)
  local bass = Synth.newBuffer(total + 1)
  local arp = Synth.newBuffer(total + 1)
  local lead = Synth.newBuffer(total + 1)
  local drums = Synth.newBuffer(total + 1)
  local verb = Synth.newBuffer(total + 1) -- the snare's room, darker and longer
  local fx = Synth.newBuffer(total + 1)

  local t = 0
  for _, s in ipairs(SECTIONS) do
    for b = 1, s.bars do
      local chord = CHORDS[(b - 1) % #CHORDS + 1]
      local last = b == s.bars
      if s.kind == "intro" then
        pad(pads, t, BAR, chord.pad, 0.05)
        arpBar(arp, t, chord.arp, 0.05 + b * 0.03)
        if b == 1 then
          fx:sweep(t, BAR * 2, 140, 2000, { wave = "saw", amp = 0.1, decay = 99 })
        else
          drumBar(drums, verb, t, "break", true)
        end
      elseif s.kind == "drive" then
        pad(pads, t, BAR, chord.pad, 0.035)
        bassBar(bass, t, chord.root)
        arpBar(arp, t, chord.arp, 0.09)
        drumBar(drums, verb, t, "four", last)
        if b == 1 then
          drums:hat(t, 0.5, true) -- a crash on the way in
        end
      elseif s.kind == "chorus" then
        pad(pads, t, BAR, chord.pad, 0.05)
        bassBar(bass, t, chord.root)
        arpBar(arp, t, chord.arp, 0.06)
        local cursor = t
        for _, n in ipairs(LEAD[b]) do
          if n[1] then
            leadNote(lead, cursor, n[2] * SIXTEENTH, n[1], s.high)
          end
          cursor = cursor + n[2] * SIXTEENTH
        end
        drumBar(drums, verb, t, "four", last and not s.high)
        if b % 4 == 1 then
          drums:hat(t, 0.55, true)
        end
      else -- the break: no kick, the pad up, the lead's last line echoing
        pad(pads, t, BAR, chord.pad, 0.07)
        arpBar(arp, t, chord.arp, 0.11)
        local cursor = t
        for _, n in ipairs(LEAD[b + 4]) do
          if n[1] then
            leadNote(lead, cursor, n[2] * SIXTEENTH, n[1], false)
            leadNote(lead, cursor + SIXTEENTH * 3, n[2] * SIXTEENTH, n[1], false) -- the echo
          end
          cursor = cursor + n[2] * SIXTEENTH
        end
        drumBar(drums, verb, t, "break", last)
        if last then
          fx:sweep(t, BAR, 160, 2200, { wave = "saw", amp = 0.09, decay = 99 })
        end
      end
      t = t + BAR
    end
  end

  pads:lowpass(2200)
  bass:drive(2)
  bass:lowpass(900)
  arp:lowpass(4200)
  lead:drive(1.6)
  lead:lowpass(4800)
  drums:drive(1.3)
  drums:highpass(30)
  verb:lowpass(1800)
  verb:lowpass(1400)
  fx:lowpass(3000)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  pads:mixInto(master, 0.55)
  bass:mixInto(master, 0.5)
  arp:mixInto(master, 0.42)
  lead:mixInto(master, 0.4)
  drums:mixInto(master, 0.75)
  verb:mixInto(master, 0.3)
  fx:mixInto(master, 0.25)
  -- Squeeze the drum peaks (a soft clip that takes the loudest to ~0.9) so
  -- it plays as loud as the other levels' themes.
  master:drive(1.6 / math.max(master:peak(), 1e-6))
  return master:toSoundData(0.9)
end

return Theme
