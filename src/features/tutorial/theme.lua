-- The tutorial's soundtracks, one per map, rendered by src/audio/synth.lua
-- like the other quests' themes (karen/theme.lua). music.lua plays them.
--
--   tutorial-road  Shoeman's Road: a boot-camp march, 120 BPM in C major.
--                  Oom-pah bass, a fife on top, a snare that drills.
--   tutorial-park  Shoeman's Park: a chase, 168 BPM in A minor. Running
--                  xylophone, and every so often a shoe whistling down.
--   tutorial-yard  Shoeman's Scrap Yard: slow and heavy, 96 BPM in E minor.
--                  A fuzz riff, scrap metal clanking on the offbeats.
--   tutorial-city  Shoeman's Town: a lazy groove, 108 BPM in D minor. An
--                  organ on the backbeat, a whistled tune, hammers tapping.
--
-- Each song is data read by one renderer: chord progressions (one chord a
-- bar), sixteen-step patterns for the bass, the chords and the drums, and
-- the tunes as "note/sixteenths" tokens ("r" a rest). Bass pattern steps:
-- "1" the root, "3" the third, "5" the fifth, "7" the flat seventh, "8"
-- the octave, "-" holds the note before, "." silence.

local Synth = require("src.audio.synth")

local Theme = {}

