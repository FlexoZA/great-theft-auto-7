-- The words of the Borderline quest line (docs/borderline.md), in one
-- place: each map's banner, Handsome Jerry's intro screen lines, the story
-- beats said over the comms by Jerry and by YAP-TP ("Yappy"), their
-- chatter, and the objective line. Data only; init.lua and hud.lua use it.

local Story = {}

Story.LEVELS = 8

-- Who talks over the comms: the name shown and its colour.
Story.speakers = {
  jerry = { name = "HANDSOME JERRY", color = { 0.95, 0.76, 0.19 } },
  yappy = { name = "YAP-TP", color = { 0.35, 0.75, 1.00 } },
}

-- The banner that comes up on arriving on each map: where in the line it
-- is, its name and a tagline.
Story.banners = {
  wreck = { n = 1, title = "THE FROZEN WRECK", tagline = "Left for dead. Not dead." },
  landing = { n = 2, title = "LIAR'S LANDING", tagline = "Everything here belongs to Jerry. Including the ice." },
  pit = { n = 3, title = "THE BRAGIUM PIT", tagline = "Purple rock. Expensive. Explodes." },
  prosperity = { n = 4, title = "PROSPERITY", tagline = "Built by robots, for robots. Humans tolerated." },
  refinery = { n = 5, title = "THE REFINERY", tagline = "Where the purple gets melted down." },
  assembly = { n = 6, title = "THE ASSEMBLY LINE", tagline = "Where the army gets built." },
  cuts = { n = 7, title = "THOUSAND PAPERCUTS", tagline = "One road up. Every gun he has left." },
  bunker = { n = 8, title = "THE BUNKER", tagline = "He says it flies." },
}

-- What Jerry says on his intro screen, one line per level (quests'
-- `introLine` picks it on arrival).
Story.lines = {
  "Sorry about the train. And the snow. And you.",
  "Lovely docks. All mine. Please stop walking on them.",
  "That glowing rock pays for everything. Don't touch it.",
  "My city! Built by robots, for robots. Humans tolerated.",
  "It's like a hot tub, but it melts you.",
  "Every one of these has your name on it. Engraved.",
  "Nobody gets through the Cuts. Nobody nice, anyway.",
  "You found my bunker. Here's the thing: it flies.",
}

