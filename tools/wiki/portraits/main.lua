-- The wiki's enemy portraits (docs/wiki.md): `make wiki-portraits`.
--
-- A LÖVE program, run from the repository's root through build/wiki-love
-- (the Makefile links this folder's files and the game's in there). It is
-- the audit's headless game (tools/audit/harness.lua: the real game on its
-- stub, every frame stepped by hand) with LÖVE's real graphics put back,
-- so the game draws for real. It plays the city and every quest the way
-- the audit tours them (tools/audit/stages.lua), and the first time it
-- meets an enemy the wiki has a page for, it walks the player up to it and
-- draws it: only its own feature's drawing, centred on it, on a plain
-- ground, cropped to what was drawn round it. One PNG per page, in
-- docs/wiki/enemies/img. First it draws every gun's and ability's picture
-- (tools/wiki/items.lua) with the game's own icons, as the inventory shows
-- them: docs/wiki/weapons/img, docs/wiki/abilities/img.
--
-- WIKI_ONLY="icons city a-man karen" plays only those (the icons, the city,
-- and quest ids). WIKI_ALL=1 draws every picture again; otherwise only
-- missing ones.

package.path = "./?.lua;./?/init.lua;" .. package.path

-- The audit's stub for everything but drawing: its clock, loopback network,
-- silent audio and files read straight off the disk.
local real = love
local Stub = require("tools.audit.stub")
Stub.install()
local stub = love
_G.love = real
local KEEP = { graphics = true, image = true, window = true, font = true }
for k, v in pairs(stub) do
  if not KEEP[k] then
    real[k] = v
  end
end
Stub.install = function() end -- the harness installs it again otherwise

local Harness = require("tools.audit.harness")
local Stages = require("tools.audit.stages")
local Pages = require("tools.wiki.pages")
local Items = require("tools.wiki.items")
local Scenes = require("tools.wiki.scenes")

local OUT = 320 -- px, a portrait's side
local BG = { 0.86, 0.85, 0.82 }
local SPAN = 160 -- px across at most for anything smaller than its radius says
local SOLID = 0.25 -- how opaque a pixel must be to be part of something (faint cones and glows aren't)
local NEAR = 140 -- px from the enemy the player is put, so it is synced and in view

local function log(fmt, ...)
  io.stdout:write(("portraits: " .. fmt .. "\n"):format(...))
  io.stdout:flush()
end

-- The feature's own world drawing, centred on (x, y) at `zoom`, into `canvas`.
local BOTH, ABOVE = { "drawBelowCars", "drawAboveCars" }, { "drawAboveCars" }

local function drawAt(game, feature, x, y, zoom, canvas, draw, hooks, bg, seed)
  local w, h = canvas:getDimensions()
  -- The same dice every time, so the same frame draws the same on any ground
  -- (a crackling arc, sparks).
  math.randomseed(seed)
  love.math.setRandomSeed(seed)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(bg[1], bg[2], bg[3], 1)
  love.graphics.translate(w / 2, h / 2)
  love.graphics.scale(zoom)
  love.graphics.translate(-x, -y)
  local camera = { x = x, y = y, scale = zoom }
  -- No words: names, speech bubbles' lines and the like aren't the enemy.
  local g = love.graphics
  local print_, printf, rectangle = g.print, g.printf, g.rectangle
  g.print, g.printf = function() end, function() end -- luacheck: ignore 122
  -- Nor bars over heads or the boxes of speech bubbles: square to the world
  -- (not turned with a body, the way everything of a body is drawn) and
  -- wider than they are tall.
  g.rectangle = function(mode, rx, ry, rw, rh, ...) -- luacheck: ignore 122
    local _, oy = g.transformPoint(0, 0)
    local _, turn = g.transformPoint(1, 0)
    if math.abs(turn - oy) < 1e-6 and rw and rh and rw >= 2 * rh then
      return
    end
    return rectangle(mode, rx, ry, rw, rh, ...)
  end
  if draw then
    draw()
  else
    for _, hook in ipairs(hooks or BOTH) do
      if feature[hook] then
        feature[hook](feature, game.client, camera)
      end
    end
  end
  g.print, g.printf, g.rectangle = print_, printf, rectangle -- luacheck: ignore 122
  love.graphics.pop()
end

--- The same drawing on black and on white, as image data, (w x h).
local function onBlackAndWhite(w, h, msaa, paint)
  local out = {}
  for i, bg in ipairs({ { 0, 0, 0 }, { 1, 1, 1 } }) do
    local canvas = love.graphics.newCanvas(w, h, { msaa = msaa })
    paint(canvas, bg)
    out[i] = canvas:newImageData()
    canvas:release()
  end
  return out[1], out[2]
end

--- A shadow's grey (a flying thing's falls away from it), on white: not where to start.
local function shadowy(white, x, y)
  local r, g, b = white:getPixel(x, y)
  return math.abs(r - g) < 0.05 and math.abs(g - b) < 0.07 and r > 0.4 and r < 0.8
