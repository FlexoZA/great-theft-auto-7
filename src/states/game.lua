-- The driving scene. The world is simulated by the server; this state sends
-- local input, smooths the snapshots it receives (every vehicle, everyone
-- on foot), draws them, and gives features their hooks. Keep gameplay out
-- of here: put it in src/features/.
--
-- Esc opens the pause menu over the world: resume, settings (the same
-- panel as the main menu's, over the game), leave the game (which ends it
-- for everyone when you are the host) or quit to the desktop, which asks
-- first and saves on the way out. The game is
-- not actually paused -- nothing pauses in multiplayer -- but the controls
-- are suspended so nothing you press or click reaches the car or the gun,
-- the network keeps flowing, and the world blurs under the menu.

local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Car = require("src.car")
local Body = require("src.body")
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
      self.confirmQuit = true
    end }),
  }
  self.quitMenu = {
    UI.button({ label = "Yes, quit", w = MENU_W, onClick = function()
      self:quitToDesktop()
    end }),
    UI.button({ label = "Cancel", w = MENU_W, onClick = function()
      self.confirmQuit = false
    end }),
  }
end

--- Save and leave: the host writes the world and everyone in it before the
--- server closes (Server:close), a joiner says goodbye so the host saves
--- them, then the window goes.
function Game:quitToDesktop()
  Net.shutdown()
  love.event.quit()
end

--- What quitting does to this game, under the question.
local function quitNote()
  if Net.isHost() then
    if Net.server and Net.server.world then
      return "The world is saved first. Everyone playing is sent back to the menu."
    end
    return "This game is not a saved world: it ends for everyone and is gone."
  end
  if Net.client and Net.client.worldName then
    return "The host saves your progress in " .. Net.client.worldName .. "."
  end
  return "This game is not a saved world: nothing of it is kept."
end

--- The buttons up right now: the pause menu, or the quit question.
function Game:menuButtons()
  return self.confirmQuit and self.quitMenu or self.menu
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
  self.confirmQuit = false
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
  for i, b in ipairs(self:menuButtons()) do
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
  local title = self.confirmQuit and "QUIT TO DESKTOP?" or "PAUSED"
  love.graphics.printf(title, 0, math.floor(h / 2) - 130, w, "center")
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  local note = self.confirmQuit and quitNote() or "The game carries on without you: get back in it."
  love.graphics.printf(note, 0, math.floor(h / 2) - 72, w, "center")
  for _, b in ipairs(self:menuButtons()) do
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
  for _, c in pairs(client.vehicles) do
    if math.abs(c.x - c.dx) > SNAP_DISTANCE or math.abs(c.y - c.dy) > SNAP_DISTANCE then
      c.dx, c.dy, c.dangle = c.x, c.y, c.angle
    else
      c.dx = c.dx + (c.x - c.dx) * k
      c.dy = c.dy + (c.y - c.dy) * k
      c.dangle = c.dangle + angleDiff(c.angle, c.dangle) * k
    end
  end
  -- Walkers ease the same way; a feature that predicts one (on-foot, for
  -- the local player) marks it and moves it itself.
  for _, b in pairs(client.bodies) do
    if not b.predicted then
      local ex, ey = b.x - b.dx, b.y - b.dy
      if ex * ex + ey * ey > SNAP_DISTANCE * SNAP_DISTANCE then
        b.dx, b.dy, b.dangle = b.x, b.y, b.angle
      else
        local mx, my = ex * k, ey * k
        b.dx, b.dy = b.dx + mx, b.dy + my
        b.dangle = b.dangle + angleDiff(b.angle, b.dangle) * k
        b.running = mx * mx + my * my > (dt * 90) ^ 2
      end
    end
  end

  -- The camera follows me, driving or walking, and stays put while I am
  -- out of the world (a wreck waiting to respawn). Features add their pans
  -- and shakes on top every frame, so it is re-anchored every frame or they
  -- would pile up.
  local mx, my = client:myPose()
  if mx then
    self.focus.x, self.focus.y = mx, my
    -- Audio listener rides with me. World y maps to audio z so that
    -- positional sources pan left/right by x and fade with distance.
    love.audio.setPosition(mx, 0, my)
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

local function drawName(client, id, x, y)
  local p = client.players[id]
  if p then
    love.graphics.setColor(1, 1, 1, id == client.myId and 1 or 0.8)
    love.graphics.printf(p.name, x - 60, y, 120, "center")
  end
end

--- Every vehicle in its own colour, the driver's name over it. A parked car
--- is just a car. A feature that draws a car its own way (vehicles, for a
--- model) answers `drawVehicle` with true and the box is left out.
function Game:drawVehicles(client)
  love.graphics.setFont(UI.fonts.small)
  for _, c in pairs(client.vehicles) do
    if not Features.any("drawVehicle", client, c) then
      Car.draw(c.dx, c.dy, c.dangle, Car.paletteColor(c.color))
    end
    if c.driver then
      drawName(client, c.driver, c.dx, c.dy - Car.HEIGHT - 18)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- Everyone on foot, in their colour, waddling as they go.
function Game:drawBodies(client)
  love.graphics.setFont(UI.fonts.small)
  local t = love.timer.getTime()
  for id, b in pairs(client.bodies) do
    local swing = math.sin(t * (b.running and 16 or 8) + (b.bob or 0)) * (b.running and 1.5 or 0.9)
    Body.draw(b.dx, b.dy, b.dangle, Car.colorFor(id), swing)
    drawName(client, id, b.dx, b.dy - 30)
  end
  love.graphics.setColor(1, 1, 1)
end

--- The world through the camera: features below, vehicles and walkers,
--- features above.
function Game:drawWorld(client, w, h)
  love.graphics.push()
  love.graphics.translate(math.floor(w / 2), math.floor(h / 2))
  love.graphics.scale(self.camera.scale or 1)
  love.graphics.translate(-math.floor(self.camera.x), -math.floor(self.camera.y))
  Features.call("drawBelowCars", client, self.camera)
  self:drawVehicles(client)
  self:drawBodies(client)
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

  local me = client:myVehicle()
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
  if key == "escape" and self.confirmQuit then
    self.confirmQuit = false -- back to the pause menu
    return
  end
  if key == "escape" then
    -- A panel up in the game (inventory, shop) goes down first; only a bare
    -- Esc pauses.
    if self.paused or not Features.any("closeMenu", Net.client) then
      self:setPaused(not self.paused)
    end
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
    for _, b in ipairs(self:menuButtons()) do
      if b:mousepressed(x, y, button) then
        return
      end
    end
    return
  end
  Features.call("mousepressed", x, y, button, Net.client)
end

function Game:wheelmoved(dx, dy)
  if self.paused then
    if self.settingsOpen then
      self.settings:wheelmoved(dx, dy)
    end
    return -- the menu owns the wheel
  end
  Features.call("wheelmoved", dx, dy, Net.client)
end

return Game
