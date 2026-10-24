-- Flechettes (docs/borderline.md, "The army"): what the stalker haulers
-- fire, in bursts out of their shoulder pods. A dart flies fast and sticks
-- in the first player it reaches (stinging a little), the first wall, or
-- the ground where its flight ends; stuck, it blinks inside a red ring for
-- `FUSE` seconds and then blows, a small blast owned by nobody, so it never
-- hurts the army. One stuck in a player rides along with them: get away
-- from the others before it goes. The host flies them; every screen flies
-- its own copy and sticks it where the host says.
--
-- Messages
--   server -> all  HYP_DART  <id> <x> <y> <vx> <vy> <ttl>  one set off
--   server -> all  HYP_STICK <id> <x> <y> <who> <radius>   it stuck at (x, y): in player `who`, or 0 in the
--                                                          ground; it blows `radius` px wide

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Hauler = require("src.features.borderline.hauler_look")

local Darts = {}

Darts.FOOT = 10 -- px; how fat a player on foot is to a dart (weapons' FOOT_RADIUS)
Darts.FUSE = 1 -- seconds from sticking to going off
Darts.SOFT = 0.5 -- rounds' worth to soft targets

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { flying, stuck, nextId }

function Darts.serverStart()
  sv = { flying = {}, stuck = {}, nextId = 1 }
end

function Darts.serverStop()
  sv = nil
end

--- A dart from (x, y) along `angle`: kind { speed, ttl, sting, radius, damage }.
function Darts.serverFire(server, x, y, angle, kind)
  if not sv then
    return
  end
  local power = Bosses.enemyPower()
  local d = {
    id = sv.nextId, x = x, y = y, vx = math.cos(angle) * kind.speed, vy = math.sin(angle) * kind.speed, age = 0,
    ttl = kind.ttl, sting = kind.sting * power, radius = kind.radius, damage = kind.damage * power,
  }
  sv.nextId = sv.nextId + 1
  sv.flying[#sv.flying + 1] = d
  server:broadcast(Protocol.encode("HYP_DART", d.id, fmt(x), fmt(y), fmt(d.vx), fmt(d.vy), ("%.2f"):format(d.ttl)))
end

--- The player a dart at (x, y) has run into, if any.
local function struck(server, x, y)
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      if (px - x) ^ 2 + (py - y) ^ 2 <= Darts.FOOT * Darts.FOOT then
        return p
      end
    end
  end
  return nil
end

--- Dart `d` sticks where it is: in `who` (stinging them), or in the ground.
local function stick(server, d, who)
  d.fuse, d.who = Darts.FUSE, who and who.id or nil
  sv.stuck[#sv.stuck + 1] = d
  if who then
    local weapons = Features.byName.weapons
    if weapons and weapons.serverDamage then
      weapons:serverDamage(server, who, nil, math.floor(d.sting + 0.5), math.atan2(d.vy, d.vx), "bullet")
    end
  end
  server:broadcast(Protocol.encode("HYP_STICK", d.id, fmt(d.x), fmt(d.y), d.who or 0, d.radius))
end

function Darts.serverStep(server, dt)
  if not sv then
    return
  end
  for i = #sv.flying, 1, -1 do
    local d = sv.flying[i]
    d.age = d.age + dt
    local nx, ny = d.x + d.vx * dt, d.y + d.vy * dt
    local who = struck(server, nx, ny)
    if Features.any("blocksShot", nx, ny) then
      table.remove(sv.flying, i)
      stick(server, d) -- in the wall's face, where it was a moment ago
    else
      d.x, d.y = nx, ny
      if who or d.age >= d.ttl then
        table.remove(sv.flying, i)
        stick(server, d, who)
      end
    end
  end
  local weapons = Features.byName.weapons
  for i = #sv.stuck, 1, -1 do
    local d = sv.stuck[i]
    local p = d.who and server.players[d.who]
    if p and Features.present(p) then -- riding along in somebody
      d.x, d.y = Features.bodyPose(server, p)
    end
    d.fuse = d.fuse - dt
    if d.fuse <= 0 then
      table.remove(sv.stuck, i)
      if weapons and weapons.explode then -- nobody's blast (pid 0: no round on anyone's screen)
        weapons:explode(server, { id = 0, owner = 0, vx = 0, vy = 1,
          blast = { radius = d.radius, damage = d.damage, soft = Darts.SOFT } }, d.x, d.y)
      end
    end
  end
end

-- Client --------------------------------------------------------------------

local flying = {} -- id -> { x, y, vx, vy, age, ttl }
local stuck = {} -- id -> { x, y, angle, who, t }
local bank = {}

function Darts.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(220, 1800)
    return src
  end
  -- Set off: a sharp metal hiss.
  bank.fire = make(0.12, 0.45, function(buf)
    buf:noiseBurst(0, 0.1, { amp = 0.5, decay = 0.03 })
    buf:sweep(0, 0.08, 2400, 1200, { wave = "square", amp = 0.12, decay = 0.03 })
    buf:highpass(1800)
  end)
  -- Stuck: a thunk, then the arming tick.
  bank.stick = make(0.2, 0.5, function(buf)
    buf:sweep(0, 0.05, 420, 160, { wave = "square", amp = 0.35, decay = 0.02 })
    buf:sweep(0.09, 0.04, 2600, 2600, { wave = "sine", amp = 0.18, decay = 0.02 })
  end)
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.9 + love.math.random() * 0.25)
    s:setVolume(0.5 * Audio.volume("weapons"))
    s:play()
  end
end

function Darts.clear()
  flying, stuck = {}, {}
end

--- `client` says where each player is on this screen (a dart in one follows them).
function Darts.update(dt, client)
  for id, d in pairs(flying) do
    d.age = d.age + dt
    d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
    if d.age > d.ttl + 0.5 then
      flying[id] = nil -- never heard it stick: let it go
    end
  end
  for id, d in pairs(stuck) do
    d.t = d.t + dt
    if d.who and client then
      local x, y = client:pose(d.who)
      if x then
        d.x, d.y = x + d.offX, y + d.offY
      end
    end
    if d.t > Darts.FUSE + 0.2 then
      stuck[id] = nil -- the boom is the weapons feature's (WPN_BOOM)
    end
  end
end

--- A dart at (x, y) pointing along `angle`: a steel spike with a lit tip.
local function dart(x, y, angle, lit)
  local C = Hauler.C
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", -9, -1.6, 12, 3.2, 1)
  love.graphics.setColor(C.steel)
  love.graphics.rectangle("fill", -8, -0.8, 10, 1.6)
  love.graphics.setColor(lit and C.eye or C.yellow)
  love.graphics.circle("fill", 3, 0, 1.6, 8)
  love.graphics.pop()
end

--- The red rings round the stuck ones, on the ground (under cars).
function Darts.drawBelowCars(clock)
  for _, d in pairs(stuck) do
    local k = math.min(1, d.t / Darts.FUSE)
    love.graphics.setColor(1, 0.15, 0.1, 0.1 + 0.2 * k)
    love.graphics.circle("fill", d.x, d.y, d.r * k, 24)
    love.graphics.setColor(1, 0.2, 0.12, (0.5 + 0.4 * k) * (0.6 + 0.4 * math.sin(clock * (14 + 30 * k))))
    love.graphics.setLineWidth(1.5)
    love.graphics.circle("line", d.x, d.y, d.r, 24)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- The darts in flight with their streaks, and the stuck ones blinking, over everyone.
function Darts.drawAboveCars(clock)
  local C = Hauler.C
  love.graphics.setBlendMode("add")
  for _, d in pairs(flying) do
    local speed = math.sqrt(d.vx * d.vx + d.vy * d.vy)
    local ux, uy = d.vx / speed, d.vy / speed
    love.graphics.setColor(C.yellow[1], C.yellow[2], C.yellow[3], 0.35)
    love.graphics.setLineWidth(2)
    love.graphics.line(d.x - ux * 26, d.y - uy * 26, d.x, d.y)
    love.graphics.setLineWidth(1)
  end
  for _, d in pairs(stuck) do
    local k = d.t / Darts.FUSE
    if math.sin(clock * (12 + 40 * k)) > 0 then
      love.graphics.setColor(C.eye[1], C.eye[2], C.eye[3], 0.6)
      love.graphics.circle("fill", d.x + math.cos(d.angle) * 3, d.y + math.sin(d.angle) * 3, 5, 10)
    end
  end
  love.graphics.setBlendMode("alpha")
  for _, d in pairs(flying) do
    dart(d.x, d.y, math.atan2(d.vy, d.vx), false)
  end
  for _, d in pairs(stuck) do
    dart(d.x, d.y, d.angle, math.sin(clock * (12 + 40 * d.t / Darts.FUSE)) > 0)
  end
  love.graphics.setColor(1, 1, 1)
end

Darts.clientMessages = {
  HYP_DART = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local vx, vy, ttl = tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    if id and x and y and vx and vy and ttl and (vx ~= 0 or vy ~= 0) then
      flying[id] = { x = x, y = y, vx = vx, vy = vy, age = 0, ttl = ttl }
      play("fire", x, y)
    end
  end,
  HYP_STICK = function(client, args)
    local id, x, y, who = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    local r = tonumber(args[5])
    if not (id and x and y and r) then
      return
    end
    local f = flying[id]
    flying[id] = nil
    local angle = f and math.atan2(f.vy, f.vx) or 0
    local d = { x = x, y = y, angle = angle, t = 0, r = r, offX = 0, offY = 0 }
    if who and who ~= 0 and client:pose(who) then
      d.who, d.offX, d.offY = who, -math.cos(angle) * 4, -math.sin(angle) * 4
    end
    stuck[id] = d
    play("stick", x, y)
  end,
}

return Darts
