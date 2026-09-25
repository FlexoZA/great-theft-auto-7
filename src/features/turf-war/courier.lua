-- The delivery car on the host: a police car that brings what a player
-- bought from the shop screen out on the map. It comes out of the buyer's
-- base gate onto the lane nearest the buyer, drives that lane, siren on,
-- at the bots' reckless pace and by none of their rules, to the point of
-- the lane nearest where the buyer stood when they bought, throws the
-- parcel out there (a pickup on the road: whoever gets to it first has
-- it, friend or foe), and drives back to the gate, where it is gone. It
-- sticks to the tarmac: its route is the lane's own polyline. A second
-- purchase while one is still on its way out goes into the same car.
--
-- The car is one of bots' NPC drivers with this module's brain, wearing
-- the police livery (POL_UNIT / POL_SIREN, which the police feature's
-- clients draw and sound), on the buyer's side so its own towers and
-- creeps let it by; the other side's shoot it like anyone. Wrecked, it
-- drops the parcel where it died. A leg that takes too long (wedged
-- somewhere) ends where it is: the parcel is dropped, the car goes.

local Features = require("src.features")
local Protocol = require("src.net.protocol")

local Courier = {}
Courier.__index = Courier

-- Tuning --------------------------------------------------------------------

Courier.SPEED = 330 -- px/s, the bots' reckless pace
Courier.TURN_SPEED = 90 -- px/s it slows to for a sharp turn, so it turns on the tarmac and not through the trees
Courier.SLOW_ANGLE = 1.0 -- radians off its heading that counts as a sharp turn
Courier.REACH = 90 -- px from a waypoint that counts as reaching it
Courier.DROP_REACH = 60 -- px from the drop point it throws the parcel out
Courier.DROP_SLOW = 260 -- px from the drop point it starts slowing
Courier.GATE_BACK = 140 -- px inside the gate it starts from and ends at
Courier.GIVE_UP = 45 -- seconds a leg may take before it is cut short
Courier.NAME = "Delivery"

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The point of segment a-b nearest (x, y), and how far it is.
local function nearestOnSegment(x, y, a, b)
  local vx, vy = b.x - a.x, b.y - a.y
  local len2 = vx * vx + vy * vy
  local t = len2 > 0 and math.max(0, math.min(1, ((x - a.x) * vx + (y - a.y) * vy) / len2)) or 0
  local px, py = a.x + vx * t, a.y + vy * t
  return px, py, dist2(x, y, px, py)
end

--- The lane nearest (x, y), the index of the segment the nearest point is
--- on, and that point.
local function nearestLane(map, x, y)
  local best, bestSeg, bx, by, bestD2
  for _, lane in ipairs(map.lanes) do
    local pts = lane.points
    for i = 1, #pts - 1 do
      local px, py, d2 = nearestOnSegment(x, y, pts[i], pts[i + 1])
      if not bestD2 or d2 < bestD2 then
        best, bestSeg, bx, by, bestD2 = lane, i, px, py, d2
      end
    end
  end
  return best, bestSeg, bx, by
end

function Courier.new()
  return setmetatable({ list = {} }, Courier)
end

--- The bots feature, if it is there to drive for us.
local function bots()
  return Features.byName.bots
end

-- The brain ---------------------------------------------------------------

local Brain = {}

--- Throw the parcel out at (x, y): every item as a pickup on the road,
--- spread a little so a pile can be seen.
local function drop(server, npc, x, y)
  local c = npc.courier
  if c.dropped then
    return
  end
  c.dropped, c.legT = true, 0
  local pickups = Features.byName.pickups
  for k, parcel in ipairs(c.items) do
    local a = k * 2.4
    local px, py = x + math.cos(a) * 14 * math.min(k - 1, 2), y + math.sin(a) * 14 * math.min(k - 1, 2)
    if pickups and pickups.serverDrop then
      pickups:serverDrop(server, parcel.item, px, py, parcel.n)
    end
  end
end

