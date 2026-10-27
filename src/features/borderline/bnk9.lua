-- BNK-9, the Bunker's boss and the line's last (docs/borderline.md, "The
-- bosses"): how it comes into the fight and what everyone sees of it. What
-- it does in the fight is its brain's (bnk_brain.lua: it is one of the army,
-- model BNK, its corner turrets BNT), how it looks bnk_look.lua's. init.lua
-- passes its hooks on to this module.
--
-- The map says where (city-map's `map.boss` { kind = "bnk", x, y, after,
-- unlocks, bounds }): the moment lock `after` opens (the last rim cannon
-- down) the eye's hatch at (x, y) irises open and BNK-9 rises out of it
-- (RISE seconds), its turrets on. It flies over the roof inside `bounds`.
-- Its health is a boss's (Bosses.health: more humans, more; tougher on a
-- job done before). Down, it crashes onto the deck, its turrets with it,
-- and opens lock `unlocks` (the way home: a lock of the terminals feature
-- with no terminals or walls, `serverUnlock`).
--
-- Every screen: the hatch opening and it rising out, its laser's red line
-- and then the beam, a turret growing back, its crash, the boss bar.
--
-- Messages
--   server -> all  BNK_RISE <x> <y> <seconds>                  it is rising out of the hatch (to a joiner too)
--   server -> all  BNK_AIM <seconds>                           its eye is charging (the line from it)
--   server -> all  BNK_BEAM <x> <y> <angle> <length> <seconds> the beam
--   server -> all  BNK_TURRET <x> <y>                          a turret grew back there
--   server -> all  BNK_FURY                                    below half (to a joiner too)
--   server -> all  BNK_CRASH <x> <y>                           it came down there, the way home open (to a joiner too)

local Protocol = require("src.net.protocol")
local Bosses = require("src.features.bosses")
local Bar = require("src.features.bosses.bar")
local Entry = require("src.features.borderline.boss_entry")
local Army = require("src.features.borderline.army")
local Sound = require("src.features.borderline.boss_sound")
local Hauler = require("src.features.borderline.hauler_look")
local Brain = require("src.features.borderline.bnk_brain")
local Look = require("src.features.borderline.bnk_look")

local Bnk = {}

-- Tuning ------------------------------------------------------------------
Bnk.RISE = 3 -- seconds it takes to rise out of the hatch
Bnk.CRASH = 1.6 -- seconds its crash takes on screen
Bnk.HATCH = 120 -- px across the hatch's open shaft

local TITLE = { 1.00, 0.25, 0.20 }
local FILL = { 0.85, 0.15, 0.12 }
local FILL_FURY = { 1.00, 0.45, 0.10 }

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { spec, phase = "waiting" | "coming" | "up" | "down", comeIn, s, fury, crash }

--- A level starts on `map`: BNK-9 down in the bunker, if it has one.
function Bnk.serverStart(map)
  local spec = map and map.boss
  sv = spec and spec.kind == "bnk" and { spec = spec, phase = "waiting" } or nil
end

function Bnk.serverStop()
  sv = nil
end

local function rise(server, beat)
  local spec = sv.spec
  Entry.come(sv, Bnk.RISE)
  server:broadcast(Protocol.encode("BNK_RISE", fmt(spec.x), fmt(spec.y), ("%.2f"):format(Bnk.RISE)))
  beat("bnk")
end

local function stand(server)
  local spec = sv.spec
  local s = Army.serverSpawn("BNK", spec.x, spec.y, math.pi / 2) -- its eye on the way everyone came up
  if not s then
    sv.phase = "down" -- no army on: nothing to hold the way home
    Entry.open(server, sv)
    return
  end
  s.x, s.y = spec.x, spec.y -- (over the hatch, not a clear spot on the deck)
  s.hp = Bosses.health(Brain.HEALTH, server)
  s.max = s.hp
  s.bounds = spec.bounds
  sv.s, sv.phase = s, "up"
end

--- What its brain left for everyone to see.
local function tell(server, s, beat)
  for _, e in ipairs(s.events) do
    if e[1] == "aim" then
      server:broadcast(Protocol.encode("BNK_AIM", ("%.2f"):format(e[2])))
    elseif e[1] == "beam" then
      server:broadcast(Protocol.encode("BNK_BEAM", fmt(e[2]), fmt(e[3]), ("%.3f"):format(e[4]), fmt(e[5]),
        ("%.2f"):format(e[6])))
    elseif e[1] == "turret" then
      server:broadcast(Protocol.encode("BNK_TURRET", fmt(e[2]), fmt(e[3])))
    elseif e[1] == "fury" then
      sv.fury = true
      server:broadcast(Protocol.encode("BNK_FURY"))
      beat("fury")
    end
  end
  s.events = {}
end

