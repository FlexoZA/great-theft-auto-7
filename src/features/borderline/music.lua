-- Each Borderline map's theme, by map name (so far the Frozen Wreck's,
-- theme_wreck.lua, and Liar's Landing's, theme_landing.lua), played from the moment Max's intro screen goes: its
-- intro once, then its loop. Rendered the first time its map comes up,
-- under Max's screen. A map without one plays nothing.

local Audio = require("src.audio")
local WreckTheme = require("src.features.borderline.theme_wreck")
local LandingTheme = require("src.features.borderline.theme_landing")

local Music = {}

local THEMES = { wreck = WreckTheme, landing = LandingTheme }
local music = {} -- map name -> { intro, loop } Sources
local playing = nil -- the map whose theme is on

local function volume()
  return Audio.muted and 0 or Audio.volume("music")
end

local function load(name)
  local theme = THEMES[name]
  if theme and not music[name] then
    local loop = love.audio.newSource(theme.render(), "static")
    loop:setLooping(true)
    loop:setRelative(true) -- never positional: the game moves the listener around
    local intro = theme.renderIntro and love.audio.newSource(theme.renderIntro(), "static")
    if intro then
      intro:setRelative(true)
    end
    music[name] = { intro = intro, loop = loop }
  end
end

function Music.stop()
  for _, m in pairs(music) do
    m.loop:stop()
    if m.intro then
      m.intro:stop()
    end
  end
  playing = nil
end

local function start(name)
  Music.stop()
  local m = music[name]
  playing, m.introDone = name, false
  local first = m.intro or m.loop
  first:setVolume(volume())
  first:seek(0)
  first:play()
end

--- `map` the map in play, `level` whether this screen is on one of the
--- line's levels on it, `screenUp` whether Max's intro screen is up.
function Music.update(map, level, screenUp)
  local want = level and map and THEMES[map.name] and map.name or nil
  if want then
    load(want)
    if playing ~= want and not screenUp then
      start(want)
    end
  elseif playing then
    Music.stop()
  end
  local m = playing and music[playing]
  if m then
    if m.intro and not m.introDone and not m.intro:isPlaying() then
      m.introDone = true -- the rails are behind us: full tilt
      m.loop:seek(0)
      m.loop:play()
    end
    m.loop:setVolume(volume()) -- the slider may move
    if m.intro then
      m.intro:setVolume(volume())
    end
  end
end

return Music
