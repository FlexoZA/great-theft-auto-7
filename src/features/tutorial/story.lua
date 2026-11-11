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
-- later stages add their own (a dodge, a wave down, a death).

local Story = {}

-- The name on the comms panel and its colour (his t-shirt's navy, lifted
-- so it reads on the dark panel).
Story.speaker = { name = "SHOEMAN", color = { 0.45, 0.58, 0.95 } }

Story.beats = {
  -- Level 1, cross the road: the opening speech, then moving and stamina.
  ["tutorial-1.start"] = {
    "You. Yes, YOU. Look at you. Soft hands. Soft head. Public school, was it? Thought so.",
    "The world out there has gone WOKE. Violent and woke. Cars, guns, robots, and nobody even says sorry.",
    "I am Shoeman. I am going to teach you to survive it. Whether you like it or not. You won't like it.",
    "Lesson one: walking. {move}. Even a public school kid can manage that. Probably.",
    "Hold {sprint} to run. Watch the bar: running drains it, it rests a moment before it fills again,"
      .. " and an empty bar has to come back before you can run again.",
    "See that road? Four streets of it. Nobody brakes for you, and one touch from a car is all it takes.",
    "Get to the other side. Alive, ideally. I'm not carrying you.",
  },
}

return Story