--- `beat(what)` raises a story beat: "bnk" as it rises, "fury" below half,
--- "bnk-down" when it crashes.
function Bnk.serverStep(server, dt, beat)
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
    tell(server, sv.s, beat)
    if sv.s.dead then
      sv.phase, sv.crash = "down", { x = sv.s.x, y = sv.s.y }
      for _, t in pairs(sv.s.turrets) do
        Army.serverTake(t) -- down with it
      end
      Entry.open(server, sv)
      server:broadcast(Protocol.encode("BNK_CRASH", fmt(sv.crash.x), fmt(sv.crash.y)))
      beat("bnk-down")
    end
  end
end

function Bnk.serverPlayerJoined(server, player)
  if not sv then
    return
  end
  if sv.phase == "coming" then
    local spec = sv.spec
    server:send(player, Protocol.encode("BNK_RISE", fmt(spec.x), fmt(spec.y), ("%.2f"):format(sv.comeIn)))
  elseif sv.phase == "up" then
    server:send(player, Protocol.encode("BNK_RISE", fmt(sv.spec.x), fmt(sv.spec.y), "0.01"))
  end
  if sv.fury then
    server:send(player, Protocol.encode("BNK_FURY"))
  end
  if sv.crash then
    server:send(player, Protocol.encode("BNK_CRASH", fmt(sv.crash.x), fmt(sv.crash.y)))
  end
end

--- The launch's --boss: the rim cannons gone, `player` on the deck south of
--- the hatch, and BNK-9 rising. True when there is one to skip to.
function Bnk.serverSkipTo(server, player, beat)
  if not (sv and sv.phase == "waiting") then
    return false
  end
  local spec = sv.spec
  Army.serverClear("CAN")
  Entry.skip(server, sv)
  if player and player.body then
    player.body.x, player.body.y = spec.x, spec.y + 520
  end
  rise(server, beat)
  return true
end

--- The wiki's page on it (tools/wiki, docs/wiki.md).
function Bnk.wikiEnemies(add)
  local B, L, M, T = Brain, Brain.LASER, Brain.MINES, require("src.features.borderline.bnt_brain")
  local Mines = require("src.features.borderline.mines")
  add({
    kind = "borderline/bnk",
    name = "BNK-9",
    quests = { "borderline-bunker" },
    boss = true,
    where = "The Bunker: it rises out of the eye's hatch once all eleven rim cannons are down, and flies over the "
      .. "roof; the way home opens when it crashes",
    about = "The bunker's flying core and the line's last boss: a slab of armour on four engines, a turret on each "
      .. "corner, and at its front the huge red eye it sees with.",
    stats = {
      { "Health", B.HEALTH },
      { "Speed", ("%g px/s in the air, %g below half"):format(B.FLY.speed, B.FLY.fury) },
      { "Sight", B.CONF.range, "px" },
    },
    weapons = {
      { "Eye laser", ("parked, it charges its eye for %g s (a red line to you, which follows you for %g s), then a "
        .. "beam for %g s: %g fire a second, up to the first thing solid"):format(L.aim, L.follow, L.beam, L.dps) },
      { "Mines", ("parked, %d mines come down round you; they arm on landing, beep when you step within %g px, "
        .. "and blow %g s later: %g explosive damage within %g px"):format(M.count, Mines.TRIP, Mines.FUSE,
        Mines.BLAST.damage, Mines.BLAST.radius) },
      { "Corner turrets", ("four, %g health each, bursts of %d at %g bullet damage; one shot off grows back %g s "
        .. "later (%g below half)"):format(T.CONF.health, T.CONF.burst, T.gun().damage, B.TURRETS.back,
        B.TURRETS.fury) },
    },
    abilities = {
      ("It flies from spot to spot over the roof and parks %g s (%g below half) to fight."):format(B.PARK.time,
        B.PARK.fury),
      ("Its eye is its weak spot: a hit there does %gx."):format(B.EYE.taken),
      "A machine: no breath, no medkits.",
    },
    tips = {
      "Aim at the eye.",
      "Get out of the red line before the beam, and put something solid between you and it.",
      "Shoot its turrets off when it parks, then the eye while they grow back.",
    },
    drops = ("%g koins and a pickup"):format(Army.drops.BNK),
  })
end

--- For tests.
function Bnk.server()
  return sv
end

-- Client --------------------------------------------------------------------

local clock = 0
local bank = {}

local function fresh()
  return { hatch = nil, rise = nil, aim = nil, beams = {}, puffs = {}, crash = nil, down = false, started = false }
end
local cl = fresh()

