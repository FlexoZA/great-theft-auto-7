-- The Roof's music (init.lua plays it), rendered by src/audio/synth.lua the
-- way the other levels' themes are. Two pieces, for the two halves of the
-- fight:
--
-- `render`: Saye and Kilowatt, from the moment the roof wakes. The finale:
-- a bell tolling over a choir and a drone; then Kilowatt's half (a gallop
-- of drop-tuned chugs over double kick) and Saye's (staccato strings and a
-- cold square arpeggio over a ticking clock), each in turn; then the two
-- together, power chords and choir and strings under a lead; a half-time
-- breakdown with the bell; and together again, the lead an octave up.
-- 140 BPM in F# minor, ~45 s, loops.
--
-- `renderVex`: VEX's, from the moment she takes the roof until she gets
-- away. Hers is all signal: her modem chirp (a falling squeal) as the hook,
-- a chiptune arpeggio that glitches an octave now and then, a detuned
-- square bass, a breakbeat with stuttering snare rolls, and a bar where
-- the whole thing sticks like a frozen frame. 150 BPM in A minor, ~32 s,
-- loops.

local Synth = require("src.audio.synth")

local Theme = {}

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- Shared voices -----------------------------------------------------------------

--- A power chord on `root`, detuned wide, the low string an octave under.
local function powerChord(buf, t, dur, root, muted)
  local f = freq(root)
  local o = muted and { amp = 0.34, decay = 0.05, sustain = 0 } or { amp = 0.25, decay = 0.8, sustain = 0.6 }
  o.wave = "saw"
  for _, d in ipairs({ -13, 13 }) do
    o.detune = d
    buf:tone(t, dur, f, o)
    buf:tone(t, dur, f * 1.5, o)
  end
  o.detune, o.amp = 0, o.amp * 0.7
  buf:tone(t, dur, f / 2, o)
end

--- A choir: soft detuned saws and a sine an octave down, slow in and out
--- (a lowpass later takes the edge off: "aah").
local function choir(buf, t, dur, notes, amp)
  for _, n in ipairs(notes) do
    for _, d in ipairs({ -9, 0, 9 }) do
      buf:tone(t, dur, freq(n), { wave = "saw", amp = amp, attack = 0.35, decay = 99, sustain = 1, release = 0.4,
        detune = d, vibRate = 4.8, vibDepth = 0.06 })
    end
  end
end

--- A tolling bell: a sine and its clashing partials, ringing a long time.
local function bell(buf, t, note, amp)
  local f = freq(note)
  for _, p in ipairs({ { 1, 1 }, { 2.76, 0.45 }, { 5.4, 0.25 }, { 0.5, 0.5 } }) do
    buf:tone(t, 2.2, f * p[1], { wave = "sine", amp = amp * p[2], attack = 0.002, decay = 1.1 / p[1], sustain = 0 })
  end
end

-- Saye and Kilowatt -------------------------------------------------------------

local BPM = 140
local S = 60 / BPM / 4 -- a sixteenth
local BAR = S * 16

-- The chords a bar at a time, each a root, a choir and the strings' notes.
local CHORDS = {
  { root = "F#2", choir = { "F#3", "A3", "C#4" }, str = { "F#4", "A4", "C#5", "A4" } },
  { root = "D2", choir = { "D3", "F#3", "A3" }, str = { "D4", "F#4", "A4", "F#4" } },
  { root = "A1", choir = { "A2", "C#3", "E3" }, str = { "A3", "C#4", "E4", "C#4" } },
  { root = "E2", choir = { "E3", "G#3", "B3" }, str = { "E4", "G#4", "B4", "G#4" } },
}

-- The lead over "together": eight bars of { note|false, sixteenths }.
local LEAD = {
  { { "C#5", 4 }, { "F#5", 4 }, { "A5", 6 }, { "G#5", 2 } },
  { { "F#5", 8 }, { "D5", 4 }, { "E5", 4 } },
  { { "C#5", 4 }, { "E5", 4 }, { "A5", 4 }, { "B5", 4 } },
  { { "G#5", 12 }, { false, 4 } },
  { { "A5", 4 }, { "G#5", 2 }, { "F#5", 2 }, { "E5", 4 }, { "F#5", 4 } },
  { { "D5", 6 }, { "E5", 2 }, { "F#5", 8 } },
  { { "E5", 4 }, { "A5", 4 }, { "C#6", 4 }, { "B5", 4 } },
  { { "C#6", 12 }, { false, 4 } },
}