Theme.SONGS = {
  ["tutorial-road"] = {
    bpm = 120,
    bassOctave = 2,
    chordOctave = 4,
    bass = { pattern = "1.......5.......", wave = "tri", amp = 0.7, decay = 0.25, sustain = 0.3 },
    chords = { pattern = "....x.......x...", wave = "square", amp = 0.11, decay = 0.08, sustain = 0 },
    drums = {
      kick = "x.......x.......",
      snare = "x..x..x.x.x.xxxx",
      snareAmp = 0.45,
    },
    lead = { wave = "square", amp = 0.24, decay = 0.6, sustain = 0.6, vibRate = 6, vibDepth = 0.12 },
    progs = {
      intro = { "C", "C" },
      verse = { "C", "C", "G", "C", "F", "C", "G", "C" },
      bridge = { "Am", "Am", "F", "G" },
    },
    tunes = {
      verse = "G4/2 C5/2 C5/2 C5/2 E5/4 C5/4  D5/2 E5/2 F5/2 E5/2 D5/4 C5/4  B4/4 D5/4 G5/4 F5/2 D5/2  "
        .. "E5/4 C5/4 C5/8  A5/4 A5/2 G5/2 F5/4 A5/4  G5/4 E5/4 C5/8  D5/2 E5/2 F5/2 D5/2 B4/4 G4/4  "
        .. "C5/4 G4/4 C5/8",
      bridge = "A5/8 E5/8  F5/8 C5/8  A5/4 G5/4 F5/4 D5/4  G5/12 r/4",
    },
    parts = {
      { prog = "intro" },
      { prog = "verse", tune = "verse" },
      { prog = "bridge", tune = "bridge", harmony = -12 },
      { prog = "verse", tune = "verse", harmony = -12 },
    },
  },

  ["tutorial-park"] = {
    bpm = 168,
    bassOctave = 2,
    chordOctave = 4,
    bass = { pattern = "1...5...1...5...", wave = "square", amp = 0.45, decay = 0.12, sustain = 0.2 },
    chords = { pattern = "..x...x...x...x.", wave = "square", amp = 0.1, decay = 0.05, sustain = 0 },
    drums = {
      kick = "x...x...x...x...",
      snare = "....x.......x...",
      hat = "xxxxxxxxxxxxxxxx",
      hatAmp = 0.12,
    },
    lead = { wave = "tri", amp = 0.42, decay = 0.12, sustain = 0.1, length = 0.7 },
    progs = {
      chase = { "Am", "Am", "E", "E", "Am", "Am", "Dm", "E" },
      dodge = { "F", "G", "E", "Am" },
    },
    tunes = {
      chase = "A5/1 B5/1 C6/2 A5/2 E5/2 A5/2 C6/2 B5/2 A5/2  E6/2 D6/2 C6/2 B5/2 A5/4 r/4  "
        .. "G#5/1 A5/1 B5/2 G#5/2 E5/2 B5/2 E6/2 D6/2 B5/2  D6/2 C6/2 B5/2 G#5/2 E5/4 r/4  "
        .. "A5/1 B5/1 C6/2 A5/2 E5/2 A5/2 C6/2 B5/2 A5/2  C6/2 E6/2 A6/4 G#6/2 A6/2 E6/4  "
        .. "F6/2 E6/2 D6/2 C6/2 A5/2 D6/2 F6/4  E6/4 B5/2 G#5/2 E5/8",
    },
    -- A shoe whistling down and landing: once a bar through the dodge.
    fx = function(buf, t)
      buf:sweep(t, 0.55, 2400, 500, { wave = "sine", amp = 0.3, decay = 0.5 })
      buf:noiseBurst(t + 0.55, 0.12, { amp = 0.5, decay = 0.03 })
      buf:kick(t + 0.55, 0.8)
    end,
    parts = {
      { prog = "chase", tune = "chase" },
      { prog = "dodge", fx = "x..............." },
      { prog = "chase", tune = "chase", harmony = -12 },
      { prog = "dodge", fx = "x..............." },
    },
  },

  ["tutorial-yard"] = {
    bpm = 96,
    bassOctave = 1,
    chordOctave = 3,
    bass = { pattern = "1.11..1.1.11.3.5", wave = "saw", amp = 0.5, decay = 0.15, sustain = 0.3, drive = 3 },
    chords = { pattern = "x.xx..x.x.xx....", wave = "saw", amp = 0.2, decay = 0.2, sustain = 0.3, power = true,
      drive = 7, lowpass = 2500 },
    drums = {
      kick = "x..x..x.x..x....",
      snare = "....x.......x...",
      hat = "x.x.x.x.x.x.x.x.",
      hatAmp = 0.18,
    },
    lead = { wave = "saw", amp = 0.2, decay = 1.2, sustain = 0.7, vibRate = 5, vibDepth = 0.2, lowpass = 3000 },
    progs = {
      riff = { "Em", "Em", "Em", "Em" },
      verse = { "Em", "Em", "C", "D" },
    },
    tunes = {
      verse = "E4/8 G4/4 F#4/4  E4/12 r/4  C5/8 B4/4 G4/4  A4/8 F#4/8",
    },
    -- Scrap metal struck: two clashing high partials over a rattle.
    fx = function(buf, t)
      buf:tone(t, 0.05, 1243, { wave = "tri", amp = 0.18, decay = 0.12, sustain = 0, release = 0.2 })
      buf:tone(t, 0.05, 1731, { wave = "tri", amp = 0.14, decay = 0.09, sustain = 0, release = 0.15 })
      buf:noiseBurst(t, 0.15, { amp = 0.22, decay = 0.04 })
    end,
    parts = {
      { prog = "riff", fx = "......x.......x." },
      { prog = "verse", fx = "......x.......x." },
      { prog = "verse", tune = "verse", fx = "......x.......x." },
      { prog = "verse", tune = "verse", harmony = 12 },
    },
  },

  ["tutorial-city"] = {
    bpm = 108,
    bassOctave = 2,
    chordOctave = 4,
    bass = { pattern = "1-.8..1.5.7.8.5.", wave = "square", amp = 0.4, decay = 0.2, sustain = 0.4, lowpass = 900 },
    chords = { pattern = "....x-......x-..", wave = "sine", amp = 0.16, decay = 0.4, sustain = 0.6, organ = true },
    drums = {
      kick = "x.....x...x.....",
      snare = "....x.......x...",
      hat = "x.xox.x.x.xox.x.",
      hatAmp = 0.16,
    },
    lead = { wave = "sine", amp = 0.3, decay = 0.8, sustain = 0.7, vibRate = 5.5, vibDepth = 0.18 },
    progs = {
      groove = { "Dm", "Dm", "G", "G", "Dm", "Dm", "F", "G" },
      site = { "A#", "C", "Dm", "Dm" },
    },
    tunes = {
      groove = "A5/4 C6/2 A5/2 G5/4 F5/4  D5/8 r/4 F5/2 G5/2  B5/4 A5/2 G5/2 D5/4 G5/4  A5/12 r/4  "
        .. "A5/2 A5/2 C6/2 D6/2 C6/4 A5/4  G5/4 F5/4 D5/8  F5/2 G5/2 A5/4 C6/4 A5/4  G5/12 r/4",
    },
    -- A hammer tapping a nail in, somewhere on a plot.
    fx = function(buf, t)
      buf:tone(t, 0.02, 880, { wave = "tri", amp = 0.2, decay = 0.05, sustain = 0, release = 0.08 })
      buf:noiseBurst(t, 0.04, { amp = 0.25, decay = 0.01 })
    end,
    parts = {
      { prog = "site", fx = "x.x.....x.x....." },
      { prog = "groove", tune = "groove" },
      { prog = "site", fx = "x.x.....x.x....." },
      { prog = "groove", tune = "groove", harmony = -12 },
    },
  },
}

-- Notation ------------------------------------------------------------------

--- "Am" -> root MIDI number in `octave` and whether it is minor.
local function chord(name, octave)
  local root, minor = name:match("^([A-G]#?)(m?)$")
  assert(root, "bad chord " .. tostring(name))
  return Synth.midi(root .. octave), minor == "m"
end

local STEP = { ["1"] = 0, ["5"] = 7, ["7"] = 10, ["8"] = 12 }

--- Semitones above the root of bass step `c`, or nil for "." and "-".
local function interval(c, minor)
  if c == "3" then
    return minor and 3 or 4
  end
  return STEP[c]
end

--- How many sixteenths the step at `i` of `pattern` lasts (its "-" ties included).
local function length(pattern, i)
  local n = 1
  while pattern:sub(i + n, i + n) == "-" do
    n = n + 1
  end
  return n
end

