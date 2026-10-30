-- The Frozen Wreck's theme (music.lua plays it once Max's intro screen
-- goes), rendered by src/audio/synth.lua the way Eternal Mood's level themes
-- are. Freight-yard thrash: fast, cold and metallic, a train at full tilt.
-- Its own riffs; none of anybody else's.
--
-- It opens on the rails: wheels clacking over the joints, faster and
-- faster, a train horn swelling over them, and a snare roll into the riff.
-- Then the gallop: low E chugged eighth-two-sixteenths like wheels at speed
-- over a thrash beat, a chromatic climb at the end of every fourth bar; a
-- tremolo-picked riff in E Phrygian dominant (the flat second and the
-- major third give it the frontier twang), anvils ringing on the backbeat;
-- the chorus, open power chords E, C, D, B under a twangy slide lead with a
-- slapback echo; a half-time breakdown where the yard's metal rings out,
-- rails clanging and the wheels clacking; and the gallop again into the
-- top. 168 BPM in E minor: the rails ~3 s once (`renderIntro`), then the
-- loop ~46 s (`render`).

local Kit = require("src.features.borderline.theme_kit")

local Theme = {}

local BPM = 168
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16
local freq, clang = Kit.freq, Kit.clang

-- The gallop: a bar of sixteenths, `x` a chug on the low E, `o` the next of
-- the bar's `ring` notes rung out, `-` silence.
local GALLOP = {
  { "x-xxx-xxx-xxx-xx" },
  { "x-xxx-xxx-xxo---", ring = { "G2" } },
  { "x-xxx-xxx-xxx-xx" },
  { "x-xxx-xxo-o-o-o-", ring = { "G2", "A2", "A#2", "B2" } },
}

-- The tremolo riff: eighths, each note picked twice; Phrygian dominant.
local TREMOLO = {
  { "E2", "E2", "F2", "E2", "G#2", "A2", "G#2", "F2" },
  { "E2", "E2", "F2", "E2", "B2", "C3", "B2", "G#2" },
  { "E2", "E2", "F2", "E2", "G#2", "A2", "G#2", "F2" },
  { "E2", "F2", "G#2", "A2", "B2", "C3", "D3", "B2" },
}

-- The chorus: a chord a bar, hit on { sixteenth, length }.
local CHORUS = { "E2", "C2", "D2", "B1", "E2", "C2", "D2", "B1" }
local CHORUS_HITS = { { 0, 6 }, { 6, 4 }, { 10, 6 } }

-- The twang lead over the chorus: eight bars of { note|false, sixteenths }.
local LEAD = {
  { { "B4", 4 }, { "E5", 4 }, { "G5", 6 }, { "F#5", 2 } },
  { { "E5", 6 }, { "D5", 2 }, { "C5", 8 } },
  { { "D5", 4 }, { "F#5", 4 }, { "A5", 4 }, { "G5", 2 }, { "F#5", 2 } },
  { { "D#5", 12 }, { false, 4 } },
  { { "B4", 4 }, { "E5", 4 }, { "B5", 6 }, { "A5", 2 } },
  { { "G5", 4 }, { "E5", 4 }, { "C5", 4 }, { "E5", 4 } },
  { { "F#5", 4 }, { "A5", 4 }, { "D6", 4 }, { "C6", 2 }, { "A5", 2 } },
  { { "B5", 12 }, { false, 4 } },
}

-- The breakdown, half-time: chugs on the lowest E (x), silence (-).
local BREAKDOWN = { "x-----x---x-----", "x-----x---x-x---", "x-----x---x-----", "x-x-x-x-xxxxxxxx" }
-- The wheels over the rail joints: ka-ta, ka-ta.
local CLACKS = { 0, 3, 8, 11 }

local INTRO = { { bars = 2, kind = "rails" } }
local SECTIONS = {
  { bars = 8, kind = "gallop" },
  { bars = 8, kind = "tremolo" },
  { bars = 8, kind = "chorus" },
  { bars = 4, kind = "breakdown" },
  { bars = 4, kind = "gallop", last = true },
}

-- Voices ------------------------------------------------------------------------

