-- Heck on Earth's theme (init.lua plays it from the moment the Voice's intro
-- screen goes), rendered by src/audio/synth.lua like Fobos Base's
-- (theme_fobos.lua). Where Fobos Base's is slow and heavy, this one is rush
-- hour: faster thrash, galloping, tremolo-picked, with the city's air-raid
-- sirens wailing through it and its car horns blaring in the gaps. Its own
-- riffs; none of anybody else's.
--
-- It opens in the dream, as they all do: a cheery TV advert's jingle (the
-- sofa sale off the billboards) over a phone buzzing on a table, the jingle
-- dragged down like a tape stopping as an air-raid siren comes up and the
-- floor drops out. Then the gallop on the low E (an eighth and two
-- sixteenths, over and over), the kick locked to it; a tremolo-picked riff
-- in E Phrygian over a thrash beat, the sirens rising behind it; the
-- chorus, open chords E minor, C, D, B under a lead that slides like a
-- siren; a stop-start breakdown, rush hour, car horns in the gaps; and the
-- gallop again into the top. 150 BPM in E minor: the dream ~3 s once
-- (`renderIntro`), then the loop ~51 s (`render`).

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 150
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- The gallop: a bar of sixteenths, `x` a chug on the bar's root, `o` it rung
-- out, `-` silence; the root changes every two bars.
local GALLOP = "x-xxx-xxx-xxx-xx"
local GALLOP_LAST = "x-xxx-xxx-xxo---"
local GALLOP_ROOTS = { "E1", "G1", "E1", "C2" }

-- The tremolo riff: a note a beat, picked as sixteenths. Two bars, round.
local TREMOLO = {
  { "E2", "F2", "E2", "G2" },
  { "E2", "F2", "A2", "G2" },
  { "E2", "F2", "E2", "G2" },
  { "A#2", "A2", "G2", "F2" },
}

-- The chorus: a chord a bar.
local CHORUS = { "E1", "C2", "D2", "B1", "E1", "C2", "D2", "B1" }

-- The lead over the chorus, sliding into each note like a siren: eight
-- bars of { note|false, sixteenths }.
local LEAD = {
  { { "B4", 4 }, { "E5", 8 }, { "D5", 4 } },
  { { "E5", 4 }, { "G5", 8 }, { "F#5", 4 } },
  { { "F#5", 4 }, { "A5", 6 }, { "G5", 2 }, { "F#5", 4 } },
  { { "D#5", 12 }, { "B4", 4 } },
  { { "B4", 4 }, { "E5", 8 }, { "G5", 4 } },
  { { "B5", 6 }, { "A5", 2 }, { "G5", 8 } },
  { { "A5", 4 }, { "F#5", 4 }, { "D5", 4 }, { "A5", 4 } },
  { { "B5", 12 }, { false, 4 } },
}

-- The breakdown: chugs on the lowest E (x), silence (-), and in the
-- silences the city's car horns (h).
local BREAKDOWN = { "x--x--x---hh----", "x--x--x---h-h---", "x--x--x---hh----", "x-x-x-x-xxxxxxxx" }

-- The sofa sale's jingle on the TV: { note, sixteenths }. Major, bright,
-- and nothing to do with the end of the world.
local JINGLE = { { "C6", 2 }, { "E6", 2 }, { "G6", 2 }, { "C7", 4 }, { "A6", 2 }, { "G6", 4 } }

local INTRO = { { bars = 2, kind = "dream" } }
local SECTIONS = {
  { bars = 8, kind = "gallop" },
  { bars = 8, kind = "tremolo" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "breakdown" },
  { bars = 4, kind = "gallop", last = true },
}

-- Voices ------------------------------------------------------------------------

--- A power chord on `root` (root, fifth, octave), detuned wide, with the
--- low string an octave under it. Muted: a short thump; open: rung out.
local function powerChord(buf, t, dur, root, muted)
  local f = freq(root)
  local o = muted and { amp = 0.36, decay = 0.045, sustain = 0 } or { amp = 0.25, decay = 0.9, sustain = 0.6 }
  o.wave = "saw"
  for _, d in ipairs({ -14, 14 }) do
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
  buf:tone(t, dur, freq(root) / 2, { wave = "square", amp = 0.5, decay = muted and 0.08 or 0.6,
    sustain = muted and 0 or 0.6 })
end

--- One tremolo-picked note: a beat of fast sixteenths, single string, bright.
local function tremolo(buf, t, note)
  local f = freq(note)
  for k = 0, 3 do
    for _, d in ipairs({ -8, 8 }) do
      buf:tone(t + k * SIXTEENTH, SIXTEENTH * 0.85, f, { wave = "saw", amp = 0.16, attack = 0.002, decay = 0.06,
        sustain = 0.4, detune = d })
    end
  end
