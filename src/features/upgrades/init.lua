-- Upgrades: spend your Fcks on a bigger body and a longer arm, at the gym.
-- The gym is a building beside the Jobs building and the shop (quests/jobs.lua
-- picks it from the map the same way on every machine, so there is nothing
-- to send; `Upgrades:here()`, the default city only), marked on the minimap
-- with a dumbbell. Stand on the square by its door and the action key (F,
-- through `actionTaken`) opens the upgrade panel; 1 buys the next level of
-- health, 2 the next level of stamina, 3 the next level of pickup reach (how
-- far koins and drops jump to you), 4 the next level of stamina regen (how
-- fast it comes back), 5 another inventory slot (buildings). F again, Esc or
-- walking away from the door closes it. Each level costs more than the last
-- and there are five of each, so a full set is a serious amount of roadkill.
--
-- The host owns the sale: it checks the buyer is at the gym door, checks
-- the wallet (money), takes the koins and
-- raises the value through the feature that owns it -- weapons for health,
-- on-foot for stamina and its regen, money itself for reach, buildings for
-- inventory slots -- which tell
-- the clients whatever they need to know themselves. This feature only
-- remembers the level each player is at and draws the shop.
-- Nothing is bought on the client's say-so; a client that asks for what it
-- can't afford just hears a buzz.
--
-- Keys are Controls actions, so they can be rebound in Settings. The buy
-- keys only count while the shop is open, so they can share keys with
-- anything that isn't.
--
-- Messages
--   client -> server  UPG_BUY   <kind>
--   server -> all     UPG_LEVEL <id> <kind> <level>
--   server -> buyer   UPG_DENY  <kind> <reason>    "broke", "maxed", "away" or "gone"

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Sounds = require("src.features.upgrades.sounds")
local Storefront = require("src.features.quests.storefront")

local Upgrades = {
  name = "upgrades",
  priority = 960, -- HUD after weapons (950): the shop goes over everything but the cursor (vision, 900)
}

-- Tuning ------------------------------------------------------------------
-- What each kind starts at, what a level adds, how a value reads on the shop
-- and what each level costs. The cost list is as long as there are levels.
-- Reach is a percentage of the base pickup radius: koins (money) and every drop (pickups) use it.
Upgrades.kinds = {
  {
    key = "health", label = "Health", base = 100, step = 20, costs = { 5, 8, 12, 16, 20 },
    action = "buy-health", defaultKey = "1",
    show = function(v) return ("%d HP"):format(v) end,
  },
  {
    key = "stamina", label = "Stamina", base = 100, step = 25, costs = { 4, 6, 9, 12, 15 },
    action = "buy-stamina", defaultKey = "2",
    show = function(v) return ("%d stamina"):format(v) end,
  },
  {
    key = "reach", label = "Pickup reach", base = 100, step = 40, costs = { 3, 5, 8, 11, 14 },
    action = "buy-reach", defaultKey = "3",
    show = function(v) return ("x%.1f reach"):format(v / 100) end,
  },
  {
    key = "regen", label = "Stamina regen", base = 100, step = 30, costs = { 3, 5, 8, 11, 14 },
    action = "buy-regen", defaultKey = "4",
    show = function(v) return ("x%.1f regen"):format(v / 100) end,
  },
  {
    key = "slots", label = "Inventory slots", base = 4, step = 1, costs = { 4, 7, 10, 14, 18 },
    action = "buy-slots", defaultKey = "5",
    show = function(v) return ("%d slots"):format(v) end,
  },
}
Upgrades.byKey = {}
for i, k in ipairs(Upgrades.kinds) do
  k.index = i
  Upgrades.byKey[k.key] = k
end

local NOTICE_TIME = 1.6 -- seconds a "not enough" line stays on the shop

