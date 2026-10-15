-- The audit: rates a branch out of 10 before it may go into staging.
--
--   luajit tools/audit/run.lua            this branch against origin/staging
--   luajit tools/audit/run.lua --full     shoot every gun at every enemy, whatever changed
--   options: --base <ref>  --quest <id> (repeatable)  --no-base  --no-game
--            --md <file>  --json <file>  --pass <score>
--
-- It reads the change (checks/static.lua), plays the game headless
-- (checks/game.lua, checks/arsenal.lua): every quest in a process of its
-- own, several at once, each under a time limit so a hang is a finding and
-- not a frozen audit. The same game checks run on the base in a worktree
-- beside it, so what was already wrong there is debt and costs this branch
-- nothing. Exit code 0 passes, 1 fails. See docs/audit.md.

package.path = "./?.lua;./?/init.lua;" .. package.path

local Config = require("tools.audit.config")
local Diff = require("tools.audit.diff")
local Report = require("tools.audit.report")

local function parse(argv)
  local opts = { quests = {}, base = Config.base }
  local i = 1
  while i <= #argv do
    local a = argv[i]
    local function value()
      i = i + 1
      return argv[i]
    end
    if a == "--full" then
      opts.full = true
    elseif a == "--base" then
      opts.base = value()
    elseif a == "--quest" then
      opts.quests[#opts.quests + 1] = value()
    elseif a == "--no-base" then
      opts.noBase = true
    elseif a == "--no-game" then
      opts.noGame = true
    elseif a == "--md" then
      opts.md = value()
    elseif a == "--json" then
      opts.json = value()
    elseif a == "--pass" then
      opts.pass = tonumber(value())
    elseif a == "--as-base" then
      opts.asBase = value() -- write the keys found here, and nothing else
    elseif a == "--scope" then
      opts.scopeFile = value()
    elseif a == "--job" then
      opts.job = value() -- one job, for a parent run: "general" or "quest:<id>"
    elseif a == "--out" then
      opts.out = value()
    elseif a == "--jobs" then
      opts.jobs = tonumber(value())
    elseif a == "--help" or a == "-h" then
      print((io.open("tools/audit/run.lua"):read("*a"):match("^(.-)\n\npackage") or ""):gsub("%-%- ?", ""))
      os.exit(0)
    else
      io.stderr:write("audit: unknown option " .. a .. "\n")
      os.exit(2)
    end
    i = i + 1
  end
  return opts
end

-- Which guns and abilities, and whose enemies, the arsenal matrix covers:
-- `true` for all of it, a { weapons, features } table, or false for none.
-- Whatever a branch changes about either side is covered; a change to the
-- damage plumbing itself covers everything.
local EVERYTHING = {
  "src/features/weapons/init.lua",
  "src/features/damage/",
  "src/features/tiers/",
  "src/features/init.lua",
  "src/net/",
}

local function arsenalScope(files, full)
  if full then
    return true
  end
  local scope = { weapons = {}, features = {}, any = false }
  for path in pairs(files) do
    for _, prefix in ipairs(EVERYTHING) do
      if path:sub(1, #prefix) == prefix then
        return true
      end
    end
    if path == "src/features/weapons/guns.lua" then
      scope.weapons["gun:*"], scope.any = true, true
    end
    local ability = path:match("^src/features/abilities/([%w%-_]+)%.lua$")
    if ability then
      scope.weapons["ability:" .. ability] = true
      scope.any = true
      if ability == "init" or ability == "kinds" then
        return true
      end
    end
    if path:match("^src/features/grenades/") then
      scope.weapons["grenade:*"], scope.any = true, true
    end
    local feature = Diff.featureOf(path)
    if feature then
      scope.features[feature] = true
      scope.any = true
    end
  end
  return scope.any and scope or false
end

local function writeScope(path, scope)
  local f = assert(io.open(path, "w"))
  if scope == true then
    f:write("all\n")
  elseif scope then
    for k in pairs(scope.weapons) do
      f:write("weapon\t", k, "\n")
    end
    for k in pairs(scope.features) do
      f:write("feature\t", k, "\n")
    end
  end
  f:close()
end

local function readScope(path)
  local scope = { weapons = {}, features = {} }
  local any = false
  for line in io.lines(path) do
    if line == "all" then
      return true
    end
    local what, name = line:match("^(%a+)\t(.+)$")
    if what == "weapon" then
      scope.weapons[name], any = true, true
    elseif what == "feature" then
      scope.features[name], any = true, true
    end
  end
  return any and scope or false
end

local function exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

local function shellQuote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- Open `path` for writing, making its folder first.
local function create(path)
  local dir = path:match("^(.*)/[^/]+$")
  if dir then
    os.execute("mkdir -p " .. shellQuote(dir))
  end
  return assert(io.open(path, "w"))
end

--- Start the base's run in a worktree beside this one, in the background.
--- Returns a function that waits for it and gives its keys (nil if it failed).
local function startBase(sha, opts, scopeFile)
  local dir = Diff.run("mktemp -d"):gsub("%s+$", "")
  local tree = dir .. "/base"
  local keys, log, done = dir .. "/keys.txt", dir .. "/log.txt", dir .. "/done"
  Diff.run(("git worktree add --detach %s %s"):format(shellQuote(tree), sha))
  if not exists(tree .. "/main.lua") then
    return function()
      return nil, "could not check the base out into a worktree"
    end
  end
  -- The base is judged by this branch's audit, not its own (it may have none).
  Diff.run(("rm -rf %s/tools/audit && mkdir -p %s/tools && cp -r tools/audit %s/tools/audit"):format(
    shellQuote(tree), shellQuote(tree), shellQuote(tree)))
  local args = { "--as-base", shellQuote(keys), "--scope", shellQuote(scopeFile) }
  for _, q in ipairs(opts.quests) do
    args[#args + 1] = "--quest " .. shellQuote(q)
  end
  os.execute(("(cd %s && luajit tools/audit/run.lua %s > %s 2>&1; touch %s) &"):format(shellQuote(tree),
    table.concat(args, " "), shellQuote(log), shellQuote(done)))
  return function()
    while not exists(done) do
      os.execute("sleep 1")
    end
    local set = nil
    if exists(keys) then
      set = {}
      for line in io.lines(keys) do
        set[line] = true
      end
    end
    local why = nil
    if not set then
      local f = io.open(log)
      why = f and f:read("*a") or "no log"
      if f then
        f:close()
      end
    end
    Diff.run(("git worktree remove --force %s"):format(shellQuote(tree)))
    Diff.run(("rm -rf %s"):format(shellQuote(dir)))
    return set, why
  end
end

-- Jobs -------------------------------------------------------------------------

local JOB_SECONDS = 300 -- one quest's (or the general job's) limit; a quest normally takes under 30
local Serialize = nil

--- Run one job in this process and write what it found to `out`.
local function runJob(opts)
  local Harness = require("tools.audit.harness")
  Harness.watch(60)
  Serialize = require("src.serialize")
  local report = Report.new()
  local ctx = { arsenal = opts.scopeFile and readScope(opts.scopeFile) or false }
  local state = { soundtracks = {}, seen = {} }
  local started = os.clock()
  local game, err = Harness.boot()
  if not game then
    report:add({ severity = "blocker", category = "stability", key = "boot",
      title = "The game does not load", detail = err })
  else
    local Game = require("tools.audit.checks.game")
    local ok, crash
    if opts.job == "general" then
      report:note(("Booted every feature headless and hosted a game (%.1fs)"):format(os.clock() - started))
      ok, crash = Harness.guard(Game.general, report, ctx, game)
    else
      ok, crash = Harness.guard(Game.quest, report, ctx, game, opts.job:match("^quest:(.+)$"), state)
    end
    if not ok then
      report:add({ severity = "blocker", category = "stability", key = "audit-crash:" .. opts.job,
        title = ("The audit fell over in %s (something it relies on broke)"):format(opts.job), detail = crash })
    end
  end
  local findings = {}
  for _, f in ipairs(report.findings) do
    findings[#findings + 1] = { severity = f.severity, category = f.category, key = f.key, title = f.title,
      detail = f.detail, file = f.file, line = f.line }
  end
  local f = assert(io.open(opts.out .. ".part", "w"))
  f:write(Serialize.encode({ findings = findings, notes = report.notes, matrix = ctx.matrix or {}, state = state }))
  f:close()
  os.rename(opts.out .. ".part", opts.out)
  return 0
end

local function cores()
  local n = tonumber((Diff.run("nproc"):gsub("%s+", ""))) or 2
  return math.max(1, math.min(n, 6))
end

--- The quests to play, read from the game's own list.
local function questIds(only)
  require("tools.audit.stub").install()
  local Quests = require("src.features.quests")
  return require("tools.audit.checks.game").questIds(Quests, only)
end

local function tail(path, n)
  local lines = {}
  local f = io.open(path)
  if f then
    for line in f:lines() do
      if not line:match("rendered in") and not line:match("canvas built") then
        lines[#lines + 1] = line
        if #lines > n then
          table.remove(lines, 1)
        end
      end
    end
    f:close()
  end
  return table.concat(lines, "\n")
end

--- Every game job, `opts.jobs` at a time, merged into `report`.
local function playGame(report, ctx, opts)
  Serialize = Serialize or require("src.serialize")
  local Game = require("tools.audit.checks.game")
  local Arsenal = require("tools.audit.checks.arsenal")
  local dir = Diff.run("mktemp -d"):gsub("%s+$", "")
  local scopeFile = dir .. "/scope"
  writeScope(scopeFile, ctx.arsenal)
  local jobs = { "general" }
  for _, id in ipairs(questIds(ctx.only)) do
    jobs[#jobs + 1] = "quest:" .. id
  end

  local running, nextJob, finished = {}, 1, {}
  local width = opts.jobs or cores()
  local function start(job, i)
    local base = ("%s/%02d"):format(dir, i)
    -- SIGINT first: LuaJIT turns it into an error where the code is stuck,
    -- with a traceback in the log; a kill 30 s later if that wasn't enough.
    local cmd = ("(timeout -s INT -k 30 %d luajit tools/audit/run.lua --job %s --out %s --scope %s > %s 2>&1; "
      .. "touch %s) &"):format(JOB_SECONDS, shellQuote(job), shellQuote(base .. ".out"), shellQuote(scopeFile),
        shellQuote(base .. ".log"), shellQuote(base .. ".done"))
    os.execute(cmd)
    running[#running + 1] = { job = job, base = base, started = os.time() }
  end
  while nextJob <= #jobs or #running > 0 do
    while #running < width and nextJob <= #jobs do
      start(jobs[nextJob], nextJob)
      nextJob = nextJob + 1
    end
    os.execute("sleep 0.5")
    for i = #running, 1, -1 do
      local r = running[i]
      if exists(r.base .. ".done") then
        table.remove(running, i)
        finished[#finished + 1] = r
        io.stderr:write(("audit: %s done in %ds\n"):format(r.job, os.time() - r.started))
      end
    end
  end

  local state = { soundtracks = {}, seen = {} }
  ctx.matrix = {}
  table.sort(finished, function(a, b)
    return a.base < b.base
  end)
  for _, r in ipairs(finished) do
    local f = io.open(r.base .. ".out")
    local result = f and Serialize.decode(f:read("*a"), r.job)
    if f then
      f:close()
    end
    if not result then
      report:add({ severity = "blocker", category = "stability", key = "hang:" .. r.job,
        title = ("%s never finished (a hang, or the game took the process down)"):format(r.job),
        detail = ("Stopped after %ds. The end of its log:\n%s"):format(JOB_SECONDS, tail(r.base .. ".log", 25)) })
    else
      for _, finding in ipairs(result.findings) do
        report:add(finding)
      end
      for _, n in ipairs(result.notes) do
        report:note(n)
      end
      Arsenal.merge(ctx.matrix, result.matrix)
      for map, sig in pairs(result.state.soundtracks) do
        state.soundtracks[map] = sig
      end
      for kind, s in pairs(result.state.seen) do
        local have = state.seen[kind]
        state.seen[kind] = { quest = have and have.quest or s.quest, hittable = s.hittable or (have and have.hittable) }
      end
    end
  end
  Game.merge(report, ctx, state)
  Diff.run("rm -rf " .. shellQuote(dir))
  report:note(("Played %d jobs, %d at a time"):format(#jobs, width))
end

local function main(argv)
  local opts = parse(argv)
  if opts.job then
    return runJob(opts)
  end
  if opts.pass then
    Report.PASS = opts.pass
  end
  local report = Report.new()
  local ctx = { branch = Diff.currentBranch() }
  if #opts.quests > 0 then
    ctx.only = {}
    for _, q in ipairs(opts.quests) do
      ctx.only[q] = true
    end
  end

  -- The base's own run: the game checks and the whole-tree ones, keys out.
  if opts.asBase then
    ctx.arsenal = opts.scopeFile and readScope(opts.scopeFile) or false
    require("tools.audit.checks.static").wholeTree(report)
    playGame(report, ctx, opts)
    local f = assert(io.open(opts.asBase, "w"))
    for key in pairs(report:keys()) do
      f:write(key, "\n")
    end
    f:close()
    return 0
  end

  local started = os.time()
  local sha = Diff.mergeBase(opts.base)
  if not sha then
    io.stderr:write(("audit: can't find where this branch left %s (git fetch origin?)\n"):format(opts.base))
    return 2
  end
  ctx.files = Diff.read(sha)
  local meta = { branch = ctx.branch, base = opts.base .. " @ " .. sha:sub(1, 8) }

  ctx.arsenal = arsenalScope(ctx.files, opts.full)
  meta.mode = opts.full and "full" or "scoped to the change"
  if not ctx.arsenal then
    report:note("Arsenal matrix skipped: no gun, ability, grenade or enemy changed (run with --full for all of it)")
  end

  local waitBase = nil
  if not opts.noGame and not opts.noBase then
    local scopeFile = os.tmpname()
    writeScope(scopeFile, ctx.arsenal)
    waitBase = startBase(sha, opts, scopeFile)
  end

  require("tools.audit.checks.static").run(report, ctx)
  if not opts.noGame then
    playGame(report, ctx, opts)
  else
    report:note("Game checks skipped (--no-game)")
  end

  if waitBase then
    local keys, why = waitBase()
    if keys then
      report:subtract(keys)
      report:note("Compared with a run of the same checks on the base: what it had already is debt, not scored")
    else
      report:note("The base could not be run, so every finding counts as new:\n" .. tostring(why):sub(1, 2000))
    end
  elseif not opts.noGame then
    report:note("Not compared with the base (--no-base): every finding counts as new")
  end
  report:note(("Took %ds"):format(os.time() - started))

  print(report:text(meta))
  local md = report:markdown(meta)
  if opts.md then
    local f = create(opts.md)
    f:write(md, "\n")
    f:close()
  end
  local summary = os.getenv("GITHUB_STEP_SUMMARY")
  if summary and summary ~= "" then
    local f = io.open(summary, "a")
    if f then
      f:write(md, "\n")
      f:close()
    end
  end
  if opts.json then
    local f = create(opts.json)
    f:write(report:json(meta), "\n")
    f:close()
  end
  return report:score().pass and 0 or 1
end

os.exit(main(arg))
