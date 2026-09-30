-- Damage: what kind of hit a hit is. Every bit of damage in the game says
-- its type (docs/damage-types.md): the weapons API takes it as the last
-- argument (`serverDamage`, `damageCar`), guns declare it (`damageType`,
-- `blast.type`), and every hook that hears about damage passes it on
-- (`serverAbsorbDamage`, `serverPlayerDamaged`, `serverShotAt`,
-- `serverBlast`, `serverWallHit`, and `cause` on `serverKill`). Clients get
-- it on WPN_KILL and WPN_WRECK and word the kill feed with it.
--
-- A new type is a new entry in TYPES. For now this is only the list;
-- resistances and burning come next (see the doc).

local Damage = {
  name = "damage",
}

--- Anything that hurts without saying what it is.
Damage.DEFAULT = "bullet"

--- type -> { name, color, killed = "<killer> killed <victim>" verb,
--- died = "<victim> died" words when nobody did it }
Damage.types = {
  bullet = { name = "Bullet", color = { 1, 0.85, 0.3 }, killed = "wasted", died = "was wasted" },
  explosive = { name = "Explosive", color = { 1, 0.5, 0.15 }, killed = "blew up", died = "was blown up" },
  fire = { name = "Fire", color = { 1, 0.3, 0.1 }, killed = "burned", died = "burned to a crisp" },
  impact = { name = "Impact", color = { 0.75, 0.75, 0.8 }, killed = "flattened", died = "was flattened" },
  shock = { name = "Shock", color = { 0.5, 0.8, 1 }, killed = "fried", died = "was fried" },
  melee = { name = "Melee", color = { 0.9, 0.4, 0.4 }, killed = "beat down", died = "was beaten down" },
}

--- The entry for type `dtype`, the default's for nil or anything unknown.
function Damage.of(dtype)
  return Damage.types[dtype] or Damage.types[Damage.DEFAULT]
end

--- `dtype` when it is a known type, else the default: what goes on the wire.
function Damage.key(dtype)
  return Damage.types[dtype] and dtype or Damage.DEFAULT
end

return Damage
