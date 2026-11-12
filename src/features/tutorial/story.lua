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

  -- Level 3, the scrap yard: picking up and equipping (gift.lua drops
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
    "Now shut up and listen. Hear that scratching? Bigfoot came through here once. He left his squirrels.",
    "They bite, and they don't stop biting. Shoot them before they reach you. Use the wrecks. Keep moving.",
  },
  -- A wave comes out of the burrows (waves.lua). All shouting: it cuts in.
  ["tutorial-3.out"] = {
    { "HERE THEY COME!", shout = true },
  },
  -- A wave shot down; the third is the way on (wave3).
  ["tutorial-3.wave1"] = {
    "Six. Not bad. There's more where they came from. There's always more.",
  },
  ["tutorial-3.wave2"] = {
    "Last lot coming. Make it count.",
  },
  -- The third wave down: the way on, at the gate, is open.
  ["tutorial-3.wave3"] = {
    "That's the lot. You can point a gun and pull a trigger. Your public school would be amazed.",
    "The gate's at the top of the yard, right of the middle. Off you go.",
  },
  -- The first player the squirrels got.
  ["tutorial-3.bitten"] = {
    "Eaten by squirrels. I'll put that on your headstone. Back to the checkpoint, the ones you shot stay shot.",
  },

  -- Level 4, open borders: the ability lesson. gift.lua drops openborders
  -- while he says so.
  ["tutorial-4.start"] = {
    "Town. A hospital, a shop, people. Civilisation, or what's left of it.",
    "Lesson five: abilities. Tricks you carry besides a gun. I've put one down by me. One each, again.",
    "Open Borders, it's called. Don't look at me like that, I didn't name it. Walk over it.",
  },
  -- Somebody got here without a pistol: he put one in their hand.
  ["tutorial-4.armed"] = {
    "No gun? Did you skip the scrap yard? Here. A pistol. You'll want it later, trust me.",
  },
  -- The first player with it in their bag.
  ["tutorial-4.picked"] = {
    "Same as the pistol: {inventory}, then drag it into an ability slot. An ability in a bag does nothing either.",
  },
  -- The first player with it in an ability slot.
  ["tutorial-4.equipped"] = {
    "Good. Press {ability-1} to cast it, or the key under the slot you put it in. Go on. I want to see your face.",
  },
  -- Every cast: he laughs. All shouting, so it cuts in.
  ["tutorial-4.laugh"] = {
    { "HAHAHAHAHA!", shout = true },
  },
  -- The first cast: the mockery.
  ["tutorial-4.cast"] = {
    "Look at them. Twenty-five rioters with torches, and they're all yours. Congratulations.",
    "Use it as a weapon and it turns on you. Every time. They'll burn the town and punch YOU while they're at it.",
    "Only a friend of Sorros opens the borders. And Sorros hates everyone. Including you. ESPECIALLY you.",
    "Now clean up your mess. Shoot them, run them over, I don't care. All of them.",
  },
  -- The last of a horde's worth down: "Destroy the rioters" ticked.
  ["tutorial-4.cleared"] = {
    "That's the lot. The town still stands, mostly. No thanks to you.",
    "Remember this the next time you feel like opening borders.",
  },
  -- Everything ticked, by everyone: the way on is open.
  ["tutorial-4.open"] = {
    "Right. School's nearly out. The way on is on the top street, above the empty plot top left. Go.",
  },
  -- The first player to die on the level (their own rioters, most likely).
  ["tutorial-4.died"] = {
    "HA! Dead. Burned by your own rioters, or punched by them. Either way, you let them in.",
    "That's what Sorros does for his friends. The hospital's patched you up. Try not to waste their time again.",
  },
  -- Every death after that, one each in turn (at most one every
  -- Tutorial.mockEvery seconds).
  ["tutorial-4.died2"] = {
    "Back from the hospital already? They must be getting quick at you.",
  },
  ["tutorial-4.died3"] = {
    "Again. Your public school would be so proud.",
  },
  ["tutorial-4.died4"] = {
    "Sorros sends his regards. He hates you too, remember.",
  },
  -- Somebody put a building up on level 4 (build.lua): nothing is asked
  -- for there, so it comes down again.
  ["tutorial-4.wrong"] = {
    "Who said anything about building? Rioters first, bricks later. Down it comes.",
  },

  -- Level 5, build: one section at a time (build.lua), a beat as each
  -- item ticks, named after it.
  ["tutorial-5.start"] = {
    "Last lesson. Building. Guns don't grow on trees, and neither does ammo. You make them.",
    "Those four empty plots are free here. Stand on one and press {buy}. Don't get used to free.",
    "Then stand on the square in front of it and press {buy} again to build. First: a Quarry Mine.",
  },
  -- Somebody built what the list did not ask for: down it comes.
  ["tutorial-5.wrong"] = {
    "Did I ask for that? DID I? Public school. They let you build whatever you like there, didn't they.",
    "Down it comes. Build what's on the list.",
  },
  -- A quarry went up, digging iron from the start.
  ["tutorial-5.iron"] = {
    "A quarry. It digs up what every factory runs on, and it starts on iron. That's the one we want.",
    "Now a second one. Next plot, same thing.",
  },
  -- A quarry went up and iron was ticked already (one set to iron, then
  -- to sulfur): this one is for iron.
  ["tutorial-5.quarry1"] = {
    "A quarry. It digs up what every factory runs on. Make one of them dig iron.",
  },
  ["tutorial-5.quarry2"] = {
    "Another one. This one digs sulfur. Ammo needs both: iron for the case, sulfur for the bang.",
    "{buy} on its square, then 'Choose what to make'. Pick sulfur.",
  },
  -- Sulfur set before the second quarry went up.
  ["tutorial-5.sulfur"] = {
    "Sulfur. Smells like your school dinners. Now a second quarry, for the iron.",
  },
  -- Section 1 done: two quarries, iron and sulfur.
  ["tutorial-5.resources"] = {
    "Iron and sulfur. Raw materials. Worth nothing in the ground, worth a lot in a gun.",
    "Factories next. A Weapons Factory and an Ammo Factory, one plot each.",
  },
  -- A Weapons Factory went up, making pistols from the start.
  ["tutorial-5.pistols"] = {
    "A Weapons Factory. Iron goes in, guns come out. It starts on pistols. Leave it on pistols.",
    "Now the Ammo Factory.",
  },
  -- One went up and pistols were ticked already (it was set away from them).
  ["tutorial-5.weapons"] = {
    "A Weapons Factory. Iron goes in, guns come out. Set one to pistols.",
  },
  -- The Ammo Factory went up before the Weapons Factory.
  ["tutorial-5.ammo"] = {
    "An Ammo Factory. Iron and sulfur in, rounds out. Now the Weapons Factory.",
  },
  -- Section 2 done: both factories, the gun one on pistols.
  ["tutorial-5.factories"] = {
    "The Ammo Factory starts on 9mm. Not for your pistol: that never runs dry. The Uzi and the SMG eat 9mm.",
    "Factories do nothing without materials, and materials don't walk over by themselves.",
    "Neither do you, it seems. Off you go.",
    "Stand on the iron quarry's square, {buy}, and collect what it dug up. It digs slowly. Wait for it.",
  },
  -- Somebody collected iron.
  ["tutorial-5.collect"] = {
    "Iron, in your bag. Now carry it to the Weapons Factory. {buy} on its square and load it in.",
    "The Ammo Factory wants iron AND sulfur. Fetch some sulfur from the other quarry too.",
  },
  ["tutorial-5.loadWeapons"] = {
    "Four iron, one pistol. It takes a while. Good things do. You wouldn't know.",
    "It swallowed every bit of iron you carried, mind. Dig up more for the Ammo Factory.",
  },
  ["tutorial-5.loadAmmo"] = {
    "Iron and sulfur in the Ammo Factory. One of each, ten rounds. Even you can do that sum.",
  },
  -- Section 3 done: collected and loaded.
  ["tutorial-5.transport"] = {
    "Dig, carry, load. That's the whole economy. Everything else is people pretending to work.",
  },
  -- Section 4: he throws a shoe at the nearest building (build.lua). All
  -- shouting, so it cuts in.
  ["tutorial-5.throw"] = {
    { "OI! HEADS UP!", shout = true },
  },
  -- One of his shoes left a building damaged.
  ["tutorial-5.dent"] = {
    "Oops. Hole in your building. Buildings get shot, burned and rammed out there, and they don't mend themselves.",
    "{buy} on its square and repair the damage. Free here. Out there it costs you.",
  },
  -- Section 4 done.
  ["tutorial-5.repaired"] = {
    "Good as new. Better than my shoe, anyway.",
    "Next: staff. You can't be everywhere. Hire a driver at the shop. And a Handsy Man while you're there.",
  },
}

return Story
