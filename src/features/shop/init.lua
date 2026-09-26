-- Shop: a building in the city that sells guns, ammo, abilities, medkits
-- and cars. It stands in the same block as the Jobs building: quests/jobs.lua
-- picks both from the map the same way on every machine, so there is nothing
-- to send (`Shop:here()`, the default city only). Stand on the square by its
-- door and a prompt offers the shop on the action key (F, shared with getting
-- in and out of cars through the `actionTaken` convention); press it and the
-- shop screen comes up over the game (screen.lua), press it again to close
-- it. Leaving the door closes it too.
--
-- What is for sale is catalog.lua: every gun and a box of its rounds, every
-- ability, a medkit, armor and clothes, and every car model. Everything is free for now (a
-- price of 0); prices go in the catalog when the economy is ready and the
-- host charges them through money:spend the way every other sale works
-- (docs/features.md, "Selling things for Fcks").
--
-- Equipment (guns, abilities, armor, clothes) is sold in every tier
-- (tiers/init.lua): a row of tier buttons under the tabs picks the one the
-- cards show and sell, each card framed in its colour with what the tier
-- improves; a better tier is dearer (Catalog.price).
--
-- A click on a card shows it in the side panel on the right (what it does
-- and its numbers in the tier on show: details.lua); the panel's Buy button
-- asks the host. The host checks the buyer is at the door
-- (SLACK px allowed for a car drawn a little behind where it is), that the
-- shop is on the map in play, that the wallet covers the price, and then
-- hands the thing over: an item goes into the buyer's bag through
-- buildings:serverGive, a car onto the road outside the door through the
-- `serverDeliver` event (vehicles answers it), in the first delivery bay
-- with no car standing in it. Clients only draw the building, the screen
-- and ask.
--
-- Messages
--   client -> server  SHOP_BUY <item>[@<tier>]
--   server -> buyer   SHOP_OK  <item>[@<tier>] <n>      (bought; n of it went into the bag, or a car is outside)
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
local Layout = require("src.features.city-map.layout")
local Storefront = require("src.features.quests.storefront")

local Shop = {
  name = "shop",
  -- The screen goes over every HUD piece (the ability row is 990, the boss portraits 992), so none of them
  -- lies over its cards; only the inventory (995), which opens over the shop, comes later.
  priority = 993,
}

Shop.catalog = Catalog

-- The shop ----------------------------------------------------------------
-- Where cars bought here are put down, in steps along the road outside the
-- door: (along, lane) with lane 1 the near one and 2 the far one. The first
-- with nothing standing in it is used. A bay past the block's stretch of
-- road (in the crossing) is left out.
local T = Layout.TILE
local CAR_HALF = 40 -- px a parked car reaches along the road from its middle
local BAYS = { { -1.6, 1 }, { 1.6, 1 }, { -1.6, 2 }, { 1.6, 2 }, { -2.8, 1 }, { 2.8, 1 }, { -2.8, 2 }, { 2.8, 2 } }
local cache = setmetatable({}, { __mode = "k" }) -- jobs building -> shop

