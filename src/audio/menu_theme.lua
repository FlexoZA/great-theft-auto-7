-- "Great Theft Auto 7" menu theme: retro metal, rendered by src/audio/synth.lua.
-- 168 BPM in E minor. Gallop riff, a double-kick section, then the lead comes
-- in over the gallop (harmonised the second time) and rides out over the
-- double-kick riff. ~34 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 168
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

-- Notation helpers: a bar is a list of { note|false, sixteenths, muted } summing to 16.
local function bar(...)
  local out = {}
  for _, group in ipairs({ ... }) do
    for _, ev in ipairs(group) do
      out[#out + 1] = ev
    end
  end
  return out
end
local function gallop(n) -- eighth + two sixteenths, palm muted
  return { { n, 2, true }, { n, 1, true }, { n, 1, true } }
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
  bar(gallop("E2"), gallop("E2"), gallop("E2"), gallop("E2")),
  bar(gallop("E2"), gallop("E2"), gallop("G2"), gallop("A2")),
  bar(gallop("E2"), gallop("E2"), gallop("E2"), gallop("E2")),
  bar(hit("C3", 4), hit("B2", 4), gallop("A2"), gallop("G2")),
}

local riffB = {
  bar(chug("E2", 8), hit("G2", 2), hit("A2", 2), hit("B2", 2), hit("A2", 2)),
  bar(chug("E2", 8), hit("C3", 2), hit("B2", 2), hit("A2", 2), hit("G2", 2)),
  bar(chug("E2", 8), hit("G2", 2), hit("A2", 2), hit("B2", 2), hit("D3", 2)),
  bar(hit("D3", 4), hit("C3", 4), hit("B2", 8)),
}

-- Lead ------------------------------------------------------------------------

local leadA = {
  bar(hit("E4", 2), hit("G4", 2), hit("A4", 4), hit("B4", 4), hit("A4", 2), hit("G4", 2)),
  bar(hit("E4", 4), rest(2), hit("D4", 2), hit("E4", 8)),
  bar(hit("G4", 2), hit("A4", 2), hit("B4", 4), hit("D5", 4), hit("B4", 2), hit("A4", 2)),
  bar(hit("G4", 4), hit("B4", 4), hit("E5", 8)),
}

local leadB = {
  bar(hit("B4", 16)),
  bar(hit("A4", 16)),
  bar(hit("G4", 16)),
  bar(hit("F#4", 8), hit("E4", 8)),
}

-- Diatonic third above, in E natural minor.
local THIRD = { E = 3, ["F#"] = 3, G = 4, A = 3, B = 3, C = 4, D = 4 }
local function harmony(note)
  local letter = note:match("^([A-G]#?)")
  return Synth.midi(note) + (THIRD[letter] or 3)
end

-- Arrangement -----------------------------------------------------------------

local SECTIONS = {
  { riff = riffA, drums = "gallop", repeats = 2 },
  { riff = riffB, drums = "double", repeats = 1 },
  { riff = riffA, drums = "gallop", repeats = 2, lead = leadA, harmonyOnRepeat = true },
  { riff = riffB, drums = "double", repeats = 1, lead = leadB },
}

-- Voices ------------------------------------------------------------------------

local function powerChord(buf, t, len, note, muted)
  local root = Synth.freq(note)
  local dur = len * SIXTEENTH * (muted and 0.9 or 0.98)
  local o = muted and { amp = 0.30, decay = 0.07, sustain = 0 } or { amp = 0.26, decay = 0.6, sustain = 0.35 }
  o.wave = "saw"
  o.detune = -7
  buf:tone(t, dur, root, o)
  o.detune = 7
  buf:tone(t, dur, root, o)
  o.detune = 0
  buf:tone(t, dur, root * 1.5, o) -- fifth
  o.amp = o.amp * 0.5
  buf:tone(t, dur, root * 2, o) -- octave
end

local function bassNote(buf, t, len, note, muted)
  local dur = len * SIXTEENTH * (muted and 0.85 or 0.98)
  buf:tone(t, dur, Synth.freq(note) / 2, {
    wave = "tri",
    amp = 0.6,
    decay = muted and 0.12 or 0.5,
    sustain = muted and 0 or 0.5,
  })
end

local function leadNote(buf, t, len, midi, amp)
  local dur = len * SIXTEENTH * 0.95
  local long = len >= 4
  buf:tone(t, dur, Synth.midiFreq(midi), {
    wave = "square",
    amp = amp,
    attack = 0.01,
    decay = 1.2,
    sustain = 0.7,
    release = 0.05,
    vibRate = 5.5,
    vibDepth = long and 0.3 or 0,
  })
end

local function drumBar(buf, t, style, crash)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    local inGroup = i % 4
    local kick = style == "double" or inGroup == 0 or inGroup == 2 or inGroup == 3
    if kick then
      buf:kick(ti, 0.9)
    end
    if i == 4 or i == 12 then
      buf:snare(ti, 0.8)
    end
    if i % 2 == 0 then
      buf:hat(ti, 0.25, false)
    end
  end
  if crash then
    buf:hat(t, 0.5, true)
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
      leadNote(lead, cursor, len, Synth.midi(note), 0.28)
      if harmonised then
        leadNote(lead, cursor, len, harmony(note), 0.18)
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
        t = t + BAR
      end
    end
  end

  -- Amp and cab.
  guitar:drive(7)
  guitar:lowpass(3200)
  bass:drive(2.5)
  bass:lowpass(700)
  lead:drive(5)
  lead:lowpass(4500)
  drums:highpass(30)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  guitar:mixInto(master, 0.55)
  bass:mixInto(master, 0.45)
  lead:mixInto(master, 0.35)
  drums:mixInto(master, 0.7)
  return master:toSoundData(0.9)
end

return Theme
