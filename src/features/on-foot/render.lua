-- Client-side figures for the players who are out of their car: the last
-- snapshot from the server, eased towards, and drawn. Nothing here changes
-- the world. The local player's own figure is predicted in init.lua, which
-- writes straight into its dx, dy; everyone else is smoothed here.

local Car = require("src.car")
local UI = require("src.ui")

local Render = {
  figures = {}, -- player id -> { x, y, dx, dy, angle, stamina, sprinting, bob }
  events = {}, -- player id -> server tick of the last OF_OUT / OF_IN applied
  lastTick = 0, -- newest OF_STATE seen
  time = 0,
}

local SMOOTHING = 12 -- per second, matching the car smoothing in the game state
local SNAP = 150 -- px; a jump this big is a teleport, not a step
local BODY = 6 -- px, body radius
local HEAD = 3.5
local GUN = 9 -- px the barrel sticks out past the body
local SKIN = { 0.92, 0.78, 0.63 }

function Render.clear()
  Render.figures = {}
  Render.events = {}
  Render.lastTick = 0
  Render.time = 0
end

function Render.get(id)
  return Render.figures[id]
end

--- Somebody stepped out of their car; start drawing them right away rather
--- than waiting for the next OF_STATE. `tick` is the server tick the news is
--- from, so an unreliable snapshot that overtook it can't undo it.
function Render.spawn(id, x, y, angle, tick)
  Render.events[id] = tick or Render.events[id]
  Render.figures[id] = {
    x = x,
    y = y,
    dx = x,
    dy = y,
    angle = angle or 0,
    stamina = 100,
    sprinting = false,
    bob = love.math.random() * 6,
  }
  return Render.figures[id]
end

function Render.remove(id, tick)
  Render.events[id] = tick or Render.events[id]
  Render.figures[id] = nil
end

--- Apply an OF_STATE payload: args[1] is the tick, then groups of five.
--- Positions are the server's truth; dx, dy stay where they are and ease
--- towards them in update(). Anyone the snapshot doesn't mention got back in
--- their car, unless we already know something newer about them.
function Render.sync(args)
  local tick = tonumber(args[1])
  if not tick or tick <= Render.lastTick then
    return -- an unreliable packet that overtook a newer one
  end
  Render.lastTick = tick
  local seen = {}
  for i = 2, #args - 4, 5 do
    local id = tonumber(args[i])
    local x, y = tonumber(args[i + 1]), tonumber(args[i + 2])
    local angle, stamina = tonumber(args[i + 3]), tonumber(args[i + 4])
    -- Strictly newer than the last OF_OUT/OF_IN: a snapshot from the same
    -- tick as a removal was built before the death and must not undo it.
    if id and x and y and angle and (Render.events[id] or -1) < tick then
      local p = Render.figures[id] or Render.spawn(id, x, y, angle)
      p.x, p.y, p.angle = x, y, angle
      p.stamina = stamina or p.stamina
      seen[id] = true
    end
  end
  for id in pairs(Render.figures) do
    if not seen[id] and (Render.events[id] or -1) < tick then
      Render.figures[id] = nil
    end
  end
end

--- Ease everyone except `myId` towards their last known position.
function Render.update(dt, myId)
  Render.time = Render.time + dt
  local k = math.min(1, dt * SMOOTHING)
  for id, p in pairs(Render.figures) do
    if id ~= myId then
      local ex, ey = p.x - p.dx, p.y - p.dy
      if ex * ex + ey * ey > SNAP * SNAP then
        p.dx, p.dy = p.x, p.y
      else
        local mx, my = ex * k, ey * k
        p.dx, p.dy = p.dx + mx, p.dy + my
        p.sprinting = mx * mx + my * my > (dt * 90) ^ 2
      end
    end
  end
end

--- Everyone on foot inside the view. Two circles and a barrel each, in the
--- colour of the car they climbed out of.
function Render.draw(client, camera)
  local w, h = love.graphics.getDimensions()
  local scale = camera.scale or 1
  local halfW, halfH = w / (2 * scale) + 40, h / (2 * scale) + 40
  local t = Render.time

  love.graphics.setFont(UI.fonts.small)
  for id, p in pairs(Render.figures) do
    local x, y = p.dx, p.dy
    if math.abs(x - camera.x) < halfW and math.abs(y - camera.y) < halfH then
      local fx, fy = math.cos(p.angle), math.sin(p.angle)
      -- Sway across the direction the body faces: the same waddle the crowd
      -- has, quicker while sprinting.
      local swing = math.sin(t * (p.sprinting and 16 or 8) + p.bob) * (p.sprinting and 1.5 or 0.9)
      local sx, sy = -fy * swing, fx * swing

      love.graphics.setColor(0, 0, 0, 0.3)
      love.graphics.circle("fill", x + 2, y + 2, BODY, 10)
      love.graphics.setColor(Car.colorFor(id))
      love.graphics.circle("fill", x + sx, y + sy, BODY, 10)
      love.graphics.setColor(0.12, 0.12, 0.15)
      love.graphics.setLineWidth(2)
      love.graphics.line(x + fx * BODY, y + fy * BODY, x + fx * (BODY + GUN), y + fy * (BODY + GUN))
      love.graphics.setLineWidth(1)
      love.graphics.setColor(SKIN)
      love.graphics.circle("fill", x + fx * 1.6 + sx * 0.5, y + fy * 1.6 + sy * 0.5, HEAD, 8)

      local player = client.players[id]
      if player then
        love.graphics.setColor(1, 1, 1, id == client.myId and 1 or 0.8)
        love.graphics.printf(player.name, x - 60, y - 30, 120, "center")
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Render
