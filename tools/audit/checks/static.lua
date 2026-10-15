-- Checks that read the code: what this branch adds, line by line, plus a
-- few that look over the whole tree (messages, hooks, enemies). Nothing is
-- run here; the game checks (game.lua) play it.
--
-- Every finding on an added line is the branch's own; whole-tree findings
-- are compared with the base run like the game's.

local Diff = require("tools.audit.diff")
local Config = require("tools.audit.config")

local Static = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function indentOf(s)
  return #(s:match("^(%s*)") or "")
end

local function isLua(path)
  return path:match("%.lua$") ~= nil
end

local function isGameCode(path)
  return isLua(path) and (path:match("^src/") or path == "main.lua" or path == "conf.lua")
end

local function isCore(path)
  for _, prefix in ipairs(Config.core) do
    if path == prefix or path:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

local function allLuaFiles()
  local files = {}
  for path in Diff.run("git ls-files 'src/*.lua' main.lua conf.lua"):gmatch("[^\n]+") do
    files[#files + 1] = path
  end
  -- New files of this branch are not in the index yet.
  for path in Diff.run("git ls-files --others --exclude-standard 'src/*.lua'"):gmatch("[^\n]+") do
    files[#files + 1] = path
  end
  return files
end

--- The name of the function a line sits in, and the line it starts on:
--- walk up through ever less indented lines to the first function header.
local function enclosingFunction(lines, n)
  local indent = indentOf(lines[n] or "")
  for i = n - 1, 1, -1 do
    local line = lines[i]
    if trim(line) ~= "" and indentOf(line) < indent then
      local name = line:match("function%s+([%w_.:]+)%s*%(") or line:match("([%w_.]+)%s*=%s*function%s*%(")
      if name then
        return name, i
      end
      indent = indentOf(line)
    end
  end
  return nil
end

--- Where the function starting at line `i` ends (its `end` at the same indent).
local function functionEnd(lines, i)
  local indent = indentOf(lines[i])
  if lines[i]:match("end%s*,?%)?%s*$") and lines[i]:match("function.-%).-end") then
    return i -- a one-liner
  end
  for j = i + 1, #lines do
    local line = lines[j]
    if indentOf(line) == indent and line:match("^%s*end[%s,%)]*$") then
      return j
    end
    if indentOf(line) < indent and trim(line) ~= "" then
      return j - 1
    end
  end
  return #lines
end

-- Hook names: every name the core or a feature raises on every feature,
-- plus what the template lists. A feature's data field must never be one.
local function hookNames(files)
  local names = {}
  for _, path in ipairs(files) do
    local lines = Diff.lines(path) or {}
    local loopsFeatures = false
    for _, line in ipairs(lines) do
      for name in line:gmatch('Features%.%a+%("([%w_]+)"') do
        names[name] = true
      end
      if line:find("Features.list", 1, true) then
        loopsFeatures = true
      end
    end
    if loopsFeatures then
      for _, line in ipairs(lines) do
        for name in line:gmatch("%f[%w]f%.([%a_][%w_]*)") do
          names[name] = true
        end
      end
    end
  end
  for _, line in ipairs(Diff.lines("src/features/_template/init.lua") or {}) do
    local name = line:match("^function %w+:([%w_]+)%(")
    if name then
      names[name] = true
    end
  end
  names.name, names.priority, names.clientMessages, names.serverMessages, names.hookName = nil, nil, nil, nil, nil
  return names
end

-- Commas at the top level of the call opening at `open` (an index of "(").
-- Returns the argument count, or nil when the call does not close on the line.
local function argCount(text, open)
  local depth, args, any = 0, 1, false
  local i = open
  local quote = nil
  while i <= #text do
    local c = text:sub(i, i)
    if quote then
      if c == "\\" then
        i = i + 1
      elseif c == quote then
        quote = nil
      end
    elseif c == '"' or c == "'" then
      quote = c
      any = true
    elseif c == "(" or c == "{" or c == "[" then
      depth = depth + 1
    elseif c == ")" or c == "}" or c == "]" then
      depth = depth - 1
      if depth == 0 then
        return any and args or 0
      end
    elseif c == "," and depth == 1 then
      args = args + 1
    elseif not c:match("%s") then
      any = true
    end
    i = i + 1
  end
  return nil
end

local DAMAGE_CALLS = {
  -- pattern, full argument count (the damage type last), what it is
  { ":serverDamage%(", 6, "serverDamage(server, victim, attacker, amount, angle, type)" },
  { ":damageCar%(", 7, "damageCar(server, car, byId, amount, pid, angle, type)" },
  { ":serverShotAt%(", 8, "serverShotAt(server, x, y, radius, by, angle, damage, type)" },
  { 'Features%.call%("serverBlast"', 8, 'Features.call("serverBlast", server, x, y, radius, damage, by, type)' },
}

local ASSET_MAKERS = {
  "love%.graphics%.newImage",
  "love%.graphics%.newFont",
  "love%.graphics%.newCanvas",
  "love%.graphics%.newShader",
  "love%.graphics%.newMesh",
  "love%.audio%.newSource",
  "love%.image%.newImageData",
  "love%.sound%.newSoundData",
}

local PER_FRAME = { "update", "draw", "drawBelowCars", "drawAboveCars", "drawHUD", "drawScreen", "drawLens",
  "drawVehicle", "serverStep", "predictCar", "think", "step", "drawOnMinimap", "drawNightLights" }

local function perFrame(name)
  if not name then
    return false
  end
  local last = name:match("[%.:]([%w_]+)$") or name
  for _, n in ipairs(PER_FRAME) do
    if last == n then
      return true
    end
  end
  return false
end

--- The local name a feature's init.lua returns ("Weapons").
local function featureTableName(path)
  local lines = Diff.lines(path) or {}
  for i = #lines, 1, -1 do
    local name = lines[i]:match("^return%s+([%a_][%w_]*)%s*$")
    if name then
      return name
    end
  end
  return nil
end

-- What a commented-out line of code looks like (prose rarely does: "x =
-- the speed" has words after the equals sign, code has one token).
local CODE_LINE = {
  "^local%s+[%a_]",
  "^end[%s%),]*$",
  "^if%s.+%sthen$",
  "^for%s.+%sdo$",
  "^while%s.+%sdo$",
  "^return%s",
  "^function[%s%(]",
  "^[%a_][%w_.:]*%b()$",
  "^[%a_][%w_.%[%]\"]*%s*=%s*[^%s]+$",
}

local function looksLikeCode(comment)
  local c = trim(comment)
  for _, pattern in ipairs(CODE_LINE) do
    if c:match(pattern) then
      return true
    end
  end
  return false
end

function Static.run(report, ctx)
  local files = ctx.files
  local changedLua, changedGame = {}, {}
  for path, f in pairs(files) do
    if f.status ~= "D" and isLua(path) then
      changedLua[#changedLua + 1] = path
      if isGameCode(path) then
        changedGame[#changedGame + 1] = path
      end
    end
  end
  table.sort(changedLua)
  table.sort(changedGame)

  local function add(f)
    f.new = true
    return report:add(f)
  end

  -- Lint ---------------------------------------------------------------
  if #changedLua > 0 then
    local out = Diff.run("luacheck --formatter plain --codes --no-color " .. table.concat(changedLua, " "))
    local lintCount = 0
    for line in out:gmatch("[^\n]+") do
      local path, ln, _, code, msg = line:match("^(.-):(%d+):(%d+): %(([EW]%d+)%) (.+)$")
      if path then
        ln = tonumber(ln)
        local entry = files[path]
        if code:sub(1, 1) == "E" then
          add({ severity = "blocker", category = "quality", key = "lint:" .. path .. ":" .. msg,
            title = "Lua error: " .. msg, file = path, line = ln })
        elseif entry and entry.added[ln] then
          lintCount = lintCount + 1
          -- Globals (W11x set/read an undefined one, W12x a read-only one) are
          -- crashes waiting to happen; the rest is tidiness.
          local severity = code:match("^W1[12]%d") and "major" or "minor"
          add({ severity = severity, category = "quality", key = "lint:" .. path .. ":" .. code .. ":" ..
            trim(entry.added[ln]), title = ("luacheck %s: %s"):format(code, msg), file = path, line = ln })
        end
      end
    end
    report:note(("luacheck over %d changed Lua files: %d warnings on added lines"):format(#changedLua, lintCount))
  end

  -- Line by line over what was added -----------------------------------
  local hooks = hookNames(allLuaFiles())
  local leftovers, todos = 0, 0
  for _, path in ipairs(changedGame) do
    local entry = files[path]
    local lines = Diff.lines(path) or {}
    local feature = Diff.featureOf(path)
    local tableName = feature and path:match("/init%.lua$") and featureTableName(path)
    local commentRun, previous = 0, nil
    local addedNumbers = {}
    for n in pairs(entry.added) do
      addedNumbers[#addedNumbers + 1] = n
    end
    table.sort(addedNumbers)

    for _, n in ipairs(addedNumbers) do
      local text = entry.added[n]
      local code = text:gsub("%-%-.*$", "")
      local stripped = trim(text)
      local allowed = text:find("audit: allow", 1, true)
      local function lineKey(kind)
        return kind .. ":" .. path .. ":" .. stripped
      end

      if not allowed then
        -- Leftovers from debugging.
        if code:match("%f[%w_.:]print%s*%(") then
          leftovers = leftovers + 1
          add({ severity = "minor", category = "quality", key = lineKey("print"), file = path, line = n,
            title = "print() left in game code", detail = "Players never see the console; drop it or log on purpose." })
        end
        if code:match("os%.exit%s*%(") or code:match("debug%.debug%s*%(") or code:match("io%.write%s*%(") then
          add({ severity = "major", category = "quality", key = lineKey("debugcall"), file = path, line = n,
            title = "Debugging call left in: " .. stripped })
        end
        local switch = code:gsub("^%s*local%s+", "")
        if switch:match("^%s*[%w_.]*DEBUG%s*=%s*true") or switch:match("^%s*[%w_.]*[Gg]od[Mm]ode%s*=%s*true") then
          add({ severity = "major", category = "quality", key = lineKey("debugflag"), file = path, line = n,
            title = "Debug switch left on: " .. stripped })
        end
        if text:match("%-%-.*%f[%w]TODO%f[%W]") or text:match("%-%-.*%f[%w]FIXME%f[%W]")
          or text:match("%-%-.*%f[%w]HACK%f[%W]") or text:match("%-%-.*%f[%w]XXX%f[%W]") then
          todos = todos + 1
          add({ severity = "minor", category = "quality", key = lineKey("todo"), file = path, line = n,
            title = "Unfinished work marked in a comment", detail = stripped })
        end
        if stripped:match("^pcall%(") then
          add({ severity = "minor", category = "quality", key = lineKey("pcall"), file = path, line = n,
            title = "pcall's result is thrown away: an error here vanishes", detail = stripped })
        end

        -- Commented-out code: three such lines in a row.
        local comment = stripped:match("^%-%-%s?(.*)$")
        if comment and not stripped:match("^%-%-%-") and looksLikeCode(comment) then
          commentRun = previous == n - 1 and commentRun + 1 or 1
          if commentRun == 3 then
            add({ severity = "minor", category = "quality", key = lineKey("deadcode"), file = path, line = n - 2,
              title = "Commented-out code", detail = "Delete it; git remembers." })
          end
        else
          commentRun = 0
        end
        previous = n

        -- Assets made per frame.
        for _, maker in ipairs(ASSET_MAKERS) do
          if code:match(maker) and not code:match("%s+or%s+" .. maker) then
            local fn = enclosingFunction(lines, n)
            local cached = false
            for k = math.max(1, n - 3), n do
              if (lines[k] or ""):match("if%s+not%s") or (lines[k] or ""):match("==%s*nil") then
                cached = true
              end
            end
            if perFrame(fn) and not cached then
              add({ severity = "major", category = "quality", key = lineKey("perframe"), file = path, line = n,
                title = ("%s made every frame in %s"):format(maker:gsub("%%", ""), fn),
                detail = "Assets are made once in load (CLAUDE.md), never per frame." })
            end
          end
        end

        -- Frame-rate dependent motion: x = x + 3 every update.
        local lhs = code:match("^%s*([%w_.%[%]\"]+)%s*=%s*")
        if lhs and not code:find("dt", 1, true) then
          local esc = lhs:gsub("[%.%[%]]", "%%%0")
          local stepped = code:match("=%s*" .. esc .. "%s*[%+%-]%s*%d*%.?%d+%s*$")
          local decayed = code:match("=%s*" .. esc .. "%s*%*%s*0?%.%d+%s*$")
          if stepped or decayed then
            local fn = enclosingFunction(lines, n)
            if fn and (fn:match("[%.:]update$") or fn == "update") then
              add({ severity = "minor", category = "quality", key = lineKey("framerate"), file = path, line = n,
                title = "Changes by a fixed step every frame (no dt)", detail = stripped
                  .. " — at 144 fps this runs 2.4x faster than at 60 (CLAUDE.md: scale by dt)." })
            end
          end
        end

        -- Raw keys instead of Controls.
        if feature and code:match("key%s*==%s*\"[%w%s]+\"") and not code:match("\"escape\"") then
          add({ severity = "minor", category = "structure", key = lineKey("rawkey"), file = path, line = n,
            title = "Raw key test", detail = "Register an action with Controls.register and ask Controls.is "
              .. "(docs/features.md, Key bindings), so players can rebind it." })
        end

        -- Reaching into another feature's files.
        local other = code:match('require%("src%.features%.([%w%-_]+)%.')
        if feature and other and other ~= feature and not Config.sharedFeatures[other] then
          add({ severity = "minor", category = "structure", key = lineKey("reach"), file = path, line = n,
            title = ("Reaches into another feature's files (%s)"):format(other),
            detail = "Features talk through hooks and Features.byName; a shared helper belongs in one place." })
        end

        -- Something that hurts without saying what kind of hurt.
        for _, call in ipairs(DAMAGE_CALLS) do
          local s = code:find(call[1])
          if s and not code:match("^%s*function") then
            local open = code:find("%(", s)
            local count = open and argCount(code, open)
            if count and count < call[2] then
              add({ severity = "minor", category = "structure", key = lineKey("dtype"), file = path, line = n,
                title = "Damage without a damage type", detail = ("%s: anything that hurts passes its type "
                  .. "(docs/features.md, Damage types)"):format(call[3]) })
            end
          end
        end

        -- A data field named like a hook: Features.any calls it and crashes.
        if tableName then
          local field, value = code:match("^" .. tableName .. "%.([%a_][%w_]*)%s*=%s*(.-)%s*$")
          if field and hooks[field] and not value:match("^function") then
            add({ severity = "major", category = "structure", key = lineKey("hookfield"), file = path, line = n,
              title = ("Field %s.%s shares its name with the %s hook"):format(tableName, field, field),
              detail = "Features.call/any calls every feature's field of that name; a value there crashes the game." })
          end
        end

        -- Sounds that ignore the volume sliders.
        if code:match("love%.audio%.newSource") then
          local mentions = false
          for _, l in ipairs(lines) do
            if l:find("Audio.volume", 1, true) or l:find("volume(", 1, true) then
              mentions = true
              break
            end
          end
          if not mentions then
            add({ severity = "minor", category = "structure", key = lineKey("volume"), file = path, line = n,
              title = "A sound that ignores the volume sliders",
              detail = "Register a channel and scale by Audio.volume (docs/features.md, Sound volumes)." })
          end
        end
      end
    end

    -- Long new functions.
    for _, n in ipairs(addedNumbers) do
      local text = entry.added[n]
      local name = text:match("function%s+([%w_.:]+)%s*%(") or text:match("([%w_.]+)%s*=%s*function%s*%(")
      if name and not text:find("audit: allow", 1, true) then
        local last = functionEnd(lines, n)
        local length = last - n + 1
        if length > Config.longFunction then
          add({ severity = "minor", category = "quality", key = "longfn:" .. path .. ":" .. name, file = path, line = n,
            title = ("%s is %d lines long"):format(name, length),
            detail = ("Over %d lines: split it into named steps."):format(Config.longFunction) })
        end
      end
    end

    -- A file that grew past the size where it is hard to work in.
    if #lines > Config.bigFile and #lines - entry.addedCount + entry.removedCount <= Config.bigFile then
      add({ severity = "minor", category = "structure", key = "bigfile:" .. path, file = path,
        title = ("%s grew past %d lines (%d)"):format(path, Config.bigFile, #lines),
        detail = "Split it into modules in the feature's folder." })
    end
  end
  report:note(("Read %d changed game files line by line (%d leftovers, %d TODO-style comments)"):format(#changedGame,
    leftovers, todos))

  Static.duplicates(report, ctx, changedGame, add)
  Static.layout(report, ctx, add)
  Static.wholeTree(report)
end

--- Copy-paste: a run of `Config.duplicateLines` added lines that already
--- exists somewhere else in the game.
function Static.duplicates(report, ctx, changedGame, add)
  local WINDOW = Config.duplicateLines
  local function norm(s)
    s = trim(s:gsub("%-%-.*$", ""))
    return s
  end
  local function windows(lines, fn)
    local buf, at = {}, {}
    for i, raw in ipairs(lines) do
      local s = norm(raw)
      if s ~= "" then
        buf[#buf + 1] = s
        at[#at + 1] = i
        if #buf > WINDOW then
          table.remove(buf, 1)
          table.remove(at, 1)
        end
        if #buf == WINDOW then
          local substantive = 0
          for _, l in ipairs(buf) do
            if #l >= 18 then
              substantive = substantive + 1
            end
          end
          if substantive >= WINDOW - 2 then
            fn(table.concat(buf, "\n"), at[1], at[#at])
          end
        end
      end
    end
  end

  local index = {}
  for _, path in ipairs(allLuaFiles()) do
    windows(Diff.lines(path) or {}, function(key, first)
      index[key] = index[key] or {}
      table.insert(index[key], { path = path, line = first })
    end)
  end

  local found = 0
  for _, path in ipairs(changedGame) do
    local entry = ctx.files[path]
    local lines = Diff.lines(path) or {}
    local reported = {}
    windows(lines, function(key, first, last)
      for i = first, last do
        if not entry.added[i] then
          return -- only runs made wholly of added lines
        end
      end
      local copies = index[key] or {}
      for _, c in ipairs(copies) do
        if not (c.path == path and c.line == first) and not reported[c.path] then
          reported[c.path] = true
          found = found + 1
          add({ severity = "minor", category = "structure", key = "dup:" .. path .. ":" .. c.path .. ":" .. key,
            file = path, line = first,
            title = ("%d+ lines copied from %s:%d"):format(WINDOW, c.path, c.line),
            detail = "Copy-paste spreads one idea over two places: share it, or say in a comment why they differ." })
          return
        end
      end
    end)
  end
  report:note(("Looked for copy-paste: runs of %d added lines already elsewhere in src (%d found)"):format(WINDOW,
    found))
end

--- Where the change lands: core files, gameplay outside a feature folder,
--- how many features one branch touches, the changelog, the branch name.
function Static.layout(report, ctx, add)
  local files = ctx.files
  local features, coreLines, coreFiles = {}, 0, {}
  local touchesGame = false
  for path, f in pairs(files) do
    local feature = Diff.featureOf(path)
    if feature and feature ~= "_template" then
      features[feature] = (features[feature] or 0) + f.addedCount + f.removedCount
    end
    if isCore(path) then
      coreLines = coreLines + f.addedCount + f.removedCount
      coreFiles[#coreFiles + 1] = path
    end
    if path:match("^src/") or path:match("^assets/") or path == "main.lua" or path == "conf.lua" then
      touchesGame = true
    end
    if f.status == "A" and path:match("^src/[^/]+%.lua$") then
      add({ severity = "major", category = "structure", key = "outside:" .. path, file = path,
        title = "New gameplay module outside a feature folder",
        detail = "Gameplay lives in src/features/<name>/ (CLAUDE.md); the core is shared by everyone." })
    end
    if f.status == "A" and path:match("^assets/") then
      add({ severity = "minor", category = "structure", key = "asset:" .. path, file = path,
        title = "New asset in the shared assets folder",
        detail = "An asset only one feature uses belongs in that feature's folder (docs/features.md)." })
    end
    if path:match("^lib/") then
      add({ severity = "major", category = "structure", key = "lib:" .. path, file = path,
        title = "Vendored library edited in place", detail = "lib/ is never edited (CLAUDE.md)." })
    end
    if path == "main.lua" then
      add({ severity = "major", category = "structure", key = "main.lua", file = path,
        title = "main.lua changed", detail = "Features are discovered by themselves; main.lua stays as it is." })
    end
  end
  table.sort(coreFiles)
  if #coreFiles > 0 then
    add({ severity = coreLines > Config.bigCoreChange and "major" or "minor", category = "structure",
      key = "core:" .. table.concat(coreFiles, ","),
      title = ("Core files changed (%d lines): %s"):format(coreLines, table.concat(coreFiles, ", ")),
      detail = "Only when a feature needs a new hook, kept minimal, and called out in the pull request (CLAUDE.md)." })
  end

  local names = {}
  for name in pairs(features) do
    names[#names + 1] = name
  end
  table.sort(names)
  if #names > Config.wideChange then
    add({ severity = "minor", category = "structure", key = "wide:" .. #names,
      title = ("One branch touches %d features"):format(#names),
      detail = "Scattered over " .. table.concat(names, ", ") .. ". Split unrelated work into its own branches." })
  end

  local log = files["CHANGELOG.md"]
  local srcChanged = false
  for path in pairs(files) do
    if isGameCode(path) and path ~= "src/version.lua" then
      srcChanged = true
    end
  end
  if srcChanged and not (log and log.addedCount > 0) then
    -- Only changes players notice get a line, which only a person can tell.
    add({ severity = "minor", category = "structure", key = "changelog",
      title = "Game code changed but CHANGELOG.md has no new line",
      detail = "If players will notice this, add one line under ## [Unreleased] (CLAUDE.md)." })
  end

  local branch = ctx.branch or ""
  if branch ~= "" and not branch:match("^feature/[a-z0-9%-]+$") and not branch:match("^bug/[a-z0-9%-]+$") then
    add({ severity = "minor", category = "structure", key = "branch:" .. branch,
      title = ("Branch name %q is not feature/<name> or bug/<name>"):format(branch) })
  end
  report:note(("Change spans %d features, %d core lines, game code %s"):format(#names, coreLines,
    touchesGame and "touched" or "untouched"))
  ctx.touchesGame = touchesGame
  ctx.featuresTouched = features
end

--- Over the whole tree, compared with the base like the game checks:
--- hooks raised that nobody documents, enemies the audit can't see.
function Static.wholeTree(report)
  local raised, enemyFeatures, listed = {}, {}, {}
  for _, path in ipairs(allLuaFiles()) do
    local feature = Diff.featureOf(path)
    for n, line in ipairs(Diff.lines(path) or {}) do
      local code = line:gsub("%-%-.*$", "")
      for name in code:gmatch('Features%.%a+%("([%w_]+)"') do
        raised[name] = raised[name] or { file = path, line = n }
      end
      if feature and code:match("^%s*function.-serverShotAt%s*%(") then
        enemyFeatures[feature] = enemyFeatures[feature] or { file = path, line = n }
      end
      if feature and code:match("serverEnemies") then
        listed[feature] = true
      end
    end
  end

  local docs = table.concat(Diff.lines("docs/features.md") or {}, "\n")
  for name, at in pairs(raised) do
    if name ~= "hookName" and not docs:find(name, 1, true) then
      report:add({ severity = "minor", category = "structure", key = "undocumented:" .. name, file = at.file,
        line = at.line, title = ("Hook %s is raised but docs/features.md never mentions it"):format(name),
        detail = "A hook other features answer is a convention: document it with the others." })
    end
  end

  for feature, at in pairs(enemyFeatures) do
    if not listed[feature] and not Config.notEnemies[feature] then
      report:add({ severity = "major", category = "structure", key = "noenemies:" .. feature, file = at.file,
        line = at.line,
        title = ("%s can be shot (serverShotAt) but does not list its enemies (serverEnemies)"):format(feature),
        detail = "The audit can't aim at what it can't see; answer serverEnemies (docs/features.md), or add it to "
          .. "notEnemies in tools/audit/config.lua if nothing in it is an enemy." })
    end
  end
end

--- Messages, against the handlers the loaded game really registered
--- (`Features.serverMessages` / `clientMessages`, however a feature wraps
--- them): kinds encoded but handled nowhere, and handlers whose kind never
--- appears anywhere else in the code (dead, or a typo).
function Static.messages(report, Features)
  local core = { HELLO = true, WELCOME = true, JOIN = true, LEAVE = true, START = true, REJECT = true, INPUT = true,
    STATE = true, VEHICLE = true, VEHICLE_GONE = true, KNOWN = true, YOU = true }
  local handled = {}
  for kind, entry in pairs(Features.serverMessages) do
    handled[kind] = entry.feature
  end
  for kind, entry in pairs(Features.clientMessages) do
    handled[kind] = entry.feature
  end
  local encoded, mentions = {}, {}
  for _, path in ipairs(allLuaFiles()) do
    for n, line in ipairs(Diff.lines(path) or {}) do
      local code = line:gsub("%-%-.*$", "")
      for kind in code:gmatch('encode%(%s*"([%u%d_]+)"') do
        encoded[kind] = encoded[kind] or { file = path, line = n }
      end
      -- Every use of the kind's name but the handler's own `KIND =` line.
      local defining = code:match("^%s*([%u%d_]+)%s*=")
      for kind in code:gmatch('"([%u%d_]+)"') do
        mentions[kind] = true
      end
      for kind in code:gmatch("%f[%w_]([%u][%u%d]*_[%u%d_]+)%f[^%w_]") do
        if kind ~= defining then
          mentions[kind] = true
        end
      end
    end
  end
  for kind, at in pairs(encoded) do
    if not handled[kind] and not core[kind] then
      report:add({ severity = "major", category = "stability", key = "unhandled:" .. kind, file = at.file,
        line = at.line, title = ("Message %s is sent but nothing handles it"):format(kind),
        detail = "Every message needs a clientMessages or serverMessages handler on the other side." })
    end
  end
  for kind, feature in pairs(handled) do
    if not mentions[kind] and not core[kind] then
      report:add({ severity = "minor", category = "quality", key = "unsent:" .. kind,
        file = "src/features/" .. feature .. "/", title = ("%s handles %s, but nothing sends it"):format(feature, kind),
        detail = "Dead code, or a typo in the kind." })
    end
  end
end

return Static
