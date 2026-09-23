-- The driving scene. All cars are simulated by the server; this state sends
-- local input, smooths the snapshots it receives, draws everyone, and gives
-- features their hooks. Keep gameplay out of here: put it in src/features/.
--
-- Esc opens the pause menu over the world: resume, settings (the same
-- panel as the main menu's, over the game), leave the game (which ends it
-- for everyone when you are the host) or quit to the desktop. The game is
-- not actually paused -- nothing pauses in multiplayer -- but the controls
-- are suspended so nothing you press or click reaches the car or the gun,
-- the network keeps flowing, and the world blurs under the menu.

local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Car = require("src.car")
local Features = require("src.features")
local Audio = require("src.audio")
local Video = require("src.video")
local Controls = require("src.controls")
local SettingsPanel = require("src.settings_panel")

local Game = {}

local SMOOTHING = 12 -- per second; higher = snappier, lower = smoother
local SNAP_DISTANCE = 200 -- a jump bigger than this is a teleport (respawn), don't ease it
local BLUR_RATE = 6 -- per second; how fast the world softens and clears again
local RESUME_GRACE = 0.15 -- seconds the controls stay suspended after the menu closes, so the click that
-- closed it can't fire the gun
local MENU_W = 300
local BLUR_RADIUS = 3 -- px per pass at full strength (two passes each way)

-- A separable 5-tap Gaussian, sampled between texels so it costs five reads.
-- `dir` is one step along the pass in texture space, already scaled by the
-- radius; the game draws horizontally then vertically.
local BLUR_SHADER = [[
  extern vec2 dir;
  vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec4 sum = Texel(tex, uv) * 0.227027;
    vec2 o1 = dir * 1.384615;
    vec2 o2 = dir * 3.230769;
    sum += (Texel(tex, uv + o1) + Texel(tex, uv - o1)) * 0.316216;
    sum += (Texel(tex, uv + o2) + Texel(tex, uv - o2)) * 0.070270;
    return sum * color;
  }
]]

local function angleDiff(target, current)
  return (target - current + math.pi) % (2 * math.pi) - math.pi
end

function Game:enter()
  UI.load()
  Audio.pauseMusic()
  -- Features may move the camera and change its scale in their update hook.
  self.camera = { x = 0, y = 0, scale = 1 }
  self.focus = { x = 0, y = 0 } -- where the camera is anchored: the car, or where it last was
  self.blur = 0 -- current softening of the world, 0..1, eased towards what features ask for
  if not self.blurShader then
    -- No shader support is not fatal: the world just stays sharp.
    local ok, shader = pcall(love.graphics.newShader, BLUR_SHADER)
    self.blurShader = ok and shader or false
  end
  self.paused = false
  self.settingsOpen = false
  self.resumeGrace = 0
  Controls.suspend(false)
  self:buildMenu()
  Features.call("enterGame", Net.client)
end

function Game:exit()
  self:setPaused(false)
  self.resumeGrace = 0
  Controls.suspend(false) -- no update is coming to run the grace out
  Features.call("exitGame", Net.client)
  love.audio.setPosition(0, 0, 0)
end

-- Pause menu ----------------------------------------------------------------

function Game:buildMenu()
  self.menu = {
    UI.button({ label = "Resume", w = MENU_W, onClick = function()
      self:setPaused(false)
    end }),
    UI.button({ label = "Settings", w = MENU_W, onClick = function()
      self:openSettings()
    end }),
    UI.button({ label = Net.isHost() and "End game for everyone" or "Leave game", w = MENU_W, onClick = function()
      Net.shutdown()
      State.switch("menu")
    end }),
    UI.button({ label = "Quit to desktop", w = MENU_W, onClick = function()
      love.event.quit()
    end }),
  }
end

--- The settings panel over the pause menu; Back (or Esc) returns to the menu.
function Game:openSettings()
  self.settings = self.settings or SettingsPanel.new({ onClose = function()
    self.settingsOpen = false
  end })
  self.settings:build() -- live values may have changed since last time
  self.settingsOpen = true
end

