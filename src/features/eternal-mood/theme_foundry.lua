-- The Foundry's theme (init.lua plays it from the moment the Voice's intro
-- screen goes), rendered by src/audio/synth.lua like Fobos Base's and
-- Earth's (theme_fobos.lua, theme_earth.lua). A factory that melts Heck
-- down: industrial metal, slower and heavier than Earth's, the guitars
-- locked to a machine, anvils ringing on the off-beats, steam hissing out
-- of the press, and a choir coming up out of the floor where the UAC's half
-- gives way to Heck's. Its own riffs; none of anybody else's.
--
-- It opens in the dream: Dr. Seek's speech has turned into a cooking show,
-- so a cheery marimba jingle over a pan sizzling; somebody far away calls
-- "hey" (falling, two notes, the beat); steam builds and a hydraulic press
-- slams the dream shut. Then the machine: palm-muted chugs on the low D in
-- a mechanical pattern, a sequenced synth ticking sixteenths under it, the
-- kick on every chug, an anvil on the last off-beat; the press, half time,
-- chords slammed on one and three with the steam hissing between and
-- anvils on every off-beat; the chorus, open chords D minor, B flat, C, A
-- under a choir and a slow mournful lead; and the machine again into the
-- top. 110 BPM in D minor, drop D: the dream ~4 s once (`renderIntro`),
-- then the loop ~61 s (`render`).

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 110
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- The machine: a bar of sixteenths, `x` a chug on the low D, `o` the bar's
-- `ring` rung out, `-` silence.
local MACHINE = {
  { "x---x---x-x-x---" },
  { "x---x---x-x-x-o-", ring = "F2" },
  { "x---x---x-x-x---" },
  { "x---x---x-x-xxo-", ring = "D#2" },
}

-- The sequencer under it: sixteenths round and round, a bar each.
local SEQUENCE = {
  { "D3", "D4", "A3", "D4", "F4", "D4", "A3", "D4", "D3", "D4", "A3", "D4", "G4", "F4", "A3", "D4" },
  { "D3", "D4", "A3", "D4", "F4", "D4", "A3", "D4", "D3", "D4", "A#3", "D4", "A4", "G4", "F4", "E4" },
}

-- The press: chords on one and three, the root for each bar.
local PRESS = { "D2", "D2", "F2", "D#2", "D2", "D2", "A#1", "A1" }

-- The chorus: a chord a bar.
local CHORUS = { "D2", "A#1", "C2", "A1", "D2", "A#1", "C2", "A1" }

-- The choir over it: a chord a bar (three notes), slow in.
local CHOIR = {
  { "D4", "F4", "A4" }, { "D4", "F4", "A#4" }, { "C4", "E4", "G4" }, { "C#4", "E4", "A4" },
  { "D4", "F4", "A4" }, { "D4", "F4", "A#4" }, { "E4", "G4", "C5" }, { "C#4", "E4", "A4" },
}

-- The lead over the chorus, slow and mournful: eight bars of { note|false, sixteenths }.
local LEAD = {
  { { "A5", 8 }, { "F5", 4 }, { "D5", 4 } },
  { { "F5", 12 }, { "D5", 4 } },
  { { "E5", 6 }, { "G5", 6 }, { "C6", 4 } },
  { { "A5", 12 }, { false, 4 } },
  { { "A5", 4 }, { "D6", 8 }, { "C6", 4 } },
  { { "A#5", 8 }, { "A5", 4 }, { "F5", 4 } },
  { { "G5", 6 }, { "E5", 6 }, { "C5", 4 } },
  { { "C#5", 12 }, { false, 4 } },
}

-- Dr. Seek's cooking show's jingle: { note, sixteenths }.
local JINGLE = { { "G5", 2 }, { "C6", 2 }, { "E6", 2 }, { "G6", 2 }, { "E6", 2 }, { "C6", 2 }, { "D6", 4 } }

local INTRO = { { bars = 2, kind = "dream" } }
local SECTIONS = {
  { bars = 8, kind = "machine" },
  { bars = 8, kind = "press" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "machine", last = true },
}

