-- The Bragium Pit's theme (music.lua plays it once Max's intro screen goes),
-- rendered by src/audio/synth.lua like the others. An open-pit mine at
-- dusk: slow, heavy, drop-tuned groove metal, the Bragium ringing like
-- glass over it. Its own riffs; none of anybody else's.
--
-- It opens on a blast: the mine's siren wailing up and down, three
-- warning beeps, then the charge going off, rubble raining down, and the
-- riff out of the dust. Then the grind: low C chugged in a lurching,
-- syncopated riff, a pick sliding down the strings, the drums half-time
-- and huge; the crystals, a chime of glass bells picking out a tune in C
-- minor over rung-out chords (Cm, Ab, Bb, G), pickaxes clinking on the
-- offbeats; the drill, the chorus, a lead guitar wailing the tune over a
-- double kick while a rock drill whines up and down under it; the blasts,
-- half-time, a charge going off on the one and the three, the siren over
-- it; and the grind again into the top. 120 BPM in C minor: the blast
-- ~4 s once (`renderIntro`), then the loop ~64 s (`render`).

local Kit = require("src.features.borderline.theme_kit")

local Theme = {}

local BEAT = 0.5 -- seconds a beat: 120 a minute
local STEP = BEAT / 4 -- a sixteenth
local BAR = BEAT * 4
local freq, clang = Kit.freq, Kit.clang

-- The grind: a bar of sixteenths, `x` a chug on the low C, `/` a pick
-- slide down the strings, `o` the next of the bar's `ring` notes rung out.
local GRIND = {
  { "x--x--x-x-x--x--" },
  { "x--x--x-x-x-/---" },
  { "x--x--x-x-x--x--" },
  { "x--x--x-o--o--o-", ring = { "D#2", "F2", "F#2" } },
}

-- The crystals: a chord a bar, and the chime's tune over it, eight bars of
-- { note|false, sixteenths }.
local CRYSTAL_CHORDS = { "C2", "G#1", "A#1", "G1", "C2", "G#1", "A#1", "G1" }
local CHIME = {
  { { "G5", 2 }, { "C6", 2 }, { "D#6", 2 }, { "G6", 4 }, { "D#6", 2 }, { "D6", 4 } },
  { { "C6", 2 }, { "D#6", 2 }, { "G#5", 4 }, { "C6", 8 } },
  { { "D6", 2 }, { "F6", 2 }, { "A#5", 4 }, { "D6", 4 }, { "F6", 4 } },
  { { "D6", 4 }, { "B5", 4 }, { "G5", 8 } },
  { { "G5", 2 }, { "C6", 2 }, { "D#6", 2 }, { "G6", 4 }, { "G#6", 2 }, { "G6", 4 } },
  { { "F6", 2 }, { "D#6", 2 }, { "C6", 4 }, { "G#5", 8 } },
  { { "A#5", 2 }, { "D6", 2 }, { "F6", 4 }, { "D6", 2 }, { "A#5", 2 }, { "D6", 4 } },
  { { "B5", 4 }, { "D6", 4 }, { "G6", 8 } },
}

-- The drill, the chorus: its chords, and the lead's tune.
local DRILL_CHORDS = { "C2", "D#2", "A#1", "G1", "G#1", "D#2", "G1", "C2" }
local WAIL = {
  { { "C5", 6 }, { "D#5", 2 }, { "G5", 8 } },
  { { "G5", 4 }, { "G#5", 4 }, { "G5", 4 }, { "D#5", 4 } },
  { { "F5", 6 }, { "D5", 2 }, { "A#4", 8 } },
  { { "B4", 4 }, { "D5", 4 }, { "F5", 4 }, { "D5", 4 } },
  { { "C5", 6 }, { "D#5", 2 }, { "G#5", 8 } },
  { { "G5", 4 }, { "A#5", 4 }, { "G5", 4 }, { "D#5", 4 } },
  { { "D5", 6 }, { "B4", 2 }, { "D5", 4 }, { "F5", 4 } },
  { { "C5", 12 }, { false, 4 } },
}

-- The blasts, half-time: chugs on the lowest C (x), silence (-).
local BLASTS = { "x-------x-------", "x-------x---x---", "x-------x-------", "x---x---x-x-xxxx" }

local INTRO = { { bars = 2, kind = "blast" } }
local SECTIONS = {
  { bars = 8, kind = "grind" },
  { bars = 8, kind = "crystals" },
  { bars = 8, kind = "drill" },
  { bars = 4, kind = "blasts" },
  { bars = 4, kind = "grind", last = true },
}

-- Voices ------------------------------------------------------------------------

--- A glass bell (the Bragium ringing): a pure tone and a few bright
--- partials, struck and left to ring.
local function chime(buf, t, dur, note, amp)
  local f = freq(note)
  for i, k in ipairs({ 1, 2.76, 5.4 }) do
    buf:tone(t, dur + 0.6, f * k, { wave = i == 1 and "sine" or "tri", amp = 0.09 * amp / i, attack = 0.002,
      decay = (dur + 0.6) / i, sustain = 0 })
  end
