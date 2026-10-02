-- Horns: hold the horn key while driving and everyone near hears your car
-- for as long as you lean on it. Each kind of vehicle has its own: a
-- hatchback beeps, a sedan has the two-tone car horn, an SUV's is deeper,
-- a motorbike meeps, a van's is harsh and a truck or bus blasts an air horn.
-- Bots lean on theirs for a moment when somebody rams them.
--
-- The host decides: a client only says the key went down or up, the host
-- checks the player is driving and tells everyone which car is honking.
--
-- Messages
--   client -> server  HRN_PRESS <0|1>        my horn key went up / down
--   server -> all     HRN <vid> <0|1>        that car's horn stopped / started

local Protocol = require("src.net.protocol")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Controls = require("src.controls")
local Features = require("src.features")
local Profiles = require("src.features.engine-sound.profiles")

local Horns = {
  name = "horns",
}

-- Tuning ------------------------------------------------------------------
Horns.volume = 0.7 -- default level of the "horns" channel
Horns.key = "v" -- default binding of the "horn" action
Horns.refDistance = 260 -- px: full volume inside this radius
Horns.maxDistance = 2400 -- px: quietest beyond this
Horns.minHonk = 0.15 -- s: a tap still beeps this long
Horns.maxHonk = 8 -- s: the host lets go of a horn held longer than this
Horns.botHonk = { 0.35, 0.9 } -- s a rammed bot leans on it (random between)
Horns.botCooldown = 4 -- s before the same bot honks again
Horns.attack, Horns.release = 0.02, 0.07 -- s to swell in and die away

