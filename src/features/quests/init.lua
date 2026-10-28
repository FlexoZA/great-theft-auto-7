-- Quests: jobs you pick up in the world. Every job starts at the Jobs
-- building in the city (jobs.lua picks it from the map): stand on the
-- square by its door, open the job board on the action key and take one of
-- the jobs listed there; the host takes everyone to the map the job is on
-- (city-map's `switchTo`). There is one world, so a quest is a group
-- outing: whoever takes the job takes the whole server with them.
--
-- Seven jobs so far: one sends everyone to Crazy Karen's cul-de-sac (the
-- karen feature runs the fight), one into the forest after a wild man
-- hunting aliens (alien-hunt), one onto a defended beach to take Major
-- Looz'er's hill (d-day), one across a meadow under a sniper's cliff
-- after Shotgun (shotgun), one by train into City 17 after A-Man (a-man),
-- whose trail carries on over four more maps by EXIT stars, and the
-- courier job into Grey City (cyber-feud), five maps the same way, and
-- the pest-control job to the UAC's moon base (eternal-mood). A blue
-- star by the entrance of each brings everyone home again (not on Cyber
-- Feud's Roof: there the only way home is the star on the helipad once VEX
-- is gone); a star comes
-- up when you drive or walk onto it, and
-- declined it waits until you come back. A map may have several stars; the
-- nearest one is the one on offer. Add a quest to `Quests.list` with
-- `board = true` and the board, the offer and the trip are all done here;
-- a quest marked `returns` is the way back and ends the one under way. What
-- happens on the quest is another feature's business: this one raises
-- `questStarted(client, quest, byId)` / `questEnded(client, quest)` on every
-- machine and `serverQuestStarted(server, quest, player)` /
-- `serverQuestEnded(server, quest)` on the host, and a feature that finishes
-- the job calls `quests:serverComplete(server, questId, x, y)`.
--
-- A boss that goes down far from the way in leaves a way out: pass where it
-- fell to `serverComplete` and an EXIT star comes up there, taking
-- everyone home the same as the blue star by the entrance. Never on the
-- body itself: a star that would stand within `exitClear` of where a boss
-- fell on this map (its koins and drops lie there) moves to the nearest
-- open road or ground clear of it. That goes for every quest, the ones that
-- put their star at a spot of their own too.
--
-- Once the last map of a job is done, the star home offers the victory
-- screen (victory.lua) instead of the plain offer: how the job went for
-- you, counted on the host (stats.lua), with the same keys to go home or
-- stay. Whoever is taken home by somebody else sees it on arriving.
--
-- The host decides: it checks the taker's body is on the star (or at the
-- Jobs building's door for a job on the board), that the star is on the
-- map in play and that the destination exists, then switches the map and
-- tells everyone. Clients only draw the stars and the board, and ask.
--
-- Messages
--   client -> server  QST_ACCEPT <questId>
--   server -> all     QST_MAP    <mapName>              (play on this map from now on; before QST_START)
--   server -> all     QST_START  <questId> <playerId>   (who took the job)
--   server -> all     QST_DONE   <questId>              (the job is done)
--   server -> all     QST_EXIT   <x> <y>                (an EXIT star home stands here, on the map in play)
--   server -> all     QST_HELD   <questId>              (the trip was taken but a feature holds it up: offers down)
--   server -> all     QST_FINISHED [<questId> <clears>]...  (every board job finished in this world so far,
--                                                         and how many times)
--   server -> player  QST_NO     <reason>               (away | gone | locked)
--   server -> player  QST_STATS  <seconds> <kills> <deaths> <koins> <bosses> [<unlocked>]...
--                                                       (how the job is going for them: stats.lua)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Jobs = require("src.features.quests.jobs")
local Stats = require("src.features.quests.stats")
local Victory = require("src.features.quests.victory")

local Quests = {
  name = "quests",
  priority = 22, -- star over the map (20), under real-estate (25); QST_MAP reaches a joiner before RE_EXPAND
}

