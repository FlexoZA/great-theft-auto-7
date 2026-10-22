-- The Borderline quest line on the HUD, client side, in a comic-book look:
-- thick black outlines on yellow and white.
--   the intro screen  Handsome Jerry live on a Hyperbole broadcast: his
--                     portrait big on the right, his line in a speech box
--   the map banner    PANDORIA, where in the line it is, the map's name and
--                     tagline, on arriving
--   the zone banner   the part of the map just walked into (city-map's
--                     `map.zones`)
--   the comms         Jerry or Yappy's portrait and what they say, typed out
--   the objective     what to do next and how far it is
-- init.lua keeps the state and calls in here.

local UI = require("src.ui")
local Faces = require("src.features.borderline.faces")
local Story = require("src.features.borderline.story")

local Hud = {}

Hud.TYPE_RATE = 40 -- characters a second the words type out at
Hud.BANNER_TIME = 4.5 -- seconds the map banner stays up
Hud.ZONE_TIME = 2.6
Hud.SAY_HOLD = 3.5 -- seconds a line stays up once it is all typed out

local YELLOW = Story.speakers.jerry.color
local INK = { 0.06, 0.06, 0.07 }
local BG = { 0.14, 0.15, 0.17 }

--- How much of `text` is typed `t` seconds in.
function Hud.typed(text, t)
  return text:sub(1, math.max(0, math.floor(t * Hud.TYPE_RATE)))
end

--- How long `text` stays on the comms, typing and held.
function Hud.sayFor(text)
  return #text / Hud.TYPE_RATE + Hud.SAY_HOLD
end

--- `text` in `font` and `fill` with a hard black outline round it, the
--- comic way: printed at the eight neighbours in ink first.
local function inked(text, font, x, y, w, align, fill, a, thick)
  love.graphics.setFont(font)
  thick = thick or 2
  love.graphics.setColor(INK[1], INK[2], INK[3], a)
  for dx = -thick, thick, thick do
    for dy = -thick, thick, thick do
      if dx ~= 0 or dy ~= 0 then
        love.graphics.printf(text, x + dx, y + dy, w, align)
      end
    end
  end
  love.graphics.setColor(fill[1], fill[2], fill[3], a)
  love.graphics.printf(text, x, y, w, align)
end

