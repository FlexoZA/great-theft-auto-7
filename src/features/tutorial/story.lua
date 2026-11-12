-- Every line Shoeman says in the tutorial (docs/tutorial.md, "Cast" and
-- "Levels"), keyed by beat. Data only; comms.lua plays it.
--
-- A beat is a list of lines said over the comms in order. A line is a
-- string, or { "TEXT", shout = true } for one he bellows (red face, wide
-- mouth: the "DODGE!!!!" before a throw). `{name}` in a line is replaced
-- with the key bound to control `name` (`{move}` with the four walking
-- keys), so the lessons name the player's own keys.
--
-- Keys are "<quest id>.<what>": "start" a moment after a level begins;
-- the rest when the host sees it happen (level 1's: road.lua, and "flat"
-- from the tutorial's serverKill). Later stages add their own (a dodge, a
-- wave down).

local Story = {}

-- The name on the comms panel and its colour (his t-shirt's navy, lifted
-- so it reads on the dark panel).
Story.speaker = { name = "SHOEMAN", color = { 0.45, 0.58, 0.95 } }

Story.beats = {
  -- Level 1, cross the road: the opening speech, walking and running,
  -- then the stamina lesson as it happens (road.lua).
  ["tutorial-1.start"] = {
    "You. Yes, YOU. Look at you. Soft hands. Soft head. Public school, was it? Thought so.",
    "The world out there has gone WOKE. Violent and woke. Cars, guns, robots, and nobody even says sorry.",
    "I am Shoeman. I am going to teach you to survive it. Whether you like it or not. You won't like it.",
    "Lesson one: walking. {move}. Even a public school kid can manage that. Probably.",
    "Lesson two: hold {sprint} to run. Walk across that road and they'll scrape you off it.",
    "Four streets. Nobody brakes for you, and one touch from a car is all it takes.",
    "Get to the other side. Alive, ideally. I'm not carrying you.",
  },
  -- Somebody's stamina went down for the first time.
  ["tutorial-1.sprint"] = {
    "See that green bar going down? Stamina. Running eats it. So does a dodge.",
    "Stop running and it rests a moment, then fills up again. Pace yourself.",
  },
  -- Somebody ran their bar empty.
  ["tutorial-1.spent"] = {
    { "EMPTY!", shout = true },
    "Now you walk until it comes back. Let go of {sprint}: leaning on it gets you nothing.",
  },
  -- Somebody reached the pavement between two streets.
  ["tutorial-1.strip"] = {
    "Pavement. Nothing drives on it. Stand here, get your breath back, then the next street.",
  },
  -- The first player run over.
  ["tutorial-1.flat"] = {
    "Flat as a pancake. Back to the checkpoint with you.",
    "The first lane comes from the LEFT. It's painted on the kerb. They taught reading at your school, yes?",
  },
  -- Somebody is past the last street.
  ["tutorial-1.across"] = {
    "Well, well. Still in one piece. The way on is right there on the grass. Don't trip.",
  },

  -- Level 2, dodge: the dodge lesson, then a shoe every five seconds
  -- (shoe.lua), each one shouted first.
  ["tutorial-2.start"] = {
    "The park. Grass, trees, a pond. And me, with a bag of shoes. You can guess the rest.",
    "Lesson three: the dodge. Press {dodge} and you jump the way you're walking. Standing still, the way you face.",
    "Every dodge costs stamina, and you need a breath before the next one. Mash it and you'll be lying in the grass.",
    "When I shout, watch the shoe. I aim where you stand when I let go, so dodge when it's in the air, not before.",
    "My shoes don't wound. They END. Ask the last kid.",
  },
  -- The first shoe dodged.
  ["tutorial-2.dodged"] = {
    "Hm. Not bad. Luck, probably. Again.",
  },
  -- The fifth dodge: the way on is open and he stops throwing.
  ["tutorial-2.open"] = {
    "FIVE. Fine. You can move when it matters. I'm almost proud. Almost.",
    "The gate's at the top of the park. Off you go, before I find another shoe.",
  },
  -- The first player a shoe went through.
  ["tutorial-2.hit"] = {
    "Too early, too late, or not at all. Back to the checkpoint. The shoes you dodged still count. I'm fair like that.",
  },
  -- He winds up: the telegraph. All shouting, so it cuts in (comms.lua).
  ["tutorial-2.dodge"] = {
    { "DODGE!!!!", shout = true },
  },

  -- Level 3, the scrap yard: picking up and equipping (pistol.lua drops
  -- the pistol while he says so), then shooting.
  ["tutorial-3.start"] = {
    "The scrap yard. Everything in here was somebody's pride and joy once. Now it's cover.",
    "Lesson four: guns. There's a pistol on the ground by me. One each. Don't fight over it, it's embarrassing.",
    "Walk over it to pick it up. It goes in your bag, where it is about as dangerous as you are.",
  },
  -- The first player with a pistol in their bag.
  ["tutorial-3.picked"] = {
    "Now open your bag with {inventory} and drag the pistol into a weapon slot. A gun in a bag shoots nobody.",
  },
  -- The first player with it in a weapon slot.
  ["tutorial-3.equipped"] = {
    "There. Armed. Mostly dangerous to yourself, but armed.",
    "Now {fire} and keep firing until the magazine is empty. Shoot a wreck. Not me.",
  },
  -- The first magazine fired dry.
  ["tutorial-3.emptied"] = {
    "Click. That's the sound of you dying. Watch the count by your gun, down at the bottom.",
    "Press {reload} to reload. Pull the trigger on an empty gun and it reloads too, slowly, while something eats you.",
  },
  -- The first reload done after that.
  ["tutorial-3.reloaded"] = {
    "Good. The pistol never runs out, it only needs reloading. Every other gun eats ammo, and ammo costs money.",
  },
}

return Story