local SECTIONS = {
  { bars = 2, kind = "intro" },
  { bars = 4, kind = "kilowatt" },
  { bars = 4, kind = "saye" },
  { bars = 8, kind = "together" },
  { bars = 4, kind = "breakdown" },
  { bars = 4, kind = "together", high = true },
}

local function drumBar(buf, t, style, fill)
  for i = 0, 15 do
    local ti = t + i * S
    if fill and i >= 12 then
      buf:snare(ti, 0.5 + (i - 12) * 0.13)
      buf:kick(ti, 0.85)
    elseif style == "double" then
      buf:kick(ti, i % 4 == 0 and 1 or 0.62)
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.2, i % 8 == 4)
      end
    elseif style == "clock" then -- Saye's: a light four, a tick on every sixteenth
      if i % 4 == 0 then
        buf:kick(ti, 0.75)
      end
      if i == 12 then
        buf:snare(ti, 0.55)
      end
      buf:hat(ti, i % 4 == 2 and 0.18 or 0.08)
    elseif style == "half" then
      if i == 0 or i == 6 then
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

local function sectionsLength(sections, bar)
  local bars = 0
  for _, s in ipairs(sections) do
    bars = bars + s.bars
  end
  return bars * bar
end

function Theme.duration()
  return sectionsLength(SECTIONS, BAR)
end