-- Which horn a vehicle has, by its engine (engine-sound's profiles).
local BY_ENGINE = {
  classic = "car", sedan = "car", compact = "beep", v8 = "deep", bike = "meep",
  diesel = "van", truck = "air", hauler = "air",
}

-- The horns: tones in Hz (whole numbers, so a one-second loop is seamless),
-- a wave, how bright (low-pass Hz) and how much drive. `hiss` is the air
-- rushing in an air horn.
local HORNS = {
  car = { tones = { 370, 466 }, wave = "square", bright = 2200, drive = 2.0 },
  beep = { tones = { 523 }, wave = "square", bright = 2800, drive = 1.6 },
  deep = { tones = { 311, 392 }, wave = "saw", bright = 1800, drive = 2.2 },
  meep = { tones = { 659 }, wave = "square", bright = 3200, drive = 1.4 },
  van = { tones = { 330, 415 }, wave = "saw", bright = 2600, drive = 2.8 },
  air = { tones = { 185, 233, 277 }, wave = "saw", bright = 1500, drive = 2.4, hiss = 0.12 },
}

local bank = {} -- horn kind -> looping base Source
local honking = {} -- client: vid -> { source, on, gain, held }
local pressed = false -- client: my key, as the host was last told

-- Sounds --------------------------------------------------------------------

local WAVES = {
  square = function(p)
    return p < 0.5 and 1 or -1
  end,
  saw = function(p)
    return 2 * p - 1
  end,
}

--- One second of horn `h`, looping cleanly: each tone a whole number of
--- cycles, two slightly beating voices per tone the way real horns waver.
local function render(h)
  local RATE = Synth.RATE
  local buf = Synth.newBuffer(1)
  local wave = WAVES[h.wave]
  local data = buf.data
  for _, f in ipairs(h.tones) do
    for _, voice in ipairs({ { f, 0 }, { f + 1, 0.37 } }) do -- 1 Hz apart: a slow beat, still whole cycles
      for i = 0, buf.n - 1 do
        data[i] = data[i] + wave((voice[1] * i / RATE + voice[2]) % 1) * 0.5
      end
    end
  end
  if h.hiss then
    for i = 0, buf.n - 1 do
      data[i] = data[i] + Synth.noise() * h.hiss
    end
  end
  buf:drive(h.drive)
  -- Filter twice round so the filter has settled by the time it loops.
  local twice = Synth.newBuffer(2)
  for i = 0, buf.n - 1 do
    twice.data[i], twice.data[buf.n + i] = data[i], data[i]
  end
  twice:lowpass(h.bright)
  twice:lowpass(h.bright * 1.5)
  twice:highpass(120)
  for i = 0, buf.n - 1 do
    data[i] = twice.data[buf.n + i]
  end
  local source = love.audio.newSource(buf:toSoundData(0.85), "static")
  source:setLooping(true)
  source:setAttenuationDistances(Horns.refDistance, Horns.maxDistance)
  return source
end

function Horns:load()
  for kind, h in pairs(HORNS) do
    bank[kind] = render(h)
  end
  Controls.register("horn", "Horn (hold, driving)", self.key)
  local order, i = { "beep", "car", "deep", "van", "meep", "air" }, 0
  Audio.registerChannel("horns", "Car horns", self.volume, function()
    i = i % #order + 1 -- each press, the next horn
    local s = bank[order[i]]:clone()
    s:setLooping(false)
    s:setRelative(true)
    s:setVolume(Audio.volume("horns"))
    s:play()
    local stopAt = love.timer.getTime() + 0.5
    honking["preview" .. i] = { source = s, on = false, gain = 1, held = 0, stopAt = stopAt, preview = true }
  end)
end

--- The horn car `vid` has: from its model's engine, else a car's.
function Horns.kindOf(vid)
  local vehicles = Features.byName.vehicles
  local model = vehicles and vehicles.catalog.byKey[vehicles.models[vid] or ""]
  return BY_ENGINE[Profiles.forModel(model)] or "car"
end

-- Server --------------------------------------------------------------------

local sv = nil -- { time, horns = { [vid] = { by = player id, or false for a bot, stopAt } }, botNext }

function Horns:serverStart()
  sv = { time = 0, horns = {}, botNext = {} }
end

local function setHorn(server, car, on, by, seconds)
  local h = sv.horns[car.id]
  if on then
    if not h then
      server:broadcast(Protocol.encode("HRN", car.id, 1))
    end
    sv.horns[car.id] = { by = by, stopAt = seconds and sv.time + seconds or sv.time + Horns.maxHonk }
  elseif h then
    sv.horns[car.id] = nil
    server:broadcast(Protocol.encode("HRN", car.id, 0))
  end
end

--- Sound car `car`'s horn for `seconds` (another feature may ask: a bot).
function Horns:serverHonk(server, car, seconds)
  if sv and car then
    setHorn(server, car, true, false, seconds)
  end
end

function Horns:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  for vid, h in pairs(sv.horns) do
    local car = server.vehicles[vid]
    local player = h.by and server.players[h.by]
    -- Gone, run out, or its player got out (or left): stop it.
    if not car or sv.time >= h.stopAt or (h.by and not (player and player.vehicle == car)) then
      sv.horns[vid] = nil
      server:broadcast(Protocol.encode("HRN", vid, 0))
    end
  end
end

--- A rammed bot answers with its horn.
function Horns:serverCarsCollided(server, _rammer, rammed, closing)
  if not (sv and rammed.bot and rammed.vehicle and closing > 60) then
    return
  end
  if (sv.botNext[rammed.id] or 0) > sv.time then
    return
  end
  sv.botNext[rammed.id] = sv.time + self.botCooldown
  local lo, hi = self.botHonk[1], self.botHonk[2]
  self:serverHonk(server, rammed.vehicle, lo + love.math.random() * (hi - lo))
end

--- Tell someone joining which cars are honking right now.
function Horns:serverPlayerJoined(server, player)
  for vid in pairs(sv and sv.horns or {}) do
    server:send(player, Protocol.encode("HRN", vid, 1))
  end
end

Horns.serverMessages = {
  HRN_PRESS = function(server, player, args)
    local car = player.vehicle
    if not (sv and car) then
      return
    end
    if args[1] == "1" then
      setHorn(server, car, true, player.id)
    else
      local h = sv.horns[car.id]
      if h and h.by == player.id then
        setHorn(server, car, false)
      end
    end
  end,
}

-- Client --------------------------------------------------------------------

function Horns:enterGame()
  honking, pressed = {}, false
end

function Horns:exitGame()
  for vid, e in pairs(honking) do
    e.source:stop()
    honking[vid] = nil
  end
  pressed = false
end

--- Car `vid`'s horn started (on) or stopped.
function Horns.set(vid, on)
  local e = honking[vid]
  if on then
    if not e then
      e = { source = bank[Horns.kindOf(vid)]:clone(), gain = 0, held = 0 }
      e.source:setVolume(0)
      e.source:play()
      honking[vid] = e
    end
    e.on, e.held = true, 0
  elseif e then
    e.on = false
  end
end

function Horns:update(dt, client)
  -- My key: tell the host when it goes down or up while I drive.
  local want = client:myVehicle() ~= nil and Controls.isDown("horn")
    and not Features.any("menuOpen", client) and not Features.any("pointerTaken", client)
  if want ~= pressed then
    pressed = want
    client:send(Protocol.encode("HRN_PRESS", want and 1 or 0))
  end

  local volume = Audio.volume("horns")
  for vid, e in pairs(honking) do
    if e.preview then
      if love.timer.getTime() >= e.stopAt then
        e.source:stop()
        honking[vid] = nil
      end
    else
      e.held = e.held + dt
      local c = client.vehicles[vid]
      local on = c and (e.on or e.held < self.minHonk)
      local rate = on and 1 / self.attack or 1 / self.release
      e.gain = math.max(0, math.min(1, e.gain + (on and 1 or -1) * rate * dt))
      if not on and e.gain <= 0 then
        e.source:stop()
        honking[vid] = nil
      else
        if c then
          e.source:setPosition(c.dx, 0, c.dy)
        end
        e.source:setVolume(volume * e.gain)
      end
    end
  end
end

--- For tests.
function Horns.honking()
  return honking
end

Horns.clientMessages = {
  HRN = function(_client, args)
    local vid = tonumber(args[1])
    if vid then
      Horns.set(vid, args[2] == "1")
    end
  end,
}

return Horns