-- The gym ------------------------------------------------------------------
Upgrades.enterRadius = 60 -- px from the door that brings the panel up (the shop's)
Upgrades.leaveRadius = 140 -- px from the door that takes it down again
local SLACK = 60 -- px the host allows for a buyer drawn a little behind where it is

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The gym while the default city is in play, or nil.
function Upgrades:here()
  local quests = Features.byName.quests
  local j = quests and quests.jobs and quests:jobs()
  return j and j.gym or nil
end

--- The ceiling a kind gives at `level`.
local function valueAt(kind, level)
  return kind.base + kind.step * level
end

-- Client --------------------------------------------------------------------

Upgrades.open = false
Upgrades.levels = {} -- player id -> { health = n, stamina = n }
Upgrades.notice = nil -- { text, t }
Upgrades.flash = 0 -- seconds of glow left on a row just bought
Upgrades.flashKind = nil
Upgrades.near = nil -- the gym when I am standing at its door, or nil
local time = 0

function Upgrades:load()
  Sounds.load()
  Controls.register("gym", "Open / close the gym (at its door)", "f") -- the action key, like the shop's
  for _, kind in ipairs(self.kinds) do
    Controls.register(kind.action, "Buy " .. kind.label:lower() .. " (gym open)", kind.defaultKey)
  end
end

function Upgrades:enterGame()
  self.open = false
  self.notice = nil
  self.flash = 0
  self.near = nil
end

function Upgrades:exitGame()
  self:enterGame()
  self.levels = {}
end

--- The number keys are the shop's while it is open (weapons asks).
function Upgrades:menuOpen()
  return self.open
end

--- The `actionTaken` convention: the action key is ours at the door and
--- while the panel is up, so on-foot leaves the cars alone.
function Upgrades:actionTaken()
  return self.open or self.near ~= nil
end

--- The `closeMenu` convention: Esc takes the panel down.
function Upgrades:closeMenu()
  if not self.open then
    return false
  end
  self.open, self.notice = false, nil
  return true
end

function Upgrades:levelOf(id, key)
  local l = self.levels[id]
  return l and l[key] or 0
end

--- Koins in my wallet, as the money feature last told me.
local function wallet(client)
  local money = Features.byName.money
  return money and money.mine and money:mine(client) or 0
end

function Upgrades:update(dt, client)
  time = time + dt
  local x, y = client:myPose()
  local gym = x and self:here()
  local d2 = gym and dist2(x, y, gym.doorX, gym.doorY) or math.huge
  self.near = d2 <= self.enterRadius ^ 2 and gym or nil
  if self.open and d2 > self.leaveRadius ^ 2 then
    self.open, self.notice = false, nil -- walked away: the panel goes down
  end
  if self.notice then
    self.notice.t = self.notice.t - dt
    if self.notice.t <= 0 then
      self.notice = nil
    end
  end
  self.flash = math.max(0, self.flash - dt)
end

function Upgrades:keypressed(key, client)
  if Controls.is("gym", key) and (self.open or self.near) then
    self.open = not self.open
    self.notice = nil
    return
  end
  if not self.open or not client then
    return
  end
  for _, kind in ipairs(self.kinds) do
    if Controls.is(kind.action, key) then
      self:tryBuy(client, kind.key)
      return
    end
  end
end

--- Ask the host for the next level. The refusal cases are checked here too,
--- so the shop can answer at once; the host is still the one that decides.
function Upgrades:tryBuy(client, key)
  local kind = self.byKey[key]
  local level = self:levelOf(client.myId, key)
  local cost = kind.costs[level + 1]
  if not cost then
    self:refuse(kind, "maxed")
  elseif wallet(client) < cost then
    self:refuse(kind, "broke")
  else
    client:send(Protocol.encode("UPG_BUY", key))
  end
end

function Upgrades:refuse(kind, reason)
  local text
  if reason == "maxed" then
    text = kind.label .. " is already maxed out"
  elseif reason == "away" then
    text = "Get back to the gym to train"
  elseif reason == "gone" then
    text = "There is no gym on this map"
  else
    text = "Not enough Fcks for " .. kind.label:lower()
  end
  self.notice = { text = text, t = NOTICE_TIME }
  Sounds.play("buzz")
end

--- One row of the shop: key, name, level pips, what the next level gives and
--- what it costs. Greyed when it can't be bought.
local function drawRow(self, kind, x, y, w, level, purse, keyName)
  local maxed = level >= #kind.costs
  local cost = kind.costs[level + 1]
  local affordable = cost and purse >= cost
  local glow = self.flashKind == kind.key and self.flash or 0

  if glow > 0 then
    love.graphics.setColor(1, 0.85, 0.3, glow * 0.5)
    love.graphics.rectangle("fill", x - 8, y - 6, w + 16, 52, 6)
  end

  local dim = (maxed or not affordable) and 0.5 or 1
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0.36 * dim + 0.2, 0.56 * dim + 0.2, 0.92 * dim, 1)
  love.graphics.rectangle("fill", x, y, 34, 34, 6)
  love.graphics.setColor(1, 1, 1, dim)
  love.graphics.printf(keyName, x, y + 7, 34, "center")
  love.graphics.print(kind.label, x + 46, y - 2)

  -- Level pips, one per level, lit up to the current one.
  for i = 1, #kind.costs do
    if i <= level then
      love.graphics.setColor(1, 0.85, 0.3, dim)
    else
      love.graphics.setColor(1, 1, 1, 0.18)
    end
    love.graphics.circle("fill", x + 52 + (i - 1) * 16, y + 28, 5, 12)
  end

  love.graphics.setFont(UI.fonts.small)
  local now = kind.show(valueAt(kind, level))
  if maxed then
    love.graphics.setColor(1, 0.85, 0.3, 0.9)
    love.graphics.printf(now .. "   MAX", x, y + 2, w, "right")
  else
    love.graphics.setColor(1, 1, 1, dim)
    love.graphics.printf(now .. " -> " .. kind.show(valueAt(kind, level + 1)), x, y + 2, w, "right")
    if affordable then
      love.graphics.setColor(1, 0.85, 0.3)
    else
      love.graphics.setColor(1, 0.45, 0.4, 0.9)
    end
    love.graphics.printf(("%d %s"):format(cost, cost == 1 and "Fck" or "Fcks"), x, y + 21, w, "right")
  end
