-- The Outer City's theme (quests' "a-man-2", the Hunter-Chopper's level),
-- rendered by src/audio/synth.lua like A-Man's own. A chase: fast and
-- electronic, the way Half-Life's action tracks run. A warning siren and a
-- filtered bass pulse open it; then a breakbeat under a sixteenth-note saw
-- bass and offbeat distorted stabs, i - VI - VII - v; a half-time break
-- where an arpeggio climbs and the siren comes back; and the drive again
-- with a lead over it. 150 BPM in D minor, ~45 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 150
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

-- One chord a bar, round and round: { root, third, fifth }.
local CHORDS = {
  { "D2", "F2", "A2" }, -- Dm
  { "A#1", "D2", "F2" }, -- Bb
  { "C2", "E2", "G2" }, -- C
  { "A1", "C2", "E2" }, -- Am
}

-- The lead, the last time round: four bars of { note|false, sixteenths }.
local LEAD = {
  { { "A4", 4 }, { "D5", 4 }, { "F5", 6 }, { "E5", 2 } },
  { { "D5", 4 }, { "A#4", 4 }, { "D5", 4 }, { "F5", 4 } },
  { { "G5", 6 }, { "F5", 2 }, { "E5", 4 }, { "C5", 4 } },
  { { "E5", 4 }, { "A4", 4 }, { "C#5", 4 }, { "E5", 4 } },
}

local SECTIONS = {
  { bars = 4, intro = true },
  { bars = 8, drive = true, fill = true },
  { bars = 8, breakdown = true },
  { bars = 8, drive = true, lead = true, outro = true },
}

local function up(note, octaves)
  return Synth.freq(note) * 2 ^ octaves
end

--- The bass: a sixteenth-note pulse on the root, up the octave on the offbeats.
local function bassBar(buf, t, chord, open)
  for i = 0, 15 do
    local f = Synth.freq(chord[1]) * ((i % 4 == 2) and 2 or 1)
    buf:tone(t + i * SIXTEENTH, SIXTEENTH * 0.8, f, { wave = "saw", amp = (i % 4 == 0) and 0.55 or 0.38,
      decay = 0.08 + open * 0.1, sustain = 0 })
  end
end

--- Short distorted stabs of the chord on the offbeats.
local function stabs(buf, t, chord)
  for _, i in ipairs({ 2, 6, 10, 13 }) do
    for k, n in ipairs(chord) do
      buf:tone(t + i * SIXTEENTH, SIXTEENTH * 0.9, up(n, 2), { wave = "saw", amp = 0.16, decay = 0.07, sustain = 0,
        detune = (k - 2) * 8 })
    end
  end
end

--- A held chord, for the break.
local function pad(buf, t, chord, len)
  for k, n in ipairs(chord) do
    buf:tone(t, len, up(n, 1), { wave = "saw", amp = 0.14, attack = 0.3, decay = 99, sustain = 1, release = 0.3,
      detune = (k - 2) * 10 })
    buf:tone(t, len, up(n, 1), { wave = "tri", amp = 0.12, attack = 0.3, decay = 99, sustain = 1, release = 0.3,
      detune = -(k - 2) * 7 })
  end
end

