-- Shotgun's Bluff's theme, rendered by src/audio/synth.lua the way Karen's
-- is. A spaghetti-western standoff at 80 BPM in A minor, built up slowly: a
-- lone whistle over a twangy guitar rung once a bar; then the guitar gallops
-- (an eighth and two sixteenths a beat) with hooves clopping under it; then a
-- trumpet takes the tune over a choir and a snare. Last the standoff itself:
-- everything drops out but a tolling bell, a ticking woodblock and a low
-- string, until a howl and a snare roll go for their guns and it all starts
-- again. ~48 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 80
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16
local SLAP = 0.13 -- seconds: the twang's slapback, off the canyon wall
local SQUEEZE = 2 -- how hard the peaks are squeezed at the end, so it sits as loud as the other themes

local SHAPES = { -- a guitar chord, low string to high
  Am = { "A2", "E3", "A3", "C4", "E4" },
  Dm = { "D3", "A3", "D4", "F4" },
  E = { "E2", "B2", "E3", "G#3", "B3" },
  G = { "G2", "D3", "G3", "B3", "D4" },
  F = { "F2", "C3", "F3", "A3", "C4" },
}

-- The tunes: { note|false, sixteenths } a bar.
local WHISTLE = {
  { { "E5", 4 }, { "A5", 12 } },
  { { "G5", 2 }, { "A5", 2 }, { "B5", 2 }, { "C6", 2 }, { "B5", 8 } },
  { { "A5", 4 }, { "F5", 4 }, { "D5", 8 } },
  { { "E5", 16 } },
  { { "A4", 2 }, { "C5", 2 }, { "E5", 4 }, { "A5", 8 } },
  { { "G5", 4 }, { "D5", 4 }, { "B4", 8 } },
  { { "C5", 4 }, { "F5", 4 }, { "A5", 6 }, { "G5", 2 } },
  { { "G#5", 8 }, { "E5", 8 } },
}
local TRUMPET = {
  { { "D5", 4 }, { "F5", 4 }, { "A5", 8 } },
  { { "E5", 4 }, { "A5", 4 }, { "C6", 8 } },
  { { "B5", 4 }, { "G#5", 2 }, { "A5", 2 }, { "B5", 8 } },
  { { "A5", 12 }, { false, 4 } },
}

-- The build, four bars a part. `strum` rings the chord once a bar, `gallop`
-- rides it; `standoff` is the quiet before the draw.
local PARTS = {
  { chords = { "Am", "Am", "Dm", "E" }, strum = true, tune = WHISTLE, from = 1, voice = "whistle" },
  { chords = { "Am", "G", "F", "E" }, gallop = true, tune = WHISTLE, from = 5, voice = "whistle", hooves = true },
  { chords = { "Dm", "Am", "E", "Am" }, gallop = true, tune = TRUMPET, from = 1, voice = "trumpet", hooves = true,
    choir = true, snare = true },
  { chords = { "Am", "Am", "E", "E" }, standoff = true },
}

function Theme.duration()
  return #PARTS * 4 * BAR
end

-- Voices ---------------------------------------------------------------------

--- A twanged string with its slapback. Only a long ring gets the tremolo
--- arm (it is the costly part to render, and a short one never shows it).
local function twang(buf, t, note, amp, ring)
  local f = Synth.freq(note)
  local wobble = ring > 1 and 0.08 or 0
  for _, hit in ipairs({ { 0, 1 }, { SLAP, 0.35 } }) do
    buf:tone(t + hit[1], ring, f, { wave = "saw", amp = amp * hit[2], decay = ring / 2, sustain = 0, release = 0.05,
      vibRate = 5, vibDepth = wobble })
    buf:tone(t + hit[1], math.min(ring * 0.5, 0.3), f * 2, { wave = "square", amp = amp * hit[2] * 0.25,
      decay = 0.08, sustain = 0 })
  end
end

local function strum(buf, t, chord, amp, ring)
  for i, note in ipairs(SHAPES[chord]) do
    twang(buf, t + (i - 1) * 0.018, note, amp, ring) -- down the strings, not all at once
  end
end

local function sing(buf, t, events, voice)
  for _, ev in ipairs(events) do
    local note, len = ev[1], ev[2]
    if note then
      local dur, f = len * SIXTEENTH * 0.95, Synth.freq(note)
      if voice == "whistle" then
        buf:tone(t, dur, f, { wave = "sine", amp = 0.26, attack = 0.04, decay = 3, sustain = 0.8, release = 0.15,
          vibRate = 6, vibDepth = len >= 8 and 0.35 or 0.12 })
      else -- a mariachi trumpet: bright, with a fast shake on the long notes
        buf:tone(t, dur, f, { wave = "saw", amp = 0.26, attack = 0.03, decay = 2, sustain = 0.7, release = 0.1,
          vibRate = 6.5, vibDepth = len >= 8 and 0.25 or 0.06 })
        buf:tone(t, dur, f, { wave = "square", amp = 0.08, detune = 6, attack = 0.03, decay = 2, sustain = 0.7 })
      end
    end
    t = t + len * SIXTEENTH
  end