end

-- The building -----------------------------------------------------------------

local GYM_RED = { 1, 0.42, 0.32 }
local IRON = { 0.22, 0.23, 0.26 }
local STEEL = { 0.72, 0.74, 0.78 }
local STYLE = {
  rim = { 0.2, 0.12, 0.12 },
  roof = { 0.36, 0.27, 0.27 },
  awning = { GYM_RED, { 0.14, 0.14, 0.16 } },
  glass = { 1, 0.8, 0.7 },
}

--- A dumbbell lying across (x, y), `s` px from end to end: a bar with two
--- plates at each end.
local function dumbbell(x, y, s, plate)
  local half = s / 2
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x - half + 2, y - s * 0.2 + 2, s, s * 0.4, 2)
  love.graphics.setColor(STEEL)
  love.graphics.rectangle("fill", x - half * 0.7, y - s * 0.04, s * 0.7, s * 0.08)
  love.graphics.setColor(plate or IRON)
  for side = -1, 1, 2 do
    love.graphics.rectangle("fill", x + side * half * 0.78 - s * 0.07, y - s * 0.2, s * 0.14, s * 0.4, 2)
    love.graphics.rectangle("fill", x + side * half * 0.95 - s * 0.05, y - s * 0.14, s * 0.1, s * 0.28, 2)
  end
end

--- A weight bench seen from above, long side along x, centred on (x, y),
--- with a barbell racked over its head end.
local function bench(x, y)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", x - 18 + 3, y - 6 + 3, 36, 12, 3)
  love.graphics.setColor(0.12, 0.12, 0.14)
  love.graphics.rectangle("fill", x - 18, y - 6, 36, 12, 3)
  love.graphics.setColor(0.55, 0.15, 0.13)
  love.graphics.rectangle("fill", x - 16, y - 4, 32, 8, 2)
  love.graphics.setColor(STEEL)
  love.graphics.rectangle("fill", x - 17, y - 16, 2, 32)
  love.graphics.setColor(IRON)
  love.graphics.rectangle("fill", x - 20, y - 18, 8, 5, 1)
  love.graphics.rectangle("fill", x - 20, y + 13, 8, 5, 1)
