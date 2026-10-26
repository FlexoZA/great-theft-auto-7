-- The Refinery's theme (music.lua plays it once Max's intro screen goes),
-- rendered by src/audio/synth.lua like the others. A smelting hall in the
-- dark: mechanical industrial metal, every riff locked to the machines,
-- forge hammers ringing on the beat. Its own riffs; none of anybody else's.
--
-- It opens on the shift starting: a steam whistle shrieking up to its
-- note, then the furnace catching, a roar swelling under a hammer blow,
-- and the press out of it. The press: low D muted in a tight, clipped
-- sixteenth riff, the kick on every chug like a machine stamping, the
-- snare dead on two and four, a forge hammer on the anvil each bar; the
-- pour, the chorus, a lead singing over rung-out chords (Dm, Bb, F, C;
-- Dm, Bb, Gm, A) with anvils on the backbeat; the vent, half-time, chugs
-- on the lowest D, steam hissing out of the floor and the big hammer on
-- the one; and the press again into the top. 128 BPM in D minor: the
-- whistle and the furnace ~4 s once (`renderIntro`), then the loop
-- ~53 s (`render`).

local Kit = require("src.features.borderline.theme_kit")

local Theme = {}

local BEAT = 60 / 128 -- seconds a beat
local STEP = BEAT / 4 -- a sixteenth
local BAR = BEAT * 4
local freq, clang = Kit.freq, Kit.clang

-- The press: a bar of sixteenths, `x` a chug on the low D, `o` the next of
-- the bar's `ring` notes rung out.
local PRESS = {
  { "xx-x-xx-xx-x-x-x" },
  { "xx-x-xx-xx-x-o--", ring = { "F2" } },
  { "xx-x-xx-xx-x-x-x" },
  { "xx-x-xx-x-o-o-o-", ring = { "G2", "F2", "C2" } },
}

-- The pour, the chorus: a chord a bar, and the lead's tune over it, eight
-- bars of { note|false, sixteenths }.
local POUR_CHORDS = { "D2", "A#1", "F2", "C2", "D2", "A#1", "G1", "A1" }
local SING = {
  { { "A4", 4 }, { "D5", 4 }, { "F5", 6 }, { "E5", 2 } },
  { { "D5", 8 }, { "A#4", 8 } },
  { { "C5", 4 }, { "F5", 4 }, { "A5", 6 }, { "G5", 2 } },
  { { "E5", 8 }, { "C5", 8 } },
  { { "A4", 4 }, { "D5", 4 }, { "F5", 4 }, { "A5", 4 } },
  { { "A#5", 6 }, { "A5", 2 }, { "F5", 8 } },
  { { "G5", 4 }, { "F5", 4 }, { "E5", 4 }, { "D5", 4 } },
  { { "C#5", 8 }, { "E5", 4 }, { false, 4 } },
}

-- The vent, half-time: chugs on the lowest D (x), silence (-).
local VENT = { "x-------x--x----", "x-------x--x-x--", "x-------x--x----", "x--x--x-x-x-xxxx" }

local INTRO = { { bars = 2, kind = "shift" } }
local SECTIONS = {
  { bars = 8, kind = "press" },
  { bars = 8, kind = "pour" },
  { bars = 8, kind = "vent" },
  { bars = 4, kind = "press", last = true },
}

-- Voices ------------------------------------------------------------------------

--- The steam whistle: two pipes shrieking up to a chord and holding it,
--- the steam rushing round them.
local function whistle(buf, steam, t, dur)
  for _, note in ipairs({ "A5", "C6" }) do
    local f = freq(note)
    buf:sweep(t, 0.25, f * 0.8, f, { wave = "sine", amp = 0.1, decay = 1 })
    buf:tone(t + 0.25, dur - 0.25, f, { wave = "sine", amp = 0.1, attack = 0.01, decay = 1, sustain = 0.9,
      release = 0.2, vibRate = 7, vibDepth = 0.1 })
  end
  steam:noiseBurst(t, dur, { amp = 0.25, decay = dur })
end

--- The furnace catching: a roar swelling up out of nothing, low and wide.
local function roar(buf, steam, t, dur)
  for i = 0, 11 do
    local at = t + i * dur / 12
    steam:noiseBurst(at, dur / 6, { amp = 0.04 + 0.035 * i, decay = dur / 8 })
  end
  buf:sweep(t, dur, 30, 55, { wave = "saw", amp = 0.3, decay = dur * 2 })
end

--- A forge hammer on the anvil: struck metal ringing on, a thump under it.
local function hammer(metal, sub, t, amp)
  clang(metal, t, freq("D4"), 0.16 * amp, 0.5)
  sub:sweep(t, 0.15, 110, 45, { wave = "sine", amp = 0.5 * amp, decay = 0.06 })
end

--- Steam out of a vent in the floor: a hiss, rising and gone.
local function hiss(steam, t, dur, amp)
  steam:noiseBurst(t, dur, { amp = 0.3 * amp, decay = dur * 0.6 })
end

--- The lead singing: slid up into each note, held with a slow vibrato, an
--- octave under it on the long ones.
local function sing(buf, t, dur, note)
  local f = freq(note)
  buf:sweep(t, 0.05, f * 0.94, f, { wave = "square", amp = 0.07, decay = 0.08 })
  local o = { wave = "square", amp = 0.085, attack = 0.04, decay = 1, sustain = 0.8, release = 0.08, vibRate = 5.5,
    vibDepth = dur > STEP * 5 and 0.3 or 0.05 }
  buf:tone(t + 0.04, dur * 0.95, f, o)
  if dur > STEP * 5 then
    o.amp, o.vibDepth = 0.045, 0.15
    buf:tone(t + 0.04, dur * 0.95, f / 2, o)
  end
