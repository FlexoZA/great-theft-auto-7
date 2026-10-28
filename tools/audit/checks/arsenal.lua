-- Every gun, every damaging ability and every grenade against every kind
-- of enemy the audit meets: the host is put on foot in clear sight of one,
-- uses the thing on it the way the game does (weapons' serverFireFrom, the
-- ability's serverCast, grenades' serverLob) and the audit looks whether
-- it was hurt. A pair that hurts on any quest is fine; one that never
-- does is a finding.
--
-- Bosses are healed back after each try, so every weapon gets its turn
-- at them; one-hit enemies are simply used up. After two tries the enemy
-- is held still (serverFreezeArea, as the freeze ability does) so dodgers
-- can't make a weapon look harmless when it is only hard to land.

local Tiers = require("src.features.tiers")

local Arsenal = {}

local GUN_SECONDS = 2 -- trigger held this long, re-aimed every VOLLEY
local VOLLEY = 0.1
local ABILITY_SECONDS = 3
local GRENADE_SECONDS = 3
local RANGES = { 80, 130, 50 } -- px from the enemy's edge to stand at, best first
local TRIES = 5 -- different sides of the enemy before giving up on it, with a gun
local SLOW_TRIES = 6 -- with a grenade or an ability: one go each, and dodgers (Hunters, droids) see them coming
local HELD_AFTER = 2 -- tries after which the enemy is held still (frozen) for the rest

