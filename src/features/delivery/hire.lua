-- Hiring a delivery driver: the numbers the host and every client share,
-- and the shop's entry for one (shop/catalog.lua puts `Hire.list` on its
-- Hire shelf). Buying the entry goes through the `serverDeliver` event,
-- which delivery answers by putting the driver on the road outside the shop.

local VehicleCatalog = require("src.features.vehicles.catalog")

local Hire = {}

-- Tuning ------------------------------------------------------------------
Hire.ITEM = "hire-driver" -- what the shop sells; nobody carries it
Hire.price = 50 -- Fcks to hire one
Hire.model = "coe-4ton-refrigerated-blue" -- the box truck they drive (vehicles/models)
Hire.slots = 2 -- stacks the truck carries (materials, or goods for the shop)
Hire.maxPerPlayer = 3 -- drivers one player may have on the road at once
Hire.yard = 50 -- materials a factory keeps in its yard, past what its hopper holds

--- The truck's model, or nil if its SVG is gone.
function Hire.truck()
  return VehicleCatalog.byKey[Hire.model]
end

--- The shop card's picture: the truck, or a plain box without it.
local function icon(cx, cy, scale)
  local model = Hire.truck()
  if model then
    VehicleCatalog.draw(model, cx, cy, 0, 60 * scale)
    return
  end
  love.graphics.setColor(0.9, 0.9, 0.95)
  love.graphics.rectangle("fill", cx - 24 * scale, cy - 10 * scale, 36 * scale, 20 * scale, 2)
  love.graphics.setColor(0.36, 0.56, 0.92)
  love.graphics.rectangle("fill", cx + 13 * scale, cy - 9 * scale, 11 * scale, 18 * scale, 2)
end

local function details()
  return {
    blurb = "A driver with a box truck who keeps your factories fed and sells what they make.",
    use = "They pick up what your quarries and oil wells made and drop it at your factories that run on it. "
      .. "A full hopper gets the rest in its yard. A factory set to sell to the shop has its goods "
      .. "taken to the shop and sold for you. Wrecked, they spill their load and are gone.",
    rows = {
      { label = "carries", value = ("%d stacks"):format(Hire.slots) },
      { label = "factory yard", value = ("%d materials"):format(Hire.yard) },
      { label = "most at once", value = ("%d drivers"):format(Hire.maxPerPlayer) },
    },
  }
end

Hire.list = {
  {
    item = Hire.ITEM, n = 1, name = "Delivery driver", kind = "hire", price = Hire.price,
    onRoad = true, icon = icon, details = details,
    bought = "Your delivery driver is outside the door and on their way to work.",
  },
}

--- A short line of what a driver is doing, for their owner.
Hire.states = {
  idle = "waiting for work",
  pickup = "going to collect",
  loading = "loading",
  drop = "delivering",
  unloading = "unloading",
  sell = "taking goods to the shop",
  selling = "selling at the shop",
}

return Hire
