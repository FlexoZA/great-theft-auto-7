-- The words of the Borderline quest line (docs/borderline.md), in one
-- place: each map's banner, Maximum Maximilian Max's intro screen lines, the
-- story beats said over the comms by Max and by YAP-TP ("Yappy"), their
-- chatter, and the objective line. Data only; init.lua and hud.lua use it.

local Story = {}

Story.LEVELS = 8

-- Who talks over the comms: the name shown and its colour.
Story.speakers = {
  max = { name = "MAXIMUM MAXIMILIAN MAX", color = { 0.95, 0.76, 0.19 } },
  yappy = { name = "YAP-TP", color = { 0.35, 0.75, 1.00 } },
}

-- The banner that comes up on arriving on each map: where in the line it
-- is, its name and a tagline.
Story.banners = {
  wreck = { n = 1, title = "THE FROZEN WRECK", tagline = "Left for dead. Not dead." },
  landing = { n = 2, title = "LIAR'S LANDING", tagline = "Everything here belongs to Max. Including the ice." },
  pit = { n = 3, title = "THE BRAGIUM PIT", tagline = "Purple rock. Expensive. Explodes." },
  prosperity = { n = 4, title = "PROSPERITY", tagline = "Built by robots, for robots. Humans tolerated." },
  refinery = { n = 5, title = "THE REFINERY", tagline = "Where the purple gets melted down." },
  assembly = { n = 6, title = "THE ASSEMBLY LINE", tagline = "Where the army gets built." },
  cuts = { n = 7, title = "THOUSAND PAPERCUTS", tagline = "One road up. Every gun he has left." },
  bunker = { n = 8, title = "THE BUNKER", tagline = "He says it flies." },
}

-- What Max says on his intro screen, one line per level (quests'
-- `introLine` picks it on arrival).
Story.lines = {
  "That train hit the snow at maximum speed. Biggest crash on record. TO THE MAX!",
  "The biggest docks on Pandoria. Maximum cranes. Maximum guns. Enjoy!",
  "The deepest hole on the planet. I dug it to the max. Mind the glowing rock.",
  "My city! The biggest statue, the biggest screens, the biggest me. TO THE MAX!",
  "The hottest river in the galaxy. I turned it up. Then I turned it up again.",
  "A robot every four seconds. I asked for two. Every one has your name on it.",
  "One road, a thousand guns. I wanted a million. We're getting there.",
  "You found my bunker! It flies. Of course it flies. TO THE MAX!",
}

