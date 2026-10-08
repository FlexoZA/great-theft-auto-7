-- The crews a Gang Hangout can put on the street, one per level. Level 1
-- comes with the building; each level after it is an upgrade, bought once.
-- Every level is one of the game's armed NPCs with that NPC's gun: the
-- police's officers, D-Day's riflemen, City 17's Combine. The harder a
-- crew's gun hits, the dearer the upgrade and every guard it spawns.
--
--   name     what the menu calls them
--   gun      key in weapons/guns.lua; they carry a common one
--   burst    rounds at the gun's own rate, then...
--   pause    ...seconds before the next burst
--   health   what each guard can take
--   spawn    Fcks out of the hangout's fund for each guard that comes out
--   upgrade  Fcks from the owner's wallet to reach this level (none for 1)
--   look     how they are drawn (src/body.lua's person); `colors = true`
--            dresses them in their boss's colour instead of `hat`

local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")

local Crews = {}

local ROUND_TTL = 1.2 -- seconds a round flies when its gun doesn't say (weapons' default)

Crews.list = {
  {
    name = "Street thugs", gun = "pistol", burst = 2, pause = 1.0, health = 60, spawn = 100,
    look = {
      shirt = { 0.12, 0.12, 0.14 }, pants = { 0.2, 0.26, 0.4 }, shoes = { 0.9, 0.9, 0.9 }, colors = true,
    },
  },
  {
    name = "Bent cops", gun = "uzi", burst = 5, pause = 1.0, health = 70, spawn = 150, upgrade = 500,
    look = {
      shirt = { 0.13, 0.18, 0.38 }, vest = { 0.30, 0.34, 0.46 }, hat = { 0.09, 0.12, 0.26 }, brim = true,
      pants = { 0.1, 0.12, 0.22 },
    },
  },
  {
    name = "Riflemen", gun = "ak47", burst = 4, pause = 0.8, health = 80, spawn = 200, upgrade = 1000,
    look = {
      shirt = { 0.42, 0.45, 0.38 }, pants = { 0.30, 0.33, 0.27 }, hat = { 0.26, 0.29, 0.24 },
      skin = { 0.90, 0.74, 0.60 }, shoes = { 0.16, 0.13, 0.1 }, pack = { 0.40, 0.34, 0.24 },
    },
  },
  {
    name = "Combine", gun = "shotgun", burst = 1, pause = 0.9, health = 90, spawn = 300, upgrade = 2000,
    look = {
      shirt = { 0.34, 0.40, 0.48 }, pants = { 0.18, 0.21, 0.25 }, skin = { 0.13, 0.14, 0.16 },
      hood = { 0.17, 0.19, 0.22 }, shoes = { 0.06, 0.06, 0.07 }, vest = { 0.45, 0.51, 0.59 }, lenses = true,
    },
  },
}

-- How far each gun's barrel reaches past the hands (City 17's soldiers hold them the same).
local HELD = { pistol = 4, uzi = 8, ak47 = 15, shotgun = 14, sniper = 21, rocket = 18, flamethrower = 12, minigun = 14 }

for i, crew in ipairs(Crews.list) do
  local gun = Guns[crew.gun]
  crew.level = i
  crew.arms = Tiers.apply(gun, Tiers.DEFAULT)
  crew.gunIndex = gun.index
  crew.gunName = gun.name
  -- A little short of where its rounds give out, and never further than a cop shoots.
  crew.reach = math.min(520, gun.speed * (gun.ttl or ROUND_TTL) * 0.85)
  crew.look.gun = true
  crew.look.gunLength = HELD[crew.gun] or 15
  -- Damage a second while firing, every pellet landing: what the menu shows.
  -- A burst is its rounds at the gun's rate, then the pause before the next.
  local per = gun.damage * (gun.pellets or 1)
  crew.dps = math.floor(per * crew.burst / ((crew.burst - 1) * gun.cooldown + math.max(crew.pause, gun.cooldown)) + 0.5)
end

Crews.MAX = #Crews.list

--- The crew at `level`, clamped to the list.
function Crews.at(level)
  return Crews.list[math.max(1, math.min(Crews.MAX, math.floor(tonumber(level) or 1)))]
end

return Crews
