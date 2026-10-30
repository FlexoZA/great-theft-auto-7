-- Max's four big screens on Prosperity (docs/borderline.md, "4. Prosperity"):
-- up on two legs in each corner district's square, his face on them live,
-- TO THE MAX running along the bottom. Shoot them down: each one down, the
-- rest turn up brighter; the last one down, he throws the north gate open
-- (a lock of the terminals feature with no terminals: `serverUnlock`).
-- init.lua passes its hooks on to this module.
--
-- The map says where (city-map's `map.screens` { x, y, w, h }, world px:
-- the panel). Anybody's round or blast that touches a panel hurts it
-- (`serverShotAt`); its health is a boss's (Bosses.health: more humans,
-- more), each. Nobody stands under one for long: it's up in the air.
--
-- Messages
--   server -> all  SCR_HP <screen> <0..1>   it was hit: how much of it is left
--   server -> all  SCR_DOWN <screen>        it is down (to a joiner, every one that is)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Terminals = require("src.features.terminals")
local Faces = require("src.features.borderline.faces")

local Screens = {}

-- Tuning ------------------------------------------------------------------
Screens.HEALTH = 450 -- each, for one human (Bosses.health)
Screens.BLAST = 40 -- what a blast's touch takes off one (blasts carry no damage)
Screens.BRIGHTER = 0.35 -- how much brighter the rest get for each one down
Screens.LOCK = "gate" -- the lock the last one down opens

local YELLOW = { 0.95, 0.76, 0.19 }
local INK = { 0.07, 0.07, 0.09 }
local STEEL = { 0.36, 0.38, 0.42 }
local LIFT = 26 -- px the panel is drawn up off the ground (its shadow lies there)

local function screensOf(map)
  return map and map.screens or {}
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

-- Server --------------------------------------------------------------------

local sv = nil -- { [i] = { hp, max, down }, down = count } while a map has screens

function Screens.serverStart(server, map)
  sv = nil
  if #screensOf(map) == 0 then
    return
  end
  sv = { down = 0, map = map }
  for i in ipairs(screensOf(map)) do
    local hp = Bosses.health(Screens.HEALTH, server)
    sv[i] = { hp = hp, max = hp, down = false }
  end
end

function Screens.serverStop()
  sv = nil
end

--- Does the circle (x, y, r) touch the rect `s`?
local function touches(s, x, y, r)
  local nx, ny = math.max(s.x, math.min(x, s.x + s.w)), math.max(s.y, math.min(y, s.y + s.h))
  return (x - nx) ^ 2 + (y - ny) ^ 2 <= r * r
end

--- `beat(what)` raises a story beat: "screen1" .. "screen3" as each goes
--- down, "screens" with the last (and the north gate opens).
function Screens.serverShotAt(server, x, y, radius, by, damage, beat)
  if not sv or by == 0 then
    return false
  end
  for i, s in ipairs(screensOf(sv.map)) do
    local st = sv[i]
    if not st.down and touches(s, x, y, radius) then
      st.hp = st.hp - (damage or Screens.BLAST)
      if st.hp > 0 then
        server:broadcast(Protocol.encode("SCR_HP", i, ("%.3f"):format(st.hp / st.max)))
        return "metal"
      end
      st.down, sv.down = true, sv.down + 1
      server:broadcast(Protocol.encode("SCR_DOWN", i))
      if sv.down >= #screensOf(sv.map) then
        Terminals.serverUnlock(server, Screens.LOCK)
        beat("screens")
      else
        beat("screen" .. sv.down)
      end
      return "metal"
    end
  end
  return false
end

--- Every screen still up, for the audit (tools/audit): it may hang over walls.
function Screens.serverEnemies(add)
  for i, s in ipairs(sv and screensOf(sv.map) or {}) do
    local st = sv[i]
    if not st.down then
      add({ id = st, kind = "borderline/screen", x = s.x + s.w / 2, y = s.y + s.h / 2, hp = st.hp,
        radius = math.min(s.w, s.h) / 2, flying = true })
    end
  end
end

function Screens.serverPlayerJoined(server, player)
  for i in ipairs(sv and screensOf(sv.map) or {}) do
    local st = sv[i]
    if st.down then
      server:send(player, Protocol.encode("SCR_DOWN", i))
    elseif st.hp < st.max then
      server:send(player, Protocol.encode("SCR_HP", i, ("%.3f"):format(st.hp / st.max)))
    end
  end
end

--- The wiki's page on them (tools/wiki, docs/wiki.md).
function Screens.wikiEnemies(add)
  add({
    kind = "borderline/screen",
    name = "Max's screen",
    quests = { "borderline-prosperity" },
    where = "Prosperity: one in each corner district's square, up on two legs, a hauler dock guarding it; the "
      .. "north gate stays shut until all four are down",
    about = "Maximum Maximilian Max live, on a giant screen in Hyperbole yellow, TO THE MAX running along the "
      .. "bottom. It doesn't shoot back; the dock and the gun haulers guarding it do.",
    stats = {
      { "Health", Screens.HEALTH },
      { "A blast", ("takes %g off it"):format(Screens.BLAST) },
    },
    abilities = {
      ("Every one shot down, the rest turn up %d%% brighter. The last one down, Max throws the north gate open.")
        :format(Screens.BRIGHTER * 100),
    },
    tips = {
      "Shoot the hauler dock first: it keeps building junk haulers while you're near.",
      "Rockets and grenades work: anything that touches the panel hurts it.",
    },
    drops = "nothing: the north gate opens when the last one goes",
  })
