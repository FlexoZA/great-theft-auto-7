-- Gang Hangout: a building that puts armed guards on the street for you.
--
-- Build it on a plot you own like any other building (buildings' kind
-- "hangout", run by this feature through `service`). It keeps a fund of
-- koins its boss (the owner) deposits from its square. While there is money
-- in it, up to `Gang.guards` guards come out of the door one by one, each
-- taking its crew's `spawn` price (100 Fcks for street thugs) out of the
-- fund, and stand at their posts on the sidewalk out front. A guard who goes
-- down is replaced `Gang.respawn` seconds later, for the same price; with
-- the fund empty nobody comes out. The boss can take what is left in the
-- fund back.
--
-- The guards fight for their boss: anyone (a player or a bot, police cars
-- too) who hurts one of the boss's buildings, anywhere in the city, or the
-- boss while they are on the hangout's block or one of the blocks around
-- it, or one of the guards, has the whole crew after them. So does a police
-- officer on foot who shoots the boss there, or a guard: their rounds name
-- nobody, so it is taken to be the nearest officer after somebody within
-- shooting range (`copReach`). The guards' own rounds are marked as the
-- gang's (`serverFireFrom`'s `from`), so unlike the force's own they hit
-- officers. The crew is after them for `Gang.chase` seconds, renewed
-- by every new attack. They give up when that runs out or the attacker is
-- down or gone, and walk back to their posts. guards.lua is what each one
-- does.
--
-- The hangout is upgradable (crews.lua): each level is a crew of one of
-- the game's armed NPCs with that NPC's gun, and costs more, to upgrade to
-- and for each guard, the harder the gun hits. Guards already out keep the
-- gun they came with; the ones who replace them come out as the new crew.
--
-- The guards live in the city: on a quest map they wait where they are. A
-- ruined hangout loses its fund and sends nobody new out until it is
-- rebuilt; one whose plot changes hands is gone, its crew with it. A saved
-- world keeps each hangout's level, its fund and how many guards were out
-- (they are back at their posts, already paid for).
--
-- Messages
--   client -> server  GANG_DEPOSIT  <plotId> <amount>   (into the fund, from my wallet)
--   client -> server  GANG_WITHDRAW <plotId>            (all of the fund back into my wallet)
--   client -> server  GANG_UPGRADE  <plotId>            (the next crew)
--   server -> all     GANG_STATE    <plotId> <owner> <level> <fund> <out>
--   server -> all     GANG_GONE     <plotId>
--   server -> all     GANG_UNITS    <tick> [<id> <plotId> <x> <y> <facing> <level> <hp> <mode>]...
--                     (unreliable, 10 Hz; mode p = at his post, w = walking back, f = fighting)
--   server -> all     GANG_DOWN     <id> <x> <y> <angle> <cause>
--   server -> owner   GANG_ALERT    <targetId> <why>     (building | boss | crew; police | copcrew:
--                                                         an officer on foot, target 0)
--   server -> player  GANG_OK       <what>               (deposit | withdraw | upgrade)
--   server -> player  GANG_NO       <reason>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Layout = require("src.features.city-map.layout")
local Crews = require("src.features.gang-hangout.crews")
local Guards = require("src.features.gang-hangout.guards")
local Render = require("src.features.gang-hangout.render")

local Gang = { name = "gang-hangout" }

-- Tuning ------------------------------------------------------------------
Gang.guards = 4 -- guards one hangout puts out
Gang.respawn = 10 -- seconds before a guard who went down is replaced
Gang.spawnGap = 1.2 -- seconds between guards coming out of the same door
Gang.chase = 30 -- seconds the crew stays after somebody, renewed by each attack
Gang.zoneBlocks = 1 -- blocks round the hangout's own where they defend their boss
Gang.maxDeposit = 100000 -- most one deposit can put in
Gang.copReach = 560 -- px; an officer after the boss this near when they are hit is taken to have done it

