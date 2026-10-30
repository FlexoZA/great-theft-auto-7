-- The arc haulers' domes (arc_brain.lua; docs/borderline.md, "The army"):
-- a dome of blue light thrown up round an arc hauler for a few seconds.
-- Rounds from outside stop at it: none of the army under it can be hurt
-- by somebody standing outside (`Domes.shields`, army.lua asks before a
-- round lands). Whoever stands inside is zapped every second (shock), and
-- from inside their rounds hit. The dome moves with the hauler and drops
-- when it goes down.
--
-- Messages
--   server -> all  HYP_DOME <id> <seconds>   hauler `id` threw its dome up for that long

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Arc = require("src.features.borderline.arc_brain")
local Hauler = require("src.features.borderline.hauler_look")

local Domes = {}

Domes.ZAP_EVERY = 1 -- seconds between zaps inside

-- Server --------------------------------------------------------------------

local function inside(x, y, s)
  local r = Arc.DOME.radius
  return (x - s.x) ^ 2 + (y - s.y) ^ 2 <= r * r
end

--- Is `target` (one of the army) under a dome that player `by` is outside of?
function Domes.shields(server, roster, target, by)
  local p = server.players[by]
  if not p then
    return false
  end
  local px, py = Features.bodyPose(server, p)
  for _, s in ipairs(roster.list) do
    if s.dome and inside(target.x, target.y, s) and not inside(px, py, s) then
      return true
    end
  end
  return false
end

--- Tell everyone about new domes; zap whoever stands in one.
function Domes.serverStep(server, roster, dt)
  local weapons = Features.byName.weapons
  for _, s in ipairs(roster.list) do
    if s.domed then
      s.domed, s.zapIn = nil, Domes.ZAP_EVERY
      server:broadcast(Protocol.encode("HYP_DOME", s.id, ("%.1f"):format(s.dome)))
    end
    if s.dome then
      s.zapIn = s.zapIn - dt
      if s.zapIn <= 0 then
        s.zapIn = Domes.ZAP_EVERY
        for _, p in pairs(server.players) do
          if Features.visible(server, p) and weapons and weapons.serverDamage then
            local px, py = Features.bodyPose(server, p)
            if inside(px, py, s) then
              weapons:serverDamage(server, p, nil, Arc.DOME.zap, math.atan2(py - s.y, px - s.x), "shock")
            end
          end
        end
      end
    end
  end
end

-- Client --------------------------------------------------------------------

local up = {} -- hauler id -> seconds left

function Domes.clear()
  up = {}
end

function Domes.update(dt)
  for id, t in pairs(up) do
    up[id] = t > dt and t - dt or nil
  end
end

--- Each dome over its hauler (`at(id)` gives where it is shown, or nil).
function Domes.draw(at, clock)
  local c, hot = Hauler.C.arc, Hauler.C.arcHot
  local r = Arc.DOME.radius
  for id, t in pairs(up) do
    local x, y = at(id)
    if x then
      local fade = math.min(1, t * 2) -- it flickers out over the last half second
      love.graphics.setColor(c[1], c[2], c[3], 0.14 * fade)
      love.graphics.circle("fill", x, y, r, 40)
      love.graphics.setColor(hot[1], hot[2], hot[3], (0.5 + 0.3 * math.sin(clock * 20)) * fade)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", x, y, r, 40)
      for k = 0, 5 do -- arcs crawling over it
        local a = clock * 1.3 + k * math.pi / 3
        love.graphics.arc("line", "open", x, y, r * (0.4 + 0.1 * k), a, a + 0.6, 6)
      end
      love.graphics.setLineWidth(1)
    end
  end
end

Domes.clientMessages = {
  HYP_DOME = function(_client, args)
    local id, t = tonumber(args[1]), tonumber(args[2])
    if id and t then
      up[id] = t
    end
  end,
}

return Domes
