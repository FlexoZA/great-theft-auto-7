-- Liar's Landing's theme (music.lua plays it once Max's intro screen goes),
-- rendered by src/audio/synth.lua like the Wreck's. A frozen port at dusk:
-- shanty metal, heavy and swaying, a sailors' song played on chugging
-- guitars and a squeezebox. Its own tunes; none of anybody else's.
--
-- It opens on the harbour: the ice creaking, a bell buoy, the foghorn
-- sounding twice over the bay, then a gantry's winch whining up and a
-- container slammed down into the riff. Then the stomp: low D chugged in a
-- rolling 6/8 like a deck in a swell, the kick on the one and the snare on
-- the four; the shanty, the squeezebox singing a sailors' tune in D minor
-- over open chords (Dm, C, Bb, A), a bell on the downbeats; the chorus, the
-- tune taken up an octave by a lead guitar with a harmony a third over it
-- and the drums driving every eighth; the cranes, half-time, the winches
-- whining, chains rattling and containers slamming down, the foghorn once;
-- and the stomp again into the top. 6/8 at 100 dotted crotchets, D minor:
-- the harbour ~5 s once (`renderIntro`), then the loop ~38 s (`render`).

local Kit = require("src.features.borderline.theme_kit")

local Theme = {}

local STEP = 0.1 -- seconds a sixteenth: an eighth is 0.2 s, a dotted crotchet 0.6 s (100 a minute)
local STEPS = 12 -- sixteenths to a bar of 6/8
local BAR = STEP * STEPS
local freq, clang = Kit.freq, Kit.clang

-- The stomp: a bar of sixteenths, `x` a chug on the low D, `o` the next of
-- the bar's `ring` notes rung out, `-` silence.
local STOMP = {
  { "x-xxx-x-xxx-" },
  { "x-xxx-x-o---", ring = { "F2" } },
  { "x-xxx-x-xxx-" },
  { "x-xxx-o-o-o-", ring = { "F2", "G2", "A2" } },
}

-- The shanty: a chord a bar, and the squeezebox's tune over it, eight bars
-- of { note|false, eighths }.
local SHANTY_CHORDS = { "D2", "C2", "A#1", "A1", "D2", "C2", "A1", "D2" }
local SHANTY = {
  { { "A4", 2 }, { "A4", 1 }, { "D5", 2 }, { "E5", 1 } },
  { { "F5", 3 }, { "E5", 1 }, { "D5", 1 }, { "C5", 1 } },
  { { "D5", 2 }, { "A#4", 1 }, { "F4", 2 }, { "G4", 1 } },
  { { "A4", 3 }, { "C#5", 3 } },
  { { "A4", 2 }, { "A4", 1 }, { "D5", 2 }, { "E5", 1 } },
  { { "F5", 2 }, { "G5", 1 }, { "A5", 2 }, { "G5", 1 } },
  { { "F5", 2 }, { "E5", 1 }, { "D5", 1 }, { "C#5", 2 } },
  { { "D5", 5 }, { false, 1 } },
}

-- The chorus: its chords, and the tune the lead guitar takes up.
local CHORUS_CHORDS = { "D2", "F2", "C2", "A1", "D2", "F2", "A1", "D2" }
local CHORUS = {
  { { "D5", 1 }, { "F5", 1 }, { "A5", 2 }, { "G5", 1 }, { "F5", 1 } },
  { { "C6", 3 }, { "A5", 2 }, { "F5", 1 } },
  { { "G5", 2 }, { "E5", 1 }, { "C5", 2 }, { "E5", 1 } },
  { { "C#5", 3 }, { "E5", 3 } },
  { { "D5", 1 }, { "F5", 1 }, { "A5", 2 }, { "D6", 2 } },
  { { "C6", 2 }, { "A5", 1 }, { "F5", 2 }, { "A5", 1 } },
  { { "G5", 2 }, { "F5", 1 }, { "E5", 2 }, { "C#5", 1 } },
  { { "D5", 5 }, { false, 1 } },
}
-- The harmony a third over it: how far up each of the tune's notes goes,
-- in the key (D minor, the C# raised).
local THIRD = { D = 3, E = 3, F = 4, G = 3, A = 3, ["A#"] = 4, C = 4, ["C#"] = 3 }

-- The cranes, half-time: chugs on the lowest D (x), silence (-).
local CRANES = { "x-----x-x---", "x-----x-xx--", "x-----x-x---", "x-x-x-xxxxxx" }

local INTRO = { { bars = 4, kind = "harbour" } }
local SECTIONS = {
  { bars = 8, kind = "stomp" },
  { bars = 8, kind = "shanty" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "cranes" },
  { bars = 4, kind = "stomp", last = true },
}

-- Voices ------------------------------------------------------------------------

--- The squeezebox: two reeds a little apart, a third an octave down, the
--- bellows' wobble on the held notes.
local function squeezebox(buf, t, dur, note, amp)
  local f = freq(note)
  local o = { wave = "square", amp = 0.07 * amp, attack = 0.04, decay = 0.8, sustain = 0.8, release = 0.06,
    vibRate = 6, vibDepth = dur > STEP * 3 and 0.12 or 0.03 }
  for _, d in ipairs({ -9, 9 }) do
    o.detune = d
    buf:tone(t, dur * 0.94, f, o)
  end
  o.wave, o.detune, o.amp = "tri", 0, 0.08 * amp
  buf:tone(t, dur * 0.94, f / 2, o)
end

--- One note of the lead guitar: picked, a little slide into it, a wide
--- vibrato on the long ones.
local function leadNote(buf, t, dur, f, amp)
  buf:sweep(t, 0.03, f * 0.94, f, { wave = "saw", amp = 0.08 * amp, decay = 0.04 })
  buf:tone(t + 0.02, dur * 0.95, f, { wave = "saw", amp = 0.11 * amp, attack = 0.01, decay = 0.6, sustain = 0.7,
    release = 0.05, vibRate = 6, vibDepth = dur > STEP * 3 and 0.3 or 0.02 })
end

--- The foghorn over the bay: two deep reeds a fifth apart, swelling, held,
--- dying away.
local function foghorn(buf, t, dur)
  for _, n in ipairs({ "D2", "A1" }) do
    for _, d in ipairs({ -6, 6 }) do
      buf:tone(t, dur, freq(n), { wave = "saw", amp = 0.12, attack = dur * 0.2, decay = dur * 2, sustain = 0.9,
        release = dur * 0.35, detune = d, vibRate = 2, vibDepth = 0.03 })
    end
  end
end

--- A gantry's winch: a motor whining up from `f0` to `f1`, with its gears' buzz.
local function winch(buf, t, dur, f0, f1)
  buf:sweep(t, dur, f0, f1, { wave = "square", amp = 0.05, decay = dur * 4 })
  buf:sweep(t, dur, f0 * 2.01, f1 * 2.01, { wave = "saw", amp = 0.03, decay = dur * 4 })
end

--- A chain running out over a drum: a rattle of links, `n` of them.
local function chain(buf, t, n, amp)
  for i = 0, n - 1 do
    local at = t + i * 0.035 + (i % 3) * 0.006
    buf:noiseBurst(at, 0.02, { amp = amp * (0.6 + 0.4 * ((i * 7) % 5) / 4), decay = 0.004 })
    buf:tone(at, 0.03, 1800 + (i % 4) * 230, { wave = "square", amp = amp * 0.15, attack = 0.001, decay = 0.01,
      sustain = 0 })
  end
end

--- A container slammed down on the quay: a boom, the box's steel ringing.
local function slam(buf, metal, t, amp)
  buf:sweep(t, 0.5, 90, 35, { wave = "sine", amp = 0.7 * amp, decay = 0.18 })
  buf:noiseBurst(t, 0.12, { amp = 0.5 * amp, decay = 0.03 })
  clang(metal, t, freq("D3"), 0.22 * amp, 0.9)
end

--- The sea ice creaking: a low groan bending down, a crackle along it.
local function creak(buf, t, dur)
  buf:sweep(t, dur, 140, 90, { wave = "saw", amp = 0.06, decay = dur })
  for i = 0, 7 do
    buf:noiseBurst(t + dur * i / 8 + (i % 2) * 0.02, 0.015, { amp = 0.12, decay = 0.003 })
  end
end

local function drumBar(buf, verb, t, style, fill, pattern)
  for i = 0, STEPS - 1 do
    local ti = t + i * STEP
    if fill and i >= 8 then
      buf:snare(ti, 0.55 + (i - 8) * 0.14) -- the roll into what comes next
      buf:kick(ti, 0.85)
    elseif style == "stomp" then -- the kick with the chugs, the snare on the four
      if pattern and pattern:sub(i + 1, i + 1) ~= "-" and i ~= 6 then
        buf:kick(ti, i == 0 and 1 or 0.65)
      end
      if i == 6 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
      end
      if i % 2 == 0 then
        buf:hat(ti, i % 6 == 0 and 0.26 or 0.14)
      end
    elseif style == "sway" then -- under the shanty: one and four, the hats rolling
      if i == 0 or i == 10 then
        buf:kick(ti, i == 0 and 1 or 0.6)
      elseif i == 6 then
        buf:snare(ti, 0.9)
        verb:snare(ti, 0.7)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.18, i == 4)
      end
    elseif style == "drive" then -- the chorus: the kick every eighth
      if i % 2 == 0 then
        buf:kick(ti, i % 6 == 0 and 1 or 0.6)
      end
      if i == 6 then
        buf:snare(ti, 1)
        verb:snare(ti, 0.9)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.22, i == 0)
      end
    elseif style == "half" then
      if i == 0 then
        buf:kick(ti, 1)
      elseif i == 6 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
      end
      if i % 6 == 0 then
        buf:hat(ti, 0.3, true)
      end
    end
  end