-- Story beats: the host raises each once per level (BRL_BEAT), so every
-- screen says the same. Each is a list of { who, text } said over the comms
-- in order. Keys are "<map>.<what>": "start" (just after arriving), a
-- zone's name (city-map's `map.zones`) for walking into it, "fight" (the
-- first time the army spots anyone), "open" (the last of the map's
-- terminals hacked, its lock open), "end" (the way on reached).
Story.beats = {
  ["wreck.start"] = {
    { "yappy", "Minion! You're alive! I dug you out. With a clipboard. It took ages." },
    { "yappy", "I'm YAP-TP, Mr. Max's secretary. Was. He put me on that train too. I know the way to his bunker. "
      .. "Probably. Follow me. Go first." },
  },
  ["wreck.fight"] = { { "yappy", "Junk bots! Stripping the train! I am bravely hiding!" } },
  ["wreck.The Wreck"] = { { "max", "Twelve carriages, one fireball. When I crash, I crash to the max." } },
  ["wreck.The Engine"] = { { "yappy", "The tunnel's past the engine."
    .. " I can see it from here. Well. I can imagine it." } },
  ["wreck.scrapper"] = {
    { "yappy", "Power's on! Wait. Why is the engine moving? Minion, the train is getting UP. It's building "
      .. "itself out of the wreck!" },
    { "max", "Oh, that's the Knuckle Scrapper! A junk hauler that wanted to be bigger. I respect that. "
      .. "TO THE MAX!" },
    { "yappy", "The little junk bots are carrying it scrap! Shoot them before they get there, or it heals!" },
  },
  ["wreck.scrapper-down"] = {
    { "yappy", "It fell apart! The blast door's opening. I'd like to say I helped. I'm going to say it anyway." },
    { "max", "My train! Twice in one day! Fine. The next thing I build out of it will be bigger." },
  },
  ["wreck.end"] = { { "yappy", "Into the tunnel, minion. The harbour's on the other side. Mind the bats. "
    .. "There are no bats." } },

  ["landing.start"] = {
    { "yappy", "Liar's Landing! The ferry lift crosses the bay, but it's shuttered. There's a control terminal "
      .. "in every corner of the yard. Hack all four, then get on the lift and I'll do the rest. From over here." },
    { "max", "You're still alive! Fantastic! Guards? Maximum guards!" },
  },
  ["landing.fight"] = { { "yappy", "Gun haulers! The good ones! Tactical retreat! Tactical retreat!" } },
  ["landing.The Quay"] = { { "yappy", "The lift! Up on the quay! Shoot the rocket ones first. I'll supervise." } },
  ["landing.open"] = {
    { "yappy", "That's the last terminal! The shutters are coming off the lift. Get on it, minion!" },
    { "max", "You opened my lift? Fantastic! That means a bigger welcome party. TO THE MAX!" },
  },
  ["landing.hold"] = {
    { "yappy", "You're on! Hacking now. Stay on the lift. They'll come at you. That's sort of the plan." },
  },
  ["landing.half"] = { { "max", "Somebody's on my ferry! Send everything. Then send more. TO THE MAX!" } },
  ["landing.end"] = { { "yappy", "We did it! By we I mean me. The lift goes over to Mr. Max's mine." } },

  ["pit.start"] = {
    { "yappy", "The Bragium Pit. All that purple powers his robots. His friends call him MMM. He doesn't have "
      .. "friends. He has robots." },
    { "max", "Welcome to the Pit! I dug it so deep the core sends me postcards." },
    { "yappy", "The pit's floor is gated off. Four power terminals round the terraces: hack them all to get down "
      .. "there. Wilbur has the mine lift's code. Probably. He has everything." },
  },
  ["pit.open"] = {
    { "yappy", "Power's on! The gates to the floor are open. Something big's waiting down there. It's Wilbur. "
      .. "It's always Wilbur." },
    { "max", "You opened the floor? Fantastic! Wilbur's been waiting all day. TO THE MAX!" },
  },
  ["pit.fight"] = { { "yappy", "Purple bolts! They melt armour! Duck! I'm ducking! I'm very good at ducking!" } },
  ["pit.The Pit"] = { { "yappy", "Down the ramps, round the rings, up the other side. Easy. For you." } },
  ["pit.The Mine Lift"] = { { "yappy", "The mine lift comes up under Prosperity. His city. He'll love that." } },
  ["pit.wilbur"] = {
    { "max", "Wilbur! My best employee. Ninety per cent machine, ten per cent payroll, a hundred and ten per "
      .. "cent effort!" },
    { "yappy", "That's Wilbur. He was in accounting. Now he IS accounting. Shoot his drones first!" },
  },
  ["pit.upgrade"] = { { "max", "Wilbur, you're doing great. Let's go bigger. Upgrade authorised. TO THE MAX!" } },
  ["pit.wilbur-down"] = {
    { "yappy", "Wilbur's down! He dropped something. His keycard! That's the mine lift's code. Grab it, minion!" },
    { "max", "What a fight! Wilbur gave it everything. The next one gets twice the everything." },
  },
  ["pit.keycard"] = {
    { "yappy", "Got it! The mine lift's open. I'll put Wilbur on gardening leave." },
    { "max", "Keep the card, bandit. Consider it a promotion. TO THE MAX!" },
  },
  ["pit.end"] = { { "max", "Coming up to my city? Excellent! Everybody should see it. Bring friends!" } },

  ["prosperity.start"] = {
    { "max", "Welcome to Prosperity! Maximum prosperity. Mostly for me." },
    { "yappy", "Look at all his faces! On every screen! We should leave before he sees us. Oh. He sees us." },
    { "yappy", "The north gate's shut. Four giant screens, one in every corner of town. I say we shoot them. "
      .. "All of them. For morale." },
  },
  ["prosperity.screen1"] = {
    { "max", "You broke a screen? No problem. The others just went brighter. MAXIMUM brightness!" },
  },
  ["prosperity.screen2"] = {
    { "yappy", "Two down! That's half his faces. He has more faces. He has so many faces." },
    { "max", "Love the energy! Double brightness on the rest. TO THE MAX!" },
  },
  ["prosperity.screen3"] = {
    { "max", "One screen left! Triple brightness! Wear sunglasses! I am!" },
  },
  ["prosperity.screens"] = {
    { "max", "You took out every screen! Biggest audience I ever had. Open the north gate! A show this big "
      .. "needs a bigger stage!" },
    { "yappy", "He's opening the gate himself. Of course he is. North gate, minion! Go!" },
  },
  ["prosperity.fight"] = { { "yappy", "Jet haulers! They fly! That's not fair! I'm in heels!" } },
  ["prosperity.Max Plaza"] = { { "max", "Like the statue? It's me. Twice life-size. I asked for three." } },
  ["prosperity.North District"] = { { "yappy", "The north gate! It goes down to the refinery. Shut, while "
    .. "his screens are up. He wants us to watch the show first." } },
  ["prosperity.end"] = { { "max", "Bravo! On to the refinery. It's hotter. Maximum hot. You'll love it." } },

  ["refinery.start"] = {
    { "yappy", "The refinery. Don't fall in the river. You won't come out. I mean that medically." },
    { "yappy", "Every bridge is up. Of course it is. There's a bridge control on each bank. Hack one, the next "
      .. "bridge comes down. I'll do the waving." },
  },
  ["refinery.bridge1"] = {
    { "yappy", "It's coming down! First crossing, minion. Don't look down. Don't look at the arc haulers either." },
    { "max", "You lowered a bridge? Ha! I've got three more. Every one hotter than the last. TO THE MAX!" },
  },
  ["refinery.bridge2"] = {
    { "yappy", "Two down! I mean two lowered. That's the opposite of down. You know what I mean. Cross!" },
  },
  ["refinery.bridge3"] = {
    { "max", "Bandit, you're halfway across my river! Nobody gets halfway! I'm turning the river up." },
    { "yappy", "He can't turn the river up. Can he? Hurry." },
  },
  ["refinery.bridge4"] = {
    { "yappy", "That's the last bridge! The outflow's across it, and the freight door. And the big ones. "
      .. "Of course the big ones." },
    { "max", "Every bridge down? Magnificent! The outflow team is VERY excited to meet you." },
  },
  ["refinery.smelter"] = {
    { "max", "Bandit, meet the Smelter! It melts down everything I don't need anymore. You, for example." },
    { "yappy", "It's climbing out of the casting pit! Don't stand in front of it when its belly opens. "
      .. "And when it vents, shoot it! That's the soft bit. Softer bit." },
  },
  ["refinery.smelter-down"] = {
    { "yappy", "It's gone out! The freight door's opening. I'm putting that down as a team win." },
    { "max", "My Smelter! Do you know what a furnace like that costs? Neither do I. I've never looked." },
  },
  ["refinery.fight"] = { { "yappy", "Arc haulers on the bridges! Don't stand in the blue! It tingles! It kills!" } },
  ["refinery.The Smelting Floor"] = { { "max", "Every bridge is hotter than the last. Keep going, it gets better!" } },
  ["refinery.The Outflow"] = { { "yappy", "The freight door! Past the big ones. Of course past the big ones." } },
  ["refinery.end"] = { { "yappy", "The factory's through there. I did its paperwork. Six years. "
    .. "Nobody said thank you." } },

  ["assembly.start"] = {
    { "yappy", "I typed up the order for every robot off this line. Every one. I'm fine. It's the fumes." },
    { "max", "YAP-TP! Still alive? Great hustle! You're fired. Maximum fired." },
    { "yappy", "The stairs up are shuttered while the Fabricators run. Two of them, one each side. Break "
      .. "them and the line stops. Mind the belts, they go places. Without asking." },
  },
  ["assembly.fabricator"] = {
    { "max", "You broke a Fabricator? It cost more than your planet. Good thing I have another one." },
  },
  ["assembly.fabricators"] = {
    { "yappy", "The line's stopped! The shutters are up! Stairs, minion! The Foreman's up there. Bring snacks." },
    { "max", "My Fabricators! Both! You know what? Respect. The Foreman will see you now." },
  },
  ["assembly.fight"] = { { "yappy", "They're waking up off the belts! Shoot the new ones! They're shiny!" } },
  ["assembly.The Foreman's Floor"] = {
    { "max", "My foreman's floor! He built a robot a minute. I said: make it two." },
  },
  ["assembly.foreman"] = {
    { "max", "Foreman BIG-B055! My best manager. Never takes a break. I took them away." },
    { "yappy", "It's awake! It blows that whistle, the crane brings it another robot. Shoot the new ones before "
      .. "they gang up. Or after. I'm not your boss. He is." },
  },
  ["assembly.rip"] = {
    { "yappy", "It tore its own cannon off! That's a safety violation! It's going to charge. Get a wall behind "
      .. "you and step aside!" },
    { "max", "Overtime, Foreman! No breaks, no cannons, no brakes! TO THE MAX!" },
  },
  ["assembly.foreman-down"] = {
    { "yappy", "The Foreman's down! The shipping bay's opening. I'm writing it a reference. It'll be short." },
    { "max", "My Foreman! Who's going to tell the robots what to do now? Me? I don't know how robots work!" },
  },
  ["assembly.end"] = { { "yappy", "The shipping bay! The road up to the bunker starts outside. Uphill. Of course." } },

  ["cuts.start"] = {
    { "max", "Thousand Papercuts! I counted the guns myself. Then I doubled them. TO THE MAX!" },
    { "yappy", "Stick to the road. The other side is a cliff. The other other side is also a cliff." },
  },
  ["cuts.pursuit"] = {
    { "max", "Everything I've got left is coming up that road behind you. And the artillery. Run, bandit! RUN!" },
    { "yappy", "He's shelling the road behind us! Up, minion! Up, up, up! Don't stop!" },
  },
  ["cuts.stall"] = {
    { "yappy", "Why are we stopping?! The road is exploding! Behind us! Which is where we are!" },
  },
  ["cuts.hold"] = {
    { "yappy", "The door! I'm in. Sort of. Stand by me, they're all coming up the road. Every single one." },
  },
  ["cuts.half"] = { { "max", "You're knocking on my door? RUDE. Everybody, up the road. Bring the big one!" } },
  ["cuts.fight"] = { { "yappy", "Rockets on the ledges! Keep moving! I'll keep moving too! Backwards!" } },
  ["cuts.The Cuts"] = { { "yappy", "Every hole in the rock has a gun in it. Every one. I "
    .. "counted. I stopped counting." } },
  ["cuts.The Bunker Door"] = { { "yappy", "The bunker door! I'll open it! I have a lot of tabs open. "
    .. "Give me a minute." } },
  ["cuts.end"] = { { "yappy", "Open! I did that. Remember I did that. Up onto the roof!" } },

  ["bunker.start"] = {
    { "max", "You're on my bunker! The biggest bunker ever built. Hold on to something." },
    { "yappy", "Eleven cannons round the rim. They lob shells. Watch for the red rings and don't stand in them. "
      .. "That's most of my advice. Also: shoot the cannons." },
  },
  ["bunker.cannon"] = {
    { "max", "You broke a cannon! I have ten more. I counted them myself. Twice." },
  },
  ["bunker.cannons"] = {
    { "yappy", "Half of them down! The roof's getting quieter. I don't trust quiet. It's usually Max planning." },
  },
  ["bunker.bnk"] = {
    { "yappy", "That's the last cannon! The hatch is opening, his computer's down th... no. No no no. Something's "
      .. "coming up." },
    { "max", "Meet BNK-9! The bunker's brain, the bunker's heart, the bunker's FLYING PART. TO THE MAX!" },
    { "yappy", "Shoot the eye! The big red one! It's always the eye!" },
  },
  ["bunker.fury"] = {
    { "max", "You've made BNK-9 angry. I didn't know it could be angry. I'm a little bit proud." },
    { "yappy", "It's faster! It's smoking! That's good smoking! Keep going!" },
  },
  ["bunker.bnk-down"] = {
    { "yappy", "It's down! BNK-9 is down! The hatch is clear. His computer's right there, minion!" },
    { "max", "No. No no no. That was my BEST thing. I'm going to have to think of a new best thing." },
  },
  ["bunker.fight"] = { { "max", "Cannons! All of them! Every cannon! TO THE MAX!" } },
  ["bunker.end"] = {
    { "yappy", "We did it! I'm on his computer. His password's 'TOTHEMAX'. Shutting down every robot on "
      .. "Pandoria..." },
    { "yappy", "...Did we win? I feel like I won." },
    { "max", "What a finish! The biggest loss in Hyperbole history. Next time, bandit: bigger. TO THE MAX!" },
  },
}