end

--- The lead guitar wailing: bent up into each note, held with a wide
--- vibrato, a fifth under it on the long ones.
local function wail(buf, t, dur, note)
  local f = freq(note)
  buf:sweep(t, 0.08, f * 0.89, f, { wave = "square", amp = 0.07, decay = 0.1 })
  local o = { wave = "square", amp = 0.09, attack = 0.06, decay = 1, sustain = 0.8, release = 0.08, vibRate = 5,
    vibDepth = dur > STEP * 6 and 0.4 or 0.05 }
  buf:tone(t + 0.06, dur * 0.95, f, o)
  if dur > STEP * 6 then
    o.amp, o.vibDepth = 0.05, 0.2
    buf:tone(t + 0.06, dur * 0.95, f / 1.5, o)
  end
end

--- The mine's siren: a wail sweeping up and back down, `amp` loud.
local function siren(buf, t, dur, amp)
  buf:sweep(t, dur / 2, 300, 700, { wave = "square", amp = amp, decay = dur * 4 })
  buf:sweep(t + dur / 2, dur / 2, 700, 300, { wave = "square", amp = amp, decay = dur * 4 })
end

--- A charge going off: a deep boom, the rock cracking, rubble raining down
--- after it (`amp` how big).
local function blast(buf, metal, t, amp)
  buf:sweep(t, 1.2, 70, 22, { wave = "sine", amp = 0.9 * amp, decay = 0.45 })
  buf:noiseBurst(t, 0.6, { amp = 0.7 * amp, decay = 0.16 })
  for i = 1, 10 do
    local at = t + 0.15 + i * 0.07 + (i % 3) * 0.02
    metal:noiseBurst(at, 0.03, { amp = 0.12 * amp * (1 - i / 12), decay = 0.008 })
  end
end

--- A pickaxe on rock: a sharp tick and a short ring.
local function pick(metal, t, amp)
  clang(metal, t, freq("A5"), 0.06 * amp, 0.12)
end

--- A rock drill under it all: a whine wavering up and down, a rattle in it.
local function drill(buf, t, dur, up)
  local f0, f1 = up and 180 or 420, up and 420 or 180
  buf:sweep(t, dur, f0, f1, { wave = "saw", amp = 0.035, decay = dur * 3 })
  for a = t, t + dur - 0.05, 0.05 do
    buf:noiseBurst(a, 0.02, { amp = 0.03, decay = 0.006 })
  end
end

--- A pick slide down the strings: a scrape falling in pitch.
local function slide(buf, t)
  buf:sweep(t, STEP * 3, 1800, 300, { wave = "saw", amp = 0.12, decay = STEP * 2 })
  buf:noiseBurst(t, STEP * 3, { amp = 0.08, decay = STEP })
end

--- One bar of drums from `t`, `style`: "grind" (half-time, the kick
--- following the riff `pattern`, the snare on three), "lift" (the kick on
--- one and the and of two, the snare on two and four, ride on the beats),
--- "double" (sixteenth kicks under the snare's backbeat), "slow" (the kick
--- on one, the snare on three); `fill` a roll over the last beat.
local function drums(band, t, style, fill, pattern)
  local kit, room = band.drums, band.verb
  for i = 0, 15 do
    local at = t + i * STEP
    local beat, sub = math.floor(i / 4), i % 4
    if fill and beat == 3 then
      kit:snare(at, 0.6 + sub * 0.12)
      kit:kick(at, 0.8)
    elseif style == "grind" then
      if pattern and pattern:sub(i + 1, i + 1) == "x" and i ~= 8 then
        kit:kick(at, i == 0 and 1 or 0.7)
      end
      if i == 8 then
        kit:snare(at, 1)
        room:snare(at, 1)
      end
      if sub == 0 then
        kit:hat(at, 0.24, beat == 0)
      end
    elseif style == "lift" then
      if i == 0 or i == 6 or i == 10 then
        kit:kick(at, i == 0 and 1 or 0.75)
      end
      if beat % 2 == 1 and sub == 0 then
        kit:snare(at, 0.95)
        room:snare(at, 0.7)
      end
      if sub % 2 == 0 then
        kit:hat(at, sub == 0 and 0.22 or 0.12)
      end
    elseif style == "double" then
      kit:kick(at, sub == 0 and 1 or 0.55)
      if beat % 2 == 1 and sub == 0 then
        kit:snare(at, 1)
        room:snare(at, 0.9)
      end
      if sub == 0 then
        kit:hat(at, 0.26, beat == 0)
      end
    elseif style == "slow" then
      if i == 0 then
        kit:kick(at, 1)
      elseif i == 8 then
        kit:snare(at, 1)
        room:snare(at, 1)
      end
      if sub == 0 and beat % 2 == 0 then
        kit:hat(at, 0.32, true)
      end
    end
  end
