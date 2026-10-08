-- The game's version and changelog, both read from CHANGELOG.md at the
-- repository root (packaged into the .love by `make build`), so there is one
-- place to bump. The file follows Keep a Changelog:
--
--   ## [Unreleased]
--   ### Added
--   - A line for players, which may carry on
--     over indented lines.
--   ## [0.1.0] - 2026-09-30
--   Free text under a release is its summary.
--
-- Version.current is the newest numbered release. While [Unreleased] has
-- lines (a staging build) the label reads "0.1.0-dev".

local Version = {}

local FILE = "CHANGELOG.md"

local function readFile()
  if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(FILE) then
    return love.filesystem.read(FILE)
  end
  local f = io.open(FILE, "r")
  if not f then
    return nil
  end
  local text = f:read("*a")
  f:close()
  return text
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Parse changelog text into releases, newest first:
--- { { version=, date=, unreleased=, summary=, sections = { { title=, items = { "..." } } } } }
function Version.parse(text)
  local releases = {}
  local release, section, item
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local heading = line:match("^##%s+(.*)$")
    local sub = line:match("^###%s+(.*)$")
    if sub and release then
      section = { title = trim(sub), items = {} }
      table.insert(release.sections, section)
      item = nil
    elseif heading then
      local name = heading:match("%[(.-)%]") or trim(heading)
      release = {
        version = name,
        date = heading:match("(%d%d%d%d%-%d%d%-%d%d)"),
        unreleased = name:lower() == "unreleased",
        sections = {},
      }
      table.insert(releases, release)
      section, item = nil, nil
    elseif release then
      local bullet = line:match("^[-*]%s+(.*)$")
      if bullet then
        if not section then
          section = { title = "", items = {} }
          table.insert(release.sections, section)
        end
        table.insert(section.items, trim(bullet))
        item = #section.items
      elseif line:match("^%s+%S") and item then
        section.items[item] = section.items[item] .. " " .. trim(line)
      elseif line:match("%S") and not line:match("^%[.-%]:") then
        release.summary = (release.summary and release.summary .. " " or "") .. trim(line)
        item = nil
      else
        item = nil
      end
    end
  end
  return releases
end

--- Does a release have anything to say?
function Version.hasItems(release)
  for _, s in ipairs(release.sections) do
    if #s.items > 0 then
      return true
    end
  end
  return false
end

function Version.load(text)
  text = text or readFile() or ""
  Version.releases = Version.parse(text)
  Version.current = "0.0.0"
  Version.dev = false
  for _, r in ipairs(Version.releases) do
    if r.unreleased then
      Version.dev = Version.dev or Version.hasItems(r)
    else
      Version.current = r.version
      break
    end
  end
  Version.label = Version.current .. (Version.dev and "-dev" or "")
end

Version.load()

return Version
