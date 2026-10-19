-- Rockets that come down on a marked spot (docs/borderline.md, "The
-- army"): a rocket hauler's pod volley and a jet hauler's strafing run
-- (the bunker's later). Every screen sees a red ring on the ground where
-- each will land, filling in as it comes, then the rocket diving in out of
-- the sky with its flame; on the ground it goes off as a missile does
-- (weapons' `explode`: the boom, damage falling off to a third at the
-- edge, cars and soft targets too), owned by nobody, so it never hurts the
-- army. Step out of the ring.
--
-- Messages
--   server -> all  HYP_RAIN <x> <y> <radius> <delay> <fromX> <fromY>
--                  a rocket set off from (fromX, fromY) lands on (x, y) in `delay` seconds

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Hauler = require("src.features.borderline.hauler_look")

local Barrage = {}

Barrage.SOFT = 2 -- rounds' worth to soft targets
Barrage.ALTITUDE = 260 -- px up it is drawn when it sets off

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local incoming = nil -- on the host: { x, y, radius, damage, t }

function Barrage.serverStart()
  incoming = {}
end

function Barrage.serverStop()
  incoming = nil
end

--- A rocket from (fromX, fromY) onto (x, y), landing `delay` seconds on
--- with a blast of `radius` px and `damage` at the middle (grown on a job
--- done before).
function Barrage.serverFire(server, fromX, fromY, x, y, radius, damage, delay)
  if not incoming then
    return
  end
  incoming[#incoming + 1] = { x = x, y = y, radius = radius, damage = damage * Bosses.enemyPower(), t = delay }
  server:broadcast(Protocol.encode("HYP_RAIN", fmt(x), fmt(y), radius, ("%.2f"):format(delay), fmt(fromX),
    fmt(fromY)))
end

function Barrage.serverStep(server, dt)
  local weapons = Features.byName.weapons
  for i = #(incoming or {}), 1, -1 do
    local r = incoming[i]
    r.t = r.t - dt
    if r.t <= 0 then
      table.remove(incoming, i)
      if weapons and weapons.explode then
        -- Nobody's missile, come straight down (pid 0: no round on anyone's screen).
        weapons:explode(server, { id = 0, owner = 0, vx = 0, vy = 1,
          blast = { radius = r.radius, damage = r.damage, soft = Barrage.SOFT } }, r.x, r.y)
      end
    end
  end
end

-- Client --------------------------------------------------------------------

local coming = {} -- { x, y, r, t, total, fromX, fromY }

function Barrage.clear()
  coming = {}
end

function Barrage.update(dt)
  for i = #coming, 1, -1 do
    local c = coming[i]
    c.t = c.t - dt
    if c.t <= 0 then
      table.remove(coming, i) -- the boom is the weapons feature's (WPN_BOOM)
    end
  end
end

--- The rings on the ground, under everyone.
function Barrage.drawBelowCars(clock)
  for _, c in ipairs(coming) do
    local k = 1 - c.t / c.total
    local pulse = 0.6 + 0.4 * math.sin(clock * (10 + k * 24))
    love.graphics.setColor(1, 0.15, 0.1, 0.08 + 0.22 * k)
    love.graphics.circle("fill", c.x, c.y, c.r * k, 32)
    love.graphics.setColor(1, 0.2, 0.12, (0.45 + 0.45 * k) * pulse)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", c.x, c.y, c.r, 32)
    love.graphics.line(c.x - 8, c.y, c.x + 8, c.y)
    love.graphics.line(c.x, c.y - 8, c.x, c.y + 8)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- The rockets on their way in, over everyone: from where they set off,
--- up and over, diving onto the ring.
function Barrage.drawAboveCars(clock)
  local C = Hauler.C
  for _, c in ipairs(coming) do
    local k = 1 - c.t / c.total
    local gx, gy = c.fromX + (c.x - c.fromX) * k, c.fromY + (c.y - c.fromY) * k -- over the ground
    local up = Barrage.ALTITUDE * 4 * k * (1 - k) + Barrage.ALTITUDE * 0.15 * (1 - k)
    local x, y = gx, gy - up
    local nx, ny = c.x - c.fromX, (c.y - c.fromY) - Barrage.ALTITUDE * 4 * (1 - 2 * k) -- where it heads
    local a = math.atan2(ny, nx)
    love.graphics.setColor(0, 0, 0, 0.25 * k) -- its shadow, darker as it comes down
    love.graphics.circle("fill", gx, gy, 4, 8)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(a)
    local f = 0.7 + 0.3 * math.sin(clock * 45)
    love.graphics.setColor(C.flame[1], C.flame[2], C.flame[3], f)
    love.graphics.polygon("fill", -6, -2.5, -14 - 5 * f, 0, -6, 2.5)
    love.graphics.setColor(C.ink)
    love.graphics.rectangle("fill", -7, -3, 15, 6, 2)
    love.graphics.setColor(C.rocket)
    love.graphics.rectangle("fill", -6, -2, 13, 4, 2)
    love.graphics.pop()
  end
  love.graphics.setColor(1, 1, 1)
end

Barrage.clientMessages = {
  HYP_RAIN = function(_client, args)
    local x, y, r, delay = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and r and delay and delay > 0 then
      coming[#coming + 1] = { x = x, y = y, r = r, t = delay, total = delay, fromX = tonumber(args[5]) or x,
        fromY = tonumber(args[6]) or y }
    end
  end,
}

return Barrage
