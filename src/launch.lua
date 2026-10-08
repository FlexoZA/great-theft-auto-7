-- Launch options, for trying things out from a terminal without the menus:
--
--   love . --world <slug>                 host the saved world <slug> and start it
--   love . --world <slug> --quest <id>    ...and take everyone straight on quest <id>
--
-- <slug> is the world's folder under saves/ in LÖVE's save directory; you
-- come back as your saved player (the world knows you by the player key in
-- your settings). <id> is any quest in quests' `Quests.list`, e.g. "a-man"
-- for City 17, "a-man-2" for the Outer City, "a-man-road" for the Winding
-- Road or "a-man-citadel" for the Citadel. --name <name> plays under that
-- name instead of $USER. Unknown worlds and quests are reported and the
-- game goes to the menu (or plays on in the city).

local State = require("src.state")
local Net = require("src.net")
local Saves = require("src.saves")
local Protocol = require("src.net.protocol")
local Features = require("src.features")

local Launch = {}

local pending = nil -- { quest } until the game is under way and the quest taken

--- Read the options out of LÖVE's `args`. Returns true when it took over
--- from the menu.
function Launch.start(args)
  local opts, i = {}, 1
  while args and args[i] do
    local key = args[i]:match("^%-%-(%a+)$")
    if key and args[i + 1] then
      opts[key] = args[i + 1]
      i = i + 2
    else
      i = i + 1
    end
  end
  if not opts.world then
    return false
  end
  local world, err = Saves.open(opts.world)
  if not world then
    print("launch: " .. err)
    return false
  end
  local name = Protocol.sanitizeName(opts.name or os.getenv("USER") or os.getenv("USERNAME") or "Player")
  local ok, hostErr = Net.host(name, world)
  if not ok then
    print("launch: " .. tostring(hostErr))
    return false
  end
  pending = { quest = opts.quest }
  State.switch("lobby")
  return true
end

--- Start the game once our own client has joined, then take the quest.
function Launch.update()
  local server, client = Net.server, Net.client
  if not (pending and server and client) then
    return
  end
  if not server.started then
    if client.state == "joined" then
      server:start()
    end
    return
  end
  local id = pending.quest
  pending = nil
  if id then
    local quests = Features.byName.quests
    local quest = quests and quests.byId[id]
    local me = server.players[1] -- the host is always id 1
    if not (quest and me and quests:serverBegin(server, quest, me)) then
      print("launch: no quest " .. id)
    end
  end
end

return Launch
