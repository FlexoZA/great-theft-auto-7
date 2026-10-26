-- The Bunker's theme (music.lua plays it once Max's intro screen goes),
-- rendered by src/audio/synth.lua like the others. The last fight, on the
-- roof above the clouds: a final-boss epic, a choir and a church organ
-- under heavy riffs, war drums marching, a hero's tune in a minor key and
-- a last-stand solo. Its own tunes; none of anybody else's.
--
-- It opens on a bell tolling while the organ swells. The march: war drums
-- pounding a slow tattoo, a choir singing long chords (Am, F, G, Em) over
-- a chord rung out and chugged under it; the anthem, the chorus, the hero's tune in A minor on a
-- lead over the organ and rung chords (Am, F, C, G), the double kick
-- under it; the last stand, a solo racing over Am, Dm, E, Am; and the
-- march again into the top. 104 BPM in A minor: the bell ~5 s once
-- (`renderIntro`), then the loop ~74 s (`render`).

local Kit = require("src.features.borderline.theme_kit")

local Theme = {}

local BEAT = 60 / 104 -- seconds a beat
local STEP = BEAT / 4 -- a sixteenth
local BAR = BEAT * 4
local freq, clang = Kit.freq, Kit.clang

-- The march: chords a bar for the choir (their notes), and the chugs under it.
local MARCH_CHOIR = {
  { "A3", "C4", "E4" }, { "F3", "A3", "C4" }, { "G3", "B3", "D4" }, { "E3", "G3", "B3" },
}
local MARCH_ROOTS = { "A1", "F1", "G1", "E1" }
local MARCH = "x---x-x-x---x-x-"

-- The anthem: chords a bar (for the organ and the guitars), and the tune.
local ANTHEM_ORGAN = {
  { "A3", "C4", "E4" }, { "F3", "A3", "C4" }, { "C4", "E4", "G4" }, { "G3", "B3", "D4" },
  { "A3", "C4", "E4" }, { "F3", "A3", "C4" }, { "E3", "G#3", "B3" }, { "A3", "C4", "E4" },
}
local ANTHEM_ROOTS = { "A1", "F1", "C2", "G1", "A1", "F1", "E1", "A1" }
local HERO = {
  { { "E5", 4 }, { "A5", 4 }, { "C6", 6 }, { "B5", 2 } },
  { { "A5", 8 }, { "F5", 8 } },
  { { "G5", 4 }, { "C6", 4 }, { "E6", 6 }, { "D6", 2 } },
  { { "B5", 12 }, { false, 4 } },
  { { "E5", 4 }, { "A5", 4 }, { "C6", 4 }, { "E6", 4 } },
  { { "F6", 6 }, { "E6", 2 }, { "C6", 8 } },
  { { "B5", 4 }, { "G#5", 4 }, { "E5", 4 }, { "B5", 4 } },
  { { "A5", 12 }, { false, 4 } },
}

-- The last stand: chords a bar, and the solo's runs (a note a sixteenth).
local STAND_ROOTS = { "A1", "D2", "E1", "A1", "A1", "D2", "E1", "A1" }
local RUNS = {
  { "A4", "C5", "E5", "A5", "E5", "C5", "A4", "C5", "E5", "A5", "C6", "A5", "E5", "C5", "E5", "A5" },
  { "D5", "F5", "A5", "D6", "A5", "F5", "D5", "F5", "A5", "D6", "F6", "D6", "A5", "F5", "A5", "D6" },
  { "E5", "G#5", "B5", "E6", "B5", "G#5", "E5", "G#5", "B5", "E6", "G#6", "E6", "B5", "G#5", "B5", "E6" },
  { "A5", "E5", "C5", "A4", "C5", "E5", "A5", "C6", "E6", "C6", "A5", "E5", "A5", "C6", "E6", "A6" },
}

local INTRO = { { bars = 2, kind = "toll" } }
local SECTIONS = {
  { bars = 8, kind = "march" },
  { bars = 8, kind = "anthem" },
  { bars = 8, kind = "stand" },
  { bars = 8, kind = "march", last = true },
}

-- Voices ------------------------------------------------------------------------

--- The organ: a chord held, each note its pipes (the note and its
--- harmonics, softer going up), swelling in.
local function organ(buf, t, dur, notes, amp)
  for _, note in ipairs(notes) do
    local f = freq(note)
    for i, k in ipairs({ 1, 2, 3, 4 }) do
      buf:tone(t, dur, f * k, { wave = "sine", amp = 0.05 * amp / i, attack = 0.12, decay = dur, sustain = 0.9,
        release = 0.15 })
    end
  end
end

--- The choir: a chord sung, each note two voices a little apart with a
--- slow vibrato, breathing in.
local function choir(buf, t, dur, notes)
  for _, note in ipairs(notes) do
    local f = freq(note)
    for _, d in ipairs({ -7, 7 }) do
      buf:tone(t, dur, f, { wave = "tri", amp = 0.045, attack = 0.5, decay = dur, sustain = 0.85, release = 0.4,
        detune = d, vibRate = 4.5, vibDepth = 0.25 })
    end
  end
end

