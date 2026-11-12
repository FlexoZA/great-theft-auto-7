-- Level 3's squirrels (docs/tutorial.md, "Level 3"): three waves of six,
-- out of the burrows in the far half of the scrap yard (city-map's
-- `map.dens`), each when the one before is dead. They are the events
-- feature's loose squirrels (events/squirrels.lua): they run at the
-- nearest player, bite and back off, and stay until shot.
--
-- Host only. `Waves.serverStart(dens)` once the reload lesson is done;
-- the first wave comes out `FIRST_AFTER` seconds later, each next one
-- `GAP` seconds after the last squirrel of the one before. What happens is
-- told to init.lua through `on`:
--   on.out(server, wave)            wave `wave` (1 to `COUNT`) came out
--   on.killed(server, wave, n)      `n` more of it were shot
--   on.cleared(server, wave)        the last of it is dead
-- Loose squirrels already about when a wave comes out are not counted in it.

local Features = require("src.features")

local Waves = {}

Waves.COUNT = 3 -- waves
Waves.SIZE = 6 -- squirrels in each
Waves.DENS = 2 -- burrows each wave comes out of, the six shared between them
Waves.SPREAD = 36 -- px round a burrow they come out within
Waves.FIRST_AFTER = 5 -- seconds after the reload before the first (his warning)
Waves.GAP = 4 -- seconds between one wave's last squirrel and the next wave

local sv = nil -- { dens, wave, nextIn, others (loose ones not ours), left (ours still loose) }

function Waves.serverStart(dens)
  sv = { dens = dens, wave = 0, nextIn = Waves.FIRST_AFTER, left = 0, others = 0 }
end

function Waves.serverStop()
  sv = nil
end

--- Wave `n` out of its burrows: the dens in turn, `DENS` a wave.
local function release(server, events, n)
  sv.others = events:serverSquirrelsLoose()
  local per = math.ceil(Waves.SIZE / Waves.DENS)
  local left = Waves.SIZE
  for k = 1, Waves.DENS do
    local den = sv.dens[((n - 1) * Waves.DENS + k - 1) % #sv.dens + 1]
    local count = math.min(per, left)
    events:serverSummonSquirrels(server, den.x, den.y, count, Waves.SPREAD)
    left = left - count
  end
  sv.left = Waves.SIZE
end

function Waves.serverStep(server, dt, on)
  local events = Features.byName.events
  if not (sv and events and #sv.dens > 0) then
    return
  end
  if sv.nextIn then
    sv.nextIn = sv.nextIn - dt
    if sv.nextIn > 0 then
      return
    end
    sv.nextIn = nil
    sv.wave = sv.wave + 1
    release(server, events, sv.wave)
    on.out(server, sv.wave)
    return
  end
  local left = math.max(0, events:serverSquirrelsLoose() - sv.others)
  if left < sv.left then
    local n = sv.left - left
    sv.left = left
    on.killed(server, sv.wave, n)
  end
  if left == 0 then
    local wave = sv.wave
    if wave >= Waves.COUNT then
      sv = nil
    else
      sv.nextIn = Waves.GAP
    end
    on.cleared(server, wave)
  end
end

return Waves