--- The shop beside the Jobs building `j`: its building (x, y, w, h), the
--- square by its door (doorX, doorY) and the delivery bays on the road
--- outside ({ x, y, angle }), or nil when the block had no room for one.
local function build(j)
  local b = j.shop
  if not b then
    return nil
  end
  local shop = { x = b.x, y = b.y, w = b.w, h = b.h, doorX = b.doorX, doorY = b.doorY, nx = b.nx, ny = b.ny, bays = {} }
  -- The door is mid-sidewalk; the road's two lanes are one and two tiles on.
  -- Traffic keeps to the lanes the way the rest of the city's does.
  local tx, ty = -b.ny, b.nx
  local k = b.block
  local lo, hi -- how far along the road the block's stretch runs
  if b.nx ~= 0 then
    lo, hi = k.y - T, k.y + k.h + T
  else
    lo, hi = k.x - T, k.x + k.w + T
  end
  for _, bay in ipairs(BAYS) do
    local x = b.doorX + b.nx * T * bay[2] + tx * T * bay[1]
    local y = b.doorY + b.ny * T * bay[2] + ty * T * bay[1]
    local angle
    if b.nx ~= 0 then -- a north-south road: the west lane heads north
      angle = (x < b.doorX + b.nx * T * 1.5) and -math.pi / 2 or math.pi / 2
    else -- an east-west road: the north lane heads east
      angle = (y < b.doorY + b.ny * T * 1.5) and 0 or math.pi
    end
    local along = b.nx ~= 0 and y or x
    if along - CAR_HALF >= lo and along + CAR_HALF <= hi then
      shop.bays[#shop.bays + 1] = { x = x, y = y, angle = angle }
    end
  end
  return shop
end

--- The shop while the default city is in play, or nil.
function Shop:here()
  local quests = Features.byName.quests
  local j = quests and quests.jobs and quests:jobs()
  if not j then
    return nil
  end
  if cache[j] == nil then
    cache[j] = build(j) or false
  end
  return cache[j] or nil
end

-- Tuning ------------------------------------------------------------------
Shop.enterRadius = 60 -- px from the door that brings the screen up
Shop.leaveRadius = 140 -- px from the door that takes it down again
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

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- Client --------------------------------------------------------------------

Shop.open = false
Shop.tab = Catalog.tabs[1].key
Shop.page = 1
Shop.tier = Tiers.DEFAULT -- the tier the cards show and sell
Shop.notice = nil -- { text, color, t }
Shop.flash = nil -- { item, t }
Shop.picked = nil -- the catalog entry in the side panel, or nil
Shop.near = nil -- the shop when I am standing at its door, or nil
local time = 0

function Shop:load()
  Sounds.load()
  Controls.register("shop", "Open / close the shop (at its door)", "f") -- the action key, like real-estate's buy
end

function Shop:enterGame()
  self.open, self.tab, self.page, self.notice, self.flash, self.near = false, Catalog.tabs[1].key, 1, nil, nil, nil
  self.tier, self.picked = Tiers.DEFAULT, nil
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

--- The `actionTaken` convention: the action key is ours at the door and
--- while the screen is up, so on-foot leaves the cars alone.
function Shop:actionTaken()
  return self.open or self.near ~= nil
end

--- The world softens under the screen, the way it does under a quest offer.
function Shop:worldBlur()
  return self.open and 0.7 or 0
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
  local shop = x and self:here()
  local d2 = shop and dist2(x, y, shop.doorX, shop.doorY) or math.huge
  self.near = d2 <= self.enterRadius ^ 2 and shop or nil
  if self.open and d2 > self.leaveRadius ^ 2 then
    self.open = false -- walked away: the screen goes down
  end
end

function Shop:keypressed(key)
  if not Controls.is("shop", key) then
    return
  end
  if self.open then
    self.open = false
  elseif self.near then
    self.open, self.tab, self.page, self.notice, self.picked = true, Catalog.tabs[1].key, 1, nil, nil
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
  local L = Screen.layout(self.tab, self.page, self.picked)
  if L.buy and Screen.inside(L.buy, x, y) then
    self:tryBuy(client, self.picked, self.tier)
    return
  end
  for _, t in ipairs(L.tabs) do
    if Screen.inside(t, x, y) then
      if t.key ~= self.tab then
        self.tab, self.page, self.picked = t.key, 1, nil
      end
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
      self.picked = r.entry -- into the side panel; its Buy button buys it
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

local function drawBag(x, y, s, c)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.polygon("fill", bagOutline(x + s * 0.15, y + s * 0.15, s))
  love.graphics.setColor(c)
  love.graphics.polygon("fill", bagOutline(x, y, s))
  love.graphics.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
  love.graphics.setLineWidth(math.max(1, s / 9))
  love.graphics.polygon("line", bagOutline(x, y, s))
  love.graphics.arc("line", "open", x - s * 0.3, y - s * 0.35, s * 0.3, math.pi, 2 * math.pi)
  love.graphics.arc("line", "open", x + s * 0.3, y - s * 0.35, s * 0.3, math.pi, 2 * math.pi)
  love.graphics.setLineWidth(1)
end

local GREEN_SIGN = { 0.45, 0.95, 0.6 }
local STYLE = {
  rim = { 0.12, 0.2, 0.16 },
  roof = { 0.26, 0.34, 0.29 },
  awning = { GREEN_SIGN, { 0.95, 0.95, 0.9 } },
  glass = { 0.75, 1, 0.85 },
}
local FRUIT = { { 0.95, 0.3, 0.25 }, { 1, 0.75, 0.2 }, { 0.5, 0.85, 0.3 } }

--- Two crates of fruit out front, side by side from (x, y) in the
--- storefront's frame.
local function crates(x, y)
  for i = 0, 1 do
    local cx = x + i * 30
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle("fill", cx - 13 + 3, y - 11 + 3, 26, 22)
    love.graphics.setColor(0.62, 0.45, 0.26)
    love.graphics.rectangle("fill", cx - 13, y - 11, 26, 22)
    love.graphics.setColor(0.45, 0.31, 0.17)
    love.graphics.rectangle("line", cx - 13, y - 11, 26, 22)
    love.graphics.setColor(FRUIT[i + 1])
    for fx = -1, 1 do
      for fy = -1, 0 do
        love.graphics.circle("fill", cx + fx * 7, y + 3 + fy * 8, 3.5)
      end
    end
  end
end

--- A shopping cart seen from above, its handle towards the building, at
--- (x, y) in the storefront's frame.
local function cart(x, y)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", x - 10 + 3, y - 12 + 3, 20, 26, 2)
  love.graphics.setColor(0.78, 0.8, 0.84)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x - 10, y - 10, 20, 24, 2)
  love.graphics.line(x - 10, y - 2, x + 10, y - 2)
  love.graphics.line(x - 10, y + 6, x + 10, y + 6)
  love.graphics.line(x, y - 10, x, y + 14)
  love.graphics.setColor(0.85, 0.2, 0.2)
  love.graphics.line(x - 11, y - 14, x + 11, y - 14)
  love.graphics.setLineWidth(1)
