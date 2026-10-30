-- The Assembly Line's two Fabricators (docs/borderline.md, "6. The Assembly
-- Line"): a machine on a pad each side of the floor, a gantry with welding
-- arms over a cradle, building haulers. While anyone is near, every so
-- often one walks out of it finished (army.lua's `serverSpawn`) and goes
-- for them; it keeps a few of its own out at once. Shoot them down: the
-- first one down, Max has something to say; the last, the shutters over
-- the stairs up to the Foreman's floor come off (a lock of the terminals
-- feature with no terminals: `serverUnlock`). init.lua passes its hooks
-- on to this module.
--
-- The map says where (city-map's `map.fabricators` { x, y, w, h, face },
-- world px: the machine, and the side, "e" or "w", its haulers walk out
-- of). It stands in the way of walking (a `water` solid: rounds fly over
-- the floor to it), and anybody's round or blast that touches it hurts it
-- (`serverShotAt`); its health is a boss's (Bosses.health: more humans,
-- more), each.
--
-- Messages
--   server -> all  FAB_HP <fabricator> <0..1>   it was hit: how much of it is left
--   server -> all  FAB_BUILT <fabricator>       a hauler just walked out of it
--   server -> all  FAB_DOWN <fabricator>        it is down (to a joiner, every one that is)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Terminals = require("src.features.terminals")
local Army = require("src.features.borderline.army")
local Hauler = require("src.features.borderline.hauler_look")

local Fabricators = {}

-- Tuning ------------------------------------------------------------------
Fabricators.HEALTH = 900 -- each, for one human (Bosses.health)
Fabricators.BLAST = 50 -- what a blast's touch takes off one (blasts carry no damage)
Fabricators.BUILD_EVERY = 14 -- seconds between new haulers while anyone is near
Fabricators.WAKE = 1100 -- px a player comes within to start it building
Fabricators.CAP = 3 -- of its own out at once
Fabricators.BUILDS = { "GUN", "JNK", "GUN", "EXP" } -- what it builds, in turn
Fabricators.LOCK = "stairs" -- the lock the last one down opens

local C = Hauler.C
local LIFT = 22 -- px the gantry is drawn up off the ground (its shadow lies there)

local function fabricatorsOf(map)
  return map and map.fabricators or {}
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

--- Where a hauler walks out of fabricator `f`, and which way it faces.
local function door(f)
  local east = f.face == "e"
  return (east and f.x + f.w + 40 or f.x - 40), f.y + f.h / 2, east and 0 or math.pi
end

-- Server --------------------------------------------------------------------

local sv = nil -- { [i] = { hp, max, down, buildIn, built, next }, down = count, map } while a map has them

function Fabricators.serverStart(server, map)
  sv = nil
  if #fabricatorsOf(map) == 0 then
    return
  end
  sv = { down = 0, map = map }
  for i in ipairs(fabricatorsOf(map)) do
    local hp = Bosses.health(Fabricators.HEALTH, server)
    sv[i] = { hp = hp, max = hp, down = false, buildIn = Fabricators.BUILD_EVERY / 2, built = {}, next = i }
  end
end

function Fabricators.serverStop()
  sv = nil
end

--- The human player nearest (x, y) within `reach`, and where they are.
local function nearest(server, x, y, reach)
  local best, bx, by, bd = nil, nil, nil, reach * reach
  for _, p in pairs(server.players) do
    if not p.bot and Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local d = (px - x) ^ 2 + (py - y) ^ 2
      if d <= bd then
        best, bx, by, bd = p, px, py, d
      end
    end
  end
  return best, bx, by
end

