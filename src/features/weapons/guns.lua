-- The guns. One table per weapon, in the order the number keys select
-- them: 1 is the pistol everyone starts with. Damage and rate of fire are
-- the host's business (it reads the gun off its own record of what a
-- player is holding, never off the shot message); clients read the sound,
-- the streak and the HUD name.
--
--   damage    hit points per round
--   cooldown  seconds between rounds; holding fire repeats at this rate
--   spread    radians of scatter either side of the aim
--   speed     px/s a round flies
--   streak    px; how long a round is drawn
--   sound     name in sounds.lua, and a pitch around 1
--   magazine  rounds between reloads
--   reload    seconds a reload takes, and its sound in sounds.lua
--
-- Rounds come out of the player's inventory (the buildings feature keeps
-- it: "ammo-<key>"), a magazine at a time.

local Guns = {}

Guns.list = {
  {
    key = "pistol",
    name = "pistol",
    damage = 20,
    cooldown = 0.2,
    spread = 0,
    speed = 900,
    streak = 10,
    sound = "shot",
    pitch = 1,
    magazine = 15,
    reload = 1.2,
    reloadSound = "reload-pistol",
  },
  {
    key = "uzi",
    name = "uzi",
    damage = 12, -- a little less per round...
    cooldown = 0.07, -- ...but fourteen of them a second
    spread = 0.09, -- about five degrees either way: spray, don't snipe
    speed = 900,
    streak = 7,
    sound = "uzi",
    pitch = 1,
    magazine = 30, -- a couple of seconds of spray
    reload = 1.8,
    reloadSound = "reload-uzi",
  },
}

Guns.DEFAULT = 1

for i, gun in ipairs(Guns.list) do
  gun.index = i
  Guns[gun.key] = gun
end

--- The gun at `index`, or the default for anything that isn't one.
function Guns.at(index)
  return Guns.list[index] or Guns.list[Guns.DEFAULT]
end

return Guns
