-- Second wind: a passive ability, regen (regen.lua) for stamina. Carry it
-- in the passive slot and, once you have gone a moment on foot without
-- spending any stamina while short of it, your breath comes back fast for
-- a few seconds; then it rests through a cooldown before it can go again.
-- It refills the bar through on-foot's serverRestoreStamina, so a blown
-- bar can sprint again at once. Behind the wheel there is no bar, so it
-- waits until you get out; it does nothing while you are dead or out of
-- the world.
--
-- "Spending" is the bar going down between two ticks (a sprint or a
-- dodge): this watches the number on-foot keeps rather than asking it
-- when you last ran. The HUD ring shows it working and then waiting,
-- through `abilities:serverPassive`, like regen's.

local Features = require("src.features")

local SecondWind = {
  key = "secondwind", -- on the wire and in a bag ("ability-secondwind")
  title = "second wind",
  hud = "2nd wind", -- under its ring
  passive = true, -- fits only the passive slot
  color = { 1, 0.45, 0.75 }, -- energy-drink pink
}

-- Tuning ------------------------------------------------------------------
SecondWind.rate = 20 -- stamina a second while it works (on-foot's own is 9)
SecondWind.seconds = 3 -- seconds it works for, once it starts
SecondWind.cooldown = 12 -- seconds of rest after that
SecondWind.delay = 1 -- seconds without spending stamina before it starts
SecondWind.tierStats = { "cooldown", "rate", "seconds", "delay" } -- what a better tier improves, in order
SecondWind.tierLabels = { rate = "recovery rate" } -- what a card calls them where the usual name won't do

-- player id -> { phase = "idle" | "active" | "cooldown", untilT, seen, last, spentAt }
local state = {}
local STALE = 0.5 -- seconds without a tick: it was put down, start afresh

--- Move `player`'s second wind into `phase` for `seconds` and tell them.
local function enter(server, player, s, phase, seconds, abilities)
  s.phase, s.untilT = phase, abilities.sv.time + seconds
  abilities:serverPassive(server, player, SecondWind.key, phase, seconds)
end

function SecondWind.serverTick(server, player, dt, abilities, A)
  A = A or SecondWind -- the second wind in the carrier's tier
  local now = abilities.sv.time
  local s = state[player.id]
  if not s or now - s.seen > STALE then
    s = { phase = "idle", untilT = 0, seen = now, last = nil, spentAt = now }
    state[player.id] = s
  end
  s.seen = now
  local onFoot = Features.byName["on-foot"]
  if not (onFoot and onFoot.serverStamina and onFoot.serverRestoreStamina and Features.present(player)) then
    return
  end
  local stamina, max = onFoot:serverStamina(player)
  if not stamina then
    s.last = nil -- driving: no bar to watch, but the clock still runs
    if s.phase == "active" and now >= s.untilT then
      enter(server, player, s, "cooldown", A.cooldown, abilities)
    elseif s.phase == "cooldown" and now >= s.untilT then
      enter(server, player, s, "idle", 0, abilities)
    end
    return
  end
  if s.last and stamina < s.last then
    s.spentAt = now
  end
  if s.phase == "idle" then
    if stamina < max and now - s.spentAt >= A.delay then
      enter(server, player, s, "active", A.seconds, abilities)
    end
  elseif s.phase == "active" then
    if stamina < max then
      onFoot:serverRestoreStamina(server, player, A.rate * dt)
      stamina = onFoot:serverStamina(player)
    end
    if now >= s.untilT or stamina >= max then
      enter(server, player, s, "cooldown", A.cooldown, abilities)
    end
  elseif now >= s.untilT then
    enter(server, player, s, "idle", 0, abilities)
  end
  s.last = stamina
end

--- Forget a player who left.
function SecondWind.serverForget(player)
  state[player.id] = nil
end

return SecondWind
