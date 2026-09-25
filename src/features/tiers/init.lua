-- Tiers: how good a piece of equipment is. Everything a player equips (a
-- gun, an ability, a vest, a piece of clothing) comes in one of four
-- tiers, each with its colour on every card, slot and box that shows it:
--
--   common      grey   the item's base stats
--   uncommon    green  its first stat better
--   rare        blue   its first two stats better, and by more
--   legendary   gold   every stat better, and by more again
--
-- Each kind of item lists the stats a tier improves, in order
-- (`tierStats`: guns.lua, each ability, armor/kinds.lua, gear/kinds.lua), so
-- the first one is what an uncommon improves: a leap's cooldown, then its
-- range, so a rare leap comes back sooner and goes further and a legendary
-- one hits harder and wider too. An improved stat is `boost` times better:
-- more of it where more is better, divided by it where less is (cooldowns,
-- reloads, scatter). A clothes multiplier keeps its direction and grows
-- its bonus by `bonus` instead (running shoes x1.15 speed: x1.26 legendary).
--
-- An item of a tier is its key with "@<tier>" on the end, "gun-uzi@rare",
-- "ability-leap@legendary"; a common one has nothing on the end, so every
-- item from before tiers is common. The same goes for what sits in a slot
-- ("leap@rare" in an ability slot). Items of different tiers are different
-- items: they stack apart. Medkits, drinks, ammo and materials have no
-- tier. A new kind of equipment gets tiers by adding its prefix to
-- `Tiers.prefixes` and a `tierStats` list to its kinds.
--
-- The shop sells every tier (dearer the better); anything else hands out
-- commons unless it says otherwise (Bigfoot drops a legendary leap).
--
-- No hooks: every feature that equips things requires this module for the
-- names, colours and numbers.

local Tiers = {
  name = "tiers",
  SEP = "@",
  DEFAULT = "common",
  list = {
    { key = "common", title = "common", color = { 0.66, 0.66, 0.7 }, upgrades = 0, boost = 1, bonus = 1, price = 1 },
    {
      key = "uncommon", title = "uncommon", color = { 0.35, 0.85, 0.4 }, upgrades = 1, boost = 1.15, bonus = 1.25,
      price = 2,
    },
    { key = "rare", title = "rare", color = { 0.3, 0.6, 1 }, upgrades = 2, boost = 1.25, bonus = 1.5, price = 4 },
    {
      key = "legendary", title = "legendary", color = { 1, 0.78, 0.2 }, upgrades = math.huge, boost = 1.35,
      bonus = 1.75, price = 8,
    },
  },
  byKey = {},
  -- Items that come in tiers, by the start of their key.
  prefixes = { "gun-", "ability-", "armor-", "gear-" },
}

-- Stats where less is better: a tier divides them.
local LOWER = { cooldown = true, reload = true, spread = true, delay = true, fireEvery = true }
-- Stats that are counts: a tier rounds them.
local WHOLE = { damage = true, magazine = true, soft = true, points = true, pellets = true }
-- What a stat is called on a card, where its name won't do.
local LABELS = {
  cooldown = "cooldown", fireEvery = "fire rate", seconds = "duration", rate = "heal rate", delay = "delay",
  ["blast.damage"] = "blast", ["blast.radius"] = "blast radius", points = "points", stamina = "sprint cost",
}

for i, t in ipairs(Tiers.list) do
  t.rank = i
  Tiers.byKey[t.key] = t
end
local COMMON = Tiers.byKey[Tiers.DEFAULT]

--- The tier table for `key` (common for nil or anything unknown).
function Tiers.get(key)
  return Tiers.byKey[key or ""] or COMMON
end

--- The colour of tier `key`.
function Tiers.color(key)
  return Tiers.get(key).color
end

--- `s` ("gun-uzi@rare", "leap") as its base and tier key: "gun-uzi",
--- "rare". Nothing on the end is common; an unknown tier comes back nil,
--- so a forged one is refused.
function Tiers.split(s)
  local base, tier = s:match("^(.-)@([^@]*)$")
  if not base then
    return s, Tiers.DEFAULT
  end
  return base, Tiers.byKey[tier] and tier or nil
end

--- The base of `s`, without its tier.
function Tiers.base(s)
  return (Tiers.split(s))
end

--- The tier key of `s` (common if it has none or a bad one).
function Tiers.of(s)
  local _, tier = Tiers.split(s)
  return tier or Tiers.DEFAULT
end

--- `base` in tier `tier`: "gun-uzi" + "rare" = "gun-uzi@rare"; common
--- (or nil) leaves it as it is.
function Tiers.join(base, tier)
  if not tier or tier == Tiers.DEFAULT then
    return base
  end
  return base .. Tiers.SEP .. tier