function Bnk.load()
  local make = Sound.make
  -- Rising: engines spooling up over a deep rumble.
  bank.rise = make(3.2, 0.8, function(buf)
    buf:sweep(0, 3, 60, 180, { wave = "saw", amp = 0.3, attack = 1.5, decay = 1, vibRate = 9, vibDepth = 8 })
    buf:sweep(0, 3, 300, 900, { wave = "sine", amp = 0.15, attack = 2, decay = 0.6 })
    buf:noiseBurst(0, 3, { amp = 0.35, attack = 1.8, decay = 0.8 })
    buf:lowpass(2400)
  end)
  -- Its eye charging: a whine climbing.
  bank.charge = make(1.1, 0.6, function(buf)
    buf:sweep(0, 1, 400, 2400, { wave = "saw", amp = 0.2, attack = 0.2, decay = 0.4 })
    buf:lowpass(3600)
  end)
  -- The beam: a hard buzzing roar.
  bank.beam = make(1.3, 0.8, function(buf)
    buf:tone(0, 1.2, 110, { wave = "square", amp = 0.25, attack = 0.02, decay = 0.4 })
    buf:tone(0, 1.2, 165, { wave = "saw", amp = 0.2, attack = 0.02, decay = 0.4, vibRate = 50, vibDepth = 6 })
    buf:noiseBurst(0, 1.2, { amp = 0.3, decay = 0.6 })
    buf:lowpass(3000)
  end)
  -- A turret growing back: a clank and a servo.
  bank.turret = make(0.5, 0.5, function(buf)
    buf:tone(0, 0.2, 600, { wave = "square", amp = 0.15, decay = 0.08 })
    buf:sweep(0.1, 0.35, 300, 700, { wave = "saw", amp = 0.1, decay = 0.2 })
  end)
  -- The crash: a long tearing boom.
  bank.crash = make(2.2, 1, function(buf)
    buf:kick(0, 1)
    buf:sweep(0, 1.5, 120, 30, { wave = "sine", amp = 0.9, decay = 0.8 })
    buf:noiseBurst(0, 2, { amp = 0.8, decay = 0.7 })
    buf:kick(0.5, 0.8)
    buf:lowpass(1800)
  end)
end

local function play(name, x, y)
  Sound.play(bank[name], x, y)
end

function Bnk.clear()
  cl = fresh()
  Look.fury = false
end

local function age(list, dt)
  for i = #list, 1, -1 do
    list[i].t = list[i].t + dt
    if list[i].t >= list[i].total then
      table.remove(list, i)
    end
  end
end

function Bnk.update(dt)
  clock = clock + dt
  for _, k in ipairs({ "rise", "aim", "crash" }) do
    local v = cl[k]
    if v then
      v.t = v.t + dt
      if v.t >= v.total then
        cl[k] = nil
      end
    end
  end
  if cl.hatch then
    cl.hatch.t = cl.hatch.t + dt
  end
  age(cl.beams, dt)
  age(cl.puffs, dt)
end

--- What the objective line should be after on `map` now: "fight" from when
--- it rises until it crashes, or nil (no BNK-9 here, the cannons still up,
--- or it is down).
function Bnk.objective(map)
  local spec = map and map.boss
  if not (spec and spec.kind == "bnk") or cl.down or not cl.started then
    return nil
  end
  return "fight"
end

--- The hatch open: its blades drawn back into the rim, the shaft going
--- down into the bunker, lit from below.
local function drawHatch(h)
  local k = math.min(1, h.t / 1)
  local r = Bnk.HATCH / 2 * k
  local C = Hauler.C
  love.graphics.setColor(0.03, 0.03, 0.04)
  love.graphics.circle("fill", h.x, h.y, r, 40)
  love.graphics.setColor(C.eye[1], C.eye[2], C.eye[3], 0.25 * k)
  love.graphics.circle("fill", h.x, h.y, r * 0.6, 32)
  love.graphics.setColor(C.gunmetal)
  love.graphics.setLineWidth(6)
  love.graphics.circle("line", h.x, h.y, r + 3, 40)
  love.graphics.setLineWidth(1)
end

--- The beam: a hard red line with a white core, glowing, sparks where it ends.
local function drawBeam(b)
  local C = Hauler.C
  local fade = math.min(1, (b.total - b.t) / 0.2, b.t / 0.08)
  local ux, uy = math.cos(b.angle), math.sin(b.angle)
  local x1, y1 = b.x + ux * b.length, b.y + uy * b.length
  local w = Brain.LASER.width
  love.graphics.setBlendMode("add")
  love.graphics.setColor(C.eye[1], C.eye[2], C.eye[3], 0.35 * fade)
  love.graphics.setLineWidth(w * 1.8)
  love.graphics.line(b.x, b.y, x1, y1)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(C.eye[1], C.eye[2], C.eye[3], 0.9 * fade)
  love.graphics.setLineWidth(w)
  love.graphics.line(b.x, b.y, x1, y1)
  love.graphics.setColor(1, 0.9, 0.85, fade)
  love.graphics.setLineWidth(w * 0.35 + math.sin(clock * 60) * 2)
  love.graphics.line(b.x, b.y, x1, y1)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 0.8, 0.4, fade)
  for i = 0, 5 do
    local a = clock * 17 + i
    love.graphics.circle("fill", x1 + math.cos(a) * (6 + i * 3), y1 + math.sin(a) * (6 + i * 3), 2.5, 6)
  end
