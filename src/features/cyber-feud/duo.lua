-- Saye and Kilowatt together on the Roof (docs/cyber-feud.md, "Saye and
-- Kilowatt together"): forty years of a business partnership, on the host.
-- kilowatt.lua and saye.lua are each a boss on its own; this is what makes
-- them partners, and the only place either looks at the other.
--
--   They cover each other. A player who shoots Saye gets Kilowatt's grudge
--   (`grudge`): he goes for them, charging as soon as he can. A player
--   standing next to Kilowatt (within NEAR) draws Saye's sightline
--   (`nearKilowatt`), and she hurries it.
--   Shield. While Kilowatt vents, Saye parks her drones round him
--   (`shielding`); while any of them are there his vent doesn't double
--   what hits him. Shoot the drones and the window opens properly.
--   When one falls the other rages (`serverStep` notices): Saye alone,
--   "Hostile takeover.": twice the drones, her sightline in bursts of
--   three. Kilowatt alone, "MELTDOWN!": phase 2 for good, and his slams
--   leave shock patches on the ground.
--   They bicker: every so often one says a line and the other answers.

local Protocol = require("src.net.protocol")

local Duo = {}

-- Tuning ------------------------------------------------------------------
Duo.NEAR = 200 -- px from Kilowatt that draws Saye's sightline
Duo.GRUDGE = 6 -- seconds Kilowatt goes for whoever shot Saye
Duo.BICKER_EVERY = { 18, 30 } -- seconds between one exchange and the next
Duo.ANSWER = 2.4 -- seconds before the other answers

-- Who says what to whom: { first speaker, line, the other, answer }, by
-- the speakers' own line numbers (kilowatt.lua's and saye.lua's `LINE.bicker`).
local EXCHANGES = {
  { "k", 1, "s", 1 }, -- "You said this kid was a nobody!" / "They are. It's a very expensive nobody."
  { "s", 2, "k", 2 }, -- "Your people destroyed my lobby." / "It was ugly."
  { "k", 3, "s", 3 }, -- "Sixty-forty, Saye..." / "Noted. We'll discuss it at the review."
  { "s", 4, "k", 4 }, -- "Try to hit them, not the building." / "I AM hitting them!..."
}

local function kilowattSv()
  return require("src.features.cyber-feud.kilowatt").server()
end

local function sayeSv()
  return require("src.features.cyber-feud.saye").server()
end

--- Kilowatt, if he is up and fighting.
function Duo.kilowatt()
  local sv = kilowattSv()
  return sv and sv.awake and not sv.down and sv.k or nil
end

--- Saye, if she is up and fighting.
function Duo.saye()
  local sv = sayeSv()
  return sv and sv.awake and not sv.down and sv.s or nil
end

--- Player `id` shot Saye: Kilowatt goes for them. True the first time a
--- grudge starts (so he can say so).
function Duo.grudge(id)
  local k = Duo.kilowatt()
  if not k or not id or id == 0 then
    return false
  end
  local fresh = not (k.grudge and k.grudge.id == id and k.time < k.grudge.untilT)
  k.grudge = { id = id, untilT = k.time + Duo.GRUDGE }
  if fresh then
    k.chargeIn = math.min(k.chargeIn, 0.3)
  end
  return fresh
end

--- The player standing nearest Kilowatt, within NEAR of him, among those
--- `ok(p, x, y)` allows (Saye can see them); and where they are.
function Duo.nearKilowatt(server, ok)
  local k = Duo.kilowatt()
  if not k then
    return nil
  end
  local Features = require("src.features")
  local best, bx, by, bestD2 = nil, nil, nil, Duo.NEAR * Duo.NEAR
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = (x - k.x) ^ 2 + (y - k.y) ^ 2
      if d2 <= bestD2 and ok(p, x, y) then
        best, bx, by, bestD2 = p, x, y, d2
      end
    end
  end
  return best, bx, by
end

--- Is Kilowatt venting with Saye's drones round him? Returns him, then, for
--- the drones to circle.
function Duo.shielding()
  local k, s = Duo.kilowatt(), Duo.saye()
  if k and s and k.action == "vent" and #s.drones > 0 then
    return k
  end
  return nil
end

-- Server --------------------------------------------------------------------

local st = nil -- { bickerIn, next, answer = { who, line, t } }

function Duo.serverStop()
  st = nil
end

local function sayLine(server, who, n)
  if who == "k" then
    local K = require("src.features.cyber-feud.kilowatt")
    server:broadcast(Protocol.encode("KWB_SAY", K.LINE.bicker[n]))
  else
    local S = require("src.features.cyber-feud.saye")
    server:broadcast(Protocol.encode("SYE_SAY", S.LINE.bicker[n]))
  end
end

function Duo.serverStep(server, dt)
  local ksv, ssv = kilowattSv(), sayeSv()
  if not (ksv and ssv) then
    st = nil
    return
  end
  st = st or { bickerIn = Duo.BICKER_EVERY[1], next = 1 }
  -- One down, the other rages.
  if ksv.down and not ssv.down and not ssv.s.rage then
    local S = require("src.features.cyber-feud.saye")
    ssv.s.rage = true
    ssv.s:callDrones()
    server:broadcast(Protocol.encode("SYE_SAY", S.LINE.rage))
  end
  if ssv.down and not ksv.down and not ksv.k.meltdown then
    local K = require("src.features.cyber-feud.kilowatt")
    ksv.k.meltdown, ksv.k.phase2 = true, true
    server:broadcast(Protocol.encode("KWB_SAY", K.LINE.rage))
  end
  -- Bickering, while both are at it.
  if not (Duo.kilowatt() and Duo.saye()) then
    return
  end
  if st.answer then
    st.answer.t = st.answer.t - dt
    if st.answer.t <= 0 then
      sayLine(server, st.answer.who, st.answer.line)
      st.answer = nil
    end
    return
  end
  st.bickerIn = st.bickerIn - dt
  if st.bickerIn <= 0 then
    local e = EXCHANGES[st.next]
    st.next = st.next % #EXCHANGES + 1
    st.bickerIn = Duo.BICKER_EVERY[1] + love.math.random() * (Duo.BICKER_EVERY[2] - Duo.BICKER_EVERY[1])
    sayLine(server, e[1], e[2])
    st.answer = { who = e[3], line = e[4], t = Duo.ANSWER }
  end
end

return Duo
