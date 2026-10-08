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
--             from the inventory, and there is no "ammo-<key>" item at
--             all: the shop, the ammo factory and the police drops leave
--             it out.
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
    stack = 50,
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
    stack = 20,
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
    stack = 50,
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
    stack = 10,
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
    stack = 300,
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

--- The gun at `index`, or the default for anything that isn't one.
function Guns.at(index)
  return Guns.list[index] or Guns.list[Guns.DEFAULT]
end

return Guns
