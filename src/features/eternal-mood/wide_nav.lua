-- The walking grid for something big (a boss a good deal wider than the
-- 12 px the level's grid is cut for, d-day/nav.lua's CLEARANCE): the same
-- grid, but a cell is only open when he fits at its middle too, so a way
-- found on it never sends him down a gap or round a corner his hull won't
-- take. Doors still count: when the level's grid works a cell out again (a
-- blast door opening, terminals.lua), what he fits through is worked out
-- afresh as well.
--
--   local wide = WideNav.of(nav, radius)   -- one per grid and size, kept
--   wide:path(x0, y0, x1, y1)              -- as nav:path, on cells he fits

local Ground = require("src.features.eternal-mood.ground")

local WideNav = {}

WideNav.EASE = 0.8 -- of his radius he must fit at a cell's middle: his walk slides him along the rest

--- The grid `nav` as something `radius` px across the shoulders walks it.
function WideNav.of(nav, radius)
  local sizes = nav.wide -- { [radius] = wide grid }, kept on the level's grid and gone with it
  if not sizes then
    sizes = {}
    nav.wide = sizes
    local refresh = nav.refresh
    nav.refresh = function(self, ...) -- a door: forget what fitted, all sizes
      refresh(self, ...)
      for _, wide in pairs(sizes) do
        wide.fit = {}
      end
    end
  end
  if sizes[radius] then
    return sizes[radius]
  end
  local r = radius * WideNav.EASE
  local wide = setmetatable({ fit = {} }, { __index = nav })
  function wide:isOpen(c, row)
    if not nav:isOpen(c, row) then
      return false
    end
    local key = row * nav.cols + c
    local fits = self.fit[key]
    if fits == nil then
      local x, y = nav:centre(c, row)
      fits = Ground.fits(x, y, r)
      self.fit[key] = fits
    end
    return fits
  end
  sizes[radius] = wide
  return wide
end

return WideNav