end

--- The synth bass diving: the floor dropping out.
local function dive(buf, t, dur, from)
  local f = freq(from)
  buf:sweep(t, dur, f, f / 3, { wave = "saw", amp = 0.7, decay = dur * 1.5 })
  buf:sweep(t, dur, f * 1.01, f / 3.1, { wave = "square", amp = 0.4, decay = dur * 1.5 })
end

--- A note of the lead, sliding up into it from a fourth under like a
--- siren, then singing.
local function leadNote(buf, t, dur, note)
  local f = freq(note)
  local slide = math.min(SIXTEENTH * 1.5, dur * 0.3)
  local long = dur > SIXTEENTH * 5
  for _, d in ipairs({ -10, 10 }) do
    buf:sweep(t, slide, f * 0.75, f, { wave = "saw", amp = 0.12, attack = 0.01, decay = 99, detune = d })
    buf:tone(t + slide, dur * 0.95 - slide, f, { wave = "saw", amp = 0.12, decay = 0.8, sustain = 0.8,
      release = 0.05, detune = d, vibRate = 6.5, vibDepth = long and 0.45 or 0.05 })
  end
end

--- An air-raid siren: rising, holding, falling, `dur` long.
local function siren(buf, t, dur, amp)
  local up, down = dur * 0.4, dur * 0.35
  for _, h in ipairs({ 1, 1.5 }) do
    buf:sweep(t, up, 220 * h, 620 * h, { wave = "square", amp = amp / h, attack = 0.2, decay = 99 })
    buf:tone(t + up, dur - up - down, 620 * h, { wave = "square", amp = amp / h, decay = 99, vibRate = 5,
      vibDepth = 0.3 })
    buf:sweep(t + dur - down, down, 620 * h, 260 * h, { wave = "square", amp = amp / h, decay = down * 0.8 })
  end
end

--- A car horn: two flat square notes blaring together.
local function horn(buf, t, dur)
  for _, f in ipairs({ 349, 440 }) do
    buf:tone(t, dur, f, { wave = "square", amp = 0.2, attack = 0.005, decay = 99, release = 0.02 })
  end
end

--- A phone buzzing on a table: a low rattle on and off.
local function buzz(buf, t, dur)
  buf:tone(t, dur, 150, { wave = "square", amp = 0.14, attack = 0.01, decay = 99, release = 0.02, vibRate = 32,
    vibDepth = 4 })
  buf:noiseBurst(t, dur, { amp = 0.05, decay = 99 })
end

--- A note of the jingle: bright bells, the way the adverts sound.
local function bell(buf, t, note, dur)
  local f = freq(note)
  buf:tone(t, dur, f, { wave = "sine", amp = 0.15, attack = 0.002, decay = 0.3, sustain = 0.1 })
  buf:tone(t, dur, f * 2, { wave = "square", amp = 0.03, attack = 0.002, decay = 0.1, sustain = 0 })
end

