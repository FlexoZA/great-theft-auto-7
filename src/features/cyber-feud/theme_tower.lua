-- Halcyon Tower's theme (init.lua plays it from the moment the tower wakes,
-- a player walking past the reception), rendered by src/audio/synth.lua the
-- way the other levels' themes are. Metal again, but not the Market's
-- thrash: industrial groove metal, slower, heavier, tuned down low. It
-- opens on a bar of Halcyon's lobby muzak (an electric piano, a vibraphone,
-- brushes) that VEX cuts off with a tape-stop glitch; then a syncopated
-- groove of low C# chugs with the kick locked to them and the snare on
-- three, high synth stabs between; an industrial march (four on the floor,
-- an anvil on the off-beats) with the riff leaning on D and G, the flat
-- second and the tritone; a chorus of open chords (C# minor, A, E, B) over
-- double kick under a lead, a cold square arpeggio running through it; a
-- half-time breakdown that ends on the lift's chime; and the groove again
-- into the top. 132 BPM in C# minor, ~60 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 132
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- The groove: a bar of sixteenths, `x` a chug on the low C#, `o` the bar's
-- `ring` note rung out, `-` silence.
local GROOVE = {
  { "x-xx-x-xx-x-x-xx" },
  { "x-xx-x-xx-x-o---", ring = "D2" },
  { "x-xx-x-xx-x-x-xx" },
  { "x-x-xx-x-xxxo---", ring = "G2" },
}

-- The march: eighths, a note each.
local MARCH = {
  { "C#2", "C#2", "D2", "C#2", "C#2", "C#2", "E2", "D2" },
  { "C#2", "C#2", "D2", "C#2", "C#2", "C#2", "G2", "F#2" },
}

-- The chorus: a chord a bar, and the arpeggio's notes over it.
local CHORUS = {
  { root = "C#2", arp = { "C#4", "G#4", "C#5", "E5" } },
  { root = "A1", arp = { "A3", "E4", "A4", "C#5" } },
  { root = "E2", arp = { "E4", "B4", "E5", "G#5" } },
  { root = "B1", arp = { "B3", "F#4", "B4", "D#5" } },
}
local ARP_STEPS = { 1, 2, 3, 4, 3, 2, 3, 4, 1, 2, 3, 4, 3, 4, 3, 2 }

-- The lead over the chorus: eight bars of { note|false, sixteenths }.
local LEAD = {
  { { "G#4", 4 }, { "C#5", 4 }, { "E5", 4 }, { "D#5", 4 } },
  { { "C#5", 6 }, { "B4", 2 }, { "A4", 8 } },
  { { "B4", 4 }, { "E5", 4 }, { "G#5", 4 }, { "F#5", 4 } },
  { { "F#5", 8 }, { "E5", 4 }, { "D#5", 4 } },
  { { "G#5", 4 }, { "F#5", 2 }, { "E5", 2 }, { "D#5", 4 }, { "C#5", 4 } },
  { { "E5", 4 }, { "C#5", 4 }, { "A4", 4 }, { "C#5", 4 } },
  { { "D#5", 4 }, { "F#5", 4 }, { "B5", 4 }, { "A5", 2 }, { "G#5", 2 } },
  { { "G#5", 12 }, { false, 4 } },
}

-- The breakdown: chugs (x) and silence (-), half-time.
local BREAKDOWN = { "x---x--x---x----", "x---x--x---x-x-x", "x---x--x---x----", "x-x-x-x-xxxxxxxx" }

local SECTIONS = {
  { bars = 1, kind = "muzak" },
  { bars = 8, kind = "groove" },
  { bars = 8, kind = "march" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "breakdown" },
  { bars = 4, kind = "groove", last = true },
}

-- Voices ------------------------------------------------------------------------

--- A power chord on `root` (root, fifth, octave), detuned wide, with the
--- low string an octave under it. Muted: a short thump; open: rung out.
local function powerChord(buf, t, dur, root, muted)
  local f = freq(root)
  local o = muted and { amp = 0.36, decay = 0.05, sustain = 0 } or { amp = 0.26, decay = 0.8, sustain = 0.6 }
  o.wave = "saw"
  for _, d in ipairs({ -14, 14 }) do
    o.detune = d
    buf:tone(t, dur, f, o)
    buf:tone(t, dur, f * 1.5, o)
  end
  o.detune = 0
  o.amp = o.amp * 0.7
  buf:tone(t, dur, f / 2, o) -- tuned way down
  o.amp = o.amp * 0.6
  buf:tone(t, dur, f * 2, o)
end

local function bassNote(buf, t, dur, root, muted)
  buf:tone(t, dur, freq(root) / 2, { wave = "square", amp = 0.55, decay = muted and 0.09 or 0.6,
    sustain = muted and 0 or 0.6 })
end

--- One note of the lead: a saw with its octave under it, singing on long notes.
local function leadNote(buf, t, dur, note)
  local f = freq(note)
  local long = dur > SIXTEENTH * 5
  for _, d in ipairs({ -8, 8 }) do
    buf:tone(t, dur * 0.95, f, { wave = "saw", amp = 0.13, attack = 0.01, decay = 0.8, sustain = 0.8,
      release = 0.05, detune = d, vibRate = 5.5, vibDepth = long and 0.35 or 0.05 })
  end
  buf:tone(t, dur * 0.95, f / 2, { wave = "square", amp = 0.06, attack = 0.01, decay = 0.8, sustain = 0.8,
    release = 0.05 })
end

local function arpBar(buf, t, notes, amp)
  for i, step in ipairs(ARP_STEPS) do
    buf:tone(t + (i - 1) * SIXTEENTH, SIXTEENTH * 0.6, freq(notes[step]), { wave = "square", amp = amp,
      attack = 0.002, decay = 0.05, sustain = 0.1, release = 0.02 })
  end
end

--- A high synth stab, cold and short.
local function stab(buf, t, note)
  for _, n in ipairs({ 0, 3, 7 }) do
    buf:tone(t, SIXTEENTH * 0.8, freq(note, n), { wave = "square", amp = 0.07, attack = 0.002, decay = 0.08,
      sustain = 0 })
  end
end

--- The anvil: a clank of metal, a burst of bright noise and two clashing tones.
local function anvil(buf, t, amp)
  buf:noiseBurst(t, 0.06, { amp = amp * 0.6, decay = 0.02 })
  buf:tone(t, 0.25, 1870, { wave = "square", amp = amp * 0.12, decay = 0.07, sustain = 0 })
  buf:tone(t, 0.25, 2633, { wave = "square", amp = amp * 0.09, decay = 0.05, sustain = 0 })
end

--- The lobby's electric piano: soft sines with a little bell on top.
local function epiano(buf, t, dur, notes)
  for _, n in ipairs(notes) do
    buf:tone(t, dur, freq(n), { wave = "sine", amp = 0.09, attack = 0.01, decay = 1.2, sustain = 0.4,
      release = 0.2, vibRate = 4.5, vibDepth = 0.08 })
    buf:tone(t, dur * 0.4, freq(n, 12), { wave = "sine", amp = 0.025, decay = 0.3, sustain = 0 })
  end
end

--- The lift's chime, ding-dong.
local function chime(buf, t)
  buf:tone(t, 0.9, freq("E6"), { wave = "sine", amp = 0.22, decay = 0.9, sustain = 0 })
  buf:tone(t + 0.32, 1.1, freq("C6"), { wave = "sine", amp = 0.22, decay = 1.1, sustain = 0 })
end

local function drumBar(buf, verb, t, style, fill, pattern)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      buf:snare(ti, 0.55 + (i - 12) * 0.12) -- the roll into what comes next
      buf:kick(ti, 0.8)
    elseif style == "groove" then -- the kick on every chug, the snare on three
      if pattern and pattern:sub(i + 1, i + 1) ~= "-" then
        buf:kick(ti, 0.95)
      end
      if i == 8 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.26, i == 0)
      end
    elseif style == "march" then -- four on the floor, snare on two and four, the anvil off the beat
      if i % 4 == 0 then
        buf:kick(ti, 1)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
        verb:snare(ti, 0.8)
      end
      if i % 4 == 2 then
        anvil(buf, ti, 0.7)
      end
    elseif style == "double" then
      buf:kick(ti, i % 4 == 0 and 0.95 or 0.6)
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
        verb:snare(ti, 0.9)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.22, i % 8 == 4)
      end
    elseif style == "half" then
      if i == 8 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.3, true)
      end
    elseif style == "brushes" then
      if i % 2 == 0 then
        buf:hat(ti, i % 4 == 2 and 0.08 or 0.05)
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
  local synth = Synth.newBuffer(total + 1) -- the arpeggio and the stabs
  local drums = Synth.newBuffer(total + 1)
  local verb = Synth.newBuffer(total + 1) -- the snare's room
  local clean = Synth.newBuffer(total + 1) -- the muzak and the chime, never driven
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
      if s.kind == "muzak" then
        -- Halcyon's lobby: C#m9 then Amaj7 on the piano, a vibraphone line, brushes...
        epiano(clean, t, BAR * 0.45, { "C#3", "E3", "G#3", "B3", "D#4" })
        epiano(clean, t + BAR * 0.5, BAR * 0.4, { "A2", "C#3", "E3", "G#3" })
        for k, n in ipairs({ "G#5", "E5", "B5", "G#5" }) do
          clean:tone(t + (k - 1) * 3 * SIXTEENTH, SIXTEENTH * 3, freq(n), { wave = "sine", amp = 0.07,
            decay = 0.5, sustain = 0.2, vibRate = 6, vibDepth = 0.2 })
        end
        drumBar(drums, verb, t, "brushes", false)
        -- ...until VEX pulls the plug: a tape stop, a stutter, and in.
        clean:sweep(t + BAR * 0.88, BAR * 0.12, 880, 40, { wave = "sine", amp = 0.14, decay = 99 })
        for k = 0, 3 do
          fx:noiseBurst(t + BAR * 0.88 + k * SIXTEENTH * 0.5, SIXTEENTH * 0.3, { amp = 0.25, decay = 0.02 })
        end
      elseif s.kind == "groove" then
        local bar = GROOVE[(b - 1) % #GROOVE + 1]
        if s.last and last then
          bar = GROOVE[4]
        end
        local pattern = bar[1]
        for i = 1, 16 do
          local c = pattern:sub(i, i)
          local ti = t + (i - 1) * SIXTEENTH
          if c == "x" then
            mute(ti, SIXTEENTH * 0.9, "C#2")
          elseif c == "o" then
            ring(ti, SIXTEENTH * 3.8, bar.ring)
          end
        end
        for _, i in ipairs({ 2, 6, 14 }) do -- stabs in the gaps
          if pattern:sub(i, i) == "-" then
            stab(synth, t + (i - 1) * SIXTEENTH, "C#5")
          end
        end
        drumBar(drums, verb, t, "groove", last and not s.last, pattern)
        if b == 1 then
          drums:hat(t, 0.65, true) -- the crash on the way in
          drums:kick(t, 1)
        end
      elseif s.kind == "march" then
        local riff = MARCH[(b - 1) % 2 + 1]
        for e, note in ipairs(riff) do
          mute(t + (e - 1) * 2 * SIXTEENTH, SIXTEENTH * 1.7, note)
        end
        if b >= 5 then
          arpBar(synth, t, CHORUS[1].arp, 0.035) -- the arpeggio creeping in
        end
        drumBar(drums, verb, t, "march", last)
        if b == 1 or b == 5 then
          drums:hat(t, 0.6, true)
        end
      elseif s.kind == "chorus" then
        local chord = CHORUS[(b - 1) % #CHORUS + 1]
        for _, h in ipairs({ { 0, 6 }, { 6, 6 }, { 12, 4 } }) do
          ring(t + h[1] * SIXTEENTH, h[2] * SIXTEENTH * 0.96, chord.root)
        end
        arpBar(synth, t, chord.arp, 0.05)
        local cursor = t
        for _, n in ipairs(LEAD[b]) do
          if n[1] then
            leadNote(lead, cursor, n[2] * SIXTEENTH, n[1])
          end
          cursor = cursor + n[2] * SIXTEENTH
        end
        drumBar(drums, verb, t, "double", last)
        if b % 2 == 1 then
          drums:hat(t, 0.6, true)
        end
      else -- the breakdown, ending on the lift's chime
        local pattern = BREAKDOWN[b]
        for i = 1, 16 do
          if pattern:sub(i, i) == "x" then
            mute(t + (i - 1) * SIXTEENTH, SIXTEENTH * 0.9, "C#2")
            drums:kick(t + (i - 1) * SIXTEENTH, 1)
          end
        end
        drumBar(drums, verb, t, "half", false)
        if b == 1 then
          drums:hat(t, 0.7, true)
        end
        if last then
          chime(clean, t + BAR * 0.45)
          fx:sweep(t, BAR, 150, 1700, { wave = "saw", amp = 0.08, decay = 99 })
        end
      end
      t = t + BAR
    end
  end

  rhythm:drive(12)
  rhythm:lowpass(3000)
  chug:drive(11)
  chug:lowpass(1700)
  bass:drive(3)
  bass:lowpass(500)
  lead:drive(3)
  lead:lowpass(5000)
  synth:lowpass(5000)
  drums:drive(1.5)
  drums:highpass(30)
  verb:lowpass(1500)
  verb:lowpass(1200)
  clean:lowpass(6000)
  fx:highpass(800)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  rhythm:mixInto(master, 0.42)
  chug:mixInto(master, 0.55)
  bass:mixInto(master, 0.45)
  lead:mixInto(master, 0.34)
  synth:mixInto(master, 0.4)
  drums:mixInto(master, 0.8)
  verb:mixInto(master, 0.25)
  clean:mixInto(master, 0.8)
  fx:mixInto(master, 0.2)
  master:drive(0.7 / math.max(master:peak(), 1e-6)) -- a gentle squeeze of the peaks: as loud as the Market's
  return master:toSoundData(0.9)
end

return Theme