end

--- Painted there, not a faint glow over the ground: it comes out the same on
--- black as on white, whatever its colour (a pixel `a` opaque differs by 1 - a).
local function inked(black, white, x, y)
  local r0, g0, b0 = black:getPixel(x, y)
  local r1, g1, b1 = white:getPixel(x, y)
  return (r1 - r0) + (g1 - g0) + (b1 - b0) <= 3 * (1 - SOLID)
end

--- The shape the enemy is in a drawing (`black`, `white`): every painted
--- pixel joined (8 ways) to the painted pixel nearest the centre, looking no
--- further than `reach` px out for it. Its health bar, a speech bubble, a
--- neighbour are other shapes and are left out. Returns the set
--- (y * w + x -> true) and its box.
local function shape(black, white, reach)
  local w, h = black:getDimensions()
  local cx, cy = math.floor(w / 2), math.floor(h / 2)
  local sx, sy
  for r = 0, math.floor(reach) do
    for dy = -r, r do
      for dx = -r, r do
        if (math.abs(dx) == r or math.abs(dy) == r) and not sx then
          local x, y = cx + dx, cy + dy
          if x >= 0 and y >= 0 and x < w and y < h and inked(black, white, x, y) and not shadowy(white, x, y) then
            sx, sy = x, y
          end
        end
      end
    end
    if sx then
      break
    end
  end
  if not sx then
    return nil
  end
  local set, stack = { [sy * w + sx] = true }, { sx, sy }
  local x0, y0, x1, y1 = sx, sy, sx, sy
  while #stack > 0 do
    local y = table.remove(stack)
    local x = table.remove(stack)
    x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = x + dx, y + dy
        local key = ny * w + nx
        if nx >= 0 and ny >= 0 and nx < w and ny < h and not set[key] and inked(black, white, nx, ny) then
          set[key] = true
          stack[#stack + 1] = nx
          stack[#stack + 1] = ny
        end
      end
    end
  end
  return set, x0, y0, x1, y1
end

local function portrait(game, entry, e, draw, hooks)
  local feature = game.Features.byName[entry.feature]
  local radius = entry.portraitReach or (e.radius or 12) * 4
  local seed = love.math.random(1, 1e6)
  local probeZoom = math.min(3, 400 / radius)
  local black, white = onBlackAndWhite(1024, 1024, 0, function(canvas, bg)
    drawAt(game, feature, e.x, e.y, probeZoom, canvas, draw, hooks, bg, seed)
  end)
  local set, x0, y0, x1, y1 = shape(black, white, radius * probeZoom)
  black:release()
  white:release()
  if not set then
    if hooks == ABOVE then
      return portrait(game, entry, e, nil, BOTH) -- drawn under cars (the police on foot)
    end
    return false, "nothing drawn there"
  end
  -- Back to world units round (e.x, e.y).
  x0, y0, x1, y1 = (x0 - 512) / probeZoom, (y0 - 512) / probeZoom, (x1 - 512) / probeZoom, (y1 - 512) / probeZoom
  local span = math.max(x1 - x0, y1 - y0) * 1.2 + 4
  if span > math.max(SPAN, (e.radius or 12) * 12) then
    -- Run into something else of its feature's (a neighbour): another time.
    return false, ("%d px across, too big"):format(span)
  end
  local cx, cy, zoom = e.x + (x0 + x1) / 2, e.y + (y0 + y1) / 2, OUT / span
  local canvas = love.graphics.newCanvas(OUT, OUT, { msaa = 4 })
  drawAt(game, feature, cx, cy, zoom, canvas, draw, hooks, BG, seed)
  local final = canvas:newImageData()
  canvas:release()
  black, white = onBlackAndWhite(OUT, OUT, 4, function(c, bg)
    drawAt(game, feature, cx, cy, zoom, c, draw, hooks, bg, seed)
  end)
  local keep = shape(black, white, OUT / 4)
  black:release()
  white:release()
  if keep then
    -- Everything that isn't the enemy goes back to the plain ground.
    final:mapPixel(function(x, y, r, g, b, a)
      if keep[y * OUT + x] then
        return r, g, b, a
      end
      return BG[1], BG[2], BG[3], 1
    end)
  end
  local path = ("%s/%s.png"):format(Pages.IMAGES, Pages.id(entry))
  local f = assert(io.open(path, "wb"))
  f:write(final:encode("png"):getString())
  f:close()
  final:release()
  return true
end

-- A gun is drawn side on at GUN_SCALE times its icon's size (about 60 x 30),
-- on the portraits' ground; an ability as its slot shows it, on a dark
-- disc with a ring in its colour, ICON_R px across the middle.
local GUN_W, GUN_H, GUN_SCALE = 320, 160, 3.4
local ICON_SIDE, ICON_R = 160, 64

local function save(canvas, path)
  local data = canvas:newImageData()
  local f = assert(io.open(path, "wb"))
  f:write(data:encode("png"):getString())
  f:close()
  data:release()
end

local function itemPicture(it)
  local GunIcons = require("src.features.weapons.icons")
  local AbilityIcons = require("src.features.abilities.icons")
  local UI = require("src.ui")
  local gun = it.section.key == "weapons"
  local w, h = gun and GUN_W or ICON_SIDE, gun and GUN_H or ICON_SIDE
  local canvas = love.graphics.newCanvas(w, h, { msaa = 4 })
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  if gun then
    love.graphics.clear(BG[1], BG[2], BG[3], 1)
    GunIcons.draw(it.key, w / 2, h / 2, GUN_SCALE)
  else
    love.graphics.clear(0, 0, 0, 0)
    local c, cx, cy = it.base.color, w / 2, h / 2
    love.graphics.setColor(0.08, 0.08, 0.1, 1)
    love.graphics.circle("fill", cx, cy, ICON_R + 12, 64)
    love.graphics.setColor(c[1], c[2], c[3], 0.2)
    love.graphics.circle("fill", cx, cy, ICON_R + 12, 64)
    UI.ring(cx, cy, ICON_R, 1, c, 10)
    AbilityIcons.draw(it.key, cx, cy, ICON_R - 14)
  end
  love.graphics.pop()
  os.execute("mkdir -p " .. it.section.images)
  save(canvas, it.image)
  canvas:release()
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
  end
  return f ~= nil
end

local function main()
  local game = assert(Harness.boot())
  -- The game screen itself is never looked at: only the portraits are drawn.
  game.drawing = false
  os.execute("mkdir -p " .. Pages.IMAGES)
  local entries, problems = Pages.collect(game.Features)
  for _, p in ipairs(problems) do
    log("%s", p)
  end
  local all = os.getenv("WIKI_ALL") == "1"
  local wanted = {} -- entries still to draw
  for _, e in ipairs(entries) do
    if e.portrait ~= false and (all or not exists(("%s/%s.png"):format(Pages.IMAGES, Pages.id(e)))) then
      wanted[#wanted + 1] = e
    end
  end

  local only = {}
  for id in (os.getenv("WIKI_ONLY") or ""):gmatch("%S+") do
    only[id] = true
  end
  local function playing(id)
    return next(only) == nil or only[id]
  end

  if playing("icons") then
    for _, it in ipairs(Items.all()) do
      if all or not exists(it.image) then
        itemPicture(it)
        log("drew %s", it.item)
      end
    end
  end

  -- What a scene draws itself (Scenes.portraits): not when only the icons are wanted.
  local enemiesToo = next(only) == nil
  for id in pairs(only) do
    enemiesToo = enemiesToo or id ~= "icons"
  end
  for i = (enemiesToo and #wanted or 0), 1, -1 do
    local entry = wanted[i]
    local draw = Scenes.portraits[Pages.id(entry)]
    if draw then
      local drawn, why = portrait(game, entry, { x = 0, y = 0, radius = 40 }, draw)
      log(drawn and "drew %s" or "could not draw %s: %s", Pages.id(entry), why)
      if drawn then
        table.remove(wanted, i)
      end
    end
  end

  -- Draw whatever wanted enemy is about now.
  local function look()
    for _, e in ipairs(game:enemies()) do
      for i = #wanted, 1, -1 do
        local entry = wanted[i]
        if entry.kind == e.kind and (not e.immune or entry.drawImmune) and (not entry.pick or entry.pick(e)) then
          local me = game:me()
          local fx, fy = me and me.body and me.body.x, me and me.body and me.body.y
          game:godMode()
          game:placeOnFoot(e.x + NEAR, e.y)
          game:run(0.4)
          for _, now in ipairs(game:enemies()) do
            if now.id == e.id then
              e = now -- where it is now, not where it was before the client caught up
            end
          end
          -- Bodies first, above cars, without the level under them (lava, vents, signs).
          local drawn, why = portrait(game, entry, e, nil, entry.portraitLayers == "all" and BOTH or ABOVE)
          if fx then
            game:placeOnFoot(fx, fy)
          end
          if drawn then
            log("drew %s", Pages.id(entry))
            table.remove(wanted, i)
          elseif why ~= entry.why then
            entry.why = why
            log("not yet %s: %s", Pages.id(entry), why)
          end
        end
      end
    end
  end


  if playing("city") then
    game:godMode()
    game:run(2)
    look()
  end
  for _, q in ipairs(game.Features.byName.quests.list) do
    if #wanted == 0 then
      break
    end
    if not q.returns and playing(q.id) then
      log("playing %s", q.id)
      game:godMode()
      if game:quest(q.id) then
        game:run(2)
        look()
        Stages.tour(game, q.id, function(x, y, seconds)
          game:godMode()
          game:placeOnFoot(x, y)
          game:run(seconds or 3)
          look()
        end)
        for _ = 1, 20 do -- a boss still talking comes out after a while
          game:godMode()
          game:run(1)
          look()
        end
        if Scenes.after[q.id] and #wanted > 0 then
          Scenes.after[q.id](game, look)
        end
        game:home()
      end
    end
  end
  if playing("city") then
    for _, scene in ipairs(Scenes.city) do
      if #wanted == 0 then
        break
      end
      local ok, why = scene(game, look)
      if ok == false then
        log("%s", why)
      end
    end
  end
  for _, entry in ipairs(wanted) do
    if next(only) == nil then
      log("never met %s (%s)", Pages.id(entry), entry.kind)
    end
  end
  for _, e in ipairs(game.errors) do
    log("error in %s: %s", e.where, e.message)
  end
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
  log("%s", err)
end
os.exit(ok and 0 or 1)
