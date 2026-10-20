-- The wiki (docs/wiki, tools/wiki, docs/wiki.md): its pages are written
-- from the game's code, so a branch that changes an enemy's numbers and
-- doesn't run `make wiki` leaves them wrong, and a new enemy without a
-- `wikiEnemies` entry has no page at all.

local Pages = require("tools.wiki.pages")

local Wiki = {}

local function read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return s
end

--- Entries that don't hold together, and pages that aren't what
--- `make wiki` would write now.
function Wiki.pages(report, Features)
  local files, problems = Pages.build(Features)
  for _, p in ipairs(problems) do
    report:add({ severity = "minor", category = "structure", key = "wiki-entry:" .. p,
      title = "A wiki entry is wrong: " .. p, detail = "See \"Wiki\" in docs/features.md and docs/wiki.md." })
  end
  local stale = {}
  for _, file in ipairs(files) do
    if read(file.path) ~= file.text then
      stale[#stale + 1] = file.path
    end
  end
  if #stale > 0 then
    report:add({ severity = "minor", category = "structure", key = "wiki-stale",
      title = ("%d wiki page(s) out of date"):format(#stale),
      detail = "Run `make wiki` and commit docs/wiki: " .. table.concat(stale, ", ") })
  end
end

--- The enemy kinds the wiki has a page for: { kind = true }.
function Wiki.kinds(Features)
  local kinds = {}
  for _, e in ipairs((Pages.collect(Features))) do
    kinds[e.kind] = true
  end
  return kinds
end

--- An enemy met in play with no page.
function Wiki.unpaged(report, kinds, kind, quest)
  if not kinds[kind] then
    report:add({ severity = "minor", category = "structure", key = "wiki-kind:" .. kind,
      title = ("No wiki page for %s (met on %s)"):format(kind, quest),
      detail = "Its feature's `wikiEnemies(add)` should add one (docs/wiki.md), then `make wiki`." })
  end
end

return Wiki