-- Quests -------------------------------------------------------------------
-- `board = true` puts a job on the Jobs building's board in the default
-- city; otherwise `onMap` is the map its star sits on and (x, y) where.
-- `map` is where accepting takes everyone. Every name is a key of
-- city-map's `maps`.
-- `returns` marks the trip home: taking it ends the quest under way instead
-- of starting one. `label` and `color` dress the star; `banner` is what
-- everyone reads when the trip happens (%s is the taker's name). `boss`
-- names the feature that owns the fight there (karen listens for its own).
-- `exitText` (optional) is what the EXIT star says once it is done;
-- `exitTitle` and `exitLabel` (optional) name it, for an EXIT star on to
-- the `next` quest that should not give away where it really goes.
-- `next` (optional) names the quest that carries on from this one: once
-- this one is done its EXIT star takes everyone straight on to that
-- quest's map and starts it, instead of home. A feature may hold that trip
-- up (`serverHoldTrip(server, quest, player)` returning true, e.g. A-Man
-- turning up first) and make it itself later with `quests:serverBegin`. A quest only reached that way
-- has no `board` and no `onMap`. `introLine` is for the boss feature (A-Man
-- says that line of his on his intro screen).
Quests.list = {
  {
    id = "karen",
    title = "Crazy Karen is at it again, let's end this",
    text = "She's out on her street again, screaming at the neighbourhood. "
      .. "Get everyone over there and shut her up for good.",
    board = true,
    map = "culdesac",
    boss = "karen",
    label = "KAREN",
    banner = "%s took the job. Welcome to Karen's Cul-de-sac.",
  },
  {
    id = "alien-hunt",
    title = "The truth is out there (in the woods)",
    text = "A wild-eyed man with half his lunch down his shirt is waving you over. He swears aliens are "
      .. "harvesting human hair to eat, and he knows where they land. Follow him into the forest.",
    board = true,
    map = "forest",
    boss = "alien-hunt",
    label = "ALIENS?",
    color = { 0.55, 1, 0.45 },
    banner = "%s followed the wild man. Welcome to Whispering Pines.",
  },
  {
    id = "d-day",
    title = "D-Day landing",
    text = "Major Looz'er has dug in on the hill above the beach and will not stop talking about it. "
      .. "Wade ashore, keep your head down between the tank stoppers, get past the bunkers and take his flag.",
    board = true,
    map = "beach",
    boss = "d-day",
    label = "D-DAY",
    color = { 0.78, 0.82, 0.45 },
    banner = "%s hit the beach. Welcome to Looz'er Beach.",
  },
  {
    id = "shotgun",
    title = "Shotgun's Bluff",
    text = "A man called Shotgun has taken the top of the bluff with a sniper rifle and is shooting anyone "
      .. "who debates anything. Cross the meadow from cover to cover, climb the ramp at the far left "
      .. "and settle it up there. Don't argue with him on the way.",
    board = true,
    map = "cliff",
    boss = "shotgun",
    label = "SHOTGUN",
    color = { 0.95, 0.55, 0.35 },
    banner = "%s went after Shotgun. Welcome to Shotgun's Bluff.",
  },
  {
    id = "a-man",
    title = "The man with the moustache",
    text = "A man in a suit, round glasses and a very new moustache has been seen getting off a train in "
      .. "City 17. Nobody recognises him. Take the train in, get through the city and find out where he is going.",
    board = true,
    map = "city17",
    boss = "a-man",
    label = "A-MAN",
    color = { 0.55, 0.95, 0.65 },
    banner = "%s took the train. Welcome to City 17.",
    exitText = "You made it to the Citadel. He went inside. Go in after him.",
    exitTitle = "Into the Citadel",
    exitLabel = "CITADEL",
    next = "a-man-2",
  },
  {
    -- Where the Citadel's doors really lead: A-Man turns up and sends
    -- everyone the long way round (a-man/detour.lua).
    id = "a-man-2",
    title = "The Outer City",
    text = "Not the Citadel. He sent you out past the edge of the city: blocks, canals and a square in the middle.",
    map = "outercity",
    boss = "a-man",
    label = "A-MAN",
    color = { 0.55, 0.95, 0.65 },
    banner = "A-Man had other plans for %s. Welcome to the Outer City.",
    introLine = 6,
    exitText = "The gunship is down. His trail runs on out of the city, up the coast. After him.",
    exitTitle = "Up the coast",
    exitLabel = "COAST",
    next = "a-man-coast",
  },
  {
    -- Up the coast after him: the EXIT star by the Hunter-Chopper's wreck
    -- in the Outer City leads here.
    id = "a-man-coast",
    title = "The Coast",
    text = "He went up the coast. One beach between the sea and the mountains, and the Combine in every cove.",
    map = "coast",
    boss = "a-man",
    label = "A-MAN",
    color = { 0.55, 0.95, 0.65 },
    banner = "%s followed him up the coast. Welcome to the Coast.",
    introLine = 7,
    exitText = "The Antlion Guard is down and the point is yours. His trail leaves the beach here, up a road "
      .. "into the mountains. Get back in your car.",
    exitTitle = "Up the road",
    exitLabel = "ROAD",
    next = "a-man-road",
  },
  {
    -- Up into the mountains after him, driven: the EXIT star on the
    -- Coast's point leads here.
    id = "a-man-road",
    title = "The Winding Road",
    text = "He took the road up through the mountains. A long way round, over the river and up to the pass.",
    map = "road",
    boss = "a-man",
    label = "A-MAN",
    color = { 0.55, 0.95, 0.65 },
    banner = "%s took the road after him. Welcome to the Winding Road.",
    introLine = 8,
    exitText = "The Poison Zombie is down and the pass is yours. The Citadel is right there, and this time the "
      .. "way in is open. Go in after him.",
    exitTitle = "Into the Citadel",
    exitLabel = "CITADEL",
    next = "a-man-citadel",
  },
  {
    -- The end of the trail: the EXIT star by the Poison Zombie on the
    -- Winding Road's pass leads here.
    id = "a-man-citadel",
    title = "Into the Citadel",
    text = "He went inside. One catwalk up through the Citadel, and the Combine on every platform along it.",
    map = "citadel",
    boss = "a-man",
    label = "A-MAN",
    color = { 0.55, 0.95, 0.65 },
    banner = "%s went in after him. Welcome to the Citadel.",
    exitText = "A-Man is down. A pair of joke-shop glasses, a stuck-on moustache and an empty briefcase: that's "
      .. "all that's left of him. Head home.",
    introLine = 9,
  },
  {
    -- Cyber Feud (docs/cyber-feud.md): five maps in Grey City, at night.
    -- The cyber-feud feature runs the levels.
    id = "cyber-feud",
    title = "Courier wanted",
    text = "No questions. A package is waiting in a vending machine downtown in Grey City. Pick it up and "
      .. "get it across town before anyone else does.",
    board = true,
    map = "drop",
    boss = "cyber-feud",
    label = "CYBER FEUD",
    color = { 1, 0.24, 0.78 },
    banner = "%s took the courier job. Welcome to Grey City.",
    exitText = "You're through the roadblock. The tunnel runs on under the city to the Market. Keep moving.",
    exitTitle = "Into the tunnel",
    exitLabel = "MARKET",
    next = "cyber-feud-market",
  },
  {
    -- On foot through the Market: the Drop's tunnel star leads here.
    id = "cyber-feud-market",
    title = "The Market",
    text = "A covered market of stalls round Noodle Square, both sides already in it. Get through on foot.",
    map = "market",
    boss = "cyber-feud",
    label = "CYBER FEUD",
    color = { 1, 0.24, 0.78 },
    banner = "%s came out of the tunnel. Welcome to the Market.",
    introLine = 2,
    exitText = "The dock's clear and there are cars waiting. The Overpass runs out over the city from here.",
    exitTitle = "Onto the Overpass",
    exitLabel = "OVERPASS",
    next = "cyber-feud-overpass",
  },
  {
    -- Driven along the Overpass: the Market's dock star leads here.
    id = "cyber-feud-overpass",
    title = "The Overpass",
    text = "An elevated highway over the city, war-rigs and drones on it. VEX says she knows a shortcut.",
    map = "overpass",
    boss = "cyber-feud",
    label = "CYBER FEUD",
    color = { 1, 0.24, 0.78 },
    banner = "%s took the on-ramp. Welcome to the Overpass.",
    introLine = 3,
    exitText = "The highway runs straight into Halcyon Tower's garage. Get inside.",
    exitTitle = "Into the tower",
    exitLabel = "HALCYON",
    next = "cyber-feud-tower",
  },
  {
    -- Up Halcyon Tower on foot: the Overpass's garage star leads here.
    id = "cyber-feud-tower",
    title = "Halcyon Tower",
    text = "Six floors, every stair door locked, Halcyon above you and the Static coming up behind.",
    map = "tower",
    boss = "cyber-feud",
    label = "CYBER FEUD",
    color = { 1, 0.24, 0.78 },
    banner = "%s got into the tower. Welcome to Halcyon Tower.",
    introLine = 4,
    exitText = "The executive lift goes all the way up. Saye and Kilowatt are waiting on the roof.",
    exitTitle = "Up to the roof",
    exitLabel = "ROOF",
    next = "cyber-feud-roof",
  },
  {
    -- The end of the line: the tower's lift star leads here.
    id = "cyber-feud-roof",
    title = "The Roof",
    text = "The top of Halcyon Tower, in the rain. Everyone who wants you dead is up here.",
    map = "roof",
    boss = "cyber-feud",
    label = "CYBER FEUD",
    color = { 1, 0.24, 0.78 },
    banner = "%s rode the lift up. Welcome to the Roof.",
    introLine = 5,
    exitText = "Saye and Kilowatt are down, and VEX is gone into the net. Nothing personal, courier. Head home.",
  },
  {
    -- Eternal Mood (docs/eternal-mood.md): the UAC's moon base, and it gets
    -- stranger from there. The eternal-mood feature runs the levels; so far
    -- Fobos Base, Heck on Earth, the Foundry and Heck, whose gate goes home.
    id = "eternal-mood",
    title = "Pest control",
    text = "Moon. Bring a shotgun. The UAC opened a door it shouldn't have, and something came through. "
      .. "Get up to the hangar.",
    board = true,
    map = "fobos",
    boss = "eternal-mood",
    label = "ETERNAL MOOD",
    color = { 1, 0.45, 0.1 },
    banner = "%s took the pest-control job. Welcome to Fobos Base.",
    introLine = 1,
    exitText = "The hangar lift goes up to a shuttle, and the shuttle goes down to Earth. It's worse there.",
    exitTitle = "Down to Earth",
    exitLabel = "HECK ON EARTH",
    next = "eternal-mood-earth",
  },
  {
    -- On foot up the road to the starport: Fobos Base's lift star leads here.
    id = "eternal-mood-earth",
    title = "Heck on Earth",
    text = "The portal leaked. Earth is overrun, and the only way on is the road north through the city to the "
      .. "starport. On foot.",
    map = "earth",
    boss = "eternal-mood",
    label = "ETERNAL MOOD",
    color = { 1, 0.45, 0.1 },
    banner = "%s came down off the shuttle. Welcome to Heck on Earth.",
    introLine = 2,
    exitText = "The starport's gate is open. The last shuttle out goes to the Foundry, where they melt Heck down.",
    exitTitle = "Last shuttle out",
    exitLabel = "THE FOUNDRY",
    next = "eternal-mood-foundry",
  },
  {
    -- On foot through the UAC's factory: Earth's starport star leads here.
    id = "eternal-mood-foundry",
    title = "The Foundry",
    text = "The UAC's foundry, where they melt Heck down for fuel. Half of it is Heck's already. The way on is "
      .. "the portal behind the Crucible.",
    map = "foundry",
    boss = "eternal-mood",
    label = "ETERNAL MOOD",
    color = { 1, 0.45, 0.1 },
    banner = "%s came off the shuttle. Welcome to the Foundry.",
    introLine = 3,
    exitText = "The Baron's key opens the portal behind the Crucible. It goes down. All the way down.",
    exitTitle = "Down into Heck",
    exitLabel = "HECK",
    next = "eternal-mood-heck",
  },
  {
    -- On foot across Heck itself: the Foundry's portal leads here.
    id = "eternal-mood-heck",
    title = "Heck",
    text = "Heck itself: rock, lava, bone bridges and every demon there is. The Snooze Gate is at the top.",
    map = "heck",
    boss = "eternal-mood",
    label = "ETERNAL MOOD",
    color = { 1, 0.45, 0.1 },
    banner = "%s came through the portal. Welcome to Heck.",
    introLine = 4,
    exitText = "The Snooze Gate. Something behind it is ticking. That's as far as the job goes for now. Head home.",
  },
  {
    id = "home",
    title = "Back to the City",
    text = "Done here. Call it a day and take everyone back into town.",
    onMap = "culdesac",
    x = 0, -- the entrance of the street
    y = 800,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-forest",
    title = "Back to the City",
    text = "Enough trees for one day. Take everyone back into town.",
    onMap = "forest",
    x = 0, -- the entrance of the trail, between the parked cars
    y = 1164, -- city-map puts the forest entrance (map.cx, map.cy) here
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-beach",
    title = "Back to the City",
    text = "Back in the boat. Take everyone back into town.",
    onMap = "beach",
    x = 0, -- in the surf between the landing craft
    y = 1676, -- city-map puts the beach's way in (map.cx, map.cy) here
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-cliff",
    title = "Back to the City",
    text = "Nobody needs to win this one. Take everyone back into town.",
    onMap = "cliff",
    x = 1238, -- just past the parked cars
    y = 1472, -- city-map puts the bluff's way in (map.cx, map.cy) here
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-city17",
    title = "Back to the City",
    text = "Back on the train. Take everyone home.",
    onMap = "city17",
    x = -1216, -- the left end of the platform: city-map's map.cx, map.cy
    y = 1952,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-citadel",
    title = "Back to the City",
    text = "Back down the lift. Take everyone home.",
    onMap = "citadel",
    x = -166, -- the left end of the lift: city-map's map.cx, map.cy
    y = 2816,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-coast",
    title = "Back to the City",
    text = "Back the way you came. Take everyone home.",
    onMap = "coast",
    x = -808, -- on the landing's sand: city-map's map.cx, map.cy
    y = 3232,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-road",
    title = "Back to the City",
    text = "Turn the car round. Take everyone home.",
    onMap = "road",
    x = -768, -- on the verge by the arrival: city-map's map.cx, map.cy
    y = 6400,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-outercity",
    title = "Back to the City",
    text = "Find a way back in. Take everyone home.",
    onMap = "outercity",
    x = -2016, -- the left end of the arrival square: city-map's map.cx, map.cy
    y = 1408,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-drop",
    title = "Back to the City",
    text = "Back down into the garage. Take everyone home.",
    onMap = "drop",
    x = -1152, -- in the garage: city-map's map.cx, map.cy
    y = 2912,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-market",
    title = "Back to the City",
    text = "Back through the tunnel. Take everyone home.",
    onMap = "market",
    x = -416, -- by the south gate: city-map's map.cx, map.cy
    y = 1568,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-overpass",
    title = "Back to the City",
    text = "Back down the on-ramp. Take everyone home.",
    onMap = "overpass",
    x = 0, -- at the foot of the on-ramp: city-map's map.cx, map.cy
    y = 6304,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-tower",
    title = "Back to the City",
    text = "Back out the front door. Take everyone home.",
    onMap = "tower",
    x = -256, -- by the lobby doors: city-map's map.cx, map.cy
    y = 3408,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-fobos",
    title = "Back to the City",
    text = "Back to the Lab's consoles. Take everyone home.",
    onMap = "fobos",
    x = 0, -- by the Lab's consoles: city-map's map.cx, map.cy
    y = 2112,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-earth",
    title = "Back to the City",
    text = "Back up the shuttle's ramp. Take everyone home.",
    onMap = "earth",
    x = 0, -- by the shuttle in the Depot: city-map's map.cx, map.cy
    y = 4864,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-foundry",
    title = "Back to the City",
    text = "Back up the shuttle's ramp. Take everyone home.",
    onMap = "foundry",
    x = -1312, -- by the shuttle's tail on the Pad: city-map's map.cx, map.cy
    y = 1728,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
  {
    id = "home-heck",
    title = "Back to the City",
    text = "Back through the portal. Take everyone home.",
    onMap = "heck",
    x = 0, -- by the portal on the shelf: city-map's map.cx, map.cy
    y = 2752,
    map = "city",
    returns = true,
    label = "HOME",
    color = { 0.45, 0.75, 1 },
    banner = "%s called it a day. Welcome back to The City.",
  },
}
Quests.byId = {}
Quests.board = {} -- the jobs on the Jobs building's board, in list order
for _, q in ipairs(Quests.list) do
  Quests.byId[q.id] = q
  if q.board then
    Quests.board[#Quests.board + 1] = q
  end
end

-- Progress ----------------------------------------------------------------
-- A new game starts with only the first job on the board open. Finishing a
-- job (its last map: the quest at the end of its `next` chain) opens the
-- one after it on the board, and the world remembers what is finished
-- (serverSaveWorld, written as soon as everyone is home again). A finished job stays open to play again, and the
-- world counts how many times each has been finished (its clears): a boss
-- may come back harder for it (karen does). Other features ask too: the
-- events feature keeps a city event shut until its quest is finished.
Quests.root = {} -- quest id -> the id of the board job its chain starts from
for _, q in ipairs(Quests.board) do
  local step, seen = q, {}
  while step and not seen[step.id] do
    seen[step.id] = true
    Quests.root[step.id] = q.id
    step = Quests.byId[step.next or ""]
  end
end

--- Is board job `quest` open, given `finished` (a set of board job ids)?
--- The first always is; each after it once the one before it is finished.
--- Anything not on the board (a chain's later maps, the way home) is.
function Quests.unlocked(quest, finished)
  if not quest.board then
    return true
  end
  for i, q in ipairs(Quests.board) do
    if q == quest then
      return i == 1 or finished[quest.id] == true or finished[Quests.board[i - 1].id] == true
    end
  end
  return false
end

--- The board job before `quest`, the one to finish to open it.
function Quests.before(quest)
  for i, q in ipairs(Quests.board) do
    if q == quest then
      return Quests.board[i - 1]
    end
  end
end

-- Tuning ------------------------------------------------------------------
Quests.starRadius = 60 -- px from the star that brings the offer up
Quests.leaveRadius = 140 -- px from the star that takes it down again (and forgets a decline)
Quests.starSize = 30 -- px, outer radius of the star
Quests.doorRadius = 60 -- px from the Jobs building's door that lets the board open
Quests.exitClear = 240 -- px an EXIT star keeps from where a boss fell (its drops spread about 80)
Quests.exitSearch = 700 -- px from that spot the star may move to, to be clear of it

local SLACK = 60 -- px the host allows for a taker drawn a little behind where it is
local NOTICE_TIME = 2.5 -- seconds a refusal stays on the offer
local BANNER_TIME = 4 -- seconds the "took the job" banner stays up
local PANEL_W = 560
local REASONS = {
  away = "Get back to the star (or the Jobs door) to take it.",
  gone = "That job is off the table.",
  locked = "Finish the job before it first.",
}

local function cityMap()
  return Features.byName["city-map"]
end

--- The EXIT star a fallen boss leaves on map `onMap` at (x, y): the way
--- home, the same as the blue star by the entrance, or on to the quest
--- that carries on from `done` (its `next`).
local function exitQuest(onMap, x, y, done)
  local city = cityMap()
  local next = done and Quests.byId[done.next or ""]
  if next then
    return {
      id = "exit",
      title = done.exitTitle or next.title,
      text = done.exitText or next.text,
      onMap = onMap,
      x = x,
      y = y,
      map = next.map,
      starts = next.id, -- the quest taking it starts
      label = done.exitLabel or next.label,
      color = next.color,
      banner = next.banner,
    }
  end
  return {
    id = "exit",
    title = "Get out of here",
    text = done and done.exitText or "The boss is down. Head home and leave this place behind.",
    onMap = onMap,
    x = x,
    y = y,
    map = city and city.DEFAULT or "city",
    returns = true,
    label = "EXIT",
    color = { 0.45, 1, 0.75 },
    banner = "%s found the way out. Welcome back to The City.",
  }
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The Jobs building (jobs.lua) while the default city is in play.
function Quests:jobs()
  local city = cityMap()
  if not (city and city.map and city.current == city.DEFAULT) then
    return nil
  end
  return Jobs.of(city.map)
end

--- The quest whose star on map `current` is nearest to (x, y), or the
--- first one there when no position is given. `extra` is an EXIT star, if
--- one is up.
local function offeredOn(current, x, y, extra)
  local best, bestD2
  for i = 1, #Quests.list + 1 do
    local q = Quests.list[i] or extra
    if q and q.onMap == current then
      local d2 = x and dist2(x, y, q.x, q.y) or 0
      if not bestD2 or d2 < bestD2 then
        best, bestD2 = q, d2
      end
    end
  end
  return best
end

-- Client --------------------------------------------------------------------

Quests.active = nil -- id of the quest everyone is on, from the host
Quests.done = nil -- id of a quest finished on this trip (the star home is still the way back)
Quests.prompt = nil -- the quest whose offer is up
Quests.exit = nil -- the EXIT star a fallen boss left, from the host
Quests.atJobs = false -- standing on the square by the Jobs building's door
Quests.boardOpen = false -- the job board is up
Quests.pick = 1 -- the job picked on the board (an index of `Quests.board`)
Quests.finished = {} -- board job id -> true once finished in this world, from the host
Quests.clears = {} -- board job id -> times finished in this world, from the host
Quests.stats = nil -- how the job under way went for me (QST_STATS), from the host
Quests.doneLevel = nil -- the level the job just done was at (QST_DONE), for the victory screen
local victory = nil -- { t } while the victory screen is up at home (someone else took us there)
local offerT = 0 -- seconds the offer has been up
local declined = nil -- quest id turned down; forgotten once you leave its star
local seenMap = nil -- the map the last frame was on, to notice arriving on another
local notice, noticeTimer = nil, 0
local banner, bannerTimer = nil, 0
local time = 0

function Quests:load()
  Controls.register("quest-accept", "Accept a quest (offer up)", "return")
  Controls.register("quest-decline", "Decline a quest (offer up)", "backspace")
  Controls.register("jobs", "Open / close the job board (at the Jobs building)", "f") -- the action key, like the shop's
end

-- QST_MAP and QST_START for a quest under way arrive in the same burst as
-- START, so the quest is only forgotten on the way out.
function Quests:exitGame()
  self.active, self.done, self.prompt, self.exit, declined, seenMap = nil, nil, nil, nil, nil, nil
  self.stats, victory, offerT = nil, nil, 0
  self.atJobs, self.boardOpen, self.pick, self.finished, self.clears = false, false, 1, {}, {}
  notice, noticeTimer, banner, bannerTimer = nil, 0, nil, 0
end

--- The `pointerTaken` convention: the mouse is ours while the board or the
--- victory screen is up.
function Quests:pointerTaken()
  return self.boardOpen or victory ~= nil
end

--- The `closeMenu` convention: Esc takes the board down.
function Quests:closeMenu()
  if not self.boardOpen then
    return false
  end
  self.boardOpen = false
  return true
end

--- The `actionTaken` convention: the action key is ours at the Jobs door
--- and while the board is up, so on-foot leaves the cars alone.
function Quests:actionTaken()
  return self.boardOpen or self.atJobs
end

--- Ask the host for job `quest` (the offer or the board stays up until it
--- answers). A job still locked is refused here and then.
local function accept(client, quest)
  if not Quests.unlocked(quest, Quests.finished) then
    notice, noticeTimer = REASONS.locked, NOTICE_TIME
    return
  end
  client:send(Protocol.encode("QST_ACCEPT", quest.id))
end

--- What the board shows by each job (Jobs.drawBoard's `status`): "done",
--- or for one still locked the line saying what opens it.
local function boardStatus()
  local status = {}
  for _, q in ipairs(Quests.board) do
    if Quests.finished[q.id] then
      status[q.id] = "done"
    elseif not Quests.unlocked(q, Quests.finished) then
      local before = Quests.before(q)
      status[q.id] = "Finish \"" .. (before and before.title or "the job before") .. "\" to open this job."
    end
  end
  return status
end

--- The level each open job is at (Jobs.drawBoard's `levels`): 1 the first
--- time, one more for every time it was finished in this world, as far as
--- its bosses get harder (bosses' `rage.max`). { level, max, times } by id.
local function boardLevels()
  local bosses = Features.byName.bosses
  local most = bosses and bosses.rage and bosses.rage.max or math.huge
  local levels = {}
  for _, q in ipairs(Quests.board) do
    if Quests.unlocked(q, Quests.finished) then
      local times = Quests.clears[q.id] or 0
      levels[q.id] = { level = math.min(times, most) + 1, max = times >= most, times = times }
    end
  end
  return levels
end

--- The board opens on the newest job open: the last one not locked.
local function newestOpen()
  local pick = 1
  for i, q in ipairs(Quests.board) do
    if Quests.unlocked(q, Quests.finished) then
      pick = i
    end
  end
  return pick
end

--- The quest whose star on the map I am on is nearest (x, y), if any.
function Quests:offered(x, y)
  local city = cityMap()
  return city and offeredOn(city.current, x, y, self.exit) or nil
end

--- Is `quest` the way home from a job that is done, on its last map? Then
--- its star offers the victory screen rather than the plain offer.
local function victoryOffer(quest)
  local done = Quests.done and Quests.byId[Quests.done]
  return quest ~= nil and quest.returns == true and done ~= nil and Quests.done == Quests.active and not done.next
end

--- A reward card (the rewards feature) is up over everything and has the keys.
local function rewardUp()
  local rewards = Features.byName.rewards
  return rewards ~= nil and rewards.menuOpen ~= nil and rewards:menuOpen()
end

--- The job `id` belongs to, as it stands on the board (a later map's own
--- title gives away nothing worth seeing on the victory screen).
local function jobOf(id)
  return Quests.byId[Quests.root[id or ""] or id or ""]
end

function Quests:update(dt, client)
  time = time + dt
  if victory then
    victory.t = victory.t + dt
  end
  offerT = self.prompt and offerT + dt or 0
  noticeTimer = math.max(0, noticeTimer - dt)
  bannerTimer = math.max(0, bannerTimer - dt)
  local x, y = client:myPose()
  local jobs = x and self:jobs()
  local jd2 = jobs and dist2(x, y, jobs.doorX, jobs.doorY) or math.huge
  self.atJobs = jd2 <= self.doorRadius ^ 2
  if self.boardOpen and jd2 > self.leaveRadius ^ 2 then
    self.boardOpen = false -- walked off: the board goes down
  end
  local quest = self:offered(x, y)
  local city = cityMap()
  if x and city and city.current ~= seenMap and (seenMap or city.current ~= city.DEFAULT) then
    -- Just arrived (or joined a game out on a quest map): the cars land
    -- beside this map's star, and nobody wants the trip straight back. It
    -- counts as declined until you drive off.
    self.prompt, declined = nil, quest and quest.id or nil
  end
  if x then
    seenMap = city and city.current or nil -- not before we are placed: a latecomer may not be yet
  end
  if not (quest and x) then
    self.prompt, declined = nil, nil
    return
  end
  local d2 = dist2(x, y, quest.x, quest.y)
  if d2 > self.leaveRadius ^ 2 then
    self.prompt, declined = nil, nil -- drove off: the offer goes down and a no is forgotten
  elseif d2 <= self.starRadius ^ 2 and not self.prompt and declined ~= quest.id then
    self.prompt, notice, noticeTimer = quest, nil, 0
  end
end

function Quests:keypressed(key, client)
  if self.boardOpen then
    if Controls.is("jobs", key) or Controls.is("quest-decline", key) then
      self.boardOpen = false
    elseif Controls.is("quest-accept", key) and self.board[self.pick] then
      accept(client, self.board[self.pick])
    end
    return
  end
  if victory then
    if victory.t >= Victory.minTime and not rewardUp() then
      victory = nil -- any key puts it away
    end
    return
  end
  if self.atJobs and Controls.is("jobs", key) and not Features.any("pointerTaken", client) then
    -- (Not under another screen: the board draws over everything, the inventory too.)
    self.boardOpen, self.pick, notice, noticeTimer = true, newestOpen(), nil, 0
    return
  end
  local quest = self.prompt
  if not quest or (victoryOffer(quest) and (offerT < Victory.minTime or rewardUp())) then
    return
  end
  if Controls.is("quest-accept", key) then
    accept(client, quest)
  elseif Controls.is("quest-decline", key) then
    declined, self.prompt = quest.id, nil
  end
end

--- Another screen over ours that has the mouse (the inventory draws on top
--- and takes the clicks meant for it).
local function covered()
  local inventory = Features.byName.inventory
  return inventory and inventory.open or false
end

--- Pick a job on the board, take it, or leave.
function Quests:mousepressed(x, y, button, client)
  if victory and victory.t >= Victory.minTime and not rewardUp() then
    victory = nil
    return
  end
  if not self.boardOpen or button ~= 1 or covered() then
    return
  end
  local L = Jobs.layout(self.board, self.pick, boardStatus())
  for i, r in ipairs(L.rows) do
    if Jobs.inside(r, x, y) then
      self.pick = i
      return
    end
  end
  if Jobs.inside(L.accept, x, y) and self.board[self.pick] then
    accept(client, self.board[self.pick])
  elseif Jobs.inside(L.close, x, y) then
    self.boardOpen = false
  end
end

--- The world softens under the offer and the board, and goes behind the
--- victory screen.
function Quests:worldBlur()
  if victory or (self.prompt and victoryOffer(self.prompt)) then
    return 1
  end
  return (self.prompt or self.boardOpen) and 0.7 or 0
end

--- The ten corners of a five-point star, outer radius R, point up.
local function starPoints(cx, cy, R)
  local pts = {}
  for k = 0, 9 do
    local a = -math.pi / 2 + k * math.pi / 5
    local r = k % 2 == 0 and R or R * 0.42
    pts[#pts + 1] = cx + math.cos(a) * r
    pts[#pts + 1] = cy + math.sin(a) * r
  end
  return pts
end

--- A filled star: five tips, each a triangle, on a pentagon. LÖVE only
--- fills convex polygons, so the concave outline is drawn in pieces.
local function fillStar(cx, cy, R)
  local p = starPoints(cx, cy, R)
  local function at(j)
    j = j % 10
    return p[2 * j + 1], p[2 * j + 2]
  end
  local pentagon = {}
  for k = 0, 4 do
    local ox, oy = at(2 * k)
    local ax, ay = at(2 * k - 1)
    local bx, by = at(2 * k + 1)
    love.graphics.polygon("fill", ox, oy, ax, ay, bx, by)
    pentagon[#pentagon + 1], pentagon[#pentagon + 2] = bx, by
  end
  love.graphics.polygon("fill", pentagon)
  return p
end

--- The stars on the road: a soft glow the size of the trigger, the star
--- itself breathing slowly, and its name underneath.
function Quests:drawBelowCars()
  local city = cityMap()
  for _, quest in ipairs(self.list) do
    if city and quest.onMap == city.current then
      self:drawStar(quest)
    end
  end
  if city and self.exit and self.exit.onMap == city.current then
    self:drawStar(self.exit)
  end
  local jobs = self:jobs()
  if jobs then
    Jobs.drawBuilding(jobs, fillStar, self.doorRadius, self.atJobs, time)
  end
end

--- At night (the night feature), every star on this map glows so it can be found.
function Quests:drawNightLights(_client, _camera, glow)
  local city = cityMap()
  if not city then
    return
  end
  for _, quest in ipairs(self.list) do
    if quest.onMap == city.current then
      glow(quest.x, quest.y, 110, quest.color, 0.9)
    end
  end
  if self.exit and self.exit.onMap == city.current then
    glow(self.exit.x, self.exit.y, 110, self.exit.color, 0.9)
  end
end

--- The Jobs building on the minimap: a gold star, so it can be found.
function Quests:drawOnMinimap(_client, toMap)
  local jobs = self:jobs()
  if not jobs then
    return
  end
  local x, y = toMap(jobs.x + jobs.w / 2, jobs.y + jobs.h / 2)
  love.graphics.setColor(0, 0, 0, 0.8)
  fillStar(x, y, 7)
  love.graphics.setColor(1, 0.85, 0.3)
  fillStar(x, y, 5.5)
  love.graphics.setColor(1, 1, 1)
end

function Quests:drawStar(quest)
  local pulse = 0.5 + 0.5 * math.sin(time * 2.5)
  local size = self.starSize * (0.92 + 0.08 * pulse)
  local c = quest.color or { 1, 0.85, 0.3 }
  local label = quest.label or "QUEST"
  love.graphics.setColor(c[1], c[2], c[3], 0.10 + 0.08 * pulse)
  love.graphics.circle("fill", quest.x, quest.y, self.starRadius)
  love.graphics.setColor(c[1], c[2], c[3], 0.35 + 0.25 * pulse)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", quest.x, quest.y, self.starRadius)
  love.graphics.setColor(0, 0, 0, 0.35)
  fillStar(quest.x + 4, quest.y + 4, size)
  love.graphics.setColor(c[1], c[2], c[3])
  local outline = fillStar(quest.x, quest.y, size)
  love.graphics.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
  love.graphics.setLineWidth(3)
  love.graphics.polygon("line", outline)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(label, quest.x - 59, quest.y + size + 7, 120, "center")
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.printf(label, quest.x - 60, quest.y + size + 6, 120, "center")
  love.graphics.setColor(1, 1, 1)
end

--- The offer: what the job is, and the keys to take it or leave it.
local function drawPrompt(quest)
  local w, h = love.graphics.getDimensions()
  local inner = PANEL_W - 48
  local _, lines = UI.fonts.body:getWrap(quest.text, inner)
  local textH = #lines * UI.fonts.body:getHeight()
  local _, titleLines = UI.fonts.heading:getWrap(quest.title, inner)
  local titleH = #titleLines * UI.fonts.heading:getHeight()
  local ph = 24 + UI.fonts.small:getHeight() + 8 + titleH + 14 + textH + 44 + 26
  local px, py = math.floor((w - PANEL_W) / 2), math.floor((h - ph) / 2)

  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.10, 0.10, 0.13, 0.96)
  love.graphics.rectangle("fill", px, py, PANEL_W, ph, 10)
  love.graphics.setColor(1, 0.85, 0.3, 0.8)
  love.graphics.rectangle("line", px, py, PANEL_W, ph, 10)

  local y = py + 24
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.printf("QUEST", px, y, PANEL_W, "center")
  y = y + UI.fonts.small:getHeight() + 8
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(quest.title, px + 24, y, inner, "center")
  y = y + titleH + 14
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0.85, 0.85, 0.88)
  love.graphics.printf(quest.text, px + 24, y, inner, "center")
  y = y + textH + 14

  love.graphics.setFont(UI.fonts.small)
  if noticeTimer > 0 then
    love.graphics.setColor(1, 0.45, 0.4, math.min(1, noticeTimer * 2))
    love.graphics.printf(notice, px, y, PANEL_W, "center")
  end
  y = y + 30
  local yes = Controls.name(Controls.bindings("quest-accept")[1])
  local no = Controls.name(Controls.bindings("quest-decline")[1])
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.printf(yes .. ": accept   " .. no .. ": decline", px, y, PANEL_W, "center")
  love.graphics.setColor(1, 1, 1)
end

function Quests:drawHUD(client)
  local w = love.graphics.getWidth()
  if self.active then
    local quest = self.byId[self.active]
    local city = cityMap()
    local where = city and city.map.title
    love.graphics.setFont(UI.fonts.small)
    local label = "Quest: " .. (quest and quest.title or self.active)
    if self.done == self.active then
      love.graphics.setColor(0.5, 1, 0.6)
      label = "Quest complete: " .. (quest and quest.title or self.active)
    else
      love.graphics.setColor(1, 0.85, 0.3)
    end
    if where then
      label = label .. "  (" .. where .. ")"
    end
    love.graphics.print(label, 10, 190)
  end
  if bannerTimer > 0 and banner then
    local a = math.min(1, bannerTimer * 2)
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.6 * a)
    love.graphics.printf(banner.title, 1, 111, w, "center")
    love.graphics.setColor(1, 0.85, 0.3, a)
    love.graphics.printf(banner.title, 0, 110, w, "center")
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0, 0, 0, 0.6 * a)
    love.graphics.printf(banner.text, 1, 145, w, "center")
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.printf(banner.text, 0, 144, w, "center")
  end
  if self.prompt and client and not victoryOffer(self.prompt) then
    drawPrompt(self.prompt)
  end
  if self.atJobs and not self.boardOpen and client then
    -- On the square with the board down: the offer, where the shop's stands.
    local h = love.graphics.getHeight()
    local text = "Jobs.  " .. Controls.name(Controls.bindings("jobs")[1]) .. ": open the job board"
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf(text, 1, h - 129, w, "center")
    love.graphics.setColor(1, 0.85, 0.3)
    love.graphics.printf(text, 0, h - 130, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

--- The board goes over every HUD piece (the core's `drawScreen`): our
--- priority (22) would put it under nearly all of them.
function Quests:drawScreen(client)
  local offer = self.prompt and victoryOffer(self.prompt)
  if client and (victory or offer) then
    local job = jobOf(victory and victory.questId or self.done)
    local hint = "press any key"
    if not victory then
      local yes = Controls.name(Controls.bindings("quest-accept")[1])
      local no = Controls.name(Controls.bindings("quest-decline")[1])
      hint = yes .. ": go home   " .. no .. ": stay a while"
      if noticeTimer > 0 and notice then
        hint = notice .. "   " .. hint
      end
    end
    Victory.draw({ title = job and job.title, color = job and job.color, stats = self.stats, hint = hint,
      level = self.doneLevel },
      victory and victory.t or offerT, time, fillStar)
  end
  if self.boardOpen and client then
    local city = cityMap()
    local places = {}
    for _, q in ipairs(self.board) do
      places[q.id] = city and city.maps[q.map] and city.maps[q.map].title or q.map
    end
    local yes = Controls.name(Controls.bindings("quest-accept")[1])
    local no = Controls.name(Controls.bindings("jobs")[1])
    local shown = noticeTimer > 0 and { text = notice, alpha = math.min(1, noticeTimer * 2) } or nil
    local status = boardStatus()
    Jobs.drawBoard(Jobs.layout(self.board, self.pick, status), self.pick, places, shown, { yes, no }, status,
      boardLevels())
    local vision = Features.byName.vision
    if vision then
      vision:drawCursor(client) -- over the board, not under it
    end
    love.graphics.setColor(1, 1, 1)
  end
end

Quests.clientMessages = {
  QST_MAP = function(_client, args)
    local city = cityMap()
    if city and city.maps[args[1] or ""] then
      city:switchTo(args[1]) -- does nothing on the host's own client: the server already switched
    end
  end,
  QST_START = function(client, args)
    local quest, by = Quests.byId[args[1] or ""], tonumber(args[2])
    if args[1] == "exit" then
      quest = Quests.exit
    end
    if not quest then
      return
    end
    Quests.exit = nil -- any trip leaves the fallen boss's star behind
    local ended = Quests.active and Quests.byId[Quests.active]
    local won = ended and Quests.done == ended.id and not ended.next
    Quests.active = not quest.returns and quest.id or nil
    Quests.done = nil
    Quests.boardOpen = false
    Quests.prompt = nil -- `declined` is left alone: update sets it for the star we land next to
    local taker = client:nameOf(by) -- they may have left since (a latecomer hears this too)
    local city = cityMap()
    local where = city and city.maps[quest.map] and city.maps[quest.map].title or quest.map
    local text = quest.banner or ("%s took the job. Welcome to " .. where .. ".")
    banner = { title = quest.title:upper(), text = text:format(taker or "Someone") }
    bannerTimer = BANNER_TIME
    if quest.returns then
      if won and by ~= client.myId then
        victory = { t = 0, questId = ended.id } -- somebody else took us home: here is how it went
      end
      if ended then
        Features.call("questEnded", client, ended)
      end
    else
      if quest.board then
        Quests.stats, Quests.doneLevel = nil, nil -- a new job: the host counts from nothing again
      end
      Features.call("questStarted", client, quest, by)
    end
  end,
  QST_DONE = function(_client, args)
    local quest = Quests.byId[args[1] or ""]
    if quest then
      Quests.done = quest.id
      -- Its level, from the times it was finished before this one (the host's
      -- count of this one comes after QST_DONE).
      local bosses = Features.byName.bosses
      Quests.doneLevel = bosses and bosses.clientClears and bosses.clientClears() + 1 or 1
      banner = { title = "JOB DONE", text = quest.title }
      bannerTimer = BANNER_TIME
    end
  end,
  QST_EXIT = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    local city = cityMap()
    if x and y and city then
      Quests.exit = exitQuest(city.current, x, y, Quests.byId[Quests.done or ""])
    end
  end,
  QST_HELD = function(_client, args)
    -- Taken, and something is happening first: the offer goes down and stays down.
    if Quests.prompt and Quests.prompt.id == args[1] then
      declined, Quests.prompt = args[1], nil
    end
  end,
  QST_FINISHED = function(_client, args)
    Quests.finished, Quests.clears = {}, {}
    for i = 1, #args - 1, 2 do
      local id, n = args[i], tonumber(args[i + 1])
      if Quests.byId[id] and n and n > 0 then
        Quests.finished[id], Quests.clears[id] = true, n
      end
    end
  end,
  QST_NO = function(_client, args)
    notice = REASONS[args[1]]
    noticeTimer = notice and NOTICE_TIME or 0
  end,
  QST_STATS = function(_client, args)
    local n = {}
    for i = 1, 5 do
      n[i] = math.max(0, math.floor(tonumber(args[i]) or 0))
    end
    local unlocks = {}
    for i = 6, #args do
      unlocks[#unlocks + 1] = args[i]
    end
    Quests.stats = { time = n[1], kills = n[2], deaths = n[3], koins = n[4], bosses = n[5], unlocks = unlocks }
  end,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { active = quest id or nil, by = player id, done = quest id or nil, exit = EXIT star or nil,
--                  finished = { [board job id] = true }, clears = { [board job id] = times finished },
--                  fallen = { { x, y }... } where bosses went down on the map in play }

Quests.SAVE_VERSION = 1

--- QST_FINISHED with every board job finished and its clears, in board order.
local function finishedMessage()
  local parts = {}
  for _, q in ipairs(Quests.board) do
    if sv.finished[q.id] then
      parts[#parts + 1] = q.id
      parts[#parts + 1] = sv.clears[q.id] or 1
    end
  end
  return Protocol.encode("QST_FINISHED", unpack(parts))
end

-- City-map (lower priority) has put the default map back by now.
function Quests:serverStart()
  sv = { active = nil, by = nil, done = nil, finished = {}, clears = {}, fallen = {} } -- a new game: the first job
  Stats.stop()
end

--- Something died: a boss's spot is kept (the EXIT star stays clear of it),
--- and the job's stats count it.
function Quests:serverKill(server, kill)
  if not sv then
    return
  end
  if kill.kind == "boss" and kill.x and kill.y then
    sv.fallen[#sv.fallen + 1] = { x = kill.x, y = kill.y }
  end
  Stats.kill(server, kill)
end

--- A koin went into `player`'s wallet off the ground (money).
function Quests:serverKoinTaken(_server, player)
  Stats.koin(player)
end

--- `player` unlocked something for good (weapons, gear, grenades).
function Quests:serverRewarded(_server, player, title)
  Stats.reward(player, title)
end

function Quests:serverStep(server, dt)
  Stats.step(server, dt)
end

--- Within `exitClear` of where a boss fell on this map?
local function nearFallen(x, y)
  for _, f in ipairs(sv.fallen) do
    if dist2(x, y, f.x, f.y) < Quests.exitClear ^ 2 then
      return true
    end
  end
  return false
end

--- Can a star stand at (x, y): its whole ring on ground somebody can get to?
local function openGround(city, x, y)
  if city:outOfReach(x, y) then
    return false
  end
  for k = 0, 8 do
    local r = k == 0 and 0 or Quests.starRadius
    local a = k * math.pi / 4
    if Features.any("blocksPoint", x + math.cos(a) * r, y + math.sin(a) * r) then
      return false
    end
  end
  return true
end

--- Where an EXIT star meant for (x, y) goes: there, unless a boss fell
--- close by; then the nearest open road or ground clear of every boss that
--- fell (nothing found: where it was meant to go after all).
function Quests:serverExitSpot(x, y)
  local city = cityMap()
  if not (sv and city and city.randomRoadPoint) or not nearFallen(x, y) then
    return x, y
  end
  local bx, by, bestD2
  for _ = 1, 120 do
    local px, py = city:randomRoadPoint(x, y, self.exitSearch)
    if px and not nearFallen(px, py) and openGround(city, px, py) then
      local d2 = dist2(px, py, x, y)
      if not bestD2 or d2 < bestD2 then
        bx, by, bestD2 = px, py, d2
      end
    end
  end
  if bx then
    return bx, by
  end
  return x, y
end

--- The job under way is finished (the karen feature says so when she goes
--- down). Everyone hears it; the star home is still the way back. Given
--- where the boss fell (x, y), an EXIT star home comes up there too.
function Quests:serverComplete(server, questId, x, y)
  if not (sv and sv.active == questId) then
    return false
  end
  sv.done = questId
  server:broadcast(Protocol.encode("QST_DONE", questId))
  local root = Quests.root[questId]
  if root and not Quests.byId[questId].next then
    sv.finished[root] = true -- the last map of the job: the next one on the board opens
    sv.clears[root] = (sv.clears[root] or 0) + 1
    server:broadcast(finishedMessage())
  end
  if not Quests.byId[questId].next then
    Stats.finish(server) -- the job's last map: the clock stops
  end
  local city = cityMap()
  if x and y and city then
    x, y = self:serverExitSpot(x, y)
    sv.exit = exitQuest(city.current, x, y, Quests.byId[questId])
    server:broadcast(Protocol.encode("QST_EXIT", ("%.1f"):format(x), ("%.1f"):format(y)))
  end
  return true
end

--- Take everyone on `quest` (or home, for one that `returns`), taken by
--- `player`: the trip itself, with no checks. Taking a star comes here
--- once the host has checked it; the --quest launch option (src/launch.lua)
--- comes straight here.
function Quests:serverBegin(server, quest, player)
  local city = cityMap()
  if not (sv and city and city.maps[quest.map]) then
    return false
  end
  local ended = sv.active and Quests.byId[sv.active]
  sv.exit, sv.fallen = nil, {} -- any trip leaves the fallen boss and its star behind
  if quest.returns then
    Stats.flush(server, true) -- everyone's last numbers, before the trip home puts the victory screen up
  elseif quest.board or not Stats.running() then
    Stats.begin() -- a job's first map; the maps after it carry on counting
  end
  if quest.returns then
    sv.active, sv.by, sv.done = nil, nil, nil
  else
    sv.active, sv.by, sv.done = quest.id, player.id, nil
  end
  -- QST_MAP first: whatever features send from mapChanged is about the
  -- new map, so clients must be on it by then.
  server:broadcast(Protocol.encode("QST_MAP", quest.map))
  city:switchTo(quest.map, server) -- moves every car; features hear mapChanged
  server:broadcast(Protocol.encode("QST_START", quest.id, player.id))
  if quest.returns then
    Stats.stop()
    if ended then
      Features.call("serverQuestEnded", server, ended)
    end
    -- The world is not written while everyone is away (city-map's
    -- serverWorldSaveHeld), so write it now: a job finished on that trip
    -- is kept even if the host quits on the next one before an autosave.
    if server.save then
      server:save()
    end
  else
    Features.call("serverQuestStarted", server, quest, player)
  end
  return true
end

--- Has board job `id` been finished in this world (its last map done)?
function Quests:serverFinished(id)
  return sv ~= nil and sv.finished[id] == true
end

--- How many times board job `id` has been finished in this world (0 for never).
function Quests:serverClears(id)
  return sv and sv.clears[id] or 0
end

--- The world remembers which jobs are finished, and how many times.
function Quests:serverSaveWorld()
  if not (sv and next(sv.finished)) then
    return nil
  end
  local clears = {}
  for id in pairs(sv.finished) do
    clears[id] = sv.clears[id] or 1
  end
  return { version = self.SAVE_VERSION, clears = clears }
end

function Quests:serverLoadWorld(server, data)
  if not sv or type(data) ~= "table" or data.version ~= self.SAVE_VERSION or type(data.clears) ~= "table" then
    return
  end
  for id, n in pairs(data.clears) do
    n = tonumber(n)
    if Quests.byId[id] and Quests.byId[id].board and n and n >= 1 then
      sv.finished[id], sv.clears[id] = true, math.floor(n)
    end
  end
  server:broadcast(finishedMessage())
end

--- The quest under way on the host, for other features; nil between jobs.
function Quests:serverActive()
  return sv and sv.active and self.byId[sv.active] or nil
end

--- Anyone joining mid-game hears which map is in play and what job is on,
--- before real-estate (higher priority) tells them how it has grown. A
--- human joining the lobby hears nothing: `sv` may be the last game's.
function Quests:serverPlayerJoined(server, player)
  local city = cityMap()
  if not (sv and city and server.started) or player.bot then
    return
  end
  if next(sv.finished) then
    server:send(player, finishedMessage())
  end
  if city.current ~= city.DEFAULT then
    server:send(player, Protocol.encode("QST_MAP", city.current))
  end
  if sv.active then
    server:send(player, Protocol.encode("QST_START", sv.active, sv.by))
  end
  if sv.done then
    server:send(player, Protocol.encode("QST_DONE", sv.done))
  end
  if sv.exit then
    server:send(player, Protocol.encode("QST_EXIT", ("%.1f"):format(sv.exit.x), ("%.1f"):format(sv.exit.y)))
  end
end

--- Is the player's body (not a wreck) on the star, or for a job on the
--- board at the Jobs building's door?
local function onStar(server, player, quest)
  if not Features.present(player) then
    return false
  end
  local x, y = Features.bodyPose(server, player)
  if quest.board then
    local jobs = Quests:jobs()
    return jobs ~= nil and dist2(x, y, jobs.doorX, jobs.doorY) <= (Quests.doorRadius + SLACK) ^ 2
  end
  return dist2(x, y, quest.x, quest.y) <= (Quests.starRadius + SLACK) ^ 2
end

Quests.serverMessages = {
  QST_ACCEPT = function(server, player, args)
    local quest = Quests.byId[args[1] or ""]
    if args[1] == "exit" then
      quest = sv and sv.exit
    end
    local city = cityMap()
    if not (sv and quest and city and player.body) then
      return
    end
    local reason
    local here
    if quest.board then
      here = Quests:jobs() ~= nil -- the Jobs building is only in the default city
    else
      here = quest.onMap == city.current
    end
    if not here or not city.maps[quest.map] then
      reason = "gone" -- that star is not on this map (someone else's trip already happened)
    elseif not onStar(server, player, quest) then
      reason = "away"
    elseif not Quests.unlocked(quest, sv.finished) then
      reason = "locked"
    else
      local trip = Quests.byId[quest.starts or ""] or quest -- an EXIT star on starts the next
      if Features.any("serverHoldTrip", server, trip, player) then
        server:broadcast(Protocol.encode("QST_HELD", quest.id))
      else
        Quests:serverBegin(server, trip, player)
      end
      return
    end
    server:send(player, Protocol.encode("QST_NO", reason))
  end,
}

--- For tests.
function Quests.server()
  return sv
end

return Quests
