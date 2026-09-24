-- Panic fart: let one go and a stinking cloud hangs where you stood for a
-- few seconds. Everything with a nose runs from it: NPC cars (bots, police
-- units included) drive away from the cloud while they are in it,
-- pedestrians bolt, and so do Karen, her simps and the wild man's
-- creatures on the quests. Players are unmoved (they can't smell). Nothing
-- to aim: press the key (`aim = "self"`).
--
-- The host keeps the clouds and, every tick, raises `serverPanicArea(server,
-- x, y, radius, by)` for each one; bots and pedestrians answer it by
-- running from (x, y) for a moment, so whatever wanders in later runs too.

local Features = require("src.features")

local Fart = {
  key = "fart", -- on the wire and in a bag ("ability-fart")
  title = "panic fart",
  hud = "fart", -- short enough to fit under its ring
  sound = "fart",
  color = { 0.62, 0.72, 0.28 }, -- a sickly green
  aim = "self",
}

-- Tuning ------------------------------------------------------------------
Fart.radius = 150 -- px the cloud reaches
Fart.range = 0 -- it is let go where you stand
Fart.seconds = 6 -- how long the cloud hangs
Fart.cooldown = 25 -- seconds before the next
Fart.afterglow = 1.2 -- seconds the cloud takes to thin out once it is spent

local clouds = {} -- { by, x, y, untilT }

-- Server --------------------------------------------------------------------

function Fart.serverReset()
  clouds = {}
end

--- A cloud where the caster stands. Nobody is held.
function Fart.serverCast(_server, caster, x, y, abilities)
  clouds[#clouds + 1] = { by = caster.id, x = x, y = y, untilT = abilities.sv.time + Fart.seconds }
  return {}
end

--- Every cloud that still hangs tells the world to run from it.
function Fart.serverStep(server, _dt, abilities)
  local now = abilities.sv.time
  for i = #clouds, 1, -1 do
    local c = clouds[i]
    if now >= c.untilT then
      table.remove(clouds, i)
    else
      Features.call("serverPanicArea", server, c.x, c.y, Fart.radius, c.by)
    end
  end
end

--- For tests.
function Fart.serverClouds()
  return clouds
end

-- Client --------------------------------------------------------------------

local PUFFS = 9

--- The cloud: a ring of soft puffs drifting round the centre and a few
--- stink lines wobbling up, thinning out through the afterglow.
function Fart.drawEffect(e)
  local c = Fart.color
  local fade = math.max(0, math.min(1, (e.seconds + Fart.afterglow - e.t) / Fart.afterglow))
  local grow = math.min(1, e.t / 0.6) -- it billows out over the first moment
  local r = Fart.radius * grow
  local seed = math.floor(e.x * 3 + e.y * 7)
  love.graphics.setColor(c[1], c[2], c[3], 0.10 * fade)
  love.graphics.circle("fill", e.x, e.y, r, 48)
  for k = 1, PUFFS do
    local a = (k + seed % PUFFS) * (2 * math.pi / PUFFS) + e.t * 0.35
    local wob = 0.72 + 0.16 * math.sin(e.t * 1.7 + k * 1.3)
    local px, py = e.x + math.cos(a) * r * wob, e.y + math.sin(a) * r * wob
    local pr = r * (0.28 + 0.06 * math.sin(e.t * 2.3 + k))
    love.graphics.setColor(c[1] * 0.9, c[2] * 0.9, c[3] * 0.7, 0.16 * fade)
    love.graphics.circle("fill", px, py, pr, 24)
    love.graphics.setColor(c[1], c[2], c[3], 0.28 * fade)
    love.graphics.circle("line", px, py, pr, 24)
  end
  -- Stink lines: three wavy strokes rising from the middle.
  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.85, 0.95, 0.6, 0.55 * fade)
  for k = -1, 1 do
    local phase = (e.t * 0.7 + (k + 1) / 3) % 1
    local bx = e.x + k * 22
    local by = e.y - phase * 70
    love.graphics.line(bx, by + 24, bx + 6, by + 16, bx - 6, by + 8, bx + 6, by, bx, by - 6)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Fart
