-- Fobos Base's theme (init.lua plays it from the moment the Voice's intro
-- screen goes), rendered by src/audio/synth.lua the way Cyber Feud's level
-- themes are. Rip and tear: modern demon-shooter metal, tuned way down to a
-- low A, chugs syncopated against the beat, synth bass that dives, gated
-- noise, a lead that screams. Its own riffs; none of anybody else's.
--
-- It opens in the dream: a bar of a music box playing a lullaby, a snore
-- under it, slammed shut by a distorted bass drop. Then the riff: low A
-- chugs grouped three, three and two against the beat, the kick locked to
-- them, the snare on three, a synth bass diving at each bar's end; a second
-- riff over double kick that leans on the flat second (B flat) and stabs
-- high chords between; the chorus, open power chords A, F, G, E under a
-- screaming lead; a half-time breakdown on the lowest A there is, gated
-- noise stuttering through it; and the first riff again into the top.
-- 128 BPM in A minor (Phrygian where it hurts): the dream ~2 s once
-- (`renderIntro`), then the loop ~60 s (`render`).

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 128
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- Riff A: a bar of sixteenths, `x` a chug on the low A, `o` the bar's `ring`
-- note rung out, `-` silence. Three, three and two, across the bar.
local RIFF_A = {
  { "x--x--x-x--x--x-" },
  { "x--x--x-x--x-o--", ring = "C2" },
  { "x--x--x-x--x--x-" },
  { "x--x--x-xxxx-o--", ring = "A#1" },
}

-- Riff B: eighths, a note each; the flat second does the damage.
local RIFF_B = {
  { "A1", "A1", "A#1", "A1", "A1", "A1", "C2", "A#1" },
  { "A1", "A1", "A#1", "A1", "E2", "D#2", "D2", "A#1" },
}

-- The chorus: a chord a bar.
local CHORUS = { "A1", "F1", "G1", "E1", "A1", "F1", "G1", "A#1" }

-- The lead over the chorus: eight bars of { note|false, sixteenths }.
local LEAD = {
  { { "E5", 4 }, { "A5", 4 }, { "C6", 6 }, { "B5", 2 } },
  { { "A5", 6 }, { "G5", 2 }, { "F5", 8 } },
  { { "G5", 4 }, { "D6", 4 }, { "B5", 4 }, { "G5", 4 } },
  { { "G#5", 12 }, { "E5", 4 } },
  { { "A5", 4 }, { "C6", 4 }, { "E6", 6 }, { "D6", 2 } },
  { { "C6", 4 }, { "A5", 4 }, { "F5", 4 }, { "A5", 4 } },
  { { "B5", 4 }, { "D6", 4 }, { "G6", 4 }, { "F6", 2 }, { "D6", 2 } },
  { { "A#5", 12 }, { false, 4 } },
}

-- The breakdown: chugs on the lowest A (x) and silence (-), half-time.
local BREAKDOWN = { "x-----x---x-----", "x-----x---x-x---", "x-----x---x-----", "x-x-x-x-xxxxxxxx" }

-- The lullaby on the music box, in the first bar: { note, sixteenths }.
local LULLABY = { { "E6", 3 }, { "C6", 1 }, { "D6", 2 }, { "E6", 2 }, { "C6", 4 }, { "G5", 4 } }

-- The dream is its own bar, played once before the loop (`renderIntro`).
local INTRO = { { bars = 1, kind = "dream" } }
local SECTIONS = {
  { bars = 8, kind = "riffA" },
  { bars = 8, kind = "riffB" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "breakdown" },
  { bars = 4, kind = "riffA", last = true },
}

-- Voices ------------------------------------------------------------------------

--- A power chord on `root` (root, fifth, octave), detuned wide, with the
--- low string an octave under it. Muted: a short thump; open: rung out.
local function powerChord(buf, t, dur, root, muted)
  local f = freq(root)
  local o = muted and { amp = 0.38, decay = 0.05, sustain = 0 } or { amp = 0.26, decay = 0.9, sustain = 0.6 }
  o.wave = "saw"
  for _, d in ipairs({ -16, 16 }) do
    o.detune = d
    buf:tone(t, dur, f, o)
    buf:tone(t, dur, f * 1.5, o)
  end
  o.detune = 0
  o.amp = o.amp * 0.8
  buf:tone(t, dur, f / 2, o) -- the eighth string
  o.amp = o.amp * 0.5
  buf:tone(t, dur, f * 2, o)
end