end

--- One bar of drums from `t`, `style`: "press" (the kick on every chug of
--- `pattern`, the snare on two and four, the hats in eighths), "pour" (the
--- kick on one, the and of two and three, the snare on two and four, the
--- ride on the beats), "half" (the kick on one, the snare on three); `fill`
--- a roll over the last beat.
local function drums(band, t, style, fill, pattern)
  local kit, room = band.drums, band.verb
  for i = 0, 15 do
    local at = t + i * STEP
    local beat, sub = math.floor(i / 4), i % 4
    if fill and beat == 3 then
      kit:snare(at, 0.6 + sub * 0.12)
      kit:kick(at, 0.8)
    elseif style == "press" then
      if pattern and pattern:sub(i + 1, i + 1) == "x" then
        kit:kick(at, sub == 0 and 1 or 0.7)
      end
      if i == 4 or i == 12 then
        kit:snare(at, 1)
        room:snare(at, 0.8)
      end
      if sub % 2 == 0 then
        kit:hat(at, sub == 0 and 0.22 or 0.14)
      end
    elseif style == "pour" then
      if i == 0 or i == 6 or i == 8 then
        kit:kick(at, i == 0 and 1 or 0.75)
      end
      if i == 4 or i == 12 then
        kit:snare(at, 0.95)
        room:snare(at, 0.8)
      end
      if sub == 0 then
        kit:hat(at, 0.24, beat == 0)
      end
    elseif style == "half" then
      if i == 0 then
        kit:kick(at, 1)
      elseif i == 8 then
        kit:snare(at, 1)
        room:snare(at, 1)
      end
      if sub == 0 and beat % 2 == 0 then
        kit:hat(at, 0.3, true)
      end
    end
  end
end

-- Render ----------------------------------------------------------------------

-- Bar `b` of section `s` from `t`, by the section's kind, into `band`.
local PLAY = {}

function PLAY.shift(band, t, b)
  if b == 1 then -- the whistle...
    whistle(band.lead, band.steam, t, BAR * 0.8)
  else -- ...the furnace catching, a hammer blow, the press out of it
    roar(band.sub, band.steam, t, BAR * 0.75)
    hammer(band.metal, band.sub, t + BAR * 0.75, 1)
    drums(band, t, "half", true)
  end
end

function PLAY.press(band, t, b, s)
  local last = b == s.bars
  local bar = (s.last and last) and PRESS[4] or PRESS[(b - 1) % #PRESS + 1]
  local pattern, k = bar[1], 0
  for i = 1, 16 do
    local c, at = pattern:sub(i, i), t + (i - 1) * STEP
    if c == "x" then
      band.mute(at, STEP * 0.85, "D2")
    elseif c == "o" then
      k = k + 1
      band.ring(at, STEP * (k < #bar.ring and 1.8 or 3), bar.ring[k])
    end
  end
  hammer(band.metal, band.sub, t, b % 2 == 1 and 0.8 or 0.5)
  hiss(band.steam, t + 14 * STEP, STEP * 2, 0.5)
  drums(band, t, "press", last and not s.last, pattern)
  if b == 1 then
    band.drums:hat(t, 0.75, true)
  end
end

function PLAY.pour(band, t, b, s)
  local root = POUR_CHORDS[b]
  band.ring(t, STEP * 7.6, root)
  band.ring(t + 8 * STEP, STEP * 7.6, root)
  Kit.play(SING[b], t, STEP, function(at, dur, note)
    sing(band.lead, at, dur, note)
  end)
  for _, i in ipairs({ 4, 12 }) do -- the anvils on the backbeat
    clang(band.metal, t + i * STEP, freq("A4"), 0.08, 0.3)
  end
  drums(band, t, "pour", b == s.bars)
  if b == 1 or b == 5 then
    band.drums:hat(t, 0.6, true)
  end
end

function PLAY.vent(band, t, b, s)
  Kit.chugs(band, t, VENT[(b - 1) % #VENT + 1], STEP, "D2", "D1")
  hammer(band.metal, band.sub, t, 1)
  hiss(band.steam, t + 8 * STEP, BEAT * 1.5, b % 2 == 0 and 1 or 0.6)
  drums(band, t, "half", b == s.bars)
  if b == 1 or b == 5 then
    band.drums:hat(t, 0.75, true)
  end
end

-- The desk: each part's level, drive and filters.
local DESK = {
  { "rhythm", 0.42, drive = 13, lowpass = 2800 },
  { "chug", 0.62, drive = 15, lowpass = 1400 },
  { "bass", 0.5, drive = 3, lowpass = 420 },
  { "sub", 0.5, drive = 2.5, lowpass = 600 },
  { "lead", 0.34, drive = 2.2, lowpass = 6000 },
  { "drums", 0.85, drive = 1.6, highpass = 30 },
  { "verb", 0.26, lowpass = 1200 },
  { "metal", 0.5, highpass = 250 },
  { "steam", 0.35, highpass = 2500 },
}

-- The loop (press, pour, vent, press: ~53 s), and the shift starting (the
-- whistle, the furnace) once before it.
return Kit.theme(Theme, {
  bar = BAR, intro = INTRO, sections = SECTIONS, extras = { "steam" }, play = PLAY, desk = DESK,
})
