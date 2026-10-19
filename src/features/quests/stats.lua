-- How each player did on the job under way, counted on the host for the
-- victory screen (victory.lua): the job's time, what they killed, how often
-- they died, the koins they picked up, what they unlocked, and the bosses
-- beaten. A job's run starts on its first map and carries on over every map
-- after it (A-Man's trail, the courier job), stops counting time when the
-- last map is done, and is gone once everyone is home.
--
-- The quests feature feeds it from its hooks (serverKill, serverKoinTaken,
-- serverRewarded, serverStep) and each human hears their own numbers:
--   server -> player  QST_STATS <seconds> <kills> <deaths> <koins> <bosses> [<unlocked>]...
-- sent a moment after they change (FLUSH), and at once when the job is done
-- and when everyone heads home.

local Protocol = require("src.net.protocol")

local Stats = {}

Stats.FLUSH = 0.5 -- seconds a change waits, so a burst of kills is one message

local run = nil -- { time, ended, bosses, flush, players = { [id] = entry }, dirty = { [id] = true } }

local function fresh()
  return { kills = 0, deaths = 0, koins = 0, unlocks = {} }
end

--- A job begins (its first map). Any run still going is dropped.
function Stats.begin()
  run = { time = 0, ended = false, bosses = 0, flush = 0, players = {}, dirty = {} }
end

function Stats.running()
  return run ~= nil
end

--- Everyone is home: nothing more is counted.
function Stats.stop()
  run = nil
end

--- `player`'s numbers, made on first need; nil for a bot or with no run.
local function of(player)
  if not (run and player) or player.bot then
    return nil
  end
  local e = run.players[player.id]
  if not e then
    e = fresh()
    run.players[player.id] = e
  end
  run.dirty[player.id] = true
  return e
end

local function everyone(server)
  for _, p in pairs(server.players) do
    if not p.bot then
      run.dirty[p.id] = true
    end
  end
end

--- Something died (the serverKill convention). Kind "car" is a player: a
--- death when their body went down with it (a wreck they bailed out of is
--- not). Anything else is an enemy, credited to whoever killed it; a boss
--- is beaten for everyone.
function Stats.kill(server, kill)
  if not run then
    return
  end
  if kill.kind == "car" then
    local victim = kill.victim and server.players[kill.victim]
    if victim and victim.body and victim.body.dead then
      local e = of(victim)
      if e then
        e.deaths = e.deaths + 1
      end
    end
    return
  end
  local e = of(kill.by and server.players[kill.by])
  if e then
    e.kills = e.kills + 1
  end
  if kill.kind == "boss" then
    run.bosses = run.bosses + 1
    everyone(server)
  end
end

function Stats.koin(player)
  local e = of(player)
  if e then
    e.koins = e.koins + 1
  end
end

--- `player` unlocked something for good; `title` is what it is called.
function Stats.reward(player, title)
  local e = of(player)
  if e then
    e.unlocks[#e.unlocks + 1] = tostring(title or "?"):gsub("%c", " ")
  end
end

local function message(e)
  return Protocol.encode("QST_STATS", math.floor(run.time), e.kills, e.deaths, e.koins, run.bosses,
    unpack(e.unlocks))
end

--- Send what has changed now (everyone's, with `all`).
function Stats.flush(server, all)
  if not run then
    return
  end
  if all then
    everyone(server)
  end
  for id in pairs(run.dirty) do
    local p = server.players[id]
    if p then
      server:send(p, message(run.players[id] or fresh()))
    end
  end
  run.dirty, run.flush = {}, 0
end

--- The last map is done: the clock stops and everyone hears where they stand.
function Stats.finish(server)
  if run and not run.ended then
    run.ended = true
    Stats.flush(server, true)
  end
end

function Stats.step(server, dt)
  if not run then
    return
  end
  if not run.ended then
    run.time = run.time + dt
  end
  run.flush = run.flush + dt
  if run.flush >= Stats.FLUSH and next(run.dirty) then
    Stats.flush(server)
  end
end

--- For tests.
function Stats.state()
  return run
end

return Stats
