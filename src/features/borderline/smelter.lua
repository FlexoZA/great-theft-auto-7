-- The Smelter, the Refinery's boss (docs/borderline.md, "The bosses"): how
-- it comes into the fight and what everyone sees of it. What it does in the
-- fight is its brain's (sml_brain.lua: it is one of the army, model SML),
-- how it looks smelter_look.lua's. init.lua passes its hooks on to this
-- module.
--
-- The map says where (city-map's `map.boss` { kind = "smelter", x, y,
-- fromX, fromY, after, unlocks }): the moment lock `after` opens (the last
-- bridge lowered) it hauls itself up out of the casting pit at (fromX,
-- fromY), molten Bragium running off it, over RISE seconds onto (x, y) at
-- the outflow. Its health is a boss's (Bosses.health: more humans, more;
-- tougher on a job done before). Down, it opens lock `unlocks` (the freight
-- door: a lock of the terminals feature with no terminals, `serverUnlock`).
--
-- Every screen: it climbing out of the pit, a gush's lane lighting up in
-- front of it and then the molten stream running down it, its belly door
-- open and glowing while it vents (hits do double then: sml_brain.lua),
-- the boss bar.
--
-- Messages
--   server -> all  SML_RISE <fromX> <fromY> <x> <y> <seconds>          it is climbing out (to a joiner too)
--   server -> all  SML_AIM <x> <y> <angle> <length> <width> <seconds>  a gush's lane lit, pouring in `seconds`
--   server -> all  SML_GUSH <x> <y> <angle> <length> <width> <seconds> pouring down it for `seconds`
--   server -> all  SML_VENT <seconds>                                  it vents
--   server -> all  SML_DOWN                                            it went out, the door open (to a joiner too)

local Protocol = require("src.net.protocol")
local Bosses = require("src.features.bosses")
local Bar = require("src.features.bosses.bar")
local Entry = require("src.features.borderline.boss_entry")
local Army = require("src.features.borderline.army")
local Sound = require("src.features.borderline.boss_sound")
local Hauler = require("src.features.borderline.hauler_look")
local Paint = require("src.features.borderline.boss_paint")
local Brain = require("src.features.borderline.sml_brain")
local Look = require("src.features.borderline.smelter_look")

local Smelter = {}

-- Tuning ------------------------------------------------------------------
Smelter.RISE = 2.4 -- seconds it takes to haul itself out of the pit

local TITLE = { 0.95, 0.76, 0.19 }
local FILL = { 0.71, 0.30, 1.00 }
local FILL_VENT = { 1.00, 0.85, 1.00 }

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { map, spec, phase = "waiting" | "coming" | "up" | "down", comeIn, s }

--- A level starts on `map`: the Smelter down in the casting pit, if it has one.
function Smelter.serverStart(map)
  local spec = map and map.boss
  sv = spec and spec.kind == "smelter" and { map = map, spec = spec, phase = "waiting" } or nil
end

function Smelter.serverStop()
  sv = nil
end

local function rise(server, beat)
  local spec = sv.spec
  Entry.come(sv, Smelter.RISE)
  server:broadcast(Protocol.encode("SML_RISE", fmt(spec.fromX), fmt(spec.fromY), fmt(spec.x), fmt(spec.y),
    ("%.2f"):format(Smelter.RISE)))
  beat("smelter")
end

local function stand(server)
  local spec = sv.spec
  local s = Army.serverSpawn("SML", spec.x, spec.y, math.pi / 2) -- facing down the hall, the way everyone comes
  if not s then
    sv.phase = "down" -- no army on: nothing to hold the door
    Entry.open(server, sv)
    return
  end
  s.hp = Bosses.health(Brain.HEALTH, server)
  s.max = s.hp
  sv.s, sv.phase = s, "up"
end

--- What its brain left for everyone to see.
local function tell(server, s)
  for _, e in ipairs(s.events) do
    if e[1] == "aim" or e[1] == "gush" then
      server:broadcast(Protocol.encode(e[1] == "aim" and "SML_AIM" or "SML_GUSH", fmt(e[2]), fmt(e[3]),
        ("%.3f"):format(e[4]), e[5], e[6], ("%.2f"):format(e[7])))
    elseif e[1] == "vent" then
      server:broadcast(Protocol.encode("SML_VENT", ("%.2f"):format(e[2])))
    end
  end
  s.events = {}
