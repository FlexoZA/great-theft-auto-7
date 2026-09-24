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
-- Optional:
--   ttl       seconds a round flies before it is spent (weapons' default otherwise)
--   blast     { radius, damage, soft }: the round is a missile that explodes
--             where it lands (or where it runs out of flight), hurting
--             everything within `radius` px, `damage` at the centre falling
--             to a third at the edge. `soft` is how many bullets' worth it
--             does to each feature's soft targets (pedestrians, officers).
--   stack     rounds that fit in one inventory slot (100 otherwise)
--   ammoName  what one of its rounds is called ("rocket"; "<key> ammo" otherwise)
--   stock     rounds everyone starts the game with, the loaded magazine
--             included, and the gun itself: everyone starts holding a gun
--             with a stock (for testing a gun before it can be bought)
--
-- Rounds come out of the player's inventory (the buildings feature keeps
-- it: "ammo-<key>"), a magazine at a time. The gun itself is an item too
-- ("gun-<key>"), picked up from the bag and put back on the inventory screen.

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
  {
    key = "rocket",
    name = "rocket launcher",
    damage = 0, -- the blast does the damage, not the missile
    cooldown = 0.8,
    spread = 0,
    speed = 520, -- slow enough to see it coming, and to trail smoke
    streak = 0,
    ttl = 1.8, -- about 940 px, then it goes off in mid-air
    blast = { radius = 120, damage = 90, soft = 5 },
    sound = "rocket",
    pitch = 1,
    magazine = 1,
    reload = 2.2,
    reloadSound = "reload-rocket",
    stack = 20,
    ammoName = "rocket",
    stock = 5, -- for testing until the factories are up and running
  },
}

Guns.DEFAULT = 1

for i, gun in ipairs(Guns.list) do
  gun.index = i
  Guns[gun.key] = gun
end

--- The guns everyone starts holding, as a set of indexes: the default and
--- any with a `stock`.
function Guns.startSet()
  local set = { [Guns.DEFAULT] = true }
  for i, gun in ipairs(Guns.list) do
    if gun.stock then
      set[i] = true
    end
  end
  return set
end

--- The gun at `index`, or the default for anything that isn't one.
function Guns.at(index)
  return Guns.list[index] or Guns.list[Guns.DEFAULT]
end

return Guns
