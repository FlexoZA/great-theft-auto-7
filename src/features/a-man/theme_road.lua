-- The Winding Road's theme (quests' "a-man-road"), rendered by
-- src/audio/synth.lua like A-Man's own. Heavy metal for the drive up the
-- mountain: big ringing power chords to open, then a galloping palm-muted
-- riff on the low E with power-chord stabs (and a flat fifth in it), a
-- chorus of chords on every eighth under a screaming lead, a half-time
-- breakdown that stops dead between the chugs, a solo of sixteenth-note
-- arpeggios over double kick, and the chorus once more. 160 BPM in E
-- minor, the lead in the harmonic minor, ~60 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 160
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- The riff, a bar at a time: sixteenth steps. `x` a palm-muted chug on the
-- low E, `-` nothing, and { step, root, sixteenths } a power chord rung out.
local VERSE = {
  { chugs = "x-xxx-xxx-xx----", chords = { { 12, "G2", 2 }, { 14, "A2", 2 } } },
  { chugs = "x-xxx-xxx-xx----", chords = { { 12, "A#2", 4 } } }, -- the flat fifth
  { chugs = "x-xxx-xxx-xx----", chords = { { 12, "G2", 2 }, { 14, "A2", 2 } } },
  { chugs = "x-xxx-xx--------", chords = { { 8, "D3", 4 }, { 12, "C3", 2 }, { 14, "B2", 2 } } },
}
local BREAKDOWN = "x--x--x-x--x--x-"

-- The chorus: a chord a bar, picked on every eighth.
local CHORUS = { "E2", "C3", "D3", "B2" }

-- The lead over the chorus: four bars of { note|false, sixteenths }, the
-- second time round ending on the high E.
local LEAD = {
  { { "B4", 4 }, { "E5", 4 }, { "G5", 4 }, { "F#5", 4 } },
  { { "E5", 8 }, { "D5", 4 }, { "C5", 4 } },
  { { "D5", 4 }, { "F#5", 4 }, { "A5", 6 }, { "G5", 2 } },
  { { "F#5", 8 }, { "D#5", 4 }, { "B4", 4 } }, -- D#: the harmonic minor, pulling home
}
local LEAD_END = { { "E5", 4 }, { "G5", 4 }, { "B5", 4 }, { "E6", 4 } }

-- The solo's arpeggios: each bar's chord swept up and back down in sixteenths.
local SOLO = {
  { "E4", "G4", "B4", "E5", "G5", "B5", "E6", "B5", "G5", "E5", "B4", "G4", "E4", "G4", "B4", "E5" },
  { "C4", "E4", "G4", "C5", "E5", "G5", "C6", "G5", "E5", "C5", "G4", "E4", "C4", "E4", "G4", "C5" },
  { "D4", "F#4", "A4", "D5", "F#5", "A5", "D6", "A5", "F#5", "D5", "A4", "F#4", "D4", "F#4", "A4", "D5" },
  { "B3", "D#4", "F#4", "B4", "D#5", "F#5", "B5", "F#5", "D#5", "B4", "F#4", "D#4", "B3", "D#4", "F#4", "B4" },
}

local SECTIONS = {
  { bars = 4, intro = true },
  { bars = 8, verse = true },
  { bars = 8, chorus = true },
  { bars = 4, breakdown = true },
  { bars = 8, solo = true },
  { bars = 8, chorus = true, last = true },
}

--- A distorted power chord on `root` (root, fifth, octave, two strings a
--- touch out of tune with each other); the guitar's buffer is driven hard after.
local function power(buf, t, root, len, amp)
  for _, semis in ipairs({ 0, 7, 12 }) do
    local f = freq(root, semis)
    for _, cents in ipairs({ -7, 7 }) do
      buf:tone(t, len, f, { wave = "saw", amp = amp, attack = 0.003, decay = 2, sustain = 0.8, release = 0.04,
        detune = cents })
    end
  end
end

--- A palm-muted chug on the low E: short, choked, all low end.
local function chug(buf, t, amp)
  for _, semis in ipairs({ 0, 7 }) do
    buf:tone(t, SIXTEENTH * 0.9, freq("E2", semis), { wave = "saw", amp = amp, attack = 0.002, decay = 0.06,
      sustain = 0.15, release = 0.02 })
  end
end

local function bassNote(buf, t, note, len, amp)
  buf:tone(t, len, freq(note, -12), { wave = "saw", amp = amp, attack = 0.004, decay = 0.4, sustain = 0.6,
    release = 0.03 })
end

--- The lead guitar: it bends up into each note and screams with vibrato on the long ones.
local function leadNote(buf, t, note, len, amp)
  local f = freq(note)
  buf:sweep(t, 0.04, f * 0.92, f, { wave = "saw", amp = amp, decay = 99 })
  buf:tone(t + 0.04, len - 0.04, f, { wave = "saw", amp = amp, attack = 0.002, decay = 2, sustain = 0.85,
    release = 0.05, vibRate = 6.5, vibDepth = len >= SIXTEENTH * 6 and 0.35 or 0.08 })
  buf:tone(t + 0.04, len - 0.04, f * 2, { wave = "square", amp = amp * 0.25, attack = 0.002, decay = 1,
    sustain = 0.5, release = 0.05 })
end

