-- Heal: a green circle opens round you and, for a few seconds, everyone
-- standing in it is healed a little every moment, you included. The
-- circle follows you, so a driver can pull up beside a wounded friend
-- and keep moving. Nothing to aim: press the key and it is on you
-- (`aim = "self"` asks the abilities feature for that). Then it waits out
-- its cooldown.
--
-- The host does the healing through weapons:serverHeal (the body first,
-- then the car they are driving once the body is full), a whole hit point
-- at a time per player as the fractions add up.

local Features = require("src.features")

local Heal = {
  key = "heal", -- on the wire and in a bag ("ability-heal")
  title = "heal",
  sound = "heal",
  color = { 0.35, 1, 0.7 }, -- mint
  aim = "self",
}

-- Tuning ------------------------------------------------------------------
Heal.radius = 140 -- px round the caster that is healed
Heal.range = 0 -- it is cast on yourself
Heal.seconds = 4 -- how long the circle stays open
Heal.rate = 12 -- hit points a second to everyone inside
Heal.cooldown = 20 -- seconds before the next cast
Heal.afterglow = 0.5 -- seconds the circle takes to fade once it closes

local auras = {} -- { by, x, y, untilT, owed = { player id -> fraction } }

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

-- Server --------------------------------------------------------------------

function Heal.serverReset()
  auras = {}
end

--- Open a circle on the caster. Nobody is held.
function Heal.serverCast(_server, caster, x, y, abilities)
  auras[#auras + 1] = { by = caster.id, x = x, y = y, untilT = abilities.sv.time + Heal.seconds, owed = {} }
  return {}
end

--- Every open circle follows its caster and heals whoever stands in it.
function Heal.serverStep(server, dt, abilities)
  local now = abilities.sv.time
  local weapons = Features.byName.weapons
  for i = #auras, 1, -1 do
    local a = auras[i]
    if now >= a.untilT then
      table.remove(auras, i)
    else
      local caster = server.players[a.by]
      if caster and Features.present(caster) then
        a.x, a.y = Features.bodyPose(server, caster) -- it moves with them; stays put if they are wrecked
      end
      if weapons and weapons.serverHeal then
        for id, p in pairs(server.players) do
          if Features.present(p) then
            local px, py = Features.bodyPose(server, p)
            if dist2(px, py, a.x, a.y) <= Heal.radius ^ 2 then
              local sum = (a.owed[id] or 0) + Heal.rate * dt
              local whole = math.floor(sum)
              a.owed[id] = sum - whole
              if whole > 0 then
                weapons:serverHeal(server, p, whole)
              end
            end
          end
        end
      end
    end
  end
end

--- For tests.
function Heal.serverAuras()
  return auras
end

-- Client --------------------------------------------------------------------

--- The circle on the ground round its caster (where they are drawn now),
--- a soft fill with a slow pulse and a ring, fading out as it closes.
function Heal.drawEffect(e, client)
  local c = Heal.color
  local x, y = e.x, e.y
  if client then
    local px, py = Features.clientBodyPose(client, e.by)
    if px then
      x, y = px, py
    end
  end
  local fade = math.max(0, math.min(1, (e.seconds + Heal.afterglow - e.t) / Heal.afterglow))
  local pulse = 0.5 + 0.5 * math.sin(e.t * 5)
  love.graphics.setColor(c[1], c[2], c[3], (0.10 + 0.06 * pulse) * fade)
  love.graphics.circle("fill", x, y, Heal.radius, 48)
  love.graphics.setLineWidth(2.5)
  love.graphics.setColor(c[1], c[2], c[3], (0.55 + 0.25 * pulse) * fade)
  love.graphics.circle("line", x, y, Heal.radius, 48)
  -- A few crosses drifting up inside it.
  love.graphics.setLineWidth(3)
  for k = 0, 5 do
    local phase = (e.t * 0.6 + k / 6) % 1
    local ang = k * (2 * math.pi / 6) + math.floor(e.t * 0.6 + k / 6) * 1.7
    local r = Heal.radius * 0.65
    local cx, cy = x + math.cos(ang) * r, y + math.sin(ang) * r - phase * 40
    love.graphics.setColor(1, 1, 1, 0.8 * (1 - phase) * fade)
    love.graphics.line(cx - 6, cy, cx + 6, cy)
    love.graphics.line(cx, cy - 6, cx, cy + 6)
  end
  if e.t < 0.35 then
    -- The cast: a ring flashing out past the edge.
    local k = e.t / 0.35
    love.graphics.setLineWidth(3)
    love.graphics.setColor(0.85, 1, 0.9, 1 - k)
    love.graphics.circle("line", x, y, Heal.radius + k * 30, 48)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Heal
