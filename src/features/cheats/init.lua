-- Cheats: type a code while playing, the old way. The client only notices
-- the letters and tells the server which code was typed; the server looks it
-- up and does the work, so a code does nothing it isn't listed to do.
--
-- Add a code by adding an entry to CODES. Set Cheats.enabled to false to
-- turn them all off.
--
--   gimmekoin     +10000 Fcks
--   infiniteammo  magazines never run out, no reloading (type it again to stop)
--   reachforthestars  leap lands wherever the cursor is, not just within its
--                     range, and is ready again the moment you land (type it
--                     again to stop)
--   itisminenow  the shop is the dev shop: everything in it free (type it
--                again to stop)
--   ulla         a legendary heat ray (the tripod's drop), put straight into
--                an empty ability slot if there is one, else into the bag
--
-- F2 lists every code and what it does (HELP, in the same order as above);
-- while it is up, the number keys run the code on that row (1 is the first),
-- and F2 or Esc takes the list down again.
--
-- The letters still reach every other feature as ordinary key presses, so
-- typing a code that contains E steps out of the car if it is slow enough.
--
-- Messages
--   client -> server  CHEAT    <code>
--   server -> player  CHEAT_OK <code>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")

local Cheats = {
  name = "cheats",
  priority = 994, -- the list draws over the shop (993), under the inventory (995)
}

Cheats.enabled = true

local SHOW_TIME = 2 -- seconds the "cheat on" banner stays up

--- code -> function(server, player) run on the host. It may return what the
--- banner says instead of the code ("infinite ammo off").
local CODES = {
  gimmekoin = function(server, player)
    local money = Features.byName.money
    if money then
      money:give(server, player.id, 10000)
    end
  end,
  infiniteammo = function(server, player)
    local weapons = Features.byName.weapons
    if weapons and weapons.serverSetInfiniteAmmo then
      local on = weapons:serverSetInfiniteAmmo(server, player, not weapons:serverHasInfiniteAmmo(player))
      return on and "infinite ammo on" or "infinite ammo off"
    end
  end,
  itisminenow = function(server, player)
    local shop = Features.byName.shop
    if shop and shop.serverSetDev then
      local on = shop:serverSetDev(server, player, not shop:serverDev(player))
      return on and "dev shop on" or "dev shop off"
    end
  end,
  ulla = function(server, player)
    local buildings, abilities = Features.byName.buildings, Features.byName.abilities
    local item = "heatray@legendary"
    if not (buildings and buildings.serverGive) or buildings:serverGive(server, player, "ability-" .. item, 1) < 1 then
      return "no room in your bag"
    end
    local slots = abilities and abilities.sv and abilities.sv.slots[player.id]
    if slots then
      for slot = 1, abilities.slotCount do
        if slot ~= abilities.passiveSlot and not slots[slot] and abilities:serverEquip(server, player, item, slot) then
          return "heat ray on your ability keys"
        end
      end
    end
    return "heat ray in your bag"
  end,
  reachforthestars = function(server, player)
    local abilities = Features.byName.abilities
    if abilities and abilities.serverSetReach then
      local on = abilities:serverSetReach(server, player, "leap", not abilities:serverReachLifted(player, "leap"))
      return on and "leap to the stars on" or "leap to the stars off"
    end
  end,
}

--- What the F2 list says about each code, in order. A new code gets a line here too.
local HELP = {
  { code = "gimmekoin", text = "+10000 Fcks" },
  { code = "infiniteammo", text = "Magazines never run out, no reloading (again to stop)" },
  { code = "reachforthestars", text = "Leap lands wherever the cursor is and is ready again at once (again to stop)" },
  { code = "itisminenow", text = "The shop is the dev shop: everything free (again to stop)" },
  { code = "ulla", text = "A legendary heat ray, on an empty ability key if there is one" },
}

-- Client --------------------------------------------------------------------

local typed = "" -- the last few letters pressed
local shown, showTimer = nil, 0
Cheats.listOpen = false -- the F2 list is up

function Cheats:load()
  Controls.register("cheats", "List the cheat codes", "f2")
end

function Cheats:exitGame()
  typed, shown, showTimer = "", nil, 0
  self.listOpen = false
end

--- The `closeMenu` convention: Esc takes the list down.
function Cheats:closeMenu()
  if not self.listOpen then
    return false
  end
  self.listOpen = false
  return true
end

--- The `menuOpen` convention: the number keys run a code, not pick a gun.
function Cheats:menuOpen()
  return self.listOpen
end

function Cheats:update(dt)
  showTimer = math.max(0, showTimer - dt)
end

function Cheats:keypressed(key, client)
  if Cheats.enabled and Controls.is("cheats", key) then
    self.listOpen = not self.listOpen
    return
  end
  local n = self.listOpen and tonumber(key:match("^kp(%d)$") or key:match("^(%d)$"))
  local entry = n and HELP[n]
  if entry then
    client:send(Protocol.encode("CHEAT", entry.code))
    return
  end
  if #key ~= 1 or not key:match("%a") then
    return
  end
  typed = (typed .. key):sub(-24)
  for code in pairs(CODES) do
    if typed:sub(-#code) == code then
      typed = ""
      client:send(Protocol.encode("CHEAT", code))
      return
    end
  end
end

--- The F2 list: a panel in the middle of the screen, a row per code.
local function drawList()
  local fonts = UI.fonts
  local rowH, pad = fonts.body:getHeight() + 10, 20
  local codeW = 0
  for _, h in ipairs(HELP) do
    codeW = math.max(codeW, fonts.body:getWidth(#HELP .. "  " .. h.code))
  end
  local sw, sh = love.graphics.getDimensions()
  local w = math.min(sw - 32, 820)
  local textW = w - codeW - 3 * pad
  local rows = {}
  local h = pad + fonts.heading:getHeight() + 14
  for i, entry in ipairs(HELP) do
    local _, lines = fonts.body:getWrap(entry.text, textW)
    rows[i] = math.max(1, #lines) * fonts.body:getHeight() + 10
    h = h + math.max(rowH, rows[i])
  end
  h = h + fonts.small:getHeight() + pad + 8
  local x, y = math.floor((sw - w) / 2), math.floor((sh - h) / 2)
  UI.panel(x, y, w, h)
  love.graphics.setFont(fonts.heading)
  love.graphics.setColor(0.4, 1, 0.5)
  love.graphics.printf("CHEAT CODES", x, y + pad, w, "center")
  local ry = y + pad + fonts.heading:getHeight() + 14
  love.graphics.setFont(fonts.body)
  for i, entry in ipairs(HELP) do
    love.graphics.setColor(1, 0.85, 0.3)
    love.graphics.print(i .. "  " .. entry.code, x + pad, ry)
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.printf(entry.text, x + 2 * pad + codeW, ry, textW)
    ry = ry + math.max(rowH, rows[i])
  end
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  local key = Controls.name(Controls.bindings("cheats")[1])
  local hint = "Type a code while playing, or press its number here.  " .. key .. " or Esc: close"
  love.graphics.printf(hint, x, y + h - pad - 8, w, "center")
  love.graphics.setColor(1, 1, 1)
end

function Cheats:drawHUD()
  if self.listOpen and Cheats.enabled then
    drawList()
  end
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
