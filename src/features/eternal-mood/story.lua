-- The words of the Eternal Mood quest line (docs/eternal-mood.md), in one
-- place. So far what the horde says; the Voice's lines, the banners and the
-- bosses' come with them. Data only.

local Story = {}

-- What the horde says (horde.lua), by who and category; the host picks one
-- by index:
--   idle   now and then, at a post
--   alert  one who has just spotted a player
--   down   one going down
--   cover  one of the guards ducking into cover
--   grenade  one throwing a grenade
--   sweep  the first of the guards going out to look where the shooting came from
-- The possessed and the interns say the words; the imps mostly growl.
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
}

return Story