end

-- Client --------------------------------------------------------------------

local cl = {} -- [screen] = { left 0..1, down, downT, flash }
local clock = 0
local face = nil
local bank = {}

function Screens.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(400, 3000)
    return src
  end
  -- A screen going down: glass bursting, a crackle of electrics, a thud.
  bank.down = make(1.4, 0.9, function(buf)
    buf:noiseBurst(0, 0.5, { amp = 0.8, decay = 0.12 })
    for i = 0, 9 do
      buf:tone(0.02 + i * 0.03, 0.2, 2400 + i * 330, { wave = "sine", amp = 0.12, attack = 0.001, decay = 0.08,
        sustain = 0 })
    end
    for i = 0, 14 do
      buf:noiseBurst(0.3 + i * 0.05 + (i % 3) * 0.013, 0.03, { amp = 0.25, decay = 0.006 })
    end
    buf:sweep(0.1, 0.9, 120, 40, { wave = "sine", amp = 0.6, decay = 0.3 })
  end)
end

function Screens.clear()
  cl = {}
end

local function state(i)
  cl[i] = cl[i] or { left = 1, down = false, downT = 0, flash = 0 }
  return cl[i]
end

function Screens.update(dt)
  clock = clock + dt
  face = face or Faces.new("max")
  face.talking = math.sin(clock * 0.9) > -0.2 -- he is always saying something
  face:update(dt)
  for _, st in pairs(cl) do
    st.flash = math.max(0, st.flash - dt)
    if st.down then
      st.downT = st.downT + dt
    end
  end
end

--- How many of `map`'s screens are down on this screen.
local function downCount(map)
  local n = 0
  for i in ipairs(screensOf(map)) do
    if state(i).down then
      n = n + 1
    end
  end
  return n
end

--- Where the screens still up on `map` are (their middles), for the
--- objective line and its markers.
function Screens.remaining(map)
  local list = {}
  for i, s in ipairs(screensOf(map)) do
    if not state(i).down then
      list[#list + 1] = { x = s.x + s.w / 2, y = s.y + s.h / 2 }
    end
  end
  return list
end

--- A panel up: Hyperbole yellow round it, his face live on it against a
--- glow, LIVE in the corner, TO THE MAX running along the bottom, brighter
--- (`bright`) for every one of them down; flashing white when hit, cracked
--- once it is half gone (`left`), its health under it once hurt.
local function drawLive(s, st, bright)
  local x, y, w, h = s.x, s.y - LIFT, s.w, s.h
  love.graphics.setColor(INK)
  love.graphics.rectangle("fill", x - 8, y - 8, w + 16, h + 16, 6)
  love.graphics.setColor(YELLOW)
  love.graphics.rectangle("fill", x - 4, y - 4, w + 8, h + 8, 4)
  love.graphics.setColor(0.10, 0.08, 0.04)
  love.graphics.rectangle("fill", x + 4, y + 4, w - 8, h - 8)
  local k = 0.75 + 0.1 * math.sin(clock * 2)
  love.graphics.setColor(0.95 * k, 0.66 * k, 0.12 * k) -- the glow behind him
  love.graphics.circle("fill", x + w * 0.32, y + h * 0.5, h * 0.42, 28)
  if face then
    local scale = (h - 24) / Faces.H
    face:draw(x + w * 0.32, y + h * 0.5, scale)
  end
  love.graphics.setFont(Screens.font)
  love.graphics.setColor(YELLOW)
  love.graphics.printf("MAXIMUM", x + w * 0.58, y + h * 0.18, w * 0.4, "center")
  love.graphics.printf("MAXIMILIAN", x + w * 0.58, y + h * 0.36, w * 0.4, "center")
  love.graphics.printf("MAX", x + w * 0.58, y + h * 0.54, w * 0.4, "center")
  love.graphics.setColor(INK) -- the ticker
  love.graphics.rectangle("fill", x + 4, y + h - 30, w - 8, 26)
  love.graphics.setColor(YELLOW)
  local text = "TO THE MAX  *  MAX LOVES YOU  *  NO LOITERING  *  PROSPERITY LOVES YOU  *  "
  local font = Screens.font
  local tw = font:getWidth(text)
  local at = x + 4 - (clock * 80) % tw
  for _, part in ipairs({ text, text }) do -- a letter at a time, only those inside the ticker
    for n = 1, #part do
      local ch = part:sub(n, n)
      local cw = font:getWidth(ch)
      if at >= x + 6 and at + cw <= x + w - 6 then
        love.graphics.print(ch, at, y + h - 28)
      end
      at = at + cw
    end
  end
  if math.floor(clock * 2) % 2 == 0 then
    love.graphics.setColor(1, 0.2, 0.2)
    love.graphics.circle("fill", x + 18, y + 18, 6, 10)
  end
  love.graphics.setBlendMode("add") -- turned up for every one of them down
  love.graphics.setColor(1, 0.9, 0.6, 0.08 + bright * 0.12 + st.flash * 3)
  love.graphics.rectangle("fill", x + 4, y + 4, w - 8, h - 8)
  love.graphics.setBlendMode("alpha")
  if st.left < 0.5 then -- cracks across it
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.setLineWidth(2)
    local cx, cy = x + w * 0.7, y + h * 0.3
    for a = 0, 5 do
      local ang = a * 1.1 + 0.3
      love.graphics.line(cx, cy, cx + math.cos(ang) * w * 0.3, cy + math.sin(ang) * h * 0.4)
    end
    love.graphics.setLineWidth(1)
  end
  if st.left < 1 then
    local bw = w * 0.6
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x + (w - bw) / 2 - 2, y + h + 12, bw + 4, 8)
    love.graphics.setColor(1 - st.left, st.left, 0.2)
    love.graphics.rectangle("fill", x + (w - bw) / 2, y + h + 14, bw * st.left, 4)
  end