-- What they say now and then (BRL_CHAT <who> <category> <index>), picked
-- by the host.
Story.chatter = {
  max = {
    taunt = {
      "I built every robot you're shooting. I'll build more. I always build more.",
      "I don't do anything halfway. I don't even know where halfway is.",
      "My friends call me MMM. You can call me Maximum.",
      "Twelve eggs for breakfast. Maximum protein. TO THE MAX!",
      "You're on every camera I own. That's all of them. I own all the cameras.",
      "I've named a robot after you. The biggest one. It's still being built.",
    },
    kill = {
      "A prototype! Love it. The next one's bigger.",
      "I'll build ten more. No: a hundred. TO THE MAX!",
      "Great shot! Now watch what I send next.",
      "Every robot you drop, I build a bigger one. Keep going!",
    },
    down = {
      "Down! Did you see that? Maximum replay. Somebody clip that.",
      "Respawn's on me. I own the respawn stations. The biggest ones.",
      "Get up, bandit! You're not done. I'm not done. Nobody's done!",
    },
  },
  yappy = {
    down = {
      "Minion down! Get up! I can't do this alone! I won't do this alone!",
      "Ow! That looked like it hurt. Did it hurt? Get up.",
    },
    alone = { -- nobody on the spot she is hacking (hold.lua)
      "Minion? The lift? I can't hack it if nobody's standing on it. That's the rule. I made the rule.",
      "Hello? I've stopped. I'm not hacking a lift nobody's guarding. I have standards.",
      "Back on the lift! Every second you're off it, I'm just sitting here. Typing nothing.",
    },
    win = {
      "We did it! By we I mean me.",
      "Another one down! I'm keeping score. I'm winning.",
    },
  },
}

