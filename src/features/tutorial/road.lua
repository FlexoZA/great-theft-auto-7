-- Level 1's lesson as it happens (docs/tutorial.md, "Level 1: Cross the
-- road"). Host only: watches the players on Shoeman's Road and has
-- Shoeman say the next part of the moving and stamina lesson the first
-- time someone gets to it (story.lua's `tutorial-1.*` beats, each said
-- once per level by comms.lua):
--   sprint  someone's stamina drops: what the bar is, and its rest
--   spent   someone runs it empty: no running until it comes back
--   strip   someone stands on the pavement between two streets: get your breath back here
--   across  someone is past the last street, on the lawn
-- A death under a car ("flat") is the tutorial's `serverKill`, not this.
--
--   Road.serverStep(server, map)  map: the road (`map.streets`), during level 1

local Features = require("src.features")
local Comms = require("src.features.tutorial.comms")

local Road = {}

--- Is y on the pavement between two streets? Streets run bottom (1, the
--- largest y) to top, so street n+1's bottom edge is above street n's top.
local function onStrip(streets, y)
  for n = 1, #streets - 1 do
    if y > streets[n + 1].y1 and y < streets[n].y0 then
      return true
    end
  end
  return false
end

function Road.serverStep(server, map)
  local onFoot = Features.byName["on-foot"]
  local streets = map.streets
  local top = streets[#streets]
  for _, player in pairs(server.players) do
    if not player.bot and Features.present(player) then
      local _, y, walking = Features.bodyPose(server, player)
      -- On-foot's own record of their bar: `spent` from the moment it runs
      -- empty until it has come back far enough to run again.
      local st = onFoot and walking and onFoot.sv and onFoot:walker(player)
      if st and st.stamina < st.max then
        Comms.serverBeat(server, "sprint")
      end
      if st and st.spent then
        Comms.serverBeat(server, "spent")
      end
      if walking and onStrip(streets, y) then
        Comms.serverBeat(server, "strip")
      end
      if walking and y < top.y0 then
        Comms.serverBeat(server, "across")
      end
    end
  end
end

return Road
