-- Whispering Pines' theme (the alien hunt), rendered by src/audio/synth.lua
-- the way Karen's is. A night in the woods with the torch off: a cold pad, a
-- plucked arpeggio that comes back off the trees a dotted eighth later, a
-- theremin wobbling somewhere overhead and a lonely whistle on top, in A minor
-- at 96 BPM. Halfway through the toms come in, the bass starts to run and a
-- Phrygian B flat bares its teeth (something big is out there); then it all
-- sinks back into the fog it came from. ~60 s, loops: the echoes and the last
-- chord ring on into the top of the next time round.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 96
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16
local ECHO = SIXTEENTH * 3 -- the pluck's echo, a dotted eighth behind it
local ECHOES = { 0.45, 0.2 } -- how loud each one comes back
local SQUEEZE = 2 -- how hard the peaks are squeezed at the end, so it sits as loud as the other themes

-- Chords, low to high, and the arpeggio over them: eighth steps through the
-- chord's tones and the same an octave up (1-3 the chord, 4-6 above it).
local CHORDS = {
  Am = { "A3", "C4", "E4" },
  F = { "F3", "A3", "C4" },
  Dm = { "D3", "F3", "A3" },
  E = { "E3", "G#3", "B3" },
  G = { "G3", "B3", "D4" },
  Bb = { "A#3", "D4", "F4" },
}
local ARP = { 1, 3, 2, 4, 3, 5, 6, 4 }

-- The whistle: { note|false, sixteenths } a bar.
local WHISTLE = {
  { { "E5", 6 }, { "A5", 2 }, { "B5", 4 }, { "C6", 4 } },
  { { "B5", 4 }, { "A5", 4 }, { "F5", 8 } },
  { { "D5", 6 }, { "F5", 2 }, { "A5", 4 }, { "G5", 4 } },
  { { "G#5", 12 }, { false, 4 } },
  { { "E5", 6 }, { "A5", 2 }, { "B5", 4 }, { "C6", 4 } },
  { { "D6", 4 }, { "C6", 4 }, { "A5", 8 } },
  { { "B5", 4 }, { "G#5", 4 }, { "E5", 4 }, { "F5", 4 } },
  { { "E5", 12 }, { false, 4 } },
}
local FADING = { -- what is left of it as the fog comes back
  { { "E5", 6 }, { "A5", 2 }, { "B5", 8 } },
  { { "C6", 8 }, { "B5", 8 } },
  { { "A5", 16 } },
  { { false, 16 } },
}

-- Sixteenth steps of the hunt's drums: k kick, t tom, s snare (low and dry).
local HUNT_DRUMS = "k--tk-t-s-kt-tt-"

-- The song: a chord a bar. `theremin` wobbles over the bar, `hunt` brings in
-- the drums, the running bass and the growl.
local SECTIONS = {
  { chords = { "Am", "F", "Am", "E" }, theremin = { [1] = "E5", [3] = "C5" } },
  { chords = { "Am", "F", "Dm", "E", "Am", "F", "E", "E" }, lead = WHISTLE, heartbeat = true },
  { chords = { "Am", "Am", "F", "G", "Am", "Am", "Bb", "E" }, hunt = true },
  { chords = { "Am", "F", "Dm", "E" }, lead = FADING, heartbeat = true },
}

-- Voices ---------------------------------------------------------------------

function Theme.duration()
  local bars = 0
  for _, s in ipairs(SECTIONS) do
    bars = bars + #s.chords
  end
  return bars * BAR
end

local function pad(buf, t, chord)
  for _, note in ipairs(CHORDS[chord]) do
    for _, cents in ipairs({ -7, 7 }) do
      buf:tone(t, BAR, Synth.freq(note), {
        wave = "saw", amp = 0.12, detune = cents, attack = 0.6, decay = 4, sustain = 0.8, release = 0.6,
      })
    end
  end
end

local function arpeggio(plucks, t, chord, loud, total)
  local tones = {}
  for i, note in ipairs(CHORDS[chord]) do
    tones[i] = Synth.midi(note) + 12
    tones[i + 3] = tones[i] + 12
  end
  for step, which in ipairs(ARP) do
    local at = t + (step - 1) * SIXTEENTH * 2
    local f = Synth.midiFreq(tones[which])
    plucks:tone(at, SIXTEENTH * 1.5, f, { wave = "tri", amp = loud, decay = 0.22, sustain = 0, release = 0.08 })
    for n, gain in ipairs(ECHOES) do
      local back = (at + ECHO * n) % total -- an echo off the end comes back round the top
      plucks:tone(back, SIXTEENTH * 1.5, f, { wave = "tri", amp = loud * gain, decay = 0.2, sustain = 0 })
    end
  end
