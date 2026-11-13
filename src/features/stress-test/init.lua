-- Stress test: load the game up a batch at a time, the way a full game of
-- about ten players would (the human and the civilian bots the game starts
-- with): buildings making weapons and ammo, drivers feeding them, buildings
-- taking damage and Handsy Men mending them. It logs what that does to the
-- frame rate, for a chart of the load against FPS. A developer's tool, run
-- through four cheat codes (F2 lists them):
--
--   concretejungle  puts up the next BATCH buildings for random players
--                   (bots too), a supply chain in the order of MIX: quarries
--                   and oil wells (each digging a random material, already
--                   full of it) between ammo and weapons factories (hoppers
--                   full, so they work at once), now and then anything else.
--                   Every product is picked at random. They fill the city in diamond
--                   rings out from its centre: the closest free plot first,
--                   growing the city a block at a time once its own plots are
--                   taken, until every block it may grow into holds a building
--                   (4 plots + 90 grown blocks on the default city). Free; an
--                   owned empty plot keeps its owner.
--   hiringspree     hires HIRES more delivery drivers and as many Handsy Men
--                   for every player and bot, free and past the shop's limits
--                   (three drivers, one Handsy Man), and tops each wallet up
--                   to FUND Fcks to pay for repairs. Drivers with buildings to
--                   serve plan routes and haul; without, they cruise. A Handsy
--                   Man with nothing to mend goes home and is gone, so turn
--                   the wrecking ball on first.
--   wreckingball    starts or stops the damage: every DAMAGE_EVERY seconds a
--                   random building loses 10-40% of the hit points it has
--                   left, so it never falls to a ruin and keeps working.
--   fpslog          starts or stops the log on the machine that typed it.
--
-- "Players" means people and the civilian bots (B adds one): not police,
-- drivers or any other NPC with a brain of its own.
--
-- While the log runs, every time the number of buildings, drivers or Handsy
-- Men changes it waits SETTLE seconds (new buildings redraw the map), then
-- measures SAMPLE seconds of frames and appends a row to perf-stress.csv in
-- the save directory: buildings, drivers, Handsy Men, average FPS, average
-- and worst frame time (on the host the frame includes the server's tick).
-- Turning it
-- on measures the city as it stands first, the baseline. Vsync caps the FPS
-- at the screen's rate, so switch it off in Settings > Video for a fair chart;
-- the log says which it was.
--
-- Everything this puts up is real: a saved world keeps it. Try it on a world
-- you can throw away.
--
-- Messages
--   server -> player  STRESS_LOG <0|1>   (start or stop the log here)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Video = require("src.video")
local UI = require("src.ui")

local Stress = {
  name = "stress-test",
  priority = 989, -- a HUD panel, under the ability bar (990) and every full screen
}

Stress.BATCH = 15 -- buildings per concretejungle
Stress.HIRES = 1 -- drivers, and Handsy Men, per player per hiringspree
Stress.FUND = 100000 -- Fcks each player's wallet is topped up to by hiringspree
Stress.DAMAGE_EVERY = 1 -- seconds between the wrecking ball's blows
-- The order concretejungle puts kinds down in, round and round: "source" is a
-- quarry or oil well, "any" any kind at all. A kind the game lacks counts as "any".
Stress.MIX = { "source", "ammo", "source", "weapons", "source", "any" }
local SETTLE = 3 -- seconds to wait after the count changes before measuring
local SAMPLE = 5 -- seconds of frames per row
local FILE = "perf-stress.csv"
local SHOWN = 8 -- rows the HUD panel lists

-- Server ----------------------------------------------------------------

local P = 10 -- tiles per block, as in city-map's layout

--- The block at the city's centre (fractional), where the rings start.
local function centreOf(map)
  return (math.floor((map.cols - 1) / P) - 1) / 2, (math.floor((map.rows - 1) / P) - 1) / 2
end

--- The free place closest to the centre: an empty plot ({ plot }) or a block
--- the city may grow into ({ bi, bj }). Ties go to the top row, then the left,
--- so every batch grows the same shape.
local function nextPlace(city, estate, buildings)
  local ci, cj = centreOf(city.map)
  local best, bestD
  local function consider(place, bi, bj)
    local d = math.abs(bi - ci) + math.abs(bj - cj)
    if not best or d < bestD or (d == bestD and (bj < best.bj or (bj == best.bj and bi < best.bi))) then
      best, bestD = place, d
      place.bi, place.bj = bi, bj
    end
  end
  for _, plot in ipairs(estate.plots) do
    if not buildings:serverBuilding(plot.id) then
      consider({ plot = plot }, plot.block.bi, plot.block.bj)
    end
  end
  for _, site in ipairs(city:growthSites()) do
    consider({}, site.bi, site.bj)
  end
  return best
end

--- The ids of the people and civilian bots in the game, in order: the ones
--- who own what the test puts up.
local function players(server)
  local ids = {}
  for id, p in pairs(server.players) do
    if not (p.bot and p.brain) then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

local mixAt = 0 -- where concretejungle is in MIX

--- Put up to `n` buildings on the city (see the top of the file). Returns
--- how many went up and, if it stopped short, why.
function Stress:serverAdd(server, n)
  local city, estate = Features.byName["city-map"], Features.byName["real-estate"]
  local buildings = Features.byName.buildings
  if not (city and estate and buildings and estate.serverGrow and buildings.serverPlace and buildings.kindKeys) then
    return 0, "no buildings in this game"
  elseif city.current ~= city.DEFAULT then
    return 0, "only in the city"
  end
  local owners = players(server)
  local kinds, sources = buildings:kindKeys()
  local known = {}
  for _, key in ipairs(kinds) do
    known[key] = true
  end
  local placed = 0
  while placed < n do
    local place = nextPlace(city, estate, buildings)
    if not place then
      return placed, "the city is full"
    end
    local plot = place.plot
    local owner = plot and estate:owner(plot.id) or owners[math.random(#owners)]
    if plot then
      if not estate:owner(plot.id) then
        estate:serverTransfer(server, plot.id, owner)
      end
    else
      plot = estate:serverGrow(server, place.bi, place.bj, owner)
    end
    local slot = Stress.MIX[mixAt % #Stress.MIX + 1]
    mixAt = mixAt + 1
    local key = known[slot] and slot or (slot == "source" and #sources > 0 and sources[math.random(#sources)])
      or kinds[math.random(#kinds)]
    if not (plot and buildings:serverPlace(server, plot.id, key, owner, { product = "random", stocked = true })) then
      return placed, "something was in the way" -- never expected; stops the loop picking it again
    end
    placed = placed + 1
  end
  return placed
end

--- Hire `n` more drivers and `n` more Handsy Men for every player and top
--- their wallets up (see the top of the file). Returns what the banner says.
function Stress:serverHire(server, n)
  local delivery, handsy, money = Features.byName.delivery, Features.byName["handsy-man"], Features.byName.money
  local owners, drivers, men = players(server), 0, 0
  for _, id in ipairs(owners) do
    local p = server.players[id]
    if money and money.wallet and money:wallet(id) < Stress.FUND then
      money:give(server, id, Stress.FUND - money:wallet(id))
    end
    for _ = 1, n do
      if delivery and delivery.serverHire and delivery:serverHire(server, p) then
        drivers = drivers + 1
      end
      if handsy and handsy.serverHire and handsy:serverHire(server, p) then
        men = men + 1
      end
    end
  end
  return ("%d drivers, %d Handsy Men for %d players"):format(drivers, men, #owners)
end

local wrecking, blowIn = false, 0 -- the wrecking ball is on; seconds to its next blow

--- Start or stop the wrecking ball. Returns whether it runs now.
function Stress:serverToggleWrecking()
  wrecking, blowIn = not wrecking, 0
  return wrecking
end

--- A blow of the wrecking ball: a random standing building loses 10-40%
--- of the hit points it has left.
local function blow(server)
  local estate, buildings = Features.byName["real-estate"], Features.byName.buildings
  if not (estate and buildings and buildings.serverBatter) then
    return
  end
  local standing = {}
  for _, plot in ipairs(estate.plots) do
    local b = buildings:serverBuilding(plot.id)
    if b and b.hp > 1 then
      standing[#standing + 1] = { id = plot.id, hp = b.hp }
    end
  end
  local pick = standing[math.random(math.max(1, #standing))]
  if pick then
    buildings:serverBatter(server, pick.id, math.max(1, pick.hp * (0.1 + 0.3 * math.random())))
  end
end

function Stress:serverStep(server, dt)
  if not wrecking then
    return
  end
  blowIn = blowIn - dt
  if blowIn <= 0 then
    blowIn = Stress.DAMAGE_EVERY
    blow(server)
  end
end

local logging = {} -- player id -> true while their log runs

--- Start or stop `player`'s log. Returns whether it runs now.
function Stress:serverToggleLog(server, player)
  logging[player.id] = not logging[player.id] or nil
  server:send(player, Protocol.encode("STRESS_LOG", logging[player.id] and 1 or 0))
  return logging[player.id] == true
end

function Stress:serverStart()
  logging, wrecking, mixAt = {}, false, 0
end

function Stress:serverPlayerLeft(_server, player)
  logging[player.id] = nil
end

-- Client --------------------------------------------------------------------

local log = nil -- { load, phase = "settle"|"sample"|"done", timer, frames, elapsed, worst, rows }

--- How many of a feature's client-side table there are (0 without the feature).
local function count(feature, field)
  local n = 0
  for _ in pairs(Features.byName[feature] and Features.byName[feature][field] or {}) do
    n = n + 1
  end
  return n
end

local function startLog()
  local w, h = love.graphics.getDimensions()
  local vsync = Video.get("vsync") and "on" or "off"
  love.filesystem.append(FILE, ("# %s  %dx%d  vsync %s\n"):format(os.date("%Y-%m-%d %H:%M:%S"), w, h, vsync))
  love.filesystem.append(FILE, "buildings,drivers,handymen,fps,avg_ms,worst_ms\n")
  log = { rows = {} }
end

local function writeRow()
  local fps = log.frames / log.elapsed
  local row = {
    buildings = log.buildings,
    drivers = log.drivers,
    men = log.men,
    fps = fps,
    avg = 1000 * log.elapsed / log.frames,
    worst = 1000 * log.worst,
  }
  local line = ("%d,%d,%d,%.1f,%.2f,%.2f\n"):format(row.buildings, row.drivers, row.men, row.fps, row.avg, row.worst)
  love.filesystem.append(FILE, line)
  log.rows[#log.rows + 1] = row
end

function Stress:exitGame()
  log = nil
end

function Stress:update(dt)
  if not log then
    return
  end
  local buildings, drivers = count("buildings", "buildings"), count("delivery", "units")
  local men = count("handsy-man", "units")
  if buildings ~= log.buildings or drivers ~= log.drivers or men ~= log.men then
    log.buildings, log.drivers, log.men, log.phase, log.timer = buildings, drivers, men, "settle", SETTLE
  end
  if log.phase == "settle" then
    log.timer = log.timer - dt
    if log.timer <= 0 then
      log.phase, log.frames, log.elapsed, log.worst = "sample", 0, 0, 0
    end
  elseif log.phase == "sample" then
    log.frames, log.elapsed, log.worst = log.frames + 1, log.elapsed + dt, math.max(log.worst, dt)
    if log.elapsed >= SAMPLE then
      writeRow()
      log.phase = "done"
    end
  end
end

--- A small panel on the left: what the log is doing and its last rows.
function Stress:drawHUD()
  if not log then
    return
  end
  local font = UI.fonts.small
  local lineH = font:getHeight() + 2
  local lines = { { "FPS LOG -> " .. FILE, { 0.4, 1, 0.5 } } }
  if Video.get("vsync") then
    lines[#lines + 1] = { "vsync is on: FPS is capped", { 1, 0.6, 0.3 } }
  end
  local status = log.phase == "settle" and ("settling %.0fs"):format(math.max(0, log.timer))
    or log.phase == "sample" and ("measuring %.0fs"):format(math.max(0, SAMPLE - log.elapsed))
    or "measured"
  lines[#lines + 1] = {
    ("%d buildings, %d drivers, %d Handsy Men, %s"):format(log.buildings or 0, log.drivers or 0, log.men or 0, status),
    { 1, 0.85, 0.3 },
  }
  lines[#lines + 1] = { "bld  drv  hsy    fps   avg ms  worst", { 0.6, 0.6, 0.65 } }
  for i = math.max(1, #log.rows - SHOWN + 1), #log.rows do
    local r = log.rows[i]
    local text = ("%3d  %3d  %3d  %5.1f  %6.2f  %6.2f"):format(r.buildings, r.drivers, r.men, r.fps, r.avg, r.worst)
    lines[#lines + 1] = { text, { 0.9, 0.9, 0.95 } }
  end
  local w = 0
  for _, line in ipairs(lines) do
    w = math.max(w, font:getWidth(line[1]))
  end
  w = w + 16
  local h = #lines * lineH + 12
  local x, y = 10, math.floor((love.graphics.getHeight() - h) / 2)
  UI.panel(x, y, w, h)
  love.graphics.setFont(font)
  for i, line in ipairs(lines) do
    love.graphics.setColor(line[2])
    love.graphics.print(line[1], x + 8, y + 6 + (i - 1) * lineH)
  end
  love.graphics.setColor(1, 1, 1)
end

Stress.clientMessages = {
  STRESS_LOG = function(_client, args)
    if args[1] == "1" then
      startLog()
    else
      log = nil
    end
  end,
}

return Stress
