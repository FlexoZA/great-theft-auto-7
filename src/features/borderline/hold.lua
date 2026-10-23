-- Holding a spot while Yappy hacks it (docs/borderline.md): Liar's
-- Landing's ferry lift, later Thousand Papercuts' bunker door. The map's
-- `hold` says where and how long; init.lua keeps the level's way on shut
-- until it is done (`serverLocked`, as the terminals do) and passes its
-- hooks on to this module.
--
-- The hack runs while any player stands on the spot, and stops (it does
-- not drain) while nobody does. The first one on starts it. The army sends
-- waves at the spot as the hack goes: each wave comes when the hack gets
-- `at` of the way through, so walking off never piles them up. Yappy
-- frets while nobody is on it.
--
-- The map's side (city-map/borderline.lua):
--   map.hold  { x, y, w, h (px, the spot), time (seconds of standing on it),
--               waves = { { at = 0..1, codes = { code... }, x, y (px, where they come from) } } }
--
-- Messages
--   server -> all  BRL_HOLD <0..1> <on>   how far the hack is, and whether anyone is on the spot (1) or not (0);
--                                         four times a second once started, and once when done; to a joiner, now

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")

local Hold = {}

-- Tuning ------------------------------------------------------------------
Hold.MARGIN = 24 -- px off the spot's edge that still counts as on it
Hold.ALONE_AFTER = 4 -- seconds with nobody on it before Yappy says so...
Hold.ALONE_EVERY = 12 -- ...and then at most this often

local SEND_EVERY = 0.25
local AMBER = { 1.00, 0.72, 0.18 }
local GREEN = { 0.43, 1, 0.6 }
local GREY = { 0.55, 0.58, 0.62 }

local function encode(progress, on)
  return Protocol.encode("BRL_HOLD", ("%.3f"):format(progress), on and 1 or 0)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { spec, progress, started, done, on, wave, sendIn, offFor, aloneIn }

--- A level starts on `map`: a hold if it has one.
function Hold.serverStart(map)
  sv = nil
  if map and map.hold then
    sv = { spec = map.hold, progress = 0, started = false, done = false, on = false, wave = 1, sendIn = 0,
      offFor = 0, aloneIn = 0 }
  end
end

function Hold.serverStop()
  sv = nil
end

--- Does the hold still keep the way on shut?
function Hold.serverLocked()
  return sv ~= nil and not sv.done
end

--- Is any player standing on the spot?
local function anyoneOn(server, spec)
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if x >= spec.x - Hold.MARGIN and x <= spec.x + spec.w + Hold.MARGIN
        and y >= spec.y - Hold.MARGIN and y <= spec.y + spec.h + Hold.MARGIN then
        return true
      end
    end
  end
  return false
end

--- `beat(what)` raises a story beat ("hold" when it starts, "half"
--- halfway); `chat(who, category)` a line of chatter; `wave(codes, x, y,
--- toX, toY)` sends robots from (x, y) at the spot's middle.
function Hold.serverStep(server, dt, beat, chat, wave)
  if not sv or sv.done then
    return
  end
  local spec = sv.spec
  sv.on = anyoneOn(server, spec)
  if sv.on and not sv.started then
    sv.started = true
    beat("hold")
  end
  if not sv.started then
    return
  end
  if sv.on then
    local was = sv.progress
    sv.progress = math.min(1, sv.progress + dt / spec.time)
    sv.offFor = 0
    if was < 0.5 and sv.progress >= 0.5 then
      beat("half")
    end
  else
    sv.offFor = sv.offFor + dt
    sv.aloneIn = sv.aloneIn - dt
    if sv.offFor >= Hold.ALONE_AFTER and sv.aloneIn <= 0 then
      sv.aloneIn = Hold.ALONE_EVERY
      chat("yappy", "alone")
    end
  end
  local w = spec.waves[sv.wave]
  while w and sv.progress >= w.at do
    wave(w.codes, w.x, w.y, spec.x + spec.w / 2, spec.y + spec.h / 2)
    sv.wave = sv.wave + 1
    w = spec.waves[sv.wave]
  end
  if sv.progress >= 1 then
    sv.done = true
    server:broadcast(encode(1, sv.on))
    return
  end
  sv.sendIn = sv.sendIn - dt
  if sv.sendIn <= 0 then
    sv.sendIn = SEND_EVERY
    server:broadcast(encode(sv.progress, sv.on))
  end
end

function Hold.serverPlayerJoined(server, player)
  if sv and sv.started then
    server:send(player, encode(sv.progress, sv.on))
  end
end

-- Client --------------------------------------------------------------------

local shown = nil -- { progress, on } once the host says it started
local clock = 0

function Hold.clear()
  shown = nil
end

function Hold.update(dt)
  clock = clock + dt
end

--- How far the hack on this screen is: nil before it starts, else
--- progress (0..1) and whether anyone is on the spot.
function Hold.shown()
  if shown then
    return shown.progress, shown.on
  end
  return nil
end

--- On the spot itself (under the cars): its edge, lit while the hack runs,
--- and a bar across it filling as it goes.
function Hold.drawBelowCars(map)
  local spec = map and map.hold
  if not spec then
    return
  end
  local p = shown and shown.progress or 0
  local done = p >= 1
  local color = done and GREEN or (shown and not shown.on) and GREY or AMBER
  local k = 0.5 - 0.5 * math.cos(clock * 2 * math.pi / 1.4)
  love.graphics.setLineWidth(3)
  love.graphics.setColor(color[1], color[2], color[3], shown and (0.45 + 0.4 * k) or 0.25 + 0.2 * k)
  love.graphics.rectangle("line", spec.x - 6, spec.y - 6, spec.w + 12, spec.h + 12, 6)
  love.graphics.setLineWidth(1)
  if not shown then
    return
  end
  local bx, by, bw, bh = spec.x + 24, spec.y + spec.h - 34, spec.w - 48, 14
  UI.meter(bx, by, bw, bh, p, color)
  local text = done and "LIFT UNLOCKED" or shown.on and ("HACKING %d%%"):format(math.floor(p * 100))
    or "HACK PAUSED"
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.printf(text, spec.x + 1, by - 23, spec.w, "center")
  love.graphics.setColor(color)
  love.graphics.printf(text, spec.x, by - 24, spec.w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- On the HUD while the hack runs: a bar at the top of the screen.
function Hold.drawHUD(label)
  if not shown or shown.progress >= 1 then
    return
  end
  local w = love.graphics.getWidth()
  local bw = 320
  local x, y = math.floor((w - bw) / 2), 64
  local color = shown.on and AMBER or GREY
  UI.meter(x, y, bw, 10, shown.progress, color)
  love.graphics.setFont(UI.fonts.small)
  local text = shown.on and label or (label .. ": PAUSED, nobody on it")
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.printf(text, 1, y + 15, w, "center")
  love.graphics.setColor(color)
  love.graphics.printf(text, 0, y + 14, w, "center")
  love.graphics.setColor(1, 1, 1)
end

Hold.clientMessages = {
  BRL_HOLD = function(_client, args)
    local p = tonumber(args[1])
    if p then
      shown = { progress = p, on = args[2] == "1" }
    end
  end,
}

return Hold