local T = Layout.TILE
local SLACK = 40 -- px the host allows for a player drawn a little behind where it is
local SYNC_EVERY = 3 -- server ticks between GANG_UNITS packets
local SMOOTHING = 12 -- per second, easing towards the last position heard
local SNAP = 150 -- px; a jump this big is a new guard, not a step
local NOTICE_TIME = 3
local SAVE_VERSION = 1
local MODES = { p = "post", w = "home", f = "fight" }
local WIRE = { post = "p", home = "w", fight = "f" }
local REASONS = {
  away = "Stand on your hangout's square.",
  notyours = "That isn't your hangout.",
  ruined = "Rebuild it first.",
  top = "Your crew is as good as it gets.",
  empty = "The fund is empty.",
  broke = "You can't afford it.",
  nogame = "Not now.",
  unknown = "That can't be done.",
}
local DONE = {
  deposit = "Deposited. Your crew is on its way.",
  withdraw = "You took the fund back.",
  upgrade = "Upgraded. New guards come out with the new crew.",
}
local WHY = {
  building = "%s hit one of your buildings. Your crew is after them.",
  boss = "%s went for you. Your crew is after them.",
  crew = "%s went for your crew. They're after them.",
  police = "The police are on you. Your crew is taking them on.",
  copcrew = "The police shot at your crew. They're taking them on.",
}
local RED, AMBER = { 1, 0.45, 0.4 }, { 1, 0.75, 0.3 }

local function fmt(v)
  return ("%.0f"):format(v)
end

local function amount(n)
  local money = Features.byName.money
  return money and money.amount(n) or tostring(n)
end

local function realEstate()
  return Features.byName["real-estate"]
end

local function buildings()
  return Features.byName.buildings
end

local function plotById(id)
  local re = realEstate()
  return re and re.plots[id]
end

--- The city map, while it is the one in play (guards live there).
local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.current == city.DEFAULT and city.map or nil
end

--- Where a guard comes out: the plot's square on the sidewalk.
local function doorOf(plot)
  return plot.x + plot.w / 2, plot.y + plot.h + T / 2
end

--- Where guard `slot` stands: along the sidewalk out front, two either side
--- of the square, facing the street.
local POSTS = { 0.14, 0.3, 0.7, 0.86 }
local function postOf(plot, slot)
  local share = POSTS[(slot - 1) % #POSTS + 1]
  return { x = plot.x + plot.w * share, y = plot.y + plot.h + T / 2, angle = math.pi / 2 }
end

--- Is (x, y) on the hangout's block or one of the `zoneBlocks` around it?
local function inZone(plot, x, y)
  local reach = Gang.zoneBlocks * Layout.PERIOD * T
  return x >= plot.x - reach and x <= plot.x + plot.w + reach and y >= plot.y - reach and y <= plot.y + plot.h + reach
end

local function contains(r, x, y, slack)
  return x >= r.x - slack and x <= r.x + r.w + slack and y >= r.y - slack and y <= r.y + r.h + slack
end

-- Server --------------------------------------------------------------------

-- { guards, hangouts = { plot id -> hangout }, loaded = { plot id -> saved record }, syncIn, sent }
-- A hangout: { plot, owner, level, fund, out = { slot -> guard }, wait = { slot -> seconds },
--              gap, threat = { kind = "player" | "officer", id, left } }
local sv = nil

function Gang:serverStart()
  sv = { guards = Guards.new(), hangouts = {}, loaded = {}, syncIn = 0, sent = 0 }
end

--- How many guards `h` has out.
local function outCount(h)
  local n = 0
  for slot = 1, Gang.guards do
    if h.out[slot] then
      n = n + 1
    end
  end
  return n
end

local function publish(server, h, to)
  local msg = Protocol.encode("GANG_STATE", h.plot, h.owner, h.level, h.fund, outCount(h))
  if to then
    server:send(to, msg)
  else
    server:broadcast(msg)
  end
end

--- A new hangout's record (or a saved one's, put back).
local function open(server, id, owner)
  local h = { plot = id, owner = owner, level = 1, fund = 0, out = {}, wait = {}, gap = 0 }
  local saved = sv.loaded[id]
  sv.loaded[id] = nil
  local plot = plotById(id)
  if saved and saved.owner == owner then
    h.level = Crews.at(saved.level).level
    h.fund = saved.fund
    for slot = 1, math.min(Gang.guards, saved.out) do -- already paid for: straight to their posts
      local post = postOf(plot, slot)
      local g = sv.guards:spawn(h, slot, Crews.at(h.level), post.x, post.y, post)
      g.mode = "post"
      h.out[slot] = g
    end
  end
  sv.hangouts[id] = h
  publish(server, h)
  return h