end

--- Does `item` come in tiers (a gun, an ability, armor, clothes)?
function Tiers.tiered(item)
  local base = Tiers.base(item)
  for _, p in ipairs(Tiers.prefixes) do
    if base:sub(1, #p) == p then
      return true
    end
  end
  return false
end

--- Is stat number `i` of an item improved in tier `tier`?
function Tiers.improves(tier, i)
  return i <= Tiers.get(tier).upgrades
end

--- `value` of stat `path` improved by `boost`.
local function improve(path, value, boost)
  local field = path:match("([^%.]+)$")
  if LOWER[field] then
    value = value / boost
  else
    value = value * boost
  end
  if WHOLE[field] then
    value = math.floor(value + 0.5)
  end
  return value
end

--- A clothes multiplier `m` (x1.15 speed, x0.7 sprint cost) in tier
--- `tier` when it is stat number `i`: its bonus over 1 grown by the tier's.
function Tiers.multiplier(m, tier, i)
  if not Tiers.improves(tier, i) then
    return m
  end
  return 1 + (m - 1) * Tiers.get(tier).bonus
end

local cache = setmetatable({}, { __mode = "k" }) -- base -> tier key -> tuned table

--- `base` (a gun, an ability, a vest) in tier `tier`: a table that reads
--- like `base` but for the stats the tier improves, `stats` of them in
--- order (`base.tierStats` when left out). A path with a dot ("blast.damage")
--- reaches into a table of `base`'s, copied first. Common is `base` itself.
--- Every tuned table has `tier` and `base`; the same one comes back every
--- time, so it can be compared.
function Tiers.apply(base, tier, stats)
  local t = Tiers.get(tier)
  stats = stats or base.tierStats
  if t.upgrades == 0 or not stats then
    return base
  end
  local byTier = cache[base]
  if not byTier then
    byTier = {}
    cache[base] = byTier
  end
  if byTier[t.key] then
    return byTier[t.key]
  end
  local tuned = setmetatable({ tier = t.key, base = base }, { __index = base })
  for i, path in ipairs(stats) do
    if i > t.upgrades then
      break
    end
    local outer, field = path:match("^([^%.]+)%.([^%.]+)$")
    if outer and type(base[outer]) == "table" then
      if rawget(tuned, outer) == nil then
        local copy = {}
        for k, v in pairs(base[outer]) do
          copy[k] = v
        end
        tuned[outer] = copy
      end
      if type(tuned[outer][field]) == "number" then
        tuned[outer][field] = improve(path, tuned[outer][field], t.boost)
      end
    elseif type(base[path]) == "number" then
      tuned[path] = improve(path, base[path], t.boost)
    end
  end
  byTier[t.key] = tuned
  return tuned
end

--- What stat `path` is called on a card; `labels` (optional) overrides.
function Tiers.label(path, labels)
  return labels and labels[path] or LABELS[path] or path
end

--- The stats tier `tier` improves out of `stats`, as a line for a card:
--- "+15% cooldown", "+25% cooldown, range", "+35% all". Nil for common.
--- `clothes`: the stats are multipliers, and it is their bonus that grows.
--- `labels` names stats where the usual names won't do.
function Tiers.describe(stats, tier, clothes, labels)
  local t = Tiers.get(tier)
  if t.upgrades == 0 or not stats or #stats == 0 then
    return nil
  end
  local names = {}
  for i, path in ipairs(stats) do
    if i <= t.upgrades then
      names[#names + 1] = Tiers.label(path, labels)
    end
  end
  local what = (#names == #stats and #stats > 1) and "all" or table.concat(names, ", ")
  local by = clothes and t.bonus or t.boost
  return ("+%d%% %s"):format(math.floor((by - 1) * 100 + 0.5), what)
end

--- A box `w` x `h` at (x, y) in tier `tier`'s colour: a wash inside, an
--- outline and a band along the bottom. `alpha` dims it (a slot being dragged
--- out of). Every card, slot and box that holds equipment draws one.
function Tiers.drawFrame(tier, x, y, w, h, alpha)
  local c = Tiers.color(tier)
  alpha = alpha or 1
  love.graphics.setColor(c[1], c[2], c[3], 0.12 * alpha)
  love.graphics.rectangle("fill", x, y, w, h, 6)
  love.graphics.setColor(c[1], c[2], c[3], 0.9 * alpha)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, 6)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("fill", x + 6, y + h - 4, w - 12, 2)
end

--- A readable name for `name` in tier `tier`: "rare uzi"; commons keep theirs.
function Tiers.named(name, tier)
  if not tier or tier == Tiers.DEFAULT then
    return name
  end
  return tier .. " " .. name
end

return Tiers