--- A war drum: a deep skin struck, the boom falling.
local function warDrum(sub, drums, t, amp)
  sub:sweep(t, 0.4, 110, 48, { wave = "sine", amp = 0.7 * amp, decay = 0.18 })
  drums:noiseBurst(t, 0.06, { amp = 0.25 * amp, decay = 0.02 })
end

--- The lead: slid into each note, held with a vibrato, an octave under it
--- on the long ones.
local function lead(buf, t, dur, note)
  local f = freq(note)
  buf:sweep(t, 0.05, f * 0.94, f, { wave = "square", amp = 0.07, decay = 0.08 })
  local o = { wave = "square", amp = 0.085, attack = 0.04, decay = 1, sustain = 0.8, release = 0.08, vibRate = 5.5,
    vibDepth = dur > STEP * 5 and 0.35 or 0.05 }
  buf:tone(t + 0.04, dur * 0.95, f, o)
  if dur > STEP * 5 then
    o.amp, o.vibDepth = 0.045, 0.15
    buf:tone(t + 0.04, dur * 0.95, f / 2, o)
  end
end

--- One bar of drums from `t`, `style`: "march" (the war drums' tattoo,
--- the snare on three), "double" (sixteenth kicks under the backbeat);
--- `fill` a roll over the last beat.
local function drums(band, t, style, fill)
  Kit.drumBar(band, t, STEP, fill, function(kit, room, i, at, beat, sub)
    if style == "march" then
      if i == 0 or i == 2 or i == 8 or i == 12 then
        warDrum(band.sub, kit, at, i == 0 and 1 or 0.7)
      end
      if i == 8 then
        kit:snare(at, 1)
        room:snare(at, 1)
      end
      if sub == 0 then
        kit:hat(at, 0.2, beat == 0)
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
    end
  end)
end

-- Render ----------------------------------------------------------------------

-- Bar `b` of section `s` from `t`, by the section's kind, into `band`.
local PLAY = {}

function PLAY.toll(band, t, b)
  clang(band.metal, t, freq("A2"), 0.3, 2.2) -- the bell
  clang(band.metal, t + BAR / 2, freq("E2"), 0.22, 2)
  organ(band.organ, t, BAR * 0.98, { "A2", "E3", "A3", "C4" }, b == 1 and 0.6 or 1)
  if b == 2 then
    drums(band, t, "march", true)
  end
end

function PLAY.march(band, t, b, s)
  local k = (b - 1) % 4 + 1
  choir(band.choir, t, BAR, MARCH_CHOIR[k])
  local root = MARCH_ROOTS[k]
  band.ring(t, BAR * 0.95, root) -- a chord rung out under it all
  for i = 1, 16 do
    if MARCH:sub(i, i) == "x" then
      band.mute(t + (i - 1) * STEP, STEP * 0.85, root)
    end
  end
  drums(band, t, "march", b == s.bars and not s.last)
  if b == 1 then
    band.drums:hat(t, 0.7, true)
  end
end

function PLAY.anthem(band, t, b, s)
  organ(band.organ, t, BAR, ANTHEM_ORGAN[b], 1)
  local root = ANTHEM_ROOTS[b]
  band.ring(t, STEP * 7.6, root)
  band.ring(t + 8 * STEP, STEP * 7.6, root)
  Kit.play(HERO[b], t, STEP, function(at, dur, note)
    lead(band.lead, at, dur, note)
  end)
  drums(band, t, "double", b == s.bars)
  if b == 1 or b == 5 then
    band.drums:hat(t, 0.65, true)
  end
end

function PLAY.stand(band, t, b, s)
  local root = STAND_ROOTS[b]
  band.ring(t, STEP * 7.6, root)
  band.ring(t + 8 * STEP, STEP * 7.6, root)
  local run = RUNS[(b - 1) % #RUNS + 1]
  for i, note in ipairs(run) do
    band.lead:tone(t + (i - 1) * STEP, STEP, freq(note), { wave = "square", amp = 0.075, attack = 0.003,
      decay = STEP * 1.5, sustain = 0.5, release = 0.01 })
  end
  organ(band.organ, t, BAR, { root:sub(1, -2) .. "3" }, 0.5)
  drums(band, t, "double", b == s.bars)
  if b == 1 or b == 5 then
    band.drums:hat(t, 0.65, true)
  end
end

-- The desk: each part's level, drive and filters.
local DESK = {
  { "rhythm", 0.55, drive = 13, lowpass = 3000 },
  { "chug", 0.78, drive = 15, lowpass = 1700 },
  { "bass", 0.45, drive = 3, lowpass = 420 },
  { "sub", 0.22, drive = 2, lowpass = 500 },
  { "lead", 0.46, drive = 2.3, lowpass = 6500 },
  { "drums", 0.55, drive = 1.8, highpass = 40 },
  { "verb", 0.26, lowpass = 1200 },
  { "metal", 0.45, highpass = 120 },
  { "organ", 0.5, drive = 1.3, lowpass = 5000 },
  { "choir", 0.75, lowpass = 3500 },
}

-- The loop (march, anthem, last stand, march: ~74 s), and the bell and
-- the organ once before it.
return Kit.theme(Theme, {
  bar = BAR, intro = INTRO, sections = SECTIONS, extras = { "organ", "choir" }, play = PLAY, desk = DESK,
})
