-- A small SVG reader and rasteriser. LÖVE can't load SVG, so this turns the
-- common subset into flat shapes and paints them once onto a canvas, which is
-- then drawn like any other image.
--
-- Understood: <svg viewBox>, <g>, <path> (every command, arcs included),
-- <rect> (rounded too), <circle>, <ellipse>, <line>, <polyline>, <polygon>;
-- fill, stroke, stroke-width, opacity, fill-opacity, stroke-opacity, display
-- and visibility, as attributes or in style="", inherited through groups;
-- transform (matrix, translate, scale, rotate, skewX, skewY). A gradient fill
-- is painted flat in the average of its stops.
-- Not understood (skipped quietly): <style> sheets and classes, <use>, <text>,
-- <image>, clip paths, masks, filters, dashes. Fills use the even-odd rule.
--
-- Svg.parse(text) is plain Lua and runs anywhere (the host checks the models
-- without drawing them); Svg.render needs a window.

local Svg = {}

-- Colours --------------------------------------------------------------------

local NAMED = {
  black = "#000000", white = "#ffffff", red = "#ff0000", green = "#008000", blue = "#0000ff",
  yellow = "#ffff00", orange = "#ffa500", gray = "#808080", grey = "#808080", silver = "#c0c0c0",
  maroon = "#800000", purple = "#800080", navy = "#000080", teal = "#008080", lime = "#00ff00",
  aqua = "#00ffff", cyan = "#00ffff", fuchsia = "#ff00ff", magenta = "#ff00ff", olive = "#808000",
  brown = "#a52a2a", pink = "#ffc0cb", darkgray = "#a9a9a9", darkgrey = "#a9a9a9",
  lightgray = "#d3d3d3", lightgrey = "#d3d3d3", dimgray = "#696969", dimgrey = "#696969",
}

--- "#f80", "#ff8800", "rgb(255, 136, 0)", "orange" -> { r, g, b } in 0..1,
--- false for "none", nil for anything else. Gradients are looked up by id.
local function parseColor(s, gradients)
  if not s then
    return nil
  end
  s = s:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if s == "none" or s == "transparent" then
    return false
  end
  local ref = s:match("^url%(%s*['\"]?#([^)'\"]+)")
  if ref then
    return gradients and gradients[ref] or nil
  end
  s = NAMED[s] or s
  local hex = s:match("^#(%x+)$")
  if hex and #hex == 3 then
    return {
      tonumber(hex:sub(1, 1), 16) / 15,
      tonumber(hex:sub(2, 2), 16) / 15,
      tonumber(hex:sub(3, 3), 16) / 15,
    }
  elseif hex and #hex >= 6 then
    return {
      tonumber(hex:sub(1, 2), 16) / 255,
      tonumber(hex:sub(3, 4), 16) / 255,
      tonumber(hex:sub(5, 6), 16) / 255,
    }
  end
  local r, g, b = s:match("^rgba?%(%s*([%d%.]+%%?)%s*,%s*([%d%.]+%%?)%s*,%s*([%d%.]+%%?)")
  if r then
    local function channel(v)
      if v:sub(-1) == "%" then
        return tonumber(v:sub(1, -2)) / 100
      end
      return tonumber(v) / 255
    end
    return { channel(r), channel(g), channel(b) }
  end
  return nil
end

-- Transforms -----------------------------------------------------------------
-- A matrix is { a, b, c, d, e, f }: x' = a x + c y + e, y' = b x + d y + f.

local IDENTITY = { 1, 0, 0, 1, 0, 0 }

local function multiply(m, n)
  return {
    m[1] * n[1] + m[3] * n[2],
    m[2] * n[1] + m[4] * n[2],
    m[1] * n[3] + m[3] * n[4],
    m[2] * n[3] + m[4] * n[4],
    m[1] * n[5] + m[3] * n[6] + m[5],
    m[2] * n[5] + m[4] * n[6] + m[6],
  }
end