-- Story beats: the host raises each once per level (BRL_BEAT), so every
-- screen says the same. Each is a list of { who, text } said over the comms
-- in order. Keys are "<map>.<what>": "start" (just after arriving), a
-- zone's name (city-map's `map.zones`) for walking into it, "fight" (the
-- first time the army spots anyone), "end" (the way on reached).
Story.beats = {
  ["wreck.start"] = {
    { "yappy", "Minion! You're alive! I dug you out. With my hands. I have two." },
    { "yappy", "I am YAP-TP, and I know the way to Jerry's bunker. Probably. Follow me. Go first." },
  },
  ["wreck.fight"] = { { "yappy", "Junk bots! Stripping the train! I am bravely hiding!" } },
  ["wreck.The Wreck"] = { { "jerry", "That was a very expensive train. I'm adding it to your bill." } },
  ["wreck.The Engine"] = { { "yappy", "The tunnel's past the engine."
    .. " I can see it from here. Well. I can imagine it." } },
  ["wreck.end"] = { { "yappy", "Into the tunnel, minion. The harbour's on the other side. Mind the bats. "
    .. "There are no bats." } },

  ["landing.start"] = {
    { "yappy", "Liar's Landing! The ferry lift crosses the bay. We just need to get to it." },
    { "jerry", "Oh good, you're still alive. That's... great. Guards? Guards." },
  },
  ["landing.fight"] = { { "yappy", "Gun haulers! The good ones! Tactical retreat! Tactical retreat!" } },
  ["landing.The Quay"] = { { "yappy", "The lift! Up on the quay! Shoot the rocket ones first. I'll supervise." } },
  ["landing.end"] = { { "yappy", "We did it! By we I mean me. The lift goes over to Jerry's mine." } },

  ["pit.start"] = {
    { "yappy", "The Bragium Pit. All that purple is what powers his robots. And his ego." },
    { "jerry", "Don't touch the rock. Don't touch the robots. Don't touch anything. Leave." },
  },
  ["pit.fight"] = { { "yappy", "Purple bolts! They melt armour! Duck! I'm ducking! I'm very good at ducking!" } },
  ["pit.The Pit"] = { { "yappy", "Down the ramps, round the rings, up the other side. Easy. For you." } },
  ["pit.The Mine Lift"] = { { "yappy", "The mine lift comes up under Prosperity. Jerry's city. He'll love that." } },
  ["pit.end"] = { { "jerry", "No. No no no. Not my city. Somebody lock the... oh, it's open. Great." } },

  ["prosperity.start"] = {
    { "jerry", "Welcome to Prosperity! You can't afford it." },
    { "yappy", "Look at all his faces! On every screen! We should leave before he sees us. Oh. He sees us." },
  },
  ["prosperity.fight"] = { { "yappy", "Jet haulers! They fly! That's not fair! I can't even jump!" } },
  ["prosperity.Jerry Plaza"] = { { "jerry", "Do you like the statue? It's me. It's life-size." } },
  ["prosperity.North District"] = { { "yappy", "The north gate! It goes down to the refinery. And it's "
    .. "open! Jerry, you idiot!" } },
  ["prosperity.end"] = { { "jerry", "Fine. Go. Go to the refinery. It's hot there. Very hot. Have fun." } },

  ["refinery.start"] = {
    { "yappy", "The refinery. Don't fall in the river. You won't come out. I mean that medically." },
  },
  ["refinery.fight"] = { { "yappy", "Arc haulers on the bridges! Don't stand in the blue! It tingles! It kills!" } },
  ["refinery.The Smelting Floor"] = { { "jerry", "Every bridge you cross, I'm charging a toll. Retroactively." } },
  ["refinery.The Outflow"] = { { "yappy", "The freight door! Past the big ones. Of course past the big ones." } },
  ["refinery.end"] = { { "yappy", "The factory's through there. Where they build them. Where they built... me." } },

  ["assembly.start"] = {
    { "yappy", "This is where they made YAP units. Before they stopped. I'm fine. My eye is leaking. It's oil." },
    { "jerry", "Is that a YAP unit? I recalled those. Every last one. Apparently not every last one." },
  },
  ["assembly.fight"] = { { "yappy", "They're waking up off the belts! Shoot the new ones! They're shiny!" } },
  ["assembly.The Foreman's Floor"] = { { "jerry", "That's my foreman's floor. He doesn't like visitors. Or me." } },
  ["assembly.end"] = { { "yappy", "The shipping bay! The road up to the bunker starts outside. Uphill. Of course." } },

  ["cuts.start"] = {
    { "jerry", "Thousand Papercuts. Nobody makes it up. Well, nobody has so far. Statistically, you won't." },
    { "yappy", "Stick to the road. The other side is a cliff. The other other side is also a cliff." },
  },
  ["cuts.fight"] = { { "yappy", "Rockets on the ledges! Keep moving! I'll keep moving too! Backwards!" } },
  ["cuts.The Cuts"] = { { "yappy", "Every hole in the rock has a gun in it. Every one. I "
    .. "counted. I stopped counting." } },
  ["cuts.The Bunker Door"] = { { "yappy", "The bunker door! I'll open it! I have a lot of tabs open. "
    .. "Give me a minute." } },
  ["cuts.end"] = { { "yappy", "Open! I did that. Remember I did that. Up onto the roof!" } },

  ["bunker.start"] = {
    { "jerry", "You're on my bunker. Get off my bunker." },
    { "yappy", "Eleven cannons round the rim. They come up when you get close. Like me. Less friendly." },
  },
  ["bunker.fight"] = { { "jerry", "Cannons! All of them! Every cannon!" } },
  ["bunker.end"] = {
    { "yappy", "We did it! I'll plug in and shut the whole army down. Every robot on Pandoria. Every robot..." },
    { "yappy", "...Did we win? I feel like I won." },
    { "jerry", "You'll pay for this. Literally. I'm billing you." },
  },
}

-- What they say now and then (BRL_CHAT <who> <category> <index>), picked
-- by the host.
Story.chatter = {
  jerry = {
    taunt = {
      "I built every robot you're shooting. Think about my feelings.",
      "Fun fact: you're not the hero. I am.",
      "Do you know what those cost? Do you? I do.",
      "I could stop this any time. I just don't want to.",
      "You're on every camera I own. You have a weird walk.",
      "I've named a robot after you. It's the one that sweeps.",
    },
    kill = {
      "That was a prototype! Do you know what those cost?",
      "Fine. FINE. I'll build ten more.",
      "That one had a family. A product family.",
      "I'm putting that on your tab.",
    },
    down = {
      "Ha! Did you see that? Somebody clip that.",
      "Respawn's on me. Literally. I own the respawn stations.",
      "Stay down. It's comfier.",
    },
  },
  yappy = {
    down = {
      "Minion down! Get up! I can't do this alone! I won't do this alone!",
      "Ow! That looked like it hurt. Did it hurt? Get up.",
    },
    win = {
      "We did it! By we I mean me.",
      "Another one down! I'm keeping score. I'm winning.",
    },
  },
}

--- The objective line for map `name` on `map`, given whether the level is
--- done. Returns the text and where it points (x, y in world px).
function Story.objective(name, map, done)
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
    prosperity = "Objective: through Jerry's city to the north gate",
    refinery = "Objective: across the river to the freight door",
    assembly = "Objective: up the factory floor to the shipping bay",
    cuts = "Objective: up the road to the bunker door",
    bunker = "Objective: take the bunker's roof",
  }
  if where[name] then
    return where[name], map.exitX, map.exitY
  end
  return nil
end

return Story