--- The arpeggio: chord tones climbing through two octaves in sixteenths,
--- higher as the break goes on (`lift` 0..1).
local function arp(buf, t, chord, lift)
  local order = { 1, 2, 3, 2, 1, 2, 3, 1 }
  for i = 0, 15 do
    local n = chord[order[i % #order + 1]]
    local oct = 2 + (i >= 8 and 1 or 0) + (lift > 0.5 and 1 or 0)
    buf:tone(t + i * SIXTEENTH, SIXTEENTH * 0.7, up(n, oct), { wave = "square", amp = 0.12 + lift * 0.06,
      decay = 0.05, sustain = 0 })
  end
end

--- The siren: a slow wail up and down, from somewhere across the city.
local function siren(buf, t, len, amp)
  buf:tone(t, len, 700, { wave = "tri", amp = amp, attack = 0.4, decay = 99, sustain = 1, release = 0.4,
    vibRate = 1 / (BAR * 0.5), vibDepth = 5 })
end

--- A factory clang: inharmonic partials off a knock.
local function clang(buf, t, amp)
  for i, ratio in ipairs({ 1, 2.76, 4.07, 5.93 }) do
    buf:tone(t, 0.5, 210 * ratio, { wave = "sine", amp = amp / i, attack = 0.001, decay = 0.3 / i ^ 0.5,
      sustain = 0 })
  end
  buf:noiseBurst(t, 0.03, { amp = amp, decay = 0.008 })
end

local function drumBar(buf, t, style, fill)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 8 then
      buf:snare(ti, 0.35 + (i - 8) * 0.08)
    elseif style == "break" then -- the breakbeat
      if i == 0 or i == 10 or i == 11 then
        buf:kick(ti, 1)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 0.95)
      elseif i == 7 or i == 15 then
        buf:snare(ti, 0.25) -- ghosts
      end
      buf:hat(ti, i % 2 == 0 and 0.22 or 0.12)
    elseif style == "half" then
      if i == 0 or i == 14 then
        buf:kick(ti, 0.9)
      end
      if i == 8 then
        buf:snare(ti, 0.9)
      end
      if i % 4 == 2 then
        buf:hat(ti, 0.25, true)
      end
    elseif style == "intro" then
      if i % 4 == 0 then
        buf:kick(ti, 0.6)
      end
      buf:hat(ti, 0.1)
    end
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
  local bass = Synth.newBuffer(total + 0.5)
  local synths = Synth.newBuffer(total + 0.5)
  local pads = Synth.newBuffer(total + 0.5)
  local lead = Synth.newBuffer(total + 0.5)
  local drums = Synth.newBuffer(total + 0.5)
  local fx = Synth.newBuffer(total + 0.5)

  local t = 0
  for _, s in ipairs(SECTIONS) do
    for b = 1, s.bars do
      local chord = CHORDS[(b - 1) % 4 + 1]
      local last = b == s.bars
      if s.intro then
        bassBar(bass, t, chord, 0)
        drumBar(drums, t, "intro", last)
        if b % 2 == 1 then
          siren(fx, t, BAR * 2, 0.22)
        end
      elseif s.breakdown then
        pad(pads, t, chord, BAR)
        arp(synths, t, chord, (b - 1) / s.bars)
        drumBar(drums, t, "half", last)
        if b == 1 or b == 5 then
          siren(fx, t, BAR * 2, 0.16)
        end
      else
        bassBar(bass, t, chord, 1)
        stabs(synths, t, chord)
        drumBar(drums, t, "break", s.fill and last)
        if s.lead then
          local cursor = t
          for _, ev in ipairs(LEAD[(b - 1) % 4 + 1]) do
            local dur = ev[2] * SIXTEENTH
            lead:tone(cursor, dur * 0.95, Synth.freq(ev[1]), { wave = "saw", amp = 0.24, attack = 0.01, decay = 0.6,
              sustain = 0.7, release = 0.05, vibRate = 6, vibDepth = ev[2] >= 4 and 0.25 or 0.05 })
            lead:tone(cursor, dur * 0.95, Synth.freq(ev[1]) / 2, { wave = "square", amp = 0.08, decay = 0.6,
              sustain = 0.6, release = 0.05 })
            cursor = cursor + dur
          end
        end
        if b % 4 == 1 then
          clang(fx, t, 0.4)
          drums:hat(t, 0.5, true) -- a crash with it
        end
        if s.outro and last then -- the loop's seam: a rush of noise rising into the top again
          fx:sweep(t + BAR * 0.5, BAR * 0.5, 200, 2600, { wave = "saw", amp = 0.12, decay = 99 })
        end
      end
      t = t + BAR
    end
  end

  bass:drive(2.5)
  bass:lowpass(900)
  synths:drive(4)
  synths:lowpass(3800)
  pads:lowpass(1800)
  lead:drive(2.5)
  lead:lowpass(4500)
  drums:drive(1.8)
  drums:highpass(30)
  fx:highpass(80)

  local master = Synth.newBuffer(total)
  bass:mixInto(master, 0.5)
  synths:mixInto(master, 0.35)
  pads:mixInto(master, 0.35)
  lead:mixInto(master, 0.3)
  drums:mixInto(master, 0.75)
  fx:mixInto(master, 0.3)
  master:drive(0.9) -- gently squashed, to sit as loud as City 17's
  return master:toSoundData(0.9)
end

return Theme
