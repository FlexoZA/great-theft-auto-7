-- Prosperity's theme (music.lua plays it once Max's intro screen goes),
-- rendered by src/audio/synth.lua like the others. Max's own city, so his
-- own anthem: big, bright, cheesy arena rock, everything turned up to the
-- max. Its own tunes; none of anybody else's.
--
-- It opens on the PA: the chime, Hyperbole's jingle on synth brass, the
-- crowd roaring, a fill into the riff. Then the anthem: two stomps and a
-- clap under chugged E with the chords rung out on the beat; the fanfare,
-- the brass blaring a tune over E, B, C#m, A; the chorus, a lead guitar
-- and the brass on the tune together, the crowd shouting HEY on the fourth
-- beat; the factory, half-time, the presses stamping and hissing, the
-- jingle on a music box over them; and the anthem again into the top. 132
-- BPM in E major: the PA ~5 s once (`renderIntro`), then the loop ~51 s
-- (`render`).

local Kit = require("src.features.borderline.theme_kit")

local Theme = {}

local BEAT = 60 / 132
local STEP = BEAT / 4 -- a sixteenth
local BAR = BEAT * 4
local freq, clang = Kit.freq, Kit.clang

-- Hyperbole's jingle: { note, sixteenths }, once through a bar.
local JINGLE = { { "B4", 2 }, { "E5", 2 }, { "G#5", 2 }, { "B5", 6 }, { "A5", 2 }, { "B5", 2 } }

-- The anthem: a bar of sixteenths, `x` a chug on the low E, `o` the bar's
-- chord rung out, `-` silence; its chord.
local ANTHEM = {
  { "o-xx-xxxo-xx-xxx", "E2" },
  { "o-xx-xxxo-xx-xxx", "B1" },
  { "o-xx-xxxo-xx-xxx", "C#2" },
  { "o-xx-xxxo---o---", "A1" },
}

-- The fanfare and the chorus: a chord a bar, and the tune over it, eight
-- bars of { note|false, sixteenths }.
local CHORDS = { "E2", "B1", "C#2", "A1", "E2", "B1", "A1", "B1" }
local FANFARE = {
  { { "E5", 4 }, { "G#5", 4 }, { "B5", 6 }, { "G#5", 2 } },
  { { "F#5", 6 }, { "D#5", 2 }, { "B4", 8 } },
  { { "C#5", 4 }, { "E5", 4 }, { "G#5", 4 }, { "E5", 4 } },
  { { "A5", 8 }, { "G#5", 4 }, { "F#5", 4 } },
  { { "E5", 4 }, { "G#5", 4 }, { "B5", 6 }, { "C#6", 2 } },
  { { "D#6", 6 }, { "C#6", 2 }, { "B5", 8 } },
  { { "A5", 4 }, { "C#6", 4 }, { "E6", 4 }, { "C#6", 4 } },
  { { "B5", 12 }, { false, 4 } },
}
local CHORUS = {
  { { "B5", 6 }, { "E6", 2 }, { "E6", 4 }, { "D#6", 4 } },
  { { "D#6", 6 }, { "C#6", 2 }, { "B5", 8 } },
  { { "C#6", 6 }, { "E6", 2 }, { "E6", 4 }, { "G#5", 4 } },
  { { "A5", 4 }, { "B5", 4 }, { "C#6", 4 }, { "B5", 4 } },
  { { "B5", 6 }, { "E6", 2 }, { "E6", 4 }, { "F#6", 4 } },
  { { "G#6", 6 }, { "F#6", 2 }, { "E6", 8 } },
  { { "C#6", 4 }, { "E6", 4 }, { "A6", 4 }, { "G#6", 4 } },
  { { "F#6", 8 }, { "B5", 4 }, { false, 4 } },
}

-- The factory, half-time: chugs on the lowest E (x), silence (-).
local FACTORY = { "x-------x-x-----", "x-------x---x---", "x-------x-x-----", "x-x-x-x-x-x-xxxx" }

local INTRO = { { bars = 3, kind = "pa" } }
local SECTIONS = {
  { bars = 4, kind = "anthem" },
  { bars = 8, kind = "fanfare" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "factory" },
  { bars = 4, kind = "anthem", last = true },
}

-- Voices ------------------------------------------------------------------------

