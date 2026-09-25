-- Shop: a place in the world that sells guns, ammo, abilities, medkits and
-- cars. A shopping bag on the road marks it, the way a star marks a quest
-- (`Shop.list`, one per map). Drive or walk onto the bag and a prompt
-- offers the shop on the action key (F, shared with getting in and out of
-- cars through the `actionTaken` convention); press it and the shop screen
-- comes up over the game (screen.lua), press it again to close it. Leaving
-- the bag closes it too.
--
-- What is for sale is catalog.lua: every gun and a box of its rounds, every
-- ability, a medkit, and every car model. Everything is free for now (a
-- price of 0); prices go in the catalog when the economy is ready and the
-- host charges them through money:spend the way every other sale works
-- (docs/features.md, "Selling things for Fcks").
--
-- Equipment (guns, abilities, armor, clothes) is sold in every tier
-- (tiers/init.lua): a row of tier buttons under the tabs picks the one the
-- cards show and sell, each card framed in its colour with what the tier
-- improves; a better tier is dearer (Catalog.price).
--
-- A click on a card asks the host. The host checks the buyer is on the bag
-- (SLACK px allowed for a car drawn a little behind where it is), that the
-- bag is on the map in play, that the wallet covers the price, and then
-- hands the thing over: an item goes into the buyer's bag through
-- buildings:serverGive, a car onto the road beside the marker through the
-- `serverDeliver` event (vehicles answers it), in the first delivery bay
-- with no car standing in it. Clients only draw the bag, the screen and ask.
--
-- Another feature can put a shop on its own map (`Shop:addShop(spec)`, the
-- turf war has a stand in each base) and open the screen from wherever
-- the player stands (`Shop:toggle(client)`): while it answers the
-- `shopAnywhere(client)` question the screen stays up away from any bag,
-- and while it answers `serverShopAnywhere(server, player)` the host sells
-- to a buyer who is not on one (a car still goes to the nearest bag's
-- bays on the map in play). Such a sale, away from the bag, is offered to
-- the `serverShopDeliver(server, player, item, n)` question first: a
-- feature that answers true has taken the goods to bring them to the
-- buyer its own way (the turf war's police car), and the buyer hears
-- SHOP_SENT instead of SHOP_OK. See docs/features.md.
--
-- Messages
--   client -> server  SHOP_BUY <item>[@<tier>]
--   server -> buyer   SHOP_OK  <item>[@<tier>] <n>      (bought; n of it went into the bag, or a car is outside)
--   server -> buyer   SHOP_SENT <item>[@<tier>] <n>     (bought; n of it is on its way, another feature's delivery)
--   server -> buyer   SHOP_NO  <reason>        (away | gone | broke | full | nodeliver | unknown)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Kinds = require("src.features.buildings.kinds")
local Catalog = require("src.features.shop.catalog")
local Screen = require("src.features.shop.screen")
local Sounds = require("src.features.shop.sounds")
local Tiers = require("src.features.tiers")

local Shop = {
  name = "shop",
  priority = 970, -- the screen goes over the upgrade shop (960); the inventory (995) and cursor come later
}

Shop.catalog = Catalog

-- Shops -------------------------------------------------------------------
-- `onMap` is the map the bag sits on (a key of city-map's `maps`) and
-- (x, y) where. `bays` are where a car bought here is put down, relative to
-- the bag: the first one with nothing standing in it is used. The city's
-- shop is on the east road, mirroring the wild man's star on the west one;
-- the road runs north-south there, so the bays line up along it.
local HALF_PI = math.pi / 2
Shop.list = {
  {
    id = "city",
    onMap = "city",
    x = 320, -- the centre line of the first north-south road east of the middle
    y = -220,
    bays = {
      { dx = -30, dy = -120, angle = -HALF_PI },
      { dx = 30, dy = -120, angle = HALF_PI },
      { dx = -30, dy = 120, angle = -HALF_PI },
      { dx = 30, dy = 120, angle = HALF_PI },
      { dx = -30, dy = -190, angle = -HALF_PI },
      { dx = 30, dy = -190, angle = HALF_PI },
      { dx = -30, dy = 190, angle = -HALF_PI },
      { dx = 30, dy = 190, angle = HALF_PI },
    },
  },
}
Shop.byId = {}
for _, s in ipairs(Shop.list) do
  Shop.byId[s.id] = s
end

--- Put a shop on a map: `spec` is shaped like an entry of `Shop.list`
--- (`id onMap x y bays`). Calling it again with the same id replaces that
--- shop, so a feature may register on every machine as its map comes up.
function Shop:addShop(spec)
  for i, existing in ipairs(self.list) do
    if existing.id == spec.id then
      self.list[i] = spec
      self.byId[spec.id] = spec
      return spec
    end
  end
  self.list[#self.list + 1] = spec
  self.byId[spec.id] = spec
  return spec
end

-- Tuning ------------------------------------------------------------------
Shop.enterRadius = 60 -- px from the bag that brings the screen up
Shop.leaveRadius = 140 -- px from the bag that takes it down again (and forgets a close)
Shop.markerSize = 26 -- px, the bag's half height on the road
Shop.bayClear = 48 -- px; a bay with a car closer than this is taken

local SLACK = 60 -- px the host allows for a buyer drawn a little behind where it is
local NOTICE_TIME = 2.5 -- seconds a line stays under the cards
local FLASH_TIME = 0.8 -- seconds a card glows after a purchase
local REASONS = {
  away = "Get back to the shop to buy that.",
  gone = "The shop isn't on this map.",
  broke = "Not enough Fcks for that.",
  full = "No room in your bag for that.",
  nodeliver = "Nobody can deliver a car here.",
  unknown = "That isn't for sale.",
}
local RED, GREEN = { 1, 0.45, 0.4 }, { 0.5, 1, 0.55 }

local function cityMap()
  return Features.byName["city-map"]
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The shop whose bag on map `current` is nearest to (x, y).
local function shopOn(current, x, y)
  local best, bestD2
  for _, s in ipairs(Shop.list) do
    if s.onMap == current then
      local d2 = x and dist2(x, y, s.x, s.y) or 0
      if not bestD2 or d2 < bestD2 then
        best, bestD2 = s, d2
      end
    end
  end
  return best
end

-- Client --------------------------------------------------------------------

Shop.open = false
Shop.tab = Catalog.tabs[1].key
Shop.page = 1
Shop.tier = Tiers.DEFAULT -- the tier the cards show and sell
Shop.notice = nil -- { text, color, t }
Shop.flash = nil -- { item, t }
Shop.near = nil -- the shop whose bag I am standing on, or nil
local time = 0

function Shop:load()
  Sounds.load()
  Controls.register("shop", "Open / close the shop (on its bag)", "f") -- the action key, like real-estate's buy
end

function Shop:enterGame()
  self.open, self.tab, self.page, self.notice, self.flash, self.near = false, Catalog.tabs[1].key, 1, nil, nil, nil
  self.tier = Tiers.DEFAULT
end

function Shop:exitGame()
  self:enterGame()
end

--- The `pointerTaken` convention: the mouse is ours while the screen is up.
function Shop:pointerTaken()
  return self.open
end

--- The `closeMenu` convention: Esc takes the screen down.
function Shop:closeMenu()
  if not self.open then
    return false
  end
  self.open = false
  return true
end

--- The `actionTaken` convention: the action key is ours on the bag and
--- while the screen is up, so on-foot leaves the cars alone.
function Shop:actionTaken()
  return self.open or self.near ~= nil
end

--- The world softens under the screen, the way it does under a quest offer.
function Shop:worldBlur()
  return self.open and 0.7 or 0
end

--- The shop whose bag on the map I am on is nearest (x, y), if any.
function Shop:here(x, y)
  local city = cityMap()
  return city and shopOn(city.current, x, y) or nil
end

function Shop:say(text, color)
  self.notice = { text = text, color = color or RED, t = NOTICE_TIME }
end

function Shop:update(dt, client)
  time = time + dt
  if self.notice then
    self.notice.t = self.notice.t - dt
    if self.notice.t <= 0 then
      self.notice = nil
    end
  end
  if self.flash then
    self.flash.t = self.flash.t - dt
    if self.flash.t <= 0 then
      self.flash = nil
    end
  end
  local x, y = client:myPose()
  local shop = x and self:here(x, y)
  local d2 = shop and dist2(x, y, shop.x, shop.y) or math.huge
  self.near = d2 <= self.enterRadius ^ 2 and shop or nil
  if self.open and d2 > self.leaveRadius ^ 2 and not Features.any("shopAnywhere", client) then
    self.open = false -- walked off: the screen goes down
  end
end

--- Put the screen up (from the first shelf) or take it down, wherever the
--- player is: for a feature that sells from anywhere (the turf war's O).
function Shop:toggle()
  if self.open then
    self.open = false
  else
    self.open, self.tab, self.page, self.notice = true, Catalog.tabs[1].key, 1, nil
  end
end

function Shop:keypressed(key)
  if not Controls.is("shop", key) then
    return
  end
  if self.open or self.near then
    self:toggle()
  end
end

--- Another screen over ours that has the mouse (the inventory draws on top
--- of the shop and takes the clicks meant for it).
local function covered()
  local inventory = Features.byName.inventory
  return inventory and inventory.open or false
end

function Shop:mousepressed(x, y, button, client)
  if not self.open or button ~= 1 or covered() then
    return
  end
  local L = Screen.layout(self.tab, self.page)
  for _, t in ipairs(L.tabs) do
    if Screen.inside(t, x, y) then
      self.tab, self.page = t.key, 1
      return
    end
  end
  for _, t in ipairs(L.tiers) do
    if Screen.inside(t, x, y) then
      self.tier = t.key
      return
    end
  end
  if L.prev and Screen.inside(L.prev, x, y) then
    self.page = (L.page - 2) % L.pages + 1
    return
  elseif L.next and Screen.inside(L.next, x, y) then
    self.page = L.page % L.pages + 1
    return
  end
  for _, r in ipairs(L.cards) do
    if Screen.inside(r, x, y) then
      self:tryBuy(client, r.entry, self.tier)
      return
    end
  end
end

--- Ask the host for `entry`, in tier `tier` if it comes in tiers. The
--- obvious refusals are given here at once (an empty wallet, a full bag);
--- the host still decides.
function Shop:tryBuy(client, entry, tier)
  local item = entry.tiered and Tiers.join(entry.item, tier) or entry.item
  local price = Catalog.price(entry, tier)
  local money = Features.byName.money
  if price > 0 and money and money.canAfford and not money:canAfford(client, price) then
    return self:refuse("broke")
  end
  if not Catalog.isCar(entry) then
    local b = Features.byName.buildings
    if b and b.inventory and Kinds.room(b.inventory, b.slots, item) < 1 then
      return self:refuse("full")
    end
  end
  client:send(Protocol.encode("SHOP_BUY", item))
end

function Shop:refuse(reason)
  self:say(REASONS[reason] or REASONS.unknown)
  Sounds.play("buzz")
end

--- A shopping bag: the body, a rim, two handles, centred on (x, y) with
--- half height `s`.
local function bagOutline(x, y, s)
  return x - s * 0.7, y - s * 0.35, x + s * 0.7, y - s * 0.35, x + s * 0.85, y + s, x - s * 0.85, y + s
end

local function fillBag(x, y, s)
  love.graphics.polygon("fill", bagOutline(x, y, s))
end

--- The bag on the road: a soft glow the size of the trigger, the bag
--- itself breathing slowly, and "SHOP" underneath.
function Shop:drawBelowCars()
  local city = cityMap()
  for _, shop in ipairs(self.list) do
    if city and shop.onMap == city.current then
      self:drawMarker(shop)
    end
  end
end

function Shop:drawMarker(shop)
  local pulse = 0.5 + 0.5 * math.sin(time * 2.5)
  local s = self.markerSize * (0.92 + 0.08 * pulse)
  local x, y = shop.x, shop.y
  local c = { 0.45, 0.95, 0.6 }
  love.graphics.setColor(c[1], c[2], c[3], 0.10 + 0.08 * pulse)
  love.graphics.circle("fill", x, y, self.enterRadius)
  love.graphics.setColor(c[1], c[2], c[3], 0.35 + 0.25 * pulse)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", x, y, self.enterRadius)
  -- Shadow, body, rim, handles.
  love.graphics.setColor(0, 0, 0, 0.35)
  fillBag(x + 4, y + 4, s)
  love.graphics.setColor(c[1], c[2], c[3])
  fillBag(x, y, s)
  love.graphics.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
  love.graphics.setLineWidth(3)
  love.graphics.polygon("line", bagOutline(x, y, s))
  love.graphics.arc("line", "open", x - s * 0.3, y - s * 0.35, s * 0.3, math.pi, 2 * math.pi)
  love.graphics.arc("line", "open", x + s * 0.3, y - s * 0.35, s * 0.3, math.pi, 2 * math.pi)
  love.graphics.setLineWidth(1)
  -- A price tag's worth of colour in the middle.
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.printf("$", x - 20, y - 2, 40, "center")
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf("SHOP", x - 59, y + s + 7, 120, "center")
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.printf("SHOP", x - 60, y + s + 6, 120, "center")
  love.graphics.setColor(1, 1, 1)
end

--- On the bag with the screen down: the offer, where the plot and
--- building prompts stand.
local function drawPrompt()
  local w, h = love.graphics.getDimensions()
  local key = Controls.name(Controls.bindings("shop")[1])
  local text = "Shop.  " .. key .. ": open shop"
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, 1, h - 129, w, "center")
  love.graphics.setColor(0.45, 0.95, 0.6)
  love.graphics.printf(text, 0, h - 130, w, "center")
  love.graphics.setColor(1, 1, 1)
end

function Shop:drawHUD(client)
  if not self.open then
    if self.near then
      drawPrompt()
    end
    return
  end
  local money = Features.byName.money
  local purse = money and money.mine and money:mine(client) or 0
  local mx, my = love.mouse.getPosition()
  Screen.draw(self.tab, self.page, purse, mx, my, self.flash, self.notice, self.tier)
  -- The cursor last of all, over the panel.
  local vision = Features.byName.vision
  if vision then
    vision:drawCursor(client)
  end
  love.graphics.setColor(1, 1, 1)
end

Shop.clientMessages = {
  SHOP_OK = function(_client, args)
    local item, n = args[1] or "", tonumber(args[2]) or 1
    local entry = Catalog.lookup(item)
    if not entry then
      return
    end
    Sounds.play("chime")
    Shop.flash = { item = entry.item, t = FLASH_TIME }
    if Catalog.isCar(entry) then
      Shop:say("Your " .. entry.name .. " is parked on the road outside.", GREEN)
    elseif n == 1 then
      Shop:say("Bought a " .. Kinds.name(item, 1) .. ". It's in your bag.", GREEN)
    else
      Shop:say("Bought " .. Kinds.label(item, n) .. ". They're in your bag.", GREEN)
    end
  end,
  SHOP_SENT = function(_client, args)
    local item, n = args[1] or "", tonumber(args[2]) or 1
    local entry = Catalog.lookup(item)
    if not entry then
      return
    end
    Sounds.play("chime")
    Shop.flash = { item = entry.item, t = FLASH_TIME }
    Shop:say("Bought " .. Kinds.label(item, n) .. ". A police car is on its way with it.", GREEN)
  end,
  SHOP_NO = function(_client, args)
    Shop:refuse(args[1])
  end,
}

-- Server --------------------------------------------------------------------

--- Is the player's body (not a wreck) on the bag?
local function onBag(server, player, shop)
  if not Features.present(player) then
    return false
  end
  local x, y = Features.bodyPose(server, player)
  return dist2(x, y, shop.x, shop.y) <= (Shop.enterRadius + SLACK) ^ 2
end

--- The first delivery bay of `shop` with no car standing in it (the first
--- of all when every one is taken): x, y, angle.
local function freeBay(server, shop)
  for _, bay in ipairs(shop.bays) do
    local bx, by = shop.x + bay.dx, shop.y + bay.dy
    local taken = false
    for _, car in pairs(server.vehicles) do
      if not car.hidden and not car.stowed and dist2(car.x, car.y, bx, by) < Shop.bayClear ^ 2 then
        taken = true
        break
      end
    end
    if not taken then
      return bx, by, bay.angle
    end
  end
  local bay = shop.bays[1]
  return shop.x + bay.dx, shop.y + bay.dy, bay.angle
end

--- Sell `player` what `item` stands for ("gun-uzi@rare": that tier of the
--- uzi). Returns true, how many were handed over and whether they are on
--- their way rather than in the bag, or false and the reason it didn't
--- happen.
function Shop:serverBuy(server, player, item)
  local entry, tier = Catalog.lookup(item)
  local price = entry and Catalog.price(entry, tier)
  local city = cityMap()
  if not (entry and city and player.body) then
    return false, "unknown"
  end
  local shop = shopOn(city.current, player.body.x, player.body.y)
  local here = shop and onBag(server, player, shop)
  if not shop then
    return false, "gone"
  elseif not here and not Features.any("serverShopAnywhere", server, player) then
    return false, "away"
  end
  local money = Features.byName.money
  if price > 0 and money and money.wallet and money:wallet(player.id) < price then
    return false, "broke"
  end
  local given, sent
  if Catalog.isCar(entry) then
    local x, y, angle = freeBay(server, shop)
    if not Features.any("serverDeliver", server, player, item, x, y, angle) then
      return false, "nodeliver"
    end
    given = 1
  elseif not here and Features.any("serverShopDeliver", server, player, item, entry.n) then
    given, sent = entry.n, true -- somebody is bringing it
  else
    local buildings = Features.byName.buildings
    given = buildings and buildings.serverGive and buildings:serverGive(server, player, item, entry.n) or 0
    if given < 1 then
      return false, "full"
    end
  end
  -- The thing is theirs; now the price, which the wallet was checked to
  -- cover a moment ago (spend is a no-op at 0).
  if price > 0 and money and money.spend then
    money:spend(server, player.id, price, entry.tiered and Tiers.named(entry.name, tier) or entry.name)
  end
  return true, given, sent
end

Shop.serverMessages = {
  SHOP_BUY = function(server, player, args)
    local ok, result, sent = Shop:serverBuy(server, player, args[1])
    if ok then
      server:send(player, Protocol.encode(sent and "SHOP_SENT" or "SHOP_OK", args[1], result))
    else
      server:send(player, Protocol.encode("SHOP_NO", result))
    end
  end,
}

return Shop
