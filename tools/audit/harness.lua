-- The whole game, run headless: the real main.lua, the real server and
-- client joined through the stub's loopback network, the real game screen
-- updating and drawing every frame. Only LÖVE itself is stood in for
-- (stub.lua). The audit plays quests in it and looks at what happens.
--
--   local Harness = require("tools.audit.harness")
--   local game = Harness.boot()          -- menu -> hosted game, in the city
--   game:quest("karen")                  -- everyone on Karen's map, quest started
--   game:run(2)                          -- two seconds of play, 60 frames a second
--   game.server, game.client, game.Features

local Stub = require("tools.audit.stub")

local Harness = {}
Harness.__index = Harness

Harness.FPS = 60

local booted = nil

--- Run `fn` and turn any error into (false, message with traceback).
local function guard(fn, ...)
  local args = { n = select("#", ...), ... }
  return xpcall(function()
    return fn(unpack(args, 1, args.n))
  end, function(err)
    return debug.traceback(tostring(err), 2)
  end)
end
Harness.guard = guard

--- Load the game (once per process) and host a game of it, started, with
--- the host in the city. Returns the game, or nil and the error.
function Harness.boot()
  if booted then
    return booted
  end
  Stub.install()
  math.randomseed(7)
  local ok, err = guard(function()
    dofile("main.lua")
    love.load({})
  end)
  if not ok then
    return nil, "the game failed to load:\n" .. err
  end

  local Net = require("src.net")
  local State = require("src.state")
  local game = setmetatable({
    Net = Net,
    State = State,
    Features = require("src.features"),
    Stub = Stub,
    errors = {}, -- every error raised while playing: { where, message }
  }, Harness)

  ok, err = guard(function()
    local hosted, why = Net.host("Auditor")
    assert(hosted, why)
    State.switch("lobby")
  end)
  if not ok then
    return nil, "could not host a game:\n" .. err
  end
  -- Join, start, and wait for the game screen.
  for _ = 1, 120 do
    if Net.client.state == "joined" and not Net.server.started then
      Net.server:start()
    end
    game:frame()
    if State.current == require("src.states.game") then
      break
    end
  end
  if State.current ~= require("src.states.game") then
    return nil, "the hosted game never reached the game screen (state: " .. tostring(State.name) .. ")"
  end
  game.server, game.client = Net.server, Net.client
  game:run(1)
  booted = game
  return game
end

--- Watch for a hang: LuaJIT's sampling profiler looks in every
--- `interval` ms, even inside compiled loops a signal can't reach, and
--- once no frame has finished for `stuck` seconds it writes where the code
--- is to stderr (once), so a hung job's log says which line it hung on.
function Harness.watch(stuck, interval)
  local ok, profile = pcall(require, "jit.profile")
  if not ok then
    return
  end
  Harness.progress = os.clock()
  local told = false
  profile.start("li" .. (interval or 500), function(thread)
    if not told and os.clock() - Harness.progress > stuck then
      told = true
      io.stderr:write(("audit: stuck for %ds, at:\n%s\n"):format(stuck, profile.dumpstack(thread, "pl\n", 25)))
    end
  end)
end

--- One frame of the game at `dt` (1/60 by default). An error is recorded,
--- not raised, so one broken feature does not stop the audit. Set
--- `game.drawing = false` to skip drawing (much faster; the arsenal does).
function Harness:frame(dt)
  dt = dt or 1 / Harness.FPS
  Stub.advance(dt)
  local ok, err = guard(function()
    love.update(dt)
    if self.drawing ~= false then
      love.draw()
    end
  end)
  if not ok then
    self:recordError("frame", err)
  end
  Harness.progress = os.clock()
  return ok
end

--- `seconds` of play. Stops early (returning false) after an error.
function Harness:run(seconds)
  for _ = 1, math.max(1, math.floor(seconds * Harness.FPS + 0.5)) do
    if not self:frame() then
      return false
    end
  end
  return true
end

function Harness:recordError(where, message)
  -- The same error every frame is one error.
  for _, e in ipairs(self.errors) do
    if e.message == message then
      e.count = e.count + 1
      return
    end
  end
  self.errors[#self.errors + 1] = { where = where, message = message, count = 1 }
  io.stderr:write(("audit: error in %s: %s\n"):format(where, tostring(message):match("^[^\n]*")))
end

--- The host's own player on the server (always id 1).
function Harness:me()
  return self.server.players[1]
end

--- Take everyone on quest `id`, the way the job board or an EXIT star
--- does. Returns true once its map is in play.
function Harness:quest(id)
  local quests = self.Features.byName.quests
  local quest = quests and quests.byId[id]
  if not quest then
    return false, "no quest " .. tostring(id)
  end
  local ok, result = guard(function()
    return quests:serverBegin(self.server, quest, self:me())
  end)
  if not ok then
    self:recordError("quest " .. id, result)
    return false, result
  end
  if not result then
    return false, "quests:serverBegin refused " .. id
  end
  self:run(0.5)
  return true
end

--- Back to the city, the way the blue star home goes, ending the quest.
function Harness:home()
  local quests = self.Features.byName.quests
  local ok, err = guard(function()
    return quests:serverBegin(self.server, quests.byId.home, self:me())
  end)
  if not ok then
    self:recordError("home", err)
  end
  self:run(0.2)
end

--- The map in play on the host.
function Harness:map()
  local city = self.Features.byName["city-map"]
  return city and city.map
end

--- Put the host on foot at (x, y), facing `facing` (out of any car first).
function Harness:placeOnFoot(x, y, facing)
  local me = self:me()
  if not (me and me.body) then
    return false
  end
  local ok, err = guard(function()
    if me.vehicle then
      self.server:unseat(me, x, y)
    end
    me.body.x, me.body.y = x, y
    me.body.facing = facing or me.body.facing
  end)
  if not ok then
    self:recordError("placeOnFoot", err)
  end
  return ok
end

--- Every enemy in the world now, as the features list them
--- (`serverEnemies`, docs/features.md): a list of their entries.
function Harness:enemies()
  local list = {}
  local ok, err = guard(function()
    self.Features.call("serverEnemies", self.server, function(e)
      list[#list + 1] = e
    end)
  end)
  if not ok then
    self:recordError("serverEnemies", err)
  end
  return list
end

--- Count, by shooter id, every time a feature is asked to take a round or
--- a blast (`serverShotAt`, `serverBlast`): game.shotsBy[id]. The arsenal
--- check tells its own hits from someone else's by it.
function Harness:watchShots()
  if self.shotsBy then
    return
  end
  self.shotsBy = {}
  local counts = self.shotsBy
  for _, f in ipairs(self.Features.list) do
    for _, hook in ipairs({ "serverShotAt", "serverBlast" }) do
      local original = f[hook]
      if original then
        local byAt = hook == "serverShotAt" and 6 or 7 -- after self: server, x, y, radius, (damage,) by
        f[hook] = function(...)
          local by = select(byAt, ...)
          if by then
            counts[by] = (counts[by] or 0) + 1
          end
          return original(...)
        end
      end
    end
  end
end

--- Is (x, y) inside something solid, as bullets see it?
function Harness:blocked(x, y)
  return self.Features.any("blocksPoint", x, y)
end

--- Keep the host alive whatever happens to them (bosses hit hard).
function Harness:godMode()
  local weapons = self.Features.byName.weapons
  local sv = weapons and weapons.sv
  local me = sv and sv.players and sv.players[1]
  if me then
    me.hp = 1e9
  end
end

return Harness
