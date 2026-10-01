-- A-Man's theme, rendered by src/audio/synth.lua the way the other boss
-- themes are. Two things at once, like the man: underneath, a low drone
-- that warps in pitch and never resolves; on top, a cartoon "sneaking"
-- number, a plucked bass on tiptoe and a muted horn being far too pleased
-- with itself. The last bar of each section is a time-stop: everything
-- halts but the drone sinking and a clock ticking, then it all creeps on
-- as if nothing happened. 100 BPM in A minor, ~48 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 100
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

-- Notation: a bar is a list of { note|false, sixteenths } summing to 16.
local function bar(...)
  local out = {}
  for _, group in ipairs({ ... }) do
    for _, ev in ipairs(group) do
      out[#out + 1] = ev
    end
  end
  return out
end
local function hit(n, len)
  return { { n, len } }
end
local function rest(len)
  return { { false, len } }
end

-- The tiptoe: staccato steps creeping up, a pause, creeping back down.
local tiptoe = {
  bar(hit("A2", 2), rest(2), hit("C3", 2), rest(2), hit("D3", 2), rest(2), hit("D#3", 2), hit("E3", 2)),
  bar(rest(2), hit("E3", 2), rest(2), hit("D#3", 2), hit("D3", 2), rest(2), hit("C3", 2), hit("B2", 2)),
  bar(hit("A2", 2), rest(2), hit("C3", 2), rest(2), hit("F3", 2), rest(2), hit("E3", 2), rest(2)),
  bar(hit("D#3", 2), hit("D3", 2), hit("C#3", 2), hit("C3", 2), hit("B2", 4), rest(4)),
}

-- The horn: sly little phrases that keep sliding a semitone off the note.
local horn = {
  bar(rest(4), hit("E5", 2), rest(2), hit("F5", 1), hit("E5", 1), hit("D#5", 2), hit("E5", 4)),
  bar(rest(4), hit("C5", 2), rest(2), hit("B4", 1), hit("C5", 1), hit("B4", 2), hit("A4", 4)),
  bar(rest(2), hit("A4", 2), hit("C5", 2), hit("E5", 2), hit("A5", 4), hit("G#5", 4)),
  bar(hit("G5", 2), hit("F#5", 2), hit("F5", 2), hit("E5", 2), hit("D#5", 4), rest(4)),
}

-- A music box, far off, while the drone is on its own.
local bells = {
  bar(hit("E6", 4), rest(4), hit("C6", 4), rest(4)),
  bar(hit("B5", 8), rest(8)),
  bar(hit("A5", 4), rest(4), hit("D#6", 4), rest(4)),
  bar(hit("E6", 12), rest(4)),
}

-- Each section: how many bars and which parts play. The parts are four-bar
-- phrases, so a section of eight plays them through once, then three bars
-- again; with `freeze` its last bar is the time-stop instead.
local SECTIONS = {
  { bars = 4, bells = true },
  { bars = 8, bass = true, hats = true, freeze = true },
  { bars = 8, bass = true, hats = true, horn = true, freeze = true },
}

-- Voices ------------------------------------------------------------------------

--- The drone: a low A and E that drift in and out of tune with each other.
local function drone(buf, t, len)
  buf:tone(t, len, Synth.freq("A1"), { wave = "sine", amp = 0.5, attack = 0.4, decay = 99, sustain = 1,
    release = 0.4, vibRate = 0.23, vibDepth = 0.2 })
  buf:tone(t, len, Synth.freq("E2"), { wave = "tri", amp = 0.16, attack = 0.6, decay = 99, sustain = 1,
    release = 0.4, detune = 12, vibRate = 0.31, vibDepth = 0.35 })
  buf:tone(t, len, Synth.freq("A#2"), { wave = "sine", amp = 0.05, attack = 1.5, decay = 99, sustain = 1,
    release = 0.4, vibRate = 0.17, vibDepth = 0.3 }) -- the wrong note, barely there
end

--- Plucked, on tiptoe: a short triangle and a click of a string.
local function pluck(buf, t, len, note)
  local f = Synth.freq(note)
  buf:tone(t, len * SIXTEENTH * 0.5, f, { wave = "tri", amp = 0.55, attack = 0.003, decay = 0.09, sustain = 0,
    release = 0.03 })
  buf:tone(t, 0.03, f * 2, { wave = "square", amp = 0.08, attack = 0.001, decay = 0.01, sustain = 0 })
end

--- A muted horn: a square with a lazy vibrato, played legato and smug.
local function hornNote(buf, t, len, note)
  buf:tone(t, len * SIXTEENTH * 0.92, Synth.freq(note), { wave = "square", amp = 0.24, attack = 0.03,
    decay = 0.6, sustain = 0.55, release = 0.06, vibRate = 5, vibDepth = len >= 4 and 0.25 or 0 })
end

local function bell(buf, t, len, note)
  local f = Synth.freq(note)
  buf:tone(t, len * SIXTEENTH, f, { wave = "sine", amp = 0.2, attack = 0.002, decay = 0.5, sustain = 0 })
  buf:tone(t, len * SIXTEENTH, f * 2.76, { wave = "sine", amp = 0.06, attack = 0.002, decay = 0.15, sustain = 0 })
end

--- Brushes: a soft hat on the off-beats and a rim on four.
local function hatsBar(buf, t)
  for i = 0, 15 do
    if i % 4 == 2 then
      buf:hat(t + i * SIXTEENTH, 0.18)
    end
  end
  buf:snare(t + 12 * SIXTEENTH, 0.12)
end

--- The time-stop: the drone sinks a fifth and back, a clock ticks, and a
--- quick rising shimmer winds the world up again.
local function freeze(pad, fx, t)
  pad:sweep(t, BAR * 0.5, Synth.freq("A1"), Synth.freq("D1"), { wave = "sine", amp = 0.45, decay = 99 })
  pad:sweep(t + BAR * 0.5, BAR * 0.5, Synth.freq("D1"), Synth.freq("A1"), { wave = "sine", amp = 0.45, decay = 99 })
  for k = 0, 3 do
    local f = k % 2 == 0 and 1800 or 1350 -- tick, tock
    fx:tone(t + k * 4 * SIXTEENTH, 0.02, f, { wave = "sine", amp = 0.35, attack = 0.001, decay = 0.008,
      sustain = 0 })
  end
  fx:sweep(t + BAR - 0.45, 0.45, 300, 2400, { wave = "tri", amp = 0.18, decay = 99 })
end

-- Render ----------------------------------------------------------------------

local function playBar(buf, events, t, voice)
  local cursor = t
  for _, ev in ipairs(events) do
    if ev[1] then
      voice(buf, cursor, ev[2], ev[1])
    end
    cursor = cursor + ev[2] * SIXTEENTH
  end
end

function Theme.duration()
  local bars = 0
  for _, s in ipairs(SECTIONS) do
    bars = bars + s.bars
  end
  return bars * BAR
end

--- Renders the whole loop. Returns a SoundData.
function Theme.render()
  local total = Theme.duration()
  local pad = Synth.newBuffer(total + 0.5)
  local bass = Synth.newBuffer(total + 0.5)
  local lead = Synth.newBuffer(total + 0.5)
  local fx = Synth.newBuffer(total + 0.5)

  local t = 0
  for _, s in ipairs(SECTIONS) do
    for b = 1, s.bars do
      local phrase = (b - 1) % 4 + 1
      if s.freeze and b == s.bars then
        freeze(pad, fx, t)
      else
        drone(pad, t, BAR)
        if s.bells then
          playBar(fx, bells[phrase], t, bell)
        end
        if s.bass then
          playBar(bass, tiptoe[phrase], t, pluck)
        end
        if s.horn then
          playBar(lead, horn[phrase], t, hornNote)
        end
        if s.hats then
          hatsBar(fx, t)
        end
      end
      t = t + BAR
    end
  end

  pad:lowpass(700)
  bass:lowpass(1800)
  lead:drive(2)
  lead:lowpass(2200) -- the mute in the horn
  fx:highpass(40)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  pad:mixInto(master, 0.38)
  bass:mixInto(master, 0.7)
  lead:mixInto(master, 0.35)
  fx:mixInto(master, 0.5)
  return master:toSoundData(0.9)
end

return Theme
