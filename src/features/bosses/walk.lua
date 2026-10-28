-- How a boss gets about on foot without getting stuck (the standard's point
-- 10, bosses/init.lua): the steering every boss walks with, whatever its
-- feature. What stops a walker differs from feature to feature (walls; the
-- lava in Heck; the water on the Winding Road), so each passes its own
-- `blocked(x, y)`: true where nothing of its kind can stand.
--
--   Walk.fits(blocked, x, y, r)              does a walker `r` px across fit at (x, y)?
--   Walk.step(w, blocked, angle, speed, dt, r, headlong)
--                                            move w ({ x, y, stuck, feel }) a tick along `angle`
--   Walk.wideClear(blocked, x0, y0, x1, y1, r)  straight there, its whole width?
--   Walk.nav(nav, blocked, r)                the walking grid (d-day/nav.lua) as it fits through it
--   Walk.route(w, nav, x, y, time)           the way to walk towards (x, y) on it (it turns, or not, itself)
--
-- The three ways a walker got stuck, and what this does about each:
--   * a slide along a wall of next to nothing (a heading nearly square to
--     it) counted as moving, so it never tried anything else: a slide must
--     make SLIDE of a step, or it feels round the corner instead;
--   * feeling the same side first every tick rocked it on the spot at a
--     corridor's mouth: it feels away from the shoulder against something,
--     keeping to the side it chose while it can't tell;
--   * the walking grid is cut for 12 px walkers (d-day/nav.lua's
--     CLEARANCE), so it sent anything wider down gaps and round corners it
--     doesn't fit: Walk.nav keeps only the cells its body fits.
--
-- Host only.

local Walk = {}

-- Tuning ------------------------------------------------------------------
Walk.SLIDE = 0.3 -- of a step a slide along a wall must make, or it is no way on and the walker feels round instead
Walk.EASE = 0.8 -- of its radius a walker must fit at a grid cell's middle (its walk slides it along the rest)
Walk.SAMPLE = 8 -- px between the points a straight line is checked at
Walk.ARRIVE = 20 -- px from a corner of its way that counts as there
Walk.REPLAN = 1.2 -- seconds a way is followed before it is worked out again
Walk.MOVED = 80 -- px the place it is going to may move before the way is worked out again

--- Does a walker `r` px across fit at (x, y): nothing that stops it under
--- its middle or round its edge?
function Walk.fits(blocked, x, y, r)
  local c = r * 0.7
  return not (blocked(x, y) or blocked(x - r, y) or blocked(x + r, y) or blocked(x, y - r) or blocked(x, y + r)
    or blocked(x - c, y - c) or blocked(x + c, y - c) or blocked(x - c, y + c) or blocked(x + c, y + c))
end

--- Move walker `w` ({ x, y, stuck, feel }, `r` px across) along `angle` at
--- `speed` for `dt`, sliding along walls and feeling its way round a corner
--- it catches on: a little to one side, then square to it. `headlong` (a
--- charge) only slides: it goes into the wall. Returns false, counting
--- `w.stuck` up, when it got nowhere.
function Walk.step(w, blocked, angle, speed, dt, r, headlong)
  local step = speed * dt
  local mx, my = math.cos(angle) * step, math.sin(angle) * step
  local slide = Walk.SLIDE * step
  if Walk.fits(blocked, w.x + mx, w.y + my, r) then
    w.x, w.y = w.x + mx, w.y + my
  elseif math.abs(mx) >= slide and Walk.fits(blocked, w.x + mx, w.y, r) then
    w.x = w.x + mx
  elseif math.abs(my) >= slide and Walk.fits(blocked, w.x, w.y + my, r) then
    w.y = w.y + my
  else
    local moved = false
    if not headlong then
      -- Feel to this side first: away from the shoulder more against
      -- things; the side it was feeling to already when it can't tell.
      local against = 0
      for k = 1, 3 do
        local d = k * math.pi / 6
        against = against + (blocked(w.x + math.cos(angle + d) * (r + 2), w.y + math.sin(angle + d) * (r + 2))
          and 1 or 0) - (blocked(w.x + math.cos(angle - d) * (r + 2), w.y + math.sin(angle - d) * (r + 2))
          and 1 or 0)
      end
      local s = against > 0 and -1 or against < 0 and 1 or w.feel or 1
      local q = math.pi / 4
      for _, off in ipairs({ s * q, -s * q, s * 2 * q, -s * 2 * q }) do
        local fx, fy = w.x + math.cos(angle + off) * step, w.y + math.sin(angle + off) * step
        if Walk.fits(blocked, fx, fy, r) then
          w.x, w.y, moved, w.feel = fx, fy, true, off > 0 and 1 or -1
          break
        end
      end
    end
    if not moved then
      w.stuck = (w.stuck or 0) + dt
      return false
    end
  end
  w.stuck = 0
  return true
