-- Regen: a passive ability. Carry it in the passive slot and, once you have
-- gone a few seconds without being hurt while short of health, your body
-- heals itself fast for a few seconds; then it rests through a cooldown
-- before it can go again. It never mends the car you are driving (weapons'
-- serverHeal would, once the body is full, so this stops at the body) and
-- does nothing while you are dead or out of the world.
--
-- Passive abilities have no cast: the abilities feature calls
-- `serverTick(server, player, dt, abilities)` every host tick for whatever
-- sits in a player's passive slot. This one asks weapons to heal and tells
-- its carrier which phase it is in through `abilities:serverPassive`, so
-- the HUD ring shows it working and then waiting.

local Features = require("src.features")

local Regen = {
  key = "regen", -- on the wire and in a bag ("ability-regen")
  title = "regen",
  blurb = "Stay out of harm's way for a few seconds and your body heals itself fast.",
  passive = true, -- fits only the passive slot
  color = { 0.45, 0.95, 0.55 }, -- fresh green
}

-- Tuning ------------------------------------------------------------------
Regen.rate = 5 -- hit points a second while it works
Regen.seconds = 3 -- seconds it works for, once it starts
Regen.cooldown = 12 -- seconds of rest after that
Regen.delay = 3 -- seconds without being hurt before it starts
Regen.tierStats = { "cooldown", "rate", "seconds", "delay" } -- what a better tier improves, in order

-- player id -> { phase = "idle" | "active" | "cooldown", untilT, owed, seen }
local state = {}
local STALE = 0.5 -- seconds without a tick: it was put down, start afresh

--- Move `player`'s regen into `phase` for `seconds` and tell them.
local function enter(server, player, s, phase, seconds, abilities)
  s.phase, s.untilT, s.owed = phase, abilities.sv.time + seconds, 0
  abilities:serverPassive(server, player, Regen.key, phase, seconds)
end

function Regen.serverTick(server, player, dt, abilities, A)
  A = A or Regen -- the regen in the carrier's tier
  local now = abilities.sv.time
  local s = state[player.id]
  if not s or now - s.seen > STALE then
    s = { phase = "idle", untilT = 0, owed = 0, seen = now }
    state[player.id] = s
  end
  s.seen = now
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverHealth and weapons.serverHeal and Features.present(player)) then
    return
  end
  local hp, max = weapons:serverHealth(player)
  if not hp then
    return
  end
  if s.phase == "idle" then
    if hp < max and abilities:serverSinceHurt(player) >= A.delay then
      enter(server, player, s, "active", A.seconds, abilities)
    end
  elseif s.phase == "active" then
    if hp < max then
      s.owed = s.owed + A.rate * dt
      local whole = math.floor(s.owed)
      if whole > 0 then
        s.owed = s.owed - whole
        weapons:serverHeal(server, player, math.min(whole, max - hp))
        hp = math.min(max, hp + whole)
      end
    end
    if now >= s.untilT or hp >= max then
      enter(server, player, s, "cooldown", A.cooldown, abilities)
    end
  elseif now >= s.untilT then
    enter(server, player, s, "idle", 0, abilities)
  end
end

--- Forget a player who left.
function Regen.serverForget(player)
  state[player.id] = nil
end

return Regen
