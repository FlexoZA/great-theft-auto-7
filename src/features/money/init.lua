-- Money: Federal Commie Koins (Fck, plural Fcks) spilled by the dead.
-- Flatten a pedestrian and one Fck hits the tarmac. Wreck a car and the
-- driver spills up to five koins out of their own pocket -- the lot if they
-- were carrying fewer, nothing at all if they were broke, so there is no
-- money in farming a player who has none. Nothing is owned until it is
-- collected: drive over a koin and it is yours, whoever made the mess, so
-- the fastest car to a fresh wreck takes the pile.
--
-- The server owns every koin: it decides where they land, who picked one up
-- and when an uncollected one is swept away. Clients only draw them and keep
-- a running total for the HUD.
--
-- How close you have to get is a radius per player -- `radius` from a car,
-- `footRadius` on foot -- times a reach that starts at 1 and that another
-- feature can raise (upgrades sells it) through Money:serverSetReach. A
-- player with more than the base reach sees it as a faint ring around them.
--
-- Drops arrive through the `serverKill` convention (docs/features.md): the
-- feature that killed something calls it, this one turns that into koins.
--
-- Messages
--   server -> all  FCK_DROP <id> <x> <y>
--   server -> all  FCK_TAKE <id> <playerId> <total>
--   server -> all  FCK_GONE <id>
--   server -> all  FCK_PURSE <playerId> <total>   (koins left the wallet: a death, a purchase)
--   server -> all  FCK_REACH <playerId> <scale>   (their pickup radius changed)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Sounds = require("src.features.money.sounds")

local Money = {
  name = "money",
  priority = 65, -- over the map (20) and pedestrians (60), under the medkits (70)
}

-- Tuning ------------------------------------------------------------------
Money.pedValue = 1 -- koins a flattened pedestrian drops (out of thin air)
Money.policeValue = 3 -- koins off a downed officer: the badge is worth something
Money.carValue = 5 -- most koins a wrecked driver drops, out of their own wallet
Money.radius = 30 -- px from car centre that counts as driving over one
Money.footRadius = 18 -- px from a body on foot that counts as picking one up
Money.scatter = 46 -- px; how wide a multi-koin drop spreads
Money.lifetime = 30 -- seconds an uncollected koin lies in the road
Money.maxCoins = 80 -- hard cap; the oldest is swept away to make room

local FADE_TIME = 4 -- seconds of blinking before a koin expires
local FLOAT_TIME = 1.2 -- seconds the "+1 Fck" hangs over a car
local COMBO_GAP = 0.45 -- seconds; pickups closer together than this chime higher

--- "1 Fck" / "3 Fcks". Other features may want it for a scoreboard.
function Money.amount(n)
  return ("%d %s"):format(n, n == 1 and "Fck" or "Fcks")
end

-- Client --------------------------------------------------------------------

Money.coins = {} -- id -> { x, y, age, seed }
Money.wallets = {} -- player id -> koins collected
Money.reach = {} -- player id -> pickup radius scale (absent = 1)
Money.floats = {} -- { x, y, text, t }
local time = 0
local combo, comboTimer = 0, 0

function Money:load()
  Sounds.load()
end

-- A koin dropped in the first server step can reach us just before the game
-- state is entered, so the koins themselves survive the way in and are only
-- dropped on the way out.
function Money:enterGame()
  self.floats = {}
  combo, comboTimer = 0, 0
end

function Money:exitGame()
  self.coins = {}
  self.wallets = {}
  self.reach = {}
  self.floats = {}
  combo, comboTimer = 0, 0
end

function Money:update(dt)
  time = time + dt
  comboTimer = comboTimer - dt
  if comboTimer <= 0 then
    combo = 0
  end
  for _, coin in pairs(self.coins) do
    coin.age = coin.age + dt
  end
  local i = 1
  while i <= #self.floats do
    local f = self.floats[i]
    f.t = f.t - dt
    f.y = f.y - 30 * dt
    if f.t <= 0 then
      table.remove(self.floats, i)
    else
      i = i + 1
    end
  end