-- Voices ------------------------------------------------------------------------

--- A power chord on `root` (root, fifth, octave), detuned wide, with the
--- low string an octave under it. Muted: a short thump; open: rung out.
local function powerChord(buf, t, dur, root, muted)
  local f = freq(root)
  local o = muted and { amp = 0.38, decay = 0.05, sustain = 0 } or { amp = 0.26, decay = 1.0, sustain = 0.6 }
  o.wave = "saw"
  for _, d in ipairs({ -16, 16 }) do
    o.detune = d
    buf:tone(t, dur, f, o)
    buf:tone(t, dur, f * 1.5, o)
  end
  o.detune = 0
  o.amp = o.amp * 0.8
  buf:tone(t, dur, f / 2, o)
  o.amp = o.amp * 0.5
  buf:tone(t, dur, f * 2, o)
end

local function bassNote(buf, t, dur, root, muted)
  buf:tone(t, dur, freq(root) / 2, { wave = "square", amp = 0.55, decay = muted and 0.09 or 0.7,
    sustain = muted and 0 or 0.6 })
end

--- An anvil: a hammer on steel, inharmonic partials ringing out.
local function anvil(buf, t, amp)
  local f = 880
  for k, ratio in ipairs({ 1, 2.76, 5.40, 8.93 }) do
    buf:tone(t, 0.6, f * ratio, { wave = "sine", amp = amp * 0.35 / k, attack = 0.001, decay = 0.25 / k + 0.05,
      sustain = 0 })
  end
  buf:noiseBurst(t, 0.03, { amp = amp * 0.5, decay = 0.01 })
end

--- Steam: a hiss swelling and dying, in short bursts stacked up.
local function steam(buf, t, dur, amp)
  local n = 10
  for k = 0, n - 1 do
    local f = k / (n - 1)
    local swell = f < 0.4 and f / 0.4 or (1 - f) / 0.6
    buf:noiseBurst(t + k * dur / n, dur / n * 1.5, { amp = amp * (0.15 + 0.85 * swell), decay = dur / n })
  end
end

--- The press coming down: a thud, the low end dropping out under it.
local function slam(buf, sub, t)
  buf:kick(t, 1)
  buf:noiseBurst(t, 0.2, { amp = 0.6, decay = 0.06 })
  sub:sweep(t, 0.5, freq("D2"), freq("D1") / 2, { wave = "sine", amp = 0.8, decay = 0.4 })
end

--- One step of the sequencer: a short square, its edge filtered later.
local function tick(buf, t, note)
  buf:tone(t, SIXTEENTH * 0.6, freq(note), { wave = "square", amp = 0.09, attack = 0.002, decay = 0.07, sustain = 0 })
end

--- A chord of the choir: detuned saws coming in slow, "aah" once filtered.
local function choir(buf, t, dur, notes)
  for _, n in ipairs(notes) do
    for _, d in ipairs({ -12, 0, 12 }) do
      buf:tone(t, dur, freq(n), { wave = "saw", amp = 0.045, attack = dur * 0.35, decay = 99, release = 0.3,
        detune = d, vibRate = 4.5, vibDepth = 0.15 })
    end
  end
end

--- A note of the lead: two saws a little apart, a slow vibrato on the long ones.
local function leadNote(buf, t, dur, note)
  local f = freq(note)
  local long = dur > SIXTEENTH * 5
  for _, d in ipairs({ -8, 8 }) do
    buf:tone(t, dur * 0.95, f, { wave = "saw", amp = 0.12, attack = 0.03, decay = 0.8, sustain = 0.85,
      release = 0.1, detune = d, vibRate = 5, vibDepth = long and 0.5 or 0.05 })
  end
end

--- A marimba note: a woody knock, quick to die.
local function marimba(buf, t, note, dur)
  local f = freq(note)
  buf:tone(t, dur, f, { wave = "sine", amp = 0.18, attack = 0.002, decay = 0.25, sustain = 0 })
  buf:tone(t, dur, f * 4, { wave = "sine", amp = 0.05, attack = 0.002, decay = 0.05, sustain = 0 })