-- The objective line while the way on is shut behind terminals (the
-- terminals feature), by map: `%d` how many are left.
Story.hack = {
  wreck = "Objective: hack Hyperbole's terminals to get the tunnel's power back on (%d left)",
  landing = "Objective: hack the ferry's control terminals round the yard (%d left)",
  pit = "Objective: hack the power terminals round the terraces to open the pit's floor (%d left)",
  refinery = "Objective: hack the bridge control on this bank to lower the next bridge",
}

-- The objective line and the HUD bar while the way on waits for a hold
-- (hold.lua), by map: before it starts, while it runs (`%d` the percent
-- done), while nobody is on the spot.
Story.hold = {
  cuts = {
    before = "Objective: up the road to the bunker door, and hold it while Yappy opens it",
    during = "Objective: hold the bunker door while Yappy opens it (%d%%)",
    paused = "Objective: get back to the bunker door, Yappy's hack is paused",
    bar = "YAPPY OPENING THE BUNKER DOOR",
  },
  landing = {
    before = "Objective: get to the ferry lift on the quay and hold it while Yappy hacks it",
    during = "Objective: hold the ferry lift while Yappy hacks it (%d%%)",
    paused = "Objective: get back on the ferry lift, Yappy's hack is paused",
    bar = "YAPPY HACKING THE FERRY LIFT",
  },
}

