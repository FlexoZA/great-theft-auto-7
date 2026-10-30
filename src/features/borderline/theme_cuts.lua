-- Thousand Papercuts' theme (music.lua plays it once Max's intro screen
-- goes), rendered by src/audio/synth.lua like the others. The road up the
-- cliff with everything coming up it behind you: urgent, driving speed
-- metal that never lets up, climbing a key every section the way you climb
-- the road. Its own riffs; none of anybody else's.
--
-- It opens on the alarm: an air-raid siren winding up, a clock ticking, a
-- heartbeat under it, and the chase out of it. The chase: low D chugged in
-- driving sixteenths with accents, the hi-hat ticking every sixteenth
-- like a clock running down, the snare on two and four; again a whole
-- step up, in E; the climb, the chorus, up in F#: rung chords (i, VI, VII,
-- i), a lead soaring over them on a double kick; the bridge, the band
-- dropping out to a heartbeat kick and the siren wailing over a low drone,
-- the clock still ticking; and back down to D as it comes round. 172 BPM:
-- the alarm ~3 s once (`renderIntro`), then the loop ~39 s (`render`).

local Synth = require("src.audio.synth")
local Kit = require("src.features.borderline.theme_kit")

local Theme = {}

local BEAT = 60 / 172 -- seconds a beat
local STEP = BEAT / 4 -- a sixteenth
local BAR = BEAT * 4
local freq = Kit.freq

local NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

--- Note `note` ("D2") `semis` semitones up, as a name.
local function up(note, semis)
  local m = Synth.midi(note) + (semis or 0)
  return NAMES[m % 12 + 1] .. (math.floor(m / 12) - 1)
end

-- The chase: a bar of sixteenths, `x` a chug on the root, `X` one
-- accented a fifth up, `o` the next of the bar's `ring` notes (semitones
-- over the root) rung out.
local CHASE = {
  { "xxxXxxxXxxXxxxXx" },
  { "xxxXxxxXxxXxo---", ring = { 3 } },
  { "xxxXxxxXxxXxxxXx" },
  { "xxxXxxxXo---o---", ring = { 5, 7 } },
}