--- Saye and Kilowatt's: renders the whole loop. Returns a SoundData.
function Theme.render()
  local total = Theme.duration()
  local guitar = Synth.newBuffer(total + 1)
  local chug = Synth.newBuffer(total + 1)
  local bass = Synth.newBuffer(total + 1)
  local voices = Synth.newBuffer(total + 1) -- the choir
  local strings = Synth.newBuffer(total + 1)
  local lead = Synth.newBuffer(total + 1)
  local drums = Synth.newBuffer(total + 1)
  local bells = Synth.newBuffer(total + 1)

  local function bassNote(ti, len, root, muted)
    bass:tone(ti, len, freq(root) / 2, { wave = "square", amp = 0.5, decay = muted and 0.08 or 0.6,
      sustain = muted and 0 or 0.6 })
  end

  local t = 0
  for _, sec in ipairs(SECTIONS) do
    for b = 1, sec.bars do
      local chord = CHORDS[(b - 1) % #CHORDS + 1]
      local last = b == sec.bars
      if sec.kind == "intro" then
        choir(voices, t, BAR, CHORDS[1].choir, 0.05)
        bass:tone(t, BAR, freq("F#1") / 2, { wave = "saw", amp = 0.25, attack = 0.8, decay = 99, sustain = 1 })
        for k = 0, 1 do
          bell(bells, t + k * 8 * S, "F#3", 0.4)
        end
        if b == 2 then
          bells:sweep(t, BAR, 100, 1600, { wave = "saw", amp = 0.08, decay = 99 })
          drumBar(drums, t, "half", true)
        end
      elseif sec.kind == "kilowatt" then -- his: the gallop
        local root = "F#2"
        for beat = 0, 3 do
          local tb = t + beat * 4 * S
          if beat == 3 and b % 2 == 0 then
            powerChord(guitar, tb, 4 * S * 0.95, "G2", false) -- the flat second, rung
            bassNote(tb, 4 * S, "G2", false)
          else
            for _, o in ipairs({ { 0, 1.7 }, { 2, 0.85 }, { 3, 0.85 } }) do
              powerChord(chug, tb + o[1] * S, S * o[2], root, true)
              bassNote(tb + o[1] * S, S * o[2], root, true)
            end
          end
        end
        drumBar(drums, t, "double", last)
        if b == 1 then
          drums:hat(t, 0.65, true)
        end
      elseif sec.kind == "saye" then -- hers: strings and a cold arpeggio, on a clock
        for e = 0, 7 do
          strings:tone(t + e * 2 * S, S * 1.2, freq(chord.str[e % 4 + 1]), { wave = "saw", amp = 0.11,
            attack = 0.004, decay = 0.08, sustain = 0.2, release = 0.03 })
        end
        for i = 0, 15 do
          local n = chord.str[(i * 3) % 4 + 1]
          lead:tone(t + i * S, S * 0.5, freq(n, 12), { wave = "square", amp = 0.045, decay = 0.04, sustain = 0 })
        end
        bassNote(t, BAR * 0.95, chord.root, false)
        drumBar(drums, t, "clock", last)
      elseif sec.kind == "together" then
        for _, h in ipairs({ { 0, 6 }, { 6, 6 }, { 12, 4 } }) do
          powerChord(guitar, t + h[1] * S, h[2] * S * 0.96, chord.root, false)
          bassNote(t + h[1] * S, h[2] * S * 0.96, chord.root, false)
        end
        choir(voices, t, BAR, chord.choir, 0.035)
        for e = 0, 7 do
          strings:tone(t + e * 2 * S, S * 1.2, freq(chord.str[e % 4 + 1]), { wave = "saw", amp = 0.08,
            attack = 0.004, decay = 0.08, sustain = 0.2, release = 0.03 })
        end
        local cursor = t
        for _, n in ipairs(LEAD[b]) do
          if n[1] then
            local f = freq(n[1], sec.high and 12 or 0)
            local long = n[2] > 5
            for _, d in ipairs({ -8, 8 }) do
              lead:tone(cursor, n[2] * S * 0.95, f, { wave = "saw", amp = 0.12, attack = 0.01, decay = 0.8,
                sustain = 0.8, release = 0.05, detune = d, vibRate = 5.5, vibDepth = long and 0.35 or 0.05 })
            end
          end
          cursor = cursor + n[2] * S
        end
        drumBar(drums, t, "double", last and not sec.high)
        if b % 4 == 1 then
          drums:hat(t, 0.6, true)
        end
      else -- the breakdown: half-time chugs, the bell, the choir
        for _, i in ipairs({ 0, 3, 6, 10, 11 }) do
          powerChord(chug, t + i * S, S * 0.9, "F#2", true)
          bassNote(t + i * S, S * 0.9, "F#2", true)
        end
        choir(voices, t, BAR, CHORDS[(b - 1) % 2 * 3 + 1].choir, 0.045)
        bell(bells, t, "F#3", 0.35)
        drumBar(drums, t, "half", last)
      end
      t = t + BAR
    end
  end

  guitar:drive(12)
  guitar:lowpass(3000)
  chug:drive(11)
  chug:lowpass(1800)
  bass:drive(3)
  bass:lowpass(520)
  voices:lowpass(1300)
  strings:lowpass(4200)
  lead:drive(2.5)
  lead:lowpass(5000)
  drums:drive(1.4)
  drums:highpass(30)
  bells:lowpass(5000)

  local master = Synth.newBuffer(total)
  guitar:mixInto(master, 0.4)
  chug:mixInto(master, 0.5)
  bass:mixInto(master, 0.45)
  voices:mixInto(master, 0.6)
  strings:mixInto(master, 0.45)
  lead:mixInto(master, 0.36)
  drums:mixInto(master, 0.8)
  bells:mixInto(master, 0.35)
  master:drive(0.7 / math.max(master:peak(), 1e-6)) -- a gentle squeeze, as loud as the other themes
  return master:toSoundData(0.9)
end

-- VEX ---------------------------------------------------------------------------

local VBPM = 150
local V = 60 / VBPM / 4
local VBAR = V * 16

local VCHORDS = {
  { root = "A1", arp = { "A4", "C5", "E5", "A5" } },
  { root = "F1", arp = { "F4", "A4", "C5", "F5" } },
  { root = "C2", arp = { "C5", "E5", "G5", "C6" } },
  { root = "G1", arp = { "G4", "B4", "D5", "G5" } },
}
local VARP = { 1, 2, 3, 4, 3, 2, 4, 3, 1, 3, 2, 4, 4, 3, 2, 1 }
-- Which sixteenths of a bar the arpeggio jumps an octave on: the glitch.
local GLITCH = { [7] = true, [12] = true, [15] = true }

local VLEAD = {
  { { "E5", 3 }, { "E5", 3 }, { "D5", 2 }, { "C5", 4 }, { "D5", 4 } },
  { { "A4", 6 }, { false, 2 }, { "C5", 4 }, { "E5", 4 } },
  { { "G5", 3 }, { "G5", 3 }, { "F5", 2 }, { "E5", 4 }, { "C5", 4 } },
  { { "D5", 8 }, { "B4", 4 }, { false, 4 } },
}

local VSECTIONS = {
  { bars = 2, kind = "boot" },
  { bars = 8, kind = "drop" },
  { bars = 2, kind = "freeze" },
  { bars = 8, kind = "drop", lead = true },
}

function Theme.vexDuration()
  return sectionsLength(VSECTIONS, VBAR)
end

--- Her chirp: the modem's falling squeal, with a little noise on it.
local function chirp(buf, t, from, to, amp)
  buf:sweep(t, 0.22, from, to, { wave = "square", amp = amp, decay = 0.12 })
  buf:noiseBurst(t, 0.05, { amp = amp * 0.4, decay = 0.02 })
end

local function breakBar(buf, t, roll)
  for i = 0, 15 do
    local ti = t + i * V
    if roll and i >= 12 then -- the stutter: snares in thirty-seconds
      buf:snare(ti, 0.5)
      buf:snare(ti + V / 2, 0.4)
    else
      if i == 0 or i == 10 then
        buf:kick(ti, 1)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 0.9)
      end
      if i == 7 then
        buf:snare(ti, 0.3) -- a ghost
      end
      buf:hat(ti, i % 2 == 0 and 0.16 or 0.08, i == 14)
    end
  end