end

--- A rack of three dumbbells, from (x, y) along x.
local function rack(x, y)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", x - 4 + 3, y - 8 + 3, 48, 16, 2)
  love.graphics.setColor(0.3, 0.3, 0.33)
  love.graphics.rectangle("fill", x - 4, y - 8, 48, 16, 2)
  for i = 0, 2 do
    dumbbell(x + 6 + i * 14, y, 12, i == 1 and { 0.6, 0.2, 0.17 } or IRON)
  end
end

--- The building over the one it took, a storefront like the shop and the
--- Jobs building (quests/storefront.lua): a dumbbell on the roof, its sign,
--- a bench and a rack of weights outside, and the glowing square by the
--- door where the panel opens.
function Upgrades:drawBelowCars()
  local gym = self:here()
  if not gym then
    return
  end
  Storefront.draw(gym, STYLE, time)
  Storefront.front(gym, function(W, D)
    local y = Storefront.outside(D)
    bench(-W / 2 + 28, y)
    rack(W / 2 - 58, y)
  end)
  local ex, ey, r = Storefront.emblem(gym, 40)
  dumbbell(ex, ey, r * 2, GYM_RED)
  Storefront.sign(gym, "GYM", GYM_RED)
  local c = GYM_RED
  local pulse = self.near and 0.6 + 0.4 * math.abs(math.sin(time * 4)) or 0.5 + 0.5 * math.sin(time * 2.5)
  love.graphics.setColor(c[1], c[2], c[3], 0.10 + 0.08 * pulse)
  love.graphics.circle("fill", gym.doorX, gym.doorY, self.enterRadius)
  love.graphics.setColor(c[1], c[2], c[3], 0.35 + 0.25 * pulse)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", gym.doorX, gym.doorY, self.enterRadius)
  love.graphics.setLineWidth(1)
  dumbbell(gym.doorX, gym.doorY, 26, GYM_RED)
  love.graphics.setColor(1, 1, 1)
end

--- The gym on the minimap: a red dumbbell, so it can be found.
function Upgrades:drawOnMinimap(_client, toMap)
  local gym = self:here()
  if not gym then
    return
  end
  local x, y = toMap(gym.x + gym.w / 2, gym.y + gym.h / 2)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.rectangle("fill", x - 8, y - 4, 16, 8, 2)
  love.graphics.setColor(GYM_RED)
  love.graphics.rectangle("fill", x - 7, y - 3, 3, 6)
  love.graphics.rectangle("fill", x + 4, y - 3, 3, 6)
  love.graphics.rectangle("fill", x - 4, y - 1, 8, 2)
  love.graphics.setColor(1, 1, 1)
end

--- At the door with the panel down: the offer, where the shop's and the
--- plots' prompts stand.
local function drawPrompt()
  local w, h = love.graphics.getDimensions()
  local key = Controls.name(Controls.bindings("gym")[1])
  local text = "Gym.  " .. key .. ": train (upgrades)"
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, 1, h - 129, w, "center")
  love.graphics.setColor(GYM_RED)
  love.graphics.printf(text, 0, h - 130, w, "center")
  love.graphics.setColor(1, 1, 1)
end

