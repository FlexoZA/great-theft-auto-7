-- Checks that play the game (headless, harness.lua): every quest is taken
-- and played, its map looked over, its enemies listed and shot at with
-- everything a player can hurt them with; then the saves, then every
-- message handler is fed rubbish.
--
-- Findings here are compared with a run on the base (run.lua), so only
-- what this branch broke or left out costs points.

local Config = require("tools.audit.config")
local Stages = require("tools.audit.stages")
local Arsenal = require("tools.audit.checks.arsenal")
local Wiki = require("tools.audit.checks.wiki")

local Game = {}

-- An error's first line, without line numbers, so the same crash on the
-- base and on the branch has the same key even when the file moved.
local function errorKey(message)
  local first = tostring(message):match("^[^\n]*") or ""
  return (first:gsub(":%d+:", ":"))
end

local function firstLines(message, n)
  local out = {}
  for line in tostring(message):gmatch("[^\n]+") do
    out[#out + 1] = line
    if #out >= n then
      break
    end
  end
  return table.concat(out, "\n")
end

--- Errors recorded since `from` (an index into game.errors), as findings.
local function crashes(report, game, from, where, key, severity)
  for i = from + 1, #game.errors do
    local e = game.errors[i]
    report:add({ severity = severity or "blocker", category = "stability",
      key = "crash:" .. key .. ":" .. errorKey(e.message),
      title = ("%s: the game errors (%dx)"):format(where, e.count),
      detail = firstLines(e.message, 6) })
  end
end

-- Map ----------------------------------------------------------------------

--- Does anything draw past the edge of the map? Surroundings is asked to
--- draw with the camera on the map's top-left corner, zoomed out.
local function backdropDraws(game, map)
  local surroundings = game.Features.byName.surroundings
  if not (surroundings and surroundings.drawBelowCars and map.left) then
    return 0
  end
  local before = game.Stub.drawCalls
  local ok = game.guard(function()
    surroundings:drawBelowCars(game.client, { x = map.left, y = map.top, scale = 0.35 })
  end)
  return ok and game.Stub.drawCalls - before or 0
end

--- The soundtrack heard on this map since `since` (the stub's clock): a
--- looping sound at least Config.musicSeconds long, made or played then.
local function soundtrack(game, since)
  local found = nil
  for _, s in ipairs(game.Stub.sounds) do
    local recent = s.created >= since or (s.lastPlay and s.lastPlay >= since)
    if recent and s.duration >= Config.musicSeconds then
      if not found or s.duration > found.duration then
        found = s
      end
    end
  end
  return found
end

local function mapChecks(report, game, quest, since, soundtracks)
  local map = game:map()
  local name = map and map.name or quest.map
  local where = ("%s (%s)"):format(name, quest.id)

  if backdropDraws(game, map) == 0 then
    report:add({ severity = "major", category = "maps", key = "backdrop:" .. name,
      title = ("No backdrop past the edge of %s"):format(where),
      detail = "Past its edge the map shows the bare grid: give it surroundings (src/features/surroundings, DRAW)." })
  end

  local track = soundtrack(game, since)
  if not track then
    report:add({ severity = "major", category = "maps", key = "music:" .. name,
      title = ("No soundtrack on %s"):format(where),
      detail = ("No looping track of %ds or more was made or played after the quest started (music on the "
        .. "\"music\" channel, as karen, a-man, cyber-feud and eternal-mood do)."):format(Config.musicSeconds) })
  else
    soundtracks[name] = track.signature -- compared across maps once every quest is in (Game.merge)
  end

  local crates = game.Features.byName["ammo-crates"]
  local count, walled = 0, 0
  for _, c in pairs(crates and crates.crates or {}) do
    count = count + 1
    if game:blocked(c.x, c.y) then
      walled = walled + 1
    end
  end
  if count < Config.ammoCrates then
    report:add({ severity = "major", category = "maps", key = "ammo:" .. name,
      title = ("No ammo crates on %s"):format(where),
      detail = "Players run dry: ammo-crates scatters them over road/ground (or map.openKinds) tiles." })
  end
  if walled > 0 then
    report:add({ severity = "major", category = "maps", key = "ammo-wall:" .. name,
      title = ("%d ammo crate(s) inside walls on %s"):format(walled, where) })
  end

  local inWall = 0
  for _, s in ipairs(game.server.spawnPoints or {}) do
    if game:blocked(s.x, s.y) then
      inWall = inWall + 1
    end
  end
  if inWall > 0 then
    report:add({ severity = "major", category = "maps", key = "spawn-wall:" .. name,
      title = ("%d spawn point(s) inside walls on %s"):format(inWall, where) })
  end

  local spec = game.Features.byName["city-map"].maps[name]
  local home = spec and spec.noHome -- (a map that means to have none says so)
  for _, q in ipairs(game.Features.byName.quests.list) do
    if q.returns and q.onMap == name then
      home = true
    end
  end
  if not home then
    report:add({ severity = "minor", category = "maps", key = "home:" .. name,
      title = ("No star home on %s"):format(where),
      detail = "A quest map has a blue star by its way in (a quest with `returns` and onMap = the map), "
        .. "or says it means to have none (`noHome` on its city-map spec)." })
  end
end

--- Every enemy in a wall, by kind: once per kind per map.
local function wallChecks(report, game, mapName, quest, enemies)
  for _, e in ipairs(enemies) do
    if not e.flying then
      local r = (e.radius or 8) * Config.wallTolerance
      local stuck = game:blocked(e.x, e.y)
        and game:blocked(e.x + r, e.y) and game:blocked(e.x - r, e.y)
        and game:blocked(e.x, e.y + r) and game:blocked(e.x, e.y - r)
      if stuck then
        report:add({ severity = "major", category = "maps", key = "enemy-wall:" .. mapName .. ":" .. e.kind,
          title = ("%s stuck inside a wall on %s (%s)"):format(e.kind, mapName, quest.id),
          detail = ("At (%.0f, %.0f): it can't move and bullets stop before they reach it."):format(e.x, e.y) })
      end
    end
  end
end

-- Quests ---------------------------------------------------------------------

local function playQuest(report, game, quest, ctx, soundtracks, seen)
  local wall = os.clock()
  io.stderr:write(("audit: playing %s\n"):format(quest.id))
  local from = #game.errors
  local since = game.Stub.clock
  game:godMode()
  local ok, why = game:quest(quest.id)
  if not ok then
    report:add({ severity = "blocker", category = "stability", key = "quest-start:" .. quest.id,
      title = ("Quest %s does not start"):format(quest.id), detail = firstLines(why, 6) })
    crashes(report, game, from, "Starting " .. quest.id, quest.id)
    return
  end
  game:godMode()
  game:run(2)
  local map = game:map()
  local mapName = map and map.name or quest.map

  mapChecks(report, game, quest, since, soundtracks)

  local kindsHere = {}
  local paged = Wiki.kinds(game.Features)
  local function look()
    game:godMode()
    local enemies = game:enemies()
    wallChecks(report, game, mapName, quest, enemies)
    for _, e in ipairs(enemies) do
      if not seen[e.kind] then
        Wiki.unpaged(report, paged, e.kind, quest.id)
      end
      seen[e.kind] = seen[e.kind] or { quest = quest.id }
      if not e.immune then
        seen[e.kind].hittable = true
      end
      kindsHere[e.kind] = true
    end
    if ctx.arsenal then
      Arsenal.testPresent(report, game, quest, ctx)
    end
  end
  look()

  Stages.tour(game, quest.id, function(x, y, seconds)
    game:godMode()
    game:placeOnFoot(x, y)
    game.drawing = false -- quick there; drawn for a moment once it is
    game:run(seconds or 3)
    game.drawing = true
    game:run(0.25)
    look()
  end)

  -- Bosses still talking (an intro, a reveal) come out after a while: wait
  -- for every kind met so far to be hittable once, up to Config.waitSeconds.
  local waited = 0
  while waited < Config.waitSeconds do
    local pending = false
    for kind in pairs(kindsHere) do
      if not seen[kind].hittable then
        pending = true
      end
    end
    if not pending then
      break
    end
    game.drawing = false
    game:run(1)
    game.drawing = true
    waited = waited + 1
    look()
  end

  local played = game.Stub.clock - since
  if played < Config.questSeconds then
    game:godMode()
    game:run(Config.questSeconds - played)
  end
  crashes(report, game, from, ("Playing %s (%s)"):format(quest.id, mapName), quest.id)

  local n = 0
  for _ in pairs(kindsHere) do
    n = n + 1
  end
  report:note(("Quest %s on %s: played %.0fs, %d kinds of enemy met (%.0fs to audit)"):format(quest.id, mapName,
    game.Stub.clock - since, n, os.clock() - wall))
  game:home()
end

-- Saves ------------------------------------------------------------------------

local function saves(report, game)
  local Serialize = require("src.serialize")
  local Persistence = require("src.net.persistence")
  local Features = game.Features
  local server, me = game.server, game:me()
  local function step(what, fn)
    local ok, err = game.guard(fn)
    if not ok then
      report:add({ severity = "major", category = "stability", key = "save:" .. what .. ":" .. errorKey(err),
        title = ("Saving and loading fails: %s"):format(what), detail = firstLines(err, 6) })
    end
    return ok
  end
  local world, player
  step("serverSaveWorld", function()
    world = Serialize.decode(Serialize.encode(Persistence.snapshot(server)), "world")
  end)
  step("serverSavePlayer", function()
    player = Serialize.decode(Serialize.encode(Features.gather("serverSavePlayer", server, me)), "player")
  end)
  if world then
    step("serverLoadWorld", function()
      Features.deliver("serverLoadWorld", world.features, server)
    end)
  end
  if player then
    step("serverLoadPlayer", function()
      Features.deliver("serverLoadPlayer", player, server, me)
    end)
  end
  local from = #game.errors
  game:run(1)
  crashes(report, game, from, "Playing on after a save and load", "after-load", "major")
  report:note("Saved the world and the host, wrote and read them back, and loaded them into the running game")
end

-- Rubbish in -------------------------------------------------------------------

local JUNK = {
  {},
  { "" },
  { "abc", "def", "ghi", "jkl", "mno", "pqr", "stu" },
  { "-1", "-1", "-1", "-1", "-1", "-1" },
  { "0", "0", "0", "0", "0", "0", "0", "0" },
  { "1e309", "-1e309", "1e309", "-1e309", "1e309" },
  { "999999999", "999999999", "999999999", "999999999" },
  { "3.5", "nan", "inf", "0x10", "1@legendary", "gun-rocket@legendary" },
  { string.rep("x", 4000) },
}

--- Feed every handler rubbish: a client can send anything, and the host
--- must never fall over (CLAUDE.md: never trust a client message).
local function fuzz(report, game)
  local Features = game.Features
  local me = game:me()
  local kinds = {}
  for kind in pairs(Features.serverMessages) do
    kinds[#kinds + 1] = kind
  end
  table.sort(kinds)
  local failed = 0
  for _, kind in ipairs(kinds) do
    local entry = Features.serverMessages[kind]
    for _, args in ipairs(JUNK) do
      local copy = { unpack(args) }
      local ok, err = game.guard(entry.handler, game.server, me, copy)
      if not ok then
        failed = failed + 1
        report:add({ severity = "major", category = "stability", key = "fuzz:" .. kind,
          title = ("A malformed %s from a client crashes the host (%s)"):format(kind, entry.feature),
          detail = ("Sent with fields {%s}:\n%s"):format(table.concat(args, ", "):sub(1, 80), firstLines(err, 4)) })
        break
      end
    end
    game:godMode()
  end
  local from = #game.errors
  game:run(1)
  crashes(report, game, from, "Playing on after rubbish messages", "after-fuzz", "major")

  local clientKinds = {}
  for kind in pairs(Features.clientMessages) do
    clientKinds[#clientKinds + 1] = kind
  end
  table.sort(clientKinds)
  local clientFailed = 0
  for _, kind in ipairs(clientKinds) do
    local entry = Features.clientMessages[kind]
    for _, args in ipairs(JUNK) do
      local ok, err = game.guard(entry.handler, game.client, { unpack(args) })
      if not ok then
        clientFailed = clientFailed + 1
        report:add({ severity = "minor", category = "stability", key = "fuzz-client:" .. kind,
          title = ("A malformed %s from the host crashes a client (%s)"):format(kind, entry.feature),
          detail = ("Fields {%s}:\n%s"):format(table.concat(args, ", "):sub(1, 80), firstLines(err, 4)) })
        break
      end
    end
  end
  report:note(("Fed rubbish to %d server and %d client message handlers: %d and %d fell over"):format(#kinds,
    #clientKinds, failed, clientFailed))
end

-- Equipment --------------------------------------------------------------------

local TIERS = { "common", "uncommon", "rare", "legendary" }

local function statAt(t, path)
  for part in path:gmatch("[^.]+") do
    if type(t) ~= "table" then
      return nil
    end
    t = t[part]
  end
  return t
end

--- Guns, abilities, armor and clothes: tiered, described, sold.
local function equipment(report, game)
  local Tiers = require("src.features.tiers")
  local lists = {
    { what = "gun", file = "src/features/weapons/guns.lua", items = require("src.features.weapons.guns").list },
    {
      what = "ability",
      file = "src/features/abilities/kinds.lua",
      items = require("src.features.abilities.kinds").list,
    },
    { what = "armor", file = "src/features/armor/kinds.lua", items = require("src.features.armor.kinds").list },
    { what = "gear", file = "src/features/gear/kinds.lua", items = require("src.features.gear.kinds").list },
  }
  local n = 0
  for _, l in ipairs(lists) do
    for _, item in ipairs(l.items) do
      n = n + 1
      local name = ("%s %s"):format(l.what, item.key)
      if type(item.tierStats) ~= "table" or #item.tierStats == 0 then
        report:add({ severity = "major", category = "arsenal", key = "tiers:" .. l.what .. ":" .. item.key,
          file = l.file, title = ("%s has no tierStats"):format(name),
          detail = "Equipment comes in tiers: give it tierStats, read its numbers through Tiers.apply (CLAUDE.md)." })
      else
        for _, path in ipairs(item.tierStats) do
          -- A piece of clothing's stats are its multipliers (gear/kinds.lua).
          if type(statAt(item, path)) ~= "number" and type(statAt(item.stats, path)) ~= "number" then
            report:add({ severity = "major", category = "arsenal",
              key = "tierstat:" .. l.what .. ":" .. item.key .. ":" .. path,
              file = l.file, title = ("%s: tier stat %q is not a number on it"):format(name, path),
              detail = "A better tier would improve nothing (or crash): the path must name one of its numbers." })
          end
        end
        for _, tier in ipairs(TIERS) do
          local ok, err = game.guard(Tiers.apply, item, tier)
          if not ok then
            report:add({ severity = "major", category = "arsenal",
              key = "tierapply:" .. l.what .. ":" .. item.key,
              file = l.file, title = ("%s in tier %s fails"):format(name, tier), detail = firstLines(err, 4) })
            break
          end
        end
      end
      if type(item.blurb) ~= "string" or item.blurb == "" then
        report:add({ severity = "minor", category = "arsenal", key = "blurb:" .. l.what .. ":" .. item.key,
          file = l.file, title = ("%s has no blurb for the shop"):format(name) })
      end
    end
  end
  report:note(("Checked tiers and blurbs of %d pieces of equipment"):format(n))
end

-- Jobs ------------------------------------------------------------------------
-- run.lua plays each quest in a process of its own (in parallel, each
-- under a time limit, so a hang is a finding rather than a frozen audit)
-- and one more for everything else; each job's `state` comes back to be
-- merged.

--- Everything that is not a quest: messages, equipment, saves, rubbish.
function Game.general(report, _ctx, game)
  require("tools.audit.checks.static").messages(report, game.Features)
  equipment(report, game)
  saves(report, game)
  Wiki.pages(report, game.Features)
  fuzz(report, game)
end

--- The quest ids the audit plays, in order.
function Game.questIds(Quests, only)
  local ids = {}
  for _, quest in ipairs(Quests.list) do
    if not quest.returns and not Config.notQuestMaps[quest.map] and (not only or only[quest.id]) then
      ids[#ids + 1] = quest.id
    end
  end
  return ids
end

--- One quest; fills `state` = { soundtracks = { map -> signature }, seen =
--- { kind -> { quest, hittable } } } and ctx.matrix (the arsenal's cells).
function Game.quest(report, ctx, game, id, state)
  local quest = game.Features.byName.quests.byId[id]
  playQuest(report, game, quest, ctx, state.soundtracks, state.seen)
end

--- What only shows once every quest is in: shared soundtracks, enemies
--- never reached, the arsenal matrix.
function Game.merge(report, ctx, state)
  local maps = {}
  for map in pairs(state.soundtracks) do
    maps[#maps + 1] = map
  end
  table.sort(maps)
  local first = {}
  for _, map in ipairs(maps) do
    local sig = state.soundtracks[map]
    if first[sig] then
      report:add({ severity = "minor", category = "maps", key = "music-shared:" .. map,
        title = ("%s plays the same soundtrack as %s"):format(map, first[sig]),
        detail = "A map of its own deserves a track of its own." })
    else
      first[sig] = map
    end
  end

  local never = {}
  for kind, s in pairs(state.seen) do
    if not s.hittable then
      never[#never + 1] = ("%s (%s)"):format(kind, s.quest)
    end
  end
  table.sort(never)
  if #never > 0 then
    report:note("Seen but never hittable while the audit played (tours in tools/audit/stages.lua reach the "
      .. "fight): " .. table.concat(never, ", "))
  end
  if ctx.arsenal then
    Arsenal.summarise(report, ctx)
  end
end

return Game
