-- What the horde throws and shoots that you can see coming and step out of
-- the way of (docs/eternal-mood.md, "The demons"): the imps' fireballs, the
-- Cacodaemons' spit and the Floor Manager's plasma, each a `kind`
-- (Fireballs.KINDS). The host flies
-- them and decides what they hit; every screen flies its own copy from where
-- and how fast it set off, and drops it when the host says it burst.
--
-- One hits the first player it reaches and bursts, or bursts on the first
-- wall; it never hurts the horde. It burns out after its `ttl`.
--
-- Messages
--   server -> all  HRD_BALL <id> <x> <y> <vx> <vy> <kind>   one set off (kind f fireball, c spit, p plasma)
--   server -> all  HRD_POP  <id> <x> <y>                    one burst there

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Fireballs = {}

Fireballs.FOOT = 10 -- px; how fat a player on foot is to them (weapons' FOOT_RADIUS)

-- Each kind: its code on the wire, speed (px/s), ttl (s), radius (px),
-- damage and its type, and its colours (outside, inside).
Fireballs.KINDS = {
  fireball = { -- an imp's: a player sprints at 170, so a step to the side does it
    code = "f", speed = 330, ttl = 2.4, radius = 9, damage = 14, dtype = "fire",
    color = { 1.00, 0.55, 0.12 }, core = { 1.00, 0.90, 0.45 }, tail = 4,
  },
  spit = { -- a Cacodaemon's: big, slow and hot
    code = "c", speed = 260, ttl = 2.8, radius = 14, damage = 24, dtype = "fire",
    color = { 1.00, 0.32, 0.18 }, core = { 1.00, 0.80, 0.55 }, tail = 5,
  },
  plasma = { -- the Floor Manager's: quicker and smaller, in streams
    code = "p", speed = 520, ttl = 1.6, radius = 6, damage = 9, dtype = "shock",
    color = { 0.35, 1.00, 0.45 }, core = { 0.85, 1.00, 0.85 }, tail = 3,
  },
}
local BY_CODE = {}
for key, k in pairs(Fireballs.KINDS) do
  k.key = key
  BY_CODE[k.code] = k
end

local POP_FOR = 0.35 -- seconds a burst shows

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { list, nextId }

function Fireballs.serverStart()
  sv = { list = {}, nextId = 1 }
end

function Fireballs.serverStop()
  sv = nil
end

--- One of `kind` (a key of Fireballs.KINDS, "fireball" when nil) from (x, y)
--- along `angle`.
function Fireballs.serverThrow(server, x, y, angle, kind)
  if not sv then
    return
  end
  local k = Fireballs.KINDS[kind or "fireball"]
  local b = { id = sv.nextId, x = x, y = y, vx = math.cos(angle) * k.speed, vy = math.sin(angle) * k.speed, age = 0,
    kind = k }
  sv.nextId = sv.nextId + 1
  sv.list[#sv.list + 1] = b
  server:broadcast(Protocol.encode("HRD_BALL", b.id, fmt(x), fmt(y), fmt(b.vx), fmt(b.vy), k.code))
end

local function burst(server, b, i)
  table.remove(sv.list, i)
  server:broadcast(Protocol.encode("HRD_POP", b.id, fmt(b.x), fmt(b.y)))
end

function Fireballs.serverStep(server, dt)
  if not sv then
    return
  end
  local weapons = Features.byName.weapons
  for i = #sv.list, 1, -1 do
    local b = sv.list[i]
    local k = b.kind
    b.age = b.age + dt
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    local hit = nil
    for _, p in pairs(server.players) do
      if Features.visible(server, p) then
        local px, py = Features.bodyPose(server, p)
        if (px - b.x) ^ 2 + (py - b.y) ^ 2 <= (k.radius + Fireballs.FOOT) ^ 2 then
          hit = p
          break
        end
      end
    end
    if hit then
      if weapons and weapons.serverDamage then
        weapons:serverDamage(server, hit, nil, k.damage, math.atan2(b.vy, b.vx), k.dtype)
      end
      burst(server, b, i)
    elseif b.age >= k.ttl or Sight.blocked(b.x, b.y) then
      burst(server, b, i)
    end
  end
end

--- For tests.
function Fireballs.server()
  return sv
end

-- Client --------------------------------------------------------------------

local flying = {} -- id -> { x, y, vx, vy, age, kind }
local pops = {} -- { x, y, t, kind }
local clock = 0

function Fireballs.clear()
  flying, pops = {}, {}
end

function Fireballs.update(dt)
  clock = clock + dt
  for id, b in pairs(flying) do
    b.age = b.age + dt
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    if b.age > b.kind.ttl + 0.5 then
      flying[id] = nil
    end
  end
  for i = #pops, 1, -1 do
    pops[i].t = pops[i].t + dt
    if pops[i].t > POP_FOR then
      table.remove(pops, i)
    end
  end
end

function Fireballs.draw()
  for id, b in pairs(flying) do
    local k = b.kind
    local c, core, r = k.color, k.core, k.radius
    local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    local ux, uy = b.vx / speed, b.vy / speed
    for n = k.tail, 1, -1 do -- the tail
      love.graphics.setColor(c[1], c[2] * 0.8, c[3], 0.18 * (k.tail + 1 - n))
      love.graphics.circle("fill", b.x - ux * n * r * 0.8, b.y - uy * n * r * 0.8, math.max(1, r - n), 10)
    end
    local flicker = 1 + 0.15 * math.sin(clock * 30 + id)
    love.graphics.setColor(c)
    love.graphics.circle("fill", b.x, b.y, r * flicker, 14)
    love.graphics.setColor(core)
    love.graphics.circle("fill", b.x + ux * 2, b.y + uy * 2, r * 0.5, 10)
  end
  for _, p in ipairs(pops) do
    local f = p.t / POP_FOR
    local c, core = p.kind.color, p.kind.core
    love.graphics.setColor(c[1], c[2], c[3], 0.8 * (1 - f))
    love.graphics.circle("fill", p.x, p.y, 8 + 22 * f, 16)
    love.graphics.setColor(core[1], core[2], core[3], 0.9 * (1 - f))
    love.graphics.circle("fill", p.x, p.y, 4 + 8 * f, 12)
  end
  love.graphics.setColor(1, 1, 1)
end

function Fireballs.drawNightLights(glow)
  for _, b in pairs(flying) do
    glow(b.x, b.y, b.kind.radius * 12, b.kind.color, 0.9)
  end
  for _, p in ipairs(pops) do
    glow(p.x, p.y, 140, p.kind.color, 0.9 * (1 - p.t / POP_FOR))
  end
end

Fireballs.clientMessages = {
  HRD_BALL = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local vx, vy = tonumber(args[4]), tonumber(args[5])
    local k = BY_CODE[args[6]] or Fireballs.KINDS.fireball
    if id and x and y and vx and vy then
      flying[id] = { x = x, y = y, vx = vx, vy = vy, age = 0, kind = k }
      Fireballs.onThrow(x, y, k.key)
    end
  end,
  HRD_POP = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local b = id and flying[id]
    if id then
      flying[id] = nil
    end
    if x and y then
      local k = b and b.kind or Fireballs.KINDS.fireball
      pops[#pops + 1] = { x = x, y = y, t = 0, kind = k }
      Fireballs.onPop(x, y, k.key)
    end
  end,
}

--- Sounds, set by horde.lua: `kind` is the key of what was thrown.
function Fireballs.onThrow() end
function Fireballs.onPop() end

return Fireballs