--- Synth brass: a stack of saws a little apart, swelling in, a touch of
--- vibrato on the held notes.
local function brass(buf, t, dur, note, amp)
  local f = freq(note)
  for _, d in ipairs({ -9, 0, 9 }) do
    buf:tone(t, dur * 0.95, f, { wave = "saw", amp = 0.05 * amp, attack = 0.03, decay = 1.2, sustain = 0.85,
      release = 0.06, detune = d, vibRate = 5.5, vibDepth = dur > STEP * 5 and 0.12 or 0 })
  end
  buf:tone(t, dur * 0.95, f / 2, { wave = "square", amp = 0.025 * amp, attack = 0.03, decay = 1, sustain = 0.7 })
end

--- The lead guitar: picked hard, a quick slide into each note.
local function guitar(buf, t, dur, note)
  local f = freq(note)
  buf:sweep(t, 0.03, f * 0.95, f, { wave = "saw", amp = 0.07, decay = 0.04 })
  buf:tone(t + 0.02, dur * 0.95, f, { wave = "saw", amp = 0.1, attack = 0.005, decay = 0.7, sustain = 0.65,
    release = 0.05, vibRate = 6, vibDepth = dur > STEP * 5 and 0.28 or 0.02 })
end

--- A clap: a few bursts of noise close together.
local function clap(buf, t, amp)
  for i = 0, 2 do
    buf:noiseBurst(t + i * 0.008, 0.05, { amp = 0.35 * amp, decay = 0.012 })
  end
end

--- The crowd shouting HEY: a burst of breath and a falling chord of voices.
local function hey(buf, t)
  buf:noiseBurst(t, 0.18, { amp = 0.25, decay = 0.05 })
  for _, f in ipairs({ 260, 330, 390, 520 }) do
    buf:sweep(t, 0.2, f, f * 0.85, { wave = "saw", amp = 0.06, decay = 0.08 })
  end
end

--- The PA's chime: three bells, up then down, `amp` loud.
local function chime(buf, t, amp)
  for i, n in ipairs({ "G#5", "B5", "E5" }) do
    clang(buf, t + (i - 1) * 0.32, freq(n), amp, 1.4)
  end
end

--- A press stamping: a thump, its die ringing, then the hiss of its steam.
local function press(buf, metal, t)
  buf:sweep(t, 0.3, 80, 40, { wave = "sine", amp = 0.6, decay = 0.1 })
  clang(metal, t, freq("E3"), 0.16, 0.5)
  metal:noiseBurst(t + STEP * 3, BEAT, { amp = 0.08, decay = BEAT * 0.5 })
end

--- A music box: the jingle picked out, small and tinny.
local function musicBox(buf, t)
  Kit.play(JINGLE, t, STEP, function(at, dur, note)
    buf:tone(at, dur + 0.3, freq(note, 12), { wave = "tri", amp = 0.07, attack = 0.002, decay = 0.25, sustain = 0 })
  end)
end

--- One bar of drums from `t`, `style`: "stomp" (two kicks and a clap with
--- the snare, over and over), "march" (the kick on the beats, the snare on
--- two and four, rolls of sixteenths on the hats), "drive" (the kick every
--- eighth, the hats every sixteenth), "half" (the kick on one, the snare on
--- three); `fill` a roll over the last beat.
local function drums(band, t, style, fill)
  local kit, room = band.drums, band.verb
  for i = 0, 15 do
    local at = t + i * STEP
    local beat, sub = math.floor(i / 4), i % 4
    if fill and beat == 3 then
      kit:snare(at, 0.55 + sub * 0.14)
      kit:kick(at, 0.85)
    elseif style == "stomp" then
      if sub == 0 and beat % 2 == 0 then
        kit:kick(at, 1)
      elseif sub == 2 and beat % 2 == 0 then
        kit:kick(at, 0.9)
      elseif sub == 0 then
        kit:snare(at, 0.8)
        clap(room, at, 1)
      end
    elseif style == "march" then
      if sub == 0 then
        kit:kick(at, beat == 0 and 1 or 0.7)
      end
      if sub == 0 and beat % 2 == 1 then
        kit:snare(at, 1)
        room:snare(at, 0.7)
      end
      kit:hat(at, sub == 0 and 0.2 or 0.09)
    elseif style == "drive" then
      if sub % 2 == 0 then
        kit:kick(at, sub == 0 and 1 or 0.6)
      end
      if sub == 0 and beat % 2 == 1 then
        kit:snare(at, 1)
        clap(room, at, 0.8)
      end
      kit:hat(at, sub == 0 and 0.24 or 0.12, sub == 2)
    elseif style == "half" then
      if i == 0 then
        kit:kick(at, 1)
      elseif i == 8 then
        kit:snare(at, 1)
        room:snare(at, 1)
      end
      if sub == 0 then
        kit:hat(at, 0.28, beat % 2 == 0)
      end
    end
  end
