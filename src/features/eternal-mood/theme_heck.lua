-- Heck's theme (init.lua plays it from the moment the Voice's intro screen
-- goes), rendered by src/audio/synth.lua like the others (theme_fobos.lua,
-- theme_earth.lua, theme_foundry.lua). Heck itself: the darkest of them,
-- blackened, built on the tritone, between blast beats and slow doom, a
-- choir and a church organ under it all and bells tolling. And the dream
-- is wearing thin: the Voice can hardly stay in character, so once round
-- the loop everything falls away to the music box from Fobos Base's dream,
-- slowed and out of tune, and a yawn, before the blast tears back in. Its
-- own riffs; none of anybody else's.
--
-- It opens in the dream: a microwave humming (the pizza, warming), its
-- ding, a yawn, and the floor going out from under it all, falling into
-- Heck. Then the blast: tremolo-picked riffs leaning on the flat second and
-- the tritone (C#, D, G) over blast beats, the choir held over them; the
-- doom, half time, huge open chords and an organ droning, a bell tolling
-- at every bar; the chorus, open chords C# minor, A, B, G# under a lead
-- and the choir, double kick; the drowse; and the blast into the top.
-- 140 BPM in C# minor: the dream ~3.4 s once (`renderIntro`), then the
-- loop ~51 s (`render`).

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 140
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- The blast riff: a note a beat, tremolo picked. Four bars, round.
local BLAST = {
  { "C#3", "D3", "C#3", "G3" },
  { "C#3", "D3", "E3", "D3" },
  { "C#3", "D3", "C#3", "G3" },
  { "G#3", "G3", "F#3", "D3" },
}

-- The doom: a chord a bar, rung out.
local DOOM = { "C#2", "C#2", "A1", "G1", "C#2", "C#2", "D2", "G#1" }

-- The chorus: a chord a bar, and the choir's over it.
local CHORUS = { "C#2", "A1", "B1", "G#1", "C#2", "A1", "B1", "G#1" }
local CHOIR = {
  { "C#4", "E4", "G#4" }, { "C#4", "E4", "A4" }, { "D#4", "F#4", "B4" }, { "C4", "D#4", "G#4" },
  { "C#4", "E4", "G#4" }, { "C#4", "E4", "A4" }, { "D#4", "F#4", "B4" }, { "C4", "D#4", "G#4" },
}

-- The lead over the chorus: eight bars of { note|false, sixteenths }.
local LEAD = {
  { { "G#5", 6 }, { "E5", 2 }, { "C#5", 8 } },
  { { "E5", 4 }, { "A5", 8 }, { "G#5", 4 } },
  { { "F#5", 6 }, { "B5", 6 }, { "A5", 4 } },
  { { "G#5", 12 }, { false, 4 } },
  { { "C#6", 6 }, { "B5", 2 }, { "G#5", 8 } },
  { { "A5", 4 }, { "E5", 4 }, { "A5", 4 }, { "C#6", 4 } },
  { { "D#6", 6 }, { "C#6", 2 }, { "B5", 8 } },
  { { "C6", 12 }, { false, 4 } },
}

-- Fobos Base's lullaby on the music box, in the drowse: { note, sixteenths }.
local LULLABY = { { "E6", 3 }, { "C6", 1 }, { "D6", 2 }, { "E6", 2 }, { "C6", 4 }, { "G5", 4 } }

local INTRO = { { bars = 2, kind = "dream" } }
local SECTIONS = {
  { bars = 8, kind = "blast" },
  { bars = 8, kind = "doom" },
  { bars = 8, kind = "chorus" },
  { bars = 2, kind = "drowse" },
  { bars = 4, kind = "blast", last = true },
}

-- Voices ------------------------------------------------------------------------

local function powerChord(buf, t, dur, root, muted)
  local f = freq(root)
  local o = muted and { amp = 0.36, decay = 0.05, sustain = 0 } or { amp = 0.26, decay = 1.2, sustain = 0.65 }
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
  buf:tone(t, dur, freq(root) / 2, { wave = "square", amp = 0.5, decay = muted and 0.08 or 0.8,
    sustain = muted and 0 or 0.65 })
end

--- One tremolo-picked note: a beat of sixteenths, single string.
local function tremolo(buf, t, note)
  local f = freq(note)
  for k = 0, 3 do
    for _, d in ipairs({ -9, 9 }) do
      buf:tone(t + k * SIXTEENTH, SIXTEENTH * 0.85, f, { wave = "saw", amp = 0.16, attack = 0.002, decay = 0.06,
        sustain = 0.45, detune = d })
    end
  end
end

--- A chord of the choir: detuned saws in slow, "aah" once filtered.
local function choir(buf, t, dur, notes, amp)
  for _, n in ipairs(notes) do
    for _, d in ipairs({ -12, 0, 12 }) do
      buf:tone(t, dur, freq(n), { wave = "saw", amp = (amp or 0.045), attack = dur * 0.3, decay = 99, release = 0.3,
        detune = d, vibRate = 4.5, vibDepth = 0.15 })
    end
  end
end

--- The organ: octaves and a fifth of square, held, a church's worth of it.
local function organ(buf, t, dur, root)
  local f = freq(root)
  for _, m in ipairs({ 1, 2, 3, 4 }) do
    buf:tone(t, dur, f * m, { wave = m % 2 == 1 and "square" or "sine", amp = 0.05 / m, attack = 0.08, decay = 99,
      release = 0.2 })
  end
end

--- A bell tolling: inharmonic partials, a long ring.
local function bell(buf, t, root, amp)
  local f = freq(root)
  for k, ratio in ipairs({ 0.5, 1, 1.19, 1.56, 2, 2.74, 3 }) do
    buf:tone(t, 3, f * ratio, { wave = "sine", amp = amp * 0.25 / math.sqrt(k), attack = 0.002, decay = 1.6 / k + 0.3,
      sustain = 0 })
  end
end

--- A note of the lead: two saws a little apart, a slow vibrato on the long ones.
local function leadNote(buf, t, dur, note)
  local f = freq(note)
  local long = dur > SIXTEENTH * 5
  for _, d in ipairs({ -9, 9 }) do
    buf:tone(t, dur * 0.95, f, { wave = "saw", amp = 0.12, attack = 0.02, decay = 0.8, sustain = 0.85,
      release = 0.08, detune = d, vibRate = 5.5, vibDepth = long and 0.5 or 0.05 })
  end
end

--- The music box from Fobos Base's dream, slowed and out of tune.
local function musicBox(buf, t, note, dur)
  local f = freq(note) * 0.97
  buf:tone(t, dur, f, { wave = "sine", amp = 0.16, attack = 0.002, decay = 0.5, sustain = 0, vibRate = 1.5,
    vibDepth = 0.25 })
  buf:tone(t, dur, f * 3, { wave = "sine", amp = 0.04, attack = 0.002, decay = 0.15, sustain = 0 })
end

--- A yawn: a breath drawn in and let out, falling.
local function yawn(buf, t, dur)
  buf:sweep(t, dur, 300, 140, { wave = "saw", amp = 0.08, attack = dur * 0.3, decay = 99 })
  for k = 0, 7 do
    local f = k / 7
    buf:noiseBurst(t + k * dur / 8, dur / 6, { amp = 0.05 * math.sin(f * math.pi) + 0.01, decay = dur / 8 })
  end
end

--- A microwave: a hum, the turntable ticking, then the ding.
local function microwave(buf, t, dur)
  buf:tone(t, dur, 100, { wave = "saw", amp = 0.05, attack = 0.05, decay = 99, release = 0.02 })
  buf:tone(t, dur, 200, { wave = "sine", amp = 0.04, attack = 0.05, decay = 99, release = 0.02 })
  for k = 0, math.floor(dur / 0.3) do
    buf:noiseBurst(t + k * 0.3, 0.02, { amp = 0.05, decay = 0.01 })
  end
  for _, h in ipairs({ 1, 2.76 }) do
    buf:tone(t + dur, 1.2, 1400 * h, { wave = "sine", amp = 0.14 / h, attack = 0.001, decay = 0.5, sustain = 0 })
  end
end

--- The floor going out: a long dive, everything falling.
local function fall(buf, t, dur)
  buf:sweep(t, dur, freq("C#3"), freq("C#3") / 6, { wave = "saw", amp = 0.6, decay = dur * 1.5 })
  buf:sweep(t, dur, freq("C#3") * 1.01, freq("C#3") / 6.2, { wave = "square", amp = 0.35, decay = dur * 1.5 })
end

local function drumBar(buf, verb, t, style, fill)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      buf:snare(ti, 0.55 + (i - 12) * 0.12)
      buf:kick(ti, 0.85)
    elseif style == "blast" then -- kick on every sixteenth, snare on every eighth's off
      buf:kick(ti, i % 2 == 0 and 0.9 or 0.6)
      if i % 2 == 1 then
        buf:snare(ti, 0.7)
        verb:snare(ti, 0.4)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.25, i % 8 == 0)
      end
    elseif style == "doom" then
      if i == 0 or i == 10 then
        buf:kick(ti, 1)
      end
      if i == 8 then
        buf:snare(ti, 1)
        verb:snare(ti, 1.3)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.18, true)
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
  local trem = Synth.newBuffer(total + 1) -- the tremolo picking
  local bass = Synth.newBuffer(total + 1)
  local sub = Synth.newBuffer(total + 1) -- the falls
  local lead = Synth.newBuffer(total + 1)
  local pad = Synth.newBuffer(total + 1) -- the choir and the organ
  local bells = Synth.newBuffer(total + 1)
  local drums = Synth.newBuffer(total + 1)
  local verb = Synth.newBuffer(total + 1)
  local clean = Synth.newBuffer(total + 1) -- the microwave, the music box, the yawns: never driven

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
          -- The pizza in the microwave, humming, then the ding.
          microwave(clean, t + 0.1, BAR * 0.7)
        else
          -- A yawn, and the floor going out: falling into Heck.
          yawn(clean, t, BAR * 0.6)
          fall(sub, t + BAR * 0.45, BAR * 0.55)
          bell(bells, t + BAR * 0.98, "C#3", 1)
        end
      elseif s.kind == "blast" then
        local riff = BLAST[(b - 1) % #BLAST + 1]
        for k, note in ipairs(riff) do
          local ti = t + (k - 1) * 4 * SIXTEENTH
          tremolo(trem, ti, note)
          mute(ti, SIXTEENTH * 0.9, "C#1")
        end
        if b % 4 == 1 then
          choir(pad, t, BAR * 4, { "C#4", "E4", "G4" }, 0.035) -- the tritone, held
        end
        drumBar(drums, verb, t, "blast", last and not s.last)
        if b == 1 or b == 5 then
          drums:hat(t, 0.75, true)
        end
      elseif s.kind == "doom" then
        local root = DOOM[b]
        ring(t, BAR * 0.96, root)
        organ(pad, t, BAR, root)
        bell(bells, t, root, 0.6)
        drumBar(drums, verb, t, "doom", last)
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
      elseif s.kind == "drowse" then
        -- Everything falls away but a drone; the music box, slowed; a yawn.
        organ(pad, t, BAR * 2, "C#2")
        if b == 1 then
          local cursor = t
          for _, n in ipairs(LULLABY) do
            musicBox(clean, cursor, n[1], n[2] * SIXTEENTH * 2.4)
            cursor = cursor + n[2] * SIXTEENTH * 1.6
          end
        else
          yawn(clean, t, BAR * 0.7)
          fall(sub, t + BAR * 0.6, BAR * 0.4)
          drums:snare(t + BAR * 0.75, 0.6)
          drums:snare(t + BAR * 0.8125, 0.7)
          drums:snare(t + BAR * 0.875, 0.85)
          drums:snare(t + BAR * 0.9375, 1)
        end
      end
      t = t + BAR
    end
  end

  rhythm:drive(12)
  rhythm:lowpass(2800)
  chug:drive(12)
  chug:lowpass(1500)
  trem:drive(7)
  trem:lowpass(4000)
  bass:drive(3)
  bass:lowpass(450)
  sub:drive(3)
  sub:lowpass(800)
  lead:drive(4)
  lead:lowpass(4800)
  pad:lowpass(2000)
  bells:lowpass(5000)
  drums:drive(1.6)
  drums:highpass(30)
  verb:lowpass(1200)
  clean:lowpass(7000)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  rhythm:mixInto(master, 0.42)
  chug:mixInto(master, 0.6)
  trem:mixInto(master, 0.5)
  bass:mixInto(master, 0.45)
  sub:mixInto(master, 0.45)
  lead:mixInto(master, 0.32)
  pad:mixInto(master, 0.6)
  bells:mixInto(master, 0.35)
  drums:mixInto(master, 0.75)
  verb:mixInto(master, 0.3)
  clean:mixInto(master, 0.9)
  master:drive(0.7 / math.max(master:peak(), 1e-6)) -- the same squeeze as the others, as loud
  return master:toSoundData(0.9)
end

--- The loop (blast, doom, chorus, drowse, blast), ~51 s. Returns a SoundData.
function Theme.render()
  return render(SECTIONS)
end

--- The dream before it, once: the microwave, a yawn, the fall. Returns a SoundData.
function Theme.renderIntro()
  return render(INTRO)
end

return Theme
