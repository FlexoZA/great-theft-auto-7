-- Key bindings. Core actions (driving, mute) are registered here; features
-- register theirs in their load hook:
--   Controls.register("fire", "Fire", "mouse1")
-- and then ask Controls.isDown("fire"), Controls.is("fire", key) in
-- keypressed, or Controls.isMouse("fire", button) in mousepressed.
--
-- Every action has a primary and an optional secondary binding. A binding is
-- a LÖVE key constant ("w", "up", "f1") or "mouse1".."mouse3". Bindings
-- persist through src/settings.lua as controls.<action> = { primary, secondary }.

local Settings = require("src.settings")

local Controls = {
  actions = {}, -- ordered: { key, label, default = { primary, secondary } }
  byKey = {},
}

function Controls.register(key, label, primary, secondary)
  if Controls.byKey[key] then
    return Controls.byKey[key]
  end
  local action = { key = key, label = label, default = { primary, secondary } }
  Controls.actions[#Controls.actions + 1] = action
  Controls.byKey[key] = action
  return action
end

Controls.register("accelerate", "Accelerate", "w", "up")
Controls.register("brake", "Brake / reverse", "s", "down")
Controls.register("left", "Steer left", "a", "left")
Controls.register("right", "Steer right", "d", "right")
Controls.register("mute", "Mute music (menus)", "m")

--- { primary, secondary } for an action; either may be nil.
function Controls.bindings(key)
  local action = Controls.byKey[key]
  if not action then
    return {}
  end
  local saved = Settings.get("controls." .. key)
  if type(saved) == "table" then
    return { saved[1] or saved.primary, saved[2] or saved.secondary }
  end
  return { action.default[1], action.default[2] }
end

--- Bind `binding` to slot 1 or 2 of `action`, removing it from any other action first.
function Controls.set(key, slot, binding)
  for _, other in ipairs(Controls.actions) do
    local b = Controls.bindings(other.key)
    local changed = false
    for i = 1, 2 do
      if b[i] == binding and not (other.key == key and i == slot) then
        b[i] = nil
        changed = true
      end
    end
    if changed then
      Settings.set("controls." .. other.key, { b[1], b[2] })
    end
  end
  local b = Controls.bindings(key)
  b[slot] = binding
  Settings.set("controls." .. key, { b[1], b[2] })
end

function Controls.clear(key, slot)
  local b = Controls.bindings(key)
  b[slot] = nil
  Settings.set("controls." .. key, { b[1], b[2] })
end

function Controls.reset()
  for _, action in ipairs(Controls.actions) do
    Settings.set("controls." .. action.key, { action.default[1], action.default[2] })
  end
end

local function mouseButton(binding)
  local n = binding and binding:match("^mouse(%d)$")
  return n and tonumber(n)
end

local function bindingDown(binding)
  if not binding then
    return false
  end
  local m = mouseButton(binding)
  if m then
    return love.mouse.isDown(m)
  end
  local ok, down = pcall(love.keyboard.isDown, binding)
  return ok and down
end

--- While suspended (the pause menu is up) every action reads as neither
--- held nor pressed, so a feature that only ever asks this module sees the
--- player let go of everything without knowing why.
Controls.suspended = false

function Controls.suspend(on)
  Controls.suspended = on and true or false
end

function Controls.isDown(key)
  if Controls.suspended then
    return false
  end
  local b = Controls.bindings(key)
  return bindingDown(b[1]) or bindingDown(b[2])
end

--- Does a keypressed `keyConstant` belong to `action`?
function Controls.is(key, keyConstant)
  if Controls.suspended then
    return false
  end
  local b = Controls.bindings(key)
  return keyConstant ~= nil and (b[1] == keyConstant or b[2] == keyConstant)
end

--- Does a mousepressed `button` belong to `action`?
function Controls.isMouse(key, button)
  return Controls.is(key, "mouse" .. tostring(button))
end

local NAMES = {
  mouse1 = "Left mouse",
  mouse2 = "Right mouse",
  mouse3 = "Middle mouse",
  lshift = "Left Shift",
  rshift = "Right Shift",
  lctrl = "Left Ctrl",
  rctrl = "Right Ctrl",
  lalt = "Left Alt",
  ralt = "Right Alt",
  ["return"] = "Enter",
  space = "Space",
  escape = "Esc",
}

--- Human-readable name for a binding.
function Controls.name(binding)
  if not binding then
    return "-"
  end
  if NAMES[binding] then
    return NAMES[binding]
  end
  if #binding == 1 then
    return binding:upper()
  end
  return binding:sub(1, 1):upper() .. binding:sub(2)
end

return Controls
