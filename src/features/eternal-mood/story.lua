-- The words of the Eternal Mood quest line (docs/eternal-mood.md), in one
-- place: the Voice's intro screen lines and what the horde says (the bosses
-- keep their own). Data only.

local Story = {}

Story.LEVELS = 5

-- What the Voice says on its intro screen, one line per level (quests'
-- `introLine` picks it on arrival). It starts out sure of itself and gets
-- sleepier the further down the dream goes.
Story.lines = {
  "They opened a door to Heck. They're about to find out I'm worse.",
  "Earth. Home. On fire. One road to the starport, and Heck's standing on all of it. Good.",
  "A factory that melts demons. Somebody's going to melt. Not me.",
  "Heck. Hot, loud, full of demons. ...Is it hot in here, or is it the blanket?",
  "One big demon left. Then I'm going back to... where was I going?",
}

-- What the horde says (horde.lua), by who and category; the host picks one
-- by index:
--   idle   now and then, at a post
--   alert  one who has just spotted a player
--   down   one going down
--   cover  one of the guards ducking into cover
--   grenade  one throwing a grenade
--   sweep  the first of the guards going out to look where the shooting came from
-- The possessed and the interns say the words; the imps mostly growl, the
-- Cacodaemons roar.
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
    cover = { "Taking my break!", "Ducking out of this meeting!", "Going on mute!", "Hot-desking it!" },
    grenade = { "Catch! It's a team-builder!", "Here's your severance!", "Fire in the hole! And the office!" },
    sweep = { "Let's circle back to that.", "Somebody action that!", "Going to touch base. Over there." },
  },
  intern = {
    idle = { "Coffee?", "Is this paid?", "Brains... storming...", "Can I shadow you?" },
    alert = {
      "BRAAAINS... storming session!",
      "Can I shadow you?!",
      "Is that a job offer?!",
      "Coffee! COFFEE!",
      "Networking opportunity!",
    },
    down = { "Unpaid...", "Exposure...", "Great... experience..." },
  },
  imp = {
    idle = { "Hungry...", "Grrrr...", "Smells like marine." },
    alert = { "MEAT!", "Who ordered the space marine?", "Heck yeah!", "SKREEEE!" },
    down = { "Skrk!" },
  },
  caco = {
    alert = { "GRAAAWRBLE!", "MEAT! FLOATING MEAT!", "Open wide...", "BLRRRAAAGH!" },
    down = { "Pfffffft...", "Blorp." },
  },
}

return Story