--- Open or close the menu. The mouse is handed back to the desktop while it
--- is up (a feature may have grabbed and hidden it) and restored after.
function Game:setPaused(on)
  if on == self.paused then
    return
  end
  self.paused = on
  self.settingsOpen = false
  if on then
    self.mouseWas = { grabbed = love.mouse.isGrabbed(), visible = love.mouse.isVisible() }
    love.mouse.setGrabbed(false)
    love.mouse.setVisible(true)
    Controls.suspend(true)
  else
    if self.mouseWas then
      love.mouse.setGrabbed(self.mouseWas.grabbed)
      love.mouse.setVisible(self.mouseWas.visible)
      self.mouseWas = nil
    end
    self.resumeGrace = RESUME_GRACE -- Controls.suspend(false) once it runs out
  end
end

function Game:layoutMenu()
  local w, h = love.graphics.getDimensions()
  local x = math.floor((w - MENU_W) / 2)
  local y = math.floor(h / 2) - 40
  for i, b in ipairs(self.menu) do
    b.x, b.y = x, y + (i - 1) * 56
  end
end

function Game:drawMenu()
  local w, h = love.graphics.getDimensions()
  self:layoutMenu()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setFont(UI.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("PAUSED", 0, math.floor(h / 2) - 130, w, "center")
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.printf("The game carries on without you: get back in it.", 0, math.floor(h / 2) - 72, w, "center")
  for _, b in ipairs(self.menu) do
    b:draw()
  end
  love.graphics.setColor(1, 1, 1)
end

function Game:update(dt)
  Net.update(dt)
  local client = Net.client
  if not client then
    State.switch("menu")
    return
  end

  if self.resumeGrace > 0 then
    self.resumeGrace = self.resumeGrace - dt
    if self.resumeGrace <= 0 and not self.paused then
      Controls.suspend(false)
    end
  end
  if self.paused and self.settingsOpen then
    self.settings:update(dt)
  end

  -- With the controls suspended this reads as hands off the wheel, which is
  -- what the server should hear while the menu is up.
  local throttle, steer, handbrake = Car.readInput()
  client:sendInput(throttle, steer, dt, handbrake)

  local k = math.min(1, dt * SMOOTHING)
  for _, c in pairs(client.cars) do
    if math.abs(c.x - c.dx) > SNAP_DISTANCE or math.abs(c.y - c.dy) > SNAP_DISTANCE then
      c.dx, c.dy, c.dangle = c.x, c.y, c.angle
    else
      c.dx = c.dx + (c.x - c.dx) * k
      c.dy = c.dy + (c.y - c.dy) * k
      c.dangle = c.dangle + angleDiff(c.angle, c.dangle) * k
    end
  end

  -- The camera follows the car and stays put when there is no car to follow
  -- (a wreck waiting to respawn). Features add their pans and shakes on top
  -- every frame, so it is re-anchored every frame or they would pile up.
  local me = client:myCar()
  if me then
    self.focus.x, self.focus.y = me.dx, me.dy
    -- Audio listener rides with the car. World y maps to audio z so that
    -- positional sources pan left/right by x and fade with distance.
    love.audio.setPosition(me.dx, 0, me.dy)
  end
  self.camera.x, self.camera.y = self.focus.x, self.focus.y

  Features.call("update", dt, client, self.camera)

  -- How soft a feature wants the world (weapons, while you are wrecked),
  -- eased so it never snaps in or out.
  local target = self.paused and 1 or 0
  for _, f in ipairs(Features.list) do
    if f.worldBlur then
      target = math.max(target, math.min(1, f:worldBlur(client) or 0))
    end
  end
  self.blur = self.blur + (target - self.blur) * math.min(1, dt * BLUR_RATE)
  if self.blur < 0.01 then
    self.blur = 0
  end
end

function Game:drawCars(client)
  love.graphics.setFont(UI.fonts.small)
  for id, c in pairs(client.cars) do
    Car.draw(c.dx, c.dy, c.dangle, Car.colorFor(id))
    local p = client.players[id]
    -- A feature may have taken the driver out of the car (on-foot). The car
    -- then stands there unnamed and the feature labels the figure instead.
    if p and not Features.any("hidesCarLabel", client, id) then
      love.graphics.setColor(1, 1, 1, id == client.myId and 1 or 0.8)
      love.graphics.printf(p.name, c.dx - 60, c.dy - Car.HEIGHT - 18, 120, "center")
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- The world through the camera: features below, cars, features above.
function Game:drawWorld(client, w, h)
  love.graphics.push()
  love.graphics.translate(math.floor(w / 2), math.floor(h / 2))
  love.graphics.scale(self.camera.scale or 1)
  love.graphics.translate(-math.floor(self.camera.x), -math.floor(self.camera.y))
  Features.call("drawBelowCars", client, self.camera)
  self:drawCars(client)
  Features.call("drawAboveCars", client, self.camera)
  love.graphics.pop()
end

--- Two window-sized canvases to blur through, rebuilt when the window changes.
function Game:blurCanvases(w, h)
  local c = self.canvases
  if not c or c.w ~= w or c.h ~= h then
    c = { w = w, h = h, a = love.graphics.newCanvas(w, h), b = love.graphics.newCanvas(w, h) }
    self.canvases = c
  end
  return c.a, c.b
end

--- The world softened by `self.blur`: drawn into a canvas, then smeared
--- horizontally and vertically, twice, before it reaches the screen. The
--- HUD is drawn after this and stays sharp.
function Game:drawWorldBlurred(client, w, h)
  local a, b = self:blurCanvases(w, h)
  local shader = self.blurShader
  love.graphics.setCanvas(a)
  love.graphics.clear(love.graphics.getBackgroundColor())
  self:drawWorld(client, w, h)

  local r = BLUR_RADIUS * self.blur
  love.graphics.setColor(1, 1, 1)
  love.graphics.setShader(shader)
  for _ = 1, 2 do
    shader:send("dir", { r / w, 0 })
    love.graphics.setCanvas(b)
    love.graphics.clear()
    love.graphics.draw(a)
    shader:send("dir", { 0, r / h })
    love.graphics.setCanvas(a)
    love.graphics.clear()
    love.graphics.draw(b)
  end
  love.graphics.setShader()
  love.graphics.setCanvas()
  love.graphics.draw(a)
end

function Game:draw()
  local client = Net.client
  if not client then
    return
  end
  local w, h = love.graphics.getDimensions()
  if self.blur > 0 and self.blurShader then
    self:drawWorldBlurred(client, w, h)
  else
    self:drawWorld(client, w, h)
  end

  if self.paused then
    -- No HUD under it: the menu, or the settings panel, is the whole screen.
    if self.settingsOpen then
      love.graphics.setColor(0, 0, 0, 0.45)
      love.graphics.rectangle("fill", 0, 0, w, h)
      self.settings:draw()
    else
      self:drawMenu()
    end
    return
  end
  Features.call("drawHUD", client)

  local me = client:myCar()
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 1, 1)
  if Video.get("showFps") then
    love.graphics.print(("FPS %d  speed %.0f"):format(love.timer.getFPS(), me and me.speed or 0), 10, 10)
  else
    love.graphics.print(("speed %.0f"):format(me and me.speed or 0), 10, 10)
  end
  local hb = require("src.controls").name(require("src.controls").bindings("handbrake")[1])
  love.graphics.print("Arrows/WASD to drive, " .. hb .. ": handbrake, Esc to leave", 10, 28)

  local text
  if client:isConnected() then
    local role = Net.isHost() and "hosting" or "connected"
    text = ("%s  players: %d  tick %d"):format(role, client:playerCount(), client.lastTick)
    love.graphics.setColor(0.7, 0.9, 0.7)
  else
    text = "connection lost: " .. tostring(client.error)
    love.graphics.setColor(1, 0.4, 0.4)
  end
  love.graphics.printf(text, 0, 10, w - 10, "right")
end

function Game:keypressed(key)
  if self.paused and self.settingsOpen then
    self.settings:keypressed(key) -- Esc there closes the panel, not the menu
    return
  end
  if key == "escape" then
    self:setPaused(not self.paused)
    return
  end
  if self.paused then
    return -- the menu owns the keyboard
  end
  Features.call("keypressed", key, Net.client)
end

function Game:mousepressed(x, y, button)
  if self.paused then
    if self.settingsOpen then
      self.settings:mousepressed(x, y, button)
      return
    end
    for _, b in ipairs(self.menu) do
      if b:mousepressed(x, y, button) then
        return
      end
    end
    return
  end
  Features.call("mousepressed", x, y, button, Net.client)
end

function Game:wheelmoved(dx, dy)
  if self.paused and self.settingsOpen then
    self.settings:wheelmoved(dx, dy)
  end
end

return Game
