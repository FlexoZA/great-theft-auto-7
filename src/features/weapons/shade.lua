-- Shading for the small drawings of things you carry (guns, clothes,
-- armor): every part is its colour, a lighter band along its top where the
-- light catches it, a darker one along its bottom, and a thin dark outline
-- that stays one pixel wide at any scale. Call `Shade.begin(scale, alpha)`
-- before a drawing (the scale it is drawn at, so outlines stay a pixel) and
-- draw its parts back to front.

local Shade = {}

local alpha, pixel = 1, 1

--- Start a drawing that will show at `scale` times its size, `a` opaque.
function Shade.begin(scale, a)
  alpha, pixel = a or 1, 1 / (scale or 1)
end

--- One screen pixel in the drawing's own units.
function Shade.pixel()
  return pixel
end

--- Set colour `c`, times `k` (1: as it is), at the drawing's alpha times `a`.
function Shade.set(c, k, a)
  k = k or 1
  love.graphics.setColor(math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k), alpha * (a or 1))
end

--- `c` lifted towards white by `k` (0..1): where the light catches it.
function Shade.lit(c, k)
  return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end

--- A part: a box `w` x `h` at (x, y), corners rounded by `r`, in colour `c`,
--- lit along the top and shadowed along the bottom, outlined.
function Shade.box(x, y, w, h, c, r)
  r = r or 0
  Shade.set(c)
  love.graphics.rectangle("fill", x, y, w, h, r)
  local band = math.max(0.8, h * 0.22)
  if h > 2 then
    Shade.set(Shade.lit(c, 0.35))
    love.graphics.rectangle("fill", x + r * 0.6, y + 0.4, w - r * 1.2, band, math.min(r, band / 2))
    Shade.set(c, 0.72)
    love.graphics.rectangle("fill", x + r * 0.6, y + h - band - 0.4, w - r * 1.2, band, math.min(r, band / 2))
  end
  Shade.set(c, 0.45)
  love.graphics.setLineWidth(pixel)
  love.graphics.rectangle("line", x, y, w, h, r)
end

--- A part of any shape: the polygon through the points, in colour `c`,
--- outlined. `...` is x1, y1, x2, y2, ... (convex, as LÖVE fills them).
function Shade.poly(c, ...)
  Shade.set(c)
  love.graphics.polygon("fill", ...)
  Shade.set(c, 0.45)
  love.graphics.setLineWidth(pixel)
  love.graphics.polygon("line", ...)
end

--- A round part: an ellipse `rx` x `ry` at (x, y), lit on its upper half,
--- outlined. `mode` "arc" draws only the top half (a dome).
function Shade.ellipse(x, y, rx, ry, c, mode)
  local function shape(fill)
    if mode == "arc" then
      love.graphics.push()
      love.graphics.translate(x, y)
      love.graphics.scale(1, ry / rx)
      love.graphics.arc(fill, fill == "fill" and "pie" or "closed", 0, 0, rx, math.pi, 2 * math.pi, 20)
      love.graphics.pop()
    else
      love.graphics.ellipse(fill, x, y, rx, ry, 20)
    end
  end
  Shade.set(c)
  shape("fill")
  Shade.set(Shade.lit(c, 0.35))
  love.graphics.ellipse("fill", x - rx * 0.25, y - ry * (mode == "arc" and 0.6 or 0.4), rx * 0.4, ry * 0.2, 12)
  Shade.set(c, 0.45)
  love.graphics.setLineWidth(pixel)
  shape("line")
end

--- A thin line in colour `c` (shaded by `k`), `w` pixels wide at any scale.
function Shade.line(c, k, w, ...)
  Shade.set(c, k)
  love.graphics.setLineWidth(pixel * (w or 1))
  love.graphics.line(...)
end

--- A few short strokes across a part, `n` of them from (x, y) every `step`:
--- serrations, grooves, ribs, stitching.
function Shade.strokes(c, k, n, x, y, step, len, vertical)
  for i = 0, n - 1 do
    if vertical then
      Shade.line(c, k, 1, x + i * step, y, x + i * step, y + len)
    else
      Shade.line(c, k, 1, x, y + i * step, x + len, y + i * step)
    end
  end
end

--- A small dot (a rivet, a button, a stud) in colour `c` shaded by `k`.
function Shade.dot(x, y, r, c, k)
  Shade.set(c, k)
  love.graphics.circle("fill", x, y, r, 8)
end

--- Done: put the line width back.
function Shade.finish()
  love.graphics.setLineWidth(1)
end

return Shade
