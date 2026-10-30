-- Mines (docs/borderline.md, "8. The Bunker"): what BNK-9 fires down onto
-- its roof. Each is lobbed from it onto a spot (FLIGHT seconds), lands and
-- arms (ARM), and lies there blinking; anyone on foot who comes within
-- TRIP px sets it beeping, and FUSE seconds later it goes off as a missile
-- does (weapons' `explode`: the boom, damage falling to a third at its
-- edge), owned by nobody, so it hurts whoever is near, never the army. Step
-- back out when it beeps. One left lying LIFE seconds fizzles out. No more
-- than MAX lie about at once: a new one past that, the oldest fizzles.
--
-- Messages
--   server -> all  HYP_MINE <id> <fromX> <fromY> <x> <y> <flight>   one lobbed from there onto there
--   server -> all  HYP_TRIP <id>                                    it is beeping
--   server -> all  HYP_GONE <id>                                    it went off or fizzled (the boom is weapons')

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Hauler = require("src.features.borderline.hauler_look")
local Sound = require("src.features.borderline.boss_sound")

local Mines = {}

Mines.FLIGHT = 0.9 -- seconds from its launcher to the ground
Mines.ARM = 0.6 -- seconds on the ground before it is live
Mines.TRIP = 55 -- px: a player this near sets it off...
Mines.FUSE = 0.6 -- ...and it goes off this long after
Mines.BLAST = { radius = 85, damage = 34, soft = 2 }
Mines.LIFE = 30 -- seconds one lies before it fizzles
Mines.MAX = 10

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { list = { id, x, y, t, fuse }, nextId }

function Mines.serverStart()
  sv = { list = {}, nextId = 1 }
end

function Mines.serverStop()
  sv = nil
end

local function gone(server, i)
  local m = table.remove(sv.list, i)
  server:broadcast(Protocol.encode("HYP_GONE", m.id))
  return m
end

--- A mine lobbed from (fromX, fromY) onto (x, y).
function Mines.serverLay(server, fromX, fromY, x, y)
  if not sv then
    return
  end
  if #sv.list >= Mines.MAX then
    gone(server, 1)
  end
  local m = { id = sv.nextId, x = x, y = y, t = -Mines.FLIGHT }
  sv.nextId = sv.nextId + 1
  sv.list[#sv.list + 1] = m
  server:broadcast(Protocol.encode("HYP_MINE", m.id, fmt(fromX), fmt(fromY), fmt(x), fmt(y),
    ("%.2f"):format(Mines.FLIGHT)))
end

--- Is anyone on foot within TRIP of `m`?
local function near(server, m)
  for _, p in pairs(server.players) do
    if Features.visible(server, p) and not p.vehicle then
      local x, y = Features.bodyPose(server, p)
      if (x - m.x) ^ 2 + (y - m.y) ^ 2 <= Mines.TRIP ^ 2 then
        return true
      end
    end
  end
  return false
end

function Mines.serverStep(server, dt)
  if not sv then
    return
  end
  local weapons = Features.byName.weapons
  for i = #sv.list, 1, -1 do
    local m = sv.list[i]
    m.t = m.t + dt
    if m.fuse then
      m.fuse = m.fuse - dt
      if m.fuse <= 0 then
        gone(server, i)
        if weapons and weapons.explode then -- nobody's blast (pid 0: no round on anyone's screen)
          local B = Mines.BLAST
          weapons:explode(server, { id = 0, owner = 0, vx = 0, vy = 1,
            blast = { radius = B.radius, damage = B.damage * Bosses.enemyPower(), soft = B.soft } }, m.x, m.y)
        end
      end
    elseif m.t >= Mines.LIFE then
      gone(server, i)
    elseif m.t >= Mines.ARM and near(server, m) then
      m.fuse = Mines.FUSE
      server:broadcast(Protocol.encode("HYP_TRIP", m.id))
    end
  end
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { fromX, fromY, x, y, t, flight, trip }
local bank = {}

function Mines.load()
  local function make(seconds, volume, build)
    return Sound.make(seconds, volume, build, 220, 1800)
  end
  -- Fired off: a hollow thunk.
  bank.thunk = make(0.3, 0.6, function(buf)
    buf:sweep(0, 0.25, 220, 80, { wave = "sine", amp = 0.6, decay = 0.1 })
    buf:noiseBurst(0, 0.05, { amp = 0.3, decay = 0.02 })
    buf:lowpass(1200)
  end)
  -- Tripped: fast beeps.
  bank.beep = make(0.6, 0.5, function(buf)
    for i = 0, 5 do
      buf:tone(i * 0.1, 0.05, 1800, { wave = "square", amp = 0.2, decay = 0.04 })
    end
  end)
end

local function play(name, x, y)
  Sound.play(bank[name], x, y)
end

function Mines.clear()
  shown = {}
end

function Mines.update(dt)
  for _, m in pairs(shown) do
    m.t = m.t + dt
  end
end

--- The mines: in the air, a lump arcing down; on the ground, a dark disc
--- with a light blinking, red and fast once it beeps, a ring round it.
function Mines.draw(clock)
  local C = Hauler.C
  for _, m in pairs(shown) do
    if m.t < m.flight then
      local k = m.t / m.flight
      local x, y = m.fromX + (m.x - m.fromX) * k, m.fromY + (m.y - m.fromY) * k
      love.graphics.setColor(0, 0, 0, 0.25 * k)
      love.graphics.ellipse("fill", x, y, 7, 5, 12)
      love.graphics.setColor(C.ink)
      love.graphics.circle("fill", x, y - math.sin(k * math.pi) * 90, 7, 12)
      love.graphics.setColor(C.yellow)
      love.graphics.circle("fill", x, y - math.sin(k * math.pi) * 90, 5, 12)
    else
      love.graphics.setColor(C.ink)
      love.graphics.circle("fill", m.x, m.y, 10, 16)
      love.graphics.setColor(C.gunmetal)
      love.graphics.circle("fill", m.x, m.y, 8.5, 16)
      love.graphics.setColor(C.yellow)
      for k = 0, 3 do -- its hazard ring
        local a = k * math.pi / 2 + 0.4
        love.graphics.arc("fill", m.x, m.y, 8.5, a, a + 0.5, 6)
      end
      local rate = m.trip and 18 or 3
      local on = math.sin(clock * rate + m.x) > 0
      love.graphics.setColor(on and C.eye or C.rustDark)
      love.graphics.circle("fill", m.x, m.y, 3.2, 10)
      if m.trip then
        local k = math.min(1, (m.t - m.trip) / Mines.FUSE)
        love.graphics.setColor(C.eye[1], C.eye[2], C.eye[3], 0.5 + 0.4 * math.sin(clock * 30))
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", m.x, m.y, Mines.BLAST.radius * (0.4 + 0.6 * k), 28)
        love.graphics.setLineWidth(1)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

Mines.clientMessages = {
  HYP_MINE = function(_client, args)
    local id, fx, fy = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local x, y, t = tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    if id and fx and fy and x and y and t and t > 0 then
      shown[id] = { fromX = fx, fromY = fy, x = x, y = y, t = 0, flight = t }
      play("thunk", fx, fy)
    end
  end,
  HYP_TRIP = function(_client, args)
    local m = shown[tonumber(args[1]) or -1]
    if m then
      m.trip = m.t
      play("beep", m.x, m.y)
    end
  end,
  HYP_GONE = function(_client, args)
    shown[tonumber(args[1]) or -1] = nil
  end,
}

return Mines
