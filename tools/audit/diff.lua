-- What this branch changes, read from git: the files touched and, for each,
-- the lines added (with their line numbers in the new file). The base is
-- where the branch left `origin/staging` (the merge base), and uncommitted
-- and untracked files count too, so a local run sees work in progress.

local Diff = {}

local function run(cmd)
  local pipe = io.popen(cmd .. " 2>/dev/null")
  if not pipe then
    return ""
  end
  local out = pipe:read("*a") or ""
  pipe:close()
  return out
end
Diff.run = run

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- The commit to compare against: the merge base of HEAD and `base`
--- (a ref, "origin/staging" by default). Nil when git can't tell.
function Diff.mergeBase(base)
  local sha = trim(run("git merge-base HEAD " .. base))
  if sha == "" then
    return nil
  end
  return sha
end

function Diff.currentBranch()
  local name = trim(run("git rev-parse --abbrev-ref HEAD"))
  if name == "HEAD" or name == "" then
    name = os.getenv("GITHUB_HEAD_REF") or name
  end
  return name
end

--- Every file the branch changes against `sha`, with its added lines:
--- { [path] = { status = "A"|"M"|"D"|"R", added = { [lineNo] = text }, addedCount, removedCount } }
function Diff.read(sha)
  local files = {}
  local function file(path)
    files[path] = files[path] or { status = "M", added = {}, addedCount = 0, removedCount = 0 }
    return files[path]
  end

  for line in run("git diff --name-status -M " .. sha):gmatch("[^\n]+") do
    local status, a, b = line:match("^(%a)%d*\t([^\t]+)\t?(.*)$")
    if status then
      local path = (b ~= "" and b) or a
      file(path).status = status
    end
  end

  local current, newLine = nil, 0
  for line in (run("git diff -U0 --no-color --no-ext-diff -M " .. sha) .. "\n"):gmatch("(.-)\n") do
    local path = line:match("^%+%+%+ b/(.+)$")
    if path then
      current = file(path)
    elseif line:match("^%+%+%+ /dev/null") then
      current = nil
    elseif line:match("^@@") then
      local start = line:match("^@@ %-%d+,?%d* %+(%d+)")
      newLine = tonumber(start) or 0
    elseif current and line:sub(1, 1) == "+" then
      current.added[newLine] = line:sub(2)
      current.addedCount = current.addedCount + 1
      newLine = newLine + 1
    elseif current and line:sub(1, 1) == "-" and not line:match("^%-%-%- ") then
      current.removedCount = current.removedCount + 1
    end
  end

  -- Untracked files are wholly new. A nested checkout (a worktree inside
  -- this one) is listed as a folder: not a file, and not this branch's.
  for path in run("git ls-files --others --exclude-standard"):gmatch("[^\n]+") do
    local f = not path:match("/$") and io.open(path, "r")
    if f and select(2, f:read(0)) then
      f:close()
      f = nil
    end
    if f then
      local entry = file(path)
      entry.status = "A"
      local n = 0
      for text in f:lines() do
        n = n + 1
        entry.added[n] = text
      end
      entry.addedCount = n
      f:close()
    end
  end
  return files
end

--- The lines of `path` as they are now, or nil.
function Diff.lines(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local lines = {}
  for text in f:lines() do
    lines[#lines + 1] = text
  end
  f:close()
  return lines
end

--- The feature a path belongs to ("weapons" for src/features/weapons/x.lua), or nil.
function Diff.featureOf(path)
  return path:match("^src/features/([^/]+)/")
end

return Diff
