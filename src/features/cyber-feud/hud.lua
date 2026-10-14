-- The Cyber Feud's lines on the HUD, client side:
--   the map banner   a neon title card on arriving on each map: GREY CITY,
--                    where in the line it is, its name and tagline
--   the zone banner  the part of the map you just walked or drove into
--                    (city-map's `map.zones`: NOODLE SQUARE, a tower floor)
--   the comms        VEX's small portrait and what she says, typed out,
--                    one line at a time off a queue
--   the objective    what to do next and how far it is
--   the bubbles      what the factions' soldiers say, over their heads
-- init.lua keeps the state and calls in here.

local UI = require("src.ui")
local Face = require("src.features.cyber-feud.face")
local Screen = require("src.features.cyber-feud.screen")

local Hud = {}

local GREEN = Face.GREEN
local MAGENTA = { 1, 0.24, 0.78 }
local CYAN = { 0.18, 0.9, 1 }

Hud.BANNER_TIME = 4.5 -- seconds the map banner stays up
Hud.ZONE_TIME = 2.6 -- seconds a zone's name stays up
Hud.SAY_HOLD = 4 -- seconds a line stays up once it is all typed out

--- The map banner, `t` seconds into its `Hud.BANNER_TIME`: flickers on,
--- holds, fades.
function Hud.drawBanner(b, t)
  local w, h = love.graphics.getDimensions()
  local a
  if t < 0.5 then
    a = (math.floor(t * 30) % 3 == 0) and 0.2 or t / 0.5 -- the neon catching
  elseif t > Hud.BANNER_TIME - 0.8 then
    a = math.max(0, (Hud.BANNER_TIME - t) / 0.8)
  else
    a = 1
  end
  local y = math.floor(h * 0.24)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], a)
  love.graphics.printf(("GREY CITY  ·  %d / %d"):format(b.n, b.of), 0, y, w, "center")
  y = y + 24
  love.graphics.setFont(UI.fonts.title)
  local j = 3 + math.floor(math.sin(t * 17) * 1.5)
  love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], a * 0.6)
  love.graphics.printf(b.title, -j, y, w, "center")
  love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], a * 0.6)
  love.graphics.printf(b.title, j, y + 1, w, "center")
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.printf(b.title, 0, y, w, "center")
  y = y + UI.fonts.title:getHeight() + 2
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0.85, 0.88, 0.95, a * 0.9)
  love.graphics.printf(b.tagline, 0, y, w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- The name of the part of the map just entered, fading out over `Hud.ZONE_TIME`.
function Hud.drawZone(name, kicker, t)
  local w, h = love.graphics.getDimensions()
  local a = math.min(1, t * 4, (Hud.ZONE_TIME - t) / 0.6)
  if a <= 0 then
    return
  end
  local y = math.floor(h * 0.16)
  if kicker then
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], a * 0.9)
    love.graphics.printf(kicker, 0, y - 20, w, "center")
  end
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0, 0, 0, a * 0.6)
  love.graphics.printf("—  " .. name:upper() .. "  —", 2, y + 2, w, "center")
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.printf("—  " .. name:upper() .. "  —", 0, y, w, "center")
  love.graphics.setColor(1, 1, 1)
end

local PANEL_X, PANEL_Y, PANEL_W = 10, 250, 470
local PORTRAIT = 1 -- screen px per art px

--- VEX on the comms: her portrait in a frame, her name and `text` typed
--- out `t` seconds in; fades as `fade` (1 to 0) runs out.
function Hud.drawComms(face, text, t, fade)
  local font = UI.fonts.small
  local textX = PANEL_X + Face.W * PORTRAIT + 22
  local textW = PANEL_W - (textX - PANEL_X) - 12
  local _, lines = font:getWrap(text, textW)
  local ph = math.max(Face.H * PORTRAIT + 16, #lines * font:getHeight() + 40)
  love.graphics.setColor(0.01, 0.04, 0.03, 0.8 * fade)
  love.graphics.rectangle("fill", PANEL_X, PANEL_Y, PANEL_W, ph, 4)
  love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.7 * fade)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", PANEL_X, PANEL_Y, PANEL_W, ph, 4)
  love.graphics.setLineWidth(1)
  face.talking = #Screen.typed(text, t) < #text
  face:draw(PANEL_X + 8 + Face.W * PORTRAIT / 2, PANEL_Y + 8 + Face.H * PORTRAIT / 2, PORTRAIT)
  love.graphics.setFont(font)
  love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], fade)
  love.graphics.print("VEX", textX, PANEL_Y + 8)
  local shown = Screen.typed(text, t)
  if #shown < #text then
    shown = shown .. "_"
  end
  love.graphics.setColor(0.88, 0.95, 0.9, fade)
  love.graphics.printf(shown, textX, PANEL_Y + 28, textW, "left")
  love.graphics.setColor(1, 1, 1)
