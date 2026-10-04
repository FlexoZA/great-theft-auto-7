-- The Citadel, inside: the second stop of A-Man's quest (city-map's
-- `citadel`). One narrow catwalk zig-zags up through a vast dark shaft,
-- from the lift everyone arrives on at the bottom to the top platform,
-- opening out on the way into wide platforms where the Combine hold the
-- way (and a landing half way over the long span across the core). There
-- is nothing else to walk on: everything off the catwalk is the drop.
--
-- Tiles are "walk" (the catwalks and the platforms) or nothing at all: the
-- layout's walls fill every empty tile, so the drop is solid to walk into
-- and, like any wall, stops rounds and sight for now.
--
-- What it leaves on the map, besides tiles, solids and spawns:
--   map.cx, map.cy        the way home, at the left end of the lift
--   map.exitX, map.exitY  the far end, the lift up at the top
--   map.platforms         { name, x, y, w, h, kind = "lift" | "arena" | "landing" | "top" }, world px
--   map.catwalks          { x, y, w, h } the spans between them, world px
--   map.posts             where guards stand ({ x, y, watch, at }: `at` the platform's name)
--   map.zones             { name, y0, y1 } as City 17's
--   map.cover             { kind = "crate" | "barrier" | "console", x, y, w, h }, all solid
--   map.backdrop          what lies down in the drop, drawn and never touched:
--                         { kind = "core", x, y, r }, { kind = "pillar", x, y, w, h, depth },
--                         { kind = "girder", x, y, w, h, depth }, { kind = "rail", x0, y0, x1, y1, pods },
--                         { kind = "light", x, y, r, warm }
-- render_citadel.lua draws it all.

local Citadel = {}

-- How each kind shows on the minimap (minimap draws any cover with a `mapColor`).
local MAP = {
  crate = { 0.40, 0.44, 0.48 },
  barrier = { 0.30, 0.55, 0.70 },
  console = { 0.45, 0.80, 0.95 },
}

--- Build it into `map` (Layout.generate's, with tiles still empty). `T` is the tile size.
function Citadel.build(map, rng, T)
  local function X(c)
    return map.x0 + c * T
  end
  local function Y(r)
    return map.y0 + r * T
  end
  local function fill(c0, r0, c1, r1)
    for c = math.max(0, c0), math.min(map.cols - 1, c1) do
      map.tiles[c] = map.tiles[c] or {}
      for r = math.max(0, r0), math.min(map.rows - 1, r1) do
        map.tiles[c][r] = "walk"
      end
    end
  end
  map.platforms, map.catwalks, map.posts, map.zones, map.cover, map.backdrop = {}, {}, {}, {}, {}, {}
  local placed = {} -- { x, y, r }: kept clear of cover (the way across each platform, the guards)

  --- A platform over tiles (c0, r0)-(c1, r1), inclusive.
  local function platform(name, kind, c0, r0, c1, r1)
    fill(c0, r0, c1, r1)
    local p = { name = name, kind = kind, x = X(c0), y = Y(r0), w = (c1 - c0 + 1) * T, h = (r1 - r0 + 1) * T }
    map.platforms[#map.platforms + 1] = p
    map.zones[#map.zones + 1] = { name = name, y0 = p.y, y1 = p.y + p.h }
    return p
  end
  local runs = {} -- { x0, y0, x1, y1, width } each straight run's middle line, for the cover along it
  --- A catwalk `width` tiles wide through tile centres `pts` ({ c, r }), straight
  --- runs only, each run kept clear of cover where it crosses a platform.
  --- `bare` keeps cover off it.
  local function catwalk(width, pts, bare)
    local lo, hi = -math.floor((width - 1) / 2), math.floor(width / 2)
    for i = 1, #pts - 1 do
      local a, b = pts[i], pts[i + 1]
      local c0, c1 = math.min(a[1], b[1]), math.max(a[1], b[1])
      local r0, r1 = math.min(a[2], b[2]), math.max(a[2], b[2])
      if a[2] == b[2] then
        r0, r1 = r0 + lo, r1 + hi
        c0, c1 = c0 + lo, c1 + hi
      else
        c0, c1 = c0 + lo, c1 + hi
        r0, r1 = r0 + lo, r1 + hi
      end
      fill(c0, r0, c1, r1)
      map.catwalks[#map.catwalks + 1] = { x = X(c0), y = Y(r0), w = (c1 - c0 + 1) * T, h = (r1 - r0 + 1) * T }
      local ax, ay, bx, by = X(a[1] + 0.5), Y(a[2] + 0.5), X(b[1] + 0.5), Y(b[2] + 0.5)
      if not bare then
        -- The run's middle line: an even width sits between tiles, not on one.
        local shift = width % 2 == 0 and T / 2 or 0
        local sx, sy = a[2] == b[2] and 0 or shift, a[2] == b[2] and shift or 0
        runs[#runs + 1] = { x0 = ax + sx, y0 = ay + sy, x1 = bx + sx, y1 = by + sy, width = width * T }
      end
      local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
      for d = 0, len, 60 do
        local k = d / math.max(len, 1)
        placed[#placed + 1] = { x = ax + (bx - ax) * k, y = ay + (by - ay) * k, r = 70 }
      end
    end
  end
  --- Guards on platform `p`, standing at (c, r) in tiles, watching (wc, wr).
  local function post(p, c, r, wc, wr)
    local x, y = X(c + 0.5), Y(r + 0.5)
    map.posts[#map.posts + 1] = { x = x, y = y, watch = math.atan2(Y(wr) - y, X(wc) - x), at = p.name }
    placed[#placed + 1] = { x = x, y = y, r = 60 }
  end
  local function free(x, y, r)
    for _, q in ipairs(placed) do
      if (q.x - x) ^ 2 + (q.y - y) ^ 2 < (q.r + r + 50) ^ 2 then
        return false
      end
    end
    return true
  end
  local function cover(kind, x, y, w, h)
    local s = { kind = kind, x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h),
      mapColor = MAP[kind], seed = rng:random(1000) }
    map.cover[#map.cover + 1] = s
    map.solids[#map.solids + 1] = { x = s.x, y = s.y, w = s.w, h = s.h }
    placed[#placed + 1] = { x = x + w / 2, y = y + h / 2, r = math.max(w, h) / 2 }
  end
  --- Cover scattered over platform `p`, `n` pieces, off the way across and the guards.
  local function scatter(p, n)
    local got = 0
    for _ = 1, 300 do
      if got >= n then
        return
      end
      local x = p.x + 90 + rng:random() * (p.w - 180)
      local y = p.y + 90 + rng:random() * (p.h - 180)
      if free(x, y, 50) then
        local roll = rng:random()
        if roll < 0.45 then
          local s = 56 + rng:random(0, 1) * 24
          cover("crate", x - s / 2, y - s / 2, s, s)
        elseif roll < 0.85 then
          local len = 120 + rng:random() * 60
          if rng:random() < 0.5 then
            cover("barrier", x - len / 2, y - 14, len, 28)
          else
            cover("barrier", x - 14, y - len / 2, 28, len)
          end
        else
          cover("console", x - 36, y - 24, 72, 48)
        end
        got = got + 1
      end
    end
  end

  -- The way up, bottom to top. Columns and rows in tiles; the map is 84 x 112.
  local lift = platform("the lift", "lift", 38, 96, 49, 103)
  local pens = platform("the pens", "arena", 14, 76, 27, 89)
  local landing = platform("the span", "landing", 34, 59, 38, 65)
  local floor = platform("the processing floor", "arena", 52, 54, 66, 67)
  local gallery = platform("the gallery", "arena", 22, 36, 35, 49)
  local reactor = platform("the reactor deck", "arena", 62, 24, 74, 35)
  local top = platform("the top", "top", 30, 8, 52, 18)

  catwalk(3, { { 43, 96 }, { 43, 83 }, { 27, 83 } }) -- up off the lift and left to the pens
  catwalk(3, { { 20, 76 }, { 20, 62 }, { 34, 62 } }) -- up out of the pens to the landing
  catwalk(2, { { 38, 62 }, { 52, 62 } }, true) -- the long span over the core: narrower, nothing to hide behind
  catwalk(3, { { 59, 54 }, { 59, 43 }, { 35, 43 } }) -- up off the floor and back left to the gallery
  catwalk(3, { { 28, 36 }, { 28, 29 }, { 62, 29 } }) -- up out of the gallery and right to the reactor deck
  catwalk(2, { { 68, 24 }, { 68, 13 }, { 52, 13 } }) -- up off the reactor deck and left to the top

  -- Guards on every wide spot, on its far side, watching the way in.
  post(pens, 16, 79, 27, 83)
  post(pens, 25, 78, 27, 83)
  post(pens, 18, 86, 27, 83)
  post(landing, 36, 60, 32, 62)
  post(floor, 63, 57, 52, 62)
  post(floor, 55, 56, 52, 62)
  post(floor, 64, 64, 52, 62)
  post(gallery, 24, 39, 35, 43)
  post(gallery, 32, 38, 35, 43)
  post(gallery, 25, 46, 35, 43)
  post(reactor, 71, 27, 62, 29)
  post(reactor, 65, 33, 62, 29)
  post(reactor, 72, 32, 62, 29)
  post(top, 34, 11, 52, 13)
  post(top, 44, 10, 52, 13)
  post(top, 46, 16, 52, 13)

  -- Cover along the catwalks: a crate or a barrier against one rail, then
  -- the other, every few strides, the way past always open. None near a
  -- turn or a platform, so nobody gets wedged on a corner.
  local function nearFloor(x, y, pad)
    for _, p in ipairs(map.platforms) do
      if x > p.x - pad and x < p.x + p.w + pad and y > p.y - pad and y < p.y + p.h + pad then
        return true
      end
    end
    return false
  end
  local side = 1
  for _, run in ipairs(runs) do
    local dx, dy = run.x1 - run.x0, run.y1 - run.y0
    local len = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dx / len, dy / len
    local nx, ny = -uy, ux -- across the run
    local d = 260 + rng:random() * 100
    while d < len - 300 do
      local mx, my = run.x0 + ux * d, run.y0 + uy * d
      if not nearFloor(mx, my, 220) then
        local crate = rng:random() < 0.5
        local along, across = crate and 52 or 110, crate and 52 or 28
        local off = run.width / 2 - 8 - across / 2 -- against the rail
        local cx, cy = mx + nx * off * side, my + ny * off * side
        local w = math.abs(ux) * along + math.abs(nx) * across
        local h = math.abs(uy) * along + math.abs(ny) * across
        cover(crate and "crate" or "barrier", cx - w / 2, cy - h / 2, w, h)
        side = -side
      end
      d = d + 300 + rng:random() * 120
    end
  end

  -- Cover on the wide spots: the lift and the landing stay bare.
  scatter(pens, 6)
  scatter(floor, 7)
  scatter(gallery, 6)
  scatter(reactor, 6)
  scatter(top, 5)

  -- Arrival on the lift, the way home at its left end, the way on at the top.
  map.cx, map.cy = math.floor(lift.x + 90), math.floor(lift.y + lift.h / 2)
  for i = 0, 15 do
    map.spawns[#map.spawns + 1] = {
      x = lift.x + 230 + (i % 8) * 64, y = lift.y + 170 + math.floor(i / 8) * 120, angle = -math.pi / 2,
    }
  end
  map.exitX, map.exitY = math.floor(top.x + top.w / 2), math.floor(top.y + 110)

  -- Down in the drop. Nothing here is solid; the canvas draws it under the catwalks.
  local W, H = map.cols * T, map.rows * T
  local function onFloor(x, y, pad)
    for _, p in ipairs(map.platforms) do
      if x > p.x - pad and x < p.x + p.w + pad and y > p.y - pad and y < p.y + p.h + pad then
        return true
      end
    end
    return false
  end
  -- The core, glowing up from the bottom of the shaft under the long span.
  map.backdrop[#map.backdrop + 1] = { kind = "core", x = X(45), y = Y(62.5), r = 9 * T }
  -- Girders far down, crossing the shaft one way or the other.
  for _ = 1, 26 do
    local depth = 0.35 + rng:random() * 0.4
    if rng:random() < 0.5 then
      local y = map.y0 + rng:random() * H
      local x = map.x0 + rng:random() * W * 0.5
      map.backdrop[#map.backdrop + 1] = { kind = "girder", x = x, y = y, w = W * (0.3 + rng:random() * 0.5),
        h = 18 + rng:random() * 22, depth = depth }
    else
      local x = map.x0 + rng:random() * W
      local y = map.y0 + rng:random() * H * 0.5
      map.backdrop[#map.backdrop + 1] = { kind = "girder", x = x, y = y, w = 18 + rng:random() * 22,
        h = H * (0.3 + rng:random() * 0.5), depth = depth }
    end
  end
  -- Pillars rising out of the dark, their tops well below the catwalks.
  local got = 0
  for _ = 1, 400 do
    if got >= 30 then
      break
    end
    local w, h = (1.5 + rng:random() * 3) * T, (1.5 + rng:random() * 3) * T
    local x, y = map.x0 + rng:random() * (W - w), map.y0 + rng:random() * (H - h)
    local core = map.backdrop[1]
    local clearOfCore = (x + w / 2 - core.x) ^ 2 + (y + h / 2 - core.y) ^ 2 > (core.r + 200) ^ 2
    if clearOfCore and not onFloor(x + w / 2, y + h / 2, 260) then
      map.backdrop[#map.backdrop + 1] = { kind = "pillar", x = x, y = y, w = w, h = h,
        depth = 0.5 + rng:random() * 0.4, seed = rng:random(1000) }
      got = got + 1
    end
  end
  -- Rails the pods ride on, right across the shaft, a few pods on each.
  for i = 1, 4 do
    local y0 = map.y0 + (0.12 + (i - 1) * 0.24 + rng:random() * 0.08) * H
    local y1 = y0 + (rng:random() - 0.5) * H * 0.3
    local pods = {}
    for k = 1, 3 + rng:random(0, 3) do
      pods[k] = rng:random()
    end
    map.backdrop[#map.backdrop + 1] = { kind = "rail", x0 = map.x0, y0 = y0, x1 = map.x0 + W, y1 = y1, pods = pods }
  end
  -- Lights far below: most a cold blue, some the orange of work going on.
  for _ = 1, 260 do
    map.backdrop[#map.backdrop + 1] = { kind = "light", x = map.x0 + rng:random() * W, y = map.y0 + rng:random() * H,
      r = 2 + rng:random() * 4, warm = rng:random() < 0.2 }
  end
end

return Citadel