end

local function choir(buf, t, chord)
  local shape = SHAPES[chord]
  for i = #shape - 2, #shape do -- the top of the chord, an octave up: "aah"
    buf:tone(t, BAR, Synth.freq(shape[i]) * 2, { wave = "tri", amp = 0.14, attack = 0.5, decay = 4, sustain = 0.8,
      release = 0.5, vibRate = 4.5, vibDepth = 0.15 })
  end
end

local function woodblock(buf, t, amp)
  buf:tone(t, 0.03, 820, { wave = "sine", amp = amp, decay = 0.025, sustain = 0, release = 0.03 })
end

local function bell(buf, t, note)
  local f = Synth.freq(note)
  for _, partial in ipairs({ { 1, 0.4 }, { 2.76, 0.2 }, { 5.4, 0.1 } }) do -- a church bell's out-of-tune partials
    buf:tone(t, 2.5, f * partial[1], { wave = "sine", amp = partial[2], attack = 0.002, decay = 1.2, sustain = 0 })
  end
end

local function partBar(bufs, part, b, t)
  local chord = part.chords[b]
  local root = SHAPES[chord][1]
  if part.strum then
    strum(bufs.guitar, t, chord, 0.08, BAR * 0.9)
  elseif part.gallop then
    for beat = 0, 3 do
      local at = t + beat * SIXTEENTH * 4
      twang(bufs.guitar, at, root, 0.3, SIXTEENTH * 1.6)
      strum(bufs.guitar, at + SIXTEENTH * 2, chord, 0.09, SIXTEENTH * 0.8)
      strum(bufs.guitar, at + SIXTEENTH * 3, chord, 0.09, SIXTEENTH * 0.8)
      if part.hooves then
        woodblock(bufs.perc, at + SIXTEENTH * 2, 0.25)
        woodblock(bufs.perc, at + SIXTEENTH * 3, 0.18)
      end
    end
  end
  if part.tune then
    sing(bufs.lead, t, part.tune[part.from + b - 1], part.voice)
  end
  if part.choir then
    choir(bufs.pad, t, chord)
  end
  if part.snare then
    bufs.perc:snare(t + SIXTEENTH * 4, 0.35)
    bufs.perc:snare(t + SIXTEENTH * 12, 0.35)
  end
  if part.standoff then
    bell(bufs.pad, t, "A4")
    twang(bufs.guitar, t, root, 0.22, BAR * 0.8)
    bufs.pad:tone(t, BAR, Synth.freq(root) * 2, { wave = "saw", amp = 0.05, attack = 1, sustain = 0.9,
      vibRate = 7, vibDepth = 0.2 }) -- the low string, trembling
    for beat = 0, 3 do
      woodblock(bufs.perc, t + beat * SIXTEENTH * 4, beat == 0 and 0.3 or 0.2)
    end
    if b == 4 then -- the draw: a howl and a roll up to the top of the loop
      bufs.lead:sweep(t + SIXTEENTH * 2, 1.2, Synth.freq("E5"), Synth.freq("A5"), { wave = "tri", amp = 0.25,
        decay = 0.9 })
      for i = 8, 15 do
        bufs.perc:snare(t + i * SIXTEENTH, 0.12 + (i - 8) * 0.05)
        bufs.perc:snare(t + (i + 0.5) * SIXTEENTH, 0.1 + (i - 8) * 0.05)
      end
    end
  end
end

-- Render ---------------------------------------------------------------------

--- Renders the whole song. Returns a SoundData.
function Theme.render()
  local total = Theme.duration()
  local bufs = {}
  for _, name in ipairs({ "guitar", "lead", "pad", "perc" }) do
    bufs[name] = Synth.newBuffer(total + 0.5)
  end

  local t = 0
  for _, part in ipairs(PARTS) do
    for b = 1, #part.chords do
      partBar(bufs, part, b, t)
      t = t + BAR
    end
    bufs.perc:sweep(t - BAR * 4, 1.5, 70, 45, { amp = 0.7, decay = 0.6 }) -- a deep drum to open each part
  end

  bufs.guitar:drive(1.8)
  bufs.guitar:lowpass(2800)
  bufs.lead:lowpass(4000)
  bufs.pad:lowpass(2500)
  bufs.perc:highpass(35)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  bufs.guitar:mixInto(master, 0.6)
  bufs.lead:mixInto(master, 0.55)
  bufs.pad:mixInto(master, 0.45)
  bufs.perc:mixInto(master, 0.7)
  master:drive(SQUEEZE / math.max(master:peak(), 1e-6))
  return master:toSoundData(0.9)
end

return Theme
