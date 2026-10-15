-- The guns. One table per weapon, in the order the weapon slots start
-- with: 1 is the pistol everyone starts with. Damage and rate of fire are
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
--   blurb     what it is like, in a sentence, for the shop's side panel
--
-- Optional:
--   ttl       seconds a round flies before it is spent (weapons' default otherwise)
--   damageType what kind of hit a round is (src/features/damage): "bullet"
--             otherwise
--   blast     { radius, damage, soft, type }: the round is a missile that explodes
--             where it lands (or where it runs out of flight), hurting
--             everything within `radius` px, `damage` at the centre falling
--             to a third at the edge. `soft` is how many bullets' worth it
--             does to each feature's soft targets (pedestrians, officers).
--             `type` is the blast's damage type, "explosive" otherwise.
--   ignite    { seconds, dps }: a round that hits somebody on foot sets them
--             alight (the damage feature's burning) for `seconds` at `dps`
--   flame     true: its rounds are drawn as tongues of fire that swell and
--             darken as they go, not as streaks (the flamethrower)
--   tank      true: the magazine is a tank, and one ammo item fills it
--             whole, however much is left in it or however big a tier
--             makes it (a fuel can). A box, a drop or a stock is counted in
--             items, one a magazine
--   pellets   projectiles one trigger pull sends out (1 otherwise), each
--             scattered by `spread` on its own: a shotgun. The magazine
--             counts pulls, not pellets, and only the first pellet sounds.
--   quiet     true: its rounds make no sound of their own (a gun a feature
--             fires and sounds itself: the scout car's tau cannon)
--   spinUp    seconds the barrels take to wind up before the first round
--             (the minigun): hold fire and it spins, rounds come once it
--             turns, and it keeps turning between rounds for as long as
--             you hold on. Let go and it has to wind up again
--   pace      with `spinUp`: the share of your pace on foot, walking or
--             sprinting, while the barrels turn (winding up or firing)
--   dropWeight how likely an enemy's ammo box is for this gun, against the
--             others' (pickups' serverDropAmmo); 1 otherwise
--   stack     rounds that fit in one inventory slot (100 otherwise)
--   ammoName  what one of its rounds is called ("rocket"; "<key> ammo" otherwise)
--   ammo      the key of another gun whose rounds it fires (the super
--             shotgun takes the shotgun's shells, the SMG the pistol's 9mm):
--             it has no ammo item of its own. A `bottomless` gun's rounds
--             are an item all the same once another gun fires them
--             (`Guns.ammoTypes`): the pistol's 9mm, for the SMG
--   unlock    true for a gun only won, never on the shelf or out of a
--             factory until you have picked one up (a boss's drop): from
--             then on the shop sells it to you (weapons/init.lua). Enemies
--             never carry it
--   tierStats the stats a better tier improves, in order (tiers/init.lua):
--             Guns.tierStats otherwise; "blast.damage" reaches into `blast`
--   scope     how many times the scope magnifies: hold the scope button
--             (right mouse) with the gun in hand and a lens that much
--             closer opens round the cursor; the cursor is a scope's
--             crosshair all the while the gun is up (the sniper rifle)
--   stock     rounds everyone starts the game with, the loaded magazine
--             included, and the gun itself: everyone starts with a gun
--             that has a stock in a weapon slot (for testing a gun before
--             it can be bought)
--   bottomless true: its reserve never runs out (the pistol). It still
--             holds a magazine and reloads, but a reload takes nothing
--             from the inventory. Its "ammo-<key>" item is only there for
--             a gun that borrows its rounds (`ammo`: the SMG's 9mm).
--
-- Rounds come out of the player's inventory (the buildings feature keeps
-- it: "ammo-<key>"), a magazine at a time. The gun itself is an item too
-- ("gun-<key>"), picked up from the bag and put back on the inventory screen.

local Guns = {}

Guns.list = {
  {
    key = "pistol",
    blurb = "Hits hard and straight, and never runs out of rounds. Everyone starts with one.",
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
    bottomless = true, -- never out of rounds, so nobody is ever left unarmed
    ammoName = "9mm round", -- the SMG's ("ammo-pistol"); the pistol itself never takes any
    stack = 300, -- ten SMG magazines a slot
  },
  {
    key = "uzi",
    dropWeight = 3, -- how often an enemy's ammo box is for it (pickups): a common gun's
    blurb = "Sprays fourteen rounds a second: weak one at a time, deadly up close.",
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
    stack = 300, -- ten magazines a slot
  },
  {
    -- The Hunter-Chopper drops it in the Outer City (hunter-chopper/init.lua).
    key = "smg",
    unlock = true,
    dropWeight = 2,
    blurb = "Fifteen 9mm rounds a second, tight and quick to reload, but spent by about 500 px. "
      .. "Fires the pistol's 9mm rounds.",
    name = "SMG",
    damage = 13,
    cooldown = 0.065, -- fifteen a second: faster than the AK's nine
    spread = 0.05, -- tighter than the uzi's spray
    speed = 900,
    streak = 8,
    ttl = 0.55, -- about 500 px, against the AK's 1200
    sound = "uzi",
    pitch = 1.15, -- a lighter crack than the uzi's
    magazine = 30,
    reload = 1.5,
    reloadSound = "reload-uzi",
    ammo = "pistol", -- 9mm
  },
  {
    key = "ak47",
    dropWeight = 3, -- as often as the uzi's: the gun most soldiers carry
    blurb = "A rifle: nine rounds a second with hardly any scatter.",
    name = "AK-47",
    damage = 18, -- between the pistol and the uzi per round...
    cooldown = 0.11, -- ...nine of them a second
    spread = 0.04, -- a couple of degrees: a rifle, not a spray
    speed = 1000,
    streak = 10,
    sound = "ak47",
    pitch = 1,
    magazine = 30,
    reload = 2.0,
    reloadSound = "reload-ak47",
    stack = 300, -- ten magazines a slot
    ammoName = "AK-47 round",
  },
  {
    key = "shotgun",
    dropWeight = 2, -- shells a little less often
    blurb = "Six pellets a pull that fill a doorway. Brutal up close, spent by about 250 px.",
    name = "shotgun",
    damage = 11, -- per pellet: all six in the chest is a car half wrecked
    cooldown = 0.9, -- pump between shots
    spread = 0.16, -- nine degrees either side: fills a doorway
    speed = 800,
    streak = 6,
    ttl = 0.32, -- about 250 px, then the pellets are spent
    pellets = 6,
    sound = "shotgun",
    pitch = 1,
    magazine = 6,
    reload = 2.4,
    reloadSound = "reload-shotgun",
    ammoName = "shell",
    stack = 60, -- ten loads a slot
  },
  {
    -- The Mood Slayer's: the Baron of Heck drops it (eternal-mood/baron.lua).
    key = "super-shotgun",
    unlock = true,
    blurb = "The Mood Slayer's own. Twelve pellets a pull that reach twice as far as a shotgun's, "
      .. "and ten shells between reloads. Fires shotgun shells.",
    name = "super shotgun",
    damage = 11, -- per pellet, as a shotgun's: there are twice as many
    cooldown = 0.9,
    spread = 0.16,
    speed = 800,
    streak = 6,
    ttl = 0.64, -- about 500 px: twice a shotgun's reach
    pellets = 12,
    sound = "shotgun",
    pitch = 0.8, -- deeper: two barrels' worth
    magazine = 10,
    reload = 2.8,
    reloadSound = "reload-shotgun",
    ammo = "shotgun",
  },
  {
    key = "rocket",
    dropWeight = 0.5, -- rockets rarely
    blurb = "A slow missile that blows up whatever it hits. Mind the blast: it hurts you too.",
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
    stack = 30, -- thirty rockets a slot
    ammoName = "rocket",
    tierStats = { "blast.damage", "reload", "blast.radius" }, -- one round a magazine whatever the tier
  },
  {
    key = "sniper",
    dropWeight = 1, -- now and then
    blurb = "One round drops anyone on foot. Hold right mouse for a 4x scope.",
    name = "sniper rifle",
    damage = 200, -- a person on foot in one; the round is the whole point
    cooldown = 1.3, -- the bolt worked between shots
    spread = 0,
    speed = 3000, -- there before you hear it
    streak = 44,
    -- About 1900 px: a little past anywhere the cursor can reach from you,
    -- with the camera panned all the way out (vision: 700 px of pan, and
    -- half a 1280-wide window at the 0.65 zoom that comes with it).
    ttl = 0.63,
    sound = "sniper",
    pitch = 1,
    magazine = 5,
    reload = 5,
    reloadSound = "reload-sniper",
    ammoName = "sniper round",
    stack = 60, -- twelve magazines a slot
    scope = 4,
  },
  {
    key = "flamethrower",
    dropWeight = 1, -- now and then
    blurb = "A jet of fire that sets whoever it touches alight. Short reach; a fuel can fills the tank.",
    name = "flamethrower",
    damageType = "fire",
    damage = 5, -- a lick of flame; fourteen of them a second, and it keeps burning after
    cooldown = 0.07,
    spread = 0.18, -- a cone about twenty degrees wide
    speed = 360,
    streak = 0,
    ttl = 0.45, -- about 160 px, then the flame has burned out
    flame = true,
    ignite = { seconds = 3, dps = 8 },
    sound = "flame",
    pitch = 1,
    magazine = 100, -- seven seconds of fire
    tank = true,
    reload = 2.5,
    reloadSound = "reload-flamethrower",
    ammoName = "fuel can",
    stack = 20, -- twenty tanks a slot
    tierStats = { "damage", "ttl", "magazine", "ignite.dps" },
  },
  {
    key = "minigun",
    dropWeight = 0.5, -- belts rarely
    blurb = "Six barrels, seventeen rounds a second once they wind up. Hold the trigger: it spins first.",
    name = "minigun",
    damage = 10, -- under an uzi's 12 a round...
    cooldown = 0.06, -- ...but seventeen of them a second, and a belt of 150
    spread = 0.08, -- about five degrees either way
    speed = 950,
    streak = 9,
    ttl = 0.8, -- about 760 px
    spinUp = 0.8, -- the barrels wind up before the first round
    pace = 0.5, -- and you lug it at half your pace while they turn
    sound = "minigun", -- one roar while it fires (weapons/sounds.lua loops it)
    pitch = 1,
    magazine = 150,
    reload = 4.5, -- a new belt box: slow
    reloadSound = "reload-minigun",
    ammoName = "minigun round",
    stack = 1500, -- ten belts a slot
    tierStats = { "damage", "spinUp", "magazine", "reload" },
  },
}

Guns.DEFAULT = 1
-- What an uncommon gun hits harder with, a rare one fires faster too, and a
-- legendary one also holds more and reloads sooner.
Guns.tierStats = { "damage", "cooldown", "magazine", "reload" }

for i, gun in ipairs(Guns.list) do
  gun.index = i
  gun.tierStats = gun.tierStats or Guns.tierStats
  Guns[gun.key] = gun
end

-- Every ammo item there is, in guns.lua's order: one per gun that fires
-- rounds from the bag, the rounds of its own or of the gun it borrows them
-- from (`ammo`), once each. `item` is "ammo-<owner key>"; `owner` the gun
-- they belong to (the pistol, for 9mm); `gun` the first gun that fires them
-- from the bag, whose magazine sizes a box and whose `dropWeight` says how
-- often one drops. The shop, the ammo factory, enemies' boxes and the ammo
-- crates sell, make and drop these, and nothing else.
Guns.ammoTypes, Guns.ammoTypeOf = {}, {}
for _, gun in ipairs(Guns.list) do
  local owner = gun.ammo and Guns[gun.ammo] or gun
  local item = "ammo-" .. owner.key
  if not gun.bottomless and not Guns.ammoTypeOf[item] then
    local t = { item = item, owner = owner, gun = gun }
    Guns.ammoTypes[#Guns.ammoTypes + 1] = t
    Guns.ammoTypeOf[item] = t
  end
end

--- The inventory item gun `gun`'s rounds are: "ammo-<key>", or the gun's it
--- borrows them from (`ammo`).
function Guns.ammoItem(gun)
  return "ammo-" .. (gun.ammo or gun.key)
end

--- The gun at `index`, or the default for anything that isn't one.
function Guns.at(index)
  return Guns.list[index] or Guns.list[Guns.DEFAULT]
end

return Guns