function Upgrades:drawHUD(client)
  local openKey = Controls.name(Controls.bindings("gym")[1])
  love.graphics.setFont(UI.fonts.small)
  if not self.open and self.near then
    drawPrompt()
    love.graphics.setFont(UI.fonts.small)
  end
  if not self.open then
    -- Under the koin in the bottom-right corner: how many upgrades the
    -- wallet covers right now, only when there are any.
    local money = Features.byName.money
    local purse = wallet(client)
    local affordable = 0
    for _, kind in ipairs(self.kinds) do
      local cost = kind.costs[self:levelOf(client.myId, kind.key) + 1]
      if cost and purse >= cost then
        affordable = affordable + 1
      end
    end
    if affordable == 0 then
      return
    end
    local pulse = 0.75 + 0.25 * math.sin(love.timer.getTime() * 4)
    local text = ("%d upgrade%s affordable at the gym"):format(affordable, affordable == 1 and "" or "s")
    local color = { 0.5, 1, 0.55, pulse }
    local font = UI.fonts.small
    local x, y
    if money and money.hudCoin then
      local w = love.graphics.getWidth()
      local _, _, _, below = money:hudCoin()
      x, y = w - money.hud.margin - font:getWidth(text), below
    else
      x, y = 10, 172
    end
    UI.label(text, x, y, color)
    love.graphics.setColor(1, 1, 1)
    return
  end

  local w, h = love.graphics.getDimensions()
  local pw, ph = 400, 110 + #self.kinds * 58 + 46
  local px, py = math.floor((w - pw) / 2), math.floor((h - ph) / 2)
  local purse = wallet(client)

  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.10, 0.10, 0.13, 0.96)
  love.graphics.rectangle("fill", px, py, pw, ph, 10)
  love.graphics.setColor(1, 0.85, 0.3, 0.8)
  love.graphics.rectangle("line", px, py, pw, ph, 10)

  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("UPGRADES", px, py + 14, pw, "center")
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.printf(("You have %d %s"):format(purse, purse == 1 and "Fck" or "Fcks"), px, py + 50, pw, "center")

  local rowX, rowW = px + 24, pw - 48
  for i, kind in ipairs(self.kinds) do
    local keyName = Controls.name(Controls.bindings(kind.action)[1])
    drawRow(self, kind, rowX, py + 84 + (i - 1) * 58, rowW, self:levelOf(client.myId, kind.key), purse, keyName)
  end

  love.graphics.setFont(UI.fonts.small)
  if self.notice then
    love.graphics.setColor(1, 0.45, 0.4, math.min(1, self.notice.t * 2))
    love.graphics.printf(self.notice.text, px, py + ph - 44, pw, "center")
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.printf(openKey .. ": close", px, py + ph - 24, pw, "center")
  love.graphics.setColor(1, 1, 1)
end

