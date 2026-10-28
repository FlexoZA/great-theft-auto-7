-- The wiki's equipment pages (docs/wiki.md): a page per gun and per
-- ability, and an index of each, written by tools/wiki/pages.lua.
--
-- Nothing here is typed in: every gun is weapons/guns.lua's, every ability
-- abilities/kinds.lua's, and their numbers are the rows the shop's side
-- panel shows (shop/details.lua) in each tier (Tiers.apply), with the
-- shop's prices (shop/catalog.lua). Where an item is won from comes from the
-- enemies' `wikiEnemies` entries: an entry's `dropsItems` lists the items
-- it drops ("gun-uzi", "ability-teleport"), and the item's page links back
-- to the enemy's.

-- The game's modules, required the first time one is used: tools/wiki/pages.lua
-- loads this before the harness has booted the game (and put `love` there).
local Guns, AbilityKinds, Catalog, Details, Tiers
local function load()
  if not Guns then
    Guns = require("src.features.weapons.guns")
    AbilityKinds = require("src.features.abilities.kinds")
    Catalog = require("src.features.shop.catalog")
    Details = require("src.features.shop.details")
    Tiers = require("src.features.tiers")
  end
end

local Items = {}

-- One per kind of equipment the wiki covers. `item` is the inventory item
-- of one ("gun-uzi"); `get` the items in order, as { key, name, base }.
Items.SECTIONS = {
  {
    key = "weapons",
    title = "Weapons",
    prefix = "gun-",
    about = "Every gun a player can carry: what it does in each tier, what it costs and where it is won.",
    get = function()
      local out = {}
      for i, g in ipairs(Guns.list) do
        out[#out + 1] = { key = g.key, name = g.name, base = g, first = i == Guns.DEFAULT }
      end
      return out
    end,
  },
  {
    key = "abilities",
    title = "Abilities",
    prefix = "ability-",
    about = "Every ability a player can slot: what it does in each tier, what it costs and where it is won.",
    get = function()
      local out = {}
      for _, a in ipairs(AbilityKinds.list) do
        out[#out + 1] = { key = a.key, name = a.title, base = a }
      end
      return out
    end,
  },
}

for _, s in ipairs(Items.SECTIONS) do
  s.dir = "docs/wiki/" .. s.key
  s.images = s.dir .. "/img"
end

--- "Uzi", "SMG": a name to head a page with.
local function title(name)
  return (name:gsub("^%l", string.upper))
end

--- Every item of every section, each with its `section`, `item`, `page`
--- (the .md path) and `image` (the .png path).
function Items.all()
  load()
  local out = {}
  for _, s in ipairs(Items.SECTIONS) do
    for _, it in ipairs(s.get()) do
      it.section = s
      it.item = s.prefix .. it.key
      it.page = ("%s/%s.md"):format(s.dir, it.key)
      it.image = ("%s/%s.png"):format(s.images, it.key)
      out[#out + 1] = it
    end
  end
  return out
end

--- The shop's entry for item `it`, or one standing in for it when the shop
--- never sells it (a boss's ability), so its numbers read the same.
local function shopEntry(it)
  return Catalog.byItem[it.item], { item = it.item, kind = it.section.key == "weapons" and "gun" or "ability",
    tiered = true }
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
  end
  return f ~= nil
end

--- The rows of `it` in every tier: { labels = {...}, tiers = { [tier] = { label = row } } }.
local function tierRows(it)
  local sold, standIn = shopEntry(it)
  local entry = sold or standIn
  local out = { labels = {}, byTier = {} }
  for _, t in ipairs(Tiers.list) do
    local d = Details.of(entry, t.key)
    local rows = {}
    for _, r in ipairs(d.rows) do
      rows[r.label] = r
      if t.key == Tiers.DEFAULT then
        out.labels[#out.labels + 1] = r.label
      end
    end
    out.byTier[t.key] = rows
    if t.key == Tiers.DEFAULT then
      out.blurb, out.use = d.blurb, d.use
    end
  end
  return out
end

local function fcks(n)
  return ("%d Fcks"):format(math.floor(n + 0.5))
end

--- How a player gets `it`, as sentences.
local function howToGet(it)
  local sold = Catalog.byItem[it.item]
  local out = {}
  if it.first then
    out[#out + 1] = "Everyone starts with one."
  end
  if sold and sold.unlock then
    out[#out + 1] = "Won first: once you have picked one up, the shop sells it to you, in every tier."
  elseif sold then
    out[#out + 1] = ("In the shop, in every tier: %s for a common one."):format(fcks(sold.price))
  else
    out[#out + 1] = "Never in the shop: only won."
  end
  return out
end

--- One gun's or ability's page.
local function page(it, ctx)
  local s = it.section
  local rows = tierRows(it)
  local out = {}
  local function add(line)
    out[#out + 1] = line or ""
  end
  add(ctx.notice)
  add()
  add("# " .. title(it.name))
  add()
  add(("[Wiki](../README.md) / [%s](README.md) / %s"):format(s.title, title(it.name)))
  add()
  if fileExists(it.image) then
    add(("<img src=\"img/%s.png\" alt=\"%s\" width=\"%d\">"):format(it.key, it.name,
      s.key == "weapons" and 320 or 160))
    add()
  end
  add(rows.blurb)
  add()
  add("**How to use it:** " .. rows.use)
  add()

  local facts = {}
  local b = it.base
  if s.key == "weapons" then
    facts[#facts + 1] = { "Damage type", b.damageType or "bullet" }
    if b.blast then
      facts[#facts + 1] = { "Blast type", b.blast.type or "explosive" }
    end
  else
    facts[#facts + 1] = { "Kind", b.passive and "passive (works from the passive slot)" or "active (a key)" }
    if b.onFoot then
      facts[#facts + 1] = { "Works", "on foot only" }
    end
    if b.modes then
      local names = {}
      for _, m in ipairs(b.modes) do
        names[#names + 1] = m.title
      end
      facts[#facts + 1] = { "Modes", table.concat(names, ", ") }
    end
  end
  add("| | |")
  add("|---|---|")
  for _, f in ipairs(facts) do
    add(("| **%s** | %s |"):format(f[1], f[2]))
  end
  add()

  add("## Stats by tier")
  add()
  local head, rule = { "| |" }, { "|---" }
  for _, t in ipairs(Tiers.list) do
    head[#head + 1] = " " .. title(t.title) .. " |"
    rule[#rule + 1] = "|---"
  end
  add(table.concat(head))
  add(table.concat(rule) .. "|")
  for _, label in ipairs(rows.labels) do
    local line = { ("| **%s** |"):format(label) }
    for _, t in ipairs(Tiers.list) do
      local r = rows.byTier[t.key][label]
      local v = r and r.value or "-"
      line[#line + 1] = (r and r.lit) and (" **%s** |"):format(v) or (" %s |"):format(v)
    end
    add(table.concat(line))
  end
  local stats = b.tierStats or (s.key == "weapons" and Guns.tierStats) or {}
  local better = { "| **better by** |" }
  for _, t in ipairs(Tiers.list) do
    better[#better + 1] = (" %s |"):format(Tiers.describe(stats, t.key, false, b.tierLabels) or "-")
  end
  add(table.concat(better))
  local sold = Catalog.byItem[it.item]
  if sold then
    local price = { "| **price** |" }
    for _, t in ipairs(Tiers.list) do
      price[#price + 1] = (" %s |"):format(fcks(Catalog.price(sold, t.key)))
    end
    add(table.concat(price))
  end
  add()
  add("_What a tier improves is in **bold**._")
  add()

  add("## How to get it")
  add()
  for _, line in ipairs(howToGet(it)) do
    add("- " .. line)
  end
  for _, d in ipairs(ctx.droppers[it.item] or {}) do
    add(("- Dropped by [%s](../enemies/%s.md) (%s): %s."):format(d.entry.name, d.id, d.arc,
      d.entry.drops or "when it goes down"))
  end
  add()
  return table.concat(out, "\n")
end

--- The value of row `labels` (the first there is) of `it` in common.
local function common(rows, ...)
  for _, label in ipairs({ ... }) do
    local r = rows.byTier[Tiers.DEFAULT][label]
    if r then
      return r.value
    end
  end
  return "-"
end

local function shortGet(it, ctx)
  local sold = Catalog.byItem[it.item]
  local won = ctx.droppers[it.item] and #ctx.droppers[it.item] > 0
  if sold and not sold.unlock then
    return fcks(sold.price) .. (won and ", or won" or "")
  elseif sold then
    return "won, then " .. fcks(sold.price)
  end
  return "won"
end

local WORDS = { "one", "two", "three", "four", "five" }

--- How the tiers work, in a paragraph, from Tiers.list.
local function tiersNote()
  local parts = {}
  for _, t in ipairs(Tiers.list) do
    if t.upgrades > 0 then
      local which = t.upgrades == math.huge and "every stat" or t.upgrades == 1 and "its first stat"
        or ("its first %s stats"):format(WORDS[t.upgrades] or t.upgrades)
      parts[#parts + 1] = ("%s improves %s by %d%% and costs %g times as much"):format(title(t.title), which,
        math.floor((t.boost - 1) * 100 + 0.5), t.price)
    end
  end
  return "Everything comes in four tiers. " .. table.concat(parts, "; ") .. ". Each page lists the stats in the order "
    .. "a tier improves them."
end

local function index(s, items, ctx)
  local out = {}
  local function add(line)
    out[#out + 1] = line or ""
  end
  add(ctx.notice)
  add()
  add("# " .. s.title)
  add()
  add(("[Wiki](../README.md) / %s"):format(s.title))
  add()
  add(s.about .. " Numbers are for a common one.")
  add()
  add(tiersNote())
  add()
  if s.key == "weapons" then
    add("| | Gun | Damage | Fire rate | Magazine | Get it |")
    add("|---|---|---|---|---|---|")
  else
    add("| | Ability | Kind | Cooldown | Get it |")
    add("|---|---|---|---|---|")
  end
  for _, it in ipairs(items) do
    local rows = tierRows(it)
    local img = fileExists(it.image) and ("<img src=\"img/%s.png\" width=\"%d\">"):format(it.key,
      s.key == "weapons" and 96 or 48) or ""
    local name = ("[%s](%s.md)"):format(title(it.name), it.key)
    if s.key == "weapons" then
      add(("| %s | %s | %s | %s | %s | %s |"):format(img, name, common(rows, "damage", "blast damage"),
        common(rows, "fire rate"), common(rows, "magazine", "tank"), shortGet(it, ctx)))
    else
      add(("| %s | %s | %s | %s | %s |"):format(img, name, it.base.passive and "passive" or "active",
        common(rows, "cooldown", "rest"), shortGet(it, ctx)))
    end
  end
  add()
  return table.concat(out, "\n")
end

--- The equipment pages, given the enemies' entries (`entries`, checked by
--- Pages.collect). `ctx` has `notice` and `arcOf(entry)`. Returns files
--- (each { path, text, item }) and problems.
function Items.build(entries, ctx, idOf)
  load()
  local items = Items.all()
  local byItem = {}
  for _, it in ipairs(items) do
    byItem[it.item] = it
  end
  local problems, droppers = {}, {}
  for _, e in ipairs(entries) do
    for _, item in ipairs(e.dropsItems or {}) do
      local base = Tiers.base(item)
      if not byItem[base] then
        problems[#problems + 1] = ("%s's wikiEnemies (%s): dropsItems names %s, which has no wiki page")
          :format(e.feature, idOf(e), tostring(item))
      else
        droppers[base] = droppers[base] or {}
        table.insert(droppers[base], { entry = e, id = idOf(e), arc = ctx.arcOf(e) })
      end
    end
  end
  ctx.droppers = droppers
  local files = {}
  for _, s in ipairs(Items.SECTIONS) do
    local here = {}
    for _, it in ipairs(items) do
      if it.section == s then
        here[#here + 1] = it
      end
    end
    files[#files + 1] = { path = s.dir .. "/README.md", text = index(s, here, ctx) }
    for _, it in ipairs(here) do
      local sold = Catalog.byItem[it.item]
      if (not sold or sold.unlock) and not it.first and not droppers[it.item] then
        problems[#problems + 1] = ("%s is never in the shop until it is won, and no wikiEnemies entry drops it: "
          .. "add it to its dropper's `dropsItems`"):format(it.item)
      end
      files[#files + 1] = { path = it.page, text = page(it, ctx), item = it }
    end
  end
  return files, problems
end

--- The link to `item`'s page from an enemy's page, and its name; nil for an item without one.
function Items.link(item)
  load()
  local base = Tiers.base(item)
  for _, it in ipairs(Items.all()) do
    if it.item == base then
      return ("../%s/%s.md"):format(it.section.key, it.key), it.name
    end
  end
  return nil
end

return Items
