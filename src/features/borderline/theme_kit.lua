-- What the Borderline themes share (theme_wreck.lua, theme_landing.lua),
-- rendered by src/audio/synth.lua: notes by name, the rhythm guitar's power
-- chords, the bass under them, struck metal; the band's buffers, a
-- half-time chug, and the desk that mixes it all down.

local Synth = require("src.audio.synth")

local Kit = {}

--- The frequency of `note` ("E2"), `semis` semitones up.
function Kit.freq(note, semis)
  return Synth.midiFreq(Synth.midi(note) + (semis or 0))
end

--- A power chord on `root` (root, fifth, octave), detuned wide, with the
--- low string an octave under it. Muted: a short thump; open: rung out.
function Kit.powerChord(buf, t, dur, root, muted)
  local f = Kit.freq(root)
  local o = muted and { amp = 0.38, decay = 0.045, sustain = 0 } or { amp = 0.26, decay = 0.9, sustain = 0.6 }
  o.wave = "saw"
  for _, d in ipairs({ -14, 14 }) do
    o.detune = d
    buf:tone(t, dur, f, o)
    buf:tone(t, dur, f * 1.5, o)
  end
  o.detune = 0
  o.amp = o.amp * 0.7
  buf:tone(t, dur, f / 2, o)
  o.amp = o.amp * 0.5
  buf:tone(t, dur, f * 2, o)
end

--- The bass under it, an octave down: muted short, or held.
function Kit.bassNote(buf, t, dur, root, muted)
  buf:tone(t, dur, Kit.freq(root) / 2, { wave = "square", amp = 0.5, decay = muted and 0.08 or 0.6,
    sustain = muted and 0 or 0.6 })
end

--- Struck metal: partials that don't line up (an anvil, a rail, a girder,
--- a bell), ringing on after the hit. `f` the lowest, `ring` how long it sings.
function Kit.clang(buf, t, f, amp, ring)
  for i, k in ipairs({ 1, 2.32, 4.25, 6.63, 9.1 }) do
    buf:tone(t, ring, f * k, { wave = "sine", amp = amp / i, attack = 0.001, decay = ring / (i * 0.8), sustain = 0 })
  end
  buf:noiseBurst(t, 0.02, { amp = amp * 0.6, decay = 0.006 })
end

--- How long `sections` ({ bars } each) last at `bar` seconds a bar.
function Kit.duration(sections, bar)
  local bars = 0
  for _, s in ipairs(sections) do
    bars = bars + s.bars
  end
  return bars * bar
end

--- The band for `total` seconds: a buffer each for the rhythm guitar's
--- open chords, its palm-muted chugs (darker), the bass, the sub, the
--- lead, the drums, the snare's room (`verb`) and struck metal, plus one
--- for each name in `extras`; and `mute(t, len, note)` and `ring(t, len,
--- note)` playing a chord with the bass under it.
function Kit.band(total, extras)
  local band = {}
  for _, name in ipairs({ "rhythm", "chug", "bass", "sub", "lead", "drums", "verb", "metal" }) do
    band[name] = Synth.newBuffer(total + 1)
  end
  for _, name in ipairs(extras or {}) do
    band[name] = Synth.newBuffer(total + 1)
  end
  function band.mute(t, len, note)
    Kit.powerChord(band.chug, t, len, note, true)
    Kit.bassNote(band.bass, t, len, note, true)
  end
  function band.ring(t, len, note)
    Kit.powerChord(band.rhythm, t, len, note, false)
    Kit.bassNote(band.bass, t, len, note, false)
  end
  return band
end

--- A bar of half-time chugs from `t`: on each `x` of `pattern` (a step
--- `step` seconds), `note` muted, `low` booming under it and the kick.
function Kit.chugs(band, t, pattern, step, note, low)
  for i = 1, #pattern do
    if pattern:sub(i, i) == "x" then
      local ti = t + (i - 1) * step
      band.mute(ti, step * 0.9, note)
      band.sub:tone(ti, step * 1.5, Kit.freq(low), { wave = "sine", amp = 0.6, decay = 0.2, sustain = 0 })
      band.drums:kick(ti, 1)
    end
  end
end

--- The desk: each of `desk`'s { name, gain, drive, lowpass, highpass } in
--- turn, the band's buffer by that name driven and filtered and mixed
--- down into exactly `total` seconds (so a loop wraps cleanly), its peaks
--- squeezed a little to sit as loud as the others. Returns a SoundData.
function Kit.mixdown(band, total, desk)
  local master = Synth.newBuffer(total)
  for _, ch in ipairs(desk) do
    local buf = band[ch[1]]
    if ch.drive then
      buf:drive(ch.drive)
    end
    if ch.lowpass then
      buf:lowpass(ch.lowpass)
    end
    if ch.highpass then
      buf:highpass(ch.highpass)
    end
    buf:mixInto(master, ch[2])
  end
  master:drive(0.7 / math.max(master:peak(), 1e-6))
  return master:toSoundData(0.9)
end

--- Plays `tune` (a bar of { note|false, units }) from `t`, a unit `unit`
--- seconds, through `voice(t, dur, note)`.
function Kit.play(tune, t, unit, voice)
  for _, n in ipairs(tune) do
    if n[1] then
      voice(t, n[2] * unit, n[1])
    end
    t = t + n[2] * unit
  end
end

--- Renders `sections` ({ bars, kind } each) at `bar` seconds a bar: a band
--- (Kit.band, with `extras`), each bar of each section played into it by
--- `play[kind](band, t, b, section)`, then mixed down at `desk`. Returns a
--- SoundData.
function Kit.render(sections, bar, extras, play, desk)
  local total = Kit.duration(sections, bar)
  local band = Kit.band(total, extras)
  local t = 0
  for _, s in ipairs(sections) do
    for b = 1, s.bars do
      play[s.kind](band, t, b, s)
      t = t + bar
    end
  end
  return Kit.mixdown(band, total, desk)
end

--- Give `theme` its music.lua side from `spec` { bar, intro, sections,
--- extras, play, desk } (as Kit.render takes them): `duration()` the loop's
--- length, `render()` the loop, `renderIntro()` the intro before it, each a
--- SoundData.
function Kit.theme(theme, spec)
  function theme.duration()
    return Kit.duration(spec.sections, spec.bar)
  end
  function theme.render()
    return Kit.render(spec.sections, spec.bar, spec.extras, spec.play, spec.desk)
  end
  function theme.renderIntro()
    return Kit.render(spec.intro, spec.bar, spec.extras, spec.play, spec.desk)
  end
  return theme
end

return Kit
