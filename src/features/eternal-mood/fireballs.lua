-- The imps' fireballs (docs/eternal-mood.md, "The demons"): slow enough to
-- sidestep, a ball of fire with a tail. The host flies them and decides what
-- they hit; every screen flies its own copy from where and how fast it set
-- off, and drops it when the host says it burst.
--
-- One hits the first player it reaches (`fire` damage) and bursts, or bursts
-- on the first wall; it never hurts the horde. It burns out after TTL.
--
-- Messages
--   server -> all  HRD_BALL <id> <x> <y> <vx> <vy>   one set off
--   server -> all  HRD_POP  <id> <x> <y>             one burst there

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Fireballs = {}

Fireballs.SPEED = 330 -- px/s; a player sprints at 170, so a step to the side does it
Fireballs.TTL = 2.4 -- seconds
Fireballs.RADIUS = 9 -- px
Fireballs.DAMAGE = 14
Fireballs.FOOT = 10 -- px; how fat a player on foot is to it (weapons' FOOT_RADIUS)

local ORANGE = { 1.00, 0.55, 0.12 }
local YELLOW = { 1.00, 0.90, 0.45 }
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

--- A fireball from (x, y) along `angle`.
function Fireballs.serverThrow(server, x, y, angle)
  if not sv then
    return
  end
  local b = { id = sv.nextId, x = x, y = y, vx = math.cos(angle) * Fireballs.SPEED,
    vy = math.sin(angle) * Fireballs.SPEED, age = 0 }
  sv.nextId = sv.nextId + 1
  sv.list[#sv.list + 1] = b
  server:broadcast(Protocol.encode("HRD_BALL", b.id, fmt(x), fmt(y), fmt(b.vx), fmt(b.vy)))
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
    b.age = b.age + dt
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    local hit = nil
    for _, p in pairs(server.players) do
      if Features.visible(server, p) then
        local px, py = Features.bodyPose(server, p)
        if (px - b.x) ^ 2 + (py - b.y) ^ 2 <= (Fireballs.RADIUS + Fireballs.FOOT) ^ 2 then
          hit = p
          break
        end
      end
    end
    if hit then
      if weapons and weapons.serverDamage then
        weapons:serverDamage(server, hit, nil, Fireballs.DAMAGE, math.atan2(b.vy, b.vx), "fire")
      end
      burst(server, b, i)
    elseif b.age >= Fireballs.TTL or Sight.blocked(b.x, b.y) then
      burst(server, b, i)
    end
  end
end

--- For tests.
function Fireballs.server()
  return sv
end

-- Client --------------------------------------------------------------------

local flying = {} -- id -> { x, y, vx, vy, age }
local pops = {} -- { x, y, t }
local clock = 0

function Fireballs.clear()
  flying, pops = {}, {}
end

function Fireballs.update(dt)
  clock = clock + dt
  for id, b in pairs(flying) do
    b.age = b.age + dt
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    if b.age > Fireballs.TTL + 0.5 then
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
    local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    local ux, uy = b.vx / speed, b.vy / speed
    for k = 4, 1, -1 do -- the tail
      local a = 0.18 * (5 - k)
      love.graphics.setColor(ORANGE[1], ORANGE[2] * 0.7, ORANGE[3], a)
      love.graphics.circle("fill", b.x - ux * k * 7, b.y - uy * k * 7, Fireballs.RADIUS - k, 10)
    end
    local flicker = 1 + 0.15 * math.sin(clock * 30 + id)
    love.graphics.setColor(ORANGE)
    love.graphics.circle("fill", b.x, b.y, Fireballs.RADIUS * flicker, 14)
    love.graphics.setColor(YELLOW)
    love.graphics.circle("fill", b.x + ux * 2, b.y + uy * 2, Fireballs.RADIUS * 0.5, 10)
  end
  for _, p in ipairs(pops) do
    local k = p.t / POP_FOR
    love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.8 * (1 - k))
    love.graphics.circle("fill", p.x, p.y, 8 + 22 * k, 16)
    love.graphics.setColor(YELLOW[1], YELLOW[2], YELLOW[3], 0.9 * (1 - k))
    love.graphics.circle("fill", p.x, p.y, 4 + 8 * k, 12)
  end
  love.graphics.setColor(1, 1, 1)
end

function Fireballs.drawNightLights(glow)
  for _, b in pairs(flying) do
    glow(b.x, b.y, 110, ORANGE, 0.9)
  end
  for _, p in ipairs(pops) do
    glow(p.x, p.y, 140, ORANGE, 0.9 * (1 - p.t / POP_FOR))
  end
end

Fireballs.clientMessages = {
  HRD_BALL = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local vx, vy = tonumber(args[4]), tonumber(args[5])
    if id and x and y and vx and vy then
      flying[id] = { x = x, y = y, vx = vx, vy = vy, age = 0 }
      Fireballs.onThrow(x, y)
    end
  end,
  HRD_POP = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if id then
      flying[id] = nil
    end
    if x and y then
      pops[#pops + 1] = { x = x, y = y, t = 0 }
      Fireballs.onPop(x, y)
    end
  end,
}

--- Sounds, set by horde.lua.
function Fireballs.onThrow() end
function Fireballs.onPop() end

return Fireballs
