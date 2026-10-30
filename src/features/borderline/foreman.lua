-- Foreman BIG-B055, the Assembly Line's boss (docs/borderline.md, "The
-- bosses"): where it stands, the haulers the line's crane brings it, and
-- what everyone sees of it. What it does in the fight is its brain's
-- (fmn_brain.lua: it is one of the army, model FMN), how it looks
-- foreman_look.lua's. init.lua passes its hooks on to this module.
--
-- The map says where (city-map's `map.boss` { kind = "foreman", x, y,
-- floor, unlocks }): it stands its post at (x, y) on the Foreman's floor
-- from the start, overseeing the line, and the first player to come up
-- onto its floor (the box `floor`) wakes it (a hit does too). Its health is
-- a boss's (Bosses.health: more humans, more; tougher on a job done
-- before). Down, it opens lock `unlocks` (the shipping bay: a lock of the
-- terminals feature with no terminals, `serverUnlock`).
--
-- Its whistle (the brain's `call`) brings the crane: a hauler comes down on
-- its cable onto a red ring by whoever is up there (DROP seconds), knocking
-- flat whoever is under it, and joins the fight: gun, gun, rocket,
-- kamikaze in turn, no more than CAP of them out at once.
--
-- Every screen: the haulers coming down on the crane, its stomp's ring, the
-- lane a charge runs down, the cannon it tears off flung across the floor,
-- stars round its head when it runs into a wall, the boss bar.
--
-- Messages
--   server -> all  FMN_WAKE                                            it woke (to a joiner too)
--   server -> all  FMN_CALL <x> <y>                                    it blew its whistle there
--   server -> all  FMN_DROP <x> <y> <seconds> <code>                   the crane is bringing one down there
--   server -> all  FMN_LAND <x> <y> <radius>                           something heavy came down there
--   server -> all  FMN_LANE <x> <y> <angle> <length> <width> <seconds> a charge's lane lit, running in `seconds`
--   server -> all  FMN_CRASH <x> <y> <seconds>                         it ran into a wall there, stunned
--   server -> all  FMN_RIP <x> <y> <facing>                            it tore a cannon off (to a joiner too)
--   server -> all  FMN_DOWN                                            it is down, the bay open (to a joiner too)
--   (and army.lua's HYP_STOMP for its stamp's sound)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Bar = require("src.features.bosses.bar")
local Entry = require("src.features.borderline.boss_entry")
local Army = require("src.features.borderline.army")
local Sound = require("src.features.borderline.boss_sound")
local Chassis = require("src.features.borderline.chassis")
local Barrage = require("src.features.borderline.barrage")
local Hauler = require("src.features.borderline.hauler_look")
local Paint = require("src.features.borderline.boss_paint")
local Brain = require("src.features.borderline.fmn_brain")
local Look = require("src.features.borderline.foreman_look")

local Foreman = {}

-- Tuning ------------------------------------------------------------------
Foreman.DROP = 1.6 -- seconds a hauler takes coming down on the crane
Foreman.DROP_HIT = 60 -- px: whoever it lands this near...
Foreman.DROP_DAMAGE = 20 -- ...takes this (impact)...
Foreman.DROP_SHOVE = 180 -- ...and goes flying
Foreman.CAP = 3 -- the crane's haulers out at once (one more for each human past the first)
Foreman.CODES = { "GUN", "GUN", "RPG", "EXP" } -- what the crane brings, in turn
Foreman.CABLE = 520 -- px up the crane's hook is drawn when a hauler starts down

local TITLE = { 1.00, 0.80, 0.25 }
local FILL = { 0.95, 0.70, 0.15 }
local FILL_RIPPED = { 1.00, 0.40, 0.12 }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function inBox(b, x, y)
  return x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1
end

-- Server --------------------------------------------------------------------

local sv = nil -- { spec, phase = "waiting" | "post" | "up" | "down", s, drops, called, next, ripped }

--- A level starts on `map`: the Foreman to stand its post, if it has one
--- (it is put there on the first step, once the army is on).
function Foreman.serverStart(map)
  local spec = map and map.boss
  sv = spec and spec.kind == "foreman" and { spec = spec, phase = "waiting", drops = {}, called = {}, next = 1 }
    or nil
end

function Foreman.serverStop()
  sv = nil
end

local function post(server)
  local spec = sv.spec
  local s = Army.serverSpawn("FMN", spec.x, spec.y, math.pi / 2) -- looking down the line
  if not s then
    sv.phase = "down" -- no army on: nothing to hold the bay
    Entry.open(server, sv)
    return
  end
  s.hp = Bosses.health(Brain.HEALTH, server)
  s.max = s.hp
  sv.s, sv.phase = s, "post"
end

--- Where the crane brings the next one down: by a player up on the floor
--- (on the floor's ground, not in a wall), or by the Foreman if nobody is.
local function dropSpot(server)
  local spec, s = sv.spec, sv.s
  local x, y = s.x, s.y
  local up = {}
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      if inBox(spec.floor, px, py) then
        up[#up + 1] = { px, py }
      end
    end
  end
  if #up > 0 then
    local at = up[random(#up)]
    x, y = at[1], at[2]
  end
  for _ = 1, 8 do
    local a, d = random() * 2 * math.pi, 90 + random() * 90
    local cx, cy = x + math.cos(a) * d, y + math.sin(a) * d
    if inBox(spec.floor, cx, cy) and Chassis.fits(cx, cy, 20) then
      return cx, cy
    end
  end
  return x, y
end

--- The whistle: the crane brings it another, unless it has CAP out already.
local function call(server, s)
  server:broadcast(Protocol.encode("FMN_CALL", fmt(s.x), fmt(s.y)))
  local alive = {}
  for _, h in ipairs(sv.called) do
    if Army.serverAlive(h) then
      alive[#alive + 1] = h
    end
  end
  sv.called = alive
  if #sv.called + #sv.drops >= Bosses.plus(Foreman.CAP, server) then
    return
  end
  local x, y = dropSpot(server)
  local code = Foreman.CODES[sv.next]
  sv.next = sv.next % #Foreman.CODES + 1
  sv.drops[#sv.drops + 1] = { x = x, y = y, t = Foreman.DROP, code = code }
  Barrage.serverMark(server, x, y, Foreman.DROP_HIT, Foreman.DROP)
  server:broadcast(Protocol.encode("FMN_DROP", fmt(x), fmt(y), ("%.2f"):format(Foreman.DROP), code))
end

--- The crane's haulers coming down: landed, it knocks flat whoever is
--- under it and joins in.
local function drops(server, dt)
  for i = #sv.drops, 1, -1 do
    local d = sv.drops[i]
    d.t = d.t - dt
    if d.t <= 0 then
      table.remove(sv.drops, i)
      Chassis.slam(server, d.x, d.y, Foreman.DROP_HIT, Foreman.DROP_DAMAGE * Bosses.power(), Foreman.DROP_SHOVE)
      server:broadcast(Protocol.encode("FMN_LAND", fmt(d.x), fmt(d.y), Foreman.DROP_HIT))
      local h = Army.serverSpawn(d.code, d.x, d.y, random() * 2 * math.pi)
      if h then
        sv.called[#sv.called + 1] = h
        if h.brain.wake then
          h.brain.wake(h, d.x, d.y)
        end
      end
    end
  end
end

--- What its brain left for everyone to see.
local function tell(server, s)
  for _, e in ipairs(s.events) do
    if e[1] == "call" then
      call(server, s)
    elseif e[1] == "stomp" then
      server:broadcast(Protocol.encode("HYP_STOMP", s.id))
      server:broadcast(Protocol.encode("FMN_LAND", fmt(e[2]), fmt(e[3]), e[4]))
    elseif e[1] == "lane" then
      server:broadcast(Protocol.encode("FMN_LANE", fmt(e[2]), fmt(e[3]), ("%.3f"):format(e[4]), fmt(e[5]), e[6],
        ("%.2f"):format(e[7])))
    elseif e[1] == "crash" then
      server:broadcast(Protocol.encode("FMN_CRASH", fmt(e[2]), fmt(e[3]), ("%.2f"):format(Brain.CHARGE.stun)))
    elseif e[1] == "rip" then
      sv.ripped = { x = e[2], y = e[3], facing = e[4] }
      server:broadcast(Protocol.encode("FMN_RIP", fmt(e[2]), fmt(e[3]), ("%.3f"):format(e[4])))
    end
  end
  s.events = {}
end

--- `beat(what)` raises a story beat: "foreman" as it wakes, "rip" when it
--- tears its cannon off, "foreman-down".
function Foreman.serverStep(server, dt, beat)
  if not sv then
    return
  end
  if sv.phase == "waiting" then
    post(server)
  elseif sv.phase == "post" then
    if sv.s.dormant then
      for _, p in pairs(server.players) do
        if not p.bot and Features.present(p) then
          local x, y = Features.bodyPose(server, p)
          if inBox(sv.spec.floor, x, y) then
            Brain.wake(sv.s, x, y)
            break
          end
        end
      end
    end
    if not sv.s.dormant then -- somebody came up, or shot it from below
      sv.phase = "up"
      server:broadcast(Protocol.encode("FMN_WAKE"))
      beat("foreman")
    end
  elseif sv.phase == "up" then
    local ripped = sv.ripped
    tell(server, sv.s)
    if sv.ripped and not ripped then
      beat("rip")
    end
    if sv.s.dead then
      sv.phase = "down"
      Entry.open(server, sv)
      server:broadcast(Protocol.encode("FMN_DOWN"))
      beat("foreman-down")
    end
  end
  drops(server, dt)
end

function Foreman.serverPlayerJoined(server, player)
  if not sv then
    return
  end
  if sv.phase == "up" or sv.phase == "down" then
    server:send(player, Protocol.encode("FMN_WAKE"))
  end
  if sv.ripped then
    local r = sv.ripped
    server:send(player, Protocol.encode("FMN_RIP", fmt(r.x), fmt(r.y), ("%.3f"):format(r.facing)))
  end
  if sv.phase == "down" then
    server:send(player, Protocol.encode("FMN_DOWN"))
  end
end

--- The launch's --boss: the stairs open, `player` up on its floor (which
--- wakes it). True when there is a Foreman to skip to.
function Foreman.serverSkipTo(server, player, beat)
  if not (sv and (sv.phase == "waiting" or sv.phase == "post")) then
    return false
  end
  if sv.phase == "waiting" then
    post(server)
  end
  local spec = sv.spec
  Entry.skip(server, sv)
  if player and player.body then
    player.body.x, player.body.y = spec.x, spec.y + 300
  end
  Foreman.serverStep(server, 0, beat)
  return true
end

--- The wiki's page on it (tools/wiki, docs/wiki.md).
function Foreman.wikiEnemies(add)
  local Heal = require("src.features.bosses.heal")
  local B, K, S, C = Brain, Brain.CONF, Brain.STOMP, Brain.CHARGE
  local gun = B.gun()
  add({
    kind = "borderline/fmn",
    name = "Foreman BIG-B055",
    quests = { "borderline-assembly" },
    boss = true,
    where = "The Assembly Line: on the Foreman's floor up the stairs (open once both Fabricators are down), "
      .. "woken by the first player up there; the shipping bay stays shut until it is down",
    about = "The badass hauler that runs the line: bigger than any other, black and gold, a hard hat welded on, "
      .. "twin war cannons and rocket pods.",
    stats = {
      { "Health", B.HEALTH },
      { "Speed", ("%g px/s, %g winded"):format(K.speed, K.walk) },
      { "Sight", K.range, "px" },
    },
    weapons = {
      { "War cannons", ("bursts of %d (%d with one cannon), each a small blast: %g explosive damage within %g px")
        :format(K.burst, B.RIPPED.burst, gun.blast.damage, gun.blast.radius) },
      { "Rocket pods", ("every %g to %g s it winds up for %g s, then %d rockets come down on red rings round you, "
        .. "%g explosive damage each"):format(K.volleyEvery[1], K.volleyEvery[2], K.windUp, K.volley,
        K.volleyDamage) },
      { "Stomp", ("at anyone within %g px: it rears up for %g s and stamps, %g impact damage, thrown %g px")
        :format(S.reach * 0.8, S.windUp, S.damage, S.shove) },
      { "Charge", ("from half health, at anyone %g px or more off every %g to %g s: a lane lights up for %g s, then "
        .. "it runs down it at %g px/s, %g impact damage, thrown %g px; into a wall and it is stunned %g s")
        :format(C.min, C.every[1], C.every[2], C.windUp, C.speed, C.damage, C.shove, C.stun) },
    },
    abilities = {
      ("Every %g s (%g once it has torn a cannon off) it blows its whistle and the crane brings a hauler down "
        .. "on a red ring by you (%g impact within %g px): gun, gun, rocket, kamikaze in turn, %d out at most.")
        :format(B.CALL.every, B.CALL.everyRipped, Foreman.DROP_DAMAGE, Foreman.DROP_HIT, Foreman.CAP),
      ("At %g%% of its health it tears one cannon off and starts charging."):format(B.RIP * 100),
      ("Under %g%% health it goes for the nearest medkit within %g px, for %g health."):format(Heal.below * 100,
        Heal.range, Heal.amount),
    },
    tips = {
      "Step off the red ring when the whistle goes: the crane drops its hauler there.",
      "Make it charge you with a wall at your back, then step aside: it stuns itself.",
      "Shoot the medic drone on its floor first.",
    },
    drops = ("%g koins and a pickup"):format(Army.drops.FMN),
  })
end

--- For tests.
function Foreman.server()
  return sv
end

-- Client --------------------------------------------------------------------

local clock = 0
local bank = {}

local function fresh()
  return { awake = false, down = false, drops = {}, waves = {}, lanes = {}, stars = nil, cannon = nil }
end
local cl = fresh()

function Foreman.load()
  local make = Sound.make
  -- Its whistle: a foreman's two shrill blasts.
  bank.whistle = make(0.9, 0.6, function(buf)
    buf:tone(0, 0.3, 2600, { wave = "sine", amp = 0.35, attack = 0.01, decay = 0.05, vibRate = 40, vibDepth = 60 })
    buf:tone(0.4, 0.45, 2600, { wave = "sine", amp = 0.35, attack = 0.01, decay = 0.1, vibRate = 40, vibDepth = 60 })
  end)
  -- The crane's winch letting a hauler down.
  bank.winch = make(1.6, 0.5, function(buf)
    buf:sweep(0, 1.5, 300, 140, { wave = "saw", amp = 0.15, decay = 0.6, vibRate = 18, vibDepth = 10 })
    buf:noiseBurst(0, 1.5, { amp = 0.12, decay = 1 })
    buf:lowpass(1800)
  end)
  -- Something heavy coming down: a clang and a thud.
  bank.land = make(0.8, 0.9, function(buf)
    buf:kick(0, 1)
    buf:tone(0, 0.5, 220, { wave = "square", amp = 0.18, decay = 0.2 })
    buf:noiseBurst(0, 0.4, { amp = 0.5, decay = 0.12 })
    buf:lowpass(2000)
  end)
  -- Tearing its cannon off: shrieking metal and a snap.
  bank.rip = make(1.0, 0.8, function(buf)
    buf:sweep(0, 0.7, 900, 300, { wave = "saw", amp = 0.3, decay = 0.4, vibRate = 25, vibDepth = 40 })
    buf:noiseBurst(0.55, 0.3, { amp = 0.8, decay = 0.06 })
    buf:lowpass(3000)
  end)
  -- Into a wall: a huge clang.
  bank.crash = make(1.0, 1, function(buf)
    buf:kick(0, 1)
    buf:tone(0, 0.9, 150, { wave = "square", amp = 0.25, decay = 0.35 })
    buf:tone(0, 0.7, 330, { wave = "square", amp = 0.15, decay = 0.3 })
    buf:noiseBurst(0, 0.5, { amp = 0.7, decay = 0.15 })
    buf:lowpass(2200)
  end)
end

local function play(name, x, y)
  Sound.play(bank[name], x, y, 0.05)
end

function Foreman.clear()
  cl = fresh()
  Look.ripped = false
end

local function age(list, dt)
  for i = #list, 1, -1 do
    list[i].t = list[i].t + dt
    if list[i].t >= list[i].total then
      table.remove(list, i)
    end
  end
end

function Foreman.update(dt)
  clock = clock + dt
  age(cl.drops, dt)
  age(cl.waves, dt)
  age(cl.lanes, dt)
  if cl.stars then
    cl.stars.t = cl.stars.t + dt
    if cl.stars.t >= cl.stars.total then
      cl.stars = nil
    end
  end
  local c = cl.cannon -- the torn-off cannon, flung across the floor, skidding to a stop
  if c and c.t < 1 then
    c.t = c.t + dt
    local k = math.max(0, 1 - dt * 3)
    c.vx, c.vy = c.vx * k, c.vy * k
    c.x, c.y, c.spin = c.x + c.vx * dt, c.y + c.vy * dt, c.spin + c.vx * 0.004 * dt
  end
end

--- What the objective line should be after on `map` now: "fight" once it
--- is awake until it is down, or nil (no Foreman here, or not yet).
function Foreman.objective(map)
  local spec = map and map.boss
  if not (spec and spec.kind == "foreman") or cl.down or not cl.awake then
    return nil
  end
  return "fight"
end

--- The rings of what came down, a charge's lane, the cannon on the floor.
function Foreman.drawBelowCars()
  if cl.cannon then
    Look.drawCannon(cl.cannon.x, cl.cannon.y, cl.cannon.spin)
  end
  for _, l in ipairs(cl.lanes) do
    Paint.lane(l.x, l.y, l.angle, l.length, l.width, l.t / l.total, clock)
  end
  for _, w in ipairs(cl.waves) do
    local k = w.t / w.total
    love.graphics.setColor(0.85, 0.75, 0.6, 0.6 * (1 - k))
    love.graphics.setLineWidth(5 * (1 - k) + 1)
    love.graphics.circle("line", w.x, w.y, w.r * (0.3 + 1.1 * k), 40)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- The crane's haulers coming down on their cables, and the stars round
--- its head while it reels.
function Foreman.drawAboveCars()
  for _, d in ipairs(cl.drops) do
    local k = d.t / d.total
    local y = d.y - Foreman.CABLE * (1 - k) ^ 2
    love.graphics.setColor(0, 0, 0, 0.15 + 0.3 * k) -- its shadow, growing as it comes
    love.graphics.ellipse("fill", d.x, d.y, 20 * (0.4 + 0.6 * k), 16 * (0.4 + 0.6 * k), 18)
    love.graphics.setColor(0.12, 0.12, 0.13)
    love.graphics.setLineWidth(2)
    love.graphics.line(d.x, y - 1000, d.x, y - 12) -- the cable, from the crane out of sight overhead
    love.graphics.setLineWidth(1)
    Paint.disc(d.x, y - 12, 4, Hauler.C.yellow) -- the hook
    Hauler.draw({ dx = d.x, dy = y, facing = math.pi / 2, code = d.code, stride = 0 }, clock)
  end
  local s = cl.stars and Army.shownOf("FMN")
  if s then
    for i = 0, 4 do
      local a = clock * 4 + i * 2 * math.pi / 5
      local x, y = s.dx + math.cos(a) * 34, s.dy - 40 + math.sin(a) * 10
      love.graphics.setColor(1, 0.9, 0.3)
      love.graphics.polygon("fill", x, y - 5, x + 1.5, y - 1.5, x + 5, y, x + 1.5, y + 1.5, x, y + 5, x - 1.5, y + 1.5,
        x - 5, y, x - 1.5, y - 1.5)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- Its bar, once it is awake.
function Foreman.drawHUD()
  local s = cl.awake and not cl.down and Army.shownOf("FMN")
  if s then
    Bar.draw({
      title = "FOREMAN BIG-B055", titleColor = TITLE, fill = Look.ripped and FILL_RIPPED or FILL, hp = s.hp,
      max = s.max, stamina = s.breath, staminaMax = 100, winded = s.winded, harder = "OVERTIME",
    })
  end
end

Foreman.clientMessages = {
  FMN_WAKE = function()
    cl.awake = true
  end,
  FMN_CALL = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      play("whistle", x, y)
    end
  end,
  FMN_DROP = function(_client, args)
    local x, y, t, code = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), args[4]
    if x and y and t and t > 0 and Hauler.KITS[code or ""] then
      cl.drops[#cl.drops + 1] = { x = x, y = y, t = 0, total = t, code = code }
      play("winch", x, y)
    end
  end,
  FMN_LAND = function(_client, args)
    local x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y and r then
      cl.waves[#cl.waves + 1] = { x = x, y = y, r = r, t = 0, total = 0.6 }
      play("land", x, y)
    end
  end,
  FMN_LANE = function(_client, args)
    local x, y, a = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local len, w, t = tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    if x and y and a and len and w and t and t > 0 then
      cl.lanes[#cl.lanes + 1] = { x = x, y = y, angle = a, length = len, width = w, t = 0, total = t }
    end
  end,
  FMN_CRASH = function(_client, args)
    local x, y, t = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y and t and t > 0 then
      cl.stars = { t = 0, total = t }
      cl.waves[#cl.waves + 1] = { x = x, y = y, r = 70, t = 0, total = 0.6 }
      play("crash", x, y)
    end
  end,
  FMN_RIP = function(_client, args)
    local x, y, facing = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y and facing and not Look.ripped then
      Look.ripped = true
      local a = facing + math.pi / 2 -- flung out to its right, the side it came off
      cl.cannon = { x = x, y = y, vx = math.cos(a) * 420, vy = math.sin(a) * 420, spin = a, t = 0 }
      play("rip", x, y)
    end
  end,
  FMN_DOWN = function()
    cl.down, cl.awake, cl.lanes, cl.stars = true, true, {}, nil
  end,
}

return Foreman