--- Each one still up builds while anyone is near.
function Fabricators.serverStep(server, dt)
  if not sv then
    return
  end
  for i, f in ipairs(fabricatorsOf(sv.map)) do
    local st = sv[i]
    local who, px, py = nearest(server, f.x + f.w / 2, f.y + f.h / 2, Fabricators.WAKE)
    if not st.down and who then
      st.buildIn = st.buildIn - dt
      if st.buildIn <= 0 then
        st.buildIn = Fabricators.BUILD_EVERY
        local alive = {}
        for _, h in ipairs(st.built) do
          if Army.serverAlive(h) then
            alive[#alive + 1] = h
          end
        end
        st.built = alive
        if #alive < Fabricators.CAP then
          local code = Fabricators.BUILDS[(st.next - 1) % #Fabricators.BUILDS + 1]
          st.next = st.next + 1
          local x, y, facing = door(f)
          local h = Army.serverSpawn(code, x, y, facing)
          if h then
            alive[#alive + 1] = h
            if h.brain.wake then
              h.brain.wake(h, px, py)
            end
            server:broadcast(Protocol.encode("FAB_BUILT", i))
          end
        end
      end
    end
  end
end

--- Does the circle (x, y, r) touch the rect `f`?
local function touches(f, x, y, r)
  local nx, ny = math.max(f.x, math.min(x, f.x + f.w)), math.max(f.y, math.min(y, f.y + f.h))
  return (x - nx) ^ 2 + (y - ny) ^ 2 <= r * r
end

--- `beat(what)` raises a story beat: "fabricator" with the first one down,
--- "fabricators" with the last (and the stairs open).
function Fabricators.serverShotAt(server, x, y, radius, by, damage, beat)
  if not sv or by == 0 then
    return false
  end
  for i, f in ipairs(fabricatorsOf(sv.map)) do
    local st = sv[i]
    if not st.down and touches(f, x, y, radius) then
      st.hp = st.hp - (damage or Fabricators.BLAST)
      if st.hp > 0 then
        server:broadcast(Protocol.encode("FAB_HP", i, ("%.3f"):format(st.hp / st.max)))
        return "metal"
      end
      st.down, sv.down = true, sv.down + 1
      server:broadcast(Protocol.encode("FAB_DOWN", i))
      if sv.down >= #fabricatorsOf(sv.map) then
        Terminals.serverUnlock(server, Fabricators.LOCK)
        beat("fabricators")
      else
        beat("fabricator")
      end
      return "metal"
    end
  end
  return false
end

--- Every one still up, for the audit (tools/audit): it never moves.
function Fabricators.serverEnemies(add)
  for i, f in ipairs(sv and fabricatorsOf(sv.map) or {}) do
    local st = sv[i]
    if not st.down then
      add({ id = st, kind = "borderline/fabricator", x = f.x + f.w / 2, y = f.y + f.h / 2, hp = st.hp,
        radius = math.min(f.w, f.h) / 2, fixed = true })
    end
  end
end

function Fabricators.serverPlayerJoined(server, player)
  for i in ipairs(sv and fabricatorsOf(sv.map) or {}) do
    local st = sv[i]
    if st.down then
      server:send(player, Protocol.encode("FAB_DOWN", i))
    elseif st.hp < st.max then
      server:send(player, Protocol.encode("FAB_HP", i, ("%.3f"):format(st.hp / st.max)))
    end
  end
end

--- The wiki's page on them (tools/wiki, docs/wiki.md).
function Fabricators.wikiEnemies(add)
  add({
    kind = "borderline/fabricator",
    name = "Fabricator",
    quests = { "borderline-assembly" },
    where = "The Assembly Line: one on a pad either side of the floor; the stairs up to the Foreman's floor stay "
      .. "shut until both are down",
    about = "A gantry of welding arms over a cradle, building Hyperbole's haulers. It doesn't shoot; what it "
      .. "builds does.",
    stats = {
      { "Health", Fabricators.HEALTH },
      { "A blast", ("takes %g off it"):format(Fabricators.BLAST) },
    },
    abilities = {
      ("While anyone is within %g px, a finished hauler walks out of it every %g seconds (gun, junk, gun, "
        .. "kamikaze in turn), up to %d of its own at once."):format(Fabricators.WAKE, Fabricators.BUILD_EVERY,
        Fabricators.CAP),
    },
    tips = {
      "Rush it: the longer you're near, the more of its haulers there are.",
      "Rockets and grenades work: anything that touches the machine hurts it.",
    },
    drops = "nothing: the stairs open when the last one goes",
  })
end

-- Client --------------------------------------------------------------------

local cl = {} -- [fabricator] = { left 0..1, down, downT, flash, built }
local clock = 0
local bank = {}

function Fabricators.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(400, 3000)
    return src
  end
  -- A hauler finished: a pneumatic hiss and the cradle's clamps letting go.
  bank.built = make(0.8, 0.7, function(buf)
    buf:noiseBurst(0, 0.45, { amp = 0.35, decay = 0.2 })
    buf:sweep(0.3, 0.12, 900, 300, { wave = "square", amp = 0.2, decay = 0.05 })
    buf:sweep(0.42, 0.12, 700, 200, { wave = "square", amp = 0.2, decay = 0.05 })
  end)
  -- One going down: the gantry buckling, electrics crackling, a deep thud.
  bank.down = make(1.6, 0.9, function(buf)
    buf:noiseBurst(0, 0.6, { amp = 0.8, decay = 0.15 })
    buf:sweep(0, 1.2, 160, 40, { wave = "saw", amp = 0.4, decay = 0.5 })
    for i = 0, 14 do
      buf:noiseBurst(0.3 + i * 0.06 + (i % 3) * 0.015, 0.03, { amp = 0.25, decay = 0.006 })
    end
    buf:sweep(0.2, 1, 110, 35, { wave = "sine", amp = 0.7, decay = 0.35 })
  end)
end

function Fabricators.clear()
  cl = {}
end

local function state(i)
  cl[i] = cl[i] or { left = 1, down = false, downT = 0, flash = 0, built = 99 }
  return cl[i]
end

function Fabricators.update(dt)
  clock = clock + dt
  for _, st in pairs(cl) do
    st.flash = math.max(0, st.flash - dt)
    st.built = st.built + dt
    if st.down then
      st.downT = st.downT + dt
    end
  end
end

--- Where the ones still up on `map` are (their middles), for the objective
--- line and its markers.
function Fabricators.remaining(map)
  local list = {}
  for i, f in ipairs(fabricatorsOf(map)) do
    if not state(i).down then
      list[#list + 1] = { x = f.x + f.w / 2, y = f.y + f.h / 2 }
    end
  end
  return list
end

--- A box with its outline, as polygons: a long beam drawn as a rectangle
--- would read as a health bar to the wiki's portraits, which leave those out.
local function rect(x, y, w, h, fill)
  love.graphics.setColor(C.ink)
  love.graphics.polygon("fill", x - 3, y - 3, x + w + 3, y - 3, x + w + 3, y + h + 3, x - 3, y + h + 3)
  love.graphics.setColor(fill)
  love.graphics.polygon("fill", x, y, x + w, y, x + w, y + h, x, y + h)
end

--- One up: the pad's cradle with a hauler half built in it, the gantry
--- over it on four yellow legs, two welding arms on its rail sweeping in
--- with sparks, Hyperbole's mark on the beam, the door on its working side
--- flashing as a hauler walks out; white when hit, its health under it once hurt.
local function drawLive(f, st)
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  local east = f.face == "e"
  -- The cradle and the hauler in it, a torso on the frame, eye not lit yet.
  rect(cx - 50, cy - 60, 100, 120, C.gunmetal)
  love.graphics.setColor(C.black)
  love.graphics.rectangle("fill", cx - 40, cy - 50, 80, 100)
  Hauler.draw({ dx = cx, dy = cy, facing = east and 0 or math.pi, code = "GUN", stride = 0 }, 0)
  -- The door on its working side, its lamp, its hazard paint.
  local dx = east and f.x + f.w - 14 or f.x
  rect(dx, cy - 40, 14, 80, C.gunmetalLight)
  for k = 0, 3 do
    love.graphics.setColor(k % 2 == 0 and C.yellow or C.ink)
    love.graphics.rectangle("fill", dx, cy - 40 + k * 20, 14, 20)
  end
  local opening = st.built < 1.2
  love.graphics.setColor(opening and C.eye or { 0.35, 0.95, 0.45 })
  love.graphics.circle("fill", dx + 7, cy - 52, 5, 10)
  -- The gantry, up off the ground: its shadow, its legs, its beams.
  love.graphics.setColor(0, 0, 0, 0.22)
  love.graphics.rectangle("fill", f.x + LIFT, f.y + LIFT + 20, f.w, 24)
  love.graphics.rectangle("fill", f.x + LIFT, f.y + f.h - 20 + LIFT, f.w, 24)
  for _, lx in ipairs({ f.x, f.x + f.w - 26 }) do
    for _, ly in ipairs({ f.y, f.y + f.h - 26 }) do
      rect(lx, ly - LIFT, 26, 26, C.yellow)
    end
  end
  for _, by in ipairs({ f.y + 6, f.y + f.h - 30 }) do
    rect(f.x + 26, by - LIFT, f.w - 52, 24, C.yellowDark)
    love.graphics.setColor(C.ink[1], C.ink[2], C.ink[3], 0.5)
    for a = f.x + 34, f.x + f.w - 40, 22 do -- the truss
      love.graphics.line(a, by - LIFT + 2, a + 11, by - LIFT + 22)
    end
  end
  love.graphics.setColor(C.ink) -- Hyperbole's H on the north beam
  love.graphics.rectangle("fill", cx - 16, f.y + 4 - LIFT, 32, 28)
  love.graphics.setColor(C.yellow)
  love.graphics.rectangle("fill", cx - 11, f.y + 8 - LIFT, 6, 20)
  love.graphics.rectangle("fill", cx + 5, f.y + 8 - LIFT, 6, 20)
  love.graphics.rectangle("fill", cx - 5, f.y + 15 - LIFT, 10, 6)
  -- The arms, sweeping in from either beam to weld.
  for k, side in ipairs({ -1, 1 }) do
    local t = clock * 1.3 + k * 1.7
    local along = cx + math.sin(t) * f.w * 0.25
    local base = side < 0 and f.y + 18 - LIFT or f.y + f.h - 18 - LIFT
    local tip = cy + side * (16 + 10 * (0.5 + 0.5 * math.sin(t * 2)))
    love.graphics.setColor(C.ink)
    love.graphics.setLineWidth(12)
    love.graphics.line(along, base, along + side * 8, tip - LIFT * 0.5)
    love.graphics.setColor(C.gunmetalLight)
    love.graphics.setLineWidth(7)
    love.graphics.line(along, base, along + side * 8, tip - LIFT * 0.5)
    love.graphics.setLineWidth(1)
    if math.sin(t * 2) > 0.3 then -- welding
      love.graphics.setColor(C.arcHot)
      love.graphics.circle("fill", along + side * 8, tip - LIFT * 0.5, 5, 10)
      love.graphics.setColor(C.flame)
      for s = 0, 4 do
        local a = clock * 17 + s * 1.3 + k
        love.graphics.circle("fill", along + side * 8 + math.cos(a) * 14, tip - LIFT * 0.5 + math.sin(a) * 10, 1.6, 5)
      end
    end
  end
  if st.flash > 0 then
    love.graphics.setColor(1, 1, 1, st.flash * 6)
    love.graphics.rectangle("fill", f.x, f.y - LIFT, f.w, f.h)
  end
  if st.left < 1 then
    local bw = f.w * 0.7
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", cx - bw / 2 - 2, f.y + f.h + 8, bw + 4, 8)
    love.graphics.setColor(1 - st.left, st.left, 0.2)
    love.graphics.rectangle("fill", cx - bw / 2, f.y + f.h + 10, bw * st.left, 4)
  end
end

--- One shot down: the gantry fallen across the cradle, the hauler in it
--- burnt out, sparks off the torn cables now and then, smoke going up.
local function drawDead(f, st)
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  rect(cx - 50, cy - 60, 100, 120, C.gunmetal)
  love.graphics.setColor(C.black)
  love.graphics.rectangle("fill", cx - 40, cy - 50, 80, 100)
  for _, lx in ipairs({ f.x, f.x + f.w - 26 }) do -- the legs, still standing
    for _, ly in ipairs({ f.y, f.y + f.h - 26 }) do
      rect(lx, ly, 26, 26, C.rustDark)
    end
  end
  love.graphics.push() -- a beam fallen across it
  love.graphics.translate(cx, cy)
  love.graphics.rotate(0.5)
  rect(-f.w * 0.45, -12, f.w * 0.9, 24, C.rust)
  love.graphics.pop()
  if (clock * 3 + f.x) % 1 < 0.3 then
    love.graphics.setColor(C.flame)
    for i = 0, 5 do
      local a = clock * 23 + i * 1.7
      love.graphics.circle("fill", cx + math.cos(a) * 24 * ((clock * 4 + i * 0.2) % 1), cy + i * 3, 2, 5)
    end
  end
  if st.downT < 25 then
    for i = 0, 4 do
      local age = (clock * 0.4 + i / 5) % 1
      love.graphics.setColor(0.25, 0.25, 0.27, 0.45 * (1 - age) * (1 - st.downT / 25))
      love.graphics.circle("fill", cx + age * 40, cy - age * 140, 24 + 44 * age, 16)
    end
  end
end

--- One standing whole round (x, y) on its pad, its haulers walking out
--- east: the wiki's portrait (tools/wiki/scenes.lua).
function Fabricators.drawAt(x, y)
  rect(x - 160, y - 160, 320, 320, { 0.42, 0.42, 0.45 })
  for k = 0, 15 do -- the pad's hazard border
    love.graphics.setColor(k % 2 == 0 and C.yellow or C.ink)
    local a = x - 160 + k * 20
    love.graphics.rectangle("fill", a, y - 160, 20, 12)
    love.graphics.rectangle("fill", a, y + 148, 20, 12)
    love.graphics.rectangle("fill", x - 160, y - 160 + k * 20, 12, 20)
    love.graphics.rectangle("fill", x + 148, y - 160 + k * 20, 12, 20)
  end
  drawLive({ x = x - 128, y = y - 128, w = 256, h = 256, face = "e" }, { left = 1, flash = 0, built = 99 })
end

--- Every one of `map`'s, over everyone.
function Fabricators.drawAboveCars(map)
  for i, f in ipairs(fabricatorsOf(map)) do
    local st = state(i)
    if st.down then
      drawDead(f, st)
    else
      drawLive(f, st)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- In the gloom (the night feature): their welding lights them up.
function Fabricators.drawNightLights(map, glow)
  for i, f in ipairs(fabricatorsOf(map)) do
    if not state(i).down then
      glow(f.x + f.w / 2, f.y + f.h / 2, 260, C.arcHot, 0.45 + 0.25 * math.abs(math.sin(clock * 2.6 + i)))
    end
  end
end

local function play(sound, f)
  local src = sound and sound:clone()
  if src and f then
    src:setPosition(f.x + f.w / 2, 0, f.y + f.h / 2)
    src:setVolume(Audio.volume("weapons"))
    src:play()
  end
end

Fabricators.clientMessages = {
  FAB_HP = function(_client, args)
    local i, left = tonumber(args[1]), tonumber(args[2])
    if i and left then
      local st = state(i)
      st.left, st.flash = left, 0.08
    end
  end,
  FAB_BUILT = function(_client, args)
    local i = tonumber(args[1])
    if i then
      state(i).built = 0
      play(bank.built, fabricatorsOf(cityMap())[i])
    end
  end,
  FAB_DOWN = function(_client, args)
    local i = tonumber(args[1])
    if i then
      local st = state(i)
      if not st.down then
        st.down, st.downT, st.left = true, 0, 0
        play(bank.down, fabricatorsOf(cityMap())[i])
      end
    end
  end,
}

return Fabricators
