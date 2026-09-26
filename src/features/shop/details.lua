-- What the shop's side panel says about a thing for sale: a sentence on
-- what it is like (the `blurb` each gun, ability, armor and piece of
-- clothing carries), how it is used, and a row per number, read off the
-- thing in the tier the panel shows (Tiers.apply), so a rare uzi's rows
-- are the rare uzi's. A row the tier improved is `lit`, and the panel
-- draws it in the tier's colour.
--
-- `Details.of(entry, tier)` gives { blurb, use, rows = { { label, value, lit } } };
-- cars have none of this (the panel shows the vehicle factory's card).

local Features = require("src.features")
local Controls = require("src.controls")
local Guns = require("src.features.weapons.guns")
local AbilityKinds = require("src.features.abilities.kinds")
local ArmorKinds = require("src.features.armor.kinds")
local GearKinds = require("src.features.gear.kinds")
local Kinds = require("src.features.buildings.kinds")
local Tiers = require("src.features.tiers")

local Details = {}

--- "1.2 s", "12 s": seconds without a trailing ".0".
local function secs(v)
  return (("%.1f"):format(v):gsub("%.0$", "")) .. " s"
end

--- `v` rounded to a whole number, as text (a tier's boost leaves 6.75 hp/s).
local function whole(v)
  return ("%d"):format(math.floor(v + 0.5))
end

--- The number at `path` ("damage", "blast.radius") in table `t`.
local function at(t, path)
  local outer, field = path:match("^([^%.]+)%.([^%.]+)$")
  if outer then
    return t[outer] and t[outer][field]
  end
  return t[path]
end

--- Did the tier change `path`: is the tuned table's number not the base's?
local function lit(tuned, base, path)
  return at(tuned, path) ~= at(base, path)
end

local function gun(entry, tier)
  local base = Guns[entry.item:sub(5)]
  local g = Tiers.apply(base, tier)
  local rows = {}
  local function row(label, value, path)
    rows[#rows + 1] = { label = label, value = value, lit = path and lit(g, base, path) }
  end
  if g.blast then
    row("blast damage", whole(g.blast.damage), "blast.damage")
    row("blast radius", whole(g.blast.radius) .. " px", "blast.radius")
  elseif (g.pellets or 1) > 1 then
    row("damage", whole(g.damage) .. (" x %d pellets"):format(g.pellets), "damage")
  else
    row("damage", whole(g.damage), "damage")
  end
  row("fire rate", ("%.1f a second"):format(1 / g.cooldown), "cooldown")
  row("magazine", whole(g.magazine), "magazine")
  row("reload", secs(g.reload), "reload")
  row("scatter", g.spread == 0 and "none" or ("%d degrees"):format(math.floor(math.deg(g.spread) + 0.5)), "spread")
  if g.scope then
    row("scope", ("x%d"):format(g.scope))
  end
  row("ammo", g.bottomless and "never runs out" or Kinds.name("ammo-" .. g.key, 2))
  return { blurb = g.blurb, use = "Drag it into a weapon slot; its number key picks it.", rows = rows }
end

-- How an ability is set off, by its `aim`.
local USE = {
  self = "Press its key: it goes off on you.",
  point = "Press its key, then click where to land.",
  direction = "Press its key, then click to put it down facing the cursor.",
}

-- The numbers an ability's rows can show: label, and how the value reads.
local FIELDS = {
  cooldown = function(v, a) return a.passive and "rest" or "cooldown", secs(v) end,
  seconds = function(v) return "duration", secs(v) end,
  range = function(v) return "reach", whole(v) .. " px" end,
  radius = function(v) return "area", whole(v) .. " px" end,
  rate = function(v, a)
    return a.tierLabels and a.tierLabels.rate or "heal rate", whole(v) .. " " .. (a.rateUnit or "hp/s")
  end,
  delay = function(v) return "starts after", secs(v) end,
  damage = function(v) return "damage", whole(v) end,
  fireEvery = function(v) return "fire rate", ("%d a second"):format(math.floor(1 / v + 0.5)) end,
  ["stats.cooldown"] = function(v) return "cooldowns", ("-%d%%"):format(math.floor((1 - v) * 100 + 0.5)) end,
}

local function ability(entry, tier)
  local base = AbilityKinds.byKey[entry.item:sub(9)]
  local a = Tiers.apply(base, tier)
  local rows, seen = {}, {}
  local function row(path)
    local v, fmt = at(a, path), FIELDS[path]
    if seen[path] or type(v) ~= "number" or (path == "range" and v == 0) then
      return
    end
    seen[path] = true
    local label, value
    if fmt then
      label, value = fmt(v, a)
    else
      label, value = Tiers.label(path, a.tierLabels), ("%g"):format(v)
    end
    rows[#rows + 1] = { label = label, value = value, lit = lit(a, base, path) }
  end
  if not a.stats then
    row("cooldown") -- first, whether a tier improves it or not
  end
  for _, path in ipairs(a.tierStats or {}) do
    row(path)
  end
  local use = a.passive and "Passive: it works from the passive slot, no key." or USE[a.aim]
    or "Hold its key and let go with the cursor where you want it."
  return { blurb = a.blurb, use = use, rows = rows }
end

local function armor(entry, tier)
  local base = ArmorKinds.byKey[entry.item:sub(7)]
  local a = Tiers.apply(base, tier)
  return {
    blurb = a.blurb, use = "Drag it into the armor slot. It breaks when its points are gone.",
    rows = { { label = "soaks up", value = whole(a.points) .. " damage", lit = lit(a, base, "points") } },
  }
end

-- What a clothes multiplier does, as a row: label and how x`m` reads.
local GEAR = {
  speed = function(m) return "on foot", ("%+d%% speed"):format(math.floor((m - 1) * 100 + 0.5)) end,
  stamina = function(m) return "sprinting", ("%+d%% cost"):format(math.floor((m - 1) * 100 + 0.5)) end,
  ammo = function(m) return "ammo bundles", ("%+d%%"):format(math.floor((m - 1) * 100 + 0.5)) end,
  cooldown = function(m) return "cooldowns", ("%+d%%"):format(math.floor((m - 1) * 100 + 0.5)) end,
  armor = function(m) return "armor points", ("%+d%%"):format(math.floor((m - 1) * 100 + 0.5)) end,
}

local function gear(entry, tier)
  local g = GearKinds.byKey[entry.item:sub(6)]
  local rows = { { label = "worn on", value = g.slot } }
  local names = {}
  for name in pairs(g.stats) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local m, improved = g.stats[name], false
    for i, s in ipairs(g.tierStats) do
      if s == name and Tiers.improves(tier, i) then
        m, improved = Tiers.multiplier(m, tier, i), true
      end
    end
    local label, value
    if GEAR[name] then
      label, value = GEAR[name](m)
    else
      label, value = name, ("x%.2f"):format(m)
    end
    rows[#rows + 1] = { label = label, value = value, lit = improved }
  end
  return { blurb = g.blurb, use = "Drag it onto its slot on your body.", rows = rows }
end

local function ammo(entry)
  local g = Guns[entry.item:sub(6)]
  return {
    blurb = ("Rounds for the %s, loaded a magazine at a time when you reload."):format(g.name),
    use = "It goes into your bag; reloading takes from it.",
    rows = {
      { label = "in a box", value = ("%d"):format(entry.n) },
      { label = "fits", value = ("%d in a bag slot"):format(Kinds.stack(entry.item)) },
    },
  }
end

local function supply(entry)
  local b = Features.byName.buildings
  local u = b and b.usableByItem and b.usableByItem[entry.item]
  local rows = {}
  if entry.item == "medkit" then
    rows[#rows + 1] = { label = "heals", value = ("%d hp"):format(b and b.medkitHeal or 0) }
  elseif entry.item == "drink" then
    rows[#rows + 1] = { label = "gives back", value = ("%d stamina"):format(b and b.drinkStamina or 0) }
  end
  if u then
    rows[#rows + 1] = { label = "between uses", value = secs(u.cooldown) }
  end
  local blurb = entry.item == "medkit" and "Patches you up on the spot." or "A can of get-up-and-go for your legs."
  local key = u and Controls.name(Controls.bindings(u.action)[1]) or "its key"
  return { blurb = blurb, use = ("Drag it to its quick slot and press %s."):format(key), rows = rows }
end

local BY_KIND = { gun = gun, ability = ability, armor = armor, gear = gear, ammo = ammo, supply = supply }

--- The side panel's contents for `entry` in tier `tier`, or nil (cars).
function Details.of(entry, tier)
  local fn = BY_KIND[entry.kind]
  return fn and fn(entry, entry.tiered and tier or Tiers.DEFAULT) or nil
end

return Details