end

local function whistle(buf, t, events)
  for _, ev in ipairs(events) do
    local note, len = ev[1], ev[2]
    if note then
      buf:tone(t, len * SIXTEENTH * 0.92, Synth.freq(note), {
        wave = "sine", amp = 0.3, attack = 0.06, decay = 2, sustain = 0.7, release = 0.12,
        vibRate = 5.5, vibDepth = len >= 6 and 0.3 or 0.1,
      })
    end
    t = t + len * SIXTEENTH
  end
end

local function huntBar(drums, bass, growl, t, chord)
  for i = 1, #HUNT_DRUMS do
    local at = t + (i - 1) * SIXTEENTH
    local c = HUNT_DRUMS:sub(i, i)
    if c == "k" then
      drums:kick(at, 0.9)
    elseif c == "t" then
      drums:sweep(at, 0.3, i > 12 and 110 or 160, 60, { amp = 0.6, decay = 0.12 })
    elseif c == "s" then
      drums:snare(at, 0.45)
    end
  end
  local root = Synth.freq(CHORDS[chord][1]) / 4
  for i = 0, 7 do -- the bass runs in eighths, the fifth on the offbeats of the second half
    local f = (i >= 4 and i % 2 == 1) and root * 1.5 or root
    bass:tone(t + i * SIXTEENTH * 2, SIXTEENTH * 1.6, f, { wave = "square", amp = 0.4, decay = 0.15, sustain = 0.3 })
  end
  if chord == "Bb" or chord == "E" then -- the low growl, a semitone off
    growl:tone(t, BAR * 0.9, root * 2, {
      wave = "saw", amp = 0.3, attack = 0.3, sustain = 0.9, vibRate = 3, vibDepth = 0.4,
    })
    growl:tone(t, BAR * 0.9, root * 2 * 2 ^ (1 / 12), { wave = "saw", amp = 0.2, attack = 0.5, sustain = 0.9 })
  end
end

-- Render ---------------------------------------------------------------------

--- Renders the whole song. Returns a SoundData.
function Theme.render()
  local total = Theme.duration()
  local tail = 1.5 -- seconds the last chord rings past the end, folded back onto the top
  local pads = Synth.newBuffer(total + tail)
  local plucks = Synth.newBuffer(total + tail)
  local lead = Synth.newBuffer(total + tail)
  local bass = Synth.newBuffer(total + tail)
  local drums = Synth.newBuffer(total + tail)
  local growl = Synth.newBuffer(total + tail)

  local t = 0
  for _, section in ipairs(SECTIONS) do
    for b, chord in ipairs(section.chords) do
      pad(pads, t, chord)
      arpeggio(plucks, t, chord, section.hunt and 0.3 or 0.22, total)
      if section.lead then
        whistle(lead, t, section.lead[b])
      end
      local wobble = section.theremin and section.theremin[b]
      if wobble then
        lead:tone(t + SIXTEENTH * 2, BAR * 1.4, Synth.freq(wobble), {
          wave = "sine", amp = 0.14, attack = 1.2, decay = 3, sustain = 0.6, release = 0.8, vibRate = 6, vibDepth = 0.7,
        })
      end
      if section.heartbeat then -- a slow heartbeat, felt more than heard
        drums:kick(t, 0.45)
        drums:kick(t + SIXTEENTH * 3, 0.3)
      end
      if section.hunt then
        huntBar(drums, bass, growl, t, chord)
      end
      t = t + BAR
    end
  end

  pads:lowpass(900)
  plucks:lowpass(3500)
  lead:lowpass(4500)
  bass:drive(2)
  bass:lowpass(500)
  growl:drive(4)
  growl:lowpass(700)
  drums:highpass(30)

  local mix = Synth.newBuffer(total + tail)
  pads:mixInto(mix, 0.5)
  plucks:mixInto(mix, 0.6)
  lead:mixInto(mix, 0.55)
  bass:mixInto(mix, 0.45)
  growl:mixInto(mix, 0.3)
  drums:mixInto(mix, 0.7)
  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  mix:mixInto(master, 1)
  for i = 0, math.min(mix.n - master.n, master.n) - 1 do
    master.data[i] = master.data[i] + mix.data[master.n + i]
  end
  master:drive(SQUEEZE / math.max(master:peak(), 1e-6))
  return master:toSoundData(0.9)
end

return Theme