--- Jerry's intro screen, `t` seconds up (his words type out).
function Hud.drawScreen(face, line, t, time)
  local w, h = love.graphics.getDimensions()
  love.graphics.setColor(BG)
  love.graphics.rectangle("fill", 0, 0, w, h)
  -- Hazard bands top and bottom, crawling along.
  local step = 40
  for _, y in ipairs({ 0, h - 18 }) do
    for x = -step * 2 + (time * 40) % (step * 2), w, step * 2 do
      love.graphics.setColor(YELLOW)
      love.graphics.polygon("fill", x, y, x + step, y, x + step + 18, y + 18, x + 18, y + 18)
    end
  end
  -- Him, big, on the right.
  local homeX, homeY = math.floor(w * 0.70), math.floor(h * 0.52)
  local scale = math.floor(math.min(h / 82, (w * 0.5) / 64))
  love.graphics.setColor(INK)
  love.graphics.rectangle("fill", homeX - 32 * scale - 6, homeY - 36 * scale - 6, 64 * scale + 12, 72 * scale + 12)
  face.talking = #Hud.typed(line, t) < #line
  face:draw(homeX, homeY, scale)

  local colX, colW = math.floor(math.max(40, w * 0.07)), math.floor(w * 0.42)
  local y = math.floor(h * 0.12)
  inked("HYPERBOLE BROADCAST  ·  LIVE", UI.fonts.small, colX, y, colW, "left", YELLOW, 1, 1)
  y = y + 28
  inked("HANDSOME JERRY", UI.fonts.title, colX, y, colW + 200, "left", YELLOW, 1, 3)
  y = y + UI.fonts.title:getHeight() + 8
  inked("CEO. Hero. Handsome.", UI.fonts.heading, colX, y, colW, "left", { 1, 1, 1 }, 1, 2)
  y = y + UI.fonts.heading:getHeight() + 36
  -- His words in a speech box, the tail pointing at him.
  local font = UI.fonts.body
  local _, full = font:getWrap(line, colW - 32)
  local bh = #full * font:getHeight() + 28
  love.graphics.setColor(INK)
  love.graphics.rectangle("fill", colX - 4, y - 4, colW + 8, bh + 8, 6)
  love.graphics.polygon("fill", colX + colW, y + bh * 0.3, colX + colW + 34, y + bh * 0.5, colX + colW, y + bh * 0.7)
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", colX, y, colW, bh, 4)
  love.graphics.polygon("fill", colX + colW - 1, y + bh * 0.36, colX + colW + 24, y + bh * 0.5,
    colX + colW - 1, y + bh * 0.64)
  love.graphics.setFont(font)
  love.graphics.setColor(INK)
  love.graphics.printf(Hud.typed(line, t), colX + 16, y + 14, colW - 32, "left")

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.75, 0.75, 0.7)
  love.graphics.printf("press any key", 0, h - 46, w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- How opaque something shown for `life` seconds is `t` in: in quickly,
--- out over its last `out` seconds.
local function fade(t, life, out)
  return math.max(0, math.min(1, t * 4, (life - t) / out))
end

--- The map banner, `t` seconds into its `Hud.BANNER_TIME`.
function Hud.drawBanner(b, t)
  local w, h = love.graphics.getDimensions()
  local a = fade(t, Hud.BANNER_TIME, 0.8)
  local y = math.floor(h * 0.22)
  inked(("PANDORIA  ·  %d / %d"):format(b.n, Story.LEVELS), UI.fonts.small, 0, y, w, "center", YELLOW, a, 1)
  y = y + 26
  inked(b.title, UI.fonts.title, 0, y, w, "center", YELLOW, a, 3)
  y = y + UI.fonts.title:getHeight() + 4
  inked(b.tagline, UI.fonts.body, 0, y, w, "center", { 1, 1, 1 }, a, 2)
  love.graphics.setColor(1, 1, 1)
end

--- The name of the part of the map just walked into.
function Hud.drawZone(name, t)
  local w, h = love.graphics.getDimensions()
  inked(name:upper(), UI.fonts.heading, 0, math.floor(h * 0.16), w, "center", { 1, 1, 1 },
    fade(t, Hud.ZONE_TIME, 0.6), 2)
  love.graphics.setColor(1, 1, 1)
end

local PANEL_X, PANEL_Y, PANEL_W = 10, 250, 470

--- `who` (a key of Story.speakers) on the comms: their portrait, their name
--- and `text` typed out `t` seconds in, fading out with `a`.
function Hud.drawComms(face, who, text, t, a)
  local speaker = Story.speakers[who]
  local font = UI.fonts.small
  local textX = PANEL_X + Faces.W + 22
  local textW = PANEL_W - (textX - PANEL_X) - 12
  local _, lines = font:getWrap(text, textW)
  local ph = math.max(Faces.H + 16, #lines * font:getHeight() + 40)
  love.graphics.setColor(INK[1], INK[2], INK[3], 0.9 * a)
  love.graphics.rectangle("fill", PANEL_X - 3, PANEL_Y - 3, PANEL_W + 6, ph + 6, 6)
  love.graphics.setColor(BG[1], BG[2], BG[3], 0.92 * a)
  love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, ph, 4)
  love.graphics.setColor(speaker.color[1], speaker.color[2], speaker.color[3], a)
  love.graphics.rectangle("fill", PANEL_X, PANEL_Y, 4, ph)
  face.talking = #Hud.typed(text, t) < #text
  face:draw(PANEL_X + 10 + Faces.W / 2, PANEL_Y + 8 + Faces.H / 2, 1)
  love.graphics.setFont(font)
  love.graphics.print(speaker.name, textX, PANEL_Y + 8)
  love.graphics.setColor(0.95, 0.95, 0.92, a)
  love.graphics.printf(Hud.typed(text, t), textX, PANEL_Y + 28, textW, "left")
  love.graphics.setColor(1, 1, 1)
end

--- What to do next, and how far it is (world px, or nil).
function Hud.drawObjective(text, distance)
  local line = distance and ("%s  (%d m)"):format(text, math.floor(distance / 10)) or text
  inked(line, UI.fonts.small, 10, 220, 900, "left", YELLOW, 1, 1)
  love.graphics.setColor(1, 1, 1)
end

return Hud
