-- The Hunter-Chopper's bombs (its bombing runs: brain.lua drops them).
-- Each is dropped off one side of it and falls for `fall` seconds onto the
-- spot below where it was let go: every screen shows a ring there filling
-- in as it comes, the bomb itself shrinking towards the ground as it drops,
-- its shadow sliding in under it, and its whistle. On the ground it goes
-- off as a missile does (weapons' `explode`: the boom, the shake, damage
-- falling from `damage` at the middle to a third at the edge of `radius`,
-- cars and soft targets too), owned by nobody.
--
-- Messages
--   server -> all  HC_BOMB <x> <y> <radius> <fall>   one is falling onto (x, y)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Render = require("src.features.hunter-chopper.render")
local Sounds = require("src.features.hunter-chopper.sounds")

local Bombs = {}

-- Tuning ------------------------------------------------------------------
Bombs.fall = 1.0 -- seconds from letting go to the ground
Bombs.radius = 80 -- px the blast reaches
Bombs.damage = 40 -- at the middle, a third of it at the edge
Bombs.soft = 2 -- rounds' worth to the crowd and other soft targets

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

--- A new, empty set of falling bombs, on the host.
function Bombs.new()
  return {}
end

--- Let one go over (x, y): it lands there `fall` seconds on.
function Bombs.drop(list, server, x, y)
  list[#list + 1] = { x = x, y = y, t = Bombs.fall }
  server:broadcast(Protocol.encode("HC_BOMB", fmt(x), fmt(y), Bombs.radius, ("%.2f"):format(Bombs.fall)))
end

--- The ones that have hit the ground go off.
function Bombs.step(list, server, dt)
  local weapons = Features.byName.weapons
  for i = #list, 1, -1 do
    local b = list[i]
    b.t = b.t - dt
    if b.t <= 0 then
      table.remove(list, i)
      if weapons and weapons.explode then
        -- A missile of nobody's that has come straight down (pid 0: no round on anyone's screen).
        weapons:explode(server, { id = 0, owner = 0, vx = 0, vy = 1,
          blast = { radius = Bombs.radius, damage = Bombs.damage, soft = Bombs.soft } }, b.x, b.y)
      end
    end
  end
end

-- Client --------------------------------------------------------------------

local falling = {} -- { x, y, r, t, total } on this screen

function Bombs.clear()
  falling = {}
end

function Bombs.update(dt)
  for i = #falling, 1, -1 do
    local b = falling[i]
    b.t = b.t - dt
    if b.t <= 0 then
      table.remove(falling, i) -- the boom is the weapons feature's (WPN_BOOM)
    end
  end
end

--- The rings on the ground, under everyone.
function Bombs.drawBelowCars(time)
  for _, b in ipairs(falling) do
    local k = 1 - b.t / b.total -- 0 let go .. 1 on the ground
    local pulse = 0.6 + 0.4 * math.sin(time * (8 + k * 20))
    love.graphics.setColor(1, 0.25, 0.15, 0.10 + 0.20 * k)
    love.graphics.circle("fill", b.x, b.y, b.r * k, 32)
    love.graphics.setColor(1, 0.3, 0.2, (0.4 + 0.4 * k) * pulse)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", b.x, b.y, b.r, 32)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- The bombs on their way down, over everyone.
function Bombs.drawAboveCars(time)
  for _, b in ipairs(falling) do
    local k = 1 - b.t / b.total
    Render.bomb(b.x, b.y, (1 - k) * Render.ALTITUDE, time)
  end
end

Bombs.clientMessages = {
  HC_BOMB = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    local r, fall = tonumber(args[3]) or Bombs.radius, tonumber(args[4]) or Bombs.fall
    if x and y then
      falling[#falling + 1] = { x = x, y = y, r = r, t = fall, total = fall }
      Sounds.play("whistle", x, y)
    end
  end,
}

return Bombs
