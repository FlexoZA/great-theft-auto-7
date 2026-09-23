-- Cheats: type a code while playing, the old way. The client only notices
-- the letters and tells the server which code was typed; the server looks it
-- up and does the work, so a code does nothing it isn't listed to do.
--
-- Add a code by adding an entry to CODES. Set Cheats.enabled to false to
-- turn them all off.
--
--   gimmekoin     +1000 Fcks
--   infiniteammo  magazines never run out, no reloading (type it again to stop)
--
-- The letters still reach every other feature as ordinary key presses, so
-- typing a code that contains E steps out of the car if it is slow enough.
--
-- Messages
--   client -> server  CHEAT    <code>
--   server -> player  CHEAT_OK <code>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")

local Cheats = {
  name = "cheats",
}

Cheats.enabled = true

local SHOW_TIME = 2 -- seconds the "cheat on" banner stays up

--- code -> function(server, player) run on the host. It may return what the
--- banner says instead of the code ("infinite ammo off").
local CODES = {
  gimmekoin = function(server, player)
    local money = Features.byName.money
    if money then
      money:give(server, player.id, 1000)
    end
  end,
  infiniteammo = function(server, player)
    local weapons = Features.byName.weapons
    if weapons and weapons.serverSetInfiniteAmmo then
      local on = weapons:serverSetInfiniteAmmo(server, player, not weapons:serverHasInfiniteAmmo(player))
      return on and "infinite ammo on" or "infinite ammo off"
    end
  end,
}

-- Client --------------------------------------------------------------------

local typed = "" -- the last few letters pressed
local shown, showTimer = nil, 0

function Cheats:exitGame()
  typed, shown, showTimer = "", nil, 0
end

function Cheats:update(dt)
  showTimer = math.max(0, showTimer - dt)
end

function Cheats:keypressed(key, client)
  if #key ~= 1 or not key:match("%a") then
    return
  end
  typed = (typed .. key):sub(-16)
  for code in pairs(CODES) do
    if typed:sub(-#code) == code then
      typed = ""
      client:send(Protocol.encode("CHEAT", code))
      return
    end
  end
end

function Cheats:drawHUD()
  if showTimer > 0 then
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0.4, 1, 0.5, math.min(1, showTimer))
    love.graphics.printf("CHEAT: " .. shown, 0, 110, love.graphics.getWidth(), "center")
    love.graphics.setColor(1, 1, 1)
  end
end

Cheats.clientMessages = {
  CHEAT_OK = function(_client, args)
    shown, showTimer = args[1] or "?", SHOW_TIME
  end,
}

-- Server ----------------------------------------------------------------

Cheats.serverMessages = {
  CHEAT = function(server, player, args)
    local run = Cheats.enabled and CODES[args[1] or ""]
    if run and player.body then
      local said = run(server, player)
      server:send(player, Protocol.encode("CHEAT_OK", said or args[1]))
    end
  end,
}

return Cheats