local function numbers(s)
  local out = {}
  for n in s:gmatch("[%+%-]?%d*%.?%d+[eE]?[%+%-]?%d*") do
    out[#out + 1] = tonumber(n) or 0
  end
  return out
end

local function parseTransform(s)
  local m = IDENTITY
  if not s then
    return m
  end
  for name, args in s:gmatch("(%a+)%s*%(([^)]*)%)") do
    local v = numbers(args)
    local t
    if name == "matrix" and #v >= 6 then
      t = { v[1], v[2], v[3], v[4], v[5], v[6] }
    elseif name == "translate" then
      t = { 1, 0, 0, 1, v[1] or 0, v[2] or 0 }
    elseif name == "scale" then
      t = { v[1] or 1, 0, 0, v[2] or v[1] or 1, 0, 0 }
    elseif name == "rotate" then
      local a = math.rad(v[1] or 0)
      local c, s2 = math.cos(a), math.sin(a)
      t = { c, s2, -s2, c, 0, 0 }
      if v[2] then
        local cx, cy = v[2], v[3] or 0
        t = multiply(multiply({ 1, 0, 0, 1, cx, cy }, t), { 1, 0, 0, 1, -cx, -cy })
      end
    elseif name == "skewX" then
      t = { 1, 0, math.tan(math.rad(v[1] or 0)), 1, 0, 0 }
    elseif name == "skewY" then
      t = { 1, math.tan(math.rad(v[1] or 0)), 0, 1, 0, 0 }
    end
    if t then
      m = multiply(m, t)
    end
  end
  return m
end

-- Paths ----------------------------------------------------------------------

--- Reads numbers and flags out of path data one at a time.
local function reader(d)
  local r = { s = d, i = 1 }

  function r.skip()
    local _, e = r.s:find("^[%s,]*", r.i)
    r.i = e + 1
  end

  function r.command()
    r.skip()
    local c = r.s:sub(r.i, r.i)
    if c ~= "" and c:match("[MmLlHhVvCcSsQqTtAaZz]") then
      r.i = r.i + 1
      return c
    end
    return nil
  end

  function r.hasNumber()
    r.skip()
    return r.s:find("^[%+%-]?%.?%d", r.i) ~= nil
  end

  function r.number()
    r.skip()
    local s, e = r.s:find("^[%+%-]?%d*%.?%d*", r.i)
    if not s or e < s then
      return nil
    end
    local _, ee = r.s:find("^[eE][%+%-]?%d+", e + 1)
    e = ee or e
    local n = tonumber(r.s:sub(s, e))
    if n then
      r.i = e + 1
    end
    return n
  end

  -- Arc flags may be packed with no separator: "a10 10 0 015 5".
  function r.flag()
    r.skip()
    local c = r.s:sub(r.i, r.i)
    if c == "0" or c == "1" then
      r.i = r.i + 1
      return c == "1"
    end
    return nil
  end

  return r
end

--- Segments to cut a curve into: about one per `step` of its control polygon.
local function segments(step, ...)
  local p = { ... }
  local len = 0
  for i = 3, #p, 2 do
    local dx, dy = p[i] - p[i - 2], p[i + 1] - p[i - 1]
    len = len + math.sqrt(dx * dx + dy * dy)
  end
  return math.max(2, math.min(64, math.ceil(len / step)))
end

local function cubic(pts, step, x0, y0, x1, y1, x2, y2, x3, y3)
  local n = segments(step, x0, y0, x1, y1, x2, y2, x3, y3)
  for k = 1, n do
    local t = k / n
    local u = 1 - t
    local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
    pts[#pts + 1] = a * x0 + b * x1 + c * x2 + d * x3
    pts[#pts + 1] = a * y0 + b * y1 + c * y2 + d * y3
  end
end

local function quadratic(pts, step, x0, y0, x1, y1, x2, y2)
  local n = segments(step, x0, y0, x1, y1, x2, y2)
  for k = 1, n do
    local t = k / n
    local u = 1 - t
    pts[#pts + 1] = u * u * x0 + 2 * u * t * x1 + t * t * x2
    pts[#pts + 1] = u * u * y0 + 2 * u * t * y1 + t * t * y2
  end
end

--- An elliptical arc from (x0, y0) to (x, y), as the SVG spec lays it out
--- (implementation notes, F.6.5 and F.6.6).
local function arc(pts, step, x0, y0, rx, ry, rotation, large, sweep, x, y)
  rx, ry = math.abs(rx), math.abs(ry)
  if rx == 0 or ry == 0 or (x0 == x and y0 == y) then
    pts[#pts + 1], pts[#pts + 2] = x, y
    return
  end
  local phi = math.rad(rotation)
  local cp, sp = math.cos(phi), math.sin(phi)
  local dx, dy = (x0 - x) / 2, (y0 - y) / 2
  local x1 = cp * dx + sp * dy
  local y1 = -sp * dx + cp * dy
  local lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
  if lambda > 1 then
    local s = math.sqrt(lambda)
    rx, ry = rx * s, ry * s
  end
  local num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
  local den = rx * rx * y1 * y1 + ry * ry * x1 * x1
  local k = math.sqrt(math.max(0, num / den))
  if large == sweep then
    k = -k
  end
  local cx1, cy1 = k * rx * y1 / ry, -k * ry * x1 / rx
  local cx = cp * cx1 - sp * cy1 + (x0 + x) / 2
  local cy = sp * cx1 + cp * cy1 + (y0 + y) / 2
  local function angle(ux, uy, vx, vy)
    local a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    return a
  end
  local ux, uy = (x1 - cx1) / rx, (y1 - cy1) / ry
  local vx, vy = (-x1 - cx1) / rx, (-y1 - cy1) / ry
  local theta = angle(1, 0, ux, uy)
  local delta = angle(ux, uy, vx, vy)
  if not sweep and delta > 0 then
    delta = delta - 2 * math.pi
  elseif sweep and delta < 0 then
    delta = delta + 2 * math.pi
  end
  local n = math.max(4, math.min(96, math.ceil(math.abs(delta) * math.max(rx, ry) / step)))
  for i = 1, n do
    local t = theta + delta * i / n
    local ex, ey = rx * math.cos(t), ry * math.sin(t)
    pts[#pts + 1] = cp * ex - sp * ey + cx
    pts[#pts + 1] = sp * ex + cp * ey + cy
  end
end

--- Path data -> list of subpaths, each a flat { x1, y1, x2, y2, ...,
--- closed = bool }. `step` is roughly how long a straight piece of a curve
--- may be, in path units.
local function parsePath(d, step)
  local r = reader(d)
  local subpaths = {}
  local pts
  local x, y, sx, sy = 0, 0, 0, 0
  local cx, cy -- last control point, for S and T
  local cmd, prev

  local function start(nx, ny)
    pts = { nx, ny }
    subpaths[#subpaths + 1] = pts
    x, y, sx, sy = nx, ny, nx, ny
  end
  local function ensure()
    if not pts then
      start(x, y)
    end
  end

  while true do
    local c = r.command()
    if c then
      cmd = c
    elseif not (cmd and r.hasNumber()) then
      break
    end
    local rel = cmd == cmd:lower()
    local C = cmd:upper()
    local ox, oy = rel and x or 0, rel and y or 0
    if C == "Z" then
      if pts then
        pts.closed = true
        x, y = sx, sy
        pts = nil
      end
      prev = "Z"
      if not c then
        break -- numbers after Z are malformed
      end
    else
      local ok = true
      if C == "M" then
        local nx, ny = r.number(), r.number()
        ok = nx and ny
        if ok then
          start(nx + ox, ny + oy)
          cmd = rel and "l" or "L" -- more pairs after a move are lines
        end
      elseif C == "L" then
        local nx, ny = r.number(), r.number()
        ok = nx and ny
        if ok then
          ensure()
          x, y = nx + ox, ny + oy
          pts[#pts + 1], pts[#pts + 2] = x, y
        end
      elseif C == "H" then
        local nx = r.number()
        ok = nx
        if ok then
          ensure()
          x = nx + ox
          pts[#pts + 1], pts[#pts + 2] = x, y
        end
      elseif C == "V" then
        local ny = r.number()
        ok = ny
        if ok then
          ensure()
          y = ny + oy
          pts[#pts + 1], pts[#pts + 2] = x, y
        end
      elseif C == "C" or C == "S" then
        local x1, y1
        if C == "C" then
          x1, y1 = r.number(), r.number()
          x1, y1 = x1 and x1 + ox, y1 and y1 + oy
        elseif prev == "C" or prev == "S" then
          x1, y1 = 2 * x - cx, 2 * y - cy
        else
          x1, y1 = x, y
        end
        local x2, y2, nx, ny = r.number(), r.number(), r.number(), r.number()
        ok = x1 and y1 and x2 and y2 and nx and ny
        if ok then
          ensure()
          x2, y2, nx, ny = x2 + ox, y2 + oy, nx + ox, ny + oy
          cubic(pts, step, x, y, x1, y1, x2, y2, nx, ny)
          cx, cy, x, y = x2, y2, nx, ny
        end
      elseif C == "Q" or C == "T" then
        local x1, y1
        if C == "Q" then
          x1, y1 = r.number(), r.number()
          x1, y1 = x1 and x1 + ox, y1 and y1 + oy
        elseif prev == "Q" or prev == "T" then
          x1, y1 = 2 * x - cx, 2 * y - cy
        else
          x1, y1 = x, y
        end
        local nx, ny = r.number(), r.number()
        ok = x1 and y1 and nx and ny
        if ok then
          ensure()
          nx, ny = nx + ox, ny + oy
          quadratic(pts, step, x, y, x1, y1, nx, ny)
          cx, cy, x, y = x1, y1, nx, ny
        end
      elseif C == "A" then
        local rx, ry, rot = r.number(), r.number(), r.number()
        local large, sweep = r.flag(), r.flag()
        local nx, ny = r.number(), r.number()
        ok = rx and ry and rot and large ~= nil and sweep ~= nil and nx and ny
        if ok then
          ensure()
          nx, ny = nx + ox, ny + oy
          arc(pts, step, x, y, rx, ry, rot, large, sweep, nx, ny)
          x, y = nx, ny
        end
      end
      if not ok then
        break -- malformed: keep what was read so far
      end
      prev = C
    end
  end
  return subpaths
end

-- Basic shapes, as subpaths --------------------------------------------------

local function num(v, default)
  return tonumber(v and v:match("^%s*([%+%-]?[%d%.eE%+%-]+)")) or default
end

local function ellipsePath(cx, cy, rx, ry, step)
  local pts = { closed = true }
  local n = math.max(12, math.min(96, math.ceil(2 * math.pi * math.max(rx, ry) / step)))
  for i = 0, n - 1 do
    local t = 2 * math.pi * i / n
    pts[#pts + 1] = cx + rx * math.cos(t)
    pts[#pts + 1] = cy + ry * math.sin(t)
  end
  return { pts }
end

local function rectPath(a, step)
  local x, y, w, h = num(a.x, 0), num(a.y, 0), num(a.width, 0), num(a.height, 0)
  if w <= 0 or h <= 0 then
    return {}
  end
  local rx, ry = num(a.rx), num(a.ry)
  rx, ry = rx or ry or 0, ry or rx or 0
  rx, ry = math.min(rx, w / 2), math.min(ry, h / 2)
  if rx <= 0 or ry <= 0 then
    return { { x, y, x + w, y, x + w, y + h, x, y + h, closed = true } }
  end
  local d = ("M%f %fH%fA%f %f 0 0 1 %f %fV%fA%f %f 0 0 1 %f %fH%fA%f %f 0 0 1 %f %fV%fA%f %f 0 0 1 %f %fZ"):format(
    x + rx, y, x + w - rx, rx, ry, x + w, y + ry, y + h - ry, rx, ry, x + w - rx, y + h,
    x + rx, rx, ry, x, y + h - ry, y + ry, rx, ry, x + rx, y)
  return parsePath(d, step)
end

local function pointsPath(s, closed)
  local v = numbers(s or "")
  local pts = { closed = closed }
  for i = 1, #v - 1, 2 do
    pts[#pts + 1], pts[#pts + 2] = v[i], v[i + 1]
  end
  return { pts }
end

-- The document -----------------------------------------------------------------

local function attributes(s)
  local a = {}
  for k, v in s:gmatch("([%w_:%-]+)%s*=%s*\"([^\"]*)\"") do
    a[k] = v
  end
  for k, v in s:gmatch("([%w_:%-]+)%s*=%s*'([^']*)'") do
    a[k] = v
  end
  local style = a.style
  if style then
    for k, v in style:gmatch("([%w%-]+)%s*:%s*([^;]+)") do
      a[k] = v:gsub("%s+$", "")
    end
  end
  return a
end

--- What a child inherits from its parent, with this element's own on top.
local function inherit(parent, a, gradients)
  local st = {}
  for k, v in pairs(parent) do
    st[k] = v
  end
  if a.fill then
    st.fill = parseColor(a.fill, gradients)
    if st.fill == nil then
      st.fill = parent.fill
    end
  end
  if a.stroke then
    st.stroke = parseColor(a.stroke, gradients)
    if st.stroke == nil then
      st.stroke = parent.stroke
    end
  end
  st.strokeWidth = num(a["stroke-width"], st.strokeWidth)
  st.fillOpacity = num(a["fill-opacity"], st.fillOpacity)
  st.strokeOpacity = num(a["stroke-opacity"], st.strokeOpacity)
  st.opacity = parent.opacity * num(a.opacity, 1) -- opacity multiplies down the tree
  if a.visibility then
    st.hidden = a.visibility == "hidden" or a.visibility == "collapse"
  end
  st.matrix = multiply(parent.matrix, parseTransform(a.transform))
  return st
end

local SKIP = { defs = true, clipPath = true, mask = true, pattern = true, symbol = true, marker = true, style = true }
local GRADIENT = { linearGradient = true, radialGradient = true }

--- Gradients by id -> the average colour of their stops, following
--- xlink:href to a gradient that holds the stops.
local function readGradients(text)
  local raw, links = {}, {}
  local at = 1
  while true do
    local s, e, tag, attrs = text:find("<(%a+Gradient)([^>]*)>", at)
    if not s then
      break
    end
    at = e + 1
    local a = attributes(attrs)
    local stops = {}
    if attrs:sub(-1) ~= "/" then
      local close = text:find("</" .. tag .. ">", at, true) or #text
      for stop in text:sub(at, close):gmatch("<stop([^>]*)>") do
        stops[#stops + 1] = parseColor(attributes(stop)["stop-color"] or "#000")
      end
    end
    if a.id then
      raw[a.id] = stops
      links[a.id] = (a["xlink:href"] or a.href or ""):match("^#(.+)")
    end
  end
  local out = {}
  for id in pairs(raw) do
    local seen, from = {}, id
    while from and raw[from] and #raw[from] == 0 and not seen[from] do
      seen[from] = true
      from = links[from]
    end
    local stops = from and raw[from] or {}
    if #stops > 0 then
      local r, g, b = 0, 0, 0
      for _, c in ipairs(stops) do
        r, g, b = r + c[1], g + c[2], b + c[3]
      end
      out[id] = { r / #stops, g / #stops, b / #stops }
    end
  end
  return out
end

--- Parse an SVG document. Returns { shapes, bounds = { x, y, w, h }, viewBox }
--- where every shape is { subpaths, fill, stroke, strokeWidth } in the
--- document's own units, transforms applied; colours are { r, g, b, a }.
--- Returns nil and a message for text that isn't an SVG.
function Svg.parse(text)
  if type(text) ~= "string" or not text:find("<svg") then
    return nil, "not an SVG document"
  end
  local gradients = readGradients(text)
  text = text:gsub("<!%-%-.-%-%->", ""):gsub("<%?.-%?>", ""):gsub("<!.->", "")

  local doc = { shapes = {} }
  local root = {
    fill = { 0, 0, 0 }, stroke = false, strokeWidth = 1, fillOpacity = 1, strokeOpacity = 1,
    opacity = 1, hidden = false, matrix = IDENTITY,
  }
  local stack = { root }
  local skipping = 0
  local step = 1

  local function add(st, subpaths)
    if st.hidden or st.gone or #subpaths == 0 then
      return
    end
    local fill = st.fill and { st.fill[1], st.fill[2], st.fill[3], st.fillOpacity * st.opacity } or nil
    local stroke = st.stroke and st.strokeWidth > 0
        and { st.stroke[1], st.stroke[2], st.stroke[3], st.strokeOpacity * st.opacity }
      or nil
    if not (fill or stroke) then
      return
    end
    local m = st.matrix
    for _, p in ipairs(subpaths) do
      for i = 1, #p - 1, 2 do
        local x, y = p[i], p[i + 1]
        p[i], p[i + 1] = m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
      end
    end
    local scale = math.sqrt(math.abs(m[1] * m[4] - m[2] * m[3]))
    doc.shapes[#doc.shapes + 1] = {
      subpaths = subpaths,
      fill = fill,
      stroke = stroke,
      strokeWidth = st.strokeWidth * scale,
    }
  end

  for closing, tag, attrs, selfClosing in text:gmatch("<(/?)([%w_:%-]+)(.-)(/?)>") do
    if closing == "/" then
      if SKIP[tag] or GRADIENT[tag] then
        skipping = math.max(0, skipping - 1)
      elseif skipping == 0 and (tag == "g" or tag == "svg" or tag == "a") and #stack > 1 then
        stack[#stack] = nil
      end
    elseif skipping > 0 or SKIP[tag] or GRADIENT[tag] then
      -- Anything inside a skipped element goes with it.
      if (SKIP[tag] or GRADIENT[tag]) and selfClosing ~= "/" then
        skipping = skipping + 1
      end
    else
      local a = attributes(attrs)
      local parent = stack[#stack]
      if a.display == "none" then
        if selfClosing ~= "/" and (tag == "g" or tag == "svg" or tag == "a") then
          local st = inherit(parent, a, gradients)
          st.gone = true -- display:none can't be undone further down
          stack[#stack + 1] = st
        end
      elseif tag == "svg" and not doc.viewBox then
        local v = numbers(a.viewBox or "")
        if #v == 4 then
          doc.viewBox = { x = v[1], y = v[2], w = v[3], h = v[4] }
        else
          local w, h = num(a.width), num(a.height)
          doc.viewBox = { x = 0, y = 0, w = w or 100, h = h or 100 }
        end
        step = math.max(doc.viewBox.w, doc.viewBox.h) / 800
        stack[#stack + 1] = inherit(parent, a, gradients)
      elseif tag == "g" or tag == "svg" or tag == "a" then
        if selfClosing ~= "/" then
          stack[#stack + 1] = inherit(parent, a, gradients)
        end
      else
        local st = inherit(parent, a, gradients)
        local subpaths
        if tag == "path" then
          subpaths = parsePath(a.d or "", step)
        elseif tag == "rect" then
          subpaths = rectPath(a, step)
        elseif tag == "circle" then
          local r = num(a.r, 0)
          subpaths = r > 0 and ellipsePath(num(a.cx, 0), num(a.cy, 0), r, r, step) or {}
        elseif tag == "ellipse" then
          local rx, ry = num(a.rx, 0), num(a.ry, 0)
          subpaths = rx > 0 and ry > 0 and ellipsePath(num(a.cx, 0), num(a.cy, 0), rx, ry, step) or {}
        elseif tag == "line" then
          subpaths = { { num(a.x1, 0), num(a.y1, 0), num(a.x2, 0), num(a.y2, 0) } }
          st.fill = false
        elseif tag == "polyline" then
          subpaths = pointsPath(a.points, false)
        elseif tag == "polygon" then
          subpaths = pointsPath(a.points, true)
        end
        if subpaths then
          add(st, subpaths)
        end
      end
    end
  end

  -- The box the drawing actually covers, strokes included.
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, s in ipairs(doc.shapes) do
    local pad = s.stroke and s.strokeWidth / 2 or 0
    for _, p in ipairs(s.subpaths) do
      for i = 1, #p - 1, 2 do
        x0, x1 = math.min(x0, p[i] - pad), math.max(x1, p[i] + pad)
        y0, y1 = math.min(y0, p[i + 1] - pad), math.max(y1, p[i + 1] + pad)
      end
    end
  end
  if x0 > x1 then
    return nil, "nothing to draw"
  end
  doc.bounds = { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
  return doc
end

--- Every subpath of `shape` as a fan of triangles, in one vertex list.
local function fan(shape)
  local verts = {}
  for _, p in ipairs(shape.subpaths) do
    local n = math.floor(#p / 2)
    if n >= 3 then
      local ax, ay = p[1], p[2]
      for i = 2, n - 1 do
        verts[#verts + 1] = { ax, ay }
        verts[#verts + 1] = { p[2 * i - 1], p[2 * i] }
        verts[#verts + 1] = { p[2 * i + 1], p[2 * i + 2] }
      end
    end
  end
  return verts
end

--- Paint `doc` onto a new canvas whose longer side is `size` px (plus a
--- pixel of margin all round). The canvas holds premultiplied colour and has
--- mipmaps, so draw it with the "alpha", "premultiplied" blend mode and it
--- stays smooth at any size below `size`.
function Svg.render(doc, size)
  local b = doc.bounds
  local scale = size / math.max(b.w, b.h)
  local margin = 2
  local cw = math.ceil(b.w * scale) + margin * 2
  local ch = math.ceil(b.h * scale) + margin * 2
  local canvas = love.graphics.newCanvas(cw, ch, { mipmaps = "auto" })
  canvas:setFilter("linear", "linear")
  canvas:setMipmapFilter("linear")

  love.graphics.push("all")
  love.graphics.setCanvas({ canvas, stencil = true })
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.translate(margin, margin)
  love.graphics.scale(scale)
  love.graphics.translate(-b.x, -b.y)
  love.graphics.setLineJoin("bevel")
  for _, s in ipairs(doc.shapes) do
    if s.fill and s.fill[4] > 0 then
      local verts = fan(s)
      if #verts >= 3 then
        local mesh = love.graphics.newMesh(verts, "triangles", "static")
        -- Each triangle flips the stencil where it lands, so a pixel is set
        -- when an odd number of them cover it: the even-odd rule.
        love.graphics.stencil(function()
          love.graphics.draw(mesh)
        end, "invert", 0)
        love.graphics.setStencilTest("notequal", 0)
        love.graphics.setColor(s.fill)
        love.graphics.rectangle("fill", b.x - 1, b.y - 1, b.w + 2, b.h + 2)
        love.graphics.setStencilTest()
        mesh:release()
      end
    end
    if s.stroke and s.stroke[4] > 0 then
      love.graphics.setColor(s.stroke)
      love.graphics.setLineWidth(s.strokeWidth)
      for _, p in ipairs(s.subpaths) do
        if #p >= 4 then
          if p.closed then
            local closed = { unpack(p) }
            closed[#closed + 1], closed[#closed + 2] = p[1], p[2]
            love.graphics.line(closed)
          else
            love.graphics.line(p)
          end
        end
      end
    end
  end
  love.graphics.pop()
  return canvas
end

return Svg
