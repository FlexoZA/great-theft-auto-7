-- How the portrait run (tools/wiki/portraits) meets the enemies that the
-- city and the audit's quest tours (tools/audit/stages.lua) never bring
-- out: city events, an ability's horde, the late waves of a fight.
-- `Scenes.city` are played in the city after the quests, `Scenes.after[id]`
-- at the end of quest `id`'s tour, for the pages still without a portrait.
-- `Scenes.portraits[page]` draws one itself, round (0, 0), for something
-- that is never a body in the world (VEX is a face over the whole roof).
-- `scene(game, look)` drives the game and calls `look()` whenever the
-- enemy may be about (it draws whatever is wanted).

local Scenes = { after = {}, portraits = {} }

-- Play `seconds`, looking every half second.
local function watch(game, look, seconds)
  for _ = 1, seconds * 2 do
    game:godMode()
    game:run(0.5)
    look()
  end
end

-- A city event (src/features/events), however locked, then called off.
local function event(key, seconds)
  return function(game, look)
    local events = game.Features.byName.events
    local after = events.after
    events.after = {} -- what unlocks it is the quests' business, not ours
    local ok, why = events:serverTrigger(game.server, key)
    events.after = after
    if not ok then
      return false, "the " .. key .. " event did not start: " .. tostring(why)
    end
    local active = events.kinds[key]
    for _ = 1, (seconds or 16) * 2 do
      -- Follow the boss about: it is drawn from what reaches this client.
      local list = game:enemies()
      if list[1] then
        game:placeOnFoot(list[1].x + 200, list[1].y)
      end
      game:godMode()
      game:run(0.5)
      look()
    end
    events:serverEnd(game.server, nil, nil, false)
    game:run(1)
    return active ~= nil
  end
end

-- A gang hangout (src/features/gang-hangout): its guards only come out of a
-- hangout a player built and paid into. Stand one up on the first plot for
-- the scene, with its fund full, and let the guards walk out.
local function hangout(game, look)
  local bld = game.Features.byName.buildings
  local re = game.Features.byName["real-estate"]
  local gang = game.Features.byName["gang-hangout"]
  local plot = next(re.plots)
  if not plot then
    return false, "no plot for a gang hangout"
  end
  local me = game:me()
  local original = bld.serverBuilding
  bld.serverBuilding = function(self, id)
    if id == plot then
      return { kind = "hangout", owner = me.id, hp = 100 }
    end
    return original(self, id)
  end
  game:run(0.2)
  local h = gang.server().hangouts[plot]
  if h then
    h.fund = 1e6
    watch(game, look, 8)
  end
  bld.serverBuilding = original
  game:run(0.2)
  return h ~= nil, "the gang hangout did not open"
end

-- Shoot every enemy `which(e)` picks with a round nobody survives, the way
-- a player's round reaches it (`serverShotAt`).
local function kill(game, which)
  for _, e in ipairs(game:enemies()) do
    if which(e) and not e.immune then
      game.Features.call("serverShotAt", game.server, e.x, e.y, e.radius or 10, 1, 0, 1e6, "bullet")
    end
  end
end

-- Stand at (x, y) for `seconds`, looking.
local function standAt(game, look, x, y, seconds)
  for _ = 1, seconds * 2 do
    game:godMode()
    game:placeOnFoot(x, y)
    game:run(0.5)
    look()
  end
end

Scenes.city = {
  hangout,
  event("bigfoot"),
  event("runner"),
  event("tripod", 20), -- its storm comes first
  event("a-man"),
  -- Open borders: the ability's horde of simps, cast where the host stands.
  function(game, look)
    local me = game:me()
    local x, y = me.body.x, me.body.y
    game.Features.call("serverOpenBorders", game.server, me, x, y, 12)
    watch(game, look, 4)
  end,
}

