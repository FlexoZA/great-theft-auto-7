-- Chicken: you go invisible. Press its key and, with a cluck and a burst
-- of feathers where you stood, nobody else can see you for a while: other
-- players don't draw you (your car too, if you are driving), no health bar
-- or name over you, no arrow or minimap dot, and nothing the world sends
-- after people (bots, police, bosses and their helpers) picks you out.
-- You still see yourself, with a shimmer round you and the seconds left.
-- A stray round or a blast that happens to find you still hurts. Firing a
-- gun gives you away: the first round that leaves it ends the chicken
-- there and then (the cooldown still runs from the cast). When it wears
-- off or you shoot, another burst of feathers shows where you are. Then it
-- waits out its cooldown. Nothing to aim (`aim = "self"`).
--
-- The host keeps who is hidden and answers `serverHidden` through the
-- abilities feature (`Features.visible` asks it); every client knows from
-- the cast (ABL_FIRED) and answers `hidden` the same way, so drawing and
-- targeting agree. A shot (weapons' `serverShotFired`) ends it on the host,
-- which tells everyone (ABL_REVEAL) so every client ends it too. Shotgun, the sniper boss, uses the same trick with his
-- own numbers (`Chicken.variant`, like Bigfoot's leap) and the same feathers.

local Features = require("src.features")

local Chicken = {
  key = "chicken", -- on the wire and in a bag ("ability-chicken")
  title = "chicken",
  blurb = "Go invisible until you shoot: nobody sees you and nothing hunts you. Stray rounds still hurt.",
  sound = "chicken",
  color = { 1, 0.82, 0.3 }, -- yolk
  aim = "self",
}

-- Tuning ------------------------------------------------------------------
Chicken.seconds = 20 -- how long you stay out of sight
Chicken.cooldown = 120 -- seconds from the cast before the next one
Chicken.range = 0 -- it is cast on yourself
Chicken.radius = 26 -- px: the burst of feathers
Chicken.afterglow = 0.8 -- seconds the feathers take to settle when you come back
Chicken.tierStats = { "seconds", "cooldown" } -- what a better tier improves, in order

local hiding = {} -- player id -> host time they come back into sight

-- Server --------------------------------------------------------------------

function Chicken.serverReset()
  hiding = {}
end

function Chicken.serverForget(player)
  hiding[player.id] = nil
end

--- Out of sight from now until the tier's `seconds` are up. Nobody is held.
function Chicken.serverCast(_server, caster, _x, _y, abilities, A)
  A = A or Chicken -- the chicken in the caster's tier
  hiding[caster.id] = abilities.sv.time + A.seconds
  return {}
end

--- Is player `id` out of sight at host time `now`?
function Chicken.serverHiding(id, now)
  local untilT = hiding[id]
  if untilT and untilT <= now then
    hiding[id] = nil
    return false
  end
  return untilT ~= nil
end

--- Bring player `id` back into sight at host time `now` (they fired).
--- Returns whether they were hiding.
function Chicken.serverReveal(id, now)
  local was = Chicken.serverHiding(id, now)
  hiding[id] = nil
  return was
end

--- Another chicken on the same trick with its own numbers (a boss's).
function Chicken.variant(tuning)
  local v = setmetatable({}, { __index = Chicken })
  for k, value in pairs(tuning) do
    v[k] = value
  end
  return v
end

-- Client --------------------------------------------------------------------

--- End effect `e`'s hiding now (its caster fired): the feathers of their
--- coming back start from here.
function Chicken.reveal(e)
  if Chicken.hiding(e) then
    e.seconds = e.t
  end
end

--- Is effect `e` a chicken still hiding its caster?
function Chicken.hiding(e)
  return e.ability.key == Chicken.key and e.t < e.seconds
end

--- A burst of feathers at (x, y), `t` seconds after it went up: a white
--- puff and a dozen feathers spinning outward and drifting down, gone by
--- `Chicken.afterglow`.
function Chicken.drawPuff(x, y, t, seed)
  local k = t / Chicken.afterglow
  if k >= 1 then
    return
  end
  seed = seed or 0
  love.graphics.setColor(1, 1, 1, 0.45 * (1 - k))
  love.graphics.circle("fill", x, y, Chicken.radius * (0.5 + k), 20)
  for i = 1, 12 do
    local a = i * 2.39996 + seed
    local d = Chicken.radius * (0.4 + k * (1.2 + (i % 3) * 0.3))
    local fx, fy = x + math.cos(a) * d, y + math.sin(a) * d + k * 14
    local spin = a + t * (6 + i % 4)
    local c = i % 4 == 0 and Chicken.color or { 0.97, 0.95, 0.9 }
    love.graphics.setColor(c[1], c[2], c[3], 1 - k)
    love.graphics.push()
    love.graphics.translate(fx, fy)
    love.graphics.rotate(spin)
    love.graphics.ellipse("fill", 0, 0, 4.5, 1.8, 8)
    love.graphics.pop()
  end
end

--- Feathers where they vanished; while it lasts, only the caster sees
--- anything more (a shimmer round themselves and the seconds left); then
--- feathers again where they come back.
function Chicken.drawEffect(e, client)
  local seed = (e.by or 0) * 1.7
  if e.t < Chicken.afterglow then
    Chicken.drawPuff(e.x, e.y, e.t, seed)
  end
  local x, y
  if client then
    x, y = Features.clientBodyPose(client, e.by)
  end
  if not x then
    return
  end
  if e.t >= e.seconds then
    Chicken.drawPuff(x, y, e.t - e.seconds, seed + 1)
  elseif client.myId == e.by then
    local c = Chicken.color
    local pulse = 0.5 + 0.5 * math.sin(e.t * 4)
    love.graphics.setLineWidth(2)
    for i = 0, 11 do -- a dashed ring, turning
      local a = e.t * 0.8 + i * math.pi / 6
      love.graphics.setColor(c[1], c[2], c[3], 0.35 + 0.35 * pulse)
      love.graphics.arc("line", "open", x, y, 24, a, a + math.pi / 12, 4)
    end
    love.graphics.setLineWidth(1)
    local left = math.ceil(e.seconds - e.t)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf(("hidden %ds"):format(left), x - 59, y + 29, 120, "center")
    love.graphics.setColor(c[1], c[2], c[3], 0.95)
    love.graphics.printf(("hidden %ds"):format(left), x - 60, y + 28, 120, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

return Chicken