local function bassNote(buf, t, dur, root, muted)
  buf:tone(t, dur, freq(root) / 2, { wave = "square", amp = 0.55, decay = muted and 0.09 or 0.6,
    sustain = muted and 0 or 0.6 })
end

--- The synth bass diving: a fat saw falling an octave and more, the floor
--- dropping out.
local function dive(buf, t, dur, from)
  local f = freq(from)
  buf:sweep(t, dur, f, f / 3, { wave = "saw", amp = 0.7, decay = dur * 1.5 })
  buf:sweep(t, dur, f * 1.01, f / 3.1, { wave = "square", amp = 0.4, decay = dur * 1.5 })
end

--- One note of the lead: two saws a little apart, singing on long notes.
local function leadNote(buf, t, dur, note)
  local f = freq(note)
  local long = dur > SIXTEENTH * 5
  for _, d in ipairs({ -9, 9 }) do
    buf:tone(t, dur * 0.95, f, { wave = "saw", amp = 0.13, attack = 0.01, decay = 0.8, sustain = 0.8,
      release = 0.05, detune = d, vibRate = 6, vibDepth = long and 0.4 or 0.05 })
  end
  buf:tone(t, dur * 0.95, f / 2, { wave = "square", amp = 0.05, attack = 0.01, decay = 0.8, sustain = 0.8,
    release = 0.05 })
end

--- A high stab: the chord an octave and more up, short.
local function stab(buf, t, root)
  for _, n in ipairs({ 24, 31, 36 }) do
    buf:tone(t, SIXTEENTH * 0.9, freq(root, n), { wave = "saw", amp = 0.06, attack = 0.002, decay = 0.08,
      sustain = 0 })
  end
end

--- Gated noise: a burst chopped into sixteenths.
local function gate(buf, t, steps, amp)
  for k = 0, steps - 1 do
    if k % 2 == 0 then
      buf:noiseBurst(t + k * SIXTEENTH * 0.5, SIXTEENTH * 0.4, { amp = amp, decay = 0.05 })
    end
  end
end

--- The music box: little bells, a fifth on top of each.
local function musicBox(buf, t, note, dur)
  local f = freq(note)
  buf:tone(t, dur, f, { wave = "sine", amp = 0.16, attack = 0.002, decay = 0.35, sustain = 0 })
  buf:tone(t, dur, f * 3, { wave = "sine", amp = 0.04, attack = 0.002, decay = 0.12, sustain = 0 })
end

--- A snore: breath in, rumbling out.
local function snore(buf, t)
  buf:noiseBurst(t, BAR * 0.35, { amp = 0.08, decay = BAR * 0.3 })
  buf:tone(t + BAR * 0.05, BAR * 0.3, 70, { wave = "saw", amp = 0.12, attack = 0.15, decay = 0.4, sustain = 0.6,
    vibRate = 18, vibDepth = 1.2 })
end

local function drumBar(buf, verb, t, style, fill, pattern)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      buf:snare(ti, 0.55 + (i - 12) * 0.12) -- the roll into what comes next
      buf:kick(ti, 0.85)
    elseif style == "groove" then -- the kick on every chug, the snare on three
      if pattern and pattern:sub(i + 1, i + 1) ~= "-" then
        buf:kick(ti, 1)
      end
      if i == 8 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
      end
      if i % 2 == 0 then
        buf:hat(ti, i % 4 == 0 and 0.28 or 0.16)
      end
    elseif style == "double" then
      buf:kick(ti, i % 4 == 0 and 1 or 0.65)
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

