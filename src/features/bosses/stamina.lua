-- A boss's breath, on the host: the rule on-foot gives players (sprinting
-- drains stamina, resting refills it after a pause, an emptied bar is
-- "winded" until enough is back), with the boss's own numbers.
--
--   local st = Stamina.new({ drain = 16, regen = 14, recovered = 50 })
--   st:step(running, dt)         -- every tick: was it at full tilt this tick?
--   st:pace(runSpeed, walkSpeed) -- how fast it may move right now
--   st:winded()                  -- true while it is walking it off
--   st:has(cost)                 -- breath for an ability that needs `cost`?
--   st:spend(cost)               -- the ability went: pay for it
--   st:wire()                    -- <stamina> <winded> for a state message
--   Stamina.read(args, i)        -- the two back off the wire (client)
--
-- `has` asks for more than the cost: `breath` (half a bar by default) is
-- what it must hold before it draws on it, so a boss just back from being
-- winded does not blow itself out again with one ability.

local Stamina = {}
Stamina.__index = Stamina

Stamina.defaults = {
  max = 100,
  drain = 16, -- per second at full tilt (~6 s of running; a player's sprint is 4.5 s)
  regen = 14, -- per second otherwise (a player's is 9)
  regenDelay = 1, -- seconds off the run before it starts coming back
  recovered = 50, -- back from empty before it runs again (~4.5 s)
  breath = 50, -- held before it may use an ability
}

--- A full breath. `tuning` overrides any of the defaults.
function Stamina.new(tuning)
  local st = { spent = false, regenIn = 0 }
  for k, v in pairs(Stamina.defaults) do
    st[k] = tuning and tuning[k] or v
  end
  st.stamina = st.max
  return setmetatable(st, Stamina)
end

--- One tick: `running` says whether it spent the tick at full tilt.
function Stamina:step(running, dt)
  if running then
    self.stamina = math.max(0, self.stamina - self.drain * dt)
    self.regenIn = self.regenDelay
    if self.stamina <= 0 then
      self.spent = true
    end
  else
    self.regenIn = self.regenIn - dt
    if self.regenIn <= 0 then
      self.stamina = math.min(self.max, self.stamina + self.regen * dt)
    end
    if self.spent and self.stamina >= self.recovered then
      self.spent = false
    end
  end
end

function Stamina:winded()
  return self.spent
end

--- Full tilt with breath in it, a walk without.
function Stamina:pace(run, walk)
  return self.spent and walk or run
end

--- Breath for an ability costing `cost`: not winded, and holding at least
--- `breath` (or the cost, whichever is more).
function Stamina:has(cost)
  return not self.spent and self.stamina >= math.max(self.breath, cost or 0)
end

--- An ability went: pay for it, and no breath comes back for a moment.
function Stamina:spend(cost)
  self.stamina = math.max(0, self.stamina - (cost or 0))
  self.regenIn = self.regenDelay
end

--- The two fields a state message ends with.
function Stamina:wire()
  return math.floor(self.stamina), self.spent and 1 or 0
end

--- Those two fields back, from `args[i]` and `args[i + 1]`: stamina (nil
--- when missing) and whether it is winded.
function Stamina.read(args, i)
  return tonumber(args[i]), args[i + 1] == "1"
end

return Stamina
