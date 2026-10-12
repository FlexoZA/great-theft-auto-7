-- The words of the Cyber Feud quest line (docs/cyber-feud.md), in one place:
-- each map's banner, VEX's intro screen lines, the story beats she talks
-- through, and the objective line. Data only; init.lua and hud.lua use it.

local Story = {}

Story.LEVELS = 5

-- The banner that comes up on arriving on each map: where in the line it
-- is, its name and a tagline.
Story.banners = {
  drop = { n = 1, title = "THE DROP", tagline = "Downtown. Somebody's package." },
  market = { n = 2, title = "THE MARKET", tagline = "Everybody's market. Nobody's friend." },
  overpass = { n = 3, title = "THE OVERPASS", tagline = "The long way up." },
  tower = { n = 4, title = "HALCYON TOWER", tagline = "Visitors by appointment only." },
  roof = { n = 5, title = "THE ROOF", tagline = "Nowhere left to go but down." },
}

-- What VEX says on her intro screen, one line per level (quests'
-- `introLine` picks it on arrival; on the Drop the "drop.boot" beat does,
-- when she boots up halfway up the map).
Story.lines = {
  "Hey, courier. Nice earpiece. I'm in it now. Run.",
  "Crowded in there. Good. Crowds are safe. Usually.",
  "I found you a shortcut. You're going to love it.",
  "Their security is a mess. I'll get you in. Getting out is on you.",
  "Funny thing about the receipts, courier. My name's on them too.",
}

