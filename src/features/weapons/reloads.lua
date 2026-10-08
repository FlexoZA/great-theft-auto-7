-- Reload sounds and the clicks of an empty gun.
--
-- A reload is a timeline of small parts (the catch, the magazine sliding
-- out and clattering on the ground, a fresh one slapped in, the slide
-- racked and let go...) spread over however long that reload really takes,
-- so a legendary gun's quicker reload sounds quicker too. Each part plays
-- where the shooter is at that moment, so it follows them about.
--
-- An empty gun clicks loud and centred in your ears when you pull the
-- trigger, and the last round out of a magazine ends with a little ping.

local Synth = require("src.audio.synth")
local Sounds = require("src.features.weapons.sounds")

local Reloads = {}

local queue = {} -- { t = seconds until it plays, name, pitch, id = shooter, or x and y }

-- Parts -----------------------------------------------------------------------

--- A sharp metal click: a tick of noise, a square snap and a short ring.
local function tick(buf, t, freq, amp)
  buf:noiseBurst(t, 0.02, { amp = amp, decay = 0.003 })
  buf:tone(t, 0.03, freq, { wave = "square", amp = amp * 0.35, attack = 0.0005, decay = 0.008, sustain = 0 })
  buf:tone(t, 0.06, freq * 1.9, { wave = "sine", amp = amp * 0.25, attack = 0.0005, decay = 0.02, sustain = 0 })
end

--- Metal sliding over metal: a gritty scrape whose pitch runs f0 -> f1.
local function scrape(buf, t, dur, f0, f1, amp)
  buf:noiseBurst(t, dur, { amp = amp * 0.45, decay = dur })
  buf:sweep(t, dur, f0, f1, { wave = "saw", amp = amp * 0.22, decay = dur })
  for k = 0, 7 do -- the grit
    buf:noiseBurst(t + dur * k / 8, 0.004, { amp = amp * 0.35, decay = 0.001 })
  end
end

--- Something solid knocking on something: a short falling thud.
local function knock(buf, t, freq, amp, decay)
  buf:sweep(t, decay * 4, freq * 1.3, freq, { wave = "sine", amp = amp, decay = decay })
  buf:noiseBurst(t, 0.03, { amp = amp * 0.4, decay = 0.006 })
end

local function between(lo, hi)
  return lo + (Synth.noise() * 0.5 + 0.5) * (hi - lo)
end

