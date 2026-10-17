-- Shadows for what stops a round. Everything that no round goes over stands
-- up out of the ground and throws a shadow across it, so a player can tell
-- a wall from paint; what rounds do go over (water, a bridge's railing,
-- lava) is drawn flat. The light is from the top left (north west) on every
-- map, so shadows fall south and east.
--
-- Two helpers the map renderers share:
--   Shade.edges  the walls round the ground (every tile no one stands on,
--                `buildWalls` in layout.lua: mountains, the drop, the slabs
--                between the tower's floors, past the map's edge) shading
--                the ground to their south and east
--   Shade.box    one standing thing's shadow, its footprint pushed south east

local Shade = {}

Shade.SOUTH = 36 -- px a wall's shadow reaches across the ground to its south
Shade.EAST = 16 -- px to its east
Shade.ALPHA = 0.4

--- Is (c, r) a wall: no tile there at all?
local function wall(map, c, r)
  local col = map.tiles[c]
  return col == nil or col[r] == nil
end

--- The walls' shadows over `map`'s ground, `T` the tile size: a strip
--- along the top of each tile with a wall to its north (deeper next to
--- the wall, fading out) and along the left of each with a wall to its west.
--- `opts` (optional): `south` and `east` change how far they reach, and
--- `wall(map, c, r)` says which tiles throw one, when it isn't every tile
--- left empty (a map whose roofs throw shadows of their own leaves those out).
function Shade.edges(map, T, opts)
  opts = opts or {}
  local south, east = opts.south or Shade.SOUTH, opts.east or Shade.EAST
  local isWall = opts.wall or wall
  local a = Shade.ALPHA
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if not wall(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        if isWall(map, c, r - 1) then
          love.graphics.setColor(0, 0, 0, a)
          love.graphics.rectangle("fill", x, y, T, south * 0.55)
          love.graphics.setColor(0, 0, 0, a * 0.5)
          love.graphics.rectangle("fill", x, y + south * 0.55, T, south * 0.45)
        end
        if isWall(map, c - 1, r) then
          love.graphics.setColor(0, 0, 0, a * 0.75)
          love.graphics.rectangle("fill", x, y, east, T)
        elseif isWall(map, c - 1, r - 1) and not isWall(map, c, r - 1) then
          -- A wall's corner off to the north west: its shadow comes round it.
          love.graphics.setColor(0, 0, 0, a * 0.75)
          love.graphics.rectangle("fill", x, y, east, south * 0.55)
        end
      end
    end
  end
end

--- The shadow of something standing on `s`'s footprint, pushed `d` px
--- (default 6) south east.
function Shade.box(s, d)
  d = d or 6
  love.graphics.setColor(0, 0, 0, Shade.ALPHA)
  love.graphics.rectangle("fill", s.x + d, s.y + d, s.w, s.h)
end

return Shade
