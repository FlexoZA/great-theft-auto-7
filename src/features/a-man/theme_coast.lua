-- The Coast's theme (quests' "a-man-coast"), rendered by src/audio/synth.lua
-- like A-Man's own. Wide open and uneasy, the way Half-Life's road up the
-- coast sounds: the sea swelling and gulls far off over a warm pad, a
-- plucked guitar arpeggio echoing round Am - F - C - G; then something
-- under the sand, a low throbbing bass, skittering clicks and a tom
-- pattern, the chords gone dark with a flat second; and the arpeggio back
-- with a slide-guitar melody over it. 96 BPM in A minor, ~70 s, loops.

local Synth = require("src.audio.synth")

local Theme = {}

local BPM = 96
local SIXTEENTH = 60 / BPM / 4
local BAR = SIXTEENTH * 16
local RATE = Synth.RATE

local CHORDS = {
  { "A2", "C3", "E3" }, -- Am
  { "F2", "A2", "C3" }, -- F
  { "C3", "E3", "G3" }, -- C
  { "G2", "B2", "D3" }, -- G
}
-- Under the sand: the same roots, dark.
local DARK = {
  { "A2", "C3", "E3" }, -- Am
  { "A#2", "D3", "F3" }, -- Bb: the flat second
  { "A2", "C3", "E3" },
  { "G#2", "B2", "E3" }, -- E over G#
}

-- The melody, the last time round: four bars of { note|false, sixteenths }.
local MELODY = {
  { { "E4", 6 }, { "D4", 2 }, { "C4", 4 }, { "E4", 4 } },
  { { "F4", 8 }, { "A4", 4 }, { "G4", 4 } },
  { { "E4", 6 }, { "G4", 2 }, { "C5", 4 }, { "B4", 4 } },
  { { "D5", 8 }, { "B4", 4 }, { false, 4 } },
}

local SECTIONS = {
  { bars = 4, intro = true },
  { bars = 8, open = true },
  { bars = 8, dark = true },
  { bars = 8, open = true, melody = true },
}

local function up(note, octaves)
  return Synth.freq(note) * 2 ^ octaves
end

--- The sea: a swell of soft noise rising and falling over `len` seconds.
local function swell(buf, t, len, amp)
  local s0 = math.floor(t * RATE)
  local s1 = math.min(buf.n - 1, s0 + math.floor(len * RATE))
  local data = buf.data
  local last = 0
  for i = s0, s1 do
    local k = (i - s0) / (s1 - s0)
    local env = math.sin(k * math.pi) ^ 2
    local n = Synth.noise()
    last = last + 0.08 * (n - last) -- a soft wash, not hiss
    data[i] = data[i] + last * amp * env
  end
end

--- A gull, far off: two falling cries.
local function gull(buf, t)
  for k = 0, 1 do
    buf:sweep(t + k * 0.28, 0.22, 1900 - k * 120, 1250, { wave = "tri", amp = 0.05, decay = 0.15 })
  end
end

local function pad(buf, t, chord, len, amp)
  for k, n in ipairs(chord) do
    buf:tone(t, len, up(n, 0), { wave = "tri", amp = amp, attack = 0.8, decay = 99, sustain = 1, release = 0.8,
      detune = (k - 2) * 6 })
    buf:tone(t, len, up(n, 1), { wave = "sine", amp = amp * 0.6, attack = 1.0, decay = 99, sustain = 1,
      release = 0.8, detune = -(k - 2) * 5 })
  end
end

--- The plucked arpeggio in eighths, each note echoing a dotted eighth later.
local function arpeggio(buf, t, chord, amp)
  local order = { 1, 2, 3, 2, 3, 1, 2, 3 }
  for i = 0, 7 do
    local n = chord[order[i + 1]]
    local oct = (i == 4 or i == 6) and 2 or 1
    local f = up(n, oct)
    local ti = t + i * 2 * SIXTEENTH
    buf:tone(ti, SIXTEENTH * 3, f, { wave = "tri", amp = amp, attack = 0.002, decay = 0.25, sustain = 0 })
    buf:tone(ti, SIXTEENTH * 3, f * 2, { wave = "saw", amp = amp * 0.15, attack = 0.002, decay = 0.08, sustain = 0 })
    buf:tone(ti + 3 * SIXTEENTH, SIXTEENTH * 3, f, { wave = "tri", amp = amp * 0.35, attack = 0.002, decay = 0.25,
      sustain = 0 }) -- the echo
  end
end

--- Under the sand: a low pulse on the root in eighths, swelling and dying.
local function throb(buf, t, chord)
  for i = 0, 7 do
    buf:tone(t + i * 2 * SIXTEENTH, SIXTEENTH * 1.6, Synth.freq(chord[1]) / 2, { wave = "saw",
      amp = 0.45 * (0.6 + 0.4 * math.sin(i / 7 * math.pi)), decay = 0.12, sustain = 0 })
  end
end

