-- The Citadel's doors in City 17 don't lead into the Citadel. Whoever
-- takes the EXIT star there (quests' "a-man" `next`, the star saying
-- CITADEL) is stopped by A-Man: he blinks in right in front of them, takes
-- a look at them for a moment, and blinks out, and everyone finds
-- themselves somewhere else: the Outer City (quests' "a-man-2"). The trip
-- is held up for him (quests' `serverHoldTrip`) and made after with
-- `quests:serverBegin`.
--
-- He comes and goes through cameo.lua's C17_AMAN_IN and C17_AMAN_OUT, so
-- every screen draws him and his tear the way it does in the plaza.

local Protocol = require("src.net.protocol")
local Features = require("src.features")

local Detour = {}

-- Tuning ------------------------------------------------------------------
Detour.questId = "a-man-2" -- the trip he steps into
Detour.distance = 110 -- px in front of the taker that he lands
Detour.standFor = 2.2 -- seconds he stands there before he sends everyone off

local sv = nil -- { t, quest, by, x, y } while he is there, on the host

local function fmt(v)
  return ("%.1f"):format(v)
end

local function clear(x, y)
  for _, k in ipairs({ { 0, 0 }, { 12, 0 }, { -12, 0 }, { 0, 12 }, { 0, -12 } }) do
    if Features.any("blocksPoint", x + k[1], y + k[2]) then
      return false
    end
  end
  return true
end

--- Somebody took the star: he turns up in front of them instead. Returns
--- true to hold the trip (and while he is there, so a second taker of the
--- same star waits too). Any other trip (somebody heading home) goes ahead,
--- and its map change calls him off.
function Detour.serverHoldTrip(server, quest, player)
  if quest.id ~= Detour.questId then
    return false
  end
  if sv then
    return true
  end
  local px, py, _, facing = Features.bodyPose(server, player)
  local x, y = px, py
  for k = 0, 7 do -- straight ahead of them if he can, else round them
    local a = facing + (k % 2 == 0 and 1 or -1) * math.ceil(k / 2) * math.pi / 4
    local tx, ty = px + math.cos(a) * Detour.distance, py + math.sin(a) * Detour.distance
    if clear(tx, ty) then
      x, y = tx, ty
      break
    end
  end
  sv = { t = Detour.standFor, quest = quest, by = player.id, x = x, y = y }
  server:broadcast(Protocol.encode("C17_AMAN_IN", fmt(x), fmt(y), ("%.2f"):format(math.atan2(py - y, px - x))))
  return true
end

--- When he has had his look, he is gone and everyone with him.
function Detour.serverStep(server, dt)
  if not sv then
    return
  end
  sv.t = sv.t - dt
  if sv.t > 0 then
    return
  end
  local d = sv
  sv = nil
  server:broadcast(Protocol.encode("C17_AMAN_OUT", fmt(d.x), fmt(d.y)))
  local quests = Features.byName.quests
  local taker = server.players[d.by]
  if not (taker and Features.present(taker)) then
    taker = nil -- they left (or went down): anyone else still here takes the trip
    for _, p in pairs(server.players) do
      if not p.bot and Features.present(p) then
        taker = p
        break
      end
    end
  end
  if quests and taker then
    quests:serverBegin(server, d.quest, taker)
  end
end

--- A map change (the trip itself among them) or the quest ending calls him off.
function Detour.serverStop()
  sv = nil
end

return Detour
