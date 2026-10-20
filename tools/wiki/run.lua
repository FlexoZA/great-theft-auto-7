-- The game's wiki (docs/wiki): pages written from the game's own code, so
-- the numbers on them are the numbers in play.
--
--   luajit tools/wiki/run.lua            write docs/wiki
--   luajit tools/wiki/run.lua --check    say which pages are out of date (exit 1), write nothing
--
-- Enemies: every feature that has enemies answers `wikiEnemies(add)`
-- (docs/features.md) with one entry per enemy, its numbers read off the
-- feature's own constants. Their portraits come from tools/wiki/portraits
-- (`make wiki-portraits`), which draws each enemy with its feature's own
-- drawing code. See docs/wiki.md.

package.path = "./?.lua;./?/init.lua;" .. package.path

local Pages = require("tools.wiki.pages")

local check = false
for _, a in ipairs(arg) do
  if a == "--check" then
    check = true
  else
    io.stderr:write("wiki: unknown option " .. a .. "\n")
    os.exit(2)
  end
end

local function quiet(fn)
  -- The game prints as it loads; the wiki's own output is what matters here.
  local print_ = print
  print = function() end -- luacheck: ignore 121
  local ok, a, b = pcall(fn)
  print = print_ -- luacheck: ignore 121
  if not ok then
    error(a, 0)
  end
  return a, b
end

local Harness = require("tools.audit.harness")
local game, err = quiet(Harness.boot)
if not game then
  io.stderr:write("wiki: " .. tostring(err) .. "\n")
  os.exit(2)
end

local files, problems = Pages.build(game.Features)
for _, p in ipairs(problems) do
  io.stderr:write("wiki: " .. p .. "\n")
end
if #problems > 0 then
  os.exit(1)
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local s = f:read("*a")
  f:close()
  return s
end

local stale = {}
for _, file in ipairs(files) do
  if read(file.path) ~= file.text then
    stale[#stale + 1] = file.path
    if not check then
      os.execute(("mkdir -p '%s'"):format(file.path:match("^(.*)/")))
      local f = assert(io.open(file.path, "wb"))
      f:write(file.text)
      f:close()
    end
  end
end

-- Pages of enemies that are gone.
local wanted = {}
for _, file in ipairs(files) do
  wanted[file.path] = true
end
for path in io.popen("ls " .. Pages.ENEMIES .. "/*.md 2>/dev/null"):lines() do
  if not wanted[path] then
    stale[#stale + 1] = path .. " (no such enemy any more)"
    if not check then
      os.remove(path)
    end
  end
end

if check then
  if #stale > 0 then
    print("wiki: out of date (run `make wiki`):")
    for _, p in ipairs(stale) do
      print("  " .. p)
    end
    os.exit(1)
  end
  print(("wiki: %d pages up to date"):format(#files))
else
  print(("wiki: %d pages, %d written"):format(#files, #stale))
  for _, missing in ipairs(Pages.missingPortraits(files)) do
    print("wiki: no portrait yet for " .. missing .. " (make wiki-portraits)")
  end
end
os.exit(0)
