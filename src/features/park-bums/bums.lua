-- The bums on the host. init.lua drives them from serverStep and owns the
-- wire.
--
-- Every park in the city has one, on one of its benches (`Bums.homes`,
-- worked out from the map, so clients know the benches without being told).
-- He sits there muttering until somebody standing next to him pays him to
-- go after another player or a bot. Then he gets up and goes for them: a
-- straight run when he can see them, round the blocks along a walking grid
-- (d-day's nav.lua) when he can't. In reach he punches them (melee) and
-- every punch leaves them bleeding harder than a plain melee hit does,
-- shouting abuse all the while. When they go down, leave, or he has been at
-- it `JOB_SECONDS`, he walks back to his bench. While they are out of sight
-- (the chicken) he stands and yells for them.
--
-- He can be shot (`HEALTH`), frozen, farted at and hit by cars (harder the
-- faster they go, so traffic knocks him about and a ramming finishes him);
-- put down, a new one is on the bench `RESPAWN_SECONDS` later. A job dies
-- with him. What he does is nobody's doing: the hirer gets no kill, and no
-- grudge from the bots or the police either. His first punch of a job has
-- the target cry out (`Lines.stabbed`), and a moment later a cop who can
-- see them answers (`Lines.cop`, police's `serverRemark`) and does nothing
-- about it. A bot he punches fights him off (bots' `fightOff`): it drives
-- at him and shoots, and shooting is a crime like any other, so a cop who
-- sees that goes after the bot (or the player) who fired.

local Features = require("src.features")
local Car = require("src.car")
local Lines = require("src.features.park-bums.lines")
local hasNav, Nav = pcall(require, "src.features.d-day.nav")

local Bums = {}
Bums.__index = Bums

-- Tuning --------------------------------------------------------------------

Bums.PRICE = 1000 -- Fcks to hire one
Bums.TALK_REACH = 60 -- px from a bum on his bench you must stand, on foot, to hire him
Bums.RADIUS = 9 -- px; a person's size (drawn as one: src/body.lua)
Bums.HEALTH = 200 -- ten pistol rounds
Bums.SHOT_DAMAGE = 20 -- what a round takes off when it doesn't say (a blast)
Bums.RUN_SPEED = 140 -- px/s after his target: past a walk, short of a sprint
Bums.WALK_SPEED = 50 -- px/s home again
Bums.REACH = 14 -- px past his body a punch lands
Bums.PUNCH_DAMAGE = 6 -- melee
Bums.PUNCH_INTERVAL = 1.0 -- seconds between punches
Bums.BLEED_SECONDS = 6 -- each punch leaves them bleeding this long...
Bums.BLEED_DPS = 5 -- ...at this much a second (a plain melee hit: 4 s at 3)
Bums.JOB_SECONDS = 75 -- he gives up after this long
Bums.HOME_SECONDS = 40 -- this long on the way home and he is just back on his bench
Bums.RESPAWN_SECONDS = 60 -- after one is put down, a new one on the bench
Bums.SHOUT_MIN = 2.5 -- seconds between insults on the job...
Bums.SHOUT_MAX = 4.5 -- ...up to here
Bums.MUTTER_MIN = 14 -- seconds between mutters on the bench...
Bums.MUTTER_MAX = 30 -- ...up to here
Bums.REPATH = 0.8 -- seconds between fresh paths while walking round things
Bums.COP_DELAY = 1.2 -- seconds after the target cries out before a cop answers
Bums.COP_RETRY = 1 -- seconds between looking for a cop to answer, while none has...
Bums.COP_WAIT = 10 -- ...for up to this long after the cry
Bums.CAR_DAMAGE = 0.3 -- health a car takes off him per px/s it hits him at...
Bums.CAR_MIN_SPEED = 60 -- ...when it is going at least this fast (slower only shoves him)
Bums.CAR_EVERY = 0.6 -- seconds before the same bum can be hit again

local random = love.math.random

--- Where each park's bum lives: { id, x, y, angle } (a bench, `angle` the
--- way he faces sitting on it), one per park in map order. The same list on
--- every machine.
function Bums.homes(map)
  local list = {}
  for _, b in ipairs(map and map.blocks or {}) do
    if b.kind == "park" and b.benches and #b.benches > 0 then
      local bench = b.benches[(b.bi + b.bj) % #b.benches + 1]
      list[#list + 1] = { id = #list + 1, x = bench.x, y = bench.y, angle = bench.angle }
    end
  end
  return list
end

-- Walking -------------------------------------------------------------------

local function blockedAt(x, y, r)
  r = r or Bums.RADIUS
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

--- One step, each axis on its own so a wall is slid along, and a note of
--- whether it got anywhere.
local function walk(b, angle, speed, dt)
  local px, py = b.x, b.y
  local nx = b.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, b.y) then
    b.x = nx
  end
  local ny = b.y + math.sin(angle) * speed * dt
  if not blockedAt(b.x, ny) then
    b.y = ny
  end
  b.moving = true
  if (b.x - px) ^ 2 + (b.y - py) ^ 2 < (speed * dt * 0.4) ^ 2 then
    b.stuck = b.stuck + dt
  else
    b.stuck = 0
  end
end

-- The bums ------------------------------------------------------------------

--- The bums for `map` (none on a map without parks).
function Bums.new(map)
  local self = setmetatable({ time = 0, list = {}, says = {}, downs = {}, cries = {}, answers = {}, map = map }, Bums)
  for _, home in ipairs(Bums.homes(map)) do
    local b = { id = home.id, home = home }
    self:seat(b)
    self.list[#self.list + 1] = b
  end
  return self
end

--- `b` on his bench, whole, with nothing to do.
function Bums:seat(b)
  local h = b.home
  b.x, b.y, b.facing = h.x, h.y, h.angle
  b.mode, b.hp = "sit", Bums.HEALTH
  b.target, b.path = nil, nil
  b.swing, b.stuck, b.sidestep, b.side = 0, 0, 0, 1
  b.frozen, b.panic, b.pathIn, b.lost, b.hitFor = 0, nil, 0, false, 0
  b.sayIn = Bums.MUTTER_MIN + random() * (Bums.MUTTER_MAX - Bums.MUTTER_MIN)
end

function Bums:byId(id)
  return self.list[id]
end

--- The walking grid, built the first time somebody needs one (it takes a
--- moment) and again when the city has changed shape.
function Bums:nav()
  local map = self.map
  if not (hasNav and map) then
    return nil
  end
  if not self.grid or self.gridVersion ~= map.version then
    self.grid = Nav.build({ x = map.left, y = map.top, w = map.w, h = map.h })
    self.gridVersion = map.version
  end
  return self.grid
end

--- Something to say: a line of `kind` for every screen.
function Bums:say(b, kind)
  local lines = Lines[kind]
  self.says[#self.says + 1] = { id = b.id, kind = kind, index = random(#lines) }
end

--- Can `player` hire bum `id` right now, and set him on `target`? Returns
--- true, or false and a reason ("gone", "busy", "away", "target").
function Bums:canHire(server, player, id, target)
  local b = self.list[id]
  if not b or b.mode == "down" then
    return false, "gone"
  end
  if b.mode ~= "sit" then
    return false, "busy"
  end
  local x, y, onFoot = Features.bodyPose(server, player)
  if not (x and onFoot and Features.present(player)) or (x - b.x) ^ 2 + (y - b.y) ^ 2 > Bums.TALK_REACH ^ 2 then
    return false, "away"
  end
  if not Bums.targetable(player, target) or not Features.present(target) then
    return false, "target"
  end
  return true
end

--- May a bum be set on `target` by `player`? A player or a traffic bot,
--- never yourself, the police or anybody's hired help.
function Bums.targetable(player, target)
  if not target or target == player or not target.body then
    return false
  end
  return not target.bot or (target.civilian and not target.brain) or false
end

--- Send bum `id` after `target` (the hire checked and paid for).
function Bums:hire(id, target)
  local b = self.list[id]
  b.mode, b.target = "hunt", target.id
  b.foe = { -- what a bot he punches fights off (bots' fightOff)
    pos = function()
      return b.x, b.y
    end,
    alive = function()
      return b.mode == "hunt" and b.target == target.id
    end,
  }
  b.jobLeft = Bums.JOB_SECONDS
  b.stabbed = false -- his first punch makes them cry out
  b.punchTimer = 0.4
  b.path, b.pathIn, b.stuck = nil, 0, 0
  b.sayIn = Bums.SHOUT_MIN + random() * (Bums.SHOUT_MAX - Bums.SHOUT_MIN)
  self:say(b, "hired")
end

--- Off home, saying why.
function Bums:goHome(b, why)
  b.mode, b.target, b.path = "home", nil, nil
  b.homeLeft = Bums.HOME_SECONDS
  if why then
    self:say(b, why)
  end
end

--- The first standing bum within `radius` of (x, y), or nil.
function Bums:at(x, y, radius)
  local r2 = (radius + Bums.RADIUS) ^ 2
  for _, b in ipairs(self.list) do
    if b.mode ~= "down" and (b.x - x) ^ 2 + (b.y - y) ^ 2 < r2 then
      return b
    end
  end
  return nil
end

--- Take `amount` off `b`; down if that finishes him. Returns the kill
--- ({ id, x, y, angle, by }) or nil.
function Bums:hurt(b, amount, by, angle)
  b.hp = b.hp - amount
  if b.hp > 0 then
    return nil
  end
  return self:fell(b, by, angle)
end

function Bums:fell(b, by, angle)
  b.mode, b.target, b.path = "down", nil, nil
  b.downLeft = Bums.RESPAWN_SECONDS
  local kill = { id = b.id, x = b.x, y = b.y, angle = angle or 0, by = by }
  self.downs[#self.downs + 1] = kill
  return kill
end

--- Everything inside (x, y, radius) stands still for `seconds`.
function Bums:freeze(x, y, radius, seconds)
  for _, b in ipairs(self.list) do
    if b.mode ~= "down" and (b.x - x) ^ 2 + (b.y - y) ^ 2 <= (radius + Bums.RADIUS) ^ 2 then
      b.frozen = math.max(b.frozen, seconds)
    end
  end
end

--- Something stinks at (x, y): every bum up and about within `radius` runs
--- from it for `seconds` (renewed while the cloud hangs). One on his bench
--- has smelled worse.
function Bums:scare(x, y, radius, seconds)
  for _, b in ipairs(self.list) do
    if b.mode ~= "down" and b.mode ~= "sit" and (b.x - x) ^ 2 + (b.y - y) ^ 2 <= (radius + Bums.RADIUS) ^ 2 then
      b.panic = { x = x, y = y, left = seconds }
    end
  end
end

--- Towards (tx, ty) at `speed`: straight when the way is open, else along
--- a path round whatever is in it.
function Bums:towards(b, tx, ty, speed, dt)
  local gx, gy = tx, ty
  local nav = self:nav()
  if nav and not nav:clear(b.x, b.y, tx, ty) then
    b.pathIn = b.pathIn - dt
    if not b.path or b.pathIn <= 0 or b.stuck > 0.6 then
      b.path, b.step, b.pathIn = nav:path(b.x, b.y, tx, ty), 1, Bums.REPATH
    end
    local path = b.path
    while path and path[b.step] and (path[b.step].x - b.x) ^ 2 + (path[b.step].y - b.y) ^ 2 < 14 * 14 do
      b.step = b.step + 1
    end
    local corner = path and path[b.step]
    if corner then
      gx, gy = corner.x, corner.y
    end
  else
    b.path = nil
  end
  b.facing = math.atan2(gy - b.y, gx - b.x)
  if b.sidestep > 0 then
    b.sidestep = b.sidestep - dt
    walk(b, b.facing + b.side * math.pi / 2, speed, dt)
  else
    walk(b, b.facing, speed, dt)
    if b.stuck > 0.8 then
      b.stuck, b.sidestep, b.side = 0, 0.5, -b.side
    end
  end
end

--- Somebody cried out: a cop who can see them answers, once, whatever has
--- become of the bum. Until one has, look again every `COP_RETRY` seconds,
--- for `COP_WAIT` at most and while they are still up.
--- `now` is the id of a player who has just fired: their answer comes at
--- once, so the cop has had their say before they see the shot and go
--- after them for it.
function Bums:answer(server, dt, now)
  local police = Features.byName.police
  for i = #self.answers, 1, -1 do
    local a = self.answers[i]
    local p = server.players[a.id]
    a.left, a.waitIn = a.left - dt, a.id == now and 0 or a.waitIn - dt
    if not (police and police.serverRemark and p and Features.present(p)) or a.left <= 0 then
      table.remove(self.answers, i)
    elseif a.waitIn <= 0 then
      local x, y = Features.bodyPose(server, p)
      if police:serverRemark(server, x, y, Lines.cop) then
        table.remove(self.answers, i)
      else
        a.waitIn = Bums.COP_RETRY
      end
    end
  end
end

--- On the job: after his target, punching in reach.
function Bums:hunt(server, b, dt)
  local target = server.players[b.target]
  b.jobLeft = b.jobLeft - dt
  if not target then
    self:goHome(b, "giveup") -- they left town
    return
  end
  if target.body and target.body.dead then
    self:goHome(b, "done")
    return
  end
  if b.jobLeft <= 0 then
    self:goHome(b, "giveup")
    return
  end
  if not Features.visible(server, target) then
    b.facing = b.facing + dt * 1.5 -- looking about
    if not b.lost then
      b.lost = true
      self:say(b, "lost")
    end
    return
  end
  b.lost = false
  local x, y, onFoot = Features.bodyPose(server, target)
  if not x then
    return
  end
  local inReach
  if onFoot or not target.vehicle then
    inReach = (x - b.x) ^ 2 + (y - b.y) ^ 2 <= (Bums.RADIUS + Bums.REACH) ^ 2
  else
    inReach = Car.hitTest(target.vehicle, b.x, b.y, Bums.RADIUS + Bums.REACH) -- any side of the car will do
  end
  if inReach then
    b.facing = math.atan2(y - b.y, x - b.x)
  else
    self:towards(b, x, y, Bums.RUN_SPEED, dt)
  end
  b.punchTimer = b.punchTimer - dt
  if inReach and b.punchTimer <= 0 then
    b.punchTimer = Bums.PUNCH_INTERVAL
    b.swing = 0.3
    local weapons = Features.byName.weapons
    if weapons and weapons.serverDamage then
      weapons:serverDamage(server, target, nil, Bums.PUNCH_DAMAGE, b.facing, "melee")
    end
    local damage = Features.byName.damage
    if damage and damage.serverAfflict and onFoot and not (target.body and target.body.dead) then
      damage:serverAfflict(server, target, "bleed", Bums.BLEED_SECONDS, Bums.BLEED_DPS)
    end
    local bots = Features.byName.bots
    if target.bot and bots and bots.fightOff then
      bots:fightOff(server, target, b.foe)
    end
    if not b.stabbed then
      b.stabbed = true
      self.cries[#self.cries + 1] = target.id
      self.answers[#self.answers + 1] = { id = target.id, waitIn = Bums.COP_DELAY, left = Bums.COP_WAIT }
    end
  end
  b.sayIn = b.sayIn - dt
  if b.sayIn <= 0 then
    b.sayIn = Bums.SHOUT_MIN + random() * (Bums.SHOUT_MAX - Bums.SHOUT_MIN)
    self:say(b, "shout")
  end
end

--- Job over: back to the bench at a shuffle.
function Bums:homeward(b, dt)
  b.homeLeft = b.homeLeft - dt
  local h = b.home
  if b.homeLeft <= 0 or (h.x - b.x) ^ 2 + (h.y - b.y) ^ 2 < 8 * 8 then
    self:seat(b)
    return
  end
  self:towards(b, h.x, h.y, Bums.WALK_SPEED, dt)
end

--- A car touching `b`: hurt by its speed (the driver's kill if it finishes
--- him) and shoved out of its way.
function Bums:trampled(server, b, dt)
  b.hitFor = math.max(0, b.hitFor - dt)
  for _, car in pairs(server.vehicles) do
    if not (car.hidden or car.stowed) and (car.x - b.x) ^ 2 + (car.y - b.y) ^ 2 < (Car.WIDTH + Bums.RADIUS) ^ 2
      and Car.hitTest(car, b.x, b.y, Bums.RADIUS) then
      local speed = math.abs(car.speed or 0)
      if speed >= Bums.CAR_MIN_SPEED and b.hitFor <= 0 then
        b.hitFor = Bums.CAR_EVERY
        local travel = car.speed >= 0 and car.angle or car.angle + math.pi
        if self:hurt(b, speed * Bums.CAR_DAMAGE, car.driver, travel) then
          return
        end
      end
      local away = math.atan2(b.y - car.y, b.x - car.x)
      local push = (Bums.RUN_SPEED + speed) * dt * 2
      if not blockedAt(b.x + math.cos(away) * push, b.y + math.sin(away) * push) then
        b.x, b.y = b.x + math.cos(away) * push, b.y + math.sin(away) * push
      end
    end
  end
end

--- What was said, who went down and who cried out (player ids) since the
--- last call (shots land between ticks), for init.lua to send; the lists
--- start again empty.
function Bums:drain()
  local says, downs, cries = self.says, self.downs, self.cries
  self.says, self.downs, self.cries = {}, {}, {}
  return says, downs, cries
end

--- One host tick.
function Bums:step(server, dt)
  self.time = self.time + dt
  self:answer(server, dt)
  for _, b in ipairs(self.list) do
    b.moving = false
    if b.mode == "down" then
      b.downLeft = b.downLeft - dt
      if b.downLeft <= 0 then
        self:seat(b)
      end
    else
      b.swing = math.max(0, b.swing - dt)
      if b.frozen > 0 then
        b.frozen = b.frozen - dt
      elseif b.panic then
        b.panic.left = b.panic.left - dt
        b.facing = math.atan2(b.y - b.panic.y, b.x - b.panic.x)
        walk(b, b.facing, Bums.RUN_SPEED, dt)
        if b.panic.left <= 0 then
          b.panic = nil
        end
      elseif b.mode == "hunt" then
        self:hunt(server, b, dt)
      elseif b.mode == "home" then
        self:homeward(b, dt)
      elseif (b.home.x - b.x) ^ 2 + (b.home.y - b.y) ^ 2 > 6 * 6 then
        self:goHome(b) -- shoved off his bench
      else
        b.sayIn = b.sayIn - dt
        if b.sayIn <= 0 then
          b.sayIn = Bums.MUTTER_MIN + random() * (Bums.MUTTER_MAX - Bums.MUTTER_MIN)
          self:say(b, "mutter")
        end
      end
      if b.mode ~= "down" then
        self:trampled(server, b, dt)
      end
    end
  end
end

return Bums