end

--- `beat(what)` raises a story beat: "smelter" as it climbs out,
--- "smelter-down" when it goes out.
function Smelter.serverStep(server, dt, beat)
  if not sv then
    return
  end
  if Entry.step(sv, dt, function()
    rise(server, beat)
  end, function()
    stand(server)
  end) then -- (waiting for its lock, or coming in)
    return
  elseif sv.phase == "up" then
    tell(server, sv.s)
    if sv.s.dead then
      sv.phase = "down"
      Entry.open(server, sv)
      server:broadcast(Protocol.encode("SML_DOWN"))
      beat("smelter-down")
    end
  end
end

function Smelter.serverPlayerJoined(server, player)
  if sv and sv.phase == "coming" then
    local spec = sv.spec
    server:send(player, Protocol.encode("SML_RISE", fmt(spec.fromX), fmt(spec.fromY), fmt(spec.x), fmt(spec.y),
      ("%.2f"):format(sv.comeIn)))
  elseif sv and sv.phase == "down" then
    server:send(player, Protocol.encode("SML_DOWN"))
  end
end

--- The launch's --boss: every bridge down, `player` over the last of them,
--- and the Smelter climbing out. True when there is one to skip to.
function Smelter.serverSkipTo(server, player, beat)
  if not (sv and sv.phase == "waiting") then
    return false
  end
  local spec = sv.spec
  Entry.skip(server, sv)
  if player and player.body then
    player.body.x, player.body.y = spec.x, spec.y + 560
  end
  rise(server, beat)
  return true
end

--- The wiki's page on it (tools/wiki, docs/wiki.md).
function Smelter.wikiEnemies(add)
  local Heal = require("src.features.bosses.heal")
  local B, S, G, V = Brain, Brain.SHOT, Brain.GUSH, Brain.VENT
  add({
    kind = "borderline/sml",
    name = "The Smelter",
    quests = { "borderline-refinery" },
    boss = true,
    where = "The Refinery: it climbs out of the casting pit at the outflow when the last bridge comes down, and "
      .. "the freight door stays shut until it goes out",
    about = "A squat plasma furnace on four legs with molten Bragium in its belly, Hyperbole's yellow band round "
      .. "its shell and a spout at its front.",
    stats = {
      { "Health", B.HEALTH },
      { "Speed", ("%g px/s, %g winded"):format(B.CONF.speed, B.CONF.walk) },
      { "Sight", B.CONF.range, "px" },
    },
    weapons = {
      { "Plasma bolt", ("its coils glow for %g s, then one bolt, %g px/s, every %g to %g s: %g plasma damage, "
        .. "splashing %g px"):format(S.aim, B.BOLT.speed, S.every[1], S.every[2], B.BOLT.damage, B.BOLT.splash) },
      { "Gush", ("every %g to %g s: a lane %g px long lights up in front of it for %g s, then it pours molten "
        .. "Bragium down it for %g s, %g plasma a second to whoever is in it, leaving puddles burning %g s")
        :format(G.every[1], G.every[2], G.length, G.windUp, G.pour, G.dps, G.burn) },
    },
    abilities = {
      ("After every %d moves it vents for %g s: it stands still with its belly open, and every hit on it does %gx.")
        :format(V.after, V.time, V.taken),
      ("Under %g%% health it goes for the nearest medkit within %g px, for %g health."):format(Heal.below * 100,
        Heal.range, Heal.amount),
      "Plasma melts armor: while you're melted, what you wear stops half as much.",
    },
    tips = {
      "Get out of the lit lane before it pours, and stay off the puddles it leaves.",
      "Count its moves: on the third it vents. Unload into it then.",
      "Its bolts are slow: sidestep them.",
    },
    drops = ("%g koins and a pickup"):format(Army.drops.SML),
  })
end

--- For tests.
function Smelter.server()
  return sv
end

-- Client --------------------------------------------------------------------

local clock = 0
local bank = {}