-- The Roof with VEX up (the launch's --boss): her dropship brings an elite
-- officer from its second drop on, so clear out what it brought each time.
Scenes.after["cyber-feud-roof"] = function(game, look)
  local quest = game.Features.byName.quests.byId["cyber-feud-roof"]
  if not game.Features.any("serverSkipToBoss", game.server, quest, game:me()) then
    return false, "the Roof would not skip to VEX"
  end
  for _ = 1, 120 do
    game:godMode()
    game:run(1)
    look()
    for _, e in ipairs(game:enemies()) do
      if e.kind == "cyber-feud/halcyon-soldier" and not e.id.elite then
        e.id.hp = 0 -- down, so the dropship comes again
      end
    end
  end
  return true
end

-- City 17's plaza: walking into it brings A-Man by with his briefcase of
-- turrets (a-man/cameo.lua).
Scenes.after["a-man"] = function(game, look)
  local map = game:map()
  for _, post in ipairs(map.posts or {}) do
    if post.at == "plaza" then
      standAt(game, look, post.x, post.y + 60, 30)
      return true
    end
  end
  return false, "City 17 has no plaza post"
end

-- The Coast: the Antlion Guard digs up once the finale's swarms and troops
-- are down and somebody is in there to see it (antlions/guard.lua).
Scenes.after["a-man-coast"] = function(game, look)
  local f = game:map().finale
  if not f then
    return false, "the Coast has no finale"
  end
  for _ = 1, 40 do
    standAt(game, look, f.x + f.w / 2, f.y + f.h / 2, 1)
    kill(game, function(e)
      return e.kind == "antlions/antlion" or e.kind == "a-man/combine"
    end)
  end
  return true
end

-- The Winding Road's pass: stand off from the Poison Zombie and he throws
-- his headcrabs (poison-zombie).
Scenes.after["a-man-road"] = function(game, look)
  for _ = 1, 30 do
    for _, e in ipairs(game:enemies()) do
      if e.kind == "poison-zombie/zombie" then
        game:placeOnFoot(e.x + 300, e.y)
      end
    end
    game:godMode()
    game:run(0.5)
    look()
  end
  return true
end

-- The Citadel's top platform: A-Man blinks in there and opens his case.
Scenes.after["a-man-citadel"] = function(game, look)
  for _, p in ipairs(game:map().platforms or {}) do
    if p.kind == "top" then
      standAt(game, look, p.x + p.w / 2, p.y + p.h / 2, 40)
      return true
    end
  end
  return false, "the Citadel has no top platform"
end

-- Kilowatt riding by on the Overpass: too quick to catch where the host
-- says he is, and he looks as he does on the Roof (kilowatt_look.lua).
Scenes.portraits["cyber-feud-kilowatt-cameo"] = function()
  love.graphics.scale(2.2)
  require("src.features.cyber-feud.kilowatt_look").draw(-math.pi / 2, 0, { pulse = 1 })
end

-- VEX: her face, the way she projects it over the Roof, at full strength.
Scenes.portraits["cyber-feud-vex"] = function()
  local face = require("src.features.cyber-feud.face").new()
  face:draw(0, 0, 4, { 1.00, 0.24, 0.78 }, { alpha = 1, broken = 0 })
end

-- Whispering Pines: Bigfoot only comes out at the trail's end, and the trail
-- only goes on once each clearing's squirrel is shot. Walk with Wendell,
-- shoot the squirrels, then follow Bigfoot round until he's on the ground.
Scenes.after["alien-hunt"] = function(game, look)
  local Hunt = require("src.features.alien-hunt")
  for _ = 1, 240 do
    local sv = Hunt.server and Hunt.server()
    if not sv or sv.stage == "done" then
      break
    end
    kill(game, function(e)
      return e.kind == "alien-hunt/squirrel"
    end)
    local followed = false
    for _, e in ipairs(game:enemies()) do
      if e.kind == "alien-hunt/bigfoot" then
        game:placeOnFoot(e.x + 260, e.y)
        followed = true
      end
    end
    if not followed and sv.man then
      game:placeOnFoot(sv.man.x + 30, sv.man.y)
    end
    game:godMode()
    game:run(0.5)
    look()
  end
  return true
end

-- The Drop: assassin droids walk cloaked until they have somebody, and the
-- street is calm until someone hurts one, so graze one and stand by it.
Scenes.after["cyber-feud"] = function(game, look)
  local grazed = false
  for _ = 1, 60 do
    for _, e in ipairs(game:enemies()) do
      if e.kind == "cyber-feud/droid" then
        game:placeOnFoot(e.x + 200, e.y)
        if not grazed then
          game.Features.call("serverShotAt", game.server, e.x, e.y, e.radius or 10, 1, 0, 1, "bullet")
          grazed = true
        end
        break
      end
    end
    game:godMode()
    game:run(0.5)
    look()
  end
  return true
end

return Scenes
