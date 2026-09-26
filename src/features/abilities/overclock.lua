-- Overclock: a passive ability that brings every other ability back
-- sooner. Carry it in the passive slot and the cooldowns of what sits in
-- your keyed slots are cut to `stats.cooldown` of what they would be.
--
-- It has no tick and no phase: the abilities feature reads the `stats` of
-- whatever is in the passive slot and answers the `serverStat` / `stat`
-- conventions with them (docs/features.md), the same "cooldown" stat
-- clothes (cargo pants) feed, so the two stack. The HUD ring is lit while
-- it is carried; the inventory's stats strip shows the cut.

local Overclock = {
  key = "overclock", -- on the wire and in a bag ("ability-overclock")
  title = "overclock",
  hud = "clock", -- short enough to fit under its ring
  passive = true, -- fits only the passive slot
  color = { 0.75, 0.45, 1 }, -- electric violet
}

-- Tuning ------------------------------------------------------------------
-- Multipliers on the carrier's stats, like a piece of clothing's: 0.8 is a
-- fifth off every cooldown. A better tier divides it by its boost.
Overclock.stats = { cooldown = 0.8 }
Overclock.tierStats = { "stats.cooldown" } -- what a better tier improves
Overclock.tierLabels = { ["stats.cooldown"] = "cooldowns" } -- what a card calls it

return Overclock
