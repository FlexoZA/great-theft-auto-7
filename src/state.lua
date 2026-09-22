-- Minimal scene switcher. A state is a module table with optional hooks:
-- enter(...), exit(), update(dt), draw(), keypressed(key), textinput(t),
-- mousepressed(x, y, button).

local State = { current = nil, name = nil }

function State.switch(name, ...)
  if State.current and State.current.exit then
    State.current:exit()
  end
  local s = type(name) == "table" and name or require("src.states." .. name)
  State.current = s
  State.name = name
  if s.enter then
    s:enter(...)
  end
end

return State
