-- The audit's knobs, in one place. Changing one is a change to the rules:
-- say why in the pull request.

return {
  base = "origin/staging", -- what a branch is rated against

  -- Core files (CLAUDE.md): shared by everyone, changed only for a new hook.
  core = {
    "main.lua",
    "src/net/",
    "src/states/",
    "src/audio/",
    "src/art/",
    "src/state.lua",
    "src/ui.lua",
    "src/car.lua",
    "src/body.lua",
    "src/features/init.lua",
  },

  -- Features that answer serverShotAt for things that are not enemies.
  notEnemies = {
    ["pedestrians"] = true, -- the crowd
    ["park-bums"] = true, -- hired help, not foes
    ["ammo-crates"] = true, -- crates break open
    ["abilities"] = true, -- the shield wall's dome stops enemy rounds
  },

  -- Features whose modules every other feature is meant to use: requiring
  -- them is following the standard, not reaching into someone's files.
  sharedFeatures = {
    ["bosses"] = true, -- every boss's (and tiring enemy's) stamina, bar, heal, dodge
    ["tiers"] = true, -- equipment's numbers go through Tiers.apply (CLAUDE.md)
  },

  -- Maps the map checks leave out: not quest maps, or not built yet.
  notQuestMaps = {
    ["city"] = true,
  },

  longFunction = 150, -- lines; longer new functions are flagged
  bigFile = 1500, -- lines; a file growing past this is flagged
  bigCoreChange = 40, -- lines changed in core files before it is a major finding
  wideChange = 8, -- features one branch may touch before it reads as scattered
  duplicateLines = 8, -- a run of this many added lines found elsewhere is copy-paste

  -- The game checks.
  questSeconds = 6, -- how long each quest is played for the stability check
  waitSeconds = 20, -- how long to wait for an enemy still out of reach (a boss's intro) to come in
  ammoCrates = 1, -- a quest map needs at least this many ammo crates
  musicSeconds = 15, -- a looping sound at least this long is a soundtrack
  wallTolerance = 0.5, -- of an enemy's radius: how deep in a wall its centre may be before it is stuck
}