end

--- VEX's: renders the whole loop. Returns a SoundData.
function Theme.renderVex()
  local total = Theme.vexDuration()
  local arp = Synth.newBuffer(total + 1)
  local bass = Synth.newBuffer(total + 1)
  local lead = Synth.newBuffer(total + 1)
  local chirps = Synth.newBuffer(total + 1)
  local drums = Synth.newBuffer(total + 1)
  local pad = Synth.newBuffer(total + 1)

  local function arpBar(t, chord, amp, frozen)
    for i, step in ipairs(VARP) do
      local n = chord.arp[frozen and 1 or step]
      local up = (GLITCH[i] and not frozen) and 12 or 0
      arp:tone(t + (i - 1) * V, V * 0.6, freq(n, up), { wave = "square", amp = amp, decay = 0.05, sustain = 0.1,
        release = 0.02 })
    end
  end

  local t = 0
  for _, sec in ipairs(VSECTIONS) do
    for b = 1, sec.bars do
      local chord = VCHORDS[(b - 1) % #VCHORDS + 1]
      local last = b == sec.bars
      if sec.kind == "boot" then -- she comes on: chirps over a filtered arpeggio
        arpBar(t, chord, 0.04 + b * 0.02)
        chirp(chirps, t, 2400, 900, 0.18)
        chirp(chirps, t + 8 * V, 2000, 700, 0.15)
        if b == 2 then
          breakBar(drums, t, true)
        end
      elseif sec.kind == "drop" then
        arpBar(t, chord, 0.07)
        for e = 0, 7 do -- the bass in eighths, two squares beating against each other
          for _, d in ipairs({ -15, 15 }) do
            bass:tone(t + e * 2 * V, V * 1.7, freq(chord.root), { wave = "square", amp = 0.2, decay = 0.2,
              sustain = 0.5, detune = d })
          end
        end
        pad:tone(t, VBAR, freq(chord.root, 24), { wave = "saw", amp = 0.04, attack = 0.2, decay = 99, sustain = 1 })
        if b % 2 == 1 then
          chirp(chirps, t, 2200, 800, 0.12)
        end
        if sec.lead then
          local cursor = t
          for _, n in ipairs(VLEAD[(b - 1) % #VLEAD + 1]) do
            if n[1] then
              lead:tone(cursor, n[2] * V * 0.9, freq(n[1]), { wave = "square", amp = 0.09, decay = 0.4,
                sustain = 0.5, vibRate = 7, vibDepth = n[2] > 5 and 0.3 or 0 })
              lead:tone(cursor, n[2] * V * 0.9, freq(n[1], 12), { wave = "tri", amp = 0.05, decay = 0.4,
                sustain = 0.5 })
            end
            cursor = cursor + n[2] * V
          end
        end
        breakBar(drums, t, last or b % 4 == 0)
      else -- the freeze: one sixteenth of everything, stuck repeating, then a tape-stop
        for i = 0, 15 do
          arp:tone(t + i * V, V * 0.8, freq(chord.arp[1]), { wave = "square", amp = 0.08, decay = 99, sustain = 1 })
          bass:tone(t + i * V, V * 0.8, freq(chord.root), { wave = "square", amp = 0.2, decay = 99, sustain = 1 })
          if i % 2 == 0 then
            drums:kick(t + i * V, 0.6)
          end
        end
        if last then
          chirps:sweep(t + 12 * V, 4 * V, 900, 40, { wave = "square", amp = 0.18, decay = 99 })
        end
      end
      t = t + VBAR
    end
  end

  arp:lowpass(5000)
  bass:drive(2.5)
  bass:lowpass(900)
  lead:drive(1.8)
  lead:lowpass(5200)
  chirps:highpass(300)
  drums:drive(1.5)
  drums:highpass(30)
  pad:lowpass(2500)

  local master = Synth.newBuffer(total)
  arp:mixInto(master, 0.55)
  bass:mixInto(master, 0.5)
  lead:mixInto(master, 0.45)
  chirps:mixInto(master, 0.5)
  drums:mixInto(master, 0.8)
  pad:mixInto(master, 0.5)
  master:drive(0.7 / math.max(master:peak(), 1e-6))
  return master:toSoundData(0.9)
end

return Theme