end

--- Somebody far away calling "hey": two notes falling, soft, a breath on them.
local function hey(buf, t)
  for k, n in ipairs({ "E4", "C#4" }) do
    local f = freq(n)
    local at = t + (k - 1) * 0.3
    buf:tone(at, 0.35, f, { wave = "tri", amp = 0.09, attack = 0.04, decay = 0.3, sustain = 0.3,
      vibRate = 5, vibDepth = 0.2 })
    buf:tone(at, 0.35, f * 2, { wave = "sine", amp = 0.03, attack = 0.04, decay = 0.3, sustain = 0.3 })
    buf:noiseBurst(at, 0.1, { amp = 0.03, decay = 0.08 })
  end
end

local function drumBar(buf, verb, t, style, fill, pattern)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      buf:snare(ti, 0.55 + (i - 12) * 0.12)
      buf:kick(ti, 0.85)
    elseif style == "machine" then -- the kick on every chug, a big snare on two and four
      if pattern and pattern:sub(i + 1, i + 1) ~= "-" then
        buf:kick(ti, 1)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
      end
      if i % 2 == 0 then
        buf:hat(ti, i % 4 == 0 and 0.22 or 0.12)
      end
    elseif style == "half" then
      if i == 0 then
        buf:kick(ti, 1)
      end
      if i == 8 then
        buf:snare(ti, 1)
        verb:snare(ti, 1.2)
      end
      if i % 4 == 2 then
        buf:hat(ti, 0.2, true)
      end
    elseif style == "double" then
      buf:kick(ti, i % 4 == 0 and 1 or 0.6)
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.25, true)
      end
    end
  end
end

-- Render ----------------------------------------------------------------------

local function duration(sections)
  local bars = 0
  for _, s in ipairs(sections) do
    bars = bars + s.bars
  end
  return bars * BAR
end

--- The loop's length, seconds.
function Theme.duration()
  return duration(SECTIONS)
end