local function crash(buf, t, amp)
  buf:hat(t, amp, true)
  buf:noiseBurst(t, 0.9, { amp = amp * 0.35, decay = 0.35 })
end

local function tom(buf, t, amp, pitch)
  buf:sweep(t, 0.25, pitch, pitch * 0.5, { wave = "sine", amp = amp, decay = 0.1 })
end

--- One bar of drums. `style`: "intro", "verse", "chorus", "breakdown", "solo";
--- `fill` rolls the last beat on the snare and toms into what comes next.
local function drumBar(buf, t, style, first, fill)
  if first then
    crash(buf, t, 0.45)
  end
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      if i % 2 == 0 then
        tom(buf, ti, 0.6, 180 - (i - 12) * 25)
      end
      buf:snare(ti, 0.35 + (i - 12) * 0.08)
    elseif style == "intro" then
      if i == 0 then
        buf:kick(ti, 0.9)
        crash(buf, ti, 0.4)
      end
    elseif style == "verse" then
      if i % 2 == 0 or i == 3 or i == 7 or i == 11 then -- the kick gallops with the riff
        buf:kick(ti, 0.6)
      end
      if i == 4 or i == 12 then
        buf:snare(ti, 0.7)
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.12)
      end
    elseif style == "breakdown" then
      if BREAKDOWN:sub(i + 1, i + 1) == "x" then
        buf:kick(ti, 0.8)
      end
      if i == 8 then
        buf:snare(ti, 0.85)
      end
      if i == 0 then
        crash(buf, ti, 0.35)
      end
    else -- chorus and solo: double kick under everything
      buf:kick(ti, i % 4 == 0 and 0.6 or 0.42)
      if i == 4 or i == 12 then
        buf:snare(ti, 0.75)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.18, true) -- riding the crash
      end
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
  local chords = Synth.newBuffer(total + 1)
  local chugs = Synth.newBuffer(total + 0.5)
  local bass = Synth.newBuffer(total + 0.5)
  local lead = Synth.newBuffer(total + 0.5)
  local drums = Synth.newBuffer(total + 1)

  local t = 0
  for _, s in ipairs(SECTIONS) do
    for b = 1, s.bars do
      local phrase = (b - 1) % 4 + 1
      local fill = b == s.bars
      if s.intro then
        -- Big chords left to ring, a bar each, the last cut short for the fill.
        local root = CHORUS[phrase]
        power(chords, t, root, fill and BAR * 0.75 or BAR, 0.3)
        bassNote(bass, t, root, fill and BAR * 0.75 or BAR, 0.5)
        drumBar(drums, t, "intro", false, fill)
      elseif s.verse or s.breakdown then
        local bar = s.verse and VERSE[phrase] or { chugs = BREAKDOWN, chords = {} }
        for i = 0, 15 do
          if bar.chugs:sub(i + 1, i + 1) == "x" then
            chug(chugs, t + i * SIXTEENTH, s.breakdown and 0.4 or 0.32)
            bassNote(bass, t + i * SIXTEENTH, "E2", SIXTEENTH * 0.9, 0.45)
          end
        end
        for _, c in ipairs(bar.chords) do
          power(chords, t + c[1] * SIXTEENTH, c[2], c[3] * SIXTEENTH * 0.95, 0.3)
          bassNote(bass, t + c[1] * SIXTEENTH, c[2], c[3] * SIXTEENTH * 0.95, 0.5)
        end
        drumBar(drums, t, s.verse and "verse" or "breakdown", b == 1, fill)
      else
        -- Chorus and solo: the chord picked on every eighth.
        local root = CHORUS[phrase]
        for i = 0, 7 do
          power(chords, t + i * 2 * SIXTEENTH, root, SIXTEENTH * 1.9, i == 0 and 0.32 or 0.26)
        end
        for i = 0, 7 do
          bassNote(bass, t + i * 2 * SIXTEENTH, root, SIXTEENTH * 1.9, 0.5)
        end
        if s.chorus then
          local line = LEAD[phrase]
          if s.last and b == s.bars then
            line = LEAD_END
          end
          local cursor = t
          for _, ev in ipairs(line) do
            local len = ev[2] * SIXTEENTH
            if ev[1] then
              leadNote(lead, cursor, ev[1], len * 0.97, 0.22)
            end
            cursor = cursor + len
          end
        else
          for i, note in ipairs(SOLO[phrase]) do
            leadNote(lead, t + (i - 1) * SIXTEENTH, note, SIXTEENTH * 0.95, 0.2)
          end
        end
        drumBar(drums, t, s.chorus and "chorus" or "solo", b == 1, fill and not s.last)
      end
      t = t + BAR
    end
  end

  -- The distortion: everything on the guitars driven into the ground.
  chords:drive(9)
  chords:lowpass(3200)
  chugs:drive(10)
  chugs:lowpass(900) -- the palm mute: all chest, no fizz
  bass:drive(3)
  bass:lowpass(600)
  lead:drive(6)
  lead:lowpass(4200)
  drums:highpass(35)

  local master = Synth.newBuffer(total)
  chords:mixInto(master, 0.32)
  chugs:mixInto(master, 0.5)
  bass:mixInto(master, 0.4)
  lead:mixInto(master, 0.28)
  drums:mixInto(master, 0.7)
  master:drive(0.6) -- squashed a little, to sit about as loud as the others
  return master:toSoundData(0.9)
end

return Theme
