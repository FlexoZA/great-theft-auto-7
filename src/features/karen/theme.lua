-- Crazy Karen's theme: a stomping boss track rendered by src/audio/synth.lua,
-- the way the menu themes are. 150 BPM in D minor with the tritone leaning
-- on every bar; a bass and guitar chug underneath and, once it gets going,
-- a shrill two-note nag on top that never lets up. ~38 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 150
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

-- Notation: a bar is a list of { note|false, sixteenths, muted } summing to 16.
local function bar(...)
  local out = {}
  for _, group in ipairs({ ... }) do
    for _, ev in ipairs(group) do
      out[#out + 1] = ev
    end
  end
  return out
end
local function chug(n, count)
  local out = {}
  for _ = 1, count do
    out[#out + 1] = { n, 1, true }
  end
  return out
end
local function hit(n, len)
  return { { n, len, false } }
end
local function rest(len)
  return { { false, len, false } }
end

-- Riffs (guitar + bass) -----------------------------------------------------

local riffA = {
  bar(chug("D2", 6), hit("G#2", 2), chug("D2", 4), hit("F2", 2), hit("E2", 2)),
  bar(chug("D2", 6), hit("G#2", 2), chug("D2", 4), hit("A#2", 2), hit("A2", 2)),
  bar(chug("D2", 6), hit("G#2", 2), chug("D2", 4), hit("F2", 2), hit("E2", 2)),
  bar(hit("C3", 2), hit("A#2", 2), hit("A2", 4), hit("G#2", 4), hit("G2", 4)),
}

local riffB = {
  bar(hit("D2", 4), hit("D2", 4), hit("F2", 4), hit("G#2", 4)),
  bar(hit("D2", 4), hit("D2", 4), hit("A#2", 4), hit("A2", 4)),
  bar(hit("D2", 4), hit("D2", 4), hit("F2", 4), hit("G#2", 4)),
  bar(hit("G2", 4), hit("G#2", 4), hit("A2", 8)),
}

-- The nag --------------------------------------------------------------------

local nagA = {
  bar(hit("A5", 1), hit("G#5", 1), hit("A5", 1), hit("G#5", 1), hit("A5", 2), rest(2), hit("F5", 2), hit("E5", 2),
    hit("D5", 4)),
  bar(hit("A5", 1), hit("G#5", 1), hit("A5", 1), hit("G#5", 1), hit("A5", 2), rest(2), hit("A#5", 2), hit("A5", 2),
    hit("G#5", 4)),
  bar(hit("D6", 2), hit("C6", 2), hit("A#5", 2), hit("A5", 2), hit("G#5", 4), hit("A5", 4)),
  bar(hit("F5", 2), hit("E5", 2), hit("D5", 4), rest(2), hit("G#5", 2), hit("A5", 4)),
}

local nagB = {
  bar(hit("A5", 16)),
  bar(hit("G#5", 16)),
  bar(hit("F5", 8), hit("E5", 8)),
  bar(hit("D5", 8), hit("G#5", 4), hit("A5", 4)),
}

-- Arrangement -----------------------------------------------------------------

local SECTIONS = {
  { riff = riffA, drums = "stomp", repeats = 2 },
  { riff = riffB, drums = "double", repeats = 1 },
  { riff = riffA, drums = "stomp", repeats = 2, lead = nagA, harmonyOnRepeat = true, whine = true },
  { riff = riffB, drums = "double", repeats = 1, lead = nagB, whine = true },
}

-- Voices ------------------------------------------------------------------------

local function powerChord(buf, t, len, note, muted)
  local root = Synth.freq(note)
  local dur = len * SIXTEENTH * (muted and 0.85 or 0.98)
  local o = muted and { amp = 0.32, decay = 0.06, sustain = 0 } or { amp = 0.26, decay = 0.5, sustain = 0.4 }
  o.wave = "saw"
  o.detune = -9
  buf:tone(t, dur, root, o)
  o.detune = 9
  buf:tone(t, dur, root, o)
  o.detune = 0
  buf:tone(t, dur, root * 1.5, o)
  o.amp = o.amp * 0.5
  buf:tone(t, dur, root * 2, o)
end

local function bassNote(buf, t, len, note, muted)
  local dur = len * SIXTEENTH * (muted and 0.8 or 0.98)
  buf:tone(t, dur, Synth.freq(note) / 2, {
    wave = "square",
    amp = 0.5,
    decay = muted and 0.1 or 0.45,
    sustain = muted and 0 or 0.5,
  })
end

local function nagNote(buf, t, len, midi, amp)
  local dur = len * SIXTEENTH * 0.9
  buf:tone(t, dur, Synth.midiFreq(midi), {
    wave = "square",
    amp = amp,
    attack = 0.005,
    decay = 0.9,
    sustain = 0.75,
    release = 0.03,
    vibRate = 7,
    vibDepth = len >= 4 and 0.5 or 0.15,
  })
end

local function drumBar(buf, t, style, crash)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if style == "double" or i % 4 == 0 then
      buf:kick(ti, 1)
    end
    if i == 4 or i == 12 then
      buf:snare(ti, 0.9)
    end
    if i % 2 == 0 then
      buf:hat(ti, 0.22, i == 14)
    end
  end
  if crash then
    buf:hat(t, 0.55, true)
  end
end

-- Render ----------------------------------------------------------------------

local function playBar(guitar, bass, events, t)
  local cursor = t
  for _, ev in ipairs(events) do
    local note, len, muted = ev[1], ev[2], ev[3]
    if note then
      powerChord(guitar, cursor, len, note, muted)
      bassNote(bass, cursor, len, note, muted)
    end
    cursor = cursor + len * SIXTEENTH
  end
end

local function playLeadBar(lead, events, t, harmonised)
  local cursor = t
  for _, ev in ipairs(events) do
    local note, len = ev[1], ev[2]
    if note then
      nagNote(lead, cursor, len, Synth.midi(note), 0.26)
      if harmonised then
        nagNote(lead, cursor, len, Synth.midi(note) - 5, 0.16) -- a fourth below: sour
      end
    end
    cursor = cursor + len * SIXTEENTH
  end
end

function Theme.duration()
  local bars = 0
  for _, s in ipairs(SECTIONS) do
    bars = bars + #s.riff * s.repeats
  end
  return bars * BAR
end

--- Renders the whole song. Returns a SoundData.
function Theme.render()
  local total = Theme.duration()
  local guitar = Synth.newBuffer(total + 0.5)
  local bass = Synth.newBuffer(total + 0.5)
  local lead = Synth.newBuffer(total + 0.5)
  local drums = Synth.newBuffer(total + 0.5)

  local t = 0
  for _, section in ipairs(SECTIONS) do
    for rep = 1, section.repeats do
      for b, events in ipairs(section.riff) do
        playBar(guitar, bass, events, t)
        drumBar(drums, t, section.drums, b == 1 and rep == 1)
        if section.lead then
          playLeadBar(lead, section.lead[b], t, section.harmonyOnRepeat and rep > 1)
        end
        if section.whine and b == 1 and rep == 1 then
          lead:sweep(t, 0.6, 350, 1500, { wave = "saw", amp = 0.22, decay = 0.5 }) -- she winds up
        end
        t = t + BAR
      end
    end
  end

  guitar:drive(8)
  guitar:lowpass(3000)
  bass:drive(3)
  bass:lowpass(600)
  lead:drive(4)
  lead:lowpass(5200)
  drums:highpass(30)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  guitar:mixInto(master, 0.55)
  bass:mixInto(master, 0.45)
  lead:mixInto(master, 0.32)
  drums:mixInto(master, 0.75)
  return master:toSoundData(0.9)
end

return Theme
