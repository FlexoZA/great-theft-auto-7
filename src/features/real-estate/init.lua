-- Real estate: land for sale, inside the city and past its limits.
--
-- Plots. The empty blocks at the corners of the city are for sale. Drive or
-- walk onto one, press the buy key, and if you are carrying enough Fcks the
-- plot is yours: the koins come out of your wallet, a fence in your colour
-- goes up around it and everyone sees your name on the sign.
--
-- Expansion. Along the city limits, beside every block the city could grow
-- into, a small green square sits on the outer street. Stop on it and buy,
-- and a new block joins the city there: an empty plot with a street on every
-- side, already yours. New blocks open up new squares further out, up to a
-- few blocks past the original edge (Layout.GROW in city-map).
--
-- Leave the game and your plots go back on the market; the city keeps the
-- blocks it grew until the game ends. Plots are 6x6 tiles; the buildings
-- feature puts something on the ones that have an owner.
--
-- The land comes from the city-map feature (blocks of kind "plot",
-- city:grow); without it there is nothing to sell and this feature does
-- nothing. The server decides every sale: it checks the buyer is standing on
-- the plot or the square, that it is still for sale and that they can pay
-- (through money:spend).
--
-- Messages
--   client -> server  RE_BUY    <plotId>
--   client -> server  RE_GROW   <bi> <bj>             (buy the block at bi, bj)
--   server -> all     RE_EXPAND <bi> <bj>             (the city grew; sent before RE_OWNER)
--   server -> all     RE_OWNER  <plotId> <playerId>   (0 = for sale again)
--   server -> player  RE_NO     <reason>              (taken | broke | away | gone)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local Car = require("src.car")
local UI = require("src.ui")

local RealEstate = {
  name = "real-estate",
  priority = 25, -- over the map (20), under pedestrians (60) and koins (65)
}

-- Tuning ------------------------------------------------------------------
RealEstate.price = 20 -- Fcks for an empty plot in the city
RealEstate.growPrice = 100 -- Fcks for a new block past the city limits
RealEstate.padSize = 44 -- px; the square you stop on to buy a new block
RealEstate.buyKey = "f" -- default binding of the "buy" action (rebind in Settings)

local T, P = 64, 10 -- tile size and tiles per block, as in city-map's layout
local SLACK = 40 -- px the server allows for a buyer drawn a little behind where it is
local NOTICE_TIME = 2.5 -- seconds a refusal stays on the HUD
local REASONS = {
  taken = "Someone beat you to it.",
  broke = "You can't afford it.",
  away = "Stand on it to buy it.",
  gone = "That block is already part of the city.",
}

--- "20 Fcks", through the money feature when it is there.
local function amount(n)
  local money = Features.byName.money
  return money and money.amount(n) or tostring(n)
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city, city and city.map
end

-- Land ----------------------------------------------------------------------
-- Both sides work these out from the city map, so they agree without sending
-- any of it: plots are numbered in block order, and the city only ever grows
-- by appending blocks in the order the server sold them.

RealEstate.plots = {} -- { id, x, y, w, h, block } in world px
local sites, sitesMap, sitesVersion = {}, nil, nil -- expansion squares, and the map they were worked out for

local function refreshPlots()
  local _, map = cityMap()
  local plots = {}
  for _, b in ipairs(map and map.blocks or {}) do
    if b.kind == "plot" then
      plots[#plots + 1] = {
        id = #plots + 1,
        x = map.x0 + b.tx * T,
        y = map.y0 + b.ty * T,
        w = b.tw * T,
        h = b.th * T,
        block = b,
      }
    end
  end
  RealEstate.plots = plots
end

--- The squares on the city limits, one per block the city can grow into.
--- Each sits in the outer lane of the street between the new block and the
--- one it grows from, halfway along the block. `area` is the ground the new
--- block will cover, streets included.
local function currentSites()
  local city, map = cityMap()
  if not map then
    return {}
  end
  if sitesMap == map and sitesVersion == map.version then
    return sites
  end
  sites, sitesMap, sitesVersion = {}, map, map.version
  for _, s in ipairs(city:growthSites()) do
    local di, dj = s.from.bi - s.bi, s.from.bj - s.bj
    local x, y
    if di ~= 0 then
      x = map.x0 + (math.max(s.bi, s.from.bi) * P + 1) * T - di * T / 2
      y = map.y0 + (s.bj * P + 6) * T
    else
      x = map.x0 + (s.bi * P + 6) * T
      y = map.y0 + (math.max(s.bj, s.from.bj) * P + 1) * T - dj * T / 2
    end
    sites[#sites + 1] = {
      bi = s.bi,
      bj = s.bj,
      x = x,
      y = y,
      area = { x = map.x0 + s.bi * P * T, y = map.y0 + s.bj * P * T, w = (P + 2) * T, h = (P + 2) * T },
    }
  end
  return sites
