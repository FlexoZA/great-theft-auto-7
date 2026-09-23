-- Client-side officers on foot: the last snapshot from the server, eased
-- towards, and drawn. Nothing here changes the world; the host decides where
-- every officer stands and what they are aiming at (officers.lua).

local Officers = require("src.features.police.officers")

local Render = {
  officers = {}, -- id -> { x, y, dx, dy, angle, alert, hp, bob }
  lastTick = 0, -- newest POL_FOOT seen
  time = 0,
  alerted = {}, -- officers that drew their gun in the last sync()...
  alertedN = 0, -- ...and how many, so the table can be reused
}

local SMOOTHING = 11 -- per second, between the crowd's 10 and the car's 12
local SNAP = 150 -- px; a jump this big is a fresh officer, not a step
local BODY = 6.5
local HEAD = 3.5
local GUN = 9 -- px the barrel sticks out past the body
local MAX_HEALTH = Officers.HEALTH -- only used to size the damage bar over a wounded one

local UNIFORM = { 0.13, 0.18, 0.38 }
local VEST = { 0.30, 0.34, 0.46 }
local CAP = { 0.09, 0.12, 0.26 }
local SKIN = { 0.92, 0.78, 0.63 }

function Render.clear()
  Render.officers = {}
  Render.lastTick = 0
  Render.time = 0
  Render.alertedN = 0
end

function Render.remove(id)
  Render.officers[id] = nil
end

--- Apply a POL_FOOT payload: args[1] is the tick, then groups of six.
function Render.sync(args)
  local tick = tonumber(args[1])
  if not tick or tick <= Render.lastTick then
    return -- an unreliable packet that overtook a newer one
  end
  Render.lastTick = tick
  local officers = Render.officers
  local seen = {}
  Render.alertedN = 0
  for i = 2, #args - 5, 6 do
    local id = tonumber(args[i])
    local x, y, facing = tonumber(args[i + 1]), tonumber(args[i + 2]), tonumber(args[i + 3])
    if id and x and y and facing then
      local o = officers[id]
      if not o then
        o = { dx = x, dy = y, bob = love.math.random() * 6 }
        officers[id] = o
      end
      local alert = args[i + 4] == "1"
      if alert and not o.alert then
        -- Just spotted someone wanted: worth a whistle (init.lua decides).
        local n = Render.alertedN + 1
        local slot = Render.alerted[n]
        if not slot then
          slot = {}
          Render.alerted[n] = slot
        end
        slot.id, slot.x, slot.y = id, x, y
        Render.alertedN = n
      end
      o.x, o.y, o.angle, o.alert = x, y, facing, alert
      o.hp = tonumber(args[i + 5]) or MAX_HEALTH
      seen[id] = true
    end
  end
  for id in pairs(officers) do
    if not seen[id] then
      officers[id] = nil -- off duty, or too far away to matter
    end
  end
end

function Render.update(dt)
  Render.time = Render.time + dt
  local k = math.min(1, dt * SMOOTHING)
  for _, o in pairs(Render.officers) do
    local ex, ey = o.x - o.dx, o.y - o.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      o.dx, o.dy = o.x, o.y
    else
      local mx, my = ex * k, ey * k
      o.dx, o.dy = o.dx + mx, o.dy + my
      o.running = mx * mx + my * my > (dt * 90) ^ 2
    end
  end
end

--- Every officer inside the view: a navy figure with a peaked cap, the same
--- waddle the crowd has, and a drawn pistol while they are hunting someone.
--- `flash` is the feature's shared strobe clock, so the radio light on a
--- hunting officer blinks in time with the patrol cars' lights.
function Render.draw(camera, flash)
  local w, h = love.graphics.getDimensions()
  local scale = camera.scale or 1
  local halfW, halfH = w / (2 * scale) + 30, h / (2 * scale) + 30
  local t = Render.time
  local phase = math.floor(flash * 9) % 2 == 0

  for _, o in pairs(Render.officers) do
    local x, y = o.dx, o.dy
    if math.abs(x - camera.x) < halfW and math.abs(y - camera.y) < halfH then
      local fx, fy = math.cos(o.angle), math.sin(o.angle)
      local swing = math.sin(t * (o.running and 15 or 7) + o.bob) * (o.running and 1.4 or 0.9)
      local sx, sy = -fy * swing, fx * swing

      love.graphics.setColor(0, 0, 0, 0.3)
      love.graphics.circle("fill", x + 2, y + 2, BODY, 10)
      love.graphics.setColor(UNIFORM)
      love.graphics.circle("fill", x + sx, y + sy, BODY, 10)
      -- Stab vest across the shoulders, lighter than the uniform.
      love.graphics.setColor(VEST)
      love.graphics.setLineWidth(2)
      love.graphics.line(x - fy * 4 + sx, y + fx * 4 + sy, x + fy * 4 + sx, y - fx * 4 + sy)

      if o.alert then
        love.graphics.setColor(0.12, 0.12, 0.15)
        love.graphics.line(x + fx * BODY, y + fy * BODY, x + fx * (BODY + GUN), y + fy * (BODY + GUN))
      end
      love.graphics.setLineWidth(1)

      love.graphics.setColor(SKIN)
      love.graphics.circle("fill", x + fx * 1.6 + sx * 0.5, y + fy * 1.6 + sy * 0.5, HEAD, 8)
      love.graphics.setColor(CAP)
      love.graphics.circle("fill", x + fx * 0.6 + sx * 0.5, y + fy * 0.6 + sy * 0.5, HEAD - 0.6, 8)

      if o.alert then
        -- Shoulder radio, blinking red then blue like the cars.
        if phase then
          love.graphics.setColor(1, 0.25, 0.25, 0.95)
        else
          love.graphics.setColor(0.35, 0.55, 1, 0.95)
        end
        love.graphics.circle("fill", x - fy * 5 - fx * 3, y + fx * 5 - fy * 3, 1.8, 6)
      end

      local hp = o.hp or MAX_HEALTH
      if hp < MAX_HEALTH then
        local bw = 16
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", x - bw / 2 - 1, y - 14, bw + 2, 4)
        love.graphics.setColor(1 - hp / MAX_HEALTH, hp / MAX_HEALTH, 0.2)
        love.graphics.rectangle("fill", x - bw / 2, y - 13, bw * hp / MAX_HEALTH, 2)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Render
