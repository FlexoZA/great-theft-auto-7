-- The Knuckle Scrapper, the Frozen Wreck's boss (docs/borderline.md, "The
-- bosses"): how it comes into the fight, the junk that feeds it, and what
-- everyone sees of it. What it does in the fight is its brain's
-- (knk_brain.lua: it is one of the army, model KNK), how it looks
-- scrapper_look.lua's. init.lua passes its hooks on to this module.
--
-- The map says where (city-map's `map.boss` { kind = "scrapper", x, y,
-- fromX, fromY, after, unlocks, climb }): the moment lock `after` opens
-- (the yard's three terminals hacked) it builds itself out of the engine at
-- (fromX, fromY), scrap dragging itself together over BUILD seconds onto
-- (x, y), in front of the tunnel, and stands up. Its health is a boss's
-- (Bosses.health: more humans, more; tougher on a job done before). Down,
-- it opens lock `unlocks` (the tunnel's blast door: a lock of the
-- terminals feature with no terminals, `serverUnlock`).
--
-- The junk that feeds it: while it is up, every FEED.every seconds junk
-- haulers climb out of the wreck (`climb`, a carriage's side each) and
-- make straight for it, carrying scrap (junk_brain.lua's `feed`). One
-- that reaches it is pulled in, and heals it FEED.heal. Shoot them on the
-- way. Hits knock its plates off as its health goes (scrapper_look.lua).
--
-- Every screen: the scrap flying together out of the engine, the tell of
-- each move (a fist going back, a lump lifted), the swing's arc, a lump of
-- scrap tumbling through the air onto its ring, the junk pulled into it,
-- its plates coming off, the boss bar.
--
-- Messages
--   server -> all  KNK_BUILD <fromX> <fromY> <x> <y> <seconds>   it is building itself (to a joiner too)
--   server -> all  KNK_TELL <draw|lift> <seconds>                a swing / a throw is coming
--   server -> all  KNK_SWING <x> <y> <facing> <reach>            it swung there
--   server -> all  KNK_THROW <fromX> <fromY> <x> <y> <seconds>   a lump of scrap let go, landing there
--   server -> all  KNK_LAND <x> <y> <radius>                     it came down there
--   server -> all  KNK_CLIMB <x> <y>                             junk climbed out of the wreck there
--   server -> all  KNK_EAT <x> <y> <toX> <toY>                   junk pulled into it
--   server -> all  KNK_DOWN                                      it fell apart, the tunnel open (to a joiner too)

local Protocol = require("src.net.protocol")
local Bosses = require("src.features.bosses")
local Bar = require("src.features.bosses.bar")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Terminals = require("src.features.terminals")
local Army = require("src.features.borderline.army")
local Chassis = require("src.features.borderline.chassis")
local Barrage = require("src.features.borderline.barrage")
local Brain = require("src.features.borderline.knk_brain")
local Look = require("src.features.borderline.scrapper_look")

local Scrapper = {}

-- Tuning ------------------------------------------------------------------
Scrapper.BUILD = 2.6 -- seconds it takes to drag itself together
-- Junk climbing out to feed it: `count` every `every` seconds (one more for
-- each human past the first), no more than `cap` out at once; one that
-- reaches it heals it `heal` (for one player: grown with its health).
Scrapper.FEED = { first = 4, every = 9, count = 2, cap = 5, heal = 90 }
Scrapper.EAT_REACH = 14 -- px past touching that pulls one in
Scrapper.LUMP_UP = 150 -- px high a lump goes at the top of its flight (drawn)

local TITLE = { 0.95, 0.76, 0.19 }
local FILL = { 0.78, 0.36, 0.16 }
local SPARK = { 1.00, 0.70, 0.30 }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function lockOpen(map, name)
  for _, l in ipairs(map and map.locks or {}) do
    if l.name == name then
      return l.open == true
    end
  end
  return false
end

-- Server --------------------------------------------------------------------

local sv = nil -- { map, spec, phase = "waiting" | "building" | "up" | "down", buildIn, s, feeders, feedIn, lumps }

--- A level starts on `map`: the Scrapper waiting in the engine, if it has one.
function Scrapper.serverStart(map)
  local spec = map and map.boss
  sv = spec and spec.kind == "scrapper" and { map = map, spec = spec, phase = "waiting", feeders = {}, lumps = {} }
    or nil
end

function Scrapper.serverStop()
  sv = nil
end

local function build(server, beat)
  local spec = sv.spec
  sv.phase, sv.buildIn = "building", Scrapper.BUILD
  server:broadcast(Protocol.encode("KNK_BUILD", fmt(spec.fromX), fmt(spec.fromY), fmt(spec.x), fmt(spec.y),
    ("%.2f"):format(Scrapper.BUILD)))
  beat("scrapper")
end

local function stand(server)
  local spec = sv.spec
  local s = Army.serverSpawn("KNK", spec.x, spec.y, math.pi / 2) -- facing down the yard, the way everyone comes
  if not s then
    sv.phase = "down" -- no army on: nothing to hold the tunnel
    Terminals.serverUnlock(server, spec.unlocks)
    return
  end
  s.hp = Bosses.health(Brain.HEALTH, server)
  s.max = s.hp
  sv.s, sv.phase, sv.feedIn = s, "up", Scrapper.FEED.first
  server:broadcast(Protocol.encode("KNK_LAND", fmt(s.x), fmt(s.y), Brain.RADIUS * 2))
end

--- What its brain left for everyone to see.
local function tell(server, s)
  for _, e in ipairs(s.events) do
    if e[1] == "draw" or e[1] == "lift" then
      server:broadcast(Protocol.encode("KNK_TELL", e[1], ("%.2f"):format(e[2])))
    elseif e[1] == "swing" then
      server:broadcast(Protocol.encode("KNK_SWING", fmt(e[2]), fmt(e[3]), ("%.2f"):format(e[4]), e[5]))
    elseif e[1] == "throw" then
      local _, fx, fy, x, y, r, flight, damage, shove = unpack(e)
      sv.lumps[#sv.lumps + 1] = { x = x, y = y, r = r, t = flight, damage = damage, shove = shove }
      Barrage.serverMark(server, x, y, r, flight)
      server:broadcast(Protocol.encode("KNK_THROW", fmt(fx), fmt(fy), fmt(x), fmt(y), ("%.2f"):format(flight)))
    end
  end
  s.events = {}
end

--- Lumps of scrap coming down on their rings.
local function lumps(server, dt)
  for i = #sv.lumps, 1, -1 do
    local l = sv.lumps[i]
    l.t = l.t - dt
    if l.t <= 0 then
      table.remove(sv.lumps, i)
      Chassis.slam(server, l.x, l.y, l.r, l.damage, l.shove)
      server:broadcast(Protocol.encode("KNK_LAND", fmt(l.x), fmt(l.y), l.r))
    end
  end
end

--- Junk climbing out of the wreck to feed it, and pulled in when it gets there.
local function feed(server, s, dt)
  local F = Scrapper.FEED
  local alive = {}
  for _, f in ipairs(sv.feeders) do
    if Army.serverAlive(f) then
      if Chassis.dist2(f.x, f.y, s.x, s.y) <= (s.radius + f.radius + Scrapper.EAT_REACH) ^ 2 then
        Army.serverTake(f)
        s.hp = math.min(s.max, s.hp + F.heal * s.max / Brain.HEALTH)
        server:broadcast(Protocol.encode("KNK_EAT", fmt(f.x), fmt(f.y), fmt(s.x), fmt(s.y)))
      else
        alive[#alive + 1] = f
      end
    end
  end
  sv.feeders = alive
  sv.feedIn = sv.feedIn - dt
  local climb = sv.spec.climb or {}
  if sv.feedIn > 0 or #climb == 0 then
    return
  end
  sv.feedIn = F.every
  for _ = 1, math.min(Bosses.plus(F.count, server), F.cap - #sv.feeders) do
    local c = climb[random(#climb)]
    local x, y = c.x + (random() - 0.5) * 60, c.y + (random() - 0.5) * 60 -- not all out of one spot
    local f = Army.serverSpawn("JNK", x, y, math.atan2(s.y - y, s.x - x))
    if f then
      f.feed = s
      sv.feeders[#sv.feeders + 1] = f
      server:broadcast(Protocol.encode("KNK_CLIMB", fmt(f.x), fmt(f.y)))
    end
  end
end

--- `beat(what)` raises a story beat: "scrapper" as it builds itself,
--- "scrapper-down" when it falls apart.
function Scrapper.serverStep(server, dt, beat)
  if not sv then
    return
  end
  if sv.phase == "waiting" then
    if lockOpen(sv.map, sv.spec.after) then
      build(server, beat)
    end
  elseif sv.phase == "building" then
    sv.buildIn = sv.buildIn - dt
    if sv.buildIn <= 0 then
      stand(server)
    end
  elseif sv.phase == "up" then
    tell(server, sv.s)
    if sv.s.dead then
      sv.phase = "down"
      for _, f in ipairs(sv.feeders) do
        f.feed = nil -- nothing left to feed: they're just junk again
      end
      sv.feeders = {}
      Terminals.serverUnlock(server, sv.spec.unlocks)
      server:broadcast(Protocol.encode("KNK_DOWN"))
      beat("scrapper-down")
    else
      feed(server, sv.s, dt)
    end
  end
  lumps(server, dt)
end

function Scrapper.serverPlayerJoined(server, player)
  if sv and sv.phase == "building" then
    local spec = sv.spec
    server:send(player, Protocol.encode("KNK_BUILD", fmt(spec.fromX), fmt(spec.fromY), fmt(spec.x), fmt(spec.y),
      ("%.2f"):format(sv.buildIn)))
  elseif sv and sv.phase == "down" then
    server:send(player, Protocol.encode("KNK_DOWN"))
  end
end

--- The launch's --boss: the yard's terminals as good as done, `player` up
--- by the engine, and the Scrapper building itself. True when there is one
--- to skip to.
function Scrapper.serverSkipTo(server, player, beat)
  if not (sv and sv.phase == "waiting") then
    return false
  end
  local spec = sv.spec
  Terminals.serverUnlock(server, spec.after)
  if player and player.body then
    player.body.x, player.body.y = spec.x, spec.y + 520
  end
  build(server, beat)
  return true
end

--- The wiki's page on it (tools/wiki, docs/wiki.md).
function Scrapper.wikiEnemies(add)
  local Heal = require("src.features.bosses.heal")
  local B, W, T, F = Brain, Brain.SWING, Brain.THROW, Scrapper.FEED
  add({
    kind = "borderline/knk",
    name = "Knuckle Scrapper",
    quests = { "borderline" },
    boss = true,
    where = "The Frozen Wreck: it builds itself out of the engine in front of the tunnel once the yard's three "
      .. "terminals are hacked, and the tunnel's blast door stays shut until it falls apart",
    about = "A junk hauler that built itself huge out of Max's wrecked train: a heap of rusted scrap with a "
      .. "carriage panel on its back, the engine's headlight for an eye and bogies for fists. The line's first boss.",
    stats = {
      { "Health", B.HEALTH },
      { "Speed", ("%g px/s, %g winded"):format(B.CONF.speed, B.CONF.walk) },
      { "Sight", B.CONF.range, "px" },
    },
    weapons = {
      { "Swing", ("at anyone within %g px in front of it: its fist goes back for %g s, then sweeps round, %g "
        .. "impact damage, thrown %g px"):format(W.reach, W.windUp, W.damage, W.shove) },
      { "Scrap", ("at anyone %g px or more off, every %g to %g s: it lifts a lump of itself for %g s and lobs it "
        .. "onto a red ring, %g impact damage within %g px, thrown %g px"):format(T.min, T.every[1], T.every[2],
        T.windUp, T.damage, T.radius, T.shove) },
    },
    abilities = {
      ("Every %g s %d junk haulers climb out of the wreck and make straight for it, %d out at most; each that "
        .. "reaches it is pulled in and heals it %g."):format(F.every, F.count, F.cap, F.heal),
      ("Under %g%% health it goes for the nearest medkit within %g px, for %g health."):format(Heal.below * 100,
        Heal.range, Heal.amount),
      "Its plates come off as it's hurt, down to the bare frame.",
    },
    tips = {
      "Shoot the junk haulers carrying scrap before they reach it: every one heals it.",
      "Step back when its fist goes back; the swing only reaches what's in front of it.",
      "Keep moving off the red ring when it lifts a lump over its head.",
    },
    drops = ("%g koins and a pickup"):format(Army.drops.KNK),
  })
end

--- For tests.
function Scrapper.server()
  return sv
end

-- Client --------------------------------------------------------------------

local clock = 0
local bank = {}

local function fresh()
  return { build = nil, lumps = {}, swings = {}, waves = {}, eats = {}, puffs = {}, shed = {}, plates = nil,
    started = false, down = false }
end
local cl = fresh()

function Scrapper.load()
  local function make(seconds, volume, synth)
    local buf = Synth.newBuffer(seconds)
    synth(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(300, 2600)
    return src
  end
  -- Building itself: metal grinding and dragging, climbing, then a clang.
  bank.build = make(2.8, 0.7, function(buf)
    buf:noiseBurst(0, 2.5, { amp = 0.4, attack = 1.6, decay = 0.6 })
    buf:sweep(0, 2.5, 60, 180, { wave = "saw", amp = 0.25, attack = 1.2, decay = 0.8, vibRate = 9, vibDepth = 12 })
    for i = 0, 7 do
      buf:tone(0.3 + i * 0.28, 0.12, 500 + random(500), { wave = "square", amp = 0.12, decay = 0.08 })
    end
    buf:kick(2.55, 1)
    buf:lowpass(2400)
  end)
  -- A swing: a whoosh of air.
  bank.swing = make(0.5, 0.6, function(buf)
    buf:noiseBurst(0, 0.4, { amp = 0.5, attack = 0.15, decay = 0.2 })
    buf:sweep(0, 0.35, 220, 90, { wave = "sine", amp = 0.3, decay = 0.2 })
    buf:lowpass(1200)
  end)
  -- A lump of scrap crashing down: a deep clang and rattle.
  bank.land = make(0.9, 0.9, function(buf)
    buf:kick(0, 1)
    buf:tone(0, 0.6, 180, { wave = "square", amp = 0.2, decay = 0.25 })
    buf:tone(0, 0.5, 410, { wave = "square", amp = 0.12, decay = 0.2 })
    buf:noiseBurst(0, 0.6, { amp = 0.6, decay = 0.18 })
    buf:lowpass(2200)
  end)
  -- Heaving a lump up: a groan of bending metal.
  bank.lift = make(0.9, 0.5, function(buf)
    buf:sweep(0, 0.85, 90, 55, { wave = "saw", amp = 0.3, attack = 0.2, decay = 0.4, vibRate = 6, vibDepth = 8 })
    buf:lowpass(900)
  end)
  -- Junk pulled in: a crunch.
  bank.eat = make(0.45, 0.6, function(buf)
    buf:noiseBurst(0, 0.3, { amp = 0.7, decay = 0.08 })
    buf:tone(0.02, 0.2, 260, { wave = "square", amp = 0.2, decay = 0.1 })
    buf:lowpass(2000)
  end)
  -- Junk climbing out of the wreck: a scrape.
  bank.climb = make(0.4, 0.4, function(buf)
    buf:noiseBurst(0, 0.35, { amp = 0.3, attack = 0.05, decay = 0.2 })
    buf:highpass(700)
  end)
  -- A plate knocked off: a clank.
  bank.plate = make(0.35, 0.5, function(buf)
    buf:tone(0, 0.3, 700, { wave = "square", amp = 0.15, decay = 0.1 })
    buf:tone(0, 0.25, 1130, { wave = "square", amp = 0.08, decay = 0.08 })
    buf:noiseBurst(0, 0.05, { amp = 0.4, decay = 0.02 })
    buf:lowpass(3000)
  end)
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.9 + random() * 0.2)
    s:setVolume(0.8 * Audio.volume("weapons"))
    s:play()
  end
end

function Scrapper.clear()
  cl = fresh()
  Look.tell.draw, Look.tell.lift, Look.tell.swing = 0, 0, 0
end

--- Its plates as they come off: one flung out from it for each it lost.
local function shedPlates()
  local s = Army.shownOf("KNK")
  if not s then
    return
  end
  local n = Look.plateCount(s.hp / s.max)
  if cl.plates and n < cl.plates then
    for _ = 1, cl.plates - n do
      local a = random() * 2 * math.pi
      cl.shed[#cl.shed + 1] = { x = s.dx, y = s.dy, vx = math.cos(a) * 160, vy = math.sin(a) * 160, spin = a, t = 0 }
      play("plate", s.dx, s.dy)
    end
  end
  cl.plates = n
end

local function age(list, dt, life)
  for i = #list, 1, -1 do
    list[i].t = list[i].t + dt
    if list[i].t >= (list[i].total or life) then
      table.remove(list, i)
    end
  end
end

function Scrapper.update(dt)
  clock = clock + dt
  if cl.build then
    cl.build.t = cl.build.t + dt
    if cl.build.t >= cl.build.total then
      cl.build = nil
    end
  end
  local T = Look.tell
  T.draw = cl.drawFor and math.min(1, T.draw + dt / cl.drawFor) or 0
  T.lift = cl.liftFor and math.min(1, T.lift + dt / cl.liftFor) or 0
  T.swing = math.max(0, T.swing - dt * 2.5)
  age(cl.lumps, dt)
  age(cl.swings, dt, 0.35)
  age(cl.waves, dt, 0.6)
  age(cl.eats, dt, 0.45)
  age(cl.puffs, dt, 0.8)
  for i = #cl.shed, 1, -1 do -- plates flung off, skidding to a stop, lying a while
    local p = cl.shed[i]
    p.t = p.t + dt
    local k = math.max(0, 1 - dt * 4)
    p.vx, p.vy = p.vx * k, p.vy * k
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    if p.t > 8 then
      table.remove(cl.shed, i)
    end
  end
  shedPlates()
end

--- What the objective line should be after on `map` now: "fight" while it
--- is building itself or up, or nil (no Scrapper here, not woken yet, or
--- down: the terminals and the way on say the rest).
function Scrapper.objective(map)
  local spec = map and map.boss
  if not (spec and spec.kind == "scrapper") or cl.down then
    return nil
  end
  if cl.started or Army.shownOf("KNK") then
    return "fight"
  end
  return nil
end

--- The swings' arcs and the dust where lumps came down, on the ground;
--- the plates it shed.
function Scrapper.drawBelowCars()
  for _, p in ipairs(cl.shed) do
    love.graphics.push()
    love.graphics.translate(p.x, p.y)
    love.graphics.rotate(p.spin + p.t * (p.vx * 0.01))
    love.graphics.setColor(0.06, 0.06, 0.07, math.min(1, 8 - p.t))
    love.graphics.rectangle("fill", -8, -5, 16, 10, 2)
    love.graphics.setColor(0.38, 0.41, 0.46, math.min(1, 8 - p.t))
    love.graphics.rectangle("fill", -6.5, -3.5, 13, 7, 1.5)
    love.graphics.pop()
  end
  for _, s in ipairs(cl.swings) do
    local k = s.t / 0.35
    love.graphics.setColor(0.92, 0.86, 0.75, 0.55 * (1 - k))
    love.graphics.setLineWidth(10 * (1 - k) + 2)
    love.graphics.arc("line", "open", s.x, s.y, s.r * (0.75 + 0.25 * k), s.facing - 1.1, s.facing + 1.1, 18)
    love.graphics.setLineWidth(1)
  end
  for _, w in ipairs(cl.waves) do
    local k = w.t / 0.6
    love.graphics.setColor(0.85, 0.75, 0.6, 0.6 * (1 - k))
    love.graphics.setLineWidth(5 * (1 - k) + 1)
    love.graphics.circle("line", w.x, w.y, w.r * (0.3 + 1.1 * k), 40)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Scrap dragging itself out of the engine onto where it will stand: a
--- stream of lumps, the heap growing under them.
local function drawBuild(b)
  local k = b.t / b.total
  for i = 1, 14 do
    local p = (k * 2.2 - i / 14) -- each lump on its way in its turn
    if p > 0 and p < 1 then
      local x = b.fromX + (b.x - b.fromX) * p + math.sin(i * 1.7) * 30 * (1 - p)
      local y = b.fromY + (b.y - b.fromY) * p + math.cos(i * 2.3) * 30 * (1 - p) - math.sin(p * math.pi) * 60
      Look.drawLump(x, y, clock * 4 + i, 0.5 + (i % 3) * 0.15)
    end
  end
  love.graphics.setColor(0, 0, 0, 0.3 * k)
  love.graphics.ellipse("fill", b.x + 8, b.y + 11, 64 * k, 58 * k, 24)
  for i = 1, math.floor(k * 10) do -- the heap piling up where it'll stand
    local a = i * 2.1
    Look.drawLump(b.x + math.cos(a) * 18 * (1 - i / 12), b.y + math.sin(a) * 16 * (1 - i / 12), a, 0.9)
  end
end

--- A lump of scrap in the air: an arc from where it let go onto its ring,
--- its shadow on the ground under it.
local function drawLump(l)
  local k = l.t / l.total
  local x, y = l.fromX + (l.x - l.fromX) * k, l.fromY + (l.y - l.fromY) * k
  love.graphics.setColor(0, 0, 0, 0.2 + 0.25 * k)
  love.graphics.ellipse("fill", x, y, 12 + 6 * k, 9 + 4 * k, 16)
  Look.drawLump(x, y - math.sin(k * math.pi) * Scrapper.LUMP_UP, clock * 6, 1.1)
end

--- The scrap over every junk hauler feeding it, and a line from each to it.
local function drawFeeders(s)
  for _, f in ipairs(Army.shownFeeding()) do
    if s then
      love.graphics.setColor(SPARK[1], SPARK[2], SPARK[3], 0.18 + 0.1 * math.sin(clock * 6 + f.x))
      love.graphics.setLineWidth(2)
      local dx, dy = s.dx - f.x, s.dy - f.y
      local d = math.max(1, math.sqrt(dx * dx + dy * dy))
      for k = 0, d - 24, 24 do -- dashed, crawling towards it
        local a, b = (k + (clock * 40) % 24) / d, math.min(1, (k + 12 + (clock * 40) % 24) / d)
        love.graphics.line(f.x + dx * a, f.y + dy * a, f.x + dx * b, f.y + dy * b)
      end
      love.graphics.setLineWidth(1)
    end
    Look.drawLoad(f.x, f.y, clock)
  end
end

--- Junk pulled into it: sparks streaking from where it was into it.
local function drawEat(e)
  local k = e.t / 0.45
  love.graphics.setBlendMode("add")
  for i = 0, 5 do
    local p = math.min(1, k * 1.6 - i * 0.08)
    if p > 0 then
      local x = e.x + (e.toX - e.x) * p + math.sin(i * 2.1) * 10 * (1 - p)
      local y = e.y + (e.toY - e.y) * p + math.cos(i * 1.3) * 10 * (1 - p)
      love.graphics.setColor(SPARK[1], SPARK[2], SPARK[3], 0.9 * (1 - k))
      love.graphics.circle("fill", x, y, 3, 8)
    end
  end
  love.graphics.setColor(SPARK[1], SPARK[2], SPARK[3], 0.4 * (1 - k))
  love.graphics.circle("fill", e.toX, e.toY, 30 + 20 * k, 20)
  love.graphics.setBlendMode("alpha")
end

--- Snow kicked up where junk climbed out of the wreck.
local function drawPuff(p)
  local k = p.t / 0.8
  love.graphics.setColor(0.92, 0.94, 0.98, 0.5 * (1 - k))
  for i = 0, 4 do
    local a = i * 1.26
    love.graphics.circle("fill", p.x + math.cos(a) * 18 * k, p.y + math.sin(a) * 18 * k, 6 + 8 * k, 12)
  end
end

--- Building itself, the lumps in the air, the junk feeding it, over everyone.
function Scrapper.drawAboveCars()
  if cl.build then
    drawBuild(cl.build)
  end
  for _, p in ipairs(cl.puffs) do
    drawPuff(p)
  end
  drawFeeders(not cl.down and Army.shownOf("KNK"))
  for _, e in ipairs(cl.eats) do
    drawEat(e)
  end
  for _, l in ipairs(cl.lumps) do
    drawLump(l)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Its bar, while it is up.
function Scrapper.drawHUD()
  local s = not cl.down and Army.shownOf("KNK")
  if s then
    Bar.draw({
      title = "KNUCKLE SCRAPPER", titleColor = TITLE, fill = FILL, hp = s.hp, max = s.max,
      stamina = s.breath, staminaMax = 100, winded = s.winded, harder = "BIGGER",
    })
  end
end

Scrapper.clientMessages = {
  KNK_BUILD = function(_client, args)
    local fx, fy, x, y, t = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4]),
      tonumber(args[5])
    if fx and fy and x and y and t and t > 0 then
      cl.build, cl.started = { fromX = fx, fromY = fy, x = x, y = y, t = 0, total = t }, true
      play("build", x, y)
    end
  end,
  KNK_TELL = function(_client, args)
    local t = tonumber(args[2])
    if t and t > 0 and args[1] == "draw" then
      cl.drawFor, Look.tell.draw = t, 0
    elseif t and t > 0 and args[1] == "lift" then
      cl.liftFor, Look.tell.lift = t, 0
      local s = Army.shownOf("KNK")
      if s then
        play("lift", s.dx, s.dy)
      end
    end
  end,
  KNK_SWING = function(_client, args)
    local x, y, facing, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    cl.drawFor, Look.tell.draw, Look.tell.swing = nil, 0, 1
    if x and y and facing and r then
      cl.swings[#cl.swings + 1] = { x = x, y = y, facing = facing, r = r, t = 0 }
      play("swing", x, y)
    end
  end,
  KNK_THROW = function(_client, args)
    local fx, fy, x, y, t = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4]),
      tonumber(args[5])
    cl.liftFor, Look.tell.lift = nil, 0
    if fx and fy and x and y and t and t > 0 then
      cl.lumps[#cl.lumps + 1] = { fromX = fx, fromY = fy, x = x, y = y, t = 0, total = t }
    end
  end,
  KNK_LAND = function(_client, args)
    local x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y and r then
      cl.waves[#cl.waves + 1] = { x = x, y = y, r = r, t = 0 }
      cl.build, cl.started = nil, true
      play("land", x, y)
    end
  end,
  KNK_CLIMB = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      cl.puffs[#cl.puffs + 1] = { x = x, y = y, t = 0 }
      play("climb", x, y)
    end
  end,
  KNK_EAT = function(_client, args)
    local x, y, tx, ty = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and tx and ty then
      cl.eats[#cl.eats + 1] = { x = x, y = y, toX = tx, toY = ty, t = 0 }
      play("eat", tx, ty)
    end
  end,
  KNK_DOWN = function()
    cl.down, cl.started, cl.build = true, true, nil
    cl.drawFor, cl.liftFor = nil, nil
  end,
}

return Scrapper