local function fresh()
  return { rise = nil, lanes = {}, ventFor = 0, started = false, down = false }
end
local cl = fresh()

function Smelter.load()
  local make = Sound.make
  -- Climbing out of the pit: a deep bubbling roar, rising, and a clank as it stands.
  bank.rise = make(2.6, 0.8, function(buf)
    buf:noiseBurst(0, 2.3, { amp = 0.45, attack = 1.4, decay = 0.6 })
    buf:sweep(0, 2.3, 45, 120, { wave = "saw", amp = 0.3, attack = 1, decay = 0.8, vibRate = 7, vibDepth = 10 })
    buf:kick(2.35, 1)
    buf:lowpass(1800)
  end)
  -- The belly door opening on a gush: a hiss and a servo.
  bank.aim = make(1.0, 0.6, function(buf)
    buf:noiseBurst(0, 0.9, { amp = 0.35, attack = 0.5, decay = 0.3 })
    buf:sweep(0, 0.8, 180, 420, { wave = "square", amp = 0.1, decay = 0.4 })
    buf:highpass(500)
  end)
  -- The pour: a rushing, bubbling roar.
  bank.gush = make(2.3, 0.8, function(buf)
    buf:noiseBurst(0, 2.2, { amp = 0.6, attack = 0.1, decay = 1.2 })
    buf:sweep(0, 2.2, 90, 60, { wave = "saw", amp = 0.25, decay = 1.2, vibRate = 11, vibDepth = 14 })
    buf:lowpass(1500)
  end)
  -- Venting: a long hiss of steam.
  bank.vent = make(3.0, 0.6, function(buf)
    buf:noiseBurst(0, 2.9, { amp = 0.5, attack = 0.1, decay = 1.6 })
    buf:highpass(1400)
  end)
end

local function play(name, x, y)
  Sound.play(bank[name], x, y)
end

function Smelter.clear()
  cl = fresh()
  Look.tell.open, Look.tell.vent = 0, false
end

function Smelter.update(dt)
  clock = clock + dt
  if cl.rise then
    cl.rise.t = cl.rise.t + dt
    if cl.rise.t >= cl.rise.total then
      cl.rise = nil
    end
  end
  local busy = false
  for i = #cl.lanes, 1, -1 do
    local l = cl.lanes[i]
    l.t = l.t + dt
    if l.t >= l.total + (l.pour and 0.5 or 0) then
      table.remove(cl.lanes, i)
    else
      busy = true
    end
  end
  cl.ventFor = math.max(0, cl.ventFor - dt)
  local T = Look.tell
  T.vent = cl.ventFor > 0
  T.open = math.max(0, math.min(1, T.open + ((busy or T.vent) and 3 or -2) * dt))
end

--- What the objective line should be after on `map` now: "fight" while it
--- is climbing out or up, or nil (no Smelter here, not woken yet, or down).
function Smelter.objective(map)
  local spec = map and map.boss
  if not (spec and spec.kind == "smelter") or cl.down then
    return nil
  end
  if cl.started or Army.shownOf("SML") then
    return "fight"
  end
  return nil
end

--- A gush's lane on the floor: lit while it lines up (boss_paint.lua's
--- lane); the molten stream running down it once it pours.
local function drawLane(l)
  if not l.pour then
    Paint.lane(l.x, l.y, l.angle, l.length, l.width, l.t / l.total, clock)
    return
  end
  local C = Hauler.C
  love.graphics.push()
  love.graphics.translate(l.x, l.y)
  love.graphics.rotate(l.angle)
  local hw = l.width / 2
  -- Pouring: the molten stream running down it, fading once it stops.
  local fade = math.max(0, math.min(1, (l.total + 0.5 - l.t) / 0.5))
  local reach = l.length * math.min(1, l.t / 0.5)
  love.graphics.setColor(0.16, 0.08, 0.22, 0.8 * fade)
  love.graphics.rectangle("fill", 0, -hw * 0.75, reach, hw * 1.5, hw * 0.5)
  love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.9 * fade)
  love.graphics.rectangle("fill", 0, -hw * 0.55, reach, hw * 1.1, hw * 0.4)
  love.graphics.setColor(C.plasmaHot[1], C.plasmaHot[2], C.plasmaHot[3], 0.8 * fade)
  for k = 0, 5 do -- streaks racing down it
    local p = ((clock * 2.4 + k / 6) % 1) * reach
    love.graphics.rectangle("fill", p, -hw * 0.3 + (k % 3) * hw * 0.25, 40, 3)
  end
  love.graphics.setBlendMode("add")
  love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.25 * fade)
  love.graphics.rectangle("fill", 0, -hw * 1.1, reach, hw * 2.2, hw)
  love.graphics.setBlendMode("alpha")
  love.graphics.pop()
