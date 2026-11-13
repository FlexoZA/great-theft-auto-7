-- The tutorial's soundtracks on this screen (theme.lua): each tutorial
-- map's own track from the moment its level starts, looping. Levels 4 and 5
-- share the town, so its track plays on through the change. Rendered the
-- first time a map asks for it and kept.

local Audio = require("src.audio")
local Theme = require("src.features.tutorial.theme")

local Music = {}

local sources = {} -- map name -> Source
local playing = nil -- the map whose track is on

local function volume()
  return Audio.muted and 0 or Audio.volume("music")
end

local function source(map)
  if not sources[map] then
    local src = love.audio.newSource(Theme.render(map), "static") -- a fraction of a second
    src:setLooping(true)
    src:setRelative(true) -- never positional: the game moves the listener around
    sources[map] = src
  end
  return sources[map]
end

--- `map`'s track, from the top unless it is the one already on.
function Music.play(map)
  if not Theme.SONGS[map] then
    return Music.stop()
  end
  if playing and playing ~= map then
    Music.stop()
  end
  local src = source(map)
  src:setVolume(volume())
  src:play() -- carries on when it is playing already
  playing = map
end

function Music.stop()
  if playing then
    sources[playing]:stop()
    playing = nil
  end
end

--- Follows the music slider while a track is on.
function Music.update()
  if playing then
    sources[playing]:setVolume(volume())
  end
end

return Music