--- A wheel over a rail joint: a click and a short metal knock.
local function clack(buf, t, amp)
  buf:noiseBurst(t, 0.03, { amp = amp, decay = 0.008 })
  buf:tone(t, 0.05, 900, { wave = "square", amp = amp * 0.3, attack = 0.001, decay = 0.02, sustain = 0 })
end

--- One note of the twang lead: a slide up into it, a saw and a square a
--- little apart, a wide vibrato on long notes, and its slapback echo.
local function leadNote(buf, t, dur, note, amp)
  amp = amp or 1
  local f = freq(note)
  local long = dur > SIXTEENTH * 5
  buf:sweep(t, 0.04, f * 0.92, f, { wave = "saw", amp = 0.1 * amp, decay = 0.05 })
  local o = { amp = 0.12 * amp, attack = 0.03, decay = 0.7, sustain = 0.75, release = 0.05,
    vibRate = 5.5, vibDepth = long and 0.35 or 0.04 }
  o.wave = "saw"
  buf:tone(t + 0.03, dur * 0.95, f, o)
  o.wave, o.amp, o.detune = "square", 0.07 * amp, 7
  buf:tone(t + 0.03, dur * 0.95, f, o)
end

--- The train horn: three reeds a little out of tune, swelling and dying.
local function horn(buf, t, dur)
  for _, n in ipairs({ "A3", "C#4", "E4" }) do
    for _, d in ipairs({ -10, 10 }) do
      buf:tone(t, dur, freq(n), { wave = "square", amp = 0.06, attack = dur * 0.25, decay = dur, sustain = 0.8,
        release = dur * 0.3, detune = d, vibRate = 3, vibDepth = 0.05 })
    end
  end
end

local function drumBar(buf, verb, t, style, fill, pattern)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      buf:snare(ti, 0.55 + (i - 12) * 0.12) -- the roll into what comes next
      buf:kick(ti, 0.85)
    elseif style == "gallop" then -- the kick with the gallop, snare on two and four
      if pattern and pattern:sub(i + 1, i + 1) ~= "-" then
        buf:kick(ti, i % 4 == 0 and 1 or 0.7)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 1)
        verb:snare(ti, 1)
      end
      if i % 2 == 0 then
        buf:hat(ti, i % 4 == 0 and 0.26 or 0.15)
      end
    elseif style == "skank" then -- thrash: kick on the beat, snare on the and
      if i % 4 == 0 then
        buf:kick(ti, 1)
      elseif i % 4 == 2 then
        buf:snare(ti, 0.9)
        verb:snare(ti, 0.6)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.2)
      end
    elseif style == "double" then
      buf:kick(ti, i % 4 == 0 and 1 or 0.6)
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

--- The loop's length, seconds.
function Theme.duration()
  return Kit.duration(SECTIONS, BAR)
end