--- Everything a player can hurt with: { key, name, file, kind, item }.
function Arsenal.weapons(game)
  local list = {}
  for _, gun in ipairs(require("src.features.weapons.guns").list) do
    list[#list + 1] = { key = "gun:" .. gun.key, name = gun.name, file = "src/features/weapons/guns.lua",
      kind = "gun", item = gun }
  end
  for _, ability in ipairs(require("src.features.abilities.kinds").list) do
    -- An ability hurts when it carries damage of its own or a gun (the nest).
    if not ability.passive and (type(ability.damage) == "number" or ability.gun) then
      list[#list + 1] = { key = "ability:" .. ability.key, name = ability.title or ability.key,
        file = "src/features/abilities/" .. ability.key .. ".lua", kind = "ability", item = ability }
    end
  end
  local grenades = game.Features.byName.grenades
  local names = {}
  for key in pairs(grenades and grenades.kinds or {}) do
    names[#names + 1] = key
  end
  table.sort(names)
  for _, key in ipairs(names) do
    list[#list + 1] = { key = "grenade:" .. key, name = key, file = "src/features/grenades/init.lua",
      kind = "grenade", item = key }
  end
  return list
end

local function find(game, id)
  for _, e in ipairs(game:enemies()) do
    if e.id == id then
      return e
    end
  end
  return nil
end

local function clearLine(game, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local steps = math.max(1, math.floor(math.sqrt(dx * dx + dy * dy) / 6))
  for i = 0, steps do
    local t = i / steps
    if game:shotBlocked(x0 + dx * t, y0 + dy * t) then
      return false
    end
  end
  return true
end

--- Somewhere to stand with a clear shot at `e`, trying side `try` first.
local function standingSpot(game, e, try)
  local r = e.radius or 10
  for _, range in ipairs(RANGES) do
    for k = 0, 7 do
      local a = (try - 1) * math.pi * 0.75 + k * math.pi / 4
      local d = r + range
      local x, y = e.x + math.cos(a) * d, e.y + math.sin(a) * d
      if not game:blocked(x, y) and (e.flying or clearLine(game, x, y, e.x, e.y)) then
        return x, y
      end
    end
  end
  return nil
end

local function fire(game, weapon, e, sx, sy)
  local server, me = game.server, game:me()
  local features = game.Features
  if weapon.kind == "gun" then
    local gun = Tiers.apply(weapon.item, "common")
    local weapons = features.byName.weapons
    local t = 0
    local lastX, lastY = e.x, e.y
    while t < GUN_SECONDS do
      -- Lead it, as a player would: where it will be when the round gets there.
      local now = find(game, e.id) or e
      local vx, vy = (now.x - lastX) / VOLLEY, (now.y - lastY) / VOLLEY
      lastX, lastY = now.x, now.y
      local flight = math.sqrt((now.x - sx) ^ 2 + (now.y - sy) ^ 2) / (gun.speed or 1000)
      local aim = math.atan2(now.y + vy * flight - sy, now.x + vx * flight - sx)
      game:placeOnFoot(sx, sy, aim)
      game.guard(weapons.serverFireFrom, weapons, server, me.id, sx + math.cos(aim) * 16, sy + math.sin(aim) * 16,
        aim, gun)
      game:godMode()
      game:run(VOLLEY)
      t = t + VOLLEY
      local after = find(game, e.id)
      if not after or (e.hp and after.hp and after.hp < e.hp) then
        return
      end
    end
    game:run(0.3) -- the last rounds land
  elseif weapon.kind == "ability" then
    local ability = Tiers.apply(weapon.item, "common")
    -- Where it is cast, the way a player would: a point ability on the
    -- enemy (a teleport through it and out the far side), a direction one
    -- (the nest stands where it is put) just in front of the caster.
    local a = math.atan2(e.y - sy, e.x - sx)
    local tx, ty = e.x, e.y
    if ability.aim == "direction" then
      tx, ty = sx + math.cos(a) * 30, sy + math.sin(a) * 30
    elseif weapon.item.key == "teleport" then
      tx, ty = e.x + math.cos(a) * ((e.radius or 10) + 60), e.y + math.sin(a) * ((e.radius or 10) + 60)
    end
    local mode = ability.modes and ability.modes[1] and ability.modes[1].key or nil
    game:placeOnFoot(sx, sy, math.atan2(ty - sy, tx - sx))
    local ok, err = game.guard(ability.serverCast, server, me, tx, ty, features.byName.abilities, ability, mode)
    if not ok then
      game:recordError("casting " .. weapon.key, err)
    end
    game:godMode()
    game:run(ABILITY_SECONDS)
  else
    local grenades = features.byName.grenades
    game:placeOnFoot(sx, sy, math.atan2(e.y - sy, e.x - sx))
    game.guard(grenades.serverLob, grenades, server, sx, sy, e.x, e.y, me.id, weapon.item)
    game:godMode()
    game:run(GRENADE_SECONDS)
  end
end

--- Use `weapon` on `e`: "hit", "miss" or "unsure" (it went immune, or
--- left, in the middle).
local function try(game, weapon, e, side, hold)
  local sx, sy = standingSpot(game, e, side)
  if not sx then
    return "unsure"
  end
  if hold then
    -- Held still the way a freeze holds it, so a dodger can't step aside:
    -- the question is whether this can hurt it, not whether it is easy to land.
    game.guard(game.Features.call, "serverFreezeArea", game.server, e.x, e.y, (e.radius or 10) + 20,
      ABILITY_SECONDS + 1, game:me().id)
  end
  local hp0 = e.hp
  local me = game:me().id
  local shots = game.shotsBy[me] or 0
  fire(game, weapon, e, sx, sy)
  local mine = (game.shotsBy[me] or 0) > shots -- something of ours reached a target at all
  local after = find(game, e.id)
  if not after then
    return mine and "hit" or "unsure" -- down, by us or by someone else
  end
  local hit = hp0 and after.hp and after.hp < hp0
  if hit and not mine then
    return "unsure" -- hurt, but not by us (Cyber Feud's sides fight each other)
  end
  -- Heal it back so the next weapon gets a full go at it.
  if hit and type(e.id.hp) == "number" and e.id.hp == after.hp then
    e.id.hp = hp0
  end
  if hit then
    return "hit"
  end
  if after.immune then
    return "unsure"
  end
  return "miss"
end

--- Whether `weapon` against `kind` is the audit's business on this branch.
local function inScope(ctx, weapon, kind)
  local scope = ctx.arsenal
  if scope == true then
    return true
  end
  local feature = kind:match("^([^/]+)/")
  return scope.weapons[weapon.key] or scope.weapons[weapon.kind .. ":*"] or (feature and scope.features[feature])
end

--- Test every pair not yet settled against the enemies in the world now.
function Arsenal.testPresent(report, game, quest, ctx)
  local drawing = game.drawing
  game.drawing = false -- nothing to look at, and five times faster
  Arsenal.testAll(report, game, quest, ctx)
  game.drawing = drawing
end

function Arsenal.testAll(report, game, quest, ctx)
  game:watchShots()
  ctx.matrix = ctx.matrix or {}
  ctx.weaponList = ctx.weaponList or Arsenal.weapons(game)
  local byKind = {}
  for _, e in ipairs(game:enemies()) do
    if not e.immune then
      byKind[e.kind] = byKind[e.kind] or {}
      table.insert(byKind[e.kind], e)
    end
  end
  local tested = 0
  for kind, instances in pairs(byKind) do
    for _, weapon in ipairs(ctx.weaponList) do
      local cell = ctx.matrix[weapon.key .. "\t" .. kind]
      local tries = weapon.kind == "gun" and TRIES or SLOW_TRIES
      if inScope(ctx, weapon, kind) and not (cell and cell.result == "hit") and not (cell and cell.tries >= tries) then
        -- Plain data only: cells travel between processes (run.lua).
        cell = cell or { weapon = { key = weapon.key, name = weapon.name, file = weapon.file }, kind = kind,
          tries = 0, quests = {} }
        ctx.matrix[weapon.key .. "\t" .. kind] = cell
        local side = 1
        while cell.tries < tries and cell.result ~= "hit" do
          -- A live one of this kind (the last try may have used it up).
          local e = nil
          for _, cand in ipairs(instances) do
            local now = find(game, cand.id)
            if now and not now.immune then
              e = now
              break
            end
          end
          if not e then
            break
          end
          cell.tries = cell.tries + 1
          cell.quests[quest.id] = true
          tested = tested + 1
          local result = try(game, weapon, e, side, cell.tries > HELD_AFTER)
          if result == "hit" or not cell.result or cell.result == "unsure" then
            cell.result = result
          end
          side = side + 1
        end
      end
    end
  end
  if tested > 0 then
    report:note(("Arsenal on %s: %d tries"):format(quest.id, tested))
  end
end

--- Fold `cells` (one job's matrix) into `into`: a pair hurts if it hurt
--- anywhere; it never does only when every job that tried it says so.
function Arsenal.merge(into, cells)
  for key, cell in pairs(cells or {}) do
    local have = into[key]
    if not have then
      into[key] = cell
    else
      have.tries = have.tries + cell.tries
      for q in pairs(cell.quests) do
        have.quests[q] = true
      end
      if cell.result == "hit" or have.result == "hit" then
        have.result = "hit"
      elseif cell.result == "miss" or have.result == "miss" then
        have.result = "miss"
      else
        have.result = have.result or cell.result
      end
    end
  end
end

--- Findings for every pair that never hurt, and a note of the matrix.
function Arsenal.summarise(report, ctx)
  local hits, misses, unsure = 0, 0, 0
  local cells = {}
  for _, cell in pairs(ctx.matrix or {}) do
    cells[#cells + 1] = cell
  end
  table.sort(cells, function(a, b)
    return a.weapon.key .. a.kind < b.weapon.key .. b.kind
  end)
  for _, cell in ipairs(cells) do
    local quests = {}
    for q in pairs(cell.quests) do
      quests[#quests + 1] = q
    end
    table.sort(quests)
    if cell.result == "hit" then
      hits = hits + 1
    elseif cell.result == "miss" then
      misses = misses + 1
      report:add({ severity = "major", category = "arsenal", key = "arsenal:" .. cell.weapon.key .. ":" .. cell.kind,
        file = cell.weapon.file,
        title = ("%s does not hurt %s"):format(cell.weapon.name, cell.kind),
        detail = ("Used on it %d times from different sides on %s; its health never dropped. Every weapon "
          .. "and ability should hurt every enemy (serverShotAt / serverBlast)."):format(cell.tries,
          table.concat(quests, ", ")) })
    else
      unsure = unsure + 1
    end
  end
  report:note(("Arsenal matrix: %d pairs hurt, %d never did, %d could not be settled (immune or out of reach "
    .. "at the time)"):format(hits, misses, unsure))
end

return Arsenal
