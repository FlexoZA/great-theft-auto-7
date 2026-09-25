-- Bigfoot's leap: the leap (leap.lua) he drops when he goes down in a city
-- event (the events feature), better in every way. It reaches nearly twice
-- as far, flies higher, lands wider and harder, cracks buildings like a
-- rocket and shakes the view of everyone near the landing. Never sold: the
-- only way to get one is to beat him.

local Leap = require("src.features.abilities.leap")

return Leap.variant({
  key = "bigleap", -- on the wire and in a bag ("ability-bigleap")
  title = "bigfoot leap",
  hud = "bigfoot",
  color = { 0.85, 0.55, 0.25 }, -- his fur, in the sun
  unsold = true, -- the shop leaves it off the shelf
  radius = 130,
  range = 600,
  seconds = 0.7,
  cooldown = 8,
  afterglow = 1.0,
  damage = 70,
  soft = 6,
  lift = 38,
  walls = 60, -- what the landing does to a building right under it
  shake = 0.35,
  pitch = 0.7, -- a deeper thud
})
