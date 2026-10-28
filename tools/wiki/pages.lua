-- What tools/wiki/run.lua writes: the wiki's pages, as text, from the
-- features' `wikiEnemies` entries (docs/features.md, docs/wiki.md), and the
-- guns' and abilities' pages (tools/wiki/items.lua).

local Pages = {}

Pages.ROOT = "docs/wiki"
Pages.ENEMIES = "docs/wiki/enemies"
Pages.IMAGES = "docs/wiki/enemies/img"

local Items = require("tools.wiki.items")

local NOTICE = "<!-- Written by tools/wiki/run.lua from the game's code (`make wiki`): "
  .. "change the game, not this page. -->"

-- The story arcs the index is grouped by, keyed by the feature a quest
-- names as its `boss`. Enemies on no quest are the city's.
local ARCS = {
  karen = "Karen's Cul-de-sac",
  ["alien-hunt"] = "Whispering Pines",
  ["d-day"] = "D-Day",
  shotgun = "Shotgun's Bluff",
  ["a-man"] = "A-Man",
  ["cyber-feud"] = "Cyber Feud",
  ["eternal-mood"] = "Eternal Mood",
}
local CITY = "The city"

-- Every folder of pages, for run.lua to clear out pages of things that are gone.
Pages.DIRS = { Pages.ENEMIES }
for _, s in ipairs(Items.SECTIONS) do
  Pages.DIRS[#Pages.DIRS + 1] = s.dir
end

--- An entry's page name: its own `id`, or its kind with the slash a dash.
function Pages.id(entry)
  return entry.id or (entry.kind:gsub("/", "-"))
end

local function nonEmpty(s)
  return type(s) == "string" and s:match("%S") ~= nil
end

--- Every feature's entries, checked. Returns entries, problems.
function Pages.collect(Features)
  local entries, problems, seen = {}, {}, {}
  for _, feature in ipairs(Features.list) do
    if feature.wikiEnemies then
      local name = feature.name or "?"
      local ok, err = pcall(feature.wikiEnemies, feature, function(e)
        local where = ("%s's wikiEnemies"):format(name)
        if type(e) ~= "table" or type(e.kind) ~= "string" or not e.kind:match("^[%w-]+/[%w-]+$") then
          problems[#problems + 1] = where .. ": an entry without a kind like \"feature/what\""
          return
        end
        local id = Pages.id(e)
        where = ("%s (%s)"):format(where, id)
        for _, field in ipairs({ "name", "about", "where" }) do
          if not nonEmpty(e[field]) then
            problems[#problems + 1] = ("%s: no %s"):format(where, field)
          end
        end
        if seen[id] then
          problems[#problems + 1] = ("%s: the page %s is %s's already"):format(where, id, seen[id])
          return
        end
        seen[id] = name
        e.feature = name
        entries[#entries + 1] = e
      end)
      if not ok then
        problems[#problems + 1] = ("%s's wikiEnemies failed: %s"):format(name, tostring(err))
      end
    end
  end
  return entries, problems
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
  end
  return f ~= nil
end

local function portrait(entry)
  return ("%s/%s.png"):format(Pages.IMAGES, Pages.id(entry))
end

--- Numbers as a person writes them: 12, 0.5, 1.25, never 0.30000000004.
local function num(v)
  if type(v) ~= "number" then
    return tostring(v)
  end
  if v == math.floor(v) then
    return ("%d"):format(v)
  end
  return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
end
Pages.num = num

-- Arcs in the order their quests come on the job board, the city first.
local function arcs(Features)
  local quests = Features.byName.quests
  local order, rank, questArc = { CITY }, { [CITY] = 1 }, {}
  for _, q in ipairs(quests and quests.list or {}) do
    if q.boss and not q.returns then
      local arc = ARCS[q.boss] or q.boss
      questArc[q.id] = arc
      if not rank[arc] then
        order[#order + 1] = arc
        rank[arc] = #order
      end
    end
  end
  return order, rank, questArc
end

local function arcOf(entry, questArc)
  return entry.quests and entry.quests[1] and questArc[entry.quests[1]] or CITY
end

local function pct(share)
  return ("%d%%"):format(math.floor(share * 100 + 0.5))
end

--- How an entry's numbers change in play (src/features/bosses), in a
--- sentence: bosses grow with the players, everything on a quest with the
--- times it has been finished before. `entry.scaling` is "boss", "enemy" or
--- "none"; by default a boss's is "boss" and anything on a quest "enemy".
local function scaling(entry)
  local Bosses = require("src.features.bosses")
  local r = Bosses.rage
  local how = entry.scaling or (entry.boss and "boss") or (entry.quests and "enemy") or "none"
  local onQuest = entry.quests ~= nil
  if how == "boss" then
    local s = "Health is for one player: it is multiplied by the number of players."
    if onQuest then
      s = s .. (" Each time the job has been finished before (up to %d), it has %s more health and hits %s harder.")
        :format(r.max, pct(r.health), pct(r.damage))
    end
    return s
  elseif how == "enemy" then
    return ("Numbers are for a job nobody has finished yet. Each time it has been finished before (up to %d), "
      .. "this enemy has %s more health and hits %s harder."):format(r.max, pct(r.enemyHealth), pct(r.enemyDamage))
  end
  return nil
end

local function page(entry, arc)
  local out = {}
  local function add(s)
    out[#out + 1] = s or ""
  end
  add(NOTICE)
  add()
  add("# " .. entry.name)
  add()
  add(("[Wiki](../README.md) / [Enemies](README.md) / %s"):format(arc))
  add()
  if fileExists(portrait(entry)) then
    add(("<img src=\"img/%s.png\" alt=\"%s\" width=\"240\">"):format(Pages.id(entry), entry.name))
    add()
  end
  add(entry.about)
  add()
  add("| | |")
  add("|---|---|")
  add(("| **Where** | %s |"):format(entry.where))
  if entry.boss then
    add("| **Rank** | Boss |")
  end
  for _, stat in ipairs(entry.stats or {}) do
    local value = num(stat[2]) .. (stat[3] and (" " .. stat[3]) or "")
    add(("| **%s** | %s |"):format(stat[1], value))
  end
  if entry.drops then
    local links = {}
    for _, item in ipairs(entry.dropsItems or {}) do
      local path, name = Items.link(item)
      if path then
        links[#links + 1] = ("[%s](%s)"):format(name, path)
      end
    end
    local also = #links > 0 and (" (%s)"):format(table.concat(links, ", ")) or ""
    add(("| **Drops** | %s%s |"):format(entry.drops, also))
  end
  add()
  if entry.weapons and #entry.weapons > 0 then
    add("## Weapons")
    add()
    for _, w in ipairs(entry.weapons) do
      add(("- **%s**: %s"):format(w[1], w[2]))
    end
    add()
  end
  if entry.abilities and #entry.abilities > 0 then
    add("## Abilities")
    add()
    for _, a in ipairs(entry.abilities) do
      add("- " .. a)
    end
    add()
  end
  if entry.tips and #entry.tips > 0 then
    add("## How to beat it")
    add()
    for _, t in ipairs(entry.tips) do
      add("- " .. t)
    end
    add()
  end
  local note = scaling(entry)
  if note then
    add("---")
    add()
    add("_" .. note .. "_")
    add()
  end
  return table.concat(out, "\n")
end

local function health(entry)
  for _, stat in ipairs(entry.stats or {}) do
    if stat[1] == "Health" then
      return num(stat[2])
    end
  end
  return "-"
end

local function index(entries, order, questArc)
  local out = {}
  local function add(s)
    out[#out + 1] = s or ""
  end
  add(NOTICE)
  add()
  add("# Enemies")
  add()
  add("[Wiki](../README.md) / Enemies")
  add()
  add("Everyone and everything in the game that fights back, by where you meet them. Bosses are in **bold**.")
  add()
  for _, arc in ipairs(order) do
    local here = {}
    for _, e in ipairs(entries) do
      if arcOf(e, questArc) == arc then
        here[#here + 1] = e
      end
    end
    if #here > 0 then
      add("## " .. arc)
      add()
      add("| | Enemy | Health | Where |")
      add("|---|---|---|---|")
      for _, e in ipairs(here) do
        local id = Pages.id(e)
        local img = fileExists(portrait(e)) and ("<img src=\"img/%s.png\" width=\"48\">"):format(id) or ""
        local name = e.boss and ("**[%s](%s.md)**"):format(e.name, id) or ("[%s](%s.md)"):format(e.name, id)
        add(("| %s | %s | %s | %s |"):format(img, name, health(e), e.where))
      end
      add()
    end
  end
  return table.concat(out, "\n")
end

local function home()
  return table.concat({
    NOTICE,
    "",
    "# Great Theft Auto 7 wiki",
    "",
    "What's in the game, written from the game's own code, so the numbers here are the numbers in play.",
    "",
    "- [Enemies](enemies/README.md): everyone who fights back, with what they carry and what they can do.",
    "- [Weapons](weapons/README.md): every gun, its numbers in each tier, its price and who drops it.",
    "- [Abilities](abilities/README.md): every ability, its numbers in each tier, its price and who drops it.",
    "",
  }, "\n")
end

--- Every page of the wiki: a list of { path, text }, and the problems found.
function Pages.build(Features)
  local entries, problems = Pages.collect(Features)
  local order, rank, questArc = arcs(Features)
  -- By arc, then as the features list them.
  for i, e in ipairs(entries) do
    e.order = i
  end
  table.sort(entries, function(a, b)
    local ra, rb = rank[arcOf(a, questArc)], rank[arcOf(b, questArc)]
    if ra ~= rb then
      return ra < rb
    end
    return a.order < b.order
  end)
  local files = {
    { path = Pages.ROOT .. "/README.md", text = home() },
    { path = Pages.ENEMIES .. "/README.md", text = index(entries, order, questArc) },
  }
  for _, e in ipairs(entries) do
    files[#files + 1] = { path = ("%s/%s.md"):format(Pages.ENEMIES, Pages.id(e)), text = page(e, arcOf(e, questArc)),
      entry = e }
  end
  local itemFiles, itemProblems = Items.build(entries, {
    notice = NOTICE,
    arcOf = function(e)
      return arcOf(e, questArc)
    end,
  }, Pages.id)
  for _, f in ipairs(itemFiles) do
    files[#files + 1] = f
  end
  for _, p in ipairs(itemProblems) do
    problems[#problems + 1] = p
  end
  return files, problems
end

--- The enemies and items among `files` that have no picture yet.
function Pages.missingPortraits(files)
  local missing = {}
  for _, f in ipairs(files) do
    if f.entry and f.entry.portrait ~= false and not fileExists(portrait(f.entry)) then
      missing[#missing + 1] = Pages.id(f.entry)
    elseif f.item and not fileExists(f.item.image) then
      missing[#missing + 1] = f.item.item
    end
  end
  return missing
end

return Pages