-- The climb: chords a bar (semitones over the section's root), and the
-- lead's tune over it (degrees: semitones over the root an octave up).
local CLIMB_CHORDS = { 0, -4, -2, 0, 0, -4, -2, 3 }
local SOAR = {
  { { 7, 4 }, { 12, 4 }, { 10, 4 }, { 7, 4 } },
  { { 8, 8 }, { 7, 4 }, { 5, 4 } },
  { { 10, 4 }, { 12, 4 }, { 14, 8 } },
  { { 12, 12 }, { false, 4 } },
  { { 7, 4 }, { 12, 4 }, { 15, 4 }, { 14, 4 } },
  { { 12, 8 }, { 10, 4 }, { 8, 4 } },
  { { 10, 4 }, { 12, 4 }, { 14, 4 }, { 15, 4 } },
  { { 14, 12 }, { false, 4 } },
}

local INTRO = { { bars = 2, kind = "alarm" } }
local SECTIONS = {
  { bars = 8, kind = "chase", key = 0 }, -- D
  { bars = 8, kind = "chase", key = 2 }, -- E
  { bars = 8, kind = "climb", key = 4 }, -- F#
  { bars = 4, kind = "bridge", key = 0 }, -- back to D, short: no time to stop
}

-- Voices ------------------------------------------------------------------------

--- An air-raid siren winding up and down over `dur`, `amp` loud.
local function siren(buf, t, dur, amp)
  buf:sweep(t, dur * 0.5, 220, 620, { wave = "saw", amp = amp, decay = dur * 4 })
  buf:sweep(t + dur * 0.5, dur * 0.5, 620, 260, { wave = "saw", amp = amp, decay = dur * 4 })
end

--- A heartbeat: lub, then dub just after it.
local function heartbeat(sub, t, amp)
  sub:sweep(t, 0.16, 90, 40, { wave = "sine", amp = 0.8 * amp, decay = 0.07 })
  sub:sweep(t + 0.2, 0.14, 80, 38, { wave = "sine", amp = 0.6 * amp, decay = 0.06 })
end

--- The clock: a dry tick.
local function tick(metal, t, amp)
  metal:tone(t, 0.02, 3800, { wave = "square", amp = 0.04 * amp, decay = 0.006, sustain = 0 })
end

--- The lead soaring: slid into each note, held with a wide vibrato, an
--- octave under it on the long ones.
local function soar(buf, t, dur, f)
  buf:sweep(t, 0.04, f * 0.95, f, { wave = "square", amp = 0.07, decay = 0.06 })
  local o = { wave = "square", amp = 0.085, attack = 0.03, decay = 1, sustain = 0.8, release = 0.06, vibRate = 6,
    vibDepth = dur > STEP * 6 and 0.35 or 0.05 }
  buf:tone(t + 0.03, dur * 0.95, f, o)
  if dur > STEP * 6 then
    o.amp, o.vibDepth = 0.045, 0.15
    buf:tone(t + 0.03, dur * 0.95, f / 2, o)
  end
end

--- One bar of drums from `t`, `style`: "drive" (the kick on one, the and
--- of two and three, the snare on two and four), "double" (sixteenth kicks
--- under the backbeat), "heart" (no kit: the heartbeat on one); the clock
--- ticks every sixteenth through all of them; `fill` a roll over the last beat.
local function drums(band, t, style, fill)
  Kit.drumBar(band, t, STEP, fill and style ~= "heart", function(kit, room, i, at, _beat, sub)
    tick(band.metal, at, sub == 0 and 1.4 or 1)
    if style == "drive" then
      if i == 0 or i == 6 or i == 8 then
        kit:kick(at, i == 0 and 1 or 0.75)
      end
      if i == 4 or i == 12 then
        kit:snare(at, 1)
        room:snare(at, 0.8)
      end
    elseif style == "double" then
      kit:kick(at, sub == 0 and 0.9 or 0.55)
      if i == 4 or i == 12 then
        kit:snare(at, 1)
        room:snare(at, 0.8)
      end
      if sub == 0 then
        kit:hat(at, 0.24, i == 0)
      end
    elseif style == "heart" and i == 0 then
      heartbeat(band.sub, at, 1)
    end
  end)
end

-- Render ----------------------------------------------------------------------

-- Bar `b` of section `s` from `t`, by the section's kind, into `band`.
local PLAY = {}

function PLAY.alarm(band, t, b)
  siren(band.horn, t + (b - 1) * BAR * 0.5, BAR * 1.5, 0.06)
  heartbeat(band.sub, t, 0.8)
  heartbeat(band.sub, t + BAR / 2, 0.8)
  for i = 0, 15 do
    tick(band.metal, t + i * STEP, i % 4 == 0 and 1.4 or 1)
  end
  if b == 2 then
    drums(band, t, "drive", true)
  end
end

function PLAY.chase(band, t, b, s)
  local last = b == s.bars
  local bar = CHASE[(b - 1) % #CHASE + 1]
  local root = up("D2", s.key)
  local pattern, k = bar[1], 0
  for i = 1, 16 do
    local c, at = pattern:sub(i, i), t + (i - 1) * STEP
    if c == "x" then
      band.mute(at, STEP * 0.85, root)
    elseif c == "X" then
      band.mute(at, STEP * 0.85, up(root, 7))
    elseif c == "o" then
      k = k + 1
      band.ring(at, STEP * (k < #bar.ring and 3.6 or 4), up(root, bar.ring[k]))
    end
  end
  drums(band, t, "drive", last)
  if b == 1 then
    band.drums:hat(t, 0.75, true)
  end
end

function PLAY.climb(band, t, b, s)
  local root = up("D2", s.key)
  local chord = up(root, CLIMB_CHORDS[b])
  band.ring(t, STEP * 7.6, chord)
  band.ring(t + 8 * STEP, STEP * 7.6, chord)
  local top = freq(root) * 4 -- the lead sings two octaves over the root
  Kit.play(SOAR[b], t, STEP, function(at, dur, degree)
    soar(band.lead, at, dur, top * 2 ^ (degree / 12))
  end)
  drums(band, t, "double", b == s.bars)
  if b == 1 or b == 5 then
    band.drums:hat(t, 0.65, true)
  end
end

function PLAY.bridge(band, t, b, s)
  local root = up("D2", s.key)
  if b % 2 == 1 then -- a low drone under it, two bars at a time
    band.bass:tone(t, BAR * 2, freq(root) / 2, { wave = "saw", amp = 0.3, attack = 0.3, decay = 2, sustain = 0.7,
      release = 0.3 })
    siren(band.horn, t, BAR * 2, 0.07)
  end
  drums(band, t, "heart")
  if b >= s.bars - 1 then -- the band coming back in under the last two bars
    band.mute(t + 8 * STEP, STEP * 0.85, root)
    band.mute(t + 12 * STEP, STEP * 0.85, root)
    if b == s.bars then
      for i = 12, 15 do
        band.drums:snare(t + i * STEP, 0.6 + (i - 12) * 0.12)
        band.drums:kick(t + i * STEP, 0.8)
      end
    end
  end
end

-- The desk: each part's level, drive and filters.
local DESK = {
  { "rhythm", 0.56, drive = 14, lowpass = 3200 },
  { "chug", 0.78, drive = 15, lowpass = 1800 },
  { "bass", 0.45, drive = 3, lowpass = 420 },
  { "sub", 0.3, drive = 2.5, lowpass = 600 },
  { "lead", 0.48, drive = 2.3, lowpass = 6500 },
  { "drums", 0.62, drive = 1.8, highpass = 40 },
  { "verb", 0.24, lowpass = 1200 },
  { "metal", 0.4, highpass = 600 },
  { "horn", 0.5, drive = 1.6, lowpass = 3000 },
}

-- The loop (the chase in D, in E, the climb in F#, the bridge: ~39 s), and
-- the alarm (the siren, the clock, the heartbeat) once before it.
return Kit.theme(Theme, {
  bar = BAR, intro = INTRO, sections = SECTIONS, extras = { "horn" }, play = PLAY, desk = DESK,
})
