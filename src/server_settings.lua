-- Server settings: the choices a host makes for the game they run, kept in
-- src/settings.lua alongside video and sound so they survive restarts and
-- can be changed from the Settings screen (its Server section) before or
-- during a game. Only the host's copy matters: features read these on the
-- host and never send them to clients. Bots read the difficulty.

local Settings = require("src.settings")

local ServerSettings = {}

ServerSettings.DIFFICULTIES = {
  { key = "easy", label = "Easy" },
  { key = "normal", label = "Normal" },
  { key = "hard", label = "Hard" },
}

ServerSettings.DEFAULTS = {
  botDifficulty = "normal",
}

function ServerSettings.get(key)
  return Settings.get("server." .. key, ServerSettings.DEFAULTS[key])
end

function ServerSettings.set(key, value)
  Settings.set("server." .. key, value)
end

--- Index into DIFFICULTIES of the saved bot difficulty (normal if unknown).
function ServerSettings.difficultyIndex()
  local key = ServerSettings.get("botDifficulty")
  for i, d in ipairs(ServerSettings.DIFFICULTIES) do
    if d.key == key then
      return i
    end
  end
  return 2
end

return ServerSettings
