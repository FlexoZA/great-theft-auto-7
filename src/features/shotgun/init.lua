-- Shotgun: the fourth boss quest. Everyone arrives at the bottom right of
-- Shotgun's Bluff (city-map's "cliff"): a meadow under a long cliff with
-- a plateau on top, and the only way up a ramp at the far left. Shotgun is
-- up there with a sniper rifle, and the cliff stops every round fired up
-- at him, so the way to him is up the map and to the left, from one clump
-- of cover to the next across the open grass he looks down on.
--
-- He hides and shoots (boss.lua): out of sight as soon as he can be (the
-- chicken, the same ability a player can buy, on his own numbers), off to
-- a new spot while hidden, then back into sight, a bead on the nearest
-- player he can see, and a round a second later. The bead shows on every
-- screen (a laser from his rifle, a ring closing on the target) and the
-- target's screen throbs red, so they can dodge or get behind something.
-- Get close and he vanishes again, or, when he can't, backs off firing
-- his pistol (he would rather use it anyway).
--
-- On arrival his portrait comes up on every screen and the world holds
-- still for it; then the hunt. When he goes down he spills koins and his
-- chicken (an "ability-chicken" orb), the quest is done, and quests puts
-- an EXIT star home where he fell.
--
-- The quests feature brings everyone to the bluff and raises
-- `serverQuestStarted` / `questStarted` for the quest whose `boss` is
-- "shotgun". The host owns all of it; clients hear the stage reliably and
-- where he is at 15 Hz, and draw. Bullets reach him through `serverShotAt`
-- (with the round's own damage, so a sniper round hurts like one); his own
-- rounds (owner 0) fly through him.
--
-- Messages
--   server -> all  SG_STAGE <stage> <line>        none | reveal | hunt | done (line: the portrait's
--                                                 speech, Boss.lines[line], for reveal)
--   server -> all  SG_BOSS  <tick> <x> <y> <facing> <hp> <max> <hidden> <stamina> <winded>
--                                                 (unreliable, 15 Hz; hidden 1 while out of sight)
--   server -> all  SG_HIDE  <x> <y> <0|1>         he vanished (1) or came back (0) there: feathers
--   server -> all  SG_AIM   <playerId> <seconds>  a bead on that player; the round comes in `seconds`
--   server -> all  SG_AIM_OFF                     the bead is off (he lost them, or vanished)
--   server -> all  SG_SAY   <line>                he says Boss.lines[line]
--   server -> all  SG_RELOAD <x> <y>              five rounds gone: a long reload
--   server -> all  SG_DOWN  <x> <y> <angle>       he went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Boss = require("src.features.shotgun.boss")
local Face = require("src.features.shotgun.face")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Render = require("src.features.shotgun.render")
local Sounds = require("src.features.shotgun.sounds")

local Shotgun = {
  name = "shotgun",
  priority = 992, -- the portrait goes over every other HUD, the ability row (990) too; under the inventory (995)
}

-- Tuning ------------------------------------------------------------------
Shotgun.questId = "shotgun"
Shotgun.revealTime = 7 -- seconds of portrait before the hunt
Shotgun.bulletDamage = 20 -- what a round takes off him when it doesn't say (a pistol's)

local SYNC_EVERY = 2 -- server ticks between SG_BOSS packets
local SMOOTHING = 10 -- per second, the easing of what is drawn
local SNAP = 150 -- px; a jump this big is a teleport, not a step

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

--- The map in play, if it is the bluff.
local function cliffMap()
  local city = Features.byName["city-map"]
  local map = city and city.map
  return map and map.kind == "cliff" and map or nil
end

-- Server --------------------------------------------------------------------

local sv = nil -- { stage, boss, revealT, syncIn }

function Shotgun:serverStart()
  sv = { stage = nil }
end

local function setStage(server, stage, line)
  sv.stage = stage
  server:broadcast(Protocol.encode("SG_STAGE", stage, line or 0))
end

--- The lip spot nearest above where everyone arrives: he is the first
--- thing they see, and out of range of them for now.
local function startPerch(map)
  local best, bestD
  for _, p in ipairs(map.perches) do
    if p.edge then
      local d = math.abs(p.x - map.cx)
      if not bestD or d < bestD then
        best, bestD = p, d
      end
    end
  end
  return best or { x = 0, y = map.cliffY - 60 }
end