-- Story beats: the host raises each once per level (CF_BEAT), so every
-- screen shows the same. `screen` puts up her intro screen with that line,
-- `say` is what she says over the comms after it. Keys are "<map>.<what>":
-- a zone's name (city-map's `map.zones`) for walking into it, "boot" (the
-- Drop's halfway line, once someone has the Shard), "knot" (the Overpass's
-- dead end), "end" (the level's far end reached).
Story.beats = {
  ["drop.boot"] = {
    screen = 1,
    say = "Tunnel's at the top of the middle avenue. Ignore the roadblock. It's decorative.",
  },
  ["drop.The Tunnel"] = { say = "Big roadblock, huh. Halcyon's very proud of it. Go round." },
  ["drop.end"] = { say = "See? Easy. Into the tunnel, courier. Market's on the other side." },

  ["market.The Lanes"] = {
    say = "Halcyon has the east side, the Static have the west. You have the middle. Lucky you.",
  },
  ["market.Noodle Square"] = { say = "Smile, courier. You're on my screen." },
  ["market.The Dock"] = { say = "Cars at the dock. I may have borrowed them. Don't scratch anything." },
  -- General Volt (volt.lua): the fight starting, and his pass code picked up.
  ["market.volt"] = {
    say = "Ah. That's Volt, Kilowatt's general. He has the dock's code. He also knew you were coming. Unrelated.",
  },
  ["market.code"] = { say = "There's the code. Dock's open. See? Everything's going to plan. Somebody's plan." },
  ["market.end"] = { say = "Nicely done. Five stars. The Overpass is right there." },

  ["overpass.The Overpass"] = { say = "Long road, nobody on it. Probably. Keep it in the middle lanes." },
  ["overpass.The Roadworks"] = { say = "Roadworks ahead. Take the off-ramp on the right. Trust me." },
  ["overpass.knot"] = { say = "Huh. Dead end. Must be the wrong exit. Back up onto the highway, quick." },
  ["overpass.The Tower Ramp"] = { say = "Halcyon Tower. Big, isn't it. The garage is open. I opened it." },
  ["overpass.end"] = { say = "You're in. Don't touch anything. Actually, touch everything." },

  ["tower.Offices"] = { say = "Offices. Nobody works late at Halcyon. Nobody leaves, either." },
  ["tower.Servers"] = { say = "Ooh, my favourite floor. Mind the racks. They bite." },
  ["tower.Labs"] = { say = "Don't look in the tanks. ...You looked in the tanks." },
  ["tower.Security"] = { say = "Security floor. They know you're coming. No idea how." },
  ["tower.Executive"] = { say = "Saye's floor. Wipe your feet. The lift's past the boardroom." },
  -- VEX opening a stair door for you (gates.lua): and the guard room with it, every time.
  ["tower.vex1"] = { say = "There you go, one door. ...And one guard room. Ignore them. They're on a break." },
  ["tower.vex2"] = { say = "Open! Oh. Wrong button. Well, it's open now. All of it." },
  ["tower.vex3"] = { say = "Door's open. So's security's break room. I'm sure they won't mind." },
  ["tower.end"] = { say = "Lift's waiting. Going up. All the way up." },

  -- VEX's phase (vex.lua): she takes the roof, and loses it a relay at a time.
  ["roof.vexLock"] = { say = "Sorry, courier. Roof's closed. Management's changed. It's me. I'm management." },
  ["roof.vex1"] = { say = "Ow. That one was load-bearing." },
  ["roof.vex2"] = { say = "Rude. I was using that. You know I'm the cameras, right?" },
  ["roof.vex3"] = { say = "Okay. Okay. Let's talk about this. Ten percent. Twenty." },
  ["roof.end"] = { say = "Well. That's the job done, I suppose. Nothing personal, courier." },
}

-- Kilowatt's cameo on the Overpass (war_rigs.lua): riding his rig past
-- everyone, landing on the road when it crashes, and running off the edge.
Story.kilowatt = {
  ride = "THERE you are, spark!",
  land = "Ha! That tickled. Do it again.",
  exit = "See you upstairs, spark! HA!",
}

-- What the factions' troops say (troops.lua), by side and category; the
-- host picks one by index:
--   idle   now and then, at a post or on a beat
--   reply  a mate answering
--   alert  one who has just spotted a player
--   rival  one who has just spotted the other side
--   down   one near a mate who just went down
--   truce  where the two sides hold fire (the Overpass), when a flare-up between them dies down
--   breakIn  the Static's, one of a pack breaking in to a floor of the tower after you
Story.troops = {
  halcyon = {
    idle = {
      "Roadblock holding. Logging it.",
      "Code green, no visitors.",
      "Reminder: overtime is not approved.",
      "Checkpoint nominal.",
      "Rain again. Filing a complaint.",
      "Badge check at the barrier. Nobody.",
    },
    reply = { "Copy. Logged.", "Noted.", "Acknowledged.", "Understood. Carry on.", "Confirmed." },
    alert = {
      "Unscheduled contractor, sector four.",
      "Visitor without a badge.",
      "Courier sighted. Engaging.",
      "Package carrier on the avenue.",
    },
    rival = { "Static on the street!", "Gang activity, engage.", "Unlicensed chrome. Remove it.", "Static incursion!" },
    down = { "Officer down. Filing it.", "We have a casualty.", "Man down. Requesting cleanup.", "Lost one. File it." },
    truce = { "Hold fire on the Static. Courier first.", "Cease fire. Priorities.", "Stand down. Paperwork later." },
  },
  static = {
    idle = {
      "Bored. Somebody start something.",
      "Who took my battery?",
      "My arm's itching again.",
      "Rain's getting in my ports.",
      "Wanna go poke a suit?",
      "Quiet. I hate quiet.",
    },
    reply = { "Shut up.", "Ha! Yeah.", "Same.", "Tell Kilowatt, not me.", "Whatever, chrome-for-brains." },
    alert = { "COURIER! Get 'em!", "There's the delivery!", "Nice shoes! Mine!", "Package! Grab it!" },
    rival = { "Grey suits! Light 'em up!", "Corp-meat at twelve!", "Suits on our street!", "Halcyon! Get some!" },
    down = { "They got Ratchet!", "Oh, that's gonna leave a mark.", "Man down! Man DOWN!", "Who's got spare parts?!" },
    truce = { "Easy, suit. Courier first, then you.", "Fine! Truce! For now!", "Save it for the courier!" },
    breakIn = { "We're in! Up, up, UP!", "Find the courier! Every floor!", "Kilowatt wants that Shard!",
      "Mind the suits. Or don't!" },
  },
}

--- The objective line for map `name`, given whether someone has the Shard,
--- whether the level is done and which bosses are still up (a name, or
--- names: "Kilowatt and Saye"), nil for none. Returns the
--- text and where it points (x, y in world px, for the distance), from `map`.
function Story.objective(name, map, shard, done, boss)
  if done then
    if name == "roof" then
      return "Objective: take the EXIT star home"
    end
    return "Objective: take the star on"
  end
  if name == "drop" then
    if not shard then
      return "Objective: get the package from the vending machine by the garage", map.pickupX, map.pickupY
    end
    return "Objective: get the Shard to the tunnel at the top of the middle avenue", map.exitX, map.exitY
  elseif name == "market" then
    return "Objective: get through the Market to the loading dock", map.exitX, map.exitY
  elseif name == "overpass" then
    return "Objective: drive the Overpass to Halcyon Tower", map.exitX, map.exitY
  elseif name == "tower" then
    return "Objective: climb to the executive lift", map.exitX, map.exitY
  elseif name == "roof" and boss then
    return "Objective: take down " .. boss
  elseif name == "roof" then
    return "Objective: get to the helipad", map.exitX, map.exitY
  end
  return nil
end

return Story