--- Renders `sections`. Returns a SoundData.
local function render(sections)
  local total = duration(sections)
  local rhythm = Synth.newBuffer(total + 1) -- open chords
  local chug = Synth.newBuffer(total + 1) -- palm-muted, darker
  local bass = Synth.newBuffer(total + 1)
  local sub = Synth.newBuffer(total + 1) -- the dives
  local lead = Synth.newBuffer(total + 1)
  local synth = Synth.newBuffer(total + 1) -- stabs
  local drums = Synth.newBuffer(total + 1)
  local verb = Synth.newBuffer(total + 1) -- the snare's room
  local clean = Synth.newBuffer(total + 1) -- the music box and the snore, never driven
  local fx = Synth.newBuffer(total + 1) -- gated noise

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
        -- Asleep: the lullaby on a music box, a snore under it...
        local cursor = t
        for _, n in ipairs(LULLABY) do
          if cursor < t + BAR * 0.8 then
            musicBox(clean, cursor, n[1], n[2] * SIXTEENTH * 1.6)
          end
          cursor = cursor + n[2] * SIXTEENTH * 0.8
        end
        snore(clean, t + BAR * 0.15)
        -- ...and the floor drops out from under it.
        dive(sub, t + BAR * 0.75, BAR * 0.25, "A2")
        fx:sweep(t + BAR * 0.7, BAR * 0.3, 200, 3000, { wave = "saw", amp = 0.1, decay = 99 })
      elseif s.kind == "riffA" then
        local bar = RIFF_A[(b - 1) % #RIFF_A + 1]
        if s.last and last then
          bar = RIFF_A[4]
        end
        local pattern = bar[1]
        for i = 1, 16 do
          local c = pattern:sub(i, i)
          local ti = t + (i - 1) * SIXTEENTH
          if c == "x" then
            mute(ti, SIXTEENTH * 0.9, "A1")
          elseif c == "o" then
            ring(ti, SIXTEENTH * 3.8, bar.ring)
          end
        end
        if b % 2 == 0 then
          dive(sub, t + BAR * 0.75, BAR * 0.25, "A1")
        end
        drumBar(drums, verb, t, "groove", last and not s.last, pattern)
        if b == 1 then
          drums:hat(t, 0.7, true) -- the crash on the way in
          drums:kick(t, 1)
        end
      elseif s.kind == "riffB" then
        local riff = RIFF_B[(b - 1) % 2 + 1]
        for e, note in ipairs(riff) do
          mute(t + (e - 1) * 2 * SIXTEENTH, SIXTEENTH * 1.7, note)
        end
        stab(synth, t + 3 * SIXTEENTH, "A1")
        stab(synth, t + 11 * SIXTEENTH, b % 2 == 0 and "A#1" or "C2")
        if b >= 5 then
          gate(fx, t, 16, 0.08) -- the noise creeping in
        end
        drumBar(drums, verb, t, "double", last)
        if b == 1 or b == 5 then
          drums:hat(t, 0.65, true)
        end
      elseif s.kind == "chorus" then
        local root = CHORUS[b]
        for _, h in ipairs({ { 0, 6 }, { 6, 6 }, { 12, 4 } }) do
          ring(t + h[1] * SIXTEENTH, h[2] * SIXTEENTH * 0.96, root)
        end
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
      else -- the breakdown, on the lowest A there is
        local pattern = BREAKDOWN[b]
        for i = 1, 16 do
          if pattern:sub(i, i) == "x" then
            local ti = t + (i - 1) * SIXTEENTH
            mute(ti, SIXTEENTH * 0.9, "A1")
            sub:tone(ti, SIXTEENTH * 1.5, freq("A0"), { wave = "sine", amp = 0.6, decay = 0.2, sustain = 0 })
            drums:kick(ti, 1)
          end
        end
        gate(fx, t + BAR * 0.5, 8, 0.12)
        drumBar(drums, verb, t, "half", false)
        if b == 1 then
          drums:hat(t, 0.75, true)
          dive(sub, t, BAR * 0.5, "A2")
        end
        if last then
          fx:sweep(t, BAR, 150, 2000, { wave = "saw", amp = 0.08, decay = 99 })
        end
      end
      t = t + BAR
    end
  end

  rhythm:drive(12)
  rhythm:lowpass(3000)
  chug:drive(12)
  chug:lowpass(1600)
  bass:drive(3)
  bass:lowpass(500)
  sub:drive(4)
  sub:lowpass(900)
  lead:drive(4)
  lead:lowpass(5200)
  synth:drive(2)
  synth:lowpass(4500)
  drums:drive(1.6)
  drums:highpass(30)
  verb:lowpass(1400)
  clean:lowpass(7000)
  fx:highpass(900)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  rhythm:mixInto(master, 0.42)
  chug:mixInto(master, 0.56)
  bass:mixInto(master, 0.45)
  sub:mixInto(master, 0.4)
  lead:mixInto(master, 0.34)
  synth:mixInto(master, 0.35)
  drums:mixInto(master, 0.8)
  verb:mixInto(master, 0.25)
  clean:mixInto(master, 0.9)
  fx:mixInto(master, 0.22)
  master:drive(0.7 / math.max(master:peak(), 1e-6)) -- a gentle squeeze of the peaks, as loud as Cyber Feud's
  return master:toSoundData(0.9)
end

--- The loop (riffs, chorus, breakdown, riff), ~60 s. Returns a SoundData.
function Theme.render()
  return render(SECTIONS)
end

--- The dream before it, once: the music box, the snore, the drop. Returns a SoundData.
function Theme.renderIntro()
  return render(INTRO)
end

return Theme
