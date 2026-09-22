-- Music playback. The menu theme is synthesised on first use (see
-- src/audio/menu_theme.lua), then looped. Menus play it; the game pauses it.

local Audio = {
  music = nil,
  volume = 0.5,
  muted = false,
}

function Audio.playMenuTheme()
  if not Audio.music then
    local started = love.timer.getTime()
    local sd = require("src.audio.menu_theme").render()
    Audio.music = love.audio.newSource(sd, "static")
    Audio.music:setLooping(true)
    print(("menu theme: %.1fs of audio rendered in %.2fs"):format(sd:getDuration(), love.timer.getTime() - started))
  end
  Audio.music:setVolume(Audio.muted and 0 or Audio.volume)
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
  if Audio.music then
    Audio.music:setVolume(Audio.muted and 0 or Audio.volume)
  end
  return Audio.muted
end

return Audio