--- Drive the route a waypoint at a time; the parcel goes out at the drop
--- waypoint; past the last one the car is finished (init takes it away).
function Brain.think(server, npc, dt)
  local c, car = npc.courier, npc.car
  local B = bots()
  c.legT = c.legT + dt
  c.lastX, c.lastY = car.x, car.y
  local wp = c.route[c.i]
  if not wp or not B then
    c.finished = true
    npc.input.throttle, npc.input.steer = 0, 0
    return
  end
  local dist = B.driveTowards(npc, wp.x, wp.y, 1, false)
  -- Flat out down the lane; easy for a sharp turn (the way back after the
  -- drop, a lane's bend) and for the drop itself, so it stays on the road.
  local heading = math.atan2(wp.y - car.y, wp.x - car.x)
  local err = math.abs((heading - car.angle + math.pi) % (2 * math.pi) - math.pi)
  local limit = Courier.SPEED
  if err > Courier.SLOW_ANGLE or (wp.drop and dist < Courier.DROP_SLOW) then
    limit = Courier.TURN_SPEED
  end
  if npc.input.throttle > 0 and car.speed > limit then
    npc.input.throttle = car.speed > limit * 1.5 and -0.6 or 0 -- brake hard when well over, else coast
  end
  B.unstick(npc, dt)
  if dist < (wp.drop and Courier.DROP_REACH or Courier.REACH) then
    if wp.drop then
      drop(server, npc, car.x, car.y)
    end
    c.i = c.i + 1
  elseif c.legT > Courier.GIVE_UP then
    -- Wedged somewhere: the parcel goes out here, and the car is done.
    drop(server, npc, car.x, car.y)
    c.finished = true
  end
end

--- Wrecked (weapons hid the car): the parcel goes out where it last was,
--- and the car is done.
function Brain.wrecked(server, npc)
  local c = npc.courier
  drop(server, npc, c.lastX or npc.car.x, c.lastY or npc.car.y)
  c.finished = true
end

-- Dispatching ---------------------------------------------------------------

--- Send `n` of `item` to `buyer` (on side `team`) on `map`. Returns the
--- car's NPC when a new one set off, false when it went into a car already
--- on its way, nil when nobody can drive.
function Courier:dispatch(server, map, buyer, team, item, n)
  for _, npc in ipairs(self.list) do
    local c = npc.courier
    if c.buyer == buyer.id and not c.dropped and not c.finished then
      c.items[#c.items + 1] = { item = item, n = n }
      return false
    end
  end
  local B = bots()
  if not (B and B.spawnNpc) then
    return nil
  end
  local bx, by = Features.bodyPose(server, buyer)
  local lane, seg, dx, dy = nearestLane(map, bx, by)
  local pts = lane.points
  local gate, step, last = pts[1], 1, seg -- the nodes between the gate and the drop, in walking order
  if team == 2 then
    gate, step, last = pts[#pts], -1, seg + 1
  end
  local next = pts[gate == pts[1] and 2 or #pts - 1]
  local len = math.sqrt(dist2(gate.x, gate.y, next.x, next.y))
  local ux, uy = (next.x - gate.x) / len, (next.y - gate.y) / len
  local sx, sy = gate.x - ux * Courier.GATE_BACK, gate.y - uy * Courier.GATE_BACK
  local route = {}
  local i = (gate == pts[1]) and 2 or #pts - 1
  while (step == 1 and i <= last) or (step == -1 and i >= last) do
    route[#route + 1] = { x = pts[i].x, y = pts[i].y }
    i = i + step
  end
  route[#route + 1] = { x = dx, y = dy, drop = true }
  for k = #route - 1, 1, -1 do
    route[#route + 1] = { x = route[k].x, y = route[k].y }
  end
  route[#route + 1] = { x = gate.x, y = gate.y }
  route[#route + 1] = { x = sx, y = sy }
  local npc = B:spawnNpc(server, {
    name = Courier.NAME,
    x = sx,
    y = sy,
    angle = math.atan2(uy, ux),
    brain = Brain,
    police = true,
    courier = {
      buyer = buyer.id, team = team, items = { { item = item, n = n } }, route = route, i = 1, legT = 0,
      dropped = false, finished = false,
    },
  })
  B:park(npc, false) -- born on a map with no traffic, it was put away: out it comes
  self.list[#self.list + 1] = npc
  server:broadcast(Protocol.encode("POL_UNIT", npc.id))
  server:broadcast(Protocol.encode("POL_SIREN", npc.id, 1))
  return npc
end

--- A car of ours was wrecked at (x, y) (weapons' `serverKill`): the parcel
--- goes out there. Returns true if `id` was one of ours.
function Courier:wrecked(server, id, x, y)
  for _, npc in ipairs(self.list) do
    if npc.id == id then
      drop(server, npc, x, y)
      npc.courier.finished = true
      return true
    end
  end
  return false
end

--- Take away every car that is done. Bots has already driven the rest
--- this tick.
function Courier:update(server)
  local B = bots()
  for i = #self.list, 1, -1 do
    local npc = self.list[i]
    if npc.courier.finished or not server.players[npc.id] then
      table.remove(self.list, i)
      if server.players[npc.id] and B and B.removeNpc then
        B:removeNpc(server, npc)
      end
    end
  end
end

--- Every car, gone (the war is over).
function Courier:clear(server)
  for _, npc in ipairs(self.list) do
    npc.courier.finished = true
  end
  self:update(server)
end

--- Tell someone who has just arrived which cars are ours.
function Courier:announce(server, player)
  for _, npc in ipairs(self.list) do
    if server.players[npc.id] then
      server:send(player, Protocol.encode("POL_UNIT", npc.id))
      server:send(player, Protocol.encode("POL_SIREN", npc.id, 1))
    end
  end
end

--- For tests: a route's drop point.
function Courier.dropPoint(npc)
  for _, wp in ipairs(npc.courier.route) do
    if wp.drop then
      return wp.x, wp.y
    end
  end
  return nil
end

return Courier