end

local function findSite(bi, bj)
  for _, s in ipairs(currentSites()) do
    if s.bi == bi and s.bj == bj then
      return s
    end
  end
  return nil
end

local function contains(plot, x, y)
  return x >= plot.x and x < plot.x + plot.w and y >= plot.y and y < plot.y + plot.h
end

local function plotAt(x, y)
  for _, plot in ipairs(RealEstate.plots) do
    if contains(plot, x, y) then
      return plot
    end
  end
  return nil
end

local function onPad(site, x, y, slack)
  local r = RealEstate.padSize / 2 + (slack or 0)
  return math.abs(x - site.x) <= r and math.abs(y - site.y) <= r
end

local function siteAt(x, y)
  for _, s in ipairs(currentSites()) do
    if onPad(s, x, y) then
      return s
    end
  end
  return nil
end

--- Add block (bi, bj) to the city and return its plot.
local function grow(bi, bj)
  local city = cityMap()
  city:grow(bi, bj) -- does nothing on the host's own client: the server already grew it
  refreshPlots()
  for _, plot in ipairs(RealEstate.plots) do
    if plot.block.bi == bi and plot.block.bj == bj then
      return plot
    end
  end
  return nil
end

-- Client --------------------------------------------------------------------

RealEstate.owners = {} -- plot id -> player id
local herePlot, hereSite = nil, nil -- the plot my body is on, or the square
local notice, noticeTimer = nil, 0
local time = 0

function RealEstate:load()
  refreshPlots()
  Controls.register("buy", "Buy (property)", self.buyKey)
end

-- RE_EXPAND and RE_OWNER for land sold before we joined arrive in the same
-- burst as START, so land is only forgotten on the way out. City-map (lower
-- priority) has already put the city back to its original size by now.
function RealEstate:exitGame()
  self.owners = {}
  refreshPlots()
  herePlot, hereSite, notice, noticeTimer = nil, nil, nil, 0
end

function RealEstate:update(dt, client)
  time = time + dt
  noticeTimer = math.max(0, noticeTimer - dt)
  local x, y = client:myPose()
  herePlot, hereSite = nil, nil
  if x then
    hereSite = siteAt(x, y)
    herePlot = not hereSite and plotAt(x, y) or nil
  end
end

--- Can I pay `price`? Answered here so an empty wallet hears "no" at once;
--- the host still checks before it sells.
local function affordable(client, price)
  local money = Features.byName.money
  if money and money.canAfford and not money:canAfford(client, price) then
    notice, noticeTimer = REASONS.broke, NOTICE_TIME
    return false
  end
  return true
end

--- The `actionTaken` convention: the buy key is ours while there is
--- something to buy underfoot, so on-foot leaves the cars alone.
function RealEstate:actionTaken()
  return hereSite ~= nil or (herePlot ~= nil and not self.owners[herePlot.id])
end

function RealEstate:keypressed(key, client)
  if not Controls.is("buy", key) then
    return
  end
  if hereSite then
    if affordable(client, self.growPrice) then
      client:send(Protocol.encode("RE_GROW", hereSite.bi, hereSite.bj))
    end
  elseif herePlot and not self.owners[herePlot.id] then
    if affordable(client, self.price) then
      client:send(Protocol.encode("RE_BUY", herePlot.id))
    end
  end
end

local function ownerName(client, id)
  local p = client.players[id]
  return p and p.name or "?"
end