end

--- The objective line, with how far off its point is when there is one.
function Hud.drawObjective(text, distance)
  if distance then
    text = text .. ("  (%d m)"):format(math.floor(distance / 10))
  end
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.print(text, 11, 221)
  love.graphics.setColor(0.75, 1, 0.82)
  love.graphics.print(text, 10, 220)
  love.graphics.setColor(1, 1, 1)
end

--- The prompt at the vending machine.
function Hud.drawPrompt(key)
  local w, h = love.graphics.getDimensions()
  local text = key .. ": take the package"
  love.graphics.setFont(UI.fonts.body)
  local tw = UI.fonts.body:getWidth(text) + 28
  local x, y = math.floor((w - tw) / 2), math.floor(h * 0.68)
  love.graphics.setColor(0.01, 0.04, 0.03, 0.85)
  love.graphics.rectangle("fill", x, y, tw, 36, 4)
  love.graphics.setColor(GREEN)
  love.graphics.rectangle("line", x, y, tw, 36, 4)
  love.graphics.printf(text, x, y + 7, tw, "center")
  love.graphics.setColor(1, 1, 1)
end

--- In the world: the vending machine calling out while the Shard is in it.
function Hud.drawMachine(x, y, time)
  local k = (time * 0.8) % 1
  love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.8 * (1 - k))
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", x, y, 24 + k * 60, 32)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- In the world: the Shard lying where it was dropped, a green chip
--- bobbing over a pulsing ring, calling to be picked up.
function Hud.drawDropped(x, y, time)
  local k = (time * 0.9) % 1
  love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.7 * (1 - k))
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", x, y, 14 + k * 46, 32)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0, 0, 0, 0.4)
  love.graphics.ellipse("fill", x, y + 6, 10, 4)
  local cy = y - 6 + math.sin(time * 4) * 3
  love.graphics.setColor(GREEN)
  love.graphics.polygon("fill", x, cy - 12, x + 8, cy, x, cy + 12, x - 8, cy)
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.polygon("fill", x, cy - 7, x + 3, cy - 1, x, cy + 2, x - 3, cy - 1)
  love.graphics.setColor(1, 1, 1)
end

--- A line of green text across the screen low down: what is holding the
--- level up (the Shard's carrier still to come to its end).
function Hud.drawNote(text)
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, 1, math.floor(h * 0.68) + 1, w, "center")
  love.graphics.setColor(GREEN)
  love.graphics.printf(text, 0, math.floor(h * 0.68), w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- In the world: a small green diamond over whoever carries the Shard.
function Hud.drawCarrier(x, y, time)
  local bob = math.sin(time * 4) * 3
  local cy = y - 44 + bob
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.polygon("fill", x, cy - 9, x + 7, cy + 1, x, cy + 11, x - 7, cy + 1)
  love.graphics.setColor(GREEN)
  love.graphics.polygon("fill", x, cy - 10, x + 6, cy, x, cy + 10, x - 6, cy)
  love.graphics.setColor(1, 1, 1, 0.8)
  love.graphics.polygon("fill", x, cy - 6, x + 2, cy - 1, x, cy + 1, x - 2, cy - 1)
  love.graphics.setColor(1, 1, 1)
end

--- In the world: what a faction's soldier says, in a bubble over (x, y) edged
--- in his side's `color`, the tail pointing down at him.
function Hud.drawBubble(x, y, text, alpha, color)
  local font = UI.fonts.small
  local maxW = 200
  local w, wrapped = font:getWrap(text, maxW)
  w = math.min(maxW, w) + 14
  local h = #wrapped * font:getHeight() + 10
  local bx, by = x - w / 2, y - h - 10
  love.graphics.setColor(0, 0, 0, 0.45 * alpha)
  love.graphics.rectangle("fill", bx + 2, by + 3, w, h, 4)
  love.graphics.setColor(0.09, 0.09, 0.11, 0.92 * alpha)
  love.graphics.rectangle("fill", bx, by, w, h, 4)
  love.graphics.polygon("fill", x - 5, by + h - 1, x + 5, by + h - 1, x, by + h + 7)
  love.graphics.setColor(color[1], color[2], color[3], 0.8 * alpha)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", bx, by, w, h, 4)
  love.graphics.setFont(font)
  love.graphics.setColor(color[1], color[2], color[3], alpha)
  love.graphics.printf(text, bx + 7, by + 5, w - 14, "center")
  love.graphics.setColor(1, 1, 1)
end

return Hud