end

-- Render ----------------------------------------------------------------------

--- Plays `tune` (a bar of { note|false, eighths }) from `t` through `voice(t, dur, note)`.
local function play(tune, t, voice)
  Kit.play(tune, t, 2 * STEP, voice)
end

-- Bar `b` of section `s` from `t`, by the section's kind, into `band`.
local PLAY = {}

function PLAY.harbour(band, t, b)
  if b == 1 then -- the ice, the bell buoy, the foghorn over the bay...
    creak(band.metal, t + 0.1, 1.1)
    clang(band.metal, t + 0.3, freq("D5"), 0.12, 2.5)
    foghorn(band.horn, t + 0.5, 1.4)
  elseif b == 2 then
    creak(band.metal, t + 0.6, 0.9)
    clang(band.metal, t + 0.9, freq("D5"), 0.1, 2.5)
    foghorn(band.horn, t + 0.3, 1.6)
  elseif b == 3 then -- ...a winch whining up, a chain running out...
    winch(band.horn, t, BAR * 1.4, 70, 220)
    chain(band.metal, t + BAR * 0.5, 16, 0.25)
  else -- ...and a container slammed down into the riff
    slam(band.sub, band.metal, t + BAR * 0.5, 1)
    drumBar(band.drums, band.verb, t, "half", true)
  end
