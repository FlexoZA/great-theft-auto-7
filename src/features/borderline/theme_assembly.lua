-- The Assembly Line's theme (music.lua plays it once Max's intro screen
-- goes), rendered by src/audio/synth.lua like the others. The robot
-- factory flat out: fast, frantic thrash, faster than any other map's, the
-- line's machines in the beat. Its own riffs; none of anybody else's.
--
-- It opens on the shift starting: the line's klaxon, the PA's robot voice
-- counting the shift in, a rivet gun rattling, and the gallop out of it.
-- The gallop: low E galloped in eighths and sixteenths over a d-beat, the
-- snare on every offbeat; the riff, chromatic thrash runs round the low E
-- with the kick doubling it; the solo, a lead shredding sixteenth arpeggios
-- over Em, C, D, B with the double kick under it; the breakdown, half-time
-- chugs on the lowest E, rivet guns rattling and the robot voice chanting
-- over them; and the gallop again into the top. 180 BPM in E minor: the
-- shift starting ~3 s once (`renderIntro`), then the loop ~43 s (`render`).

local Kit = require("src.features.borderline.theme_kit")

local Theme = {}

local BEAT = 60 / 180 -- seconds a beat
local STEP = BEAT / 4 -- a sixteenth
local BAR = BEAT * 4
local freq, clang = Kit.freq, Kit.clang

-- The gallop: a bar of sixteenths, `x` a chug on the low E, `o` the next of
-- the bar's `ring` notes rung out.
local GALLOP = {
  { "x-xxx-xxx-xxx-xx" },
  { "x-xxx-xxx-xxo---", ring = { "G2" } },
  { "x-xxx-xxx-xxx-xx" },
  { "x-xxx-xxo---o---", ring = { "A#2", "A2" } },
}

-- The riff: a note a sixteenth, muted ("-" a rest), chromatic round the low E.
local RIFF = {
  { "E2", "-", "E2", "F2", "E2", "-", "E2", "G2", "E2", "-", "E2", "F#2", "E2", "F2", "E2", "D2" },
  { "E2", "-", "E2", "F2", "E2", "-", "E2", "G2", "A2", "-", "G2", "-", "F#2", "-", "F2", "-" },
}

-- The solo: a chord a bar, and the arpeggio the lead shreds over it (its
-- notes, up and back down a sixteenth each).
local SOLO_CHORDS = { "E2", "C2", "D2", "B1", "E2", "C2", "D2", "B1" }
local SHRED = {
  { "E5", "G5", "B5", "E6" },
  { "C5", "E5", "G5", "C6" },
  { "D5", "F#5", "A5", "D6" },
  { "B4", "D#5", "F#5", "B5" },
}

-- The breakdown, half-time: chugs on the lowest E (x), silence (-).
local BREAK = { "x-----x-x-------", "x-----x-x---x---", "x-----x-x-------", "x--x--x-x-xxxxxx" }

local INTRO = { { bars = 2, kind = "shift" } }
local SECTIONS = {
  { bars = 8, kind = "gallop" },
  { bars = 8, kind = "riff" },
  { bars = 8, kind = "solo" },
  { bars = 4, kind = "breakdown" },
  { bars = 4, kind = "gallop", last = true },
}

-- Voices ------------------------------------------------------------------------

--- The line's klaxon: two notes a tritone apart, back and forth.
local function klaxon(buf, t, dur)
  local half = dur / 4
  for k = 0, 3 do
    local f = k % 2 == 0 and 440 or 311
    buf:tone(t + k * half, half * 0.9, f, { wave = "square", amp = 0.12, decay = 1, sustain = 0.9, release = 0.02 })
  end
end

--- The PA's robot voice: a syllable at a time on one flat pitch, buzzing,
--- the last of a phrase dropping (`syllables` their lengths in sixteenths).
local function robot(buf, t, syllables, note)
  local f = freq(note)
  for k, len in ipairs(syllables) do
    local dur = len * STEP * 0.85
    local pitch = k == #syllables and f * 0.84 or f
    buf:tone(t, dur, pitch, { wave = "square", amp = 0.07, attack = 0.01, decay = 1, sustain = 0.8, release = 0.02,
      vibRate = 60, vibDepth = 0.8 })
    buf:tone(t, dur, pitch * 2.98, { wave = "saw", amp = 0.02, attack = 0.01, decay = 1, sustain = 0.6,
      release = 0.02 })
    t = t + len * STEP
  end
end

--- A rivet gun: a fast rattle of hits, `n` of them.
local function rivets(metal, t, n, amp)
  for k = 0, n - 1 do
    metal:noiseBurst(t + k * 0.035, 0.02, { amp = 0.16 * amp, decay = 0.005 })
    metal:tone(t + k * 0.035, 0.03, 2200, { wave = "square", amp = 0.03 * amp, decay = 0.01, sustain = 0 })
  end
end

--- The lead shredding: a picked note, bright and short.
local function pickNote(buf, t, dur, note, amp)
  buf:tone(t, dur, freq(note), { wave = "square", amp = 0.075 * amp, attack = 0.003, decay = dur * 1.5,
    sustain = 0.5, release = 0.01 })
end

