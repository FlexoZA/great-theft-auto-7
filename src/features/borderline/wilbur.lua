-- Wilbur, the Bragium Pit's boss (docs/borderline.md, "The bosses"): how
-- he comes into the fight, and what everyone sees of it. What he does in
-- it is his brain's (wlb_brain.lua: he is one of the army, model WLB), how
-- he looks wilbur_look.lua's. init.lua passes its hooks on to this module.
--
-- The map says where (city-map's `map.boss` { kind = "wilbur", x, y, wake }):
-- the first player to walk into `wake` (the pit's floor) brings him down
-- out of the sky onto (x, y), the pad; a red ring shows where for `DROP`
-- seconds, then he lands, and whoever is in the ring is thrown flat. His
-- health is a boss's (Bosses.health: more humans, more; tougher on a job
-- done before). He carries the mine lift's code: down, he drops his keycard
-- where he falls, and the mine lift stays shut (`serverLocked`) until a
-- player walks over it and picks it up. He also leaves a plasma rifle for
-- every player, off to one side of the card, which unlocks it in the shop
-- (weapons/guns.lua's `unlock`), its tier rolled by Bosses.dropTier.
--
-- Every screen: the drop's ring and him falling into it, the ring where a
-- leap of his comes down, the shockwave of each slam, his plates glowing
-- once Max's upgrade is in, the boss bar, and his keycard lying where he
-- fell, glowing, until it is picked up.
--
-- Messages
--   server -> all  WLB_DROP <x> <y> <radius> <seconds>   he is coming down there
--   server -> all  WLB_LEAP <x> <y> <radius> <seconds>   a leap of his comes down there
--   server -> all  WLB_SLAM <x> <y> <radius>             he came down there
--   server -> all  WLB_UP                                Max's upgrade is in (to a joiner too)
--   server -> all  WLB_CARD <x> <y>                      he is down: his keycard lies there (to a joiner too)
--   server -> all  WLB_DOWN                              his keycard is picked up, the mine lift open (to a joiner too)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Tiers = require("src.features.tiers")
local Bar = require("src.features.bosses.bar")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Army = require("src.features.borderline.army")
local Brain = require("src.features.borderline.wlb_brain")
local Look = require("src.features.borderline.wilbur_look")

local Wilbur = {}

-- Tuning ------------------------------------------------------------------
Wilbur.DROP = 1.6 -- seconds the ring shows before he lands
Wilbur.DROP_HIT = 130 -- px: whoever he lands this near...
Wilbur.DROP_DAMAGE = 30 -- ...takes this (impact)...
Wilbur.DROP_SHOVE = 240 -- ...and goes flying
Wilbur.FALL = 520 -- px up he is drawn as he starts to fall
Wilbur.CARD_REACH = 60 -- px from his keycard that picks it up
Wilbur.GUN = "gun-plasma-rifle" -- his drop, one for every player (and unlocked)
Wilbur.GUN_AWAY = 110 -- px from his keycard it lands, so picking one up isn't the other

local RED = { 1, 0.2, 0.12 }
local TITLE = { 0.95, 0.76, 0.19 }
local FILL = { 0.9, 0.22, 0.15 }
local FILL_UP = { 1, 0.55, 0.15 }

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { spec, phase = "waiting" | "dropping" | "up" | "card" | "down", dropIn, s, upgraded, card }

--- A level starts on `map`: Wilbur waiting, if it has him.
function Wilbur.serverStart(map)
  local spec = map and map.boss
  sv = spec and spec.kind == "wilbur" and { spec = spec, phase = "waiting" } or nil
end

function Wilbur.serverStop()
  sv = nil
end

--- Open ground `Wilbur.GUN_AWAY` from (x, y) with nothing solid on the way
--- (the `blocksPoint` convention): the first of eight directions round it
--- that is clear, or right beside it if none is.
local function gunSpot(x, y)
  local d = Wilbur.GUN_AWAY
  for dir = 0, 7 do
    local a = dir * math.pi / 4
    local clear = true
    for k = 1, 8 do
      if Features.any("blocksPoint", x + math.cos(a) * d * k / 8, y + math.sin(a) * d * k / 8) then
        clear = false
        break
      end
    end
    if clear then
      return x + math.cos(a) * d, y + math.sin(a) * d
    end
  end
  return x + 48, y
end

--- His plasma rifle, a common one or better (Bosses.dropTier), for everyone.
local function dropGun(server, x, y)
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDrop then
    local gx, gy = gunSpot(x, y)
    pickups:serverDrop(server, Tiers.join(Wilbur.GUN, Bosses.dropTier()), gx, gy, nil, { perPlayer = true })
  end
end

--- Is the way on still shut (he hasn't come, or is still up)?
function Wilbur.serverLocked()
  return sv ~= nil and sv.phase ~= "down"
end

local function inBox(b, x, y)
  return x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1
end

local function drop(server, beat)
  local spec = sv.spec
  sv.phase, sv.dropIn = "dropping", Wilbur.DROP
  server:broadcast(Protocol.encode("WLB_DROP", fmt(spec.x), fmt(spec.y), Wilbur.DROP_HIT, Wilbur.DROP))
  beat("wilbur")
end

local function land(server)
  local spec = sv.spec
  local s = Army.serverSpawn("WLB", spec.x, spec.y, math.pi / 2) -- facing the way everyone comes in
  if not s then
    sv.phase = "down" -- no army on: nothing to hold the lift
    return
  end
  s.hp = Bosses.health(Brain.HEALTH, server)
  s.max = s.hp
  sv.s, sv.phase = s, "up"
  Brain.slam(server, spec.x, spec.y, Wilbur.DROP_HIT, Wilbur.DROP_DAMAGE * Bosses.power(), Wilbur.DROP_SHOVE)
  server:broadcast(Protocol.encode("WLB_SLAM", fmt(spec.x), fmt(spec.y), Wilbur.DROP_HIT))
end

--- What his brain left for everyone to hear about.
local function tell(server, s, beat)
  for _, e in ipairs(s.events) do
    if e[1] == "leap" then
      server:broadcast(Protocol.encode("WLB_LEAP", fmt(e[2]), fmt(e[3]), e[4], ("%.2f"):format(e[5])))
    elseif e[1] == "slam" then
      server:broadcast(Protocol.encode("WLB_SLAM", fmt(e[2]), fmt(e[3]), e[4]))
    elseif e[1] == "upgrade" then
      sv.upgraded = true
      server:broadcast(Protocol.encode("WLB_UP"))
      beat("upgrade")
    end
  end
  s.events = {}
end

--- `beat(what)` raises a story beat: "wilbur" as he comes, "upgrade",
--- "wilbur-down", "keycard" when his card is picked up.
function Wilbur.serverStep(server, dt, beat)
  if not sv then
    return
  end
  if sv.phase == "waiting" then
    for _, p in pairs(server.players) do
      if not p.bot and Features.present(p) and inBox(sv.spec.wake, Features.bodyPose(server, p)) then
        drop(server, beat)
        break
      end
    end
  elseif sv.phase == "dropping" then
    sv.dropIn = sv.dropIn - dt
    if sv.dropIn <= 0 then
      land(server)
    end
  elseif sv.phase == "up" then
    tell(server, sv.s, beat)
    if sv.s.dead then
      sv.phase, sv.card = "card", { x = sv.s.x, y = sv.s.y }
      server:broadcast(Protocol.encode("WLB_CARD", fmt(sv.card.x), fmt(sv.card.y)))
      dropGun(server, sv.card.x, sv.card.y)
      beat("wilbur-down")
    end
  elseif sv.phase == "card" then
    for _, p in pairs(server.players) do
      if not p.bot and Features.present(p) then
        local x, y = Features.bodyPose(server, p)
        if (x - sv.card.x) ^ 2 + (y - sv.card.y) ^ 2 <= Wilbur.CARD_REACH ^ 2 then
          sv.phase = "down"
          server:broadcast(Protocol.encode("WLB_DOWN"))
          beat("keycard")
          break
        end
      end
    end
  end
end

function Wilbur.serverPlayerJoined(server, player)
  if sv and sv.upgraded then
    server:send(player, Protocol.encode("WLB_UP"))
  end
  if sv and sv.phase == "card" then
    server:send(player, Protocol.encode("WLB_CARD", fmt(sv.card.x), fmt(sv.card.y)))
  elseif sv and sv.phase == "down" then
    server:send(player, Protocol.encode("WLB_DOWN"))
  end
end

--- The launch's --boss: `player` straight to the pit's floor, and him down
--- onto the pad. True when there is a Wilbur to skip to.
function Wilbur.serverSkipTo(server, player, beat)
  if not (sv and sv.phase == "waiting") then
    return false
  end
  local spec = sv.spec
  if player and player.body then
    player.body.x, player.body.y = spec.x, spec.y + 420
  end
  drop(server, beat)
  return true
end

--- The wiki's page on him (tools/wiki, docs/wiki.md).
function Wilbur.wikiEnemies(add)
  local Heal = require("src.features.bosses.heal")
  local B, V, L, D = Brain, Brain.VOLLEY, Brain.LEAP, Brain.DRONES
  add({
    kind = "borderline/wlb",
    name = "Wilbur",
    quests = { "borderline-pit" },
    boss = true,
    where = "The Bragium Pit: he comes down onto the pad when you first set foot on the pit's floor (open once "
      .. "the four power terminals are hacked), and the mine lift stays shut until his keycard is picked up",
    about = "Maximum Maximilian Max's cyborg enforcer, more machine than man: a rotary gun for a right arm, a "
      .. "steel fist for a left, a rocket pod on his shoulder, and drones out of his back that keep him going.",
    stats = {
      { "Health", B.HEALTH },
      { "Speed", ("%g px/s, %g upgraded, %g winded"):format(B.CONF.speed, B.UPGRADED.speed, B.CONF.walk) },
      { "Sight", B.CONF.range, "px" },
    },
    weapons = {
      { "Rotary gun", ("bursts of %d, %g bullet damage each"):format(B.CONF.burst, B.gun().damage) },
      { "Rocket pod", ("the pod glows for %g s, then %d rockets come down on red rings round you, %g explosive "
        .. "damage each; every %g to %g s (%g to %g upgraded)"):format(V.windUp, V.count, V.damage, V.every[1],
        V.every[2], V.everyUp[1], V.everyUp[2]) },
      { "Leap", ("at anyone %g px or more off: he crouches for %g s (a red ring where he'll land), is out of reach "
        .. "in the air for %g s, and slams down: %g impact damage within %g px, thrown %g px; at most every %g s")
        :format(L.min, L.windUp, L.air, L.damage, L.hit, L.shove, L.every) },
    },
    abilities = {
      ("Every %g s (%g upgraded) a drone out of his back, a shield drone and a medic drone by turns, %d of his own "
        .. "out at most (%d upgraded): they heal him and shield him."):format(D.every, D.everyUp, D.cap, D.capUp),
      ("At %g%% of his health Max pushes an upgrade: quicker, sooner on the trigger, drones twice as often.")
        :format(B.UPGRADE * 100),
      ("Under %g%% health he goes for the nearest medkit within %g px, for %g health."):format(Heal.below * 100,
        Heal.range, Heal.amount),
      ("Coming down onto the pad, he throws everyone within %g px flat."):format(Wilbur.DROP_HIT),
    },
    tips = {
      "Shoot his drones first: the medic heals him, the shield drone keeps a bubble on him.",
      "Get out of the red ring when he crouches; he comes up slow from a leap.",
      "Keep him running and he's winded: no leaps, no rockets.",
    },
    drops = "40 koins, a pickup, his keycard, and a plasma rifle for every player (unlocking it)",
  })
end

--- For tests.
function Wilbur.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = { falling = nil, rings = {}, waves = {}, started = false, down = false, card = nil }
local clock = 0
local bank = {}

function Wilbur.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(300, 2600)
    return src
  end
  -- Coming down: a falling whistle.
  bank.fall = make(1.6, 0.6, function(buf)
    buf:sweep(0, 1.55, 1400, 300, { wave = "sine", amp = 0.25, attack = 0.2, decay = 1.3 })
    buf:noiseBurst(0.6, 0.9, { amp = 0.2, attack = 0.6, decay = 0.2 })
    buf:lowpass(3000)
  end)
  -- A slam: a deep boom and the ground ringing.
  bank.slam = make(0.9, 0.9, function(buf)
    buf:kick(0, 1)
    buf:sweep(0, 0.8, 90, 30, { wave = "sine", amp = 0.9, decay = 0.4 })
    buf:noiseBurst(0, 0.5, { amp = 0.7, decay = 0.15 })
    buf:lowpass(1600)
  end)
  -- The upgrade: a servo whine winding up.
  bank.upgrade = make(1.2, 0.6, function(buf)
    buf:sweep(0, 1.1, 220, 1100, { wave = "saw", amp = 0.25, attack = 0.05, decay = 0.3, vibRate = 14,
      vibDepth = 20 })
    buf:lowpass(2600)
  end)
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    if x then
      s:setPosition(x, 0, y)
    else
      s:setRelative(true)
    end
    s:setVolume(0.8 * Audio.volume("weapons"))
    s:play()
  end
end

function Wilbur.clear()
  cl = { falling = nil, rings = {}, waves = {}, started = false, down = false, card = nil }
  Look.upgraded = false
end

function Wilbur.update(dt)
  clock = clock + dt
  if cl.falling then
    cl.falling.t = cl.falling.t + dt
    if cl.falling.t >= cl.falling.total then
      cl.falling = nil
    end
  end
  for i = #cl.rings, 1, -1 do
    local r = cl.rings[i]
    r.t = r.t + dt
    if r.t >= r.total then
      table.remove(cl.rings, i)
    end
  end
  for i = #cl.waves, 1, -1 do
    cl.waves[i].t = cl.waves[i].t + dt
    if cl.waves[i].t >= 0.6 then
      table.remove(cl.waves, i)
    end
  end
end

--- What the objective line should be after on `map` now: "pad" (get down
--- to where he'll come) and where, "fight" while he is coming or up,
--- "card" (his keycard to pick up) and where, or nil (no Wilbur here, or
--- his card is picked up).
function Wilbur.objective(map)
  local spec = map and map.boss
  if not (spec and spec.kind == "wilbur") or cl.down then
    return nil
  end
  if cl.card then
    return "card", cl.card.x, cl.card.y
  end
  if cl.started or Army.shownOf("WLB") then
    return "fight"
  end
  return "pad", spec.x, spec.y
end

--- The rings where he'll come down, and the shockwaves, on the ground.
function Wilbur.drawBelowCars()
  local function ring(r, k)
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.1 + 0.2 * k)
    love.graphics.circle("fill", r.x, r.y, r.r * k, 40)
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.5 + 0.4 * math.sin(clock * (8 + 20 * k)))
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", r.x, r.y, r.r, 40)
    love.graphics.setLineWidth(1)
  end
  if cl.falling then
    ring(cl.falling, cl.falling.t / cl.falling.total)
  end
  for _, r in ipairs(cl.rings) do
    ring(r, r.t / r.total)
  end
  for _, w in ipairs(cl.waves) do
    local k = w.t / 0.6
    love.graphics.setColor(0.85, 0.75, 0.6, 0.6 * (1 - k))
    love.graphics.setLineWidth(5 * (1 - k) + 1)
    love.graphics.circle("line", w.x, w.y, w.r * (0.3 + 1.1 * k), 48)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- His keycard lying where he fell: Hyperbole yellow, a magnetic stripe and
--- an H on it, bobbing, a light round it pulsing to catch the eye.
local function drawCard(c)
  local bob = math.sin(clock * 3) * 3
  local k = 0.5 + 0.5 * math.sin(clock * 4)
  love.graphics.setColor(TITLE[1], TITLE[2], TITLE[3], 0.15 + 0.2 * k)
  love.graphics.circle("fill", c.x, c.y, 34 + 8 * k, 28)
  love.graphics.setColor(TITLE[1], TITLE[2], TITLE[3], 0.6 + 0.3 * k)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", c.x, c.y, 30 + 10 * k, 28)
  love.graphics.setLineWidth(1)
  love.graphics.push()
  love.graphics.translate(c.x, c.y + bob)
  love.graphics.rotate(math.sin(clock * 1.3) * 0.25)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", -12, -6 + 10 - bob, 26, 18, 3)
  love.graphics.setColor(0.07, 0.07, 0.09)
  love.graphics.rectangle("fill", -15, -10, 30, 20, 4)
  love.graphics.setColor(TITLE)
  love.graphics.rectangle("fill", -13, -8, 26, 16, 3)
  love.graphics.setColor(0.07, 0.07, 0.09)
  love.graphics.rectangle("fill", -13, -4, 26, 4) -- the stripe
  love.graphics.rectangle("fill", 2, 2, 2, 5) -- the H
  love.graphics.rectangle("fill", 8, 2, 2, 5)
  love.graphics.rectangle("fill", 4, 4, 4, 1)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Him coming down out of the sky onto the pad, over everyone; his keycard
--- once he is down.
function Wilbur.drawAboveCars()
  if cl.card then
    drawCard(cl.card)
  end
  local f = cl.falling
  if not f then
    return
  end
  local k = f.t / f.total
  love.graphics.setColor(0, 0, 0, 0.15 + 0.3 * k) -- his shadow, growing as he comes
  love.graphics.ellipse("fill", f.x, f.y, 34 * (0.4 + 0.6 * k), 30 * (0.4 + 0.6 * k), 24)
  Look.draw({ dx = f.x, dy = f.y - Wilbur.FALL * (1 - k) ^ 2, facing = math.pi / 2, flying = true, charge = 1 },
    clock)
end

--- His bar, while he is up.
function Wilbur.drawHUD()
  local s = not cl.down and Army.shownOf("WLB")
  if s then
    Bar.draw({
      title = "WILBUR", titleColor = TITLE, fill = Look.upgraded and FILL_UP or FILL, hp = s.hp, max = s.max,
      stamina = s.breath, staminaMax = 100, winded = s.winded, harder = "MORE UPGRADED",
    })
  end
end

Wilbur.clientMessages = {
  WLB_DROP = function(_client, args)
    local x, y, r, t = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and r and t and t > 0 then
      cl.falling, cl.started = { x = x, y = y, r = r, t = 0, total = t }, true
      play("fall", x, y)
    end
  end,
  WLB_LEAP = function(_client, args)
    local x, y, r, t = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and r and t and t > 0 then
      cl.rings[#cl.rings + 1] = { x = x, y = y, r = r, t = 0, total = t }
    end
  end,
  WLB_SLAM = function(_client, args)
    local x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y and r then
      cl.waves[#cl.waves + 1] = { x = x, y = y, r = r, t = 0 }
      cl.falling, cl.started = nil, true
      play("slam", x, y)
    end
  end,
  WLB_UP = function()
    if not Look.upgraded then
      Look.upgraded = true
      play("upgrade")
    end
  end,
  WLB_CARD = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      cl.card, cl.started = { x = x, y = y }, true
    end
  end,
  WLB_DOWN = function()
    cl.down, cl.started, cl.card = true, true, nil
  end,
}

return Wilbur
