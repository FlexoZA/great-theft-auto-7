-- The Colosseum's waves, on the host: every enemy in the game in order, a
-- wave at a time. Walk in and a countdown starts; at nought the wave pours
-- in at the far end of the sand and comes for you; once every one of it is
-- down the wave is cleared, a pile of koins lands in the middle, and after
-- a pause the next comes. After the last the arena is cleared and the star
-- home by the gate is the way out; coming back in starts from the first.
--
-- A wave is a row of `Waves.LIST`: its title, the feature whose enemies it
-- is (`feature`), what of theirs (`kind`) and how many for one player
-- (`count`, grown for a bigger group the way the bosses' gangs are:
-- Bosses.count). That feature answers two calls, through Features.byName:
--   feature:serverArenaSend(server, kind, count, x, y)  `count` of `kind` turn up round (x, y) and hunt
--                                                        everyone, however far; returns how many came
--   feature:serverArenaLeft(server, kind)                how many of `kind` are still up
-- and everything else about them stays its own: their brains, how they
-- look, getting shot (`serverShotAt`, `serverEnemies`), what they drop.
--
-- The host decides it all and tells everyone (ARN_WAVE); clients draw.

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")

local Waves = {}

Waves.LIST = {
  { title = "Karen's Simps", feature = "karen", kind = "simp", count = 8 },
}

Waves.COUNTDOWN = 10 -- seconds from walking in to the first wave
Waves.PAUSE = 8 -- seconds between a wave cleared and the next
Waves.BONUS = 10 -- koins dropped in the middle of the sand when a wave is cleared
-- Where a wave comes in, as fractions of the sand's radii from its middle:
-- the far end, two groups apart, away from the gate everyone walks in by.
Waves.SPOTS = { { -0.45, -0.55 }, { 0.45, -0.55 } }

local sv = nil -- { index, phase = "countdown" | "fight" | "cleared" | "done", timer, left, sent }

--- What everyone is told: ARN_WAVE <index> <total> <phase> <left> <seconds>.
local function message()
  return Protocol.encode("ARN_WAVE", sv.index, #Waves.LIST, sv.phase, sv.left, math.max(0, math.ceil(sv.timer)))
end

local function tell(server)
  sv.said = message()
  server:broadcast(sv.said)
end

--- The fight starts: everyone has just walked in.
function Waves.start(server)
  sv = { index = 1, phase = "countdown", timer = Waves.COUNTDOWN, left = 0 }
  tell(server)
end

function Waves.stop()
  sv = nil
end

function Waves.running()
  return sv ~= nil
end

--- Send wave `sv.index` in over the sand `oval` ({ x, y, rx, ry }).
local function send(server, oval)
  local wave = Waves.LIST[sv.index]
  local f = Features.byName[wave.feature]
  local count = Bosses.count(wave.count, server)
  local came = 0
  if f and f.serverArenaSend then
    for k, spot in ipairs(Waves.SPOTS) do
      local share = math.floor(count / #Waves.SPOTS) + (k <= count % #Waves.SPOTS and 1 or 0)
      came = came + f:serverArenaSend(server, wave.kind, share, oval.x + spot[1] * oval.rx, oval.y + spot[2] * oval.ry)
    end
  end
  sv.phase, sv.left = "fight", came
end

--- How many of the wave in play are still up.
local function left(server)
  local wave = Waves.LIST[sv.index]
  local f = Features.byName[wave.feature]
  return f and f.serverArenaLeft and f:serverArenaLeft(server, wave.kind) or 0
end

--- One tick on the host, in the arena `oval`.
function Waves.step(server, dt, oval)
  if not sv then
    return
  end
  sv.timer = sv.timer - dt
  if sv.phase == "countdown" and sv.timer <= 0 then
    send(server, oval)
  elseif sv.phase == "fight" then
    sv.left = left(server)
    if sv.left == 0 then
      local money = Features.byName.money
      if money and money.drop then
        money:drop(server, oval.x, oval.y, Waves.BONUS)
      end
      local last = sv.index >= #Waves.LIST
      sv.phase, sv.timer = last and "done" or "cleared", last and 0 or Waves.PAUSE
    end
  elseif sv.phase == "cleared" and sv.timer <= 0 then
    sv.index, sv.phase, sv.timer = sv.index + 1, "countdown", 0
  end
  if message() ~= sv.said then -- told again only when something shows a change
    tell(server)
  end
end

--- Someone joining mid-fight hears where it stands.
function Waves.joined(server, player)
  if sv then
    server:send(player, message())
  end
end

return Waves