local function drumBar(buf, verb, t, style, fill, pattern)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      buf:snare(ti, 0.55 + (i - 12) * 0.12)
      buf:kick(ti, 0.85)
    elseif style == "gallop" then -- the kick on every chug, the snare on two and four
      if pattern and pattern:sub(i + 1, i + 1) ~= "-" then
        buf:kick(ti, 0.95)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
      end
      if i % 2 == 0 then
        buf:hat(ti, i % 4 == 0 and 0.26 or 0.15)
      end
    elseif style == "thrash" then -- kick and snare in turn on the eighths
      if i % 4 == 0 then
        buf:kick(ti, 1)
      elseif i % 4 == 2 then
        buf:snare(ti, 0.85)
        verb:snare(ti, 0.6)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.2, i % 8 == 0)
      end
    elseif style == "drive" then -- double kick under the chorus
      buf:kick(ti, i % 4 == 0 and 1 or 0.6)
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
        verb:snare(ti, 0.9)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.25, true)
      end
    elseif style == "stop" then
      if i == 8 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
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
  local sub = Synth.newBuffer(total + 1) -- the dives
  local lead = Synth.newBuffer(total + 1)
  local drums = Synth.newBuffer(total + 1)
  local verb = Synth.newBuffer(total + 1) -- the snare's room
  local city = Synth.newBuffer(total + 1) -- the sirens and horns
  local clean = Synth.newBuffer(total + 1) -- the advert and the phone, never driven

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
          -- Asleep in front of the telly: the sofa sale's jingle, the phone buzzing.
          local cursor = t + SIXTEENTH * 2
          for _, n in ipairs(JINGLE) do
            bell(clean, cursor, n[1], n[2] * SIXTEENTH * 1.2)
            cursor = cursor + n[2] * SIXTEENTH
          end
          buzz(clean, t + BAR * 0.05, BAR * 0.18)
          buzz(clean, t + BAR * 0.32, BAR * 0.18)
        else
          -- The jingle dragged down like a tape stopping, a siren coming up through it, and the drop.
          for k, n in ipairs({ "C7", "G6", "E6" }) do
            local f = freq(n)
            clean:sweep(t + (k - 1) * SIXTEENTH * 2, BAR * 0.4, f, f / 3, { wave = "sine", amp = 0.12, decay = 0.4 })
          end
          buzz(clean, t + BAR * 0.1, BAR * 0.15)
          siren(city, t, BAR, 0.12)
          dive(sub, t + BAR * 0.7, BAR * 0.3, "E2")
          drums:hat(t + BAR * 0.95, 0.5, true)
        end
      elseif s.kind == "gallop" then
        local root = GALLOP_ROOTS[math.floor((b - 1) / 2) % #GALLOP_ROOTS + 1]
        local pattern = (s.last and last) and GALLOP_LAST or GALLOP
        for i = 1, 16 do
          local c = pattern:sub(i, i)
          local ti = t + (i - 1) * SIXTEENTH
          if c == "x" then
            mute(ti, SIXTEENTH * 0.9, root)
          elseif c == "o" then
            ring(ti, SIXTEENTH * 3.8, "B1")
          end
        end
        if b % 4 == 0 then
          dive(sub, t + BAR * 0.75, BAR * 0.25, "E2")
        end
        drumBar(drums, verb, t, "gallop", last and not s.last, pattern)
        if b == 1 or b == 5 then
          drums:hat(t, 0.7, true)
          drums:kick(t, 1)
        end
      elseif s.kind == "tremolo" then
        local riff = TREMOLO[(b - 1) % #TREMOLO + 1]
        for k, note in ipairs(riff) do
          local ti = t + (k - 1) * 4 * SIXTEENTH
          tremolo(trem, ti, note)
          mute(ti, SIXTEENTH * 0.9, "E1") -- the low string under it on each beat
        end
        if b == 5 then
          siren(city, t, BAR * 4, 0.07) -- the sirens rising behind it
        end
        drumBar(drums, verb, t, "thrash", last)
        if b == 1 then
          drums:hat(t, 0.7, true)
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
        drumBar(drums, verb, t, "drive", last)
        if b % 2 == 1 then
          drums:hat(t, 0.65, true)
        end
      else -- the breakdown: rush hour
        local pattern = BREAKDOWN[b]
        for i = 1, 16 do
          local c = pattern:sub(i, i)
          local ti = t + (i - 1) * SIXTEENTH
          if c == "x" then
            mute(ti, SIXTEENTH * 0.9, "E1")
            sub:tone(ti, SIXTEENTH * 1.5, freq("E1"), { wave = "sine", amp = 0.6, decay = 0.2, sustain = 0 })
            drums:kick(ti, 1)
          elseif c == "h" then
            horn(city, ti, SIXTEENTH * 0.9)
          end
        end
        drumBar(drums, verb, t, "stop", false)
        if b == 1 then
          drums:hat(t, 0.75, true)
          dive(sub, t, BAR * 0.5, "E2")
        end
        if last then
          siren(city, t, BAR, 0.08)
        end
      end
      t = t + BAR
    end
  end

  rhythm:drive(12)
  rhythm:lowpass(3200)
  chug:drive(12)
  chug:lowpass(1700)
  trem:drive(6)
  trem:lowpass(4200)
  bass:drive(3)
  bass:lowpass(500)
  sub:drive(4)
  sub:lowpass(900)
  lead:drive(4)
  lead:lowpass(5200)
  drums:drive(1.6)
  drums:highpass(30)
  verb:lowpass(1400)
  city:drive(1.5)
  city:lowpass(3500)
  clean:lowpass(7000)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  rhythm:mixInto(master, 0.42)
  chug:mixInto(master, 0.56)
  trem:mixInto(master, 0.5)
  bass:mixInto(master, 0.45)
  sub:mixInto(master, 0.4)
  lead:mixInto(master, 0.34)
  drums:mixInto(master, 0.8)
  verb:mixInto(master, 0.25)
  city:mixInto(master, 0.3)
  clean:mixInto(master, 0.9)
  master:drive(0.7 / math.max(master:peak(), 1e-6)) -- the same squeeze as Fobos Base's, as loud
  return master:toSoundData(0.9)
end

--- The loop (gallop, tremolo, chorus, breakdown, gallop), ~51 s. Returns a SoundData.
function Theme.render()
  return render(SECTIONS)
end

--- The dream before it, once: the advert, the phone, the siren, the drop. Returns a SoundData.
function Theme.renderIntro()
  return render(INTRO)
end

return Theme