end

function PLAY.stomp(band, t, b, s)
  local last = b == s.bars
  local bar = (s.last and last) and STOMP[4] or STOMP[(b - 1) % #STOMP + 1]
  local pattern, k = bar[1], 0
  for i = 1, STEPS do
    local c = pattern:sub(i, i)
    local ti = t + (i - 1) * STEP
    if c == "x" then
      band.mute(ti, STEP * 0.85, "D2")
    elseif c == "o" then
      k = k + 1
      band.ring(ti, STEP * (k < #bar.ring and 1.9 or 3.8), bar.ring[k])
    end
  end
  drumBar(band.drums, band.verb, t, "stomp", last and not s.last, pattern)
  if b == 1 then
    band.drums:hat(t, 0.7, true) -- the crash on the way in
    slam(band.sub, band.metal, t, 0.6)
  elseif b % 2 == 1 then
    clang(band.metal, t + 6 * STEP, freq("A3"), 0.14, 0.5) -- a shackle on the backbeat
  end
end

function PLAY.shanty(band, t, b, s)
  local root = SHANTY_CHORDS[b]
  band.ring(t, STEP * 5.8, root)
  band.mute(t + 6 * STEP, STEP * 0.85, root)
  band.mute(t + 8 * STEP, STEP * 0.85, root)
  band.ring(t + 9 * STEP, STEP * 2.8, root)
  play(SHANTY[b], t, function(at, dur, note)
    squeezebox(band.box, at, dur, note, 1)
  end)
  if b % 2 == 1 then
    clang(band.metal, t, freq("D5"), 0.07, 1.5) -- the bell buoy
  end
  drumBar(band.drums, band.verb, t, "sway", b == s.bars)
  if b == 1 or b == 5 then
    band.drums:hat(t, 0.6, true)
  end
end

function PLAY.chorus(band, t, b, s)
  local root = CHORUS_CHORDS[b]
  band.ring(t, STEP * 5.8, root)
  band.ring(t + 6 * STEP, STEP * 5.8, root)
  play(CHORUS[b], t, function(at, dur, note)
    leadNote(band.lead, at, dur, freq(note), 1)
    leadNote(band.lead, at, dur, freq(note, THIRD[note:match("^%a#?")] or 3), 0.55)
    squeezebox(band.box, at, dur, note, 0.5)
  end)
  drumBar(band.drums, band.verb, t, "drive", b == s.bars)
  if b % 2 == 1 then
    band.drums:hat(t, 0.65, true)
  end
end

function PLAY.cranes(band, t, b, s) -- the winches, the chains, the boxes coming down
  Kit.chugs(band, t, CRANES[b], STEP, "D2", "D1")
  winch(band.horn, t, BAR * 0.9, b % 2 == 0 and 200 or 90, b % 2 == 0 and 90 or 200)
  chain(band.metal, t + 3 * STEP, 8, 0.2)
  slam(band.sub, band.metal, t + 6 * STEP, b == 4 and 1 or 0.7)
  drumBar(band.drums, band.verb, t, "half", b == s.bars)
  if b == 1 then
    band.drums:hat(t, 0.75, true)
    foghorn(band.horn, t, BAR * 1.6)
  end
end

-- The desk: each part's level, drive and filters.
local DESK = {
  { "rhythm", 0.42, drive = 11, lowpass = 3000 },
  { "chug", 0.55, drive = 12, lowpass = 1500 },
  { "bass", 0.45, drive = 3, lowpass = 450 },
  { "sub", 0.45, drive = 2.5, lowpass = 700 },
  { "lead", 0.34, drive = 4, lowpass = 4200 },
  { "box", 0.5, drive = 1.5, lowpass = 3500 },
  { "drums", 0.8, drive = 1.6, highpass = 30 },
  { "verb", 0.25, lowpass = 1300 },
  { "metal", 0.5, highpass = 150 },
  { "horn", 0.7, drive = 1.8, lowpass = 900 },
}

-- The loop (stomp, shanty, chorus, cranes, stomp: ~38 s), and the harbour (the ice, the foghorn,
-- the winch, the slam) once before it.
return Kit.theme(Theme, {
  bar = BAR, intro = INTRO, sections = SECTIONS, extras = { "box", "horn" }, play = PLAY, desk = DESK,
})
