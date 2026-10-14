-- The words of the Eternal Mood quest line (docs/eternal-mood.md), in one
-- place. So far what the horde says; the Voice's lines, the banners and the
-- bosses' come with them. Data only.

local Story = {}

-- What the horde says (horde.lua), by who and category; the host picks one
-- by index:
--   idle   now and then, at a post
--   alert  one who has just spotted a player
--   down   one going down
-- The possessed say the words; the imps mostly growl.
Story.horde = {
  possessed = {
    idle = {
      "Is this overtime?",
      "My badge doesn't work.",
      "Has anyone seen my legs?",
      "Please hold. Your call is important.",
      "Per my last email...",
      "I'll circle back on that.",
    },
    alert = {
      "Visitor in the lab!",
      "You're not on the rota.",
      "Sign in at reception!",
      "Do you have an appointment?",
    },
    down = { "Tell HR...", "Finally, a break.", "I'm clocking off." },
  },
  imp = {
    idle = { "Hungry...", "Grrrr...", "Smells like marine." },
    alert = { "MEAT!", "Who ordered the space marine?", "Heck yeah!", "SKREEEE!" },
    down = { "Skrk!" },
  },
}

return Story
