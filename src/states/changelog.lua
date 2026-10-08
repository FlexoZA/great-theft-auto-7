-- Changelog screen: every release in CHANGELOG.md (read by src/version.lua),
-- newest first, on a scrolling panel over the menu background. Reached from
-- the icon in the bottom-left corner of the main menu; Back or Esc returns.
-- Opening it marks the current version as read, which clears the menu
-- icon's dot.

local State = require("src.state")
local UI = require("src.ui")
local Audio = require("src.audio")
local Settings = require("src.settings")
local Version = require("src.version")
local Background = require("src.art.menu_background")

local Changelog = {}

local PANEL_W = 760
local CONTENT_TOP = 70 -- px below the panel top where the list starts
local CONTENT_BOTTOM = 70 -- px above the panel bottom it stops: Back lives there
local PAD = 30
local BULLET_INDENT = 18
local SCROLL_STEP = 48

--- Has the player not opened the changelog since the version changed?
function Changelog.unread()
  return Settings.get("changelog.seen") ~= Version.label
end

function Changelog:enter()
  UI.load()
  Audio.playMenuTheme()
  self.background = Background.shared()
  self.scroll = 0
  self.maxScroll = 0
  self.linesFor = nil
  Settings.set("changelog.seen", Version.label)
  self.backButton = UI.button({ label = "Back", w = 200, onClick = function()
    State.switch("menu")
  end })
end

--- Lay the releases out as lines for a text column `width` px wide: each
--- entry { font=, color=, text=, x=, y= } relative to the top of the list.
function Changelog:buildLines(width)
  local lines, y = {}, 0
  local function add(font, color, text, indent, gapAfter)
    local _, wrapped = font:getWrap(text, width - indent)
    for _, t in ipairs(wrapped) do
      table.insert(lines, { font = font, color = color, text = t, x = indent, y = y })
      y = y + font:getHeight()
    end
    y = y + (gapAfter or 0)
  end
  -- A bullet: the dash in the margin, the text wrapped beside it.
  local function bullet(text)
    table.insert(lines, { font = UI.fonts.body, color = { 0.55, 0.75, 1 }, text = "-", x = 2, y = y })
    add(UI.fonts.body, { 1, 1, 1 }, text, BULLET_INDENT, 4)
  end

  for _, r in ipairs(Version.releases) do
    if not r.unreleased or Version.hasItems(r) then
      local title = r.unreleased and "Coming next" or ("Version " .. r.version)
      if r.date then
        title = title .. "  -  " .. r.date
      end
      add(UI.fonts.heading, { 1, 0.85, 0.35 }, title, 0, 6)
      if r.summary then
        add(UI.fonts.body, { 0.75, 0.75, 0.8 }, r.summary, 0, 8)
      end
      for _, s in ipairs(r.sections) do
        if #s.items > 0 then
          if s.title ~= "" then
            add(UI.fonts.small, { 0.55, 0.75, 1 }, s.title:upper(), 0, 4)
          end
          for _, item in ipairs(s.items) do
            bullet(item)
          end
          y = y + 8
        end
      end
      y = y + 24
    end
  end
  if #lines == 0 then
    add(UI.fonts.body, { 0.75, 0.75, 0.8 }, "No changelog found.", 0)
  end
  return lines, y
end

function Changelog:layout()
  local w, h = love.graphics.getDimensions()
  local pw = math.min(PANEL_W, w - 40)
  local px = math.floor((w - pw) / 2)
  local py = math.floor(h * 0.06)
  local ph = math.floor(h * 0.88)
  self.panel = { x = px, y = py, w = pw, h = ph }
  self.clip = { x = px + 1, y = py + CONTENT_TOP, w = pw - 2, h = ph - CONTENT_TOP - CONTENT_BOTTOM }
  local textW = pw - 2 * PAD - 12
  if self.linesFor ~= textW then
    self.lines, self.contentH = self:buildLines(textW)
    self.linesFor = textW
  end
  self.maxScroll = math.max(0, self.contentH - self.clip.h)
  self.scroll = math.max(0, math.min(self.scroll, self.maxScroll))
  self.backButton.x, self.backButton.y = px + 10, py + ph - 56
end

function Changelog:update(dt)
  self.background:update(dt)
  self:layout()
end

function Changelog:draw()
  if not self.panel then
    self:layout()
  end
  self.background:drawDimmed()
  local p, c = self.panel, self.clip
  UI.panel(p.x, p.y, p.w, p.h)

  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("What's new", p.x + 20, p.y + 16)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.5, 0.5, 0.55)
  local major, minor = love.getVersion()
  local tag = "v" .. Version.label .. "  -  LÖVE " .. major .. "." .. minor
  love.graphics.printf(tag, p.x, p.y + 26, p.w - 20, "right")

  love.graphics.setScissor(c.x, c.y, c.w, c.h)
  local x0, y0 = p.x + PAD, c.y + 6 - self.scroll
  for _, l in ipairs(self.lines) do
    local y = y0 + l.y
    if y + l.font:getHeight() >= c.y and y <= c.y + c.h then
      love.graphics.setFont(l.font)
      love.graphics.setColor(l.color)
      love.graphics.print(l.text, x0 + l.x, y)
    end
  end
  love.graphics.setScissor()

  if self.maxScroll > 0 then
    local trackX, trackY, trackH = p.x + p.w - 12, c.y, c.h
    local thumbH = math.max(24, trackH * c.h / (c.h + self.maxScroll))
    local thumbY = trackY + (trackH - thumbH) * (self.scroll / self.maxScroll)
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.rectangle("fill", trackX, trackY, 6, trackH, 3)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.rectangle("fill", trackX, thumbY, 6, thumbH, 3)
  end

  self.backButton:draw()
  love.graphics.setColor(1, 1, 1)
end

function Changelog:scrollBy(px)
  self.scroll = math.max(0, math.min(self.scroll + px, self.maxScroll))
end

function Changelog:keypressed(key)
  if key == "escape" or key == "backspace" then
    State.switch("menu")
  elseif key == "down" then
    self:scrollBy(SCROLL_STEP)
  elseif key == "up" then
    self:scrollBy(-SCROLL_STEP)
  elseif key == "pagedown" or key == "space" then
    self:scrollBy(self.clip.h - SCROLL_STEP)
  elseif key == "pageup" then
    self:scrollBy(-(self.clip.h - SCROLL_STEP))
  elseif key == "home" then
    self.scroll = 0
  elseif key == "end" then
    self.scroll = self.maxScroll
  end
end

function Changelog:mousepressed(x, y, button)
  self.backButton:mousepressed(x, y, button)
end

function Changelog:wheelmoved(_dx, dy)
  self:scrollBy(-dy * SCROLL_STEP)
end

return Changelog