Upgrades.clientMessages = {
  UPG_LEVEL = function(client, args)
    local id, key, level = tonumber(args[1]), args[2], tonumber(args[3])
    if not (id and Upgrades.byKey[key] and level) then
      return
    end
    Upgrades.levels[id] = Upgrades.levels[id] or {}
    Upgrades.levels[id][key] = level
    -- Levels put back from a saved world arrive before START: no chime for those.
    if id == client.myId and client.started then
      Sounds.play("chime")
      Upgrades.flash, Upgrades.flashKind = 0.8, key
      Upgrades.notice = nil
    end
  end,
  UPG_DENY = function(_client, args)
    local kind = Upgrades.byKey[args[1]]
    if kind then
      Upgrades:refuse(kind, args[2])
    end
  end,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { levels = { id -> { health = n, stamina = n } } }

function Upgrades:serverStart()
  sv = { levels = {} }
end

function Upgrades:serverPlayerLeft(_server, player)
  if sv then
    sv.levels[player.id] = nil
  end
end

--- Put a player's ceiling where their level says, through whoever owns it.
local function apply(server, player, kind, level)
  local value = valueAt(kind, level)
  if kind.key == "health" then
    local weapons = Features.byName.weapons
    if weapons and weapons.serverSetMaxHealth then
      weapons:serverSetMaxHealth(server, player, value)
    end
  elseif kind.key == "stamina" then
    local onFoot = Features.byName["on-foot"]
    if onFoot and onFoot.serverSetMaxStamina then
      onFoot:serverSetMaxStamina(server, player, value)
    end
  elseif kind.key == "reach" then
    local money = Features.byName.money
    if money and money.serverSetReach then
      money:serverSetReach(server, player, value / 100)
    end
  elseif kind.key == "regen" then
    local onFoot = Features.byName["on-foot"]
    if onFoot and onFoot.serverSetStaminaRegen then
      onFoot:serverSetStaminaRegen(server, player, value / 100)
    end
  elseif kind.key == "slots" then
    local buildings = Features.byName.buildings
    if buildings and buildings.serverSetSlots then
      buildings:serverSetSlots(server, player, value)
    end
  end
end

--- Is the player's body (not a wreck) at the gym's door?
local function atDoor(server, player, gym)
  if not Features.present(player) then
    return false
  end
  local x, y = Features.bodyPose(server, player)
  return dist2(x, y, gym.doorX, gym.doorY) <= (Upgrades.enterRadius + SLACK) ^ 2
end

--- Sell `player` the next level of `key` at the gym. Returns true on a
--- sale; otherwise the reason it didn't happen ("gone", "away", "maxed",
--- "broke") as a second value.
function Upgrades:serverBuy(server, player, key)
  local kind = self.byKey[key]
  if not (sv and kind and player.body) then
    return false, "unknown"
  end
  local gym = self:here()
  if not gym then
    return false, "gone"
  elseif not atDoor(server, player, gym) then
    return false, "away"
  end
  local levels = sv.levels[player.id] or {}
  sv.levels[player.id] = levels
  local level = levels[key] or 0
  local cost = kind.costs[level + 1]
  if not cost then
    return false, "maxed"
  end
  local money = Features.byName.money
  if not (money and money.spend and money:spend(server, player.id, cost, kind.label:lower())) then
    return false, "broke"
  end
  levels[key] = level + 1
  apply(server, player, kind, level + 1)
  server:broadcast(Protocol.encode("UPG_LEVEL", player.id, key, level + 1))
  return true
end

Upgrades.serverMessages = {
  UPG_BUY = function(server, player, args)
    local key = args[1]
    if not Upgrades.byKey[key] then
      return -- garbage
    end
    local ok, reason = Upgrades:serverBuy(server, player, key)
    if not ok and reason ~= "unknown" then
      server:send(player, Protocol.encode("UPG_DENY", key, reason))
    end
  end,
}

-- Saved worlds (docs/persistence.md) ------------------------------------

Upgrades.SAVE_VERSION = 1

--- A player's part of a saved world: the level of each kind they bought,
--- not the ceilings those give (apply works them out again on load).
function Upgrades:serverSavePlayer(_server, player)
  local levels = sv and sv.levels[player.id]
  local out, any = {}, false
  for _, kind in ipairs(self.kinds) do
    local level = levels and levels[kind.key] or 0
    if level > 0 then
      out[kind.key] = level
      any = true
    end
  end
  if not any then
    return nil -- nothing bought yet
  end
  return { version = self.SAVE_VERSION, levels = out }
end

--- Their levels back, each ceiling raised through its owner exactly as a
--- purchase does, and everyone told. The slice came from a file: a newer
--- version is ignored, and so is any kind this game doesn't sell or a level
--- that isn't a number; the rest are held to what the shop can sell.
function Upgrades:serverLoadPlayer(server, player, data)
  if not sv or type(data) ~= "table" or data.version ~= self.SAVE_VERSION or type(data.levels) ~= "table" then
    return
  end
  local levels = sv.levels[player.id] or {}
  sv.levels[player.id] = levels
  for _, kind in ipairs(self.kinds) do
    local level = data.levels[kind.key]
    if type(level) == "number" and level == level then
      level = math.max(0, math.min(#kind.costs, math.floor(level)))
      if level > 0 then
        levels[kind.key] = level
        apply(server, player, kind, level)
        server:broadcast(Protocol.encode("UPG_LEVEL", player.id, kind.key, level))
      end
    end
  end
end

--- For tests.
function Upgrades.server()
  return sv
end

return Upgrades