--- Skittering clicks, like claws on stone: a burst of them here and there.
local function clicks(buf, t, bar)
  for i = 0, 15 do
    local h = math.sin(bar * 12.9898 + i * 78.233) * 43758.5453
    h = h - math.floor(h)
    if h < 0.45 then
      local ti = t + i * SIXTEENTH
      buf:tone(ti, 0.012, 2600 + h * 1800, { wave = "square", amp = 0.08, attack = 0.001, decay = 0.006, sustain = 0 })
      if h < 0.2 then
        buf:tone(ti + SIXTEENTH * 0.5, 0.012, 2200 + h * 1500, { wave = "square", amp = 0.06, attack = 0.001,
          decay = 0.006, sustain = 0 })
      end
    end
  end
end

--- A low tom.
local function tom(buf, t, amp)
  buf:sweep(t, 0.3, 140, 70, { wave = "sine", amp = amp, decay = 0.12 })
  buf:noiseBurst(t, 0.02, { amp = amp * 0.3, decay = 0.006 })
end

local function drumBar(buf, t, style, fill)
  for i = 0, 15 do
    local ti = t + i * SIXTEENTH
    if fill and i >= 12 then
      tom(buf, ti, 0.5 + (i - 12) * 0.1)
    elseif style == "dark" then
      if i == 0 or i == 3 or i == 10 then
        tom(buf, ti, 0.7)
      end
      if i == 8 then
        buf:snare(ti, 0.5)
      end
      if i % 2 == 1 then
        buf:hat(ti, 0.1)
      end
    elseif style == "light" then
      if i == 0 or i == 10 then
        buf:kick(ti, 0.55)
      end
      if i == 4 or i == 12 then
        buf:hat(ti, 0.22, true) -- a brushed backbeat
      end
      if i % 2 == 0 then
        buf:hat(ti, 0.08)
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
  local sea = Synth.newBuffer(total + 0.5)
  local pads = Synth.newBuffer(total + 2)
  local guitar = Synth.newBuffer(total + 0.5)
  local bass = Synth.newBuffer(total + 0.5)
  local lead = Synth.newBuffer(total + 0.5)
  local drums = Synth.newBuffer(total + 0.5)

  local t, n = 0, 0
  for _, s in ipairs(SECTIONS) do
    for b = 1, s.bars do
      n = n + 1
      local phrase = (b - 1) % 4 + 1
      local last = b == s.bars
      if b % 2 == 1 then
        swell(sea, t, BAR * 2, s.dark and 0.35 or 0.6) -- the sea, all the way through
      end
      if s.intro then
        pad(pads, t, CHORDS[phrase], BAR, 0.12)
        if b == 2 or b == 4 then
          gull(sea, t + BAR * 0.4)
        end
      elseif s.dark then
        local chord = DARK[phrase]
        pad(pads, t, chord, BAR, 0.08)
        throb(bass, t, chord)
        clicks(drums, t, n)
        drumBar(drums, t, "dark", last)
      else
        local chord = CHORDS[phrase]
        pad(pads, t, chord, BAR, 0.1)
        arpeggio(guitar, t, chord, s.melody and 0.22 or 0.26)
        bass:tone(t, BAR * 0.9, Synth.freq(chord[1]) / 2, { wave = "tri", amp = 0.4, attack = 0.02, decay = 1.2,
          sustain = 0.3 })
        drumBar(drums, t, "light", false)
        if s.melody then
          local cursor = t
          for _, ev in ipairs(MELODY[phrase]) do
            local dur = ev[2] * SIXTEENTH
            if ev[1] then -- a slide guitar: it slides up into each note and wavers on the long ones
              local f = Synth.freq(ev[1])
              lead:sweep(cursor, 0.06, f * 0.94, f, { wave = "tri", amp = 0.2, decay = 99 })
              lead:tone(cursor + 0.06, dur * 0.95 - 0.06, f, { wave = "tri", amp = 0.2, attack = 0.005, decay = 1.5,
                sustain = 0.6, release = 0.15, vibRate = 5, vibDepth = ev[2] >= 6 and 0.3 or 0.1 })
              lead:tone(cursor + 0.06, dur * 0.95 - 0.06, f * 2, { wave = "sine", amp = 0.05, decay = 1.0,
                sustain = 0.4, release = 0.15 })
            end
            cursor = cursor + dur
          end
        elseif b == 3 or b == 7 then
          gull(sea, t + BAR * 0.6)
        end
      end
      t = t + BAR
    end
  end

  sea:lowpass(1400)
  pads:lowpass(2200)
  guitar:lowpass(3800)
  bass:drive(1.6)
  bass:lowpass(500)
  lead:drive(1.5)
  lead:lowpass(4000)
  drums:highpass(40)

  local master = Synth.newBuffer(total)
  sea:mixInto(master, 0.5)
  pads:mixInto(master, 0.45)
  guitar:mixInto(master, 0.5)
  bass:mixInto(master, 0.45)
  lead:mixInto(master, 0.4)
  drums:mixInto(master, 0.55)
  master:drive(2.4) -- gently squashed, to sit as loud as City 17's
  return master:toSoundData(0.9)
end

return Theme