end

--- A neon OPEN sign in the window, level on the screen, flickering now
--- and then like a real one.
local function openSign(shop)
  local x, y = Storefront.at(shop, Storefront.width(shop) / 2 - 40, Storefront.depth(shop) / 2 - 11)
  local flicker = (math.sin(time * 23) > 0.93 or math.sin(time * 0.7) > 0.985) and 0.35 or 1
  local font = UI.fonts.small
  local w, h = font:getWidth("OPEN") + 12, font:getHeight() + 2
  love.graphics.setColor(0.05, 0.05, 0.08, 0.9)
  love.graphics.rectangle("fill", x - w / 2, y - h / 2, w, h, 6)
  love.graphics.setColor(1, 0.3, 0.45, 0.25 * flicker)
  love.graphics.rectangle("fill", x - w / 2 - 3, y - h / 2 - 3, w + 6, h + 6, 8)
  love.graphics.setColor(1, 0.35, 0.5, flicker)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x - w / 2, y - h / 2, w, h, 6)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(font)
  love.graphics.printf("OPEN", x - w / 2, y - h / 2 + 1, w, "center")
end

--- The building over the one it took, a storefront like the Jobs building
--- beside it (quests/storefront.lua): a green bag on the roof, its sign, an
--- OPEN sign in the window, fruit and a cart outside, and the glowing
--- square by the door where the shop opens.
function Shop:drawBelowCars()
  local shop = self:here()
  if not shop then
    return
  end
  local c = GREEN_SIGN
  Storefront.draw(shop, STYLE, time)
  Storefront.front(shop, function(W, D)
    local y = Storefront.outside(D)
    crates(-W / 2 + 14, y)
    cart(W / 2 - 14, y + 2)
  end)
  local ex, ey, r = Storefront.emblem(shop, 34)
  drawBag(ex, ey - r * 0.2, r * 0.85, c)
  love.graphics.setColor(1, 1, 1, 0.85)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.printf("$", ex - 20, ey - 2, 40, "center")
  Storefront.sign(shop, "SHOP", c)
  openSign(shop)
  -- The square by the door.
  local lit = self.near ~= nil
  local pulse = lit and 0.6 + 0.4 * math.abs(math.sin(time * 4)) or 0.5 + 0.5 * math.sin(time * 2.5)
  love.graphics.setColor(c[1], c[2], c[3], 0.10 + 0.08 * pulse)
  love.graphics.circle("fill", shop.doorX, shop.doorY, self.enterRadius)
  love.graphics.setColor(c[1], c[2], c[3], 0.35 + 0.25 * pulse)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", shop.doorX, shop.doorY, self.enterRadius)
  love.graphics.setLineWidth(1)
  drawBag(shop.doorX, shop.doorY - 2, 13, c)
  love.graphics.setColor(1, 1, 1)