local PARTS = {
  -- the catch that lets a magazine or a breech go
  catch = { 0.08, 0.7, function(buf)
    tick(buf, 0, 2000, 0.6)
    buf:highpass(600)
  end },
  -- the empty magazine sliding out...
  ["mag-out"] = { 0.2, 0.7, function(buf)
    scrape(buf, 0, 0.14, 700, 350, 0.6)
    tick(buf, 0.14, 1100, 0.25)
  end },
  -- ...and clattering on the ground, bouncing twice
  ["mag-drop"] = { 0.35, 0.55, function(buf)
    local f = between(560, 760)
    knock(buf, 0, f, 0.8, 0.012)
    tick(buf, 0, f * 2.3, 0.3)
    knock(buf, between(0.09, 0.12), f * 1.05, 0.45, 0.01)
    knock(buf, between(0.16, 0.2), f * 1.1, 0.2, 0.008)
    buf:lowpass(4500)
  end, takes = 3 },
  -- a fresh magazine slapped home and latched
  ["mag-in"] = { 0.16, 0.9, function(buf)
    knock(buf, 0, 300, 1.0, 0.025)
    scrape(buf, 0.01, 0.04, 500, 700, 0.4)
    tick(buf, 0.05, 1400, 0.8)
  end },
  -- the slide or charging handle pulled back...
  ["rack-back"] = { 0.16, 0.8, function(buf)
    scrape(buf, 0, 0.1, 450, 1300, 0.7)
    tick(buf, 0.1, 1100, 0.6)
  end },
  -- ...and let go: the sharp clack that says it's loaded
  ["rack-forward"] = { 0.14, 0.95, function(buf)
    tick(buf, 0, 1600, 1.0)
    knock(buf, 0, 500, 0.5, 0.012)
    buf:highpass(200)
  end },
  -- a round or a shell pushed in, brass ringing a little
  shell = { 0.12, 0.6, function(buf)
    tick(buf, 0, between(1100, 1300), 0.5)
    buf:tone(0, 0.08, between(3000, 3400), { wave = "sine", amp = 0.2, attack = 0.0005, decay = 0.035, sustain = 0 })
    knock(buf, 0.005, 400, 0.3, 0.01)
  end, takes = 3 },
  -- a shotgun's pump back...
  ["pump-back"] = { 0.2, 0.9, function(buf)
    scrape(buf, 0, 0.12, 300, 800, 0.8)
    knock(buf, 0.11, 250, 0.7, 0.02)
    tick(buf, 0.11, 900, 0.6)
  end },
  -- ...and forward, chunky
  ["pump-forward"] = { 0.2, 0.95, function(buf)
    scrape(buf, 0, 0.1, 800, 300, 0.8)
    knock(buf, 0.1, 220, 0.9, 0.025)
    tick(buf, 0.1, 700, 1.0)
  end },
  -- a bolt lifted, pulled back, run home and turned down
  ["bolt-up"] = { 0.08, 0.7, function(buf)
    tick(buf, 0, 900, 0.7)
    knock(buf, 0, 450, 0.3, 0.01)
  end },
  ["bolt-back"] = { 0.2, 0.8, function(buf)
    scrape(buf, 0, 0.14, 400, 1100, 0.7)
    tick(buf, 0.14, 1300, 0.6)
  end },
  ["bolt-forward"] = { 0.2, 0.9, function(buf)
    scrape(buf, 0, 0.12, 1100, 400, 0.7)
    tick(buf, 0.12, 800, 1.0)
    knock(buf, 0.12, 350, 0.5, 0.015)
  end },
  -- a missile slid down the launcher's tube, seated with a clunk
  ["tube-in"] = { 0.5, 0.7, function(buf)
    scrape(buf, 0, 0.45, 260, 160, 0.7)
    buf:lowpass(2200)
  end },
  ["tube-clunk"] = { 0.25, 0.95, function(buf)
    knock(buf, 0, 160, 1.0, 0.05)
    tick(buf, 0, 700, 0.6)
    buf:lowpass(3000)
  end },
  -- the launcher armed: two short electronic beeps
  ["arm-beep"] = { 0.2, 0.45, function(buf)
    local o = { wave = "square", amp = 0.5, attack = 0.002, decay = 1, sustain = 1, release = 0.01 }
    buf:tone(0, 0.05, 1760, o)
    buf:tone(0.1, 0.05, 1760, o)
    buf:lowpass(4000)
  end },
  -- a fuel tank's cap ratcheting round
  cap = { 0.25, 0.55, function(buf)
    for k = 0, 5 do
      tick(buf, k * 0.035, 2200, 0.4)
    end
    buf:sweep(0, 0.22, 900, 1200, { wave = "sine", amp = 0.12, decay = 0.2 }) -- a squeak
  end },
  -- the empty tank knocked off, hollow...
  ["can-off"] = { 0.3, 0.8, function(buf)
    knock(buf, 0, 420, 0.8, 0.03)
    buf:tone(0, 0.25, 1100, { wave = "sine", amp = 0.3, attack = 0.001, decay = 0.09, sustain = 0 })
  end },
  -- ...and a full one set on, heavy
  ["can-on"] = { 0.2, 0.9, function(buf)
    knock(buf, 0, 300, 1.0, 0.04)
    tick(buf, 0.01, 800, 0.5)
  end },
  -- the fuel line filling
  hiss = { 0.5, 0.4, function(buf)
    buf:noiseBurst(0, 0.5, { amp = 0.6, decay = 0.2 })
    buf:highpass(3000)
  end },
  -- Empty: the hammer falling on nothing, a hard "tchk"...
  dry = { 0.1, 0.9, function(buf)
    tick(buf, 0, 2600, 1.0)
    knock(buf, 0.012, 700, 0.5, 0.008)
    buf:highpass(500)
  end },
  -- ...the flamethrower's empty line spluttering...
  ["dry-tank"] = { 0.3, 0.75, function(buf)
    tick(buf, 0, 3000, 0.5) -- the igniter
    for k = 0, 2 do
      buf:noiseBurst(0.02 + k * 0.07, 0.05, { amp = 0.8 - k * 0.2, decay = 0.015 })
    end
    buf:lowpass(1800)
  end },
  -- ...and the last round out: the slide locking back with a ping.
  ["slide-lock"] = { 0.15, 0.6, function(buf)
    tick(buf, 0, 1500, 0.8)
    buf:tone(0, 0.12, 2500, { wave = "sine", amp = 0.4, attack = 0.0005, decay = 0.045, sustain = 0 })
  end },
}