--- A signboard on two posts, centred on x.
local function drawSign(x, y, text, color)
  local font = UI.fonts.small
  local w = font:getWidth(text) + 20
  love.graphics.setColor(0.25, 0.18, 0.10)
  love.graphics.rectangle("fill", x - w / 2 + 8, y + 14, 5, 22)
  love.graphics.rectangle("fill", x + w / 2 - 13, y + 14, 5, 22)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x - w / 2 + 5, y + 5, w, 24)
  love.graphics.setColor(0.95, 0.93, 0.86)
  love.graphics.rectangle("fill", x - w / 2, y, w, 24)
  love.graphics.setColor(color[1], color[2], color[3])
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x - w / 2, y, w, 24)
  love.graphics.setFont(font)
  love.graphics.printf(text, x - w / 2, y + 12 - font:getHeight() / 2, w, "center")
end

local function drawPlot(client, plot)
  local owner = RealEstate.owners[plot.id]
  local cx = plot.x + plot.w / 2
  if owner then
    -- A fence in the owner's colour.
    local c = Car.colorFor(owner)
    love.graphics.setColor(c[1], c[2], c[3], 0.9)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line", plot.x + 4, plot.y + 4, plot.w - 8, plot.h - 8)
    drawSign(cx, plot.y + 18, ownerName(client, owner) .. "'s plot", c)
  else
    -- Tape around a plot that is for sale, brighter while you stand on it.
    local lit = herePlot == plot and 0.5 + 0.4 * math.abs(math.sin(time * 3)) or 0.35
    love.graphics.setColor(1, 0.82, 0.2, lit)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", plot.x + 4, plot.y + 4, plot.w - 8, plot.h - 8)
    drawSign(cx, plot.y + 18, "FOR SALE  " .. amount(RealEstate.price), { 0.8, 0.15, 0.1 })
  end
end

--- A green square with a plus on the street at the city limits; while you
--- stand on it, the outline of the block you would be buying.
local function drawSite(site)
  local s = RealEstate.padSize
  local on = hereSite == site
  local pulse = on and 0.6 + 0.4 * math.abs(math.sin(time * 4)) or 0.85
  if on then
    local a = site.area
    love.graphics.setColor(0.4, 1, 0.5, 0.08)
    love.graphics.rectangle("fill", a.x, a.y, a.w, a.h)
    love.graphics.setColor(0.4, 1, 0.5, 0.5 * pulse)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", a.x, a.y, a.w, a.h)
  end
  love.graphics.setColor(0.1, 0.45, 0.2, pulse)
  love.graphics.rectangle("fill", site.x - s / 2, site.y - s / 2, s, s, 4)
  love.graphics.setColor(0.85, 1, 0.85, pulse)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", site.x - s / 2, site.y - s / 2, s, s, 4)
  love.graphics.rectangle("fill", site.x - 3, site.y - 12, 6, 24)
  love.graphics.rectangle("fill", site.x - 12, site.y - 3, 24, 6)
end

function RealEstate:drawBelowCars(client)
  for _, plot in ipairs(self.plots) do
    drawPlot(client, plot)
  end
  for _, site in ipairs(currentSites()) do
    drawSite(site)
  end
  love.graphics.setColor(1, 1, 1)
end

function RealEstate:drawHUD(client)
  local w, h = love.graphics.getDimensions()
  local key = Controls.name(Controls.bindings("buy")[1])
  local text, color
  if noticeTimer > 0 then
    text, color = notice, { 1, 0.45, 0.4 }
  elseif hereSite then
    text = ("Expand the city: a new block for %s.  %s: buy"):format(amount(self.growPrice), key)
    color = { 0.5, 1, 0.6 }
  elseif herePlot then
    local owner = self.owners[herePlot.id]
    if not owner then
      text, color = ("Plot for sale: %s.  %s: buy"):format(amount(self.price), key), { 1, 0.85, 0.3 }
    elseif Features.byName.buildings then
      text = nil -- buildings says what stands on a plot that has an owner
    elseif owner == client.myId then
      text, color = "Your plot.", { 0.6, 0.9, 0.6 }
    else
      text, color = ownerName(client, owner) .. "'s plot", { 0.8, 0.8, 0.85 }
    end
  end
  if text then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf(text, 1, h - 129, w, "center")
    love.graphics.setColor(color)
    love.graphics.printf(text, 0, h - 130, w, "center")
    love.graphics.setColor(1, 1, 1)
  end
end

