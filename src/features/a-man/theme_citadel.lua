-- The Citadel's theme (quests' "a-man-citadel"), rendered by
-- src/audio/synth.lua like A-Man's own. Industrial metal for the climb up
-- the Combine's tower: slower and colder than the Winding Road's. It
-- opens on the machine, a cold synth arpeggio over a sub drone with metal
-- clanking somewhere far below; then a syncopated drop-D riff that leans
-- on the flat second, half-time drums with the snare on three; the
-- arpeggio back over the riff with a marching snare; a chorus of held
-- chords under a wailing lead and its harmony a third up, on double kick;
-- a breakdown down to a slow hammer on the low D and the Combine's alarm;
-- and everything at once to close. 112 BPM in D Phrygian, ~86 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 112
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16

local function freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

-- The riff, a bar at a time in sixteenths: `x` a palm-muted chug on the low
-- D, `-` nothing, and { step, root, sixteenths } a power chord rung out.
local RIFF = {
  { chugs = "x-x--x-x--x-----", chords = { { 12, "D#2", 4 } } }, -- the flat second
  { chugs = "x-x--x-x--x-----", chords = { { 12, "F2", 2 }, { 14, "D#2", 2 } } },
  { chugs = "x-x--x-x--x-----", chords = { { 12, "D#2", 4 } } },
  { chugs = "x-x--x-x--------", chords = { { 8, "C3", 4 }, { 12, "A#2", 2 }, { 14, "A2", 2 } } },
}

-- The machine: a cold arpeggio over each bar, in sixteenths.
local ARP = {
  { "D4", "A4", "D5", "D#5", "D5", "A4", "F4", "A4", "D4", "A4", "D5", "F5", "D#5", "D5", "A4", "F4" },
  { "D4", "A4", "D5", "D#5", "D5", "A4", "F4", "A4", "D4", "A4", "D5", "F5", "D#5", "D5", "A4", "F4" },
  { "D4", "A4", "D5", "D#5", "D5", "A4", "F4", "A4", "D4", "A4", "D5", "F5", "D#5", "D5", "A4", "F4" },
  { "C4", "G4", "C5", "D#5", "C5", "G4", "A#4", "G4", "A3", "E4", "A4", "C#5", "A4", "E4", "C#4", "E4" },
}

-- The chorus: a chord held a bar each.
local CHORUS = { "D2", "A#2", "C3", "A2" }

-- The lead over it: four bars of { note|false, sixteenths }; its harmony
-- goes a third up (`HARMONY` semitones per note: a minor or a major third).
local LEAD = {
  { { "A4", 6 }, { "D5", 6 }, { "D#5", 4 } },
  { { "D5", 8 }, { "A#4", 4 }, { "F4", 4 } },
  { { "G4", 6 }, { "C5", 6 }, { "D5", 4 } },
  { { "C#5", 12 }, { false, 4 } }, -- C#: the A major, pulling back home to D
}
local HARMONY = { A4 = 3, D5 = 3, ["D#5"] = 4, ["A#4"] = 4, F4 = 4, G4 = 3, C5 = 4, ["C#5"] = 4 }

local SECTIONS = {
  { bars = 4, intro = true },
  { bars = 8, riff = true },
  { bars = 8, riff = true, machine = true },
  { bars = 8, chorus = true },
  { bars = 4, breakdown = true },
  { bars = 8, riff = true, machine = true, lead = true },
}

local function power(buf, t, root, len, amp)
  for _, semis in ipairs({ 0, 7, 12 }) do
    local f = freq(root, semis)
    for _, cents in ipairs({ -8, 8 }) do
      buf:tone(t, len, f, { wave = "saw", amp = amp, attack = 0.004, decay = 3, sustain = 0.8, release = 0.05,
        detune = cents })
    end
  end
end

local function chug(buf, t, amp)
  for _, semis in ipairs({ 0, 7 }) do
    buf:tone(t, SIXTEENTH * 0.9, freq("D2", semis), { wave = "saw", amp = amp, attack = 0.002, decay = 0.07,
      sustain = 0.15, release = 0.02 })
  end
end

