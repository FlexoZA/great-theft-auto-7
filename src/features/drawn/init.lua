-- Where a synced body is drawn. Not a feature with hooks: a helper every
-- feature that draws something the host moves (an enemy, a pedestrian, a
-- boss) uses, so all of them sit where the host has them and not behind.
--
-- The host's word on a body comes every tick or two (its x, y) and the
-- screen eases what it draws (dx, dy) toward it. Eased toward a stale spot
-- the drawing trails the body: by the message's age, and by the easing
-- itself, which settles speed / rate behind a mover. A round aimed at the
-- drawing then misses the body on the host and looks like it went through.
--
-- So the last word is carried on at the pace the words before it gave
-- (vx, vy) for the time since it came, plus the easing's own lag, and the
-- drawing is eased toward that. A body that stops shows a little past
-- where it stood until the next word pulls it back (AHEAD caps it).
--
--   local Drawn = require("src.features.drawn")
--   -- in the sync message's handler, instead of s.x, s.y = x, y:
--   Drawn.heard(s, x, y, tick)
--   -- in update, instead of easing s.dx, s.dy toward s.x, s.y:
--   local mx, my = Drawn.step(s, dt, SMOOTHING, SNAP)
--
-- `s` keeps hx, hy, htick, heardAt, vx, vy for the helper; everything else
-- on it is the feature's. `step` returns how far the drawing moved this
-- frame, for a stride or a facing worked out from it.

local Server = require("src.net.server")

local Drawn = {}

Drawn.AHEAD = 0.12 -- seconds a word is carried on at most (a sync every other tick is 0.067 old by the next)
Drawn.STILL = 15 -- px/s and under: the host rounds positions to the pixel, so this is standing still
Drawn.DASH = 1000 -- px/s and over isn't a pace, it's a jump (a leap landing, a teleport): not carried on

--- The host's word: `s` is at (x, y) as of `tick`. Its pace is read off
--- the word before (the tick tells the time between; a feature with no
--- tick in its message passes nil and the clock stands in).
function Drawn.heard(s, x, y, tick)
  local now = love.timer.getTime()
  if s.hx then
    local between
    if tick and s.htick and tick > s.htick then
      between = (tick - s.htick) * Server.TICK
    elseif not tick and s.heardAt then
      between = now - s.heardAt
    end
    if between and between > 0 then
      local vx, vy = (x - s.hx) / between, (y - s.hy) / between
      local v2 = vx * vx + vy * vy
      if v2 < Drawn.STILL ^ 2 or v2 > Drawn.DASH ^ 2 then
        vx, vy = 0, 0
      end
      s.vx, s.vy = vx, vy
    elseif tick and s.htick and tick == s.htick then
      return -- the same word again
    end
  end
  s.hx, s.hy, s.htick, s.heardAt = x, y, tick, now
  s.x, s.y = x, y
end

--- Where `s` is drawn now: dx, dy eased at `rate` per second toward where
--- the last word puts it at this moment, snapping when it is further than
--- `snap` px off (it came in, or was moved). Returns how far the drawing
--- moved this frame.
function Drawn.step(s, dt, rate, snap)
  local tx, ty = s.x, s.y
  if s.vx and s.heardAt and (s.vx ~= 0 or s.vy ~= 0) then
    local ahead = math.min(Drawn.AHEAD, love.timer.getTime() - s.heardAt) + 1 / rate
    tx, ty = tx + s.vx * ahead, ty + s.vy * ahead
  end
  if not s.dx then
    s.dx, s.dy = tx, ty
    return 0, 0
  end
  local ex, ey = tx - s.dx, ty - s.dy
  if ex * ex + ey * ey > snap * snap then
    s.dx, s.dy = tx, ty
    return 0, 0
  end
  local k = math.min(1, dt * rate)
  local mx, my = ex * k, ey * k
  s.dx, s.dy = s.dx + mx, s.dy + my
  return mx, my
end

--- Forget `s`'s pace (it was put somewhere: a spawn, a teleport), so the
--- next word is not read as a dash.
function Drawn.reset(s)
  s.hx, s.hy, s.htick, s.heardAt, s.vx, s.vy = nil, nil, nil, nil, nil, nil
end

return Drawn