end

--- The shop on the minimap: a green bag, so it can be found.
function Shop:drawOnMinimap(_client, toMap)
  local shop = self:here()
  if not shop then
    return
  end
  local x, y = toMap(shop.x + shop.w / 2, shop.y + shop.h / 2)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.polygon("fill", bagOutline(x, y, 7))
  love.graphics.setColor(GREEN_SIGN)
  love.graphics.polygon("fill", bagOutline(x, y, 5.5))
  love.graphics.setColor(1, 1, 1)
end

--- At the door with the screen down: the offer, where the plot and
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
  Screen.draw(self.tab, self.page, purse, mx, my, self.flash, self.notice, self.tier, self.picked)
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
  SHOP_NO = function(_client, args)
    Shop:refuse(args[1])
  end,
}

-- Server --------------------------------------------------------------------

--- Is the player's body (not a wreck) at the door?
local function atDoor(server, player, shop)
  if not Features.present(player) then
    return false
  end
  local x, y = Features.bodyPose(server, player)
  return dist2(x, y, shop.doorX, shop.doorY) <= (Shop.enterRadius + SLACK) ^ 2
end

--- The first delivery bay of `shop` with no car standing in it (the first
--- of all when every one is taken): x, y, angle.
local function freeBay(server, shop)
  for _, bay in ipairs(shop.bays) do
    local bx, by = bay.x, bay.y
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
  return bay.x, bay.y, bay.angle
end

--- Sell `player` what `item` stands for ("gun-uzi@rare": that tier of the
--- uzi). Returns true and how many were handed over, or false and the
--- reason it didn't happen.
function Shop:serverBuy(server, player, item)
  local entry, tier = Catalog.lookup(item)
  local price = entry and Catalog.price(entry, tier)
  if not (entry and player.body) then
    return false, "unknown"
  end
  local shop = self:here()
  if not shop then
    return false, "gone"
  elseif not atDoor(server, player, shop) then
    return false, "away"
  end
  local money = Features.byName.money
  if price > 0 and money and money.wallet and money:wallet(player.id) < price then
    return false, "broke"
  end
  local given
  if Catalog.isCar(entry) then
    local x, y, angle = freeBay(server, shop)
    if not Features.any("serverDeliver", server, player, item, x, y, angle) then
      return false, "nodeliver"
    end
    given = 1
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
  return true, given
end

Shop.serverMessages = {
  SHOP_BUY = function(server, player, args)
    local ok, result = Shop:serverBuy(server, player, args[1])
    if ok then
      server:send(player, Protocol.encode("SHOP_OK", args[1], result))
    else
      server:send(player, Protocol.encode("SHOP_NO", result))
    end
  end,
}

return Shop
