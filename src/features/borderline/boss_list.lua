-- The line's bosses (docs/borderline.md, "The bosses"), each a module of its
-- own that init.lua and tale.lua run the same way: every one is told of
-- every level, and does nothing on a map whose `map.boss` isn't its own.

local List = {
  require("src.features.borderline.scrapper"), -- the Frozen Wreck's Knuckle Scrapper
  require("src.features.borderline.wilbur"), -- the Bragium Pit's Wilbur
  require("src.features.borderline.smelter"), -- the Refinery's Smelter
  require("src.features.borderline.foreman"), -- the Assembly Line's Foreman BIG-B055
  require("src.features.borderline.bnk9"), -- the Bunker's BNK-9
}

--- Hook `name` of every one that has it, with `...`.
function List.call(name, ...)
  for _, boss in ipairs(List) do
    if boss[name] then
      boss[name](...)
    end
  end
end

--- What the first one whose hook `name` answers says.
function List.first(name, ...)
  for _, boss in ipairs(List) do
    if boss[name] then
      local a, b, c = boss[name](...)
      if a then
        return a, b, c
      end
    end
  end
  return nil
end

return List
