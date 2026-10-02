-- A walking grid for soldiers going somewhere they can't see from where
-- they stand (City 17's, going to look into something): the ground cut into
-- CELL squares, each open or not, and A* across them. A cell is shut when a
-- soldier standing in it would touch a wall (every feature's `blocksPoint`,
-- the same rule troops walk and see by). The path comes back as a few
-- corners, each one in plain sight of the next, so he walks it in straight
-- lines.
--
-- Built once for a level (Nav.build), on the host only.

local Features = require("src.features")

local Nav = {}
Nav.__index = Nav

Nav.CELL = 32 -- px on a side
Nav.CLEARANCE = 12 -- px a soldier keeps from a wall: his radius and a little
Nav.MAX_NODES = 6000 -- cells A* may open before giving up on a path

local SQRT2 = math.sqrt(2)

local function blocked(x, y)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint and f:blocksPoint(x, y) then
      return true
    end
  end
  return false
end

--- The grid over `bounds` ({ x, y, w, h }, the world's playing area).
function Nav.build(bounds)
  local C = Nav.CELL
  local cols, rows = math.ceil(bounds.w / C), math.ceil(bounds.h / C)
  local self = setmetatable({ x0 = bounds.x, y0 = bounds.y, cols = cols, rows = rows, open = {} }, Nav)
  local r, d = Nav.CLEARANCE, Nav.CLEARANCE * 0.7
  for c = 0, cols - 1 do
    for row = 0, rows - 1 do
      local x, y = self.x0 + (c + 0.5) * C, self.y0 + (row + 0.5) * C
      local shut = blocked(x, y)
        or blocked(x - r, y) or blocked(x + r, y) or blocked(x, y - r) or blocked(x, y + r)
        or blocked(x - d, y - d) or blocked(x + d, y - d) or blocked(x - d, y + d) or blocked(x + d, y + d)
      self.open[row * cols + c] = not shut
    end
  end
  return self
end

function Nav:cellOf(x, y)
  return math.floor((x - self.x0) / Nav.CELL), math.floor((y - self.y0) / Nav.CELL)
end

function Nav:isOpen(c, r)
  return c >= 0 and r >= 0 and c < self.cols and r < self.rows and self.open[r * self.cols + c]
end

function Nav:centre(c, r)
  return self.x0 + (c + 0.5) * Nav.CELL, self.y0 + (r + 0.5) * Nav.CELL
end

--- The open cell nearest (x, y), looking a few cells out: where he stands
--- may be shut when he is brushing a wall, and so may what he is going to.
function Nav:nearestOpen(x, y)
  local c0, r0 = self:cellOf(x, y)
  for ring = 0, 3 do
    local best, bestD2
    for c = c0 - ring, c0 + ring do
      for r = r0 - ring, r0 + ring do
        if self:isOpen(c, r) then
          local cx, cy = self:centre(c, r)
          local d2 = (cx - x) ^ 2 + (cy - y) ^ 2
          if not bestD2 or d2 < bestD2 then
            best, bestD2 = { c, r }, d2
          end
        end
      end
    end
    if best then
      return best[1], best[2]
    end
  end
  return nil
end

--- Is the straight line between two points over open cells all the way?
function Nav:clear(x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.ceil(math.sqrt(dx * dx + dy * dy) / (Nav.CELL / 4))
  for i = 0, n do
    local k = n == 0 and 0 or i / n
    if not self:isOpen(self:cellOf(x0 + dx * k, y0 + dy * k)) then
      return false
    end
  end
  return true
end

-- A binary heap of { f, key } for the open set.
local function push(heap, f, key)
  local i = #heap + 1
  heap[i] = { f, key }
  while i > 1 do
    local p = math.floor(i / 2)
    if heap[p][1] <= heap[i][1] then
      break
    end
    heap[p], heap[i] = heap[i], heap[p]
    i = p
  end
end

local function pop(heap)
  local top = heap[1]
  local last = table.remove(heap)
  if #heap > 0 then
    heap[1] = last
    local i = 1
    while true do
      local l, r, m = i * 2, i * 2 + 1, i
      if heap[l] and heap[l][1] < heap[m][1] then
        m = l
      end
      if heap[r] and heap[r][1] < heap[m][1] then
        m = r
      end
      if m == i then
        break
      end
      heap[m], heap[i] = heap[i], heap[m]
      i = m
    end
  end
  return top[2]
end

local STEPS = { { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
  { 1, 1, SQRT2 }, { 1, -1, SQRT2 }, { -1, 1, SQRT2 }, { -1, -1, SQRT2 } }

--- A way from (x0, y0) to (x1, y1): a list of { x, y } corners, the last
--- one (x1, y1) itself (or the nearest open spot to it), and its length in
--- px. Nil when there is none.
function Nav:path(x0, y0, x1, y1)
  local sc, sr = self:nearestOpen(x0, y0)
  local gc, gr = self:nearestOpen(x1, y1)
  if not (sc and gc) then
    return nil
  end
  local cols = self.cols
  local start, goal = sr * cols + sc, gr * cols + gc
  local g, from, closed = { [start] = 0 }, {}, {}
  local heap = {}
  local function h(c, r)
    local dc, dr = math.abs(c - gc), math.abs(r - gr)
    return (math.max(dc, dr) + (SQRT2 - 1) * math.min(dc, dr)) * Nav.CELL
  end
  push(heap, h(sc, sr), start)
  local opened = 0
  local found = false
  while #heap > 0 do
    local key = pop(heap)
    if key == goal then
      found = true
      break
    end
    if not closed[key] then
      closed[key] = true
      opened = opened + 1
      if opened > Nav.MAX_NODES then
        return nil
      end
      local c, r = key % cols, math.floor(key / cols)
      for _, st in ipairs(STEPS) do
        local nc, nr = c + st[1], r + st[2]
        -- No cutting a corner: both cells beside a diagonal must be open too.
        if self:isOpen(nc, nr) and (st[3] == 1 or (self:isOpen(nc, r) and self:isOpen(c, nr))) then
          local nk = nr * cols + nc
          local ng = g[key] + st[3] * Nav.CELL
          if not closed[nk] and (not g[nk] or ng < g[nk]) then
            g[nk], from[nk] = ng, key
            push(heap, ng + h(nc, nr), nk)
          end
        end
      end
    end
  end
  if not found then
    return nil
  end
  -- Back from the goal to the start, cell by cell...
  local cells = {}
  local key = goal
  while key do
    table.insert(cells, 1, key)
    key = from[key]
  end
  local pts = {}
  for i, k in ipairs(cells) do
    local x, y = self:centre(k % cols, math.floor(k / cols))
    pts[i] = { x = x, y = y }
  end
  if self:isOpen(self:cellOf(x1, y1)) then
    pts[#pts] = { x = x1, y = y1 }
  end
  -- ...then only the corners: from each, on to the furthest one in plain sight.
  local corners, length = {}, 0
  local ax, ay, i = x0, y0, 1
  while i <= #pts do
    local j = #pts
    while j > i and not self:clear(ax, ay, pts[j].x, pts[j].y) do
      j = j - 1
    end
    corners[#corners + 1] = pts[j]
    length = length + math.sqrt((pts[j].x - ax) ^ 2 + (pts[j].y - ay) ^ 2)
    ax, ay, i = pts[j].x, pts[j].y, j + 1
  end
  return corners, length
end

return Nav