end

--- The open hatch on the deck, under everyone.
function Bnk.drawBelowCars()
  if cl.hatch then
    drawHatch(cl.hatch)
  end
  love.graphics.setColor(1, 1, 1)
end

--- It rising out of the hatch, the line its eye is charging along, the
--- beams, turrets growing back, its crash: over everyone.
function Bnk.drawAboveCars()
  local C = Hauler.C
  local r = cl.rise
  if r then
    local k = r.t / r.total
    love.graphics.push()
    love.graphics.translate(r.x, r.y)
    love.graphics.scale(0.4 + 0.6 * k) -- coming up out of the shaft, nearer as it comes
    Look.draw({ dx = 0, dy = 0, facing = math.pi / 2, charge = 1 - k }, clock)
    love.graphics.pop()
  end
  local s = cl.aim and Army.shownOf("BNK")
  if s then
    local ex, ey = s.dx + math.cos(s.facing) * Brain.EYE.ahead, s.dy + math.sin(s.facing) * Brain.EYE.ahead
    local k = cl.aim.t / cl.aim.total
    love.graphics.setColor(C.eye[1], C.eye[2], C.eye[3], 0.4 + 0.5 * math.sin(clock * (10 + 30 * k)) ^ 2)
    love.graphics.setLineWidth(2 + 2 * k)
    local L = Brain.LASER.length
    love.graphics.line(ex, ey, ex + math.cos(s.facing) * L, ey + math.sin(s.facing) * L)
    love.graphics.setLineWidth(1)
  end
  for _, b in ipairs(cl.beams) do
    drawBeam(b)
  end
  for _, p in ipairs(cl.puffs) do
    local k = p.t / p.total
    love.graphics.setColor(1, 0.75, 0.3, 0.7 * (1 - k))
    love.graphics.circle("line", p.x, p.y, 10 + 30 * k, 20)
  end
  local c = cl.crash
  if c then -- blasts going off all over it as it comes down
    local k = c.t / c.total
    for i = 0, 5 do
      local t = (k * 3 - i * 0.3)
      if t > 0 and t < 1 then
        local a = i * 2.3
        local x, y = c.x + math.cos(a) * 50, c.y + math.sin(a) * 40
        love.graphics.setColor(1, 0.85 - 0.5 * t, 0.3, 0.9 * (1 - t))
        love.graphics.circle("fill", x, y, 20 + 50 * t, 24)
      end
    end
    love.graphics.setColor(1, 1, 1, 0.6 * (1 - k))
    love.graphics.circle("fill", c.x, c.y, 160 * k, 32)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Its bar, while it is up (a machine: no breath).
function Bnk.drawHUD()
  local s = not cl.down and Army.shownOf("BNK")
  if s then
    Bar.draw({ title = "BNK-9", titleColor = TITLE, fill = Look.fury and FILL_FURY or FILL, hp = s.hp, max = s.max,
      noBreath = true, harder = "BIGGER" })
  end
end

Bnk.clientMessages = {
  BNK_RISE = function(_client, args)
    local x, y, t = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y and t and t > 0 then
      cl.rise, cl.started = { x = x, y = y, t = 0, total = t }, true
      cl.hatch = cl.hatch or { x = x, y = y, t = 0 }
      if t > 0.5 then
        play("rise", x, y)
      end
    end
  end,
  BNK_AIM = function(_client, args)
    local t = tonumber(args[1])
    if t and t > 0 then
      cl.aim = { t = 0, total = t }
      local s = Army.shownOf("BNK")
      if s then
        play("charge", s.dx, s.dy)
      end
    end
  end,
  BNK_BEAM = function(_client, args)
    local x, y, a = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local len, t = tonumber(args[4]), tonumber(args[5])
    if x and y and a and len and t and t > 0 then
      cl.aim = nil
      cl.beams[#cl.beams + 1] = { x = x, y = y, angle = a, length = len, t = 0, total = t }
      play("beam", x, y)
    end
  end,
  BNK_TURRET = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      cl.puffs[#cl.puffs + 1] = { x = x, y = y, t = 0, total = 0.5 }
      play("turret", x, y)
    end
  end,
  BNK_FURY = function()
    Look.fury = true
  end,
  BNK_CRASH = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    cl.down, cl.started, cl.aim, cl.beams = true, true, nil, {}
    if x and y then
      cl.crash = { x = x, y = y, t = 0, total = Bnk.CRASH }
      play("crash", x, y)
    end
  end,
}

return Bnk
