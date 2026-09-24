-- Buildings: put something on the plot you bought, and let it work for you.
--
-- Every plot with an owner has a small square on the sidewalk in front of
-- it. Stand on it (on foot or in a car) and press the buy key (F): on your
-- own plot a menu lists what you can build (kinds.lua) and what it costs;
-- once it is up, the same square opens the building's own menu. Anyone else
-- uses the square to shop at a public building.
--
--   Parking Lot      earns 10 Fcks a minute, up to 100. Drive over it and the
--                    takings are yours. Always private.
--   Quarry Mine      digs iron, sulfur, minerals or copper (you pick), up to 50.
--   Oil Well         pumps oil, or refines it into plastic on the spot, up to 50.
--   Ammo Factory     makes rounds for a gun you pick, up to 200, from iron
--                    and sulfur; rockets (up to 20) take copper as well.
--   Weapons Factory  makes a gun you pick, up to 5, from iron; the rocket
--                    launcher takes copper, oil and plastic as well.
--   Health Factory   makes medkits, up to 5, from minerals. A medkit heals
--                    you when you use it (H).
--
-- Buildings are solid: cars bounce off them, and walkers, pedestrians,
-- officers and bullets stop at their walls (`blocksPoint`). The parking lot
-- is the exception, being somewhere to drive. Anyone on foot inside the
-- footprint when a building goes up is put on its square.
--
-- Factories run on materials: collect what your quarry dug (or buy it from
-- someone else's), then stand on the factory's square and load its hopper
-- from what you carry. A building with its inputs and room for another
-- batch works on its own; the rest wait. What a batch takes depends on the
-- product (kinds.lua, `recipes`); the hopper holds every material any of its
-- products needs, and loading fills it with what the one in hand needs.
--
-- The owner collects what a building made into their inventory. A building
-- set to public also sells to anyone on its square, one unit at a time, at
-- the price its owner sets; the koins go straight to the owner. Private ones
-- still work, for their owner alone.
--
-- A factory can buy its materials too. Its owner sets a price per material
-- on the menu's prices page (0, the start, means it doesn't buy that one);
-- anyone else on its square can then sell what they carry of it straight
-- into the hopper, as much as fits and the owner's wallet covers, and the
-- owner pays for it. Public or private makes no difference to buying.
--
-- The inventory (I) has slots: four to start with, more from the upgrade
-- shop (Buildings:serverSetSlots). A slot holds one stack of one item
-- (kinds.lua has the stack sizes); what doesn't fit stays in the building.
-- It is kept by the host and told to each player alone. Weapons loads its
-- magazines from the ammo in it (serverTake); guns are stock for now.
--
-- Buildings can be shot down. Each kind has its own hit points (kinds.lua,
-- `hp`); every gun hurts the walls it hits (weapons' `serverWallHit`) and a
-- rocket's blast hurts every building it reaches, the parking lot included
-- (`serverBlast`). A damaged building works on and shows a health bar; its
-- owner can repair it from the menu, paying for the damage (Kinds.repairCost).
-- At zero it is a ruin: whatever it held is lost, it stops working, and
-- walls and bullets no longer stop at it. Then the owner pays to rebuild it
-- (half of what it cost), or anyone else on its square can take the lot over
-- for `takeoverPrice`: the plot becomes theirs, empty. A building still
-- standing can't be taken over.
--
-- The plots come from real-estate; without it there is nothing to build on.
-- A building belongs to whoever owns its plot: when the plot goes back on
-- the market (they left) or the map changes, the building is gone.
--
-- Messages
--   client -> server  BLD_BUILD   <plotId> <kind>
--   client -> server  BLD_COLLECT <plotId>
--   client -> server  BLD_LOAD    <plotId>
--   client -> server  BLD_PUBLIC  <plotId>            (toggle)
--   client -> server  BLD_PRODUCT <plotId>            (next product)
--   client -> server  BLD_PRICE   <plotId> <+1|-1>
--   client -> server  BLD_BUY     <plotId>
--   client -> server  BLD_OFFER   <plotId> <item> <+1|-1>  (owner: what it pays for a material)
--   client -> server  BLD_SELL    <plotId> <item>     (sell it all the material it will take)
--   client -> server  BLD_USE     <item>              (only "medkit" today)
--   client -> server  BLD_REPAIR  <plotId>            (owner: mend the damage, or rebuild a ruin)
--   client -> server  BLD_TAKEOVER <plotId>           (anyone else: buy the lot under a ruin)
--   server -> all     BLD_STATE   <plotId> <kind> <owner> <public> <product> <price> <output>
--                                 <progress> <running> <hopper, one per material>...
--                                 <pays, one per material>...   (Kinds.materials order; 0 = not buying)
--                                 <hp>                          (0 = in ruins)
--   server -> all     BLD_HP      <plotId> <hp>       (it was hit and still stands)
--   server -> all     BLD_GONE    <plotId>
--   server -> player  BLD_INV     <item> <count>
--   server -> player  BLD_SLOTS   <slots>
--   server -> player  BLD_NO      <reason>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Car = require("src.car")
local Kinds = require("src.features.buildings.kinds")
local Render = require("src.features.buildings.render")
local Collision = require("src.features.city-map.collision")
local Layout = require("src.features.city-map.layout")

local Buildings = {
  name = "buildings",
  priority = 26, -- draws just over real-estate's plots (25)
}

-- Tuning ------------------------------------------------------------------
Buildings.medkitHeal = 50 -- health a medkit gives back
Buildings.menuKeys = 8 -- menu rows, each on its own key (1..8 by default)
Buildings.padSize = 40 -- px; the square on the sidewalk you use a building from
Buildings.takeoverPrice = 40 -- Fcks for the lot under someone else's ruin

local T = Layout.TILE
local SLACK = 40 -- px the server allows for a player drawn a little behind where it is
local INSET = 28 -- px between the plot's fence and the building
local TOP = 56 -- px left at the top of the plot for real-estate's sign
local PED_RADIUS = 6 -- px; how fat a pedestrian is against a wall, as city-map has it
local NOTICE_TIME = 2.5
local PRICE_MIN, PRICE_MAX = 1, 99
local REASONS = {
  away = "Stand on the square in front of it.",
  notyours = "That isn't your plot.",
  built = "There is already a building here.",
  nobuilding = "There's nothing built here.",
  broke = "You can't afford it.",
  private = "That building is private.",
  own = "It's yours: collect it instead.",
  empty = "Nothing to collect yet.",
  soldout = "Sold out. Come back later.",
  nomaterials = "You aren't carrying anything it runs on.",
  hopperfull = "Its hopper is full.",
  stocked = "Collect what it made before switching.",
  invfull = "Your inventory is full.",
  notbuying = "It doesn't buy that.",
  nothing = "You aren't carrying any of it.",
  ownerbroke = "The owner can't afford to pay you.",
  nomedkit = "You have no medkits.",
  healthy = "You're already at full health.",
  ruined = "It's in ruins. Repair it first.",
  standing = "Only a destroyed building's lot can be taken over.",
  intact = "It isn't damaged.",
  yours = "It's yours: repair it instead.",
}

local function amount(n)
  local money = Features.byName.money
  return money and money.amount(n) or tostring(n)
end

local function realEstate()
  return Features.byName["real-estate"]
end

local function plotById(id)
  local re = realEstate()
  return re and re.plots[id]
end

local function contains(r, x, y, slack)
  slack = slack or 0
  return x >= r.x - slack and x < r.x + r.w + slack and y >= r.y - slack and y < r.y + r.h + slack
end

--- The ground a building covers inside its plot.
local function footprint(plot)
  return { x = plot.x + INSET, y = plot.y + TOP, w = plot.w - 2 * INSET, h = plot.h - TOP - INSET }
end

--- The centre of a plot's square: on the sidewalk below it, halfway along.
local function padOf(plot)
  return plot.x + plot.w / 2, plot.y + plot.h + T / 2
end

local function onPad(plot, x, y, slack)
  local px, py = padOf(plot)
  local r = Buildings.padSize / 2 + (slack or 0)
  return math.abs(x - px) <= r and math.abs(y - py) <= r
end

--- Has building `b` been shot to pieces?
local function ruined(b)
  return b.hp <= 0
end

--- The item a building of `kind` makes when set to product `index`.
local function productOf(kind, index)
  return kind.products and kind.products[index]
end

--- How building `b` of `kind` makes what it is set to (kinds.lua).
local function recipeOf(b, kind)
  return Kinds.recipe(kind, b.product)
end

--- Can building `b` make another batch right now: room for it and every
--- input in the hopper? The parking lot runs until it is full.
local function canRun(b, kind)
  if ruined(b) then
    return false
  elseif kind.rate then
    return b.output < kind.cap
  end
  local r = recipeOf(b, kind)
  if b.output + r.batch > r.cap then
    return false
  end
  for item, n in pairs(r.inputs) do
    if (b.hopper[item] or 0) < n then
      return false
    end
  end
  return true
end

-- Walls ---------------------------------------------------------------------
-- The footprints of every solid building, bucketed the way city-map buckets
-- its own, so its collision code can push cars and pedestrians out of them.
-- Rebuilt whenever a building goes up or comes down. The host reads its own
-- book, a client what it was told; on the host they are the same.

local sv = nil -- { buildings = { plot id -> record }, stock = { player id -> { item -> n } }, slots = { id -> n } }
local walls = { list = {}, cells = {} }
local wallsDirty = true

local function markWalls()
  wallsDirty = true
end

local function currentWalls()
  if not wallsDirty then
    return walls
  end
  wallsDirty = false
  walls = { list = {}, cells = {} }
  local CELL = Layout.CELL
  for id, b in pairs(sv and sv.buildings or Buildings.buildings) do
    local kind = Kinds.byKey[b.kind]
    local plot = plotById(id)
    if kind and not kind.walkable and plot and not ruined(b) then
      local r = footprint(plot)
      walls.list[#walls.list + 1] = r
      for c = math.floor(r.x / CELL), math.floor((r.x + r.w) / CELL) do
        walls.cells[c] = walls.cells[c] or {}
        for row = math.floor(r.y / CELL), math.floor((r.y + r.h) / CELL) do
          walls.cells[c][row] = walls.cells[c][row] or {}
          table.insert(walls.cells[c][row], r)
        end
      end
    end
  end
  return walls
end

--- The `blocksPoint` convention: bullets, walkers, officers and Karen stop here.
function Buildings:blocksPoint(x, y)
  for _, r in ipairs(currentWalls().list) do
    if contains(r, x, y) then
      return true
    end
  end
  return false
end

-- Client --------------------------------------------------------------------

-- plot id -> { kind, owner, public, product, price, output, progress, running, hopper, pays, hp, hitAt }
Buildings.buildings = {}
Buildings.inventory = {} -- item -> count, mine
Buildings.slots = Kinds.SLOTS -- how many inventory slots I have
Buildings.menu = false -- is the building menu open?
Buildings.page = nil -- nil for the menu's main page, "prices" for the owner's prices, "offer" for one material's
Buildings.offerItem = nil -- the material the "offer" page sets a price for
Buildings.bag = false -- is the inventory open?
local herePad, herePlot = nil, nil -- the owned plot whose square I'm on; the plot I'm inside
local notice, noticeTimer, noticeGood = nil, 0, false
local time = 0

function Buildings:load()
  Controls.register("inventory", "Open / close the inventory", "i")
  Controls.register("use-medkit", "Use a medkit", "h")
  for i = 1, self.menuKeys do
    Controls.register("building-" .. i, ("Building menu: option %d"):format(i), tostring(i))
  end
end

-- BLD_STATE for buildings put up before we joined arrives in the same burst
-- as START, so they are only forgotten on the way out.
function Buildings:exitGame()
  self.buildings, self.inventory, self.slots = {}, {}, Kinds.SLOTS
  self.menu, self.bag = false, false
  herePad, herePlot, notice, noticeTimer = nil, nil, nil, 0
  markWalls()
end

local function say(text, good)
  notice, noticeTimer, noticeGood = text, NOTICE_TIME, good or false
end

--- Is another feature's menu up (the upgrade shop)? Then ours stays shut.
local function otherMenuOpen()
  local shop = Features.byName.upgrades
  return shop and shop.open
end

--- For weapons and anything else on the number keys: ours are taken while
--- the menu is open (docs/features.md, `menuOpen`).
function Buildings:menuOpen()
  return self.menu
end

function Buildings:update(dt, client)
  time = time + dt
  noticeTimer = math.max(0, noticeTimer - dt)
  local x, y = client:myPose()
  herePad, herePlot = nil, nil
  local re = realEstate()
  if x and re then
    for _, plot in ipairs(re.plots) do
      if re.owners[plot.id] and onPad(plot, x, y) then
        herePad = plot
      elseif contains(plot, x, y) then
        herePlot = plot
      end
    end
  end
  if not herePad or otherMenuOpen() then
    self.menu = false
  end
  if not self.menu then
    self.page = nil
  end
  -- Batches creep along between the host's reports.
  for _, b in pairs(self.buildings) do
    local kind = Kinds.byKey[b.kind]
    if b.running and kind.time then
      b.progress = math.min(1, b.progress + dt / recipeOf(b, kind).time)
    end
  end
end

local function affordable(client, price)
  local money = Features.byName.money
  if money and money.canAfford and not money:canAfford(client, price) then
    say(REASONS.broke)
    return false
  end
  return true
end

local function send(client, kind, ...)
  client:send(Protocol.encode(kind, ...))
end

--- The rows of the menu for the square I am on: { label, run = function } or
--- { label } for a line that can't be picked right now.
function Buildings:menuRows(client)
  local plot = herePad
  local re = realEstate()
  if not (plot and re) then
    return {}
  end
  local owner = re.owners[plot.id]
  local b = self.buildings[plot.id]
  local rows = {}
  local function row(label, run)
    rows[#rows + 1] = { label = label, run = run }
  end

  if owner == client.myId and not b then
    for _, kind in ipairs(Kinds.list) do
      row(("Build %s  (%s)"):format(kind.name, amount(kind.cost)), function()
        if affordable(client, kind.cost) then
          send(client, "BLD_BUILD", plot.id, kind.key)
        end
      end)
    end
    return rows
  end
  if not b then
    return rows
  end
  local kind = Kinds.byKey[b.kind]

  if ruined(b) then
    if owner == client.myId then
      local cost = Kinds.repairCost(kind, b.hp)
      row(("Rebuild it  (%s)"):format(amount(cost)), function()
        if affordable(client, cost) then
          send(client, "BLD_REPAIR", plot.id)
        end
      end)
    else
      row(("Hostile takeover: buy the lot  (%s)"):format(amount(self.takeoverPrice)), function()
        if affordable(client, self.takeoverPrice) then
          send(client, "BLD_TAKEOVER", plot.id)
        end
      end)
    end
    return rows
  end

  if owner == client.myId then
    local cost = Kinds.repairCost(kind, b.hp)
    if cost > 0 and self.page == nil then
      row(("Repair the damage  (%s)"):format(amount(cost)), function()
        if affordable(client, cost) then
          send(client, "BLD_REPAIR", plot.id)
        end
      end)
    end
    if kind.rate then
      return rows -- the parking lot pays out when you drive over it
    elseif self.page == "prices" then
      return self:priceRows(client, plot, b, kind)
    elseif self.page == "offer" then
      return self:offerRows(client, plot, b)
    end
    local item = productOf(kind, b.product)
    row(("Collect %s"):format(Kinds.label(item, b.output)), b.output > 0 and function()
      send(client, "BLD_COLLECT", plot.id)
    end or nil)
    if next(kind.hopper) then
      row("Load materials from your inventory", function()
        send(client, "BLD_LOAD", plot.id)
      end)
    end
    if #kind.products > 1 then
      local nextItem = productOf(kind, b.product % #kind.products + 1)
      row(("Switch to making %s"):format(Kinds.label(nextItem)), function()
        send(client, "BLD_PRODUCT", plot.id)
      end)
    end
    row(b.public and "Make it private" or "Open it to the public", function()
      send(client, "BLD_PUBLIC", plot.id)
    end)
    row("Prices...", function()
      self.page = "prices"
    end)
    return rows
  end

  if b.public then
    local item = productOf(kind, b.product)
    local unit = recipeOf(b, kind).unit
    local n = math.min(unit, b.output)
    row(("Buy %s  (%s)"):format(Kinds.label(item, unit), amount(b.price)), n > 0 and function()
      if Kinds.room(self.inventory, self.slots, item) < n then
        say(REASONS.invfull)
      elseif affordable(client, b.price) then
        send(client, "BLD_BUY", plot.id)
      end
    end or nil)
  end
  for _, item in ipairs(Kinds.hopperList(kind)) do
    local pays = b.pays[item] or 0
    if pays > 0 then
      local have = self.inventory[item] or 0
      local room = Kinds.HOPPER - (b.hopper[item] or 0)
      local label = ("Sell your %s  (%s each, takes %d)"):format(item, amount(pays), room)
      row(label, have > 0 and room > 0 and function()
        send(client, "BLD_SELL", plot.id, item)
      end or nil)
    end
  end
  return rows
end

--- The owner's prices page: what the building sells for, and a row per
--- material it runs on that opens that material's own page (a factory can
--- take four, too many to fit two rows each on the number keys).
function Buildings:priceRows(client, plot, b, kind)
  local rows = {}
  local function row(label, run)
    rows[#rows + 1] = { label = label, run = run }
  end
  row(("Selling price -1  (now %s)"):format(amount(b.price)), function()
    send(client, "BLD_PRICE", plot.id, -1)
  end)
  row("Selling price +1", function()
    send(client, "BLD_PRICE", plot.id, 1)
  end)
  for _, item in ipairs(Kinds.hopperList(kind)) do
    local pays = b.pays[item] or 0
    row(("Pay for %s...  (now %s)"):format(item, pays > 0 and amount(pays) or "not buying"), function()
      self.page, self.offerItem = "offer", item
    end)
  end
  row("Back", function()
    self.page = nil
  end)
  return rows
end

--- What the building pays for one material, up or down.
function Buildings:offerRows(client, plot, b)
  local item = self.offerItem
  local pays = b.pays[item] or 0
  return {
    { label = ("Pay for %s -1  (now %s)"):format(item, pays > 0 and amount(pays) or "not buying"), run = function()
      send(client, "BLD_OFFER", plot.id, item, -1)
    end },
    { label = ("Pay for %s +1"):format(item), run = function()
      send(client, "BLD_OFFER", plot.id, item, 1)
    end },
    { label = "Back", run = function()
      self.page = "prices"
    end },
  }
end

function Buildings:keypressed(key, client)
  if Controls.is("inventory", key) then
    self.bag = not self.bag
    return
  end
  if Controls.is("use-medkit", key) and not self.menu then
    if (self.inventory.medkit or 0) < 1 then
      say(REASONS.nomedkit)
    else
      send(client, "BLD_USE", "medkit")
    end
    return
  end
  if Controls.is("buy", key) then
    -- On a plot that is for sale real-estate sells it; the square in front
    -- of one that has an owner is ours.
    if herePad and not otherMenuOpen() then
      self.menu = not self.menu
      self.page = nil
    end
    return
  end
  if not self.menu then
    return
  end
  local rows = self:menuRows(client)
  for i = 1, self.menuKeys do
    if Controls.is("building-" .. i, key) then
      local r = rows[i]
      if r and r.run then
        r.run()
      end
      return
    end
  end
end

local function ownerName(client, id)
  local p = client.players[id]
  return p and p.name or "?"
end

--- The square on the sidewalk: the owner's colour, the building's initial
--- (a plus on an empty plot, red over a ruin), a green corner while it
--- sells to the public.
local function drawPad(plot, owner, b, lit)
  local s = Buildings.padSize
  local px, py = padOf(plot)
  local c = Car.colorFor(owner)
  local pulse = lit and 0.6 + 0.4 * math.abs(math.sin(time * 4)) or 0.85
  love.graphics.setColor(0.12, 0.12, 0.14, pulse)
  love.graphics.rectangle("fill", px - s / 2, py - s / 2, s, s, 4)
  love.graphics.setColor(c[1], c[2], c[3], pulse)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", px - s / 2, py - s / 2, s, s, 4)
  local kind = b and Kinds.byKey[b.kind]
  if b and ruined(b) then
    love.graphics.setColor(1, 0.35, 0.3, pulse)
  else
    love.graphics.setColor(1, 1, 1, pulse)
  end
  love.graphics.setFont(UI.fonts.body)
  local mark = kind and kind.name:sub(1, 1) or "+"
  love.graphics.printf(mark, px - s / 2, py - UI.fonts.body:getHeight() / 2, s, "center")
  if b and b.public and not ruined(b) then
    love.graphics.setColor(0.3, 1, 0.4, pulse)
    love.graphics.circle("fill", px + s / 2 - 5, py - s / 2 + 5, 4)
  end
  love.graphics.setLineWidth(1)
end

function Buildings:drawBelowCars()
  for id, b in pairs(self.buildings) do
    local plot = plotById(id)
    local kind = Kinds.byKey[b.kind]
    if plot and kind then
      local r = footprint(plot)
      if ruined(b) then
        Render.ruin(kind, r, id, time)
      else
        Render.building(b, kind, r, time)
        Render.damage(r, b.hp / kind.hp, time - (b.hitAt or -1))
      end
    end
  end
  local re = realEstate()
  if re then
    for _, plot in ipairs(re.plots) do
      local owner = re.owners[plot.id]
      if owner then
        drawPad(plot, owner, self.buildings[plot.id], herePad == plot)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- What a building is doing, in a few words.
local function status(b, kind)
  if kind.rate then
    return b.output >= kind.cap and "Full: drive over it to collect" or "Earning"
  end
  if b.running then
    return "Making " .. Kinds.label(productOf(kind, b.product))
  end
  local r = recipeOf(b, kind)
  if b.output + r.batch > r.cap then
    return "Full"
  end
  local needs = {}
  for _, input in ipairs(Kinds.inputList(r)) do
    needs[#needs + 1] = Kinds.label(input.item, input.n)
  end
  return "Idle: needs " .. table.concat(needs, " + ") .. " per batch"
end

--- The lines at the top of the menu that describe the building.
local function infoLines(client, b, kind)
  if ruined(b) then
    if b.owner == client.myId then
      return { "Destroyed. Nothing works until you rebuild it.", "Until then anyone can take the lot over." }
    end
    return { "Destroyed. Take the lot over, and it's yours to build on." }
  end
  local lines = {}
  local item = productOf(kind, b.product)
  local r = recipeOf(b, kind)
  if kind.rate then
    lines[#lines + 1] = ("Takings: %s of %s"):format(amount(math.floor(b.output)), amount(kind.cap))
  else
    lines[#lines + 1] = ("Stock: %s (most %d)"):format(Kinds.label(item, b.output), r.cap)
  end
  lines[#lines + 1] = status(b, kind)
  lines[#lines + 1] = ("Condition: %d/%d"):format(b.hp, kind.hp)
  if b.owner == client.myId and next(kind.hopper) then
    local hop = {}
    for _, m in ipairs(Kinds.hopperList(kind)) do
      hop[#hop + 1] = ("%s %d/%d"):format(m, b.hopper[m] or 0, Kinds.HOPPER)
    end
    lines[#lines + 1] = "Hopper: " .. table.concat(hop, ", ")
  end
  if not kind.private then
    local per = r.unit == 1 and Kinds.label(item, 1):gsub("^1 ", "") or Kinds.label(item, r.unit)
    lines[#lines + 1] = ("%s, %s per %s"):format(b.public and "Public" or "Private", amount(b.price), per)
  end
  local pays = {}
  for _, m in ipairs(Kinds.hopperList(kind)) do
    if (b.pays[m] or 0) > 0 then
      pays[#pays + 1] = ("%s %s"):format(m, amount(b.pays[m]))
    end
  end
  if #pays > 0 then
    lines[#lines + 1] = "Buys: " .. table.concat(pays, ", ")
  end
  return lines
end

--- Does building `b` pay for any material?
local function buysAnything(b)
  for _, price in pairs(b.pays) do
    if price > 0 then
      return true
    end
  end
  return false
end

--- A dark panel with a gold rim and a title.
local function panel(x, y, w, h, title)
  love.graphics.setColor(0.10, 0.10, 0.13, 0.94)
  love.graphics.rectangle("fill", x, y, w, h, 10)
  love.graphics.setColor(1, 0.85, 0.3, 0.8)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, 10)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(title, x, y + 12, w, "center")
end

--- The panel in the top-right corner (under the connection line) while the menu is open.
local function drawMenu(self, client)
  local re = realEstate()
  local plot = herePad
  local b = self.buildings[plot.id]
  local kind = b and Kinds.byKey[b.kind]
  local owner = re.owners[plot.id]
  local title, lines
  if kind then
    title = kind.name
    lines = infoLines(client, b, kind)
    if owner ~= client.myId then
      table.insert(lines, 1, ownerName(client, owner) .. "'s")
    end
  else
    title = owner == client.myId and "Build on your plot" or (ownerName(client, owner) .. "'s plot")
    lines = { owner == client.myId and "Pick a building." or "Nothing built here yet." }
  end
  local rows = self:menuRows(client)
  if kind and #rows == 0 then
    lines[#lines + 1] = owner == client.myId and "Drive over it to collect." or "Nothing to trade here."
  end

  local w = love.graphics.getWidth()
  local pw = 380
  -- A long line (a factory that runs on four materials) wraps onto more.
  local font = UI.fonts.small
  local wrapped = 0
  for _, line in ipairs(lines) do
    local _, parts = font:getWrap(line, pw - 40)
    wrapped = wrapped + math.max(1, #parts)
  end
  local ph = 64 + wrapped * 20 + #rows * 30 + 40
  local px, py = w - pw - 16, 36
  panel(px, py, pw, ph, title)

  love.graphics.setFont(font)
  local y = py + 54
  love.graphics.setColor(0.8, 0.8, 0.85)
  for _, line in ipairs(lines) do
    local _, parts = font:getWrap(line, pw - 40)
    for _, part in ipairs(parts) do
      love.graphics.print(part, px + 20, y)
      y = y + 20
    end
  end
  y = y + 6
  for i, r in ipairs(rows) do
    local keyName = Controls.name(Controls.bindings("building-" .. i)[1])
    local dim = r.run and 1 or 0.4
    love.graphics.setColor(0.36 * dim + 0.2, 0.56 * dim + 0.2, 0.92 * dim, 1)
    love.graphics.rectangle("fill", px + 20, y, 24, 24, 5)
    love.graphics.setColor(1, 1, 1, dim)
    love.graphics.printf(keyName, px + 20, y + 4, 24, "center")
    love.graphics.print(r.label, px + 54, y + 4)
    y = y + 30
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  local key = Controls.name(Controls.bindings("buy")[1])
  love.graphics.printf(key .. ": close", px, py + ph - 26, pw, "center")
end

--- My inventory as the stacks that fill its slots, materials first.
local function stacks(inventory)
  local items = {}
  for _, m in ipairs(Kinds.materials) do
    items[#items + 1] = m
  end
  local others = {}
  for item in pairs(inventory) do
    if not Kinds.isMaterial(item) then
      others[#others + 1] = item
    end
  end
  table.sort(others)
  for _, item in ipairs(others) do
    items[#items + 1] = item
  end
  local out = {}
  for _, item in ipairs(items) do
    local left, stack = inventory[item] or 0, Kinds.stack(item)
    while left > 0 do
      out[#out + 1] = { item = item, n = math.min(stack, left) }
      left = left - stack
    end
  end
  return out
end

local COLS, CELL, GAP = 5, 76, 8

--- The inventory panel on the left: a slot per box, locked ones greyed out.
local function drawBag(self)
  local rows = math.ceil(Kinds.MAX_SLOTS / COLS)
  local pw = 2 * 24 + COLS * CELL + (COLS - 1) * GAP
  local ph = 64 + rows * (CELL + GAP) + 62
  local px, py = 16, 250
  panel(px, py, pw, ph, "INVENTORY")
  local list = stacks(self.inventory)
  for i = 1, Kinds.MAX_SLOTS do
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    local x, y = px + 24 + col * (CELL + GAP), py + 56 + row * (CELL + GAP)
    local open = i <= self.slots
    love.graphics.setColor(1, 1, 1, open and 0.10 or 0.03)
    love.graphics.rectangle("fill", x, y, CELL, CELL, 6)
    love.graphics.setColor(1, 1, 1, open and 0.35 or 0.12)
    love.graphics.rectangle("line", x, y, CELL, CELL, 6)
    local s = open and list[i]
    if s then
      Render.itemIcon(s.item, x + CELL / 2, y + 22)
      love.graphics.setFont(UI.fonts.small)
      love.graphics.setColor(0.85, 0.85, 0.9)
      love.graphics.printf(Kinds.label(s.item), x + 2, y + 38, CELL - 4, "center")
      love.graphics.setColor(1, 0.85, 0.3)
      love.graphics.printf(tostring(s.n), x, y + 2, CELL - 5, "right")
    elseif not open then
      love.graphics.setColor(1, 1, 1, 0.2)
      love.graphics.setFont(UI.fonts.small)
      love.graphics.printf("locked", x, y + CELL / 2 - 8, CELL, "center")
    end
  end
  -- Names of what I carry under the boxes, since icons only say so much.
  love.graphics.setFont(UI.fonts.small)
  local y = py + 56 + rows * (CELL + GAP) + 4
  local hint
  if self.slots < Kinds.MAX_SLOTS then
    local shop = Controls.name(Controls.bindings("upgrades")[1])
    hint = ("%d/%d slots used. More slots in the upgrade shop (%s)."):format(
      math.min(#list, self.slots), self.slots, shop)
  else
    hint = ("%d/%d slots used."):format(math.min(#list, self.slots), self.slots)
  end
  love.graphics.setColor(0.8, 0.8, 0.85)
  love.graphics.printf(hint, px + 20, y, pw - 40, "left")
  local foot = Controls.name(Controls.bindings("inventory")[1]) .. ": close"
  if (self.inventory.medkit or 0) > 0 then
    foot = Controls.name(Controls.bindings("use-medkit")[1]) .. ": use a medkit   " .. foot
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.printf(foot, px, py + ph - 26, pw, "center")
end

--- A reminder of the inventory key, bottom left, while it is shut.
local function drawBagHint(self)
  local used = Kinds.slotsUsed(self.inventory)
  local line = ("%s: inventory (%d/%d)"):format(Controls.name(Controls.bindings("inventory")[1]), used, self.slots)
  if (self.inventory.medkit or 0) > 0 then
    line = line .. "   " .. Controls.name(Controls.bindings("use-medkit")[1]) .. ": use medkit"
  end
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.85, 0.8, 0.6)
  love.graphics.print(line, 10, love.graphics.getHeight() - 28)
end

function Buildings:drawHUD(client)
  local w, h = love.graphics.getDimensions()
  if self.bag then
    drawBag(self)
  else
    drawBagHint(self)
  end
  local re = realEstate()
  local plot = herePad
  local owner = plot and re and re.owners[plot.id]
  if self.menu and owner then
    drawMenu(self, client)
  end

  local text, color
  local key = Controls.name(Controls.bindings("buy")[1])
  if noticeTimer > 0 then
    text, color = notice, noticeGood and { 0.5, 1, 0.6 } or { 1, 0.45, 0.4 }
  elseif owner and not self.menu then
    local b = self.buildings[plot.id]
    local kind = b and Kinds.byKey[b.kind]
    if kind and ruined(b) then
      if owner == client.myId then
        text = ("Your %s lies in ruins.  %s: rebuild"):format(kind.name, key)
      else
        text = ("%s's %s lies in ruins.  %s: take over the lot"):format(ownerName(client, owner), kind.name, key)
      end
      color = { 1, 0.55, 0.35 }
    elseif owner == client.myId then
      text = kind and ("Your %s.  %s: manage"):format(kind.name, key) or ("Your plot.  %s: build"):format(key)
      color = { 0.6, 0.9, 0.6 }
    elseif kind and (b.public or buysAnything(b)) then
      local deals = {}
      if b.public then
        deals[#deals + 1] = "sells " .. Kinds.label(productOf(kind, b.product))
      end
      if buysAnything(b) then
        deals[#deals + 1] = "buys materials"
      end
      text = ("%s's %s %s.  %s: trade"):format(ownerName(client, owner), kind.name, table.concat(deals, " and "), key)
      color = { 1, 0.85, 0.3 }
    else
      text = ownerName(client, owner) .. "'s " .. (kind and (kind.name .. " (private)") or "plot")
      color = { 0.8, 0.8, 0.85 }
    end
  elseif herePlot and re and re.owners[herePlot.id] == client.myId and not self.buildings[herePlot.id] then
    text, color = "Your plot. Build from the square on the sidewalk.", { 0.6, 0.9, 0.6 }
  end
  if text then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf(text, 1, h - 129, w, "center")
    love.graphics.setColor(color)
    love.graphics.printf(text, 0, h - 130, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

--- "+10 uzi ammo" over my head, through money's floating text when it is there.
local function announceGain(client, item, gained)
  local money = Features.byName.money
  local text = "+" .. Kinds.label(item, gained)
  if money and money.float then
    money:float(client, client.myId, text)
  else
    say(text, true)
  end
end

--- Building `b` of `kind` on plot `id` just came down: it blows up where
--- everyone can see it, and its owner hears about it wherever they are.
local function collapsed(client, id, b, kind)
  local plot = plotById(id)
  local weapons = Features.byName.weapons
  if plot and weapons and weapons.explosionAt then
    local r = footprint(plot)
    weapons:explosionAt(client, r.x + r.w / 2, r.y + r.h / 2, Render.rubbleColor(kind))
  end
  if b.owner == client.myId then
    say(("Your %s was destroyed!"):format(kind.name))
  end
end

Buildings.clientMessages = {
  BLD_STATE = function(client, args)
    local id, kind = tonumber(args[1]), Kinds.byKey[args[2]]
    if not (id and kind) then
      return
    end
    local hopper, pays, n = {}, {}, #Kinds.materials
    for i, m in ipairs(Kinds.materials) do
      hopper[m] = tonumber(args[9 + i]) or 0
      pays[m] = tonumber(args[9 + n + i]) or 0
    end
    local hp = tonumber(args[10 + 2 * n]) or kind.hp
    local before = Buildings.buildings[id]
    if not before or (before.hp <= 0) ~= (hp <= 0) then
      markWalls()
    end
    Buildings.buildings[id] = {
      kind = kind.key,
      owner = tonumber(args[3]),
      public = args[4] == "1",
      product = tonumber(args[5]) or 1,
      price = tonumber(args[6]) or 0,
      output = tonumber(args[7]) or 0,
      progress = tonumber(args[8]) or 0,
      running = args[9] == "1",
      hopper = hopper,
      pays = pays,
      hp = hp,
    }
    if before and before.hp > 0 and hp <= 0 then
      collapsed(client, id, Buildings.buildings[id], kind)
    end
  end,
  BLD_HP = function(_client, args)
    local b = Buildings.buildings[tonumber(args[1])]
    local hp = tonumber(args[2])
    if b and hp then
      b.hp, b.hitAt = hp, time
    end
  end,
  BLD_GONE = function(_client, args)
    local id = tonumber(args[1])
    if id then
      Buildings.buildings[id] = nil
      markWalls()
    end
  end,
  BLD_INV = function(client, args)
    local item, n = args[1], tonumber(args[2])
    if not (item and n) then
      return
    end
    local before = Buildings.inventory[item] or 0
    Buildings.inventory[item] = n > 0 and n or nil
    if n > before then
      announceGain(client, item, n - before)
    end
  end,
  BLD_SLOTS = function(_client, args)
    Buildings.slots = tonumber(args[1]) or Buildings.slots
  end,
  BLD_NO = function(_client, args)
    if REASONS[args[1]] then
      say(REASONS[args[1]])
    end
  end,
}

-- Server ----------------------------------------------------------------

function Buildings:serverStart()
  sv = { buildings = {}, stock = {}, slots = {} }
  markWalls()
end

--- The map was swapped (a quest). Its plots start empty, so every building
--- is gone; what players carry stays with them.
function Buildings:mapChanged()
  self.buildings = {}
  self.menu = false
  herePad, herePlot = nil, nil
  if sv then
    sv.buildings = {}
  end
  markWalls()
end

local function stateMessage(id, b)
  local kind = Kinds.byKey[b.kind]
  local fields = {
    id, b.kind, b.owner, b.public and 1 or 0, b.product, b.price, math.floor(b.output),
    ("%.2f"):format(b.progress / (recipeOf(b, kind).time or 1)), b.running and 1 or 0,
  }
  for _, m in ipairs(Kinds.materials) do
    fields[#fields + 1] = b.hopper[m] or 0
  end
  for _, m in ipairs(Kinds.materials) do
    fields[#fields + 1] = b.pays[m] or 0
  end
  fields[#fields + 1] = b.hp
  return Protocol.encode("BLD_STATE", unpack(fields))
end

--- Work out whether it can run and tell everyone how the building stands.
local function publish(server, id, b)
  b.running = canRun(b, Kinds.byKey[b.kind])
  server:broadcast(stateMessage(id, b))
end

local function removeBuilding(server, id)
  sv.buildings[id] = nil
  markWalls()
  server:broadcast(Protocol.encode("BLD_GONE", id))
end

local function stockOf(id)
  local s = sv.stock[id]
  if not s then
    s = {}
    sv.stock[id] = s
  end
  return s
end

local function slotsOf(id)
  return sv.slots[id] or Kinds.SLOTS
end

--- How many more of `item` player `id` can carry.
local function roomFor(id, item)
  return Kinds.room(stockOf(id), slotsOf(id), item)
end

--- Change what player `player` carries of `item` by `delta` and tell them.
--- Callers check `roomFor` before adding.
local function addStock(server, player, item, delta)
  local s = stockOf(player.id)
  local n = math.max(0, (s[item] or 0) + delta)
  s[item] = n > 0 and n or nil
  server:send(player, Protocol.encode("BLD_INV", item, n))
end

--- How many of `item` player `id` carries, on the host.
function Buildings:serverCount(id, item)
  return sv and sv.stock[id] and sv.stock[id][item] or 0
end

--- Take up to `n` of `item` out of `player`'s inventory and tell them.
--- Returns how many were taken. Weapons loads its magazines this way.
function Buildings:serverTake(server, player, item, n)
  if not sv then
    return 0
  end
  local taken = math.min(n, self:serverCount(player.id, item))
  if taken > 0 then
    addStock(server, player, item, -taken)
  end
  return taken
end

--- Put up to `n` of `item` into `player`'s inventory, as many as fit, and
--- tell them. Returns how many went in (0 when they are full or there is
--- no game). Pickups hands out dropped ammo this way.
function Buildings:serverGive(server, player, item, n)
  if not (sv and player.body) then
    return 0
  end
  local given = math.min(n, roomFor(player.id, item))
  if given > 0 then
    addStock(server, player, item, given)
  end
  return given
end

--- Give `player` `slots` inventory slots for the rest of the game (the
--- upgrade shop does). Returns the number they have now.
function Buildings:serverSetSlots(server, player, slots)
  if not sv then
    return nil
  end
  slots = math.max(1, math.min(Kinds.MAX_SLOTS, math.floor(slots)))
  sv.slots[player.id] = slots
  server:send(player, Protocol.encode("BLD_SLOTS", slots))
  return slots
end

function Buildings:serverPlayerJoined(server, player)
  if not sv then
    return
  end
  for id, b in pairs(sv.buildings) do
    server:send(player, stateMessage(id, b))
  end
end

function Buildings:serverPlayerLeft(server, player)
  if not sv then
    return
  end
  sv.stock[player.id], sv.slots[player.id] = nil, nil
  for id, b in pairs(sv.buildings) do
    if b.owner == player.id then
      removeBuilding(server, id)
    end
  end
end

--- Is the player's body on the square in front of `plot` (a little slack
--- for lag)?
local function standsOnPad(server, player, plot)
  if not Features.present(player) then
    return false
  end
  local x, y = Features.bodyPose(server, player)
  return onPad(plot, x, y, SLACK)
end

--- The plot a message names, if the player is on its square; otherwise nil
--- and the reason to send back.
local function plotFor(server, player, args)
  local re = realEstate()
  local plot = re and re.plots[tonumber(args[1]) or 0]
  if not (sv and plot and player.body) then
    return nil
  end
  if not standsOnPad(server, player, plot) then
    return nil, "away"
  end
  return plot
end

--- The building on a plot the player owns, or nil and a reason. A ruin
--- counts only when `ruins` is set (repairing it); nothing else works there.
local function ownBuilding(server, player, args, ruins)
  local plot, reason = plotFor(server, player, args)
  if not plot then
    return nil, reason
  end
  local b = sv.buildings[plot.id]
  if not b then
    return nil, "nobuilding"
  end
  if b.owner ~= player.id then
    return nil, "notyours"
  end
  if ruined(b) and not ruins then
    return nil, "ruined"
  end
  return b, nil, plot.id
end

--- Anyone on foot standing where a new building went up is put on its
--- square; walking can't step out of a wall. Cars are pushed out by the
--- collision in serverStep.
local function clearFootprint(server, plot)
  local r = footprint(plot)
  local px, py = padOf(plot)
  for _, p in pairs(server.players) do
    local body = p.body
    if body and not p.vehicle and contains(r, body.x, body.y, T / 4) then
      body.x, body.y = px, py
    end
  end
end

--- Run `handler(server, player, args)` and send back whatever reason it
--- refuses with.
local function refusing(handler)
  return function(server, player, args)
    local reason = handler(server, player, args)
    if reason then
      server:send(player, Protocol.encode("BLD_NO", reason))
    end
  end
end

Buildings.serverMessages = {
  BLD_BUILD = refusing(function(server, player, args)
    local plot, reason = plotFor(server, player, args)
    local kind = Kinds.byKey[args[2]]
    if not (plot and kind) then
      return reason
    end
    if realEstate():owner(plot.id) ~= player.id then
      return "notyours"
    elseif sv.buildings[plot.id] then
      return "built"
    end
    local money = Features.byName.money
    if money and not money:spend(server, player.id, kind.cost, kind.name:lower()) then
      return "broke"
    end
    local b = {
      kind = kind.key,
      owner = player.id,
      public = false,
      product = 1,
      price = Kinds.recipe(kind, 1).price or 0,
      pays = {}, -- material -> Fcks it pays for one; absent = not buying
      output = 0,
      progress = 0,
      hopper = {},
      hp = kind.hp,
    }
    sv.buildings[plot.id] = b
    markWalls()
    if not kind.walkable then
      clearFootprint(server, plot)
    end
    publish(server, plot.id, b)
  end),

  BLD_COLLECT = refusing(function(server, player, args)
    local b, reason, id = ownBuilding(server, player, args)
    if not b then
      return reason
    end
    local kind = Kinds.byKey[b.kind]
    if kind.rate then
      return -- the parking lot pays out on its own
    elseif b.output < 1 then
      return "empty"
    end
    local item = productOf(kind, b.product)
    local n = math.min(b.output, roomFor(player.id, item))
    if n < 1 then
      return "invfull"
    end
    addStock(server, player, item, n)
    b.output = b.output - n
    publish(server, id, b)
    if b.output > 0 then
      return "invfull" -- took what fit; the rest waits in the building
    end
  end),

  BLD_LOAD = refusing(function(server, player, args)
    local b, reason, id = ownBuilding(server, player, args)
    if not b then
      return reason
    end
    local kind = Kinds.byKey[b.kind]
    local inputs = recipeOf(b, kind).inputs
    if not next(inputs) then
      return
    end
    local s = stockOf(player.id)
    local moved, room = false, false
    for item in pairs(inputs) do
      local space = Kinds.HOPPER - (b.hopper[item] or 0)
      local n = math.min(space, s[item] or 0)
      room = room or space > 0
      if n > 0 then
        b.hopper[item] = (b.hopper[item] or 0) + n
        addStock(server, player, item, -n)
        moved = true
      end
    end
    if not moved then
      return room and "nomaterials" or "hopperfull"
    end
    publish(server, id, b)
  end),

  BLD_PUBLIC = refusing(function(server, player, args)
    local b, reason, id = ownBuilding(server, player, args)
    if not b then
      return reason
    end
    if not Kinds.byKey[b.kind].private then
      b.public = not b.public
      publish(server, id, b)
    end
  end),

  BLD_PRODUCT = refusing(function(server, player, args)
    local b, reason, id = ownBuilding(server, player, args)
    if not b then
      return reason
    end
    local kind = Kinds.byKey[b.kind]
    if not (kind.products and #kind.products > 1) then
      return
    elseif b.output > 0 then
      return "stocked"
    end
    local before = recipeOf(b, kind).price
    b.product = b.product % #kind.products + 1
    b.progress = 0
    -- A product with a price of its own (rockets next to rounds) starts
    -- there; between two alike, the owner's price stays.
    local after = recipeOf(b, kind).price
    if after ~= before then
      b.price = after
    end
    publish(server, id, b)
  end),

  BLD_PRICE = refusing(function(server, player, args)
    local b, reason, id = ownBuilding(server, player, args)
    local delta = tonumber(args[2])
    if not b then
      return reason
    end
    if not (delta == 1 or delta == -1) or Kinds.byKey[b.kind].private then
      return
    end
    b.price = math.max(PRICE_MIN, math.min(PRICE_MAX, b.price + delta))
    publish(server, id, b)
  end),

  BLD_OFFER = refusing(function(server, player, args)
    local b, reason, id = ownBuilding(server, player, args)
    local item, delta = args[2], tonumber(args[3])
    if not b then
      return reason
    end
    local kind = Kinds.byKey[b.kind]
    if not (kind.hopper and kind.hopper[item] and (delta == 1 or delta == -1)) then
      return
    end
    b.pays[item] = math.max(0, math.min(PRICE_MAX, (b.pays[item] or 0) + delta))
    publish(server, id, b)
  end),

  BLD_SELL = refusing(function(server, player, args)
    local plot, reason = plotFor(server, player, args)
    if not plot then
      return reason
    end
    local b = sv.buildings[plot.id]
    local item = args[2]
    local pays = b and b.pays[item] or 0
    if not b then
      return "nobuilding"
    elseif ruined(b) then
      return "ruined"
    elseif b.owner == player.id then
      return "own"
    elseif pays < 1 then
      return "notbuying"
    end
    local have = stockOf(player.id)[item] or 0
    local n = math.min(have, Kinds.HOPPER - (b.hopper[item] or 0))
    local money = Features.byName.money
    if money then
      n = math.min(n, math.floor(money:wallet(b.owner) / pays))
    end
    if have < 1 then
      return "nothing"
    elseif Kinds.HOPPER - (b.hopper[item] or 0) < 1 then
      return "hopperfull"
    elseif n < 1 then
      return "ownerbroke"
    end
    if money then
      if not money:spend(server, b.owner, n * pays, "bought " .. Kinds.label(item, n)) then
        return "ownerbroke"
      end
      money:give(server, player.id, n * pays)
    end
    addStock(server, player, item, -n)
    b.hopper[item] = (b.hopper[item] or 0) + n
    publish(server, plot.id, b)
  end),

  BLD_BUY = refusing(function(server, player, args)
    local plot, reason = plotFor(server, player, args)
    if not plot then
      return reason
    end
    local b = sv.buildings[plot.id]
    local kind = b and Kinds.byKey[b.kind]
    if not b then
      return "nobuilding"
    elseif ruined(b) then
      return "ruined"
    elseif b.owner == player.id then
      return "own"
    elseif kind.private or not b.public then
      return "private"
    end
    local n = math.min(recipeOf(b, kind).unit, b.output)
    if n < 1 then
      return "soldout"
    end
    local item = productOf(kind, b.product)
    if roomFor(player.id, item) < n then
      return "invfull"
    end
    local money = Features.byName.money
    if money then
      if not money:spend(server, player.id, b.price, Kinds.label(item)) then
        return "broke"
      end
      money:give(server, b.owner, b.price)
    end
    b.output = b.output - n
    addStock(server, player, item, n)
    publish(server, plot.id, b)
  end),

  BLD_REPAIR = refusing(function(server, player, args)
    local b, reason, id = ownBuilding(server, player, args, true)
    if not b then
      return reason
    end
    local kind = Kinds.byKey[b.kind]
    local cost = Kinds.repairCost(kind, b.hp)
    if cost == 0 then
      return "intact"
    end
    local money = Features.byName.money
    if money and not money:spend(server, player.id, cost, "repairs") then
      return "broke"
    end
    local wasRuin = ruined(b)
    b.hp = kind.hp
    if wasRuin then
      markWalls()
      if not kind.walkable then
        clearFootprint(server, plotById(id))
      end
    end
    publish(server, id, b)
  end),

  BLD_TAKEOVER = refusing(function(server, player, args)
    local plot, reason = plotFor(server, player, args)
    if not plot then
      return reason
    end
    local b = sv.buildings[plot.id]
    if not b then
      return "nobuilding"
    elseif b.owner == player.id then
      return "yours"
    elseif not ruined(b) then
      return "standing"
    end
    local money = Features.byName.money
    if money and not money:spend(server, player.id, Buildings.takeoverPrice, "lot takeover") then
      return "broke"
    end
    realEstate():serverTransfer(server, plot.id, player.id)
    removeBuilding(server, plot.id) -- the lot is theirs, empty
  end),

  BLD_USE = refusing(function(server, player, args)
    if not sv or args[1] ~= "medkit" then
      return
    end
    local s = stockOf(player.id)
    if (s.medkit or 0) < 1 then
      return "nomedkit"
    end
    local weapons = Features.byName.weapons
    if not (weapons and weapons:serverHeal(server, player, Buildings.medkitHeal)) then
      return "healthy"
    end
    addStock(server, player, "medkit", -1)
  end),
}

--- Take `hits` hit points off building `b` on plot `id`. One still
--- standing tells everyone its hit points; one that falls loses whatever it
--- held and stops being a wall.
local function damage(server, id, b, hits)
  if ruined(b) or hits <= 0 then
    return
  end
  b.hp = math.max(0, b.hp - hits)
  if b.hp > 0 then
    server:broadcast(Protocol.encode("BLD_HP", id, b.hp))
    return
  end
  b.output, b.progress, b.hopper = 0, 0, {}
  markWalls()
  publish(server, id, b)
end

--- A round stopped at a wall (weapons' event): if the wall is one of ours,
--- the building takes the round's damage.
function Buildings:serverWallHit(server, x, y, hits)
  if not sv then
    return
  end
  for id, b in pairs(sv.buildings) do
    local plot = plotById(id)
    if plot and not ruined(b) and not Kinds.byKey[b.kind].walkable and contains(footprint(plot), x, y, 1) then
      damage(server, id, b, hits)
      return
    end
  end
end

--- A missile went off (weapons' event): every building within `radius` of
--- (x, y) takes `full` at the centre down to a third at the edge, measured
--- to the nearest point of its footprint the way weapons measures cars.
function Buildings:serverBlast(server, x, y, radius, full)
  if not sv then
    return
  end
  for id, b in pairs(sv.buildings) do
    local plot = plotById(id)
    if plot and not ruined(b) then
      local r = footprint(plot)
      local dx = math.max(r.x - x, 0, x - (r.x + r.w))
      local dy = math.max(r.y - y, 0, y - (r.y + r.h))
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= radius then
        damage(server, id, b, math.floor(full * (1 - (2 / 3) * d / radius) + 0.5))
      end
    end
  end
end

--- Pay the parking lot's takings to its owner while they drive across it.
local function payParking(server, id, b)
  local money = Features.byName.money
  local owner = server.players[b.owner]
  local plot = plotById(id)
  if not (money and owner and plot and owner.vehicle and b.output >= 1 and Features.present(owner)) then
    return false
  end
  local x, y = Features.bodyPose(server, owner)
  if not contains(plot, x, y) then
    return false
  end
  local n = math.floor(b.output)
  money:give(server, owner.id, n)
  b.output = b.output - n
  return true
end

--- Keep pedestrians out of the buildings, bouncing their heading off the
--- wall the way city-map does for its own.
local function collidePedestrians(w)
  local peds = Features.byName.pedestrians
  local crowd = peds and peds.crowd
  if not crowd then
    return
  end
  for i = 1, crowd.n do
    local p = crowd.peds[i]
    local x, y, nx, ny = Collision.resolveCircle(w, p.x, p.y, PED_RADIUS)
    if nx then
      p.x, p.y = x, y
      local len = math.sqrt(nx * nx + ny * ny)
      if len > 0 then
        nx, ny = nx / len, ny / len
        local dot = p.hx * nx + p.hy * ny
        if dot < 0 then
          p.hx, p.hy = p.hx - 2 * dot * nx, p.hy - 2 * dot * ny
          p.heading = math.atan2(p.hy, p.hx)
        end
      end
    end
  end
end

--- Cars (players', bots', police) and pedestrians bounce off the walls.
local function collide(server, dt)
  local w = currentWalls()
  if #w.list == 0 then
    return
  end
  for _, car in pairs(server.vehicles) do
    if not (car.hidden or car.stowed) then
      Collision.resolveCar(w, car, dt)
    end
  end
  collidePedestrians(w)
end

function Buildings:serverStep(server, dt)
  if not sv then
    return
  end
  local re = realEstate()
  for id, b in pairs(sv.buildings) do
    local kind = Kinds.byKey[b.kind]
    if not (re and re:owner(id) == b.owner) then
      -- The plot changed hands (or went back on the market): the building
      -- went with the old owner.
      removeBuilding(server, id)
    elseif kind.rate and not ruined(b) then -- a ruin earns nothing; nor does it run (canRun)
      local before = math.floor(b.output)
      b.output = math.min(kind.cap, b.output + kind.rate * dt)
      local paid = payParking(server, id, b)
      if paid or math.floor(b.output) ~= before then
        publish(server, id, b)
      end
    elseif b.running then
      local r = recipeOf(b, kind)
      b.progress = b.progress + dt
      if b.progress >= r.time then
        b.progress = 0
        for item, n in pairs(r.inputs) do
          b.hopper[item] = b.hopper[item] - n
        end
        b.output = b.output + r.batch
        publish(server, id, b)
      end
    end
  end
  collide(server, dt)
end

--- For tests.
function Buildings.server()
  return sv
end

return Buildings