end

--- Is nothing that stops a walker on the straight line from (x0, y0) to
--- (x1, y1)?
function Walk.clear(blocked, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.floor(math.sqrt(dx * dx + dy * dy) / Walk.SAMPLE)
  for i = 1, n do
    local k = i / (n + 1)
    if blocked(x0 + dx * k, y0 + dy * k) then
      return false
    end
  end
  return true
end

--- Can a walker `r` px across go straight from (x0, y0) to (x1, y1), its
--- whole width and not just its middle? (Seeing someone is not the same:
--- a line of sight passes a corner, or water, its shoulders don't.)
function Walk.wideClear(blocked, x0, y0, x1, y1, r)
  local a = math.atan2(y1 - y0, x1 - x0)
  local ox, oy = -math.sin(a) * r, math.cos(a) * r
  return Walk.clear(blocked, x0, y0, x1, y1) and Walk.clear(blocked, x0 + ox, y0 + oy, x1 + ox, y1 + oy)
    and Walk.clear(blocked, x0 - ox, y0 - oy, x1 - ox, y1 - oy)
end

--- The walking grid `nav` (d-day/nav.lua) as a walker `r` px across,
--- stopped by `blocked`, walks it: the same grid, but a cell is open only
--- where it fits at the cell's middle, so a way found on it never sends it
--- down a gap or round a corner it won't take. Doors still count: when the
--- grid works a cell out again (Nav:refresh), what fits is worked out
--- afresh. One per grid, `blocked` and size, kept on the grid.
function Walk.nav(nav, blocked, r)
  local made = nav.wide -- { [blocked] = { [r] = grid } }
  if not made then
    made = {}
    nav.wide = made
    local refresh = nav.refresh
    nav.refresh = function(self, ...) -- a door: forget what fitted, every size
      refresh(self, ...)
      for _, sizes in pairs(made) do
        for _, wide in pairs(sizes) do
          wide.fit = {}
        end
      end
    end
  end
  made[blocked] = made[blocked] or {}
  local wide = made[blocked][r]
  if wide then
    return wide
  end
  local ease = r * Walk.EASE
  wide = setmetatable({ fit = {} }, { __index = nav })
  function wide:isOpen(c, row)
    if not nav:isOpen(c, row) then
      return false
    end
    local key = row * nav.cols + c
    local fits = self.fit[key]
    if fits == nil then
      local x, y = nav:centre(c, row)
      fits = Walk.fits(blocked, x, y, ease)
      self.fit[key] = fits
    end
    return fits
  end
  made[blocked][r] = wide
  return wide
end

--- Which way walker `w` ({ x, y, stuck, route }) should walk to get to
--- (x, y) on grid `nav` (Walk.nav's, or nil to go straight), `time` being
--- its clock in seconds: an angle; or nil and true once it is there, nil
--- and false when there is no way it fits (it should hold rather than
--- grind into a wall).
--- Only the way: the walker turns (or doesn't, kiting) and walks itself.
function Walk.route(w, nav, x, y, time)
  local g = w.route
  if not g or (g.x - x) ^ 2 + (g.y - y) ^ 2 > Walk.MOVED ^ 2 or time > g.replanAt or (w.stuck or 0) > 0.3 then
    local corners = nav and nav:path(w.x, w.y, x, y)
    if not nav then
      corners = { { x = x, y = y } }
    end
    g = { x = x, y = y, corners = corners, at = 1, replanAt = time + Walk.REPLAN }
    w.route = g
  end
  if not g.corners then
    return nil, false
  end
  local c = g.corners[g.at]
  if (w.x - c.x) ^ 2 + (w.y - c.y) ^ 2 < Walk.ARRIVE ^ 2 then
    if g.at >= #g.corners then
      return nil, true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
  end
  return math.atan2(c.y - w.y, c.x - w.x)
end

return Walk