local function bassNote(buf, t, note, len, amp)
  buf:tone(t, len, freq(note, -12), { wave = "saw", amp = amp, attack = 0.004, decay = 0.5, sustain = 0.6,
    release = 0.03 })
end

--- One note of the machine's arpeggio: a short square blip, no warmth in it.
local function blip(buf, t, note, amp)
  buf:tone(t, SIXTEENTH * 0.8, freq(note), { wave = "square", amp = amp, attack = 0.001, decay = 0.09,
    sustain = 0.1, release = 0.01 })
end

--- Metal hit somewhere far below: a crack and a ringing, out of tune with everything.
local function clank(buf, t, amp, pitch)
  buf:noiseBurst(t, 0.05, { amp = amp, decay = 0.012 })
  buf:tone(t, 0.9, pitch, { wave = "square", amp = amp * 0.25, attack = 0.001, decay = 0.25, sustain = 0 })
  buf:tone(t, 0.9, pitch * 2.76, { wave = "sine", amp = amp * 0.3, attack = 0.001, decay = 0.4, sustain = 0 })
end

--- The Combine's alarm: a siren rising and falling over `len` seconds.
local function alarm(buf, t, len, amp)
  local half = len / 2
  buf:sweep(t, half, 520, 780, { wave = "square", amp = amp, decay = 99 })
  buf:sweep(t + half, half, 780, 520, { wave = "square", amp = amp, decay = 99 })
end

local function leadNote(buf, t, note, len, amp, semis)
  local f = freq(note, semis)
  buf:sweep(t, 0.05, f * 0.9, f, { wave = "saw", amp = amp, decay = 99 })
  buf:tone(t + 0.05, len - 0.05, f, { wave = "saw", amp = amp, attack = 0.002, decay = 3, sustain = 0.85,
    release = 0.08, vibRate = 5.5, vibDepth = len >= SIXTEENTH * 6 and 0.4 or 0.1 })
end

local function crash(buf, t, amp)
  buf:hat(t, amp, true)
  buf:noiseBurst(t, 1.1, { amp = amp * 0.35, decay = 0.45 })
end

local function tom(buf, t, amp, pitch)
  buf:sweep(t, 0.3, pitch, pitch * 0.5, { wave = "sine", amp = amp, decay = 0.12 })
end

