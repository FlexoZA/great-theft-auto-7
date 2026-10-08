-- A-Man's theme, rendered by src/audio/synth.lua the way the other boss
-- themes are. Industrial rock: a palm-muted riff leaning on the flat fifth,
-- a half-time section of open chords, factory clangs, and a sly saw lead
-- the last time round. His own touches frame it: it opens on a low drone
-- that warps in pitch, and the last bar is a time-stop, everything halting
-- but the drone sinking and a clock ticking, before it loops back into the
-- drone as if nothing happened. 130 BPM in E minor, ~48 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 130
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

-- Riffs (guitar + bass) -----------------------------------------------------

-- The main riff: chugging on E, jabbing at the flat fifth.
local riffA = {
  bar(chug("E2", 3), hit("G2", 2), chug("E2", 2), hit("A#2", 2), chug("E2", 3), hit("A2", 2), hit("G2", 2)),
  bar(chug("E2", 3), hit("G2", 2), chug("E2", 2), hit("D3", 3), hit("C#3", 3), chug("E2", 3)),
  bar(chug("E2", 3), hit("G2", 2), chug("E2", 2), hit("A#2", 2), chug("E2", 3), hit("A2", 2), hit("G2", 2)),
  bar(hit("E3", 2), hit("D3", 2), hit("A#2", 4), hit("A2", 4), hit("G2", 2), hit("F2", 2)),
}

-- The heavy part: open chords, half time, sliding down at the end.
local riffB = {
  bar(hit("E2", 6), hit("G2", 2), hit("A2", 8)),
  bar(hit("E2", 6), hit("A#2", 2), hit("A2", 8)),
  bar(hit("E2", 6), hit("G2", 2), hit("D3", 4), hit("C3", 4)),
  bar(hit("A#2", 4), hit("A2", 4), hit("G2", 4), hit("F#2", 4)),
}

-- The lead: still sneaking, a semitone under every note it lands on.
local lead = {
  bar(hit("B4", 4), hit("A#4", 2), hit("B4", 2), hit("D5", 4), hit("E5", 4)),
  bar(hit("G5", 6), hit("F#5", 2), hit("F5", 4), hit("E5", 4)),
  bar(hit("B4", 4), hit("A#4", 2), hit("B4", 2), hit("E5", 4), hit("G5", 4)),
  bar(hit("A#5", 4), hit("A5", 4), hit("G5", 4), hit("E5", 4)),
}

-- Arrangement -----------------------------------------------------------------

-- Each section plays its riff's four bars round for `bars` bars. `fill` ends
-- it on a snare roll; `freeze` makes its last bar the time-stop.
local SECTIONS = {
  { bars = 2, intro = true },
  { bars = 8, riff = riffA, drums = "drive", fill = true },
  { bars = 8, riff = riffB, drums = "half" },
  { bars = 8, riff = riffA, drums = "drive", lead = lead, freeze = true },
}

-- Voices ------------------------------------------------------------------------

--- The drone: a low E and B that drift in and out of tune with each other.
local function drone(buf, t, len)
  buf:tone(t, len, Synth.freq("E1"), { wave = "sine", amp = 0.6, attack = 0.4, decay = 99, sustain = 1,
    release = 0.4, vibRate = 0.23, vibDepth = 0.2 })
  buf:tone(t, len, Synth.freq("B1"), { wave = "tri", amp = 0.2, attack = 0.6, decay = 99, sustain = 1,
    release = 0.4, detune = 12, vibRate = 0.31, vibDepth = 0.35 })
  buf:tone(t, len, Synth.freq("F2"), { wave = "sine", amp = 0.06, attack = 1.5, decay = 99, sustain = 1,
    release = 0.4, vibRate = 0.17, vibDepth = 0.3 }) -- the wrong note, barely there
end

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
  buf:tone(t, len * SIXTEENTH * (muted and 0.8 or 0.98), Synth.freq(note) / 2, {
    wave = "square",
    amp = 0.5,
    decay = muted and 0.1 or 0.45,
    sustain = muted and 0 or 0.5,
  })
end

local function leadNote(buf, t, len, note)
  buf:tone(t, len * SIXTEENTH * 0.95, Synth.freq(note), { wave = "saw", amp = 0.24, attack = 0.01, decay = 0.8,
    sustain = 0.7, release = 0.05, vibRate = 6, vibDepth = len >= 4 and 0.3 or 0.1 })
  buf:tone(t, len * SIXTEENTH * 0.95, Synth.freq(note), { wave = "square", amp = 0.1, attack = 0.01, decay = 0.8,
    sustain = 0.7, release = 0.05, detune = 7 })