end

-- A five-pointed star, built once: the face of the koin.
local STAR = {}
for i = 0, 9 do
  local r = (i % 2 == 0) and 6 or 2.5
  local a = -math.pi / 2 + i * math.pi / 5
  STAR[#STAR + 1] = math.cos(a) * r
  STAR[#STAR + 1] = math.sin(a) * r
end

--- A gold koin with a red star, spinning on the spot over its own shadow.
--- It blinks in its last seconds so nobody is surprised when it vanishes.
local function drawCoin(coin)
  local left = Money.lifetime - coin.age
  if left < FADE_TIME and math.floor(left * 6) % 2 == 0 then
    return
  end
  local x, y = coin.x, coin.y
  local t = time + coin.seed
  local glow = 0.5 + 0.5 * math.sin(t * 4)
  love.graphics.setColor(1, 0.85, 0.35, 0.05 + glow * 0.06)
  love.graphics.circle("fill", x, y, 15 + glow * 3)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.ellipse("fill", x, y + 8, 8, 3.5)

  love.graphics.push()
  love.graphics.translate(x, y + math.sin(t * 3) * 2)
  -- Turning slowly on the spot. It never gets thinner than half its width,
  -- or a koin spends most of its life as an invisible sliver.
  love.graphics.scale(math.max(0.5, math.abs(math.cos(t * 1.4))), 1)
  love.graphics.setColor(0.35, 0.23, 0.03)
  love.graphics.circle("fill", 0, 0, 11)
  love.graphics.setColor(0.99, 0.82, 0.24)
  love.graphics.circle("fill", 0, 0, 9.5)
  love.graphics.setColor(1, 0.95, 0.70, 0.8)
  love.graphics.arc("fill", 0, 0, 9.5, math.pi * 1.1, math.pi * 1.6)
  love.graphics.setColor(0.85, 0.11, 0.11)
  love.graphics.polygon("fill", STAR)
  love.graphics.pop()
end

--- The reach ring: only for the local player, only once it is bigger than
--- everyone starts with, so the upgrade shows and the road stays clean.
local function drawReach(client)
  local scale = Money.reach[client.myId]
  local me = client:myCar()
  if not (scale and scale > 1 and me) then
    return
  end
  local x, y, onFoot = Features.clientBodyPose(client, client.myId, me)
  local r = (onFoot and Money.footRadius or Money.radius) * scale
  local pulse = 0.5 + 0.5 * math.sin(time * 3)
  love.graphics.setColor(1, 0.85, 0.35, 0.05 + pulse * 0.04)
  love.graphics.circle("fill", x, y, r)
  love.graphics.setColor(1, 0.85, 0.35, 0.22 + pulse * 0.1)
  love.graphics.setLineWidth(1.5)
  love.graphics.circle("line", x, y, r)
  love.graphics.setLineWidth(1)
end

function Money:drawBelowCars(client)
  drawReach(client)
  for _, coin in pairs(self.coins) do
    drawCoin(coin)
  end
  love.graphics.setColor(1, 1, 1)
end

function Money:drawAboveCars()
  love.graphics.setFont(UI.fonts.body)
  for _, f in ipairs(self.floats) do
    if f.lost then
      love.graphics.setColor(1, 0.35, 0.3, math.min(1, f.t))
    else
      love.graphics.setColor(1, 0.85, 0.3, math.min(1, f.t))
    end
    love.graphics.printf(f.text, f.x - 60, f.y, 120, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

function Money:drawHUD(client)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.print(Money.amount(self.wallets[client.myId] or 0), 10, 118)
  love.graphics.setColor(1, 1, 1)
end

Money.clientMessages = {
  FCK_DROP = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if id and x and y then
      Money.coins[id] = { x = x, y = y, age = 0, seed = love.math.random() * 6.28 }
    end
  end,
  FCK_TAKE = function(client, args)
    local id, by, total = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local coin = id and Money.coins[id]
    if not coin then
      return
    end
    Money.coins[id] = nil
    if by and total then
      Money.wallets[by] = total
    end
    combo = math.min(combo + 1, 6)
    comboTimer = COMBO_GAP
    Sounds.play(coin.x, coin.y, 1 + combo * 0.06)
    local car = by and client.cars[by]
    Money.floats[#Money.floats + 1] = {
      x = car and car.dx or coin.x,
      y = (car and car.dy or coin.y) - 30,
      text = "+" .. Money.amount(1),
      t = FLOAT_TIME,
    }
  end,
  FCK_GONE = function(_client, args)
    local id = tonumber(args[1])
    if id then
      Money.coins[id] = nil
    end
  end,
  FCK_REACH = function(_client, args)
    local id, scale = tonumber(args[1]), tonumber(args[2])
    if id and scale then
      Money.reach[id] = scale
    end
  end,
  FCK_PURSE = function(client, args)
    local id, total = tonumber(args[1]), tonumber(args[2])
    if not (id and total) then
      return
    end
    local lost = (Money.wallets[id] or 0) - total
    Money.wallets[id] = total
    -- A hidden wreck stops moving, so its last drawn position is the spot
    -- the koins rolled out at.
    local car = client.cars[id]
    if lost > 0 and car then
      Money.floats[#Money.floats + 1] = {
        x = car.dx,
        y = car.dy - 30,
        text = "-" .. Money.amount(lost),
        t = FLOAT_TIME,
        lost = true,
      }
    end
  end,
}

-- Server ----------------------------------------------------------------

local sv = nil -- { coins = { id -> { x, y, at } }, n, nextId, wallets, reach, time }

local function dropMessage(id, coin)
  return Protocol.encode("FCK_DROP", id, ("%.0f"):format(coin.x), ("%.0f"):format(coin.y))
end

--- Sweep the koin that has lain around longest; keeps a long brawl from
--- burying the map (and the wire) in gold.
local function sweepOldest(server)
  local oldest, oldestAt
  for id, coin in pairs(sv.coins) do
    if not oldestAt or coin.at < oldestAt then
      oldest, oldestAt = id, coin.at
    end
  end
  if oldest then
    sv.coins[oldest] = nil
    sv.n = sv.n - 1
    server:broadcast(Protocol.encode("FCK_GONE", oldest))
  end
end

local function spawnCoin(server, x, y)
  if sv.n >= Money.maxCoins then
    sweepOldest(server)
  end
  local id = sv.nextId
  sv.nextId = id + 1
  local coin = { x = x, y = y, at = sv.time }
  sv.coins[id] = coin
  sv.n = sv.n + 1
  server:broadcast(dropMessage(id, coin))
end

--- Koins inside a wall can never be collected, so a wreck against a building
--- gets a few tries at open tarmac (the `blocksPoint` convention) before it
--- settles for wherever it landed.
local function free(x, y)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint and f:blocksPoint(x, y) then
      return false
    end
  end
  return true
end

--- Spill `count` koins around (x, y). A single one lands nearly on the spot,
--- a pile spreads out so several cars can share the spoils.
function Money:drop(server, x, y, count)
  if not sv then
    return
  end
  for _ = 1, count do
    local cx, cy
    for _ = 1, 6 do
      local a = love.math.random() * 2 * math.pi
      local d = count > 1 and (12 + love.math.random() * self.scatter) or love.math.random() * 8
      cx, cy = x + math.cos(a) * d, y + math.sin(a) * d
      if free(cx, cy) then
        break
      end
    end
    spawnCoin(server, cx, cy)
  end
end

--- Turn up to `most` of a player's koins out of their pocket and tell
--- everyone what they have left. Returns how many actually came out, which
--- is nothing at all for a player who was carrying nothing.
function Money:spill(server, id, most)
  local purse = (id and sv and sv.wallets[id]) or 0
  local count = math.min(most, purse)
  if count > 0 then
    sv.wallets[id] = purse - count
    server:broadcast(Protocol.encode("FCK_PURSE", id, purse - count))
  end
  return count
end

--- Something died somewhere: pay out. See the `serverKill` convention in
--- docs/features.md. Kinds this feature doesn't price are ignored.
---
--- A pedestrian is loose change nobody owned, an officer a fatter handful of
--- the same. A driver is different: what lands on the tarmac comes out of the
--- wallet they were driving around with, so killing the same broke player
--- twice pays nothing.
function Money:serverKill(server, kill)
  if kill.kind == "pedestrian" then
    self:drop(server, kill.x, kill.y, self.pedValue)
  elseif kill.kind == "police" then
    self:drop(server, kill.x, kill.y, self.policeValue)
  elseif kill.kind == "car" then
    self:drop(server, kill.x, kill.y, self:spill(server, kill.victim, self.carValue))
  end
end

function Money:serverStart()
  sv = { coins = {}, n = 0, nextId = 1, wallets = {}, reach = {}, time = 0 }
end

--- A player's pickup radius scale on the host, 1 to start with.
function Money:reachOf(id)
  return sv and sv.reach[id] or 1
end

--- Set how far a player's koins jump to them, as a multiple of the base
--- radius, for the rest of the game. Other features reach this via
--- Features.byName.money (upgrades does). Returns the scale set.
function Money:serverSetReach(server, player, scale)
  if not sv then
    return nil
  end
  scale = math.max(0.1, scale)
  sv.reach[player.id] = scale
  server:broadcast(Protocol.encode("FCK_REACH", player.id, ("%.2f"):format(scale)))
  return scale
end

--- Someone joining mid-game sees the koins already lying about.
function Money:serverPlayerJoined(server, player)
  if not sv then
    return
  end
  for id, coin in pairs(sv.coins) do
    server:send(player, dropMessage(id, coin))
  end
end

function Money:serverPlayerLeft(_server, player)
  if sv then
    sv.wallets[player.id] = nil
    sv.reach[player.id] = nil
  end
end

function Money:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt

  for id, coin in pairs(sv.coins) do
    if sv.time - coin.at >= self.lifetime then
      sv.coins[id] = nil
      sv.n = sv.n - 1
      server:broadcast(Protocol.encode("FCK_GONE", id))
    else
      for _, player in pairs(server.players) do
        local car = player.car
        local bx, by, onFoot
        if car then
          bx, by, onFoot = Features.bodyPose(server, player)
        end
        local reach = (onFoot and self.footRadius or self.radius) * (sv.reach[player.id] or 1)
        local reach2 = reach * reach
        if car and not car.hidden and (bx - coin.x) ^ 2 + (by - coin.y) ^ 2 < reach2 then
          local total = (sv.wallets[player.id] or 0) + 1
          sv.wallets[player.id] = total
          sv.coins[id] = nil
          sv.n = sv.n - 1
          server:broadcast(Protocol.encode("FCK_TAKE", id, player.id, total))
          break
        end
      end
    end
  end
end

--- Koins collected by a player this game. Other features (a scoreboard, a
--- shop) can read it on the host.
function Money:wallet(id)
  return sv and sv.wallets[id] or 0
end

--- Take `amount` koins out of a player's wallet, for a shop (upgrades). All
--- or nothing: returns true and tells everyone the new total, or false and
--- touches nothing when they can't cover it.
function Money:spend(server, id, amount)
  local purse = self:wallet(id)
  if not sv or amount <= 0 or purse < amount then
    return false
  end
  sv.wallets[id] = purse - amount
  server:broadcast(Protocol.encode("FCK_PURSE", id, purse - amount))
  return true
end

--- For tests.
function Money.server()
  return sv
end

return Money