RealEstate.clientMessages = {
  RE_EXPAND = function(_client, args)
    local bi, bj = tonumber(args[1]), tonumber(args[2])
    if bi and bj and cityMap() then
      grow(bi, bj)
    end
  end,
  RE_OWNER = function(client, args)
    local id, owner = tonumber(args[1]), tonumber(args[2])
    if id and owner then
      RealEstate.owners[id] = owner ~= 0 and owner or nil
      if owner == client.myId then
        noticeTimer = 0 -- bought: an earlier refusal no longer applies
      end
    end
  end,
  RE_NO = function(_client, args)
    notice = REASONS[args[1]]
    noticeTimer = notice and NOTICE_TIME or 0
  end,
}

-- Server ----------------------------------------------------------------

local sv = nil -- { owners = { plot id -> player id } }

-- City-map (lower priority) has put the city back to its original size.
function RealEstate:serverStart()
  sv = { owners = {} }
  refreshPlots()
end

--- The city was swapped for another map (city-map's `mapChanged`; a quest
--- does it). Its plots are the ones for sale now and whatever anyone owned
--- stays behind, unpaid. On the host this clears the server's book as well
--- as what its client draws; a client clears only its own.
function RealEstate:mapChanged()
  refreshPlots()
  self.owners = {}
  if sv then
    sv.owners = {}
  end
  herePlot, hereSite, noticeTimer = nil, nil, 0
end

--- Someone joining mid-game gets the city as it has grown, then who owns what.
function RealEstate:serverPlayerJoined(server, player)
  local _, map = cityMap()
  if not (sv and map) then
    return
  end
  for _, g in ipairs(map.grown) do
    server:send(player, Protocol.encode("RE_EXPAND", g.bi, g.bj))
  end
  for id, owner in pairs(sv.owners) do
    server:send(player, Protocol.encode("RE_OWNER", id, owner))
  end
end

--- A player who leaves forfeits their land; nobody is refunded.
function RealEstate:serverPlayerLeft(server, player)
  if not sv then
    return
  end
  for id, owner in pairs(sv.owners) do
    if owner == player.id then
      sv.owners[id] = nil
      server:broadcast(Protocol.encode("RE_OWNER", id, 0))
    end
  end
end

--- Is the player's body (not a wreck) somewhere `test(x, y)` accepts?
local function standsWhere(server, player, test)
  if not Features.present(player) then
    return false
  end
  local x, y = Features.bodyPose(server, player)
  return test(x, y)
end

RealEstate.serverMessages = {
  RE_BUY = function(server, player, args)
    local plot = RealEstate.plots[tonumber(args[1]) or 0]
    if not (sv and plot and player.body) then
      return
    end
    local money = Features.byName.money
    local reason
    if not standsWhere(server, player, function(x, y)
      return contains(plot, x, y)
    end) then
      reason = "away"
    elseif sv.owners[plot.id] then
      reason = "taken"
    elseif money and not money:spend(server, player.id, RealEstate.price, "plot") then
      reason = "broke"
    else
      sv.owners[plot.id] = player.id
      server:broadcast(Protocol.encode("RE_OWNER", plot.id, player.id))
      return
    end
    server:send(player, Protocol.encode("RE_NO", reason))
  end,

  RE_GROW = function(server, player, args)
    local bi, bj = tonumber(args[1]), tonumber(args[2])
    if not (sv and bi and bj and player.body and cityMap()) then
      return
    end
    local site = findSite(bi, bj)
    local money = Features.byName.money
    local reason
    if not site then
      reason = "gone"
    elseif not standsWhere(server, player, function(x, y)
      return onPad(site, x, y, SLACK)
    end) then
      reason = "away"
    elseif money and not money:spend(server, player.id, RealEstate.growPrice, "city block") then
      reason = "broke"
    else
      local plot = grow(bi, bj)
      sv.owners[plot.id] = player.id
      server:broadcast(Protocol.encode("RE_EXPAND", bi, bj))
      server:broadcast(Protocol.encode("RE_OWNER", plot.id, player.id))
      return
    end
    server:send(player, Protocol.encode("RE_NO", reason))
  end,
}

--- Who owns plot `id` on the host, or nil. Buildings asks.
function RealEstate:owner(id)
  return sv and sv.owners[id]
end

--- For tests.
function RealEstate.server()
  return sv
end

return RealEstate
