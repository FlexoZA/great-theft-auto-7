-- Weather: rain, and lightning, turned on by whatever feature wants them
-- (General Volt's fight in the Market, so far). Nothing changes on its own:
-- the host says when it rains and when a storm is on, every screen draws it.
--
--   weather:serverSetRain(server, on)    rain on every screen, fading in or out
--   weather:serverSetStorm(server, on)   flashes in the sky now and then, with thunder far off
--   weather:serverStrike(server, x, y, opts)
--       a bolt of lightning: marked on the ground (a flickering ring) for
--       `opts.warn` seconds, then it strikes, hurting everyone on foot and
--       every car in `opts.radius` (`opts.damage`, `opts.carDamage`, shock)
--       and a few pedestrians, with a flash and thunder close by
--
-- All of it stops when the map changes. The rain is drawn over the dark of
-- the night (a lens just after the night feature's): streaks slanting down
-- the screen that move with the world as you do, and splashes on the
-- ground. A flash lights the whole view; on a dark map it lights the night
-- itself (`drawNightLights`). A bolt is the tripod's (tripod/render.lua).
--
-- Messages
--   server -> all  WTH_RAIN  <0|1>                        (to a joiner too)
--   server -> all  WTH_FLASH <x> <y>                      lightning in the sky over there
--   server -> all  WTH_BOLT  <x> <y> <warn> <radius>      a bolt will strike there in `warn` seconds

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Car = require("src.car")
local BoltRender = require("src.features.tripod.render")
local Sounds = require("src.features.weather.sounds")

local Weather = {
  name = "weather",
  priority = 401, -- its lens (the rain) just after the night's (400), under the weapons' (950)
}

-- Tuning ------------------------------------------------------------------
Weather.fadeIn = 3 -- seconds the rain takes to come down in full...
Weather.fadeOut = 5 -- ...and to stop
Weather.drops = 260 -- streaks on screen at full rain
Weather.fall = 1300 -- px/s down the screen
Weather.wind = 0.22 -- how far a streak leans: px across per px down
Weather.splashes = 60 -- per second on screen at full rain
Weather.flashEvery = { 3, 7 } -- seconds between flashes in the sky in a storm
Weather.flashRange = 800 -- px; a strike closer than this lights up the screen
Weather.strike = { warn = 1, radius = 50, damage = 20, carDamage = 30 } -- serverStrike's defaults

local BOLT_LIFE = 0.35 -- seconds a strike is drawn

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function fmt(n)
  return ("%.0f"):format(n)
end

-- Client --------------------------------------------------------------------

local function fresh()
  return {
    raining = false, rain = 0, drops = {}, splashes = {}, splashIn = 0, bolts = {}, flash = 0, thunder = {},
    cam = nil, lastCam = nil,
  }
end

-- { raining, rain (0..1), drops, splashes, splashIn, bolts, flash, thunder, cam, lastCam }. Kept from one
-- game to the next and only cleared on the way out: WTH_RAIN for a joiner can come before START.
local cl = fresh()
local time = 0

function Weather:load()
  if love.audio then
    Sounds.load()
  end
end

function Weather:exitGame()
  cl = fresh()
  Sounds.rain(0)
end

--- A streak somewhere on a `w` x `h` screen (anywhere, or just above it).
local function newDrop(w, h, top)
  return {
    x = random() * (w + h * Weather.wind) - h * Weather.wind,
    y = top and -random() * 80 or random() * h,
    len = 14 + random() * 16,
    speed = Weather.fall * (0.8 + random() * 0.4),
    a = 0.18 + random() * 0.22,
  }
end

--- Light the screen up by `k` (0..1), more if it is already brighter.
local function flash(k)
  cl.flash = math.max(cl.flash, k)
end

function Weather:update(dt, client, camera)
  time = time + dt
  cl.cam = camera
  local target = cl.raining and 1 or 0
  local rate = cl.raining and 1 / Weather.fadeIn or 1 / Weather.fadeOut
  cl.rain = cl.rain + math.max(-rate * dt, math.min(rate * dt, target - cl.rain))
  Sounds.rain(cl.rain)
  cl.flash = math.max(0, cl.flash - dt * 2.5)
  -- Thunder after a flash in the sky: as far off as the gap is long.
  for i = #cl.thunder, 1, -1 do
    local th = cl.thunder[i]
    th.t = th.t - dt
    if th.t <= 0 then
      Sounds.play("rumble", nil, nil, 0.8 + random() * 0.3, 0.6)
      table.remove(cl.thunder, i)
    end
  end
  -- Bolts counting down to their strike.
  for i = #cl.bolts, 1, -1 do
    local b = cl.bolts[i]
    b.t = b.t - dt
    if b.t <= 0 and not b.hit then
      b.hit = true
      Sounds.play("thunder", b.x, b.y, 0.85 + random() * 0.3)
      local mx, my = client:myPose()
      if mx then
        flash(1 - math.sqrt(dist2(mx, my, b.x, b.y)) / Weather.flashRange)
      end
    end
    if b.hit and b.t <= -BOLT_LIFE then
      table.remove(cl.bolts, i)
    end
  end
  -- The rain on screen: streaks falling and leaning, carried along as the
  -- view moves so they belong to the world, and splashes coming and going.
  local w, h = love.graphics.getDimensions()
  local s = camera and camera.scale or 1
  local mx, my = 0, 0
  if camera and cl.lastCam then
    mx, my = (camera.x - cl.lastCam.x) * s, (camera.y - cl.lastCam.y) * s
  end
  cl.lastCam = camera and { x = camera.x, y = camera.y } or nil
  local want = math.floor(Weather.drops * cl.rain + 0.5)
  while #cl.drops < want do
    cl.drops[#cl.drops + 1] = newDrop(w, h, false)
  end
  for i = #cl.drops, 1, -1 do
    local d = cl.drops[i]
    d.x, d.y = d.x + d.speed * Weather.wind * dt - mx, d.y + d.speed * dt - my
    if d.y > h + 40 or d.y < -120 or d.x < -h * Weather.wind - 40 or d.x > w + 40 then
      if #cl.drops > want then
        table.remove(cl.drops, i)
      else
        cl.drops[i] = newDrop(w, h, true)
      end
    end
  end
  cl.splashIn = cl.splashIn - dt * Weather.splashes * cl.rain
  while cl.splashIn < 0 do
    cl.splashIn = cl.splashIn + 1
    cl.splashes[#cl.splashes + 1] = { x = random() * w, y = random() * h, t = 0 }
  end
  for i = #cl.splashes, 1, -1 do
    local sp = cl.splashes[i]
    sp.x, sp.y, sp.t = sp.x - mx, sp.y - my, sp.t + dt
    if sp.t > 0.35 then
      table.remove(cl.splashes, i)
    end
  end
end

function Weather:mapChanged(_map, server)
  cl = fresh()
  Weather.serverClear(server)
end

--- The bolts, marked and striking, in the world.
function Weather:drawAboveCars()
  for _, b in ipairs(cl.bolts) do
    if b.hit then
      BoltRender.bolt(b.x, b.y, b.seed, math.min(1, -b.t / BOLT_LIFE))
    else
      BoltRender.boltWarning(b.x, b.y, b.radius, 1 - b.t / b.warn, time)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- On a dark map a flash lights the night itself, and a strike lights the
--- ground round it.
function Weather:drawNightLights(_client, camera, glow)
  if not camera then
    return
  end
  if cl.flash > 0 then
    local w, h = love.graphics.getDimensions()
    local s = camera.scale or 1
    love.graphics.setColor(0.6 * cl.flash, 0.65 * cl.flash, 0.8 * cl.flash, 1)
    love.graphics.rectangle("fill", camera.x - w / s, camera.y - h / s, w * 2 / s, h * 2 / s)
  end
  for _, b in ipairs(cl.bolts) do
    if b.hit then
      glow(b.x, b.y, 260, { 0.75, 0.85, 1 }, 1 + b.t / BOLT_LIFE)
    else
      glow(b.x, b.y, b.radius * 1.6, { 0.5, 0.75, 1 }, 0.35)
    end
  end
end

--- The rain and the flash, over the world (and the night's dark) but under the HUD.
function Weather:drawLens()
  if cl.rain <= 0.001 and cl.flash <= 0 then
    return
  end
  local w, h = love.graphics.getDimensions()
  love.graphics.push("all")
  love.graphics.origin()
  if cl.rain > 0.001 then
    love.graphics.setColor(0.05, 0.07, 0.12, 0.18 * cl.rain) -- the air thick with it
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setLineWidth(1)
    for _, d in ipairs(cl.drops) do
      love.graphics.setColor(0.7, 0.8, 0.95, d.a * cl.rain)
      love.graphics.line(d.x, d.y, d.x - d.len * Weather.wind, d.y - d.len)
    end
    for _, sp in ipairs(cl.splashes) do
      local k = sp.t / 0.35
      love.graphics.setColor(0.75, 0.85, 1, 0.35 * (1 - k) * cl.rain)
      love.graphics.ellipse("line", sp.x, sp.y, 2 + 7 * k, 1 + 3 * k)
    end
  end
  if cl.flash > 0 then
    love.graphics.setColor(0.85, 0.92, 1, 0.22 * cl.flash)
    love.graphics.rectangle("fill", 0, 0, w, h)
  end
  love.graphics.pop()
end

Weather.clientMessages = {
  WTH_RAIN = function(_client, args)
    cl.raining = args[1] == "1"
  end,
  WTH_FLASH = function(client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not (x and y) then
      return
    end
    local mx, my = client:myPose()
    local d = mx and math.sqrt(dist2(mx, my, x, y)) or 1000
    flash(0.6 + random() * 0.4)
    cl.thunder[#cl.thunder + 1] = { t = 0.3 + d / 1500 + random() * 0.5 }
  end,
  WTH_BOLT = function(_client, args)
    local x, y, warn, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and warn and r then
      cl.bolts[#cl.bolts + 1] = { x = x, y = y, t = warn, warn = math.max(0.01, warn), radius = r, seed = random() }
    end
  end,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { rain, storm, flashIn, bolts = { { x, y, t, radius, damage, carDamage } } }

function Weather:serverStart()
  sv = { rain = false, storm = false, flashIn = 0, bolts = {} }
end

--- Clear skies (the map changed).
function Weather.serverClear(server)
  if not sv then
    return
  end
  sv.storm, sv.bolts = false, {}
  if sv.rain and server then
    sv.rain = false
    server:broadcast(Protocol.encode("WTH_RAIN", 0))
  end
  sv.rain = false
end

--- Rain on every screen, or not.
function Weather:serverSetRain(server, on)
  if not sv or sv.rain == (on and true or false) then
    return
  end
  sv.rain = on and true or false
  server:broadcast(Protocol.encode("WTH_RAIN", sv.rain and 1 or 0))
end

--- A storm: flashes in the sky now and then, with thunder rolling in after.
function Weather:serverSetStorm(_server, on)
  if sv then
    sv.storm = on and true or false
    sv.flashIn = 1 + random() * 2
  end
end

--- A bolt of lightning at (x, y), marked first (see the top of the file).
function Weather:serverStrike(server, x, y, opts)
  if not sv then
    return
  end
  local o = opts or {}
  local d = Weather.strike
  local b = { x = x, y = y, t = o.warn or d.warn, radius = o.radius or d.radius, damage = o.damage or d.damage,
    carDamage = o.carDamage or d.carDamage }
  sv.bolts[#sv.bolts + 1] = b
  server:broadcast(Protocol.encode("WTH_BOLT", fmt(x), fmt(y), ("%.2f"):format(b.t), fmt(b.radius)))
end

--- A bolt comes down: everyone on foot (players and bots) and every car in
--- its radius are hurt (shock), and a few pedestrians.
local function strike(server, b)
  local weapons = Features.byName.weapons
  local r = b.radius
  if weapons then
    for _, p in pairs(server.players) do
      if Features.present(p) then
        local px, py, onFoot = Features.bodyPose(server, p)
        if onFoot and dist2(px, py, b.x, b.y) <= r * r then
          weapons:serverDamage(server, p, nil, b.damage, math.atan2(py - b.y, px - b.x), "shock")
        end
      end
    end
    if weapons.damageCar then
      local reach = r + Car.WIDTH / 2
      for _, car in pairs(server.vehicles) do
        if not (car.hidden or car.stowed) and dist2(car.x, car.y, b.x, b.y) <= reach * reach then
          weapons:damageCar(server, car, nil, b.carDamage, 0, 0, "shock")
        end
      end
    end
  end
  local peds = Features.byName.pedestrians
  if peds and peds.serverShotAt then
    for _ = 1, 3 do
      if not peds:serverShotAt(server, b.x, b.y, r, 0, 0, nil, "shock") then
        break
      end
    end
  end
end

function Weather:serverStep(server, dt)
  if not sv then
    return
  end
  for i = #sv.bolts, 1, -1 do
    local b = sv.bolts[i]
    b.t = b.t - dt
    if b.t <= 0 then
      table.remove(sv.bolts, i)
      strike(server, b)
    end
  end
  if sv.storm then
    sv.flashIn = sv.flashIn - dt
    if sv.flashIn <= 0 then
      local e = Weather.flashEvery
      sv.flashIn = e[1] + random() * (e[2] - e[1])
      -- Somewhere over the humans, off to one side: who sees it hears it after.
      for _, p in pairs(server.players) do
        if not p.bot and Features.present(p) then
          local x, y = Features.bodyPose(server, p)
          local a = random() * 2 * math.pi
          server:broadcast(Protocol.encode("WTH_FLASH", fmt(x + math.cos(a) * 900), fmt(y + math.sin(a) * 900)))
          break
        end
      end
    end
  end
end

function Weather:serverPlayerJoined(server, player)
  if sv and sv.rain and not player.bot then
    server:send(player, Protocol.encode("WTH_RAIN", 1))
  end
end

return Weather
