-- Pictures of the world past a map's edge, kept so they are not drawn
-- again every frame: square pieces of it (chunks) drawn once each into a
-- canvas at half resolution, as the map's own canvas is, and drawn back
-- doubled. A few are made a frame as the camera finds them; past `max` the
-- one looked at least lately gives up its canvas to the new one. A chunk
-- wholly inside the map is never made (the map's canvas lands on top).
-- The Outer City's and the Winding Road's surroundings use it.

local Chunks = {}
Chunks.__index = Chunks

--- A cache of chunks `size` px of world each way, at most `max` of them,
--- `perFrame` new ones a frame.
function Chunks.new(size, max, perFrame)
  return setmetatable({ size = size, max = max, perFrame = perFrame, map = nil, list = {}, count = 0, tick = 0 },
    Chunks)
end

--- Forget every chunk (a different map).
function Chunks:reset(map)
  for _, ch in pairs(self.list) do
    ch.canvas:release()
  end
  self.map, self.list, self.count = map, {}, 0
end

--- A canvas for a new chunk: a fresh one, or the stalest one's.
function Chunks:canvas()
  if self.count < self.max then
    self.count = self.count + 1
    local canvas = love.graphics.newCanvas(self.size / 2, self.size / 2)
    canvas:setFilter("nearest", "nearest")
    return canvas
  end
  local stalest
  for key, ch in pairs(self.list) do
    if not stalest or ch.tick < self.list[stalest].tick then
      stalest = key
    end
  end
  local canvas = self.list[stalest].canvas
  self.list[stalest] = nil
  return canvas
end

--- Draw chunk (cx, cy) into a canvas with `paint(x0, y0, x1, y1)`, world px.
function Chunks:make(cx, cy, paint)
  local canvas = self:canvas()
  local S = self.size
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.scale(0.5)
  love.graphics.translate(-cx * S, -cy * S)
  paint(cx * S, cy * S, cx * S + S, cy * S + S)
  love.graphics.setCanvas()
  love.graphics.pop()
  return { canvas = canvas, tick = self.tick }
end

--- Draw every chunk of `map`'s surroundings in the box (left, top, right,
--- bottom), making the missing ones with `paint` while the frame allows;
--- one not made yet leaves whatever was drawn under it showing.
function Chunks:draw(map, left, top, right, bottom, paint)
  if self.map ~= map then
    self:reset(map)
  end
  local S = self.size
  local made = 0
  local mx0, my0, mx1, my1 = map.left, map.top, map.left + map.w, map.top + map.h
  love.graphics.setColor(1, 1, 1)
  for cx = math.floor(left / S), math.floor(right / S) do
    for cy = math.floor(top / S), math.floor(bottom / S) do
      local x, y = cx * S, cy * S
      if not (x >= mx0 and y >= my0 and x + S <= mx1 and y + S <= my1) then
        local key = cx .. "," .. cy
        local ch = self.list[key]
        if not ch and made < self.perFrame then
          ch = self:make(cx, cy, paint)
          self.list[key] = ch
          made = made + 1
        end
        if ch then
          self.tick = self.tick + 1
          ch.tick = self.tick
          love.graphics.setColor(1, 1, 1)
          love.graphics.draw(ch.canvas, x, y, 0, 2, 2)
        end
      end
    end
  end
end

return Chunks