--- Renders `sections`. Returns a SoundData.
local function render(sections)
  local total = Kit.duration(sections, BAR)
  local band = Kit.band(total, { "reeds" }) -- and the horn
  local sub, lead, drums, verb, metal, reeds = band.sub, band.lead, band.drums, band.verb, band.metal, band.reeds
  local mute, ring = band.mute, band.ring

  local t = 0
  for _, s in ipairs(sections) do
    for b = 1, s.bars do
      local last = b == s.bars
      if s.kind == "rails" then
        -- The wheels over the joints, closing up as the train picks up speed...
        if b == 1 then
          local gap, at = BAR * 0.22, t
          while at < t + 2 * BAR - SIXTEENTH * 4 do
            clack(metal, at, 0.35)
            clack(metal, at + gap * 0.3, 0.25)
            at = at + gap
            gap = math.max(SIXTEENTH * 2, gap * 0.86)
          end
          horn(reeds, t + BAR * 0.3, BAR * 1.2) -- ...the horn over them...
          clang(metal, t, freq("E3"), 0.3, 1.2)
        else
          drumBar(drums, verb, t, "half", true) -- ...and a roll into the riff
          sub:sweep(t + BAR * 0.5, BAR * 0.5, 60, 30, { wave = "sine", amp = 0.5, decay = BAR })
        end
      elseif s.kind == "gallop" then
        local bar = GALLOP[(b - 1) % #GALLOP + 1]
        if s.last and last then
          bar = GALLOP[4]
        end
        local pattern, k = bar[1], 0
        for i = 1, 16 do
          local c = pattern:sub(i, i)
          local ti = t + (i - 1) * SIXTEENTH
          if c == "x" then
            mute(ti, SIXTEENTH * 0.85, "E2")
          elseif c == "o" then
            k = k + 1
            ring(ti, SIXTEENTH * (k < #bar.ring and 1.9 or 3.8), bar.ring[k])
          end
        end
        drumBar(drums, verb, t, "gallop", last and not s.last, pattern)
        if b == 1 then
          drums:hat(t, 0.7, true) -- the crash on the way in
          drums:kick(t, 1)
          clang(metal, t, freq("E3"), 0.25, 0.9)
        end
      elseif s.kind == "tremolo" then
        local riff = TREMOLO[(b - 1) % #TREMOLO + 1]
        for e, note in ipairs(riff) do
          for p = 0, 1 do -- picked twice an eighth
            mute(t + ((e - 1) * 2 + p) * SIXTEENTH, SIXTEENTH * 0.9, note)
          end
        end
        clang(metal, t + 4 * SIXTEENTH, freq("B3"), 0.16, 0.5) -- anvils on the backbeat
        clang(metal, t + 12 * SIXTEENTH, freq(b % 2 == 0 and "C4" or "B3"), 0.16, 0.5)
        drumBar(drums, verb, t, "skank", last)
        if b == 1 or b == 5 then
          drums:hat(t, 0.65, true)
        end
      elseif s.kind == "chorus" then
        local root = CHORUS[b]
        for _, h in ipairs(CHORUS_HITS) do
          ring(t + h[1] * SIXTEENTH, h[2] * SIXTEENTH * 0.96, root)
        end
        local cursor = t
        for _, n in ipairs(LEAD[b]) do
          if n[1] then
            leadNote(lead, cursor, n[2] * SIXTEENTH, n[1])
            leadNote(lead, cursor + 0.11, n[2] * SIXTEENTH, n[1], 0.35) -- the slapback
          end
          cursor = cursor + n[2] * SIXTEENTH
        end
        drumBar(drums, verb, t, "double", last)
        if b % 2 == 1 then
          drums:hat(t, 0.65, true)
        end
      else -- the breakdown: the yard's metal rings out
        Kit.chugs(band, t, BREAKDOWN[b], SIXTEENTH, "E2", "E1")
        for _, i in ipairs(CLACKS) do
          clack(metal, t + i * SIXTEENTH, 0.3)
        end
        clang(metal, t + 8 * SIXTEENTH, freq(b % 2 == 0 and "F3" or "E3"), 0.3, 1.0) -- a rail struck
        drumBar(drums, verb, t, "half", last)
        if b == 1 then
          drums:hat(t, 0.75, true)
          clang(metal, t, freq("E2"), 0.35, 1.6)
        end
      end
      t = t + BAR
    end
  end

  return Kit.mixdown(band, total, {
    { "rhythm", 0.42, drive = 12, lowpass = 3200 },
    { "chug", 0.56, drive = 12, lowpass = 1700 },
    { "bass", 0.45, drive = 3, lowpass = 500 },
    { "sub", 0.4, drive = 3, lowpass = 800 },
    { "lead", 0.36, drive = 3, lowpass = 5000 },
    { "drums", 0.8, drive = 1.6, highpass = 30 },
    { "verb", 0.25, lowpass = 1400 },
    { "metal", 0.55, highpass = 200 },
    { "reeds", 0.7, drive = 2, lowpass = 2500 },
  })
end

--- The loop (gallop, tremolo riff, chorus, breakdown, gallop), ~46 s. Returns a SoundData.
function Theme.render()
  return render(SECTIONS)
end

--- The rails before it, once: the wheels, the horn, the roll. Returns a SoundData.
function Theme.renderIntro()
  return render(INTRO)
end

return Theme