end

--- Its lanes, on the floor under everyone.
function Smelter.drawBelowCars()
  for _, l in ipairs(cl.lanes) do
    drawLane(l)
  end
  love.graphics.setColor(1, 1, 1)
end

--- It climbing out of the casting pit: rising from under the rim on its
--- way to where it'll stand, molten Bragium running off it.
function Smelter.drawAboveCars()
  local r = cl.rise
  if not r then
    return
  end
  local C = Hauler.C
  local k = r.t / r.total
  local x, y = r.fromX + (r.x - r.fromX) * k, r.fromY + (r.y - r.fromY) * k
  love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.6 * (1 - k))
  love.graphics.circle("fill", r.fromX, r.fromY, 60 + 30 * k, 24) -- the pit's surface churning
  Look.tell.open = 1
  Look.draw({ dx = x, dy = y - 30 * math.sin(k * math.pi), facing = math.pi / 2, stride = r.t * 120,
    charge = 1 - k }, clock)
  for i = 0, 5 do -- dripping off it
    local t = (r.t * 1.7 + i / 6) % 1
    love.graphics.setColor(C.plasmaHot[1], C.plasmaHot[2], C.plasmaHot[3], 0.9 * (1 - t))
    love.graphics.circle("fill", x + math.cos(i * 1.05) * 36, y + math.sin(i * 1.05) * 30 + t * 24, 3, 8)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Its bar, while it is up: white-hot while it vents.
function Smelter.drawHUD()
  local s = not cl.down and Army.shownOf("SML")
  if s then
    Bar.draw({
      title = cl.ventFor > 0 and "THE SMELTER  -  VENTING" or "THE SMELTER", titleColor = TITLE,
      fill = cl.ventFor > 0 and FILL_VENT or FILL, hp = s.hp, max = s.max, stamina = s.breath, staminaMax = 100,
      winded = s.winded, harder = "HOTTER",
    })
  end
end

--- A lane from the message's args (x, y, angle, length, width, seconds).
local function lane(args, pour)
  local x, y, a = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
  local len, w, t = tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
  if x and y and a and len and w and t and t > 0 then
    return { x = x, y = y, angle = a, length = len, width = w, t = 0, total = t, pour = pour }
  end
end

Smelter.clientMessages = {
  SML_RISE = function(_client, args)
    local fx, fy, x, y, t = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4]),
      tonumber(args[5])
    if fx and fy and x and y and t and t > 0 then
      cl.rise, cl.started = { fromX = fx, fromY = fy, x = x, y = y, t = 0, total = t }, true
      play("rise", fx, fy)
    end
  end,
  SML_AIM = function(_client, args)
    local l = lane(args, false)
    if l then
      cl.lanes[#cl.lanes + 1] = l
      play("aim", l.x, l.y)
    end
  end,
  SML_GUSH = function(_client, args)
    local l = lane(args, true)
    if l then
      for i = #cl.lanes, 1, -1 do -- the lit lane gives way to the stream
        if not cl.lanes[i].pour then
          table.remove(cl.lanes, i)
        end
      end
      cl.lanes[#cl.lanes + 1] = l
      play("gush", l.x, l.y)
    end
  end,
  SML_VENT = function(_client, args)
    local t = tonumber(args[1])
    if t and t > 0 then
      cl.ventFor = t
      local s = Army.shownOf("SML")
      if s then
        play("vent", s.dx, s.dy)
      end
    end
  end,
  SML_DOWN = function()
    cl.down, cl.started, cl.rise, cl.ventFor = true, true, nil, 0
  end,
}

return Smelter
