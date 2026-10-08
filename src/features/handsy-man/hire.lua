-- Hiring a Handsy Man: the numbers the host and every client share, and
-- the shop's entry for one (shop/catalog.lua puts `Hire.list` on its Hire
-- shelf). Buying the entry goes through the `serverDeliver` event, which
-- handsy-man answers by putting him on the road outside the shop, or
-- refuses when there is nothing of the buyer's to mend.

local VehicleCatalog = require("src.features.vehicles.catalog")

local Hire = {}

-- Tuning ------------------------------------------------------------------
Hire.ITEM = "hire-handsy-man" -- what the shop sells; nobody carries it
Hire.price = 30 -- Fcks to hire one
Hire.model = "pickup-singlecab-blue" -- the pickup he drives (vehicles/models)
Hire.markup = 3 -- times the repair menu's price he charges for a repair
Hire.ruinMarkup = 2 -- times that again to rebuild a ruin
Hire.rate = 80 -- hit points he mends a second
Hire.maxPerPlayer = 1 -- Handsy Men one player may have on the road at once

--- The pickup's model, or nil if its SVG is gone.
function Hire.truck()
  return VehicleCatalog.byKey[Hire.model]
end

--- The shop card's picture: the pickup, or a plain one without it.
local function icon(cx, cy, scale)
  local model = Hire.truck()
  if model then
    VehicleCatalog.draw(model, cx, cy, 0, 56 * scale)
    return
  end
  love.graphics.setColor(0.3, 0.45, 0.8)
  love.graphics.rectangle("fill", cx - 24 * scale, cy - 10 * scale, 48 * scale, 20 * scale, 3)
  love.graphics.setColor(0.2, 0.25, 0.35)
  love.graphics.rectangle("fill", cx + 2 * scale, cy - 8 * scale, 10 * scale, 16 * scale, 2)
end

local function details()
  return {
    blurb = "A Handsy Man in a pickup who goes round your damaged buildings and fixes them up.",
    use = "He drives to each of your buildings that took damage, ruins too, and repairs it, paying out of "
      .. "your Fcks. He charges more than fixing it yourself. When everything is whole or your wallet is empty "
      .. "he drives back to the shop and goes home. Only for hire while something of yours needs fixing. "
      .. "Wrecked, he is gone.",
    rows = {
      { label = "repairs", value = ("%d hp a second"):format(Hire.rate) },
      { label = "charges", value = ("%dx the repair price"):format(Hire.markup) },
      { label = "rebuilding a ruin", value = ("%dx the repair price"):format(Hire.markup * Hire.ruinMarkup) },
      { label = "pays with", value = "your Fcks" },
      { label = "most at once", value = ("%d"):format(Hire.maxPerPlayer) },
    },
  }
end

Hire.list = {
  {
    item = Hire.ITEM, n = 1, name = "Handsy Man", kind = "hire", price = Hire.price,
    onRoad = true, icon = icon, details = details,
    bought = "Your Handsy Man is outside the door and on his way to fix your buildings.",
  },
}

--- A short line of what he is doing, for his employer.
Hire.states = {
  idle = "looking for work",
  drive = "on his way to a job",
  repair = "repairing",
  home = "going home",
}

return Hire
