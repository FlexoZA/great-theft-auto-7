-- Upgrades: spend your Fcks on a bigger body and a longer arm. P opens the
-- shop over the game; 1 buys the next level of health, 2 the next level of
-- stamina, 3 the next level of koin reach (how far a koin jumps to you), 4
-- the next level of stamina regen (how fast it comes back), P closes it
-- again. Each level costs more than the last and there are five of each,
-- so a full set is a serious amount of roadkill.
--
-- The host owns the sale: it checks the wallet (money), takes the koins and
-- raises the value through the feature that owns it -- weapons for health,
-- on-foot for stamina and its regen, money itself for reach -- which tell
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
--   server -> buyer   UPG_DENY  <kind> <reason>    "broke" or "maxed"

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Sounds = require("src.features.upgrades.sounds")

local Upgrades = {
  name = "upgrades",
  priority = 960, -- HUD after weapons (950): the shop goes over everything but the cursor (vision, 900)
}

-- Tuning ------------------------------------------------------------------
-- What each kind starts at, what a level adds, how a value reads on the shop
-- and what each level costs. The cost list is as long as there are levels.
-- Reach is a percentage of the money feature's base pickup radius.
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
    key = "reach", label = "Koin reach", base = 100, step = 40, costs = { 3, 5, 8, 11, 14 },
    action = "buy-reach", defaultKey = "3",
    show = function(v) return ("x%.1f reach"):format(v / 100) end,
  },
  {
    key = "regen", label = "Stamina regen", base = 100, step = 30, costs = { 3, 5, 8, 11, 14 },
    action = "buy-regen", defaultKey = "4",
    show = function(v) return ("x%.1f regen"):format(v / 100) end,
  },
}
Upgrades.byKey = {}
for i, k in ipairs(Upgrades.kinds) do
  k.index = i
  Upgrades.byKey[k.key] = k
end

local NOTICE_TIME = 1.6 -- seconds a "not enough" line stays on the shop

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

function Upgrades:load()
  Sounds.load()
  Controls.register("upgrades", "Open / close the upgrade shop", "p")
  for _, kind in ipairs(self.kinds) do
    Controls.register(kind.action, "Buy " .. kind.label:lower() .. " (shop open)", kind.defaultKey)
  end
end

function Upgrades:enterGame()
  self.open = false
  self.notice = nil
  self.flash = 0
end

function Upgrades:exitGame()
  self:enterGame()
  self.levels = {}
end

function Upgrades:levelOf(id, key)
  local l = self.levels[id]
  return l and l[key] or 0
end

--- Koins in my wallet, as the money feature last told me.
local function wallet(client)
  local money = Features.byName.money
  return money and money.wallets and money.wallets[client.myId] or 0
end

function Upgrades:update(dt)
  if self.notice then
    self.notice.t = self.notice.t - dt
    if self.notice.t <= 0 then
      self.notice = nil
    end
  end
  self.flash = math.max(0, self.flash - dt)
end

function Upgrades:keypressed(key, client)
  if Controls.is("upgrades", key) then
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
  local text = reason == "maxed" and (kind.label .. " is already maxed out")
    or ("Not enough Fcks for " .. kind.label:lower())
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

function Upgrades:drawHUD(client)
  local openKey = Controls.name(Controls.bindings("upgrades")[1])
  love.graphics.setFont(UI.fonts.small)
  if not self.open then
    love.graphics.setColor(0.6, 0.6, 0.65)
    love.graphics.print(openKey .. ": upgrades", 10, 172)
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
    if id == client.myId then
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
  end
end

--- Sell `player` the next level of `key`. Returns true on a sale; otherwise
--- the reason it didn't happen ("maxed", "broke") as a second value.
function Upgrades:serverBuy(server, player, key)
  local kind = self.byKey[key]
  if not (sv and kind and player.car) then
    return false, "unknown"
  end
  local levels = sv.levels[player.id] or {}
  sv.levels[player.id] = levels
  local level = levels[key] or 0
  local cost = kind.costs[level + 1]
  if not cost then
    return false, "maxed"
  end
  local money = Features.byName.money
  if not (money and money.spend and money:spend(server, player.id, cost)) then
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

--- For tests.
function Upgrades.server()
  return sv
end

return Upgrades