end

-- Render ----------------------------------------------------------------------

--- The loop's length, seconds.
function Theme.duration()
  return Kit.duration(SECTIONS, BAR)
end

-- Bar `b` of section `s` from `t`, by the section's kind, into `band`.
local PLAY = {}

function PLAY.blast(band, t, b)
  if b == 1 then -- the siren, three beeps...
    siren(band.horn, t, BAR * 0.6, 0.3)
    for k = 0, 2 do
      band.horn:tone(t + BAR * 0.62 + k * 0.22, 0.1, 1200, { wave = "square", amp = 0.25, decay = 0.2, sustain = 1 })
    end
  else -- ...and the charge, the rubble, the riff out of the dust
    blast(band.sub, band.metal, t, 1)
    drums(band, t, "slow", true)
  end
end

function PLAY.grind(band, t, b, s)
  local last = b == s.bars
  local bar = (s.last and last) and GRIND[4] or GRIND[(b - 1) % #GRIND + 1]
  local pattern, k = bar[1], 0
  for i = 1, 16 do
    local c, at = pattern:sub(i, i), t + (i - 1) * STEP
    if c == "x" then
      band.mute(at, STEP * 0.9, "C2")
    elseif c == "/" then
      slide(band.metal, at)
    elseif c == "o" then
      k = k + 1
      band.ring(at, STEP * (k < #bar.ring and 2.8 or 4), bar.ring[k])
    end
  end
  drums(band, t, "grind", last and not s.last, pattern)
  if b == 1 then
    band.drums:hat(t, 0.75, true)
    blast(band.sub, band.metal, t, 0.5)
  end
end

function PLAY.crystals(band, t, b, s)
  local root = CRYSTAL_CHORDS[b]
  band.ring(t, STEP * 7.6, root)
  band.ring(t + 8 * STEP, STEP * 7.6, root)
  Kit.play(CHIME[b], t, STEP, function(at, dur, note)
    chime(band.lead, at, dur, note, 1)
  end)
  for _, i in ipairs({ 2, 6, 10, 14 }) do -- the pickaxes on the offbeats
    pick(band.metal, t + i * STEP, i % 4 == 2 and 1 or 0.6)
  end
  drums(band, t, "lift", b == s.bars)
  if b == 1 or b == 5 then
    band.drums:hat(t, 0.6, true)
  end
end

function PLAY.drill(band, t, b, s)
  local root = DRILL_CHORDS[b]
  for _, h in ipairs({ { 0, 6 }, { 6, 4 }, { 10, 6 } }) do
    band.ring(t + h[1] * STEP, h[2] * STEP * 0.96, root)
  end
  Kit.play(WAIL[b], t, STEP, function(at, dur, note)
    wail(band.lead, at, dur, note)
    chime(band.lead, at, dur * 0.5, note, 0.25)
  end)
  drill(band.horn, t, BAR, b % 2 == 1)
  drums(band, t, "double", b == s.bars)
  if b % 2 == 1 then
    band.drums:hat(t, 0.65, true)
  end
end

function PLAY.blasts(band, t, b, s)
  Kit.chugs(band, t, BLASTS[b], STEP, "C2", "C1")
  blast(band.sub, band.metal, t, b == 4 and 0.8 or 0.55)
  blast(band.sub, band.metal, t + 8 * STEP, 0.45)
  drums(band, t, "slow", b == s.bars)
  if b == 1 then
    band.drums:hat(t, 0.75, true)
    siren(band.horn, t, BAR * 2, 0.08)
  end
end

-- The desk: each part's level, drive and filters.
local DESK = {
  { "rhythm", 0.44, drive = 13, lowpass = 2600 },
  { "chug", 0.6, drive = 14, lowpass = 1300 },
  { "bass", 0.5, drive = 3, lowpass = 400 },
  { "sub", 0.5, drive = 2.5, lowpass = 600 },
  { "lead", 0.36, drive = 2.5, lowpass = 6000 },
  { "drums", 0.82, drive = 1.6, highpass = 30 },
  { "verb", 0.28, lowpass = 1200 },
  { "metal", 0.45, highpass = 200 },
  { "horn", 0.6, drive = 1.6, lowpass = 2400 },
}

--- Renders `sections`, with the siren and the drill. Returns a SoundData.
local function render(sections)
  return Kit.render(sections, BAR, { "horn" }, PLAY, DESK)
end

--- The loop (grind, crystals, drill, blasts, grind), ~64 s. Returns a SoundData.
function Theme.render()
  return render(SECTIONS)
end

--- The blast before it, once: the siren, the beeps, the charge. Returns a SoundData.
function Theme.renderIntro()
  return render(INTRO)
end

return Theme
