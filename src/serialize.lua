-- Plain data <-> Lua source. Settings and saved worlds are written with
-- encode and read back with decode, which runs the file with an empty
-- environment: a save passed around between friends can hold data, never
-- code that reaches anything.
--
-- Only tables, strings, numbers and booleans can be written; a function,
-- userdata or a table inside itself is an error naming where it is.

local Serialize = {}

local function number(v)
  if v ~= v then
    return "0/0"
  elseif v == math.huge then
    return "1/0"
  elseif v == -math.huge then
    return "-1/0"
  elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then
    return ("%d"):format(v)
  end
  return ("%.17g"):format(v)
end

local function write(v, indent, path, open)
  local t = type(v)
  if t == "table" then
    if open[v] then
      error("serialize: " .. path .. " contains itself", 0)
    end
    open[v] = true
    local keys = {}
    for k in pairs(v) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
      if type(a) == type(b) and type(a) ~= "boolean" then
        return a < b
      end
      return type(a) < type(b)
    end)
    local parts = {}
    for _, k in ipairs(keys) do
      local at = path .. "." .. tostring(k)
      parts[#parts + 1] = indent .. "  [" .. write(k, "", at, open) .. "] = " .. write(v[k], indent .. "  ", at, open)
    end
    open[v] = nil
    if #parts == 0 then
      return "{}"
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  elseif t == "string" then
    return ("%q"):format(v)
  elseif t == "number" then
    return number(v)
  elseif t == "boolean" then
    return tostring(v)
  end
  error("serialize: cannot write a " .. t .. " at " .. path, 0)
end

--- Lua source that gives back `value` when run: "return { ... }\n".
function Serialize.encode(value)
  return "return " .. write(value, "", "root", {}) .. "\n"
end

--- The value in `source` (from encode), or nil and a reason. The chunk runs
--- with nothing in reach, so a hostile file can only fail to load.
function Serialize.decode(source, name)
  local chunk, err = loadstring(source, name and ("=" .. name) or nil)
  if not chunk then
    return nil, err
  end
  setfenv(chunk, {})
  local ok, value = pcall(chunk)
  if not ok then
    return nil, value
  end
  return value
end

return Serialize