--- One bar of drums from `t`, `style`: "dbeat" (the kick on the beats and
--- the and of each, the snare on every offbeat eighth), "thrash" (the kick
--- on each chug of `pattern`, the snare on two and four), "double" (sixteenth
--- kicks, the snare on two and four), "half" (the kick on one, the snare on
--- three); `fill` a roll over the last beat.
local function drums(band, t, style, fill, pattern)
  Kit.drumBar(band, t, STEP, fill, function(kit, room, i, at, _beat, sub)
    if style == "dbeat" then
      if sub == 0 or sub == 3 then
        kit:kick(at, sub == 0 and 1 or 0.7)
      end
      if sub == 2 then
        kit:snare(at, 0.9)
        room:snare(at, 0.5)
      end
      if sub % 2 == 0 then
        kit:hat(at, 0.2)
      end
    elseif style == "thrash" then
      if pattern and pattern[i + 1] ~= "-" then
        kit:kick(at, 0.75)
      end
      if i == 4 or i == 12 then
        kit:snare(at, 1)
        room:snare(at, 0.8)
      end
      if sub % 2 == 0 then
        kit:hat(at, 0.22)
      end
    elseif style == "double" then
      kit:kick(at, sub == 0 and 0.9 or 0.55)
      if i == 4 or i == 12 then
        kit:snare(at, 1)
        room:snare(at, 0.8)
      end
      if sub == 0 then
        kit:hat(at, 0.26, i == 0)
      end
    elseif style == "half" then
      if i == 0 then
        kit:kick(at, 1)
      elseif i == 8 then
        kit:snare(at, 1)
        room:snare(at, 1)
      end
      if sub == 0 then
        kit:hat(at, 0.3, i == 0)
      end
    end
  end)
end

-- Render ----------------------------------------------------------------------

-- Bar `b` of section `s` from `t`, by the section's kind, into `band`.
local PLAY = {}

function PLAY.shift(band, t, b)
  if b == 1 then -- the klaxon, the PA counting the shift in...
    klaxon(band.horn, t, BAR)
    robot(band.lead, t + BEAT, { 2, 2, 2, 4 }, "E3")
  else -- ...a rivet gun, and the gallop out of it
    rivets(band.metal, t, 12, 1)
    robot(band.lead, t, { 2, 2, 4 }, "E3")
    drums(band, t, "half", true)
  end
end

function PLAY.gallop(band, t, b, s)
  local last = b == s.bars
  local bar = (s.last and last) and GALLOP[4] or GALLOP[(b - 1) % #GALLOP + 1]
  local pattern, k = bar[1], 0
  for i = 1, 16 do
    local c, at = pattern:sub(i, i), t + (i - 1) * STEP
    if c == "x" then
      band.mute(at, STEP * 0.85, "E2")
    elseif c == "o" then
      k = k + 1
      band.ring(at, STEP * (k < #bar.ring and 3.6 or 4), bar.ring[k])
    end
  end
  drums(band, t, "dbeat", last and not s.last)
  if b == 1 then
    band.drums:hat(t, 0.75, true)
  end
end

function PLAY.riff(band, t, b, s)
  local notes = RIFF[(b - 1) % #RIFF + 1]
  for i, note in ipairs(notes) do
    if note ~= "-" then
      band.mute(t + (i - 1) * STEP, STEP * 0.85, note)
    end
  end
  drums(band, t, "thrash", b == s.bars, notes)
  if b % 4 == 1 then
    band.drums:hat(t, 0.7, true)
    clang(band.metal, t, freq("E4"), 0.1, 0.4)
  end
end

function PLAY.solo(band, t, b, s)
  local root = SOLO_CHORDS[b]
  band.ring(t, STEP * 7.6, root)
  band.ring(t + 8 * STEP, STEP * 7.6, root)
  local arp = SHRED[(b - 1) % #SHRED + 1]
  for i = 0, 15 do -- up and back down, over and over
    local k = i % 6
    local note = arp[k < 4 and k + 1 or 7 - k]
    pickNote(band.lead, t + i * STEP, STEP, note, i % 4 == 0 and 1.2 or 1)
  end
  drums(band, t, "double", b == s.bars)
  if b == 1 or b == 5 then
    band.drums:hat(t, 0.65, true)
  end
end

function PLAY.breakdown(band, t, b, s)
  Kit.chugs(band, t, BREAK[b], STEP, "E2", "E1")
  rivets(band.metal, t + 8 * STEP, 8, b % 2 == 0 and 1 or 0.6)
  if b % 2 == 1 then
    robot(band.lead, t + 4 * STEP, { 2, 2, 2, 2 }, "E3")
  end
  drums(band, t, "half", b == s.bars)
  if b == 1 then
    band.drums:hat(t, 0.75, true)
  end
end

-- The desk: each part's level, drive and filters.
local DESK = {
  { "rhythm", 0.55, drive = 14, lowpass = 3200 },
  { "chug", 0.8, drive = 16, lowpass = 1900 },
  { "bass", 0.45, drive = 3, lowpass = 420 },
  { "sub", 0.28, drive = 2.5, lowpass = 600 },
  { "lead", 0.5, drive = 2.4, lowpass = 6500 },
  { "drums", 0.62, drive = 1.8, highpass = 40 },
  { "verb", 0.24, lowpass = 1200 },
  { "metal", 0.5, highpass = 300 },
  { "horn", 0.5, drive = 1.6, lowpass = 3000 },
}

-- The loop (gallop, riff, solo, breakdown, gallop: ~43 s), and the shift
-- starting (the klaxon, the PA, a rivet gun) once before it.
return Kit.theme(Theme, {
  bar = BAR, intro = INTRO, sections = SECTIONS, extras = { "horn" }, play = PLAY, desk = DESK,
})
