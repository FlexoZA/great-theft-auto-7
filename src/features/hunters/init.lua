-- Hunters: the Combine's tripod hunters, a ranged enemy. Quick on their
-- three legs, they keep their distance and shoot uzi rounds that carry
-- shock damage, throw themselves aside from incoming fire and players'
-- abilities, and when badly hurt go after medkits and energy drinks lying
-- nearby.
--
-- Built in steps; so far they look the part (render.lua) and walk a beat.
-- Another feature puts them on the map (City 17 has three round the
-- Citadel): `hunters:serverPatrol(server, route, count)` spreads `count` of
-- them round `route`, a loop of { x, y } corners they walk round and round,
-- finding their way round walls between corners (d-day/nav.lua's walking
-- grid). `hunters:serverClear(server)` takes them all away again; a map
-- change does too. They can't be hurt yet.
--
-- The host owns them; clients hear where they are at 15 Hz.
--
-- Messages
--   server -> all  HTR_STATE <tick> (<id> <x> <y> <facing> <moving>)...   (unreliable, 15 Hz)
--
-- Modules
--   render.lua   one drawn from above, walking, firing, hit and dodging

local Protocol = require("src.net.protocol")
local Nav = require("src.features.d-day.nav")
local Render = require("src.features.hunters.render")

local Hunters = {
  name = "hunters",
}

-- Tuning ------------------------------------------------------------------
Hunters.patrolSpeed = 85 -- px/s walking a beat (a player walks about 60)
Hunters.turn = 6 -- rad/s turning to where it is going
Hunters.navPad = 300 -- px round a beat that its walking grid covers

local SYNC_EVERY = 2 -- server ticks between HTR_STATE
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a step
local STEP = 34 -- px walked in one full step cycle, for the legs
local EMPTY_AFTER = 1 -- sends of an empty list after the last one goes, so every screen clears

local function turn(from, to, rate, dt)
  local d = (to - from + math.pi) % (2 * math.pi) - math.pi
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { list, nextId, syncIn, emptySends }

local function server()
  sv = sv or { list = {}, nextId = 1, syncIn = 0, emptySends = 0 }
  return sv
end

--- A walking grid over `route`'s bounding box, padded.
local function navFor(route)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(route) do
    x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y)
  end
  local pad = Hunters.navPad
  return Nav.build({ x = x0 - pad, y = y0 - pad, w = x1 - x0 + 2 * pad, h = y1 - y0 + 2 * pad })
end

--- `route` with every corner moved to the nearest open spot on `nav`.
local function settle(nav, route)
  local out = {}
  for _, p in ipairs(route) do
    local c, r = nav:nearestOpen(p.x, p.y)
    if c then
      local x, y = nav:centre(c, r)
      out[#out + 1] = { x = x, y = y }
    end
  end
  return out
end

--- `count` hunters spread evenly round `route` ({ x, y } corners, a loop),
--- walking it. Returns them.
function Hunters:serverPatrol(_server, route, count)
  local s = server()
  local nav = navFor(route)
  route = settle(nav, route)
  local added = {}
  if #route < 2 then
    return added
  end
  for i = 1, count do
    local at = math.floor((i - 1) * #route / count) + 1
    local p = route[at]
    local h = { id = s.nextId, x = p.x, y = p.y, facing = 0, route = route, leg = at % #route + 1, nav = nav }
    s.nextId = s.nextId + 1
    s.list[#s.list + 1] = h
    added[#added + 1] = h
  end
  return added
end

--- Take every hunter away.
function Hunters:serverClear()
  if sv then
    sv.list = {}
  end
end

function Hunters:mapChanged(_map, srv)
  if srv then
    self:serverClear()
  end
end

function Hunters:serverStart()
  sv = nil
end

--- On along its beat: to the next corner, round any walls in the way.
local function patrol(h, dt)
  local to = h.route[h.leg]
  if not h.path then
    h.path = h.nav:path(h.x, h.y, to.x, to.y) or { to }
    h.at = 1
  end
  local c = h.path[h.at]
  local dx, dy = c.x - h.x, c.y - h.y
  local d = math.sqrt(dx * dx + dy * dy)
  local step = Hunters.patrolSpeed * dt
  if d <= step then
    h.x, h.y = c.x, c.y
    h.at = h.at + 1
    if h.at > #h.path then
      h.leg = h.leg % #h.route + 1 -- there: on to the next corner
      h.path = nil
    end
  else
    h.x, h.y = h.x + dx / d * step, h.y + dy / d * step
  end
  h.moving = true
  h.facing = turn(h.facing, math.atan2(dy, dx), Hunters.turn, dt)
end

local function sync(srv)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  if #sv.list == 0 then
    if sv.emptySends >= EMPTY_AFTER then
      return
    end
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  local parts = { srv.tick }
  for _, h in ipairs(sv.list) do
    parts[#parts + 1] = h.id
    parts[#parts + 1] = ("%.0f"):format(h.x)
    parts[#parts + 1] = ("%.0f"):format(h.y)
    parts[#parts + 1] = ("%.2f"):format(h.facing)
    parts[#parts + 1] = h.moving and 1 or 0
  end
  local msg = Protocol.encode("HTR_STATE", unpack(parts))
  for _, player in pairs(srv.players) do
    if not player.bot then
      srv:send(player, msg, true)
    end
  end
end

function Hunters:serverStep(srv, dt)
  if not sv then
    return
  end
  for _, h in ipairs(sv.list) do
    patrol(h, dt)
  end
  sync(srv)
end

--- The host's hunters, for tests.
function Hunters.state()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, moving, cycle, stride }
local lastTick = 0
local clock = 0

function Hunters:exitGame()
  shown, lastTick = {}, 0
end

function Hunters:update(dt)
  clock = clock + dt
  local k = math.min(1, dt * SMOOTHING)
  for _, h in pairs(shown) do
    local ex, ey = h.x - h.dx, h.y - h.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      h.dx, h.dy = h.x, h.y
    else
      h.dx, h.dy = h.dx + ex * k, h.dy + ey * k
      h.cycle = h.cycle + math.sqrt(ex * ex + ey * ey) * k / STEP -- the legs keep up with the ground
    end
    h.stride = h.stride + ((h.moving and 1 or 0) - h.stride) * math.min(1, dt * 6)
  end
end

function Hunters:drawAboveCars()
  for _, h in pairs(shown) do
    Render.draw(h.dx, h.dy, h.facing, { cycle = h.cycle, stride = h.stride }, clock)
  end
  love.graphics.setColor(1, 1, 1)
end

Hunters.clientMessages = {
  HTR_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local seen = {}
    for i = 2, #args - 4, 5 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local h = shown[id]
        if not h then
          h = { dx = x, dy = y, cycle = love.math.random(), stride = 0 }
          shown[id] = h
        end
        h.x, h.y = x, y
        h.facing = tonumber(args[i + 3]) or h.facing or 0
        h.moving = args[i + 4] == "1"
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
}

return Hunters