-- Timelines: when each part plays, as a fraction of the whole reload, and
-- an optional pitch (heavier guns a touch lower).
local TIMELINES = {
  ["reload-pistol"] = {
    { 0.02, "catch" }, { 0.06, "mag-out" }, { 0.26, "mag-drop" }, { 0.55, "mag-in" },
    { 0.76, "rack-back" }, { 0.88, "rack-forward" },
  },
  ["reload-uzi"] = {
    { 0.02, "catch", 0.95 }, { 0.05, "mag-out", 0.9 }, { 0.22, "mag-drop", 0.95 }, { 0.5, "mag-in", 0.95 },
    { 0.74, "rack-back", 0.9 }, { 0.87, "rack-forward", 0.95 },
  },
  ["reload-ak47"] = {
    { 0.02, "catch", 0.85 }, { 0.05, "mag-out", 0.8 }, { 0.2, "mag-drop", 0.8 }, { 0.5, "mag-in", 0.8 },
    { 0.74, "rack-back", 0.85 }, { 0.87, "rack-forward", 0.82 },
  },
  ["reload-shotgun"] = {
    { 0.04, "shell" }, { 0.15, "shell", 0.97 }, { 0.26, "shell" }, { 0.37, "shell", 1.03 }, { 0.48, "shell" },
    { 0.59, "shell", 0.98 }, { 0.76, "pump-back" }, { 0.88, "pump-forward" },
  },
  ["reload-rocket"] = {
    { 0.03, "catch", 0.7 }, { 0.14, "tube-in" }, { 0.45, "tube-clunk" }, { 0.72, "catch", 0.8 },
    { 0.86, "arm-beep" },
  },
  ["reload-sniper"] = {
    { 0.02, "bolt-up" }, { 0.05, "bolt-back" }, { 0.2, "shell", 0.9 }, { 0.32, "shell", 0.92 },
    { 0.44, "shell", 0.9 }, { 0.56, "shell", 0.93 }, { 0.68, "shell", 0.9 }, { 0.84, "bolt-forward" },
    { 0.9, "bolt-up", 0.9 },
  },
  ["reload-flamethrower"] = {
    { 0.03, "cap" }, { 0.2, "can-off" }, { 0.45, "can-on" }, { 0.6, "cap", 0.9 }, { 0.78, "hiss" },
  },
  -- The minigun: the belt box unlatched and dropped, a new one clunked on,
  -- the belt fed in and the gun charged, all of it low and heavy.
  ["reload-minigun"] = {
    { 0.03, "catch", 0.7 }, { 0.12, "can-off", 0.75 }, { 0.22, "mag-drop", 0.6 }, { 0.45, "can-on", 0.7 },
    { 0.62, "mag-in", 0.65 }, { 0.8, "rack-back", 0.7 }, { 0.9, "rack-forward", 0.68 },
  },
}

function Reloads.load()
  for name, part in pairs(PARTS) do
    local seconds, level, build = part[1], part[2], part[3]
    local function render()
      return Sounds.make(seconds, build, level)
    end
    Sounds.add(name, part.takes and Sounds.takes(part.takes, render) or render())
  end
end

-- Playing ---------------------------------------------------------------------

--- Shooter `id` began reload `key` (a gun's reloadSound) lasting `seconds`.
function Reloads.start(key, id, seconds)
  local timeline = TIMELINES[key]
  if not timeline then
    return
  end
  Reloads.cancel(id, true) -- a new reload replaces one still going
  for _, step in ipairs(timeline) do
    queue[#queue + 1] = { t = step[1] * seconds, name = step[2], pitch = step[3] or 1, id = id, reload = true }
  end
end

--- Reload `key` lasting `seconds` at a fixed spot (x, y), for a shooter that
--- isn't a player (a boss).
function Reloads.startAt(key, x, y, seconds)
  for _, step in ipairs(TIMELINES[key] or {}) do
    queue[#queue + 1] = { t = step[1] * seconds, name = step[2], pitch = step[3] or 1, x = x, y = y }
  end
end

--- Play `name` from shooter `id` in `delay` seconds.
function Reloads.after(delay, name, id)
  queue[#queue + 1] = { t = delay, name = name, pitch = 1, id = id }
end

--- Drop whatever shooter `id` still had to play (they died or put the gun
--- away), or only their reload's parts if `reloadOnly`.
function Reloads.cancel(id, reloadOnly)
  for i = #queue, 1, -1 do
    if queue[i].id == id and (queue[i].reload or not reloadOnly) then
      table.remove(queue, i)
    end
  end
end

function Reloads.clear()
  queue = {}
end

--- Play the parts that are due, each where `locate(id)` says its shooter is
--- now (skipped if they are nowhere).
function Reloads.update(dt, locate)
  for i = #queue, 1, -1 do
    local q = queue[i]
    q.t = q.t - dt
    if q.t <= 0 then
      table.remove(queue, i)
      local x, y = q.x, q.y
      if not x then
        x, y = locate(q.id)
      end
      if x then
        Sounds.play(q.name, x, y, q.pitch * (0.97 + love.math.random() * 0.06))
      end
    end
  end
end

--- The trigger pulled on an empty `gun`, heard right in my ears.
function Reloads.dry(gun)
  Sounds.playHere(gun.tank and "dry-tank" or "dry")
end

--- For tests.
function Reloads.queue()
  return queue
end

return Reloads