-- The objective line while Max's screens are up (screens.lua): `%d` how many.
Story.screens = "Objective: shoot down Max's big screens (%d left)"

-- The objective line while the Bunker's rim cannons stand (the army's CAN): `%d` how many.
Story.cannons = "Objective: shoot down the cannons round the rim (%d left)"

-- The objective line while the Fabricators stand (fabricators.lua): `%d` how many.
Story.fabricators = "Objective: shoot down the Fabricators to open the stairs (%d left)"

-- The objective line while the way on waits for the level's boss, by map:
-- before it comes (pointing where it will), while it is up, and while
-- what it dropped waits to be picked up (`card`).
Story.boss = {
  bunker = {
    during = "Objective: bring BNK-9 down (shoot its eye, get out of the red line)",
  },
  assembly = {
    during = "Objective: take Foreman BIG-B055 down (shoot what the crane brings, dodge its charge)",
  },
  refinery = {
    during = "Objective: put the Smelter out (out of its lane when it gushes, shoot it when it vents)",
  },
  wreck = {
    during = "Objective: take the Knuckle Scrapper down (shoot the junk carrying it scrap)",
  },
  pit = {
    before = "Objective: get down to the pad on the pit's floor",
    during = "Objective: take Wilbur down (shoot his drones first)",
    card = "Objective: pick up Wilbur's keycard, the mine lift's code",
  },
}