end

--- A panel shot down: black glass shattered out of its frame, sparks off
--- the torn wiring now and then, smoke going up for a while.
local function drawDead(s, st)
  local x, y, w, h = s.x, s.y - LIFT, s.w, s.h
  love.graphics.setColor(INK)
  love.graphics.rectangle("fill", x - 8, y - 8, w + 16, h + 16, 6)
  love.graphics.setColor(STEEL)
  love.graphics.rectangle("fill", x - 4, y - 4, w + 8, h + 8, 4)
  love.graphics.setColor(0.05, 0.05, 0.06)
  love.graphics.rectangle("fill", x + 4, y + 4, w - 8, h - 8)
  love.graphics.setColor(0.6, 0.65, 0.7, 0.5) -- the shattered glass
  love.graphics.setLineWidth(2)
  local cx, cy = x + w * 0.45, y + h * 0.5
  for a = 0, 9 do
    local ang = a * 0.63
    love.graphics.line(cx, cy, cx + math.cos(ang) * w * 0.5, cy + math.sin(ang) * h * 0.5)
  end
  love.graphics.setLineWidth(1)
  if (clock * 3 + s.x) % 1 < 0.3 then -- sparks
    love.graphics.setColor(1, 0.75, 0.3)
    for i = 0, 5 do
      local a = clock * 23 + i * 1.7
      love.graphics.circle("fill", cx + math.cos(a) * 20 * ((clock * 4 + i * 0.2) % 1), cy + 30 + i * 3, 2, 5)
    end
  end
  if st.downT < 20 then -- smoke going up for a while
    for i = 0, 4 do
      local age = (clock * 0.4 + i / 5) % 1
      love.graphics.setColor(0.25, 0.25, 0.27, 0.4 * (1 - age) * (1 - st.downT / 20))
      love.graphics.circle("fill", cx + age * 40, cy - age * 120, 20 + 40 * age, 16)
    end
  end
end

--- Every screen of `map`, over everyone: its shadow on the ground first.
function Screens.drawAboveCars(map)
  local list = screensOf(map)
  if #list == 0 then
    return
  end
  Screens.font = Screens.font or love.graphics.newFont(20)
  local before = love.graphics.getFont()
  local bright = downCount(map) * Screens.BRIGHTER
  for i, s in ipairs(list) do
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle("fill", s.x + LIFT, s.y + LIFT, s.w, s.h * 0.5)
    local st = state(i)
    if st.down then
      drawDead(s, st)
    else
      drawLive(s, st, bright)
    end
  end
  love.graphics.setFont(before)
  love.graphics.setColor(1, 1, 1)
end

--- At dusk (the night feature): every screen still up lights the square
--- round it, more for every one of them down.
function Screens.drawNightLights(map, glow)
  local bright = 1 + downCount(map) * Screens.BRIGHTER
  for i, s in ipairs(screensOf(map)) do
    if not state(i).down then
      glow(s.x + s.w / 2, s.y + s.h / 2, 300 * bright, { 1, 0.8, 0.35 }, math.min(1, 0.55 * bright))
    end
  end
end

Screens.clientMessages = {
  SCR_HP = function(_client, args)
    local i, left = tonumber(args[1]), tonumber(args[2])
    if i and left then
      local st = state(i)
      st.left, st.flash = left, 0.08
    end
  end,
  SCR_DOWN = function(_client, args)
    local i = tonumber(args[1])
    local s = i and screensOf(cityMap())[i]
    if i then
      local st = state(i)
      if not st.down then
        st.down, st.downT, st.left = true, 0, 0
        local src = bank.down and bank.down:clone()
        if src and s then
          src:setPosition(s.x + s.w / 2, 0, s.y + s.h / 2)
          src:setVolume(Audio.volume("weapons"))
          src:play()
        end
      end
    end
  end,
}

return Screens