--- The quests feature took everyone to the bluff: he takes his spot and
--- says his piece.
function Shotgun:serverQuestStarted(server, quest)
  local map = cliffMap()
  if not (sv and quest.boss == self.questId and map) then
    return
  end
  local perch = startPerch(map)
  sv.boss = Boss.new(perch.x, perch.y, Bosses.health(Boss.HEALTH, server))
  sv.revealT, sv.syncIn = self.revealTime, 0
  setStage(server, "reveal", random(#Boss.lines))
end

--- Everyone off the bluff: nothing left to draw on any screen.
function Shotgun:stop(server)
  if sv and sv.stage then
    sv.stage, sv.boss = nil, nil
    server:broadcast(Protocol.encode("SG_STAGE", "none", 0))
  end
end

function Shotgun:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    self:stop(server)
  end
end

--- A map change of any kind ends it; the quest starts it again.
function Shotgun:mapChanged(_map, server)
  if server then
    self:stop(server)
  end
end

--- Someone joining mid-fight hears the stage; he comes with the sync.
function Shotgun:serverPlayerJoined(server, player)
  if sv and sv.stage and server.started and not player.bot then
    server:send(player, Protocol.encode("SG_STAGE", sv.stage, 0))
  end
end

--- Something froze the world around (x, y): him too, if he is in it.
function Shotgun:serverFreezeArea(_server, x, y, radius, seconds)
  local b = sv and sv.boss
  if b and b:hitBy(x, y, radius) then
    b.frozen = math.max(b.frozen, seconds)
  end
end

--- Something stinks at (x, y): he runs from it for a moment.
function Shotgun:serverPanicArea(_server, x, y, radius)
  local b = sv and sv.boss
  if b and b:hitBy(x, y, radius) then
    b.panic = { x = x, y = y, left = 0.5 }
  end
end

function Shotgun:serverStep(server, dt)
  if not (sv and sv.stage and sv.boss) then
    return
  end
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn < 0 then
    sv.syncIn = SYNC_EVERY - 1
  end
  local b = sv.boss
  if sv.stage == "reveal" then
    sv.revealT = sv.revealT - dt
    if sv.revealT <= 0 then
      setStage(server, "hunt")
    end
  elseif sv.stage == "hunt" then
    for _, e in ipairs(b:update(server, dt)) do
      if e[1] == "say" then
        server:broadcast(Protocol.encode("SG_SAY", e[2]))
      elseif e[1] == "hide" or e[1] == "show" then
        server:broadcast(Protocol.encode("SG_HIDE", fmt(e[2]), fmt(e[3]), e[1] == "hide" and 1 or 0))
      elseif e[1] == "aim" then
        server:broadcast(Protocol.encode("SG_AIM", e[2], ("%.2f"):format(e[3])))
      elseif e[1] == "aimoff" then
        server:broadcast(Protocol.encode("SG_AIM_OFF"))
      elseif e[1] == "reload" then
        server:broadcast(Protocol.encode("SG_RELOAD", fmt(b.x), fmt(b.y)))
      end
    end
  end
  if sv.syncIn == 0 and sv.boss then
    self:sync(server)
  end
end

--- Where he is, to everyone, unreliably.
function Shotgun:sync(server)
  local b = sv.boss
  server:broadcast(Protocol.encode("SG_BOSS", server.tick, fmt(b.x), fmt(b.y), ("%.2f"):format(b.facing),
    math.max(0, math.floor(b.hp)), b.max, b:hidden() and 1 or 0, b.breath:wire()), true)
end

--- Take `amount` off him. Returns true if that finished him.
function Shotgun:hurt(server, amount, by, angle)
  local b = sv.boss
  b.hp = b.hp - amount
  if b.hp > 0 then
    return false
  end
  local x, y = b.x, b.y
  sv.boss = nil
  server:broadcast(Protocol.encode("SG_DOWN", fmt(x), fmt(y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, Boss.DROPS)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDrop then
    pickups:serverDrop(server, "ability-chicken", x + 30, y)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  setStage(server, "done")
  local quests = Features.byName.quests
  if quests and quests.serverComplete then
    quests:serverComplete(server, self.questId, x, y) -- an EXIT star home where he fell
  end
  return true
end

--- A bullet passing through (x, y): the `serverShotAt` convention. His
--- own rounds (owner 0) pass through him; he can only be hurt once the
--- hunt is on, out of sight or not.
function Shotgun:serverShotAt(server, x, y, radius, by, angle, damage)
  local b = sv and sv.boss
  if not b or by == 0 or sv.stage ~= "hunt" or not b:hitBy(x, y, radius) then
    return false
  end
  self:hurt(server, damage or self.bulletDamage, by, angle)
  return true
end

--- For tests.
function Shotgun.server()
  return sv
end

-- Client --------------------------------------------------------------------

Shotgun.stage = nil -- the stage, from the host
Shotgun.boss = nil -- { x, y, dx, dy, angle, hp, max, shown, stamina, winded, say, sayTimer, bob }
Shotgun.aim = nil -- { target, t, total }: the bead he has on somebody
Shotgun.puffs = {} -- { x, y, t, seed }: feathers where he vanished or came back
Shotgun.stains = {} -- { x, y, angle }
Shotgun.page = nil -- { line, t } while his portrait is up
local face = nil
local time, lastTick = 0, 0

local function clear()
  Shotgun.stage, Shotgun.boss, Shotgun.aim, Shotgun.page = nil, nil, nil, nil
  Shotgun.puffs, Shotgun.stains = {}, {}
end

function Shotgun:load()
  Sounds.load()
end

function Shotgun:exitGame()
  clear()
  lastTick = 0
end

function Shotgun:questStarted(_client, quest)
  if quest.boss == self.questId then
    face = face or Face.new()
    clear()
  end
end

function Shotgun:questEnded(_client, quest)
  if quest.boss == self.questId then
    clear()
  end
end

function Shotgun:update(dt)
  time = time + dt
  if self.page then
    face:update(dt)
    self.page.t = self.page.t - dt
    if self.page.t <= 0 then
      self.page = nil
    end
  end
  local b = self.boss
  if b then
    local ex, ey = b.x - b.dx, b.y - b.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      b.dx, b.dy = b.x, b.y
    else
      local k = math.min(1, dt * SMOOTHING)
      b.dx, b.dy = b.dx + ex * k, b.dy + ey * k
    end
    b.sayTimer = math.max(0, b.sayTimer - dt)
  end
  if self.aim then
    self.aim.t = self.aim.t - dt
    if self.aim.t < -0.3 then
      self.aim = nil -- the shot has gone
    end
  end
  for i = #self.puffs, 1, -1 do
    local p = self.puffs[i]
    p.t = p.t + dt
    if p.t > 1 then
      table.remove(self.puffs, i)
    end
  end
end

--- His portrait softens the world behind it.
function Shotgun:worldBlur()
  return self.page and 1 or 0
end

function Shotgun:drawBelowCars()
  if self.stage then
    Render.below(self)
  end
end

function Shotgun:drawAboveCars(client)
  if self.stage then
    Render.above(self, function(id)
      return client:pose(id)
    end, time)
  end
end

function Shotgun:drawHUD(client)
  if not self.stage then
    return
  end
  local map = cliffMap()
  local _, y = client:myPose()
  Render.hud(self, face, client.myId, map and y and y < map.cliffY, time)
end

Shotgun.clientMessages = {
  SG_STAGE = function(client, args)
    local stage, line = args[1], tonumber(args[2]) or 0
    if stage == "none" then
      clear()
      return
    end
    if stage == "reveal" and Shotgun.stage ~= "reveal" and Boss.lines[line] then
      face = face or Face.new()
      Shotgun.page = { line = Boss.lines[line], t = Shotgun.revealTime }
      local x, y = client:myPose()
      Sounds.play("gavel", x or 0, y or 0) -- in everyone's ear, wherever he is
    end
    if stage ~= "hunt" then
      Shotgun.aim = nil
    end
    Shotgun.stage = stage
  end,
  SG_BOSS = function(_client, args)
    local tick = tonumber(args[1])
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (tick and x and y) or tick <= lastTick then
      return
    end
    lastTick = tick
    local b = Shotgun.boss
    if not b then
      b = { dx = x, dy = y, bob = random() * 6, sayTimer = 0 }
      Shotgun.boss = b
    end
    b.x, b.y = x, y
    b.angle = tonumber(args[4]) or b.angle or math.pi / 2
    b.hp = tonumber(args[5]) or b.hp or Boss.HEALTH
    b.max = tonumber(args[6]) or b.max or Boss.HEALTH
    b.shown = args[7] ~= "1"
    local stamina, winded = Stamina.read(args, 8)
    b.stamina, b.winded = stamina or b.stamina, winded
  end,
  SG_HIDE = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not (x and y) then
      return
    end
    Shotgun.puffs[#Shotgun.puffs + 1] = { x = x, y = y, t = 0, seed = random() * 6 }
    local b = Shotgun.boss
    if b then
      b.shown = args[3] ~= "1"
      b.x, b.y, b.dx, b.dy = x, y, x, y -- no easing across a vanish
      if not b.shown then
        b.sayTimer = 0
      end
    end
    local Abl = Features.byName.abilities and require("src.features.abilities.sounds")
    if Abl then
      Abl.play("chicken", x, y, 0.8) -- lower than a player's: a bigger chicken
    end
  end,
  SG_AIM = function(client, args)
    local id, seconds = tonumber(args[1]), tonumber(args[2])
    if id and seconds then
      Shotgun.aim = { target = id, t = seconds, total = seconds }
      if id == client.myId then
        local x, y = client:myPose()
        Sounds.play("lock", x or 0, y or 0)
      end
    end
  end,
  SG_AIM_OFF = function()
    Shotgun.aim = nil
  end,
  SG_SAY = function(_client, args)
    local b, line = Shotgun.boss, Boss.lines[tonumber(args[1]) or 0]
    if b and line and b.shown then
      b.say, b.sayTimer = line, 3.6
    end
  end,
  SG_RELOAD = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y and Features.byName.weapons then
      require("src.features.weapons.sounds").play("reload-sniper", x, y)
    end
  end,
  SG_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    Shotgun.boss, Shotgun.aim = nil, nil
    if x and y then
      Shotgun.stains[#Shotgun.stains + 1] = { x = x, y = y, angle = angle }
      if Features.byName.pedestrians then
        require("src.features.pedestrians.gibs").splat(x, y, angle)
      end
    end
  end,
}

return Shotgun