--- One bar of drums. `style`: "intro", "riff", "march", "chorus", "breakdown";
--- `fill` rolls the last beat into what comes next.
local function drumBar(buf, t, style, riff, first, fill)
  if first then
    crash(buf, t, 0.45)
  end
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      if i % 2 == 0 then
        tom(buf, ti, 0.65, 160 - (i - 12) * 22)
      end
      buf:snare(ti, 0.4 + (i - 12) * 0.08)
    elseif style == "intro" then
      if i == 0 then
        buf:kick(ti, 0.8)
      end
      if i == 8 then
        tom(buf, ti, 0.5, 90) -- a slow, heavy step
      end
    elseif style == "riff" or style == "march" then
      if riff.chugs:sub(i + 1, i + 1) == "x" then -- the kick locks to the chugs
        buf:kick(ti, 0.75)
      end
      if i == 8 then
        buf:snare(ti, 0.85) -- half time: the snare on three
      end
      if style == "march" and i ~= 8 then
        buf:snare(ti, i % 4 == 0 and 0.18 or 0.1) -- a marching roll under it
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.14)
      end
    elseif style == "breakdown" then
      if i == 0 or i == 8 then
        buf:kick(ti, 0.9)
        tom(buf, ti, 0.5, 70)
      end
    else -- the chorus: double kick, the snare on two and four
      buf:kick(ti, i % 4 == 0 and 0.6 or 0.4)
      if i == 4 or i == 12 then
        buf:snare(ti, 0.75)
      end
      if i % 4 == 0 then
        buf:hat(ti, 0.18, true)
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
  local synth = Synth.newBuffer(total + 0.5)
  local lead = Synth.newBuffer(total + 0.5)
  local metal = Synth.newBuffer(total + 1.5)
  local drums = Synth.newBuffer(total + 1)

  local t, n = 0, 0
  for _, s in ipairs(SECTIONS) do
    for b = 1, s.bars do
      n = n + 1
      local phrase = (b - 1) % 4 + 1
      local fill = b == s.bars
      -- Clanking far below, now and then, all the way through.
      local h = math.sin(n * 12.9898) * 43758.5453
      h = h - math.floor(h)
      clank(metal, t + (2 + math.floor(h * 12)) * SIXTEENTH, 0.35, 180 + h * 160)
      if s.intro then
        bass:tone(t, BAR, freq("D2", -12), { wave = "saw", amp = 0.45, attack = b == 1 and 1.5 or 0.01, decay = 99,
          sustain = 1, release = 0.05 }) -- the drone
        for i, note in ipairs(ARP[phrase]) do
          blip(synth, t + (i - 1) * SIXTEENTH, note, 0.12 + b * 0.03)
        end
        drumBar(drums, t, "intro", nil, false, fill)
      elseif s.riff then
        local riff = RIFF[phrase]
        for i = 0, 15 do
          if riff.chugs:sub(i + 1, i + 1) == "x" then
            chug(chugs, t + i * SIXTEENTH, 0.36)
            bassNote(bass, t + i * SIXTEENTH, "D2", SIXTEENTH * 1.6, 0.5)
          end
        end
        for _, c in ipairs(riff.chords) do
          power(chords, t + c[1] * SIXTEENTH, c[2], c[3] * SIXTEENTH * 0.95, 0.3)
          bassNote(bass, t + c[1] * SIXTEENTH, c[2], c[3] * SIXTEENTH * 0.95, 0.5)
        end
        if s.machine then
          for i, note in ipairs(ARP[phrase]) do
            blip(synth, t + (i - 1) * SIXTEENTH, note, 0.15)
          end
        end
        if s.lead then
          local cursor = t
          for _, ev in ipairs(LEAD[phrase]) do
            local len = ev[2] * SIXTEENTH
            if ev[1] then
              leadNote(lead, cursor, ev[1], len * 0.97, 0.2)
              leadNote(lead, cursor, ev[1], len * 0.97, 0.12, HARMONY[ev[1]])
            end
            cursor = cursor + len
          end
        end
        drumBar(drums, t, s.machine and "march" or "riff", riff, b == 1, fill)
      elseif s.chorus then
        local root = CHORUS[phrase]
        power(chords, t, root, BAR * 0.98, 0.32)
        bassNote(bass, t, root, BAR * 0.98, 0.55)
        local cursor = t
        for _, ev in ipairs(LEAD[phrase]) do
          local len = ev[2] * SIXTEENTH
          if ev[1] then
            leadNote(lead, cursor, ev[1], len * 0.97, 0.22)
            leadNote(lead, cursor, ev[1], len * 0.97, 0.13, HARMONY[ev[1]])
          end
          cursor = cursor + len
        end
        drumBar(drums, t, "chorus", nil, b == 1, fill)
      else -- the breakdown: a hammer on the low D, and the alarm
        for _, i in ipairs({ 0, 8 }) do
          power(chords, t + i * SIXTEENTH, "D2", SIXTEENTH * 3, 0.32)
          bassNote(bass, t + i * SIXTEENTH, "D2", SIXTEENTH * 3, 0.55)
        end
        if b % 2 == 1 then
          alarm(synth, t, BAR * 2, 0.07)
        end
        drumBar(drums, t, "breakdown", nil, b == 1, fill)
      end
      t = t + BAR
    end
  end

  chords:drive(9)
  chords:lowpass(2800) -- darker than the road's
  chugs:drive(10)
  chugs:lowpass(800)
  bass:drive(3)
  bass:lowpass(500)
  synth:lowpass(5000)
  lead:drive(5)
  lead:lowpass(3800)
  metal:highpass(120)
  drums:highpass(35)

  local master = Synth.newBuffer(total)
  chords:mixInto(master, 0.3)
  chugs:mixInto(master, 0.5)
  bass:mixInto(master, 0.42)
  synth:mixInto(master, 0.35)
  lead:mixInto(master, 0.26)
  metal:mixInto(master, 0.3)
  drums:mixInto(master, 0.7)
  master:drive(0.75) -- squashed a little, to sit about as loud as the others
  return master:toSoundData(0.9)
end

return Theme
