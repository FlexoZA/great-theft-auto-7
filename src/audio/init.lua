-- Audio: music playback and the volume channels the settings screen edits.
--
-- Anything that plays sound registers a channel once at load:
--   Audio.registerChannel("engine", "Vehicle engine", 0.7, previewFn)
-- and scales what it plays by Audio.volume("engine"), which already includes
-- the master level. Volumes persist through src/settings.lua.
--
-- The menu has more than one theme (see Audio.MENU_TRACKS); whoever owns the
-- choice calls Audio.setMenuTrack. Each one is synthesised the first time it
-- is asked for and kept, so switching back and forth is free.

local Settings = require("src.settings")

local Audio = {
  music = nil, -- the source currently selected, playing or not
  muted = false,
  channels = {}, -- ordered: { key, label, default, preview }
  byKey = {},
  tracks = {}, -- menu track key -> Source, rendered on demand
  menuTrack = "metal",
}

Audio.MENU_TRACKS = {
  metal = "src.audio.menu_theme",
  rap = "src.audio.rap_theme",
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

--- The source for one menu track, synthesising it on first use.
local function menuSource(key)
  local src = Audio.tracks[key]
  if not src then
    local started = love.timer.getTime()
    local sd = require(Audio.MENU_TRACKS[key]).render()
    src = love.audio.newSource(sd, "static")
    src:setLooping(true)
    src:setRelative(true) -- never positional: the game moves the listener around
    Audio.tracks[key] = src
    print(("menu theme %s: %.1fs of audio rendered in %.2fs"):format(key, sd:getDuration(),
      love.timer.getTime() - started))
  end
  return src
end

--- Choose the menu theme. Swaps straight away when music is already playing.
function Audio.setMenuTrack(key)
  if key == Audio.menuTrack or not Audio.MENU_TRACKS[key] then
    return
  end
  Audio.menuTrack = key
  local wasPlaying = Audio.music and Audio.music:isPlaying()
  if Audio.music then
    Audio.music:stop()
    Audio.music = nil
  end
  if wasPlaying then
    Audio.playMenuTheme()
  end
end

function Audio.playMenuTheme()
  Audio.music = Audio.music or menuSource(Audio.menuTrack)
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