local function render(sections)
  local total = duration(sections)
  local rhythm = Synth.newBuffer(total + 1) -- open chords
  local chug = Synth.newBuffer(total + 1) -- palm-muted
  local bass = Synth.newBuffer(total + 1)
  local sub = Synth.newBuffer(total + 1) -- the press's low end
  local seq = Synth.newBuffer(total + 1) -- the sequencer
  local lead = Synth.newBuffer(total + 1)
  local pad = Synth.newBuffer(total + 1) -- the choir
  local drums = Synth.newBuffer(total + 1)
  local verb = Synth.newBuffer(total + 1)
  local metal = Synth.newBuffer(total + 1) -- anvils and steam
  local clean = Synth.newBuffer(total + 1) -- the cooking show and the call, never driven

  local function mute(ti, len, note)
    powerChord(chug, ti, len, note, true)
    bassNote(bass, ti, len, note, true)
  end
  local function ring(ti, len, note)
    powerChord(rhythm, ti, len, note, false)
    bassNote(bass, ti, len, note, false)
  end

  local t = 0
  for _, s in ipairs(sections) do
    for b = 1, s.bars do
      local last = b == s.bars
      if s.kind == "dream" then
        if b == 1 then
          -- Dr. Seek's cooking show: the jingle on a marimba, a pan sizzling.
          local cursor = t + SIXTEENTH
          for _, n in ipairs(JINGLE) do
            marimba(clean, cursor, n[1], n[2] * SIXTEENTH * 1.5)
            cursor = cursor + n[2] * SIXTEENTH
          end
          clean:noiseBurst(t, BAR * 0.9, { amp = 0.05, decay = 99 })
        else
          -- Somebody far away calls; steam builds; the press slams it shut.
          hey(clean, t + BAR * 0.05)
          steam(metal, t + BAR * 0.35, BAR * 0.6, 0.25)
          slam(drums, sub, t + BAR * 0.94)
          anvil(metal, t + BAR * 0.94, 1)
        end
      elseif s.kind == "machine" then
        local bar = MACHINE[(b - 1) % #MACHINE + 1]
        local pattern = bar[1]
        for i = 1, 16 do
          local c = pattern:sub(i, i)
          local ti = t + (i - 1) * SIXTEENTH
          if c == "x" then
            mute(ti, SIXTEENTH * 0.9, "D1")
          elseif c == "o" then
            ring(ti, SIXTEENTH * 1.8, bar.ring)
          end
        end
        local steps = SEQUENCE[(b - 1) % 2 + 1]
        for i, n in ipairs(steps) do
          tick(seq, t + (i - 1) * SIXTEENTH, n)
        end
        anvil(metal, t + 14 * SIXTEENTH, 0.7)
        drumBar(drums, verb, t, "machine", last and not s.last, pattern)
        if b == 1 then
          drums:hat(t, 0.7, true)
        end
      elseif s.kind == "press" then
        local root = PRESS[b]
        ring(t, SIXTEENTH * 3.5, root)
        ring(t + 8 * SIXTEENTH, SIXTEENTH * 3.5, root)
        sub:tone(t, SIXTEENTH * 3, freq("D1") / 2, { wave = "sine", amp = 0.6, decay = 0.3, sustain = 0 })
        steam(metal, t + 4 * SIXTEENTH, SIXTEENTH * 4, 0.12)
        steam(metal, t + 12 * SIXTEENTH, SIXTEENTH * 4, 0.12)
        for k = 2, 14, 4 do
          anvil(metal, t + k * SIXTEENTH, 0.45)
        end
        drumBar(drums, verb, t, "half", last)
        if b == 1 or b == 5 then
          drums:hat(t, 0.7, true)
        end
      elseif s.kind == "chorus" then
        local root = CHORUS[b]
        for _, h in ipairs({ { 0, 6 }, { 6, 6 }, { 12, 4 } }) do
          ring(t + h[1] * SIXTEENTH, h[2] * SIXTEENTH * 0.96, root)
        end
        choir(pad, t, BAR, CHOIR[b])
        local cursor = t
        for _, n in ipairs(LEAD[b]) do
          if n[1] then
            leadNote(lead, cursor, n[2] * SIXTEENTH, n[1])
          end
          cursor = cursor + n[2] * SIXTEENTH
        end
        drumBar(drums, verb, t, "double", last)
        if b % 2 == 1 then
          drums:hat(t, 0.65, true)
        end
      end
      t = t + BAR
    end
  end

  rhythm:drive(12)
  rhythm:lowpass(2800)
  chug:drive(12)
  chug:lowpass(1500)
  bass:drive(3)
  bass:lowpass(450)
  sub:drive(3)
  sub:lowpass(800)
  seq:drive(2)
  seq:lowpass(2600)
  lead:drive(4)
  lead:lowpass(4800)
  pad:lowpass(1800)
  drums:drive(1.6)
  drums:highpass(30)
  verb:lowpass(1200)
  metal:highpass(400)
  clean:lowpass(7000)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  rhythm:mixInto(master, 0.42)
  chug:mixInto(master, 0.66)
  bass:mixInto(master, 0.45)
  sub:mixInto(master, 0.45)
  seq:mixInto(master, 0.5)
  lead:mixInto(master, 0.32)
  pad:mixInto(master, 0.6)
  drums:mixInto(master, 0.8)
  verb:mixInto(master, 0.3)
  metal:mixInto(master, 0.28)
  clean:mixInto(master, 0.9)
  master:drive(0.7 / math.max(master:peak(), 1e-6)) -- the same squeeze as the others, as loud
  return master:toSoundData(0.9)
end

--- The loop (machine, press, chorus, machine), ~61 s. Returns a SoundData.
function Theme.render()
  return render(SECTIONS)
end

--- The dream before it, once: the cooking show, the call, the press. Returns a SoundData.
function Theme.renderIntro()
  return render(INTRO)
end

return Theme