end

-- Render ----------------------------------------------------------------------

-- Bar `b` of section `s` from `t`, by the section's kind, into `band`.
local PLAY = {}

function PLAY.pa(band, t, b)
  if b == 1 then -- the chime...
    chime(band.metal, t + 0.1, 0.9)
  elseif b == 2 then -- ...the jingle, the crowd roaring...
    Kit.play(JINGLE, t, STEP, function(at, dur, note)
      brass(band.box, at, dur, note, 5)
    end)
    band.metal:noiseBurst(t + BAR * 0.4, BAR, { amp = 0.3, decay = BAR * 0.5 })
  else -- ...and the drums into the riff
    band.ring(t, BAR * 0.9, "E2")
    drums(band, t, "half", true)
  end
end

function PLAY.anthem(band, t, b, s)
  local last = b == s.bars
  local bar = ANTHEM[(b - 1) % #ANTHEM + 1]
  local pattern, root = bar[1], bar[2]
  for i = 1, 16 do
    local c, at = pattern:sub(i, i), t + (i - 1) * STEP
    if c == "x" then
      band.mute(at, STEP * 0.85, "E2")
    elseif c == "o" then
      band.ring(at, STEP * 3.6, root)
    end
  end
  drums(band, t, "stomp", last and not s.last)
  if b == 1 then
    band.drums:hat(t, 0.7, true)
  end
end

function PLAY.fanfare(band, t, b, s)
  local root = CHORDS[b]
  band.ring(t, STEP * 7.6, root)
  band.ring(t + 8 * STEP, STEP * 7.6, root)
  Kit.play(FANFARE[b], t, STEP, function(at, dur, note)
    brass(band.box, at, dur, note, 1)
  end)
  drums(band, t, "march", b == s.bars)
  if b == 1 or b == 5 then
    band.drums:hat(t, 0.6, true)
  end
end

function PLAY.chorus(band, t, b, s)
  local root = CHORDS[b]
  for _, h in ipairs({ { 0, 6 }, { 6, 4 }, { 10, 6 } }) do
    band.ring(t + h[1] * STEP, h[2] * STEP * 0.96, root)
  end
  Kit.play(CHORUS[b], t, STEP, function(at, dur, note)
    guitar(band.lead, at, dur, note)
    brass(band.box, at, dur, note, 0.7)
  end)
  if b % 2 == 0 then
    hey(band.horn, t + 12 * STEP)
  end
  drums(band, t, "drive", b == s.bars)
  if b % 2 == 1 then
    band.drums:hat(t, 0.65, true)
  end
end

function PLAY.factory(band, t, b, s)
  Kit.chugs(band, t, FACTORY[b], STEP, "E2", "E1")
  press(band.sub, band.metal, t)
  press(band.sub, band.metal, t + 8 * STEP)
  if b % 2 == 1 then
    musicBox(band.box, t)
  end
  drums(band, t, "half", b == s.bars)
  if b == 1 then
    band.drums:hat(t, 0.75, true)
  end
end

-- The desk: each part's level, drive and filters.
local DESK = {
  { "rhythm", 0.42, drive = 9, lowpass = 3400 },
  { "chug", 0.5, drive = 10, lowpass = 1800 },
  { "bass", 0.45, drive = 3, lowpass = 500 },
  { "sub", 0.45, drive = 2, lowpass = 700 },
  { "lead", 0.34, drive = 3.5, lowpass = 5000 },
  { "box", 0.5, drive = 1.4, lowpass = 3800 },
  { "drums", 0.8, drive = 1.5, highpass = 30 },
  { "verb", 0.3, lowpass = 2400 },
  { "metal", 0.45, highpass = 180 },
  { "horn", 0.6, drive = 1.5, lowpass = 3000 },
}

-- The loop (anthem, fanfare, chorus, factory, anthem: ~51 s), and the PA (the chime,
-- the jingle, the crowd, the fill) once before it.
return Kit.theme(Theme, {
  bar = BAR, intro = INTRO, sections = SECTIONS, extras = { "box", "horn" }, play = PLAY, desk = DESK,
})