end

--- Hangout `id` is no more: its guards go with it.
local function close(server, id)
  local h = sv.hangouts[id]
  for slot = 1, Gang.guards do
    if h.out[slot] then
      sv.guards:remove(h.out[slot])
    end
  end
  sv.hangouts[id] = nil
  server:broadcast(Protocol.encode("GANG_GONE", id))
end

--- Set `h`'s crew on `kind` ("player" or "officer", a police officer on
--- foot) number `id`, who did `why`. A crew already after somebody else
--- finishes with them first.
local function setThreat(server, h, kind, id, why)
  local t = h.threat
  if t and not (t.kind == kind and t.id == id) and t.left > 0 then
    return
  end
  h.threat = { kind = kind, id = id, left = Gang.chase }
  local boss = server.players[h.owner]
  if not t and boss and not boss.bot and outCount(h) > 0 then
    server:send(boss, Protocol.encode("GANG_ALERT", kind == "player" and id or 0, why))
  end
end

--- Set `h`'s crew on `player`: their boss is never one.
local function threaten(server, h, player, why)
  if player and player.id ~= h.owner and player.body then
    setThreat(server, h, "player", player.id, why)
  end
end

--- Every hangout of player `owner`.
local function hangoutsOf(owner)
  local list = {}
  for _, h in pairs(sv.hangouts) do
    if h.owner == owner then
      list[#list + 1] = h
    end
  end
  return list
end

--- Where officer `id` stands, or nil once they are down or off duty.
local function officerAt(id)
  local police = Features.byName.police
  if police and police.serverOfficer then
    return police:serverOfficer(id)
  end
  return nil
end

--- Is the one crew `h` is after still worth going after: in the game and
--- up, or an officer still on duty?
local function threatAlive(server, h)
  local t = h.threat
  if t.kind == "officer" then
    return officerAt(t.id) ~= nil
  end
  local p = server.players[t.id]
  return p ~= nil and not (p.body and p.body.dead)
end

--- Where the one crew `h` is after is right now ({ x, y, car }), or nil: a
--- player must be in the world and in sight (a chicken loses them until it
--- shows again).
local function threatOf(server, h)
  local t = h.threat
  if not t then
    return nil
  elseif t.kind == "officer" then
    local x, y = officerAt(t.id)
    return x and { x = x, y = y } or nil
  end
  local p = server.players[t.id]
  if not p or not Features.present(p) or (p.body and p.body.dead) or not Features.visible(server, p) then
    return nil
  end
  local x, y, onFoot = Features.bodyPose(server, p)
  return x and { x = x, y = y, car = not onFoot and p.vehicle or nil } or nil
end

--- The hangouts in the world: one for every hangout building on a city
--- plot, none for anything else.
local function reconcile(server)
  local bld, re = buildings(), realEstate()
  local seen = {}
  for id in pairs(re.plots) do
    local b = bld:serverBuilding(id)
    if b and b.kind == "hangout" then
      seen[id] = true
      local h = sv.hangouts[id]
      if h and h.owner ~= b.owner then
        close(server, id)
        h = nil
      end
      h = h or open(server, id, b.owner)
      if b.hp <= 0 and h.fund > 0 then
        h.fund = 0 -- a ruin's contents are lost
        publish(server, h)
      end
      h.ruined = b.hp <= 0
    end
  end
  for id in pairs(sv.hangouts) do
    if not seen[id] then
      close(server, id)
    end
  end
end

--- Guards coming out to fill the empty posts, as long as the fund pays.
local function recruit(server, h, dt)
  h.gap = math.max(0, h.gap - dt)
  local crew = Crews.at(h.level)
  for slot = 1, Gang.guards do
    if not h.out[slot] then
      h.wait[slot] = math.max(0, (h.wait[slot] or 0) - dt)
      if h.wait[slot] <= 0 and h.gap <= 0 and not h.ruined and h.fund >= crew.spawn then
        local plot = plotById(h.plot)
        local x, y = doorOf(plot)
        h.fund = h.fund - crew.spawn
        h.out[slot] = sv.guards:spawn(h, slot, crew, x, y, postOf(plot, slot))
        h.gap = Gang.spawnGap
        publish(server, h)
      end
    end
  end
end

--- Who went down: everyone sees it, every feature hears it, and the post
--- waits for its replacement.
local function flush(server)
  for _, d in ipairs(sv.guards:drain()) do
    local g, h = d.guard, d.guard.hangout
    server:broadcast(Protocol.encode("GANG_DOWN", g.id, fmt(d.x), fmt(d.y), ("%.3f"):format(d.angle), d.cause or "-"))
    Features.call("serverKill", server, { kind = "gang", x = d.x, y = d.y, by = d.by, cause = d.cause })
    if h.out[g.slot] == g then
      h.out[g.slot] = nil
      h.wait[g.slot] = Gang.respawn
      if sv.hangouts[h.plot] == h then
        publish(server, h)
      end
    end
  end
end

--- What the walking grid has to be rebuilt for: the city's shape and the
--- buildings standing on it.
local function gridKey(map)
  local parts = { map.version or 0 }
  for _, s in ipairs(buildings():serverStanding()) do
    parts[#parts + 1] = s.id
  end
  return table.concat(parts, ",")
end

function Gang:serverStep(server, dt)
  local map = cityMap()
  if not (sv and map and buildings() and realEstate()) then
    return -- off the city the guards wait where they are
  end
  reconcile(server)
  for _, h in pairs(sv.hangouts) do
    if h.threat then
      h.threat.left = h.threat.left - dt
      if h.threat.left <= 0 or not threatAlive(server, h) then
        h.threat = nil
      end
    end
    recruit(server, h, dt)
  end
  local moving = false
  for _, g in ipairs(sv.guards.list) do
    if g.mode ~= "post" then
      moving = true
      break
    end
  end
  if moving then
    sv.guards:nav(map, gridKey(map))
  end
  sv.guards:step(server, dt, function(h)
    return threatOf(server, h)
  end, function(g, driver)
    threaten(server, g.hangout, server.players[driver], "crew")
  end)
  flush(server)

  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local parts = { server.tick }
  for _, g in ipairs(sv.guards.list) do
    parts[#parts + 1] = g.id
    parts[#parts + 1] = g.hangout.plot
    parts[#parts + 1] = fmt(g.x)
    parts[#parts + 1] = fmt(g.y)
    parts[#parts + 1] = ("%.2f"):format(g.facing)
    parts[#parts + 1] = g.level
    parts[#parts + 1] = fmt(math.max(1, g.hp))
    parts[#parts + 1] = WIRE[g.mode] or "p"
  end
  if #parts == 1 and sv.sent == 0 then
    return -- nobody out, and everyone knows it
  end
  sv.sent = #parts - 1
  local msg = Protocol.encode("GANG_UNITS", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Gang:serverPlayerJoined(server, player)
  if sv and not player.bot then
    for _, h in pairs(sv.hangouts) do
      publish(server, h, player)
    end
  end
end

--- The police officer on foot who most likely just shot whoever is at
--- (x, y): the nearest one within shooting range who is after `id` (anybody,
--- for nil). Their rounds name nobody, so this is the best there is.
local function shootingOfficer(id, x, y)
  local police = Features.byName.police
  if not (police and police.serverOfficersAfter) then
    return nil
  end
  local best, bestD2 = nil, Gang.copReach * Gang.copReach
  for _, o in ipairs(police:serverOfficersAfter(id)) do
    local d2 = (o.x - x) ^ 2 + (o.y - y) ^ 2
    if d2 <= bestD2 then
      best, bestD2 = o.id, d2
    end
  end
  return best
end

--- The boss was hurt (weapons' event): on the hangout's ground, the crew
--- goes after whoever did it, a police officer on foot too.
function Gang:serverPlayerDamaged(server, victim, attacker)
  if not (sv and attacker ~= victim and cityMap()) then
    return
  end
  local x, y = Features.bodyPose(server, victim)
  local officer = not attacker and x and shootingOfficer(victim.id, x, y)
  if not (attacker or officer) then
    return -- a fire, a bleed, a fall: nobody to go after
  end
  for _, h in ipairs(hangoutsOf(victim.id)) do
    local plot = plotById(h.plot)
    if x and plot and inZone(plot, x, y) then
      if attacker then
        threaten(server, h, attacker, "boss")
      else
        setThreat(server, h, "officer", officer, "police")
      end
    end
  end
end

--- A building of somebody's that `by` hurt: every crew of its owner's goes
--- after them. `hit(r)` says whether a building's ground `r` was reached.
local function buildingHit(server, by, hit)
  local attacker = by and by ~= 0 and server.players[by]
  if not (sv and attacker and cityMap() and buildings()) then
    return
  end
  for _, s in ipairs(buildings():serverStanding()) do
    if s.owner ~= by and hit(s) then
      for _, h in ipairs(hangoutsOf(s.owner)) do
        threaten(server, h, attacker, "building")
      end
    end
  end
end

function Gang:serverWallHit(server, x, y, _damage, by)
  buildingHit(server, by, function(r)
    return contains(r, x, y, 1)
  end)
end

function Gang:serverBlast(server, x, y, radius, _damage, by)
  buildingHit(server, by, function(r)
    local dx = math.max(r.x - x, 0, x - (r.x + r.w))
    local dy = math.max(r.y - y, 0, y - (r.y + r.h))
    return dx * dx + dy * dy <= radius * radius
  end)
end

--- A bullet passing through (x, y): the `serverShotAt` convention. A guard
--- there takes it, and his crew goes after whoever fired: a player, or a
--- police officer on foot (a round that belongs to nobody and isn't a gang's).
function Gang:serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  local g = sv and cityMap() and sv.guards:at(x, y, radius)
  if not g then
    return false
  end
  local h, gx, gy = g.hangout, g.x, g.y
  sv.guards:hurt(g, damage or Guards.SHOT_DAMAGE, by ~= 0 and by or nil, angle, dtype)
  if by and by ~= 0 then
    threaten(server, h, server.players[by], "crew")
  elseif not from then
    local officer = shootingOfficer(nil, gx, gy)
    if officer then
      setThreat(server, h, "officer", officer, "copcrew")
    end
  end
  flush(server)
  return true
end

function Gang:serverFreezeArea(_server, x, y, radius, seconds)
  if sv and cityMap() then
    sv.guards:freeze(x, y, radius, seconds)
  end
end

function Gang:serverPanicArea(_server, x, y, radius)
  if sv and cityMap() then
    sv.guards:scare(x, y, radius, 0.5)
  end
end

--- Cars on patrol stop for a guard on the move (the `serverWalkers` event).
function Gang:serverWalkers(_server, add)
  if not (sv and cityMap()) then
    return
  end
  for _, g in ipairs(sv.guards.list) do
    if g.mode ~= "post" then
      add(g.x, g.y)
    end
  end
end

--- The boss's hangout on plot `id`, if `player` is its boss standing on its
--- square; else nil and a reason.
local function myHangout(server, player, id)
  local h = sv and sv.hangouts[id or -1]
  local plot = plotById(id or -1)
  if not (h and plot and cityMap()) then
    return nil, "unknown"
  elseif h.owner ~= player.id then
    return nil, "notyours"
  end
  local x, y = Features.bodyPose(server, player)
  local bld = buildings()
  if not (x and Features.present(player) and bld and bld.onPad(plot, x, y, SLACK)) then
    return nil, "away"
  end
  return h
end

local function answering(handler)
  return function(server, player, args)
    local ok, why = handler(server, player, args)
    if ok then
      server:send(player, Protocol.encode("GANG_OK", ok))
    else
      server:send(player, Protocol.encode("GANG_NO", why or "unknown"))
    end
  end
end

Gang.serverMessages = {
  GANG_DEPOSIT = answering(function(server, player, args)
    local h, why = myHangout(server, player, tonumber(args[1]))
    local n = math.floor(tonumber(args[2]) or 0)
    if not h then
      return nil, why
    elseif h.ruined then
      return nil, "ruined"
    elseif n <= 0 or n > Gang.maxDeposit then
      return nil, "unknown"
    end
    local money = Features.byName.money
    if money then
      local paid, reason = money:spend(server, player.id, n, "hangout fund")
      if not paid then
        return nil, reason
      end
    end
    h.fund = h.fund + n
    publish(server, h)
    return "deposit"
  end),
  GANG_WITHDRAW = answering(function(server, player, args)
    local h, why = myHangout(server, player, tonumber(args[1]))
    if not h then
      return nil, why
    elseif h.fund <= 0 then
      return nil, "empty"
    end
    local money = Features.byName.money
    if money then
      money:give(server, player.id, h.fund)
    end
    h.fund = 0
    publish(server, h)
    return "withdraw"
  end),
  GANG_UPGRADE = answering(function(server, player, args)
    local h, why = myHangout(server, player, tonumber(args[1]))
    if not h then
      return nil, why
    elseif h.ruined then
      return nil, "ruined"
    elseif h.level >= Crews.MAX then
      return nil, "top"
    end
    local money = Features.byName.money
    if money then
      local paid, reason = money:spend(server, player.id, Crews.list[h.level + 1].upgrade, "hangout upgrade")
      if not paid then
        return nil, reason
      end
    end
    h.level = h.level + 1
    publish(server, h)
    return "upgrade"
  end),
}

--- Each hangout's level, fund and how many guards are out, by block (plot
--- numbers follow the order the city grew). Nothing while away on a quest:
--- the world isn't written then.
function Gang:serverSaveWorld()
  local re = realEstate()
  if not (sv and re and cityMap()) then
    return nil
  end
  local list = {}
  for id, h in pairs(sv.hangouts) do
    local plot = re.plots[id]
    if plot then
      list[#list + 1] = {
        bi = plot.block.bi, bj = plot.block.bj, owner = h.owner, level = h.level, fund = h.fund, out = outCount(h),
      }
    end
  end
  table.sort(list, function(a, b)
    return a.bi < b.bi or (a.bi == b.bi and a.bj < b.bj)
  end)
  return { version = SAVE_VERSION, hangouts = list }
end

local function integer(v)
  return type(v) == "number" and v == v and v == math.floor(v)
end

--- Saved hangouts wait for their building (buildings puts it back) and are
--- set up as it is found.
function Gang:serverLoadWorld(server, data)
  local re = realEstate()
  if not (sv and re and cityMap() and type(data) == "table" and type(data.hangouts) == "table") then
    return
  elseif (tonumber(data.version) or 1) > SAVE_VERSION then
    return
  end
  for _, rec in ipairs(data.hangouts) do
    if type(rec) == "table" and integer(rec.bi) and integer(rec.bj) and integer(rec.owner) then
      local plot = re.plotOnBlock(re.plots, rec.bi, rec.bj)
      if plot then
        sv.loaded[plot.id] = {
          owner = rec.owner,
          level = integer(rec.level) and rec.level or 1,
          fund = integer(rec.fund) and math.max(0, rec.fund) or 0,
          out = integer(rec.out) and math.max(0, rec.out) or 0,
        }
        if sv.hangouts[plot.id] then
          close(server, plot.id) -- opened fresh before the save came in: open it again as saved
        end
      end
    end
  end
end

--- For tests.
function Gang.server()
  return sv
end

-- Client --------------------------------------------------------------------

Gang.hangouts = {} -- plot id -> { owner, level, fund, out }
Gang.units = {} -- guard id -> { x, y, dx, dy, angle, level, hp, mode, owner, plot, bob }
Gang.notice = nil -- { text, color, t }
local time, lastTick = 0, 0

function Gang:exitGame()
  self.hangouts, self.units, self.notice = {}, {}, nil
  lastTick = 0
end

function Gang:mapChanged()
  self.units = {} -- they stay home; the host sends them again once we are back
  lastTick = 0
end

function Gang:say(text, color)
  self.notice = { text = text, color = color or RED, t = NOTICE_TIME }
end

function Gang:update(dt)
  time = time + dt
  local k = math.min(1, dt * SMOOTHING)
  for _, g in pairs(self.units) do
    local ex, ey = g.x - g.dx, g.y - g.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      g.dx, g.dy = g.x, g.y
    else
      g.dx, g.dy = g.dx + ex * k, g.dy + ey * k
    end
  end
  if self.notice then
    self.notice.t = self.notice.t - dt
    if self.notice.t <= 0 then
      self.notice = nil
    end
  end
end

--- A menu answer, where the building menu shows them.
local function tell(text, good)
  local bld = buildings()
  if bld and bld.notice then
    bld:notice(text, good)
  end
end

local function affordable(client, price)
  local money = Features.byName.money
  if money and money.canAfford and not money:canAfford(client, price) then
    tell(REASONS.broke)
    return false
  end
  return true
end

-- Buildings asks for these on a hangout's square (kinds.lua, `service`).

--- The menu rows on my hangout's square: pay into the fund, take it back,
--- upgrade the crew.
function Gang:buildingRows(client, plot, _b, row)
  local h = self.hangouts[plot.id] or { level = 1, fund = 0, out = 0 }
  local crew = Crews.at(h.level)
  local function deposit(n)
    return function()
      if affordable(client, n) then
        client:send(Protocol.encode("GANG_DEPOSIT", plot.id, n))
      end
    end
  end
  row(("Deposit %s  (one guard)"):format(amount(crew.spawn)), deposit(crew.spawn))
  row(("Deposit %s  (a full crew)"):format(amount(crew.spawn * Gang.guards)), deposit(crew.spawn * Gang.guards))
  row(("Take the fund back  (%s)"):format(amount(h.fund)), h.fund > 0 and function()
    client:send(Protocol.encode("GANG_WITHDRAW", plot.id))
  end or nil)
  local nextCrew = Crews.list[h.level + 1]
  if nextCrew then
    local label = ("Upgrade to %s with %ss  (%s)"):format(
      nextCrew.name:lower(), nextCrew.gunName, amount(nextCrew.upgrade))
    row(label, function()
      if affordable(client, nextCrew.upgrade) then
        client:send(Protocol.encode("GANG_UPGRADE", plot.id))
      end
    end)
  else
    row("Fully upgraded")
  end
end

--- The lines at the top of that menu.
function Gang:buildingInfo(client, plot, b)
  local h = self.hangouts[plot.id] or { level = 1, fund = 0, out = 0 }
  local crew = Crews.at(h.level)
  if b.owner ~= client.myId then
    local who = self:nameOf(client, b.owner)
    return { ("%s's crew: %d %s with %ss."):format(who, h.out, crew.name:lower(), crew.gunName) }
  end
  local lines = {
    ("Crew: %s with %ss, about %d damage a second each. Level %d of %d."):format(
      crew.name, crew.gunName, crew.dps, crew.level, Crews.MAX),
    ("On duty: %d of %d. Each new guard takes %s from the fund."):format(h.out, Gang.guards, amount(crew.spawn)),
  }
  if h.fund >= crew.spawn then
    lines[#lines + 1] = ("Fund: %s"):format(amount(h.fund))
  else
    lines[#lines + 1] = ("Fund: %s. Nobody new comes out until you deposit."):format(amount(h.fund))
  end
  lines[#lines + 1] = "They fight for your buildings, and for you on this block and the ones round it."
  return lines
end

function Gang:nameOf(client, id)
  local p = client.players[id]
  return p and p.name or "Somebody"
end

function Gang:drawBuilding(b, _kind, r, t)
  Render.building(r, b.owner, t or time)
end

--- The hangout's mark on the big map (buildings/render.lua asks).
function Gang:drawMapMark()
  Render.mark()
end

function Gang:drawBelowCars(_client, camera)
  local w, h = love.graphics.getDimensions()
  local scale = camera.scale or 1
  local halfW, halfH = w / (2 * scale) + 30, h / (2 * scale) + 30
  for _, g in pairs(self.units) do
    if math.abs(g.dx - camera.x) < halfW and math.abs(g.dy - camera.y) < halfH then
      Render.guard(g, time)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Gang:drawHUD()
  local n = self.notice
  if not n then
    return
  end
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(n.text, 1, h - 189, w, "center")
  love.graphics.setColor(n.color[1], n.color[2], n.color[3], math.min(1, n.t * 2))
  love.graphics.printf(n.text, 0, h - 190, w, "center")
  love.graphics.setColor(1, 1, 1)
end

Gang.clientMessages = {
  GANG_STATE = function(_client, args)
    local id = tonumber(args[1])
    if id then
      Gang.hangouts[id] = {
        owner = tonumber(args[2]), level = tonumber(args[3]) or 1, fund = tonumber(args[4]) or 0,
        out = tonumber(args[5]) or 0,
      }
    end
  end,
  GANG_GONE = function(_client, args)
    local id = tonumber(args[1])
    if id then
      Gang.hangouts[id] = nil
    end
  end,
  GANG_UNITS = function(_client, args)
    local tick = tonumber(args[1]) or 0
    if tick < lastTick then
      return -- an old packet, overtaken
    end
    lastTick = tick
    local seen = {}
    for i = 2, #args - 7, 8 do
      local id = tonumber(args[i])
      local plot = tonumber(args[i + 1])
      local x, y = tonumber(args[i + 2]), tonumber(args[i + 3])
      if id and x and y then
        seen[id] = true
        local g = Gang.units[id]
        if not g then
          g = { dx = x, dy = y, bob = love.math.random() * 6 }
          Gang.units[id] = g
        end
        local h = Gang.hangouts[plot or -1]
        g.x, g.y, g.plot, g.owner = x, y, plot, h and h.owner
        g.angle = tonumber(args[i + 4]) or 0
        g.level = tonumber(args[i + 5]) or 1
        g.hp = tonumber(args[i + 6]) or 1
        g.mode = MODES[args[i + 7]] or "post"
      end
    end
    for id in pairs(Gang.units) do
      if not seen[id] then
        Gang.units[id] = nil
      end
    end
  end,
  GANG_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if id then
      Gang.units[id] = nil
    end
    local damage = Features.byName.damage
    if x and y and damage and damage.deathAt then
      damage:deathAt(x, y, angle, args[5] ~= "-" and args[5] or nil)
    end
  end,
  GANG_ALERT = function(client, args)
    local why = WHY[args[2]] or WHY.building
    Gang:say(why:format(Gang:nameOf(client, tonumber(args[1]))), AMBER)
  end,
  GANG_OK = function(_client, args)
    tell(DONE[args[1]] or "Done.", true)
  end,
  GANG_NO = function(_client, args)
    tell(REASONS[args[1]] or REASONS.unknown)
  end,
}

return Gang
