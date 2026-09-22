-- Audio: music playback and the volume channels the settings screen edits.
--
-- Anything that plays sound registers a channel once at load:
--   Audio.registerChannel("engine", "Vehicle engine", 0.7, previewFn)
-- and scales what it plays by Audio.volume("engine"), which already includes
-- the master level. Volumes persist through src/settings.lua.

local Settings = require("src.settings")

local Audio = {
  music = nil,
  muted = false,
  channels = {}, -- ordered: { key, label, default, preview }
  byKey = {},
}

function Audio.registerChannel(key, label, default, preview)
  if Audio.byKey[key] then
    return Audio.byKey[key]
  end
  local ch = { key = key, label = label, default = default or 1, preview = preview }
  Audio.channels[#Audio.channels + 1] = ch
  Audio.byKey[key] = ch
  return ch
end

Audio.registerChannel("master", "Master", 1)
Audio.registerChannel("music", "Music", 0.5, function()
  Audio.playMenuTheme()
end)

--- The stored level of one channel, 0..1.
function Audio.get(key)
  local ch = Audio.byKey[key]
  return Settings.get("sound." .. key, ch and ch.default or 1)
end

--- Effective gain for a channel: its level times master.
function Audio.volume(key)
  if key == "master" then
    return Audio.get("master")
  end
  return Audio.get("master") * Audio.get(key)
end

function Audio.setVolume(key, value)
  value = math.max(0, math.min(1, value))
  Settings.set("sound." .. key, value)
  Audio.applyMusic()
end

function Audio.resetVolumes()
  for _, ch in ipairs(Audio.channels) do
    Settings.set("sound." .. ch.key, ch.default)
  end
  Audio.applyMusic()
end

function Audio.applyMusic()
  if Audio.music then
    Audio.music:setVolume(Audio.muted and 0 or Audio.volume("music"))
  end
end

function Audio.playMenuTheme()
  if not Audio.music then
    local started = love.timer.getTime()
    local sd = require("src.audio.menu_theme").render()
    Audio.music = love.audio.newSource(sd, "static")
    Audio.music:setLooping(true)
    Audio.music:setRelative(true) -- never positional: the game moves the listener around
    print(("menu theme: %.1fs of audio rendered in %.2fs"):format(sd:getDuration(), love.timer.getTime() - started))
  end
  Audio.applyMusic()
  if not Audio.music:isPlaying() then
    Audio.music:play()
  end
end

function Audio.pauseMusic()
  if Audio.music then
    Audio.music:pause()
  end
end

function Audio.toggleMute()
  Audio.muted = not Audio.muted
  Audio.applyMusic()
  return Audio.muted
end

return Audio