--- A tune's tokens as { { midi|false, sixteenths }, ... }.
local function notes(tune)
  local out = {}
  for name, len in tune:gmatch("(%S+)/(%d+)") do
    out[#out + 1] = { name ~= "r" and Synth.midi(name), tonumber(len) }
  end
  return out
end

local function partBars(song, part)
  return #song.progs[part.prog]
end

function Theme.duration(map)
  local song = Theme.SONGS[map]
  local total = 0
  for _, part in ipairs(song.parts) do
    total = total + partBars(song, part)
  end
  return total * 16 * 60 / song.bpm / 4
end

-- Render ----------------------------------------------------------------------

local function voice(o, extra)
  local v = { wave = o.wave, amp = o.amp, decay = o.decay, sustain = o.sustain, vibRate = o.vibRate,
    vibDepth = o.vibDepth }
  for k, x in pairs(extra or {}) do
    v[k] = x
  end
  return v
end

local function renderBar(song, bufs, t, name, part, sixteenth)
  local root, minor = chord(name, song.bassOctave)
  local b, c, d = song.bass, song.chords, song.drums
  for i = 1, 16 do
    local ti = t + (i - 1) * sixteenth
    local step = interval(b.pattern:sub(i, i), minor)
    if step then
      bufs.bass:tone(ti, length(b.pattern, i) * sixteenth * 0.9, Synth.midiFreq(root + step), voice(b))
    end
    if c.pattern:sub(i, i) == "x" then
      local dur = length(c.pattern, i) * sixteenth * 0.9
      local base = chord(name, song.chordOctave)
      local tones = c.power and { 0, 7, 12 } or { 0, minor and 3 or 4, 7 }
      for _, semis in ipairs(tones) do
        bufs.chords:tone(ti, dur, Synth.midiFreq(base + semis), voice(c))
        if c.organ then
          bufs.chords:tone(ti, dur, Synth.midiFreq(base + semis + 12), voice(c, { amp = c.amp * 0.4 }))
        end
      end
    end
    if d.kick:sub(i, i) == "x" then
      bufs.drums:kick(ti, 1)
    end
    if d.snare:sub(i, i) == "x" then
      bufs.drums:snare(ti, d.snareAmp or 0.8)
    end
    local h = d.hat and d.hat:sub(i, i)
    if h == "x" or h == "o" then
      bufs.drums:hat(ti, d.hatAmp or 0.2, h == "o")
    end
    if part.fx and part.fx:sub(i, i) == "x" then
      song.fx(bufs.fx, ti)
    end
  end
end

local function renderTune(song, buf, t, tune, harmony, sixteenth)
  local o = song.lead
  for _, n in ipairs(notes(tune)) do
    local midi, len = n[1], n[2]
    if midi then
      local dur = len * sixteenth * (o.length or 0.92)
      buf:tone(t, dur, Synth.midiFreq(midi), voice(o))
      if harmony then
        buf:tone(t, dur, Synth.midiFreq(midi + harmony), voice(o, { amp = o.amp * 0.5 }))
      end
    end
    t = t + len * sixteenth
  end
end

local function finish(buf, o)
  if o.drive then
    buf:drive(o.drive)
  end
  if o.lowpass then
    buf:lowpass(o.lowpass)
  end
end

--- Renders `map`'s whole song, exactly one loop long. Returns a SoundData.
function Theme.render(map)
  local song = Theme.SONGS[map]
  local sixteenth = 60 / song.bpm / 4
  local total = Theme.duration(map)
  local bufs = {}
  for _, k in ipairs({ "bass", "chords", "lead", "drums", "fx" }) do
    bufs[k] = Synth.newBuffer(total + 0.5)
  end

  local t = 0
  for _, part in ipairs(song.parts) do
    if part.tune then
      renderTune(song, bufs.lead, t, song.tunes[part.tune], part.harmony, sixteenth)
    end
    for _, name in ipairs(song.progs[part.prog]) do
      renderBar(song, bufs, t, name, part, sixteenth)
      t = t + 16 * sixteenth
    end
  end

  finish(bufs.bass, song.bass)
  finish(bufs.chords, song.chords)
  finish(bufs.lead, song.lead)
  bufs.drums:highpass(30)

  local master = Synth.newBuffer(total) -- exactly the loop's length so it wraps cleanly
  bufs.bass:mixInto(master, 0.5)
  bufs.chords:mixInto(master, 0.45)
  bufs.lead:mixInto(master, 0.4)
  bufs.drums:mixInto(master, 0.7)
  bufs.fx:mixInto(master, 0.5)
  return master:toSoundData(0.9)
end

--- Asserts each tune is exactly as long as the bars it is played over; run it after editing a song.
function Theme.check()
  for map, song in pairs(Theme.SONGS) do
    for _, part in ipairs(song.parts) do
      if part.tune then
        local n = 0
        for _, note in ipairs(notes(song.tunes[part.tune])) do
          n = n + note[2]
        end
        assert(n == partBars(song, part) * 16, ("%s: tune %s is %d sixteenths, its bars %d"):format(map,
          part.tune, n, partBars(song, part) * 16))
      end
    end
  end
  return true
end

return Theme
