-- How Hyperbole's drones think (docs/borderline.md, "The army"): a small
-- yellow disc on four rotors that keeps the haulers going, and never
-- fights itself. Two of them, one brain:
--
--   FIX  the medic drone: tends the most hurt hauler near it, healing it
--        along its beam (`HEAL` a second)
--   SHD  the shield drone: tends a hauler with no shield (one in a fight
--        first), gives it a bubble (`SHIELD` points: the army's rounds
--        hit the bubble first, chassis.lua) and keeps it topped up while
--        the beam holds; a bubble nobody tends fades
--
-- It flies over everything, hangs a little behind whoever it tends, out of
-- the line of fire, and drifts about its spot with nobody to tend. It is
-- fragile, and anyone can shoot it: shoot it first. army.lua draws its
-- beam from `s.link` (the hauler it tends).

local Chassis = require("src.features.borderline.chassis")

local Brain = {}

Brain.LEGS = false
Brain.RADIUS = 14 -- px: drawn 1.5 times its 9 (drone_look.lua's SCALE), easier to hit

Brain.CONF = {
  health = 25,
  speed = 150, -- px/s
  range = 0, -- it doesn't look for players
  aware = 0,
  fov = 0,
  aim = 0,
}

Brain.SEEK = 700 -- px round it it looks for somebody to tend
Brain.BEAM = 150 -- px its beam reaches
Brain.BEHIND = 60 -- px behind whoever it tends it hangs
Brain.HEAL = 12 -- health a second (FIX)
Brain.SHIELD = 80 -- the bubble's points (SHD)...
Brain.TOP_UP = 20 -- ...topped up this much a second while the beam holds
Brain.FADE = 10 -- points a second a bubble nobody tends loses

function Brain.init(s)
  s.hover = true -- flies: never walks into a wall, never stopped by one
end

function Brain.wake() end

function Brain.hurt() end

--- Is `o` a hauler drone `s` could tend?
local function wants(s, o)
  if o.brain == Brain or o.flying or o.crawl or Chassis.dist2(o.x, o.y, s.x, s.y) > Brain.SEEK * Brain.SEEK then
    return false
  end
  if s.code == "FIX" then
    return o.hp < o.max
  end
  return (o.shield or 0) < Brain.SHIELD
end

--- Who it tends next: FIX the most hurt, SHD one in a fight before one
--- that isn't, then the nearest.
local function pick(roster, s)
  local best, bestScore = nil, math.huge
  for _, o in ipairs(roster.list) do
    if wants(s, o) then
      local score = Chassis.dist2(o.x, o.y, s.x, s.y) / 1e6
      if s.code == "FIX" then
        score = score + o.hp / o.max
      elseif not o.target then
        score = score + 1
      end
      if score < bestScore then
        best, bestScore = o, score
      end
    end
  end
  return best
end

--- Fly straight for (x, y), over anything, inside the map.
local function flyTo(roster, s, x, y, dt)
  local dx, dy = x - s.x, y - s.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d > 1 then
    local k = math.min(d, s.conf.speed * dt) / d
    s.x, s.y = s.x + dx * k, s.y + dy * k
    s.facing = Chassis.turn(s.facing, math.atan2(dy, dx), Chassis.TURN, dt)
  end
  local b = roster.bounds
  if b then
    s.x, s.y = math.max(b.x0 + 32, math.min(b.x1 - 32, s.x)), math.max(b.y0 + 32, math.min(b.y1 - 32, s.y))
  end
  return d
end

function Brain.think(roster, _server, s, dt)
  local ward = nil
  for _, o in ipairs(roster.list) do
    if o.id == s.link then
      ward = o
    end
  end
  if not ward or not wants(s, ward) or (s.code == "FIX" and ward.hp >= ward.max) then
    ward = pick(roster, s)
  end
  s.link = ward and ward.id or nil
  if not ward then
    local a = roster.time * 0.7 + s.id -- a slow circle round its spot
    flyTo(roster, s, s.homeX + math.cos(a) * 50, s.homeY + math.sin(a) * 50, dt)
    return
  end
  local back = ward.facing + math.pi + math.sin(roster.time + s.id) * 0.6
  flyTo(roster, s, ward.x + math.cos(back) * Brain.BEHIND, ward.y + math.sin(back) * Brain.BEHIND, dt)
  if Chassis.dist2(s.x, s.y, ward.x, ward.y) > Brain.BEAM * Brain.BEAM then
    s.beaming = nil
    return
  end
  s.beaming = true
  if s.code == "FIX" then
    ward.hp = math.min(ward.max, ward.hp + Brain.HEAL * dt)
  else
    ward.shield = math.min(Brain.SHIELD, (ward.shield or 0) > 0 and ward.shield + Brain.TOP_UP * dt or Brain.SHIELD)
    ward.shieldedAt = roster.time
  end
end

--- Every bubble nobody has tended for a moment fades (army.lua, every tick).
function Brain.fade(roster, dt)
  for _, o in ipairs(roster.list) do
    if o.shield and roster.time - (o.shieldedAt or 0) > 0.5 then
      o.shield = o.shield > Brain.FADE * dt and o.shield - Brain.FADE * dt or nil
    end
  end
end

return Brain