end

--- A factory clang: a few inharmonic partials ringing off a sharp knock.
local function clang(buf, t, amp)
  for i, ratio in ipairs({ 1, 2.41, 3.93, 5.37 }) do
    buf:tone(t, 0.6, 170 * ratio, { wave = "sine", amp = amp / i, attack = 0.001, decay = 0.35 / i ^ 0.5,
      sustain = 0 })
  end
  buf:noiseBurst(t, 0.04, { amp = amp, decay = 0.01 })
end

local function drumBar(buf, t, style, fill)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 8 then
      buf:snare(ti, 0.4 + (i - 8) * 0.07) -- the roll into the next section
    elseif style == "drive" then
      if i == 0 or i == 3 or i == 8 or i == 10 then
        buf:kick(ti, 1)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 0.95)
      end
      if i % 2 == 0 then
        buf:hat(ti, i % 4 == 2 and 0.28 or 0.18)
      end
    else -- half time
      if i == 0 or i == 6 or i == 10 then
        buf:kick(ti, 1)
      end
      if i == 8 then
        buf:snare(ti, 1)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.3, true)
      end
    end
  end
end

--- The time-stop: the drone sinks and comes back, a clock ticks, and a
--- quick rising shimmer winds the world up again.
local function freeze(pad, fx, t)
  pad:sweep(t, BAR * 0.5, Synth.freq("E1"), Synth.freq("A0"), { wave = "sine", amp = 0.6, decay = 99 })
  pad:sweep(t + BAR * 0.5, BAR * 0.5, Synth.freq("A0"), Synth.freq("E1"), { wave = "sine", amp = 0.6, decay = 99 })
  for k = 0, 3 do
    local f = k % 2 == 0 and 1800 or 1350 -- tick, tock
    fx:tone(t + k * 4 * SIXTEENTH, 0.02, f, { wave = "sine", amp = 0.35, attack = 0.001, decay = 0.008,
      sustain = 0 })
  end
  fx:sweep(t + BAR - 0.4, 0.4, 300, 2400, { wave = "tri", amp = 0.18, decay = 99 })
end

-- Render ----------------------------------------------------------------------

local function playBar(buf, events, t, voice, bass)
  local cursor = t
  for _, ev in ipairs(events) do
    if ev[1] then
      voice(buf, cursor, ev[2], ev[1], ev[3])
      if bass then
        bassNote(bass, cursor, ev[2], ev[1], ev[3])
      end
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
  local guitar = Synth.newBuffer(total + 0.5)
  local bass = Synth.newBuffer(total + 0.5)
  local solo = Synth.newBuffer(total + 0.5)
  local drums = Synth.newBuffer(total + 0.5)
  local fx = Synth.newBuffer(total + 0.5)

  local t = 0
  for _, s in ipairs(SECTIONS) do
    for b = 1, s.bars do
      local phrase = (b - 1) % 4 + 1
      if s.freeze and b == s.bars then
        freeze(pad, fx, t)
      elseif s.intro then
        drone(pad, t, BAR)
        clang(fx, t, 0.5)
        if b == s.bars then
          drumBar(drums, t, "drive", true)
        end
      else
        playBar(guitar, s.riff[phrase], t, powerChord, bass)
        drumBar(drums, t, s.drums, s.fill and b == s.bars)
        if s.lead then
          playBar(solo, s.lead[phrase], t, leadNote)
        end
        if phrase == 1 then
          clang(fx, t, 0.4)
          drums:hat(t, 0.5, true) -- a crash with it
        end
      end
      t = t + BAR
    end
  end

  pad:lowpass(600)
  guitar:drive(8)
  guitar:lowpass(3200)
  bass:drive(3)
  bass:lowpass(600)
  solo:drive(3)
  solo:lowpass(4500)
  drums:drive(1.6) -- squashed, the industrial way
  drums:highpass(30)
  fx:highpass(60)

  local master = Synth.newBuffer(total) -- exactly the loop length so it wraps cleanly
  pad:mixInto(master, 0.45)
  guitar:mixInto(master, 0.5)
  bass:mixInto(master, 0.45)
  solo:mixInto(master, 0.3)
  drums:mixInto(master, 0.75)
  fx:mixInto(master, 0.35)
  return master:toSoundData(0.9)
end

return Theme