--- The objective line for map `name` on `map`. `state` says what holds
--- the way on: `done` (the level is), `waiting` terminals (the nearest
--- `nearest`); on a map with a hold, how far it is (`held`, nil before it
--- starts) and whether anyone is on it (`on`); on a map with a boss,
--- `boss` "pad" (not come yet: it comes at `bossX`, `bossY`) or "fight";
--- on a map with Max's screens, those still up (`screens`, `screenNearest`);
--- on a map with Fabricators, those still up (`fabricators`, `fabricatorNearest`);
--- on the Bunker, its rim cannons still up (`cannons`, `cannonNearest`).
--- Returns the text and where it points (x, y in world px).
function Story.objective(name, map, state)
  local done, waiting, nearest = state.done, state.waiting, state.nearest
  local boss = Story.boss[name]
  if not done and boss and state.boss == "fight" then -- the boss first, while it is up
    return boss.during
  end
  if not done and (waiting or 0) > 0 and nearest then
    return (Story.hack[name] or "Objective: hack the terminals (%d left)"):format(waiting), nearest.x, nearest.y
  end
  if not done and #(state.screens or {}) > 0 then -- Max's screens to shoot down
    local s = state.screenNearest
    return Story.screens:format(#state.screens), s and s.x, s and s.y
  end
  if not done and #(state.cannons or {}) > 0 then -- the rim cannons to shoot down
    local c = state.cannonNearest
    return Story.cannons:format(#state.cannons), c and c.x, c and c.y
  end
  if not done and #(state.fabricators or {}) > 0 then -- the Fabricators to shoot down
    local f = state.fabricatorNearest
    return Story.fabricators:format(#state.fabricators), f and f.x, f and f.y
  end
  local hold = Story.hold[name]
  if not done and hold and map.hold then
    local hx, hy = map.hold.x + map.hold.w / 2, map.hold.y + map.hold.h / 2
    if not state.held then
      return hold.before, hx, hy
    elseif state.on then
      return hold.during:format(math.floor(state.held * 100))
    end
    return hold.paused, hx, hy
  end
  if not done and boss and (state.boss == "pad" or state.boss == "card") then
    return state.boss == "card" and boss.card or boss.before, state.bossX, state.bossY
  end
  if done then
    if name == "bunker" then
      return "Objective: take the EXIT star home"
    end
    return "Objective: take the star on"
  end
  local where = {
    wreck = "Objective: get past the wreck to the tunnel at the top of the yard",
    landing = "Objective: get through the container yard to the ferry lift on the quay",
    pit = "Objective: down through the pit and up to the mine lift on the far rim",
    prosperity = "Objective: through Max's city to the north gate",
    refinery = "Objective: across the river to the freight door",
    assembly = "Objective: up the factory floor to the shipping bay",
    cuts = "Objective: up the road to the bunker door",
    bunker = "Objective: down the eye's hatch to his computer",
  }
  if where[name] then
    return where[name], map.exitX, map.exitY
  end
  return nil
end

return Story
