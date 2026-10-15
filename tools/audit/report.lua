-- Findings, the score out of 10, and the report.
--
-- Every check files findings with `Report.add`. Each has a severity, a
-- category, a stable `key` (the same problem gets the same key on every
-- run, so this branch's findings can be told from the base's) and where it
-- is. Only findings this branch brings in (`new`) cost points; what was
-- already wrong on the base is listed as debt and costs nothing, so a pull
-- request is rated on what it does, not on what it inherited.
--
-- Scoring: each category starts at 10 and loses the penalty of every new
-- finding in it, down to 0; the overall score is the weighted mean of the
-- categories. A blocker zeroes its category and fails the gate whatever
-- the score.

local Report = {}

Report.SEVERITIES = {
  blocker = { penalty = 10, label = "BLOCKER", order = 1 },
  major = { penalty = 2, label = "major", order = 2 },
  minor = { penalty = 0.5, label = "minor", order = 3 },
  info = { penalty = 0, label = "info", order = 4 },
}

Report.CATEGORIES = {
  {
    key = "stability",
    name = "Stability",
    weight = 0.25,
    about = "loads, every quest runs, survives bad messages, saves",
  },
  { key = "arsenal", name = "Arsenal coverage", weight = 0.2, about = "every gun and ability hurts every enemy" },
  { key = "maps", name = "Map completeness", weight = 0.15, about = "backdrop, soundtrack, ammo, nothing in walls" },
  { key = "quality", name = "Code quality", weight = 0.2, about = "lint, leftovers, shortcuts, sloppiness" },
  { key = "structure", name = "Structure", weight = 0.2, about = "scatter, conventions, the feature rules" },
}

Report.PASS = 7.0 -- the gate: at least this overall, and no blocker

function Report.new()
  return setmetatable({ findings = {}, byKey = {}, notes = {}, timings = {} }, { __index = Report })
end

--- File a finding: { severity, category, key, title, detail, file, line }.
--- The same key twice is one finding.
function Report:add(f)
  assert(Report.SEVERITIES[f.severity], "unknown severity " .. tostring(f.severity))
  assert(f.category and f.key and f.title, "a finding needs a category, a key and a title")
  if self.byKey[f.key] then
    return self.byKey[f.key]
  end
  f.new = f.new ~= false
  self.findings[#self.findings + 1] = f
  self.byKey[f.key] = f
  return f
end

--- A line for the report's notes (what was checked, what was skipped).
function Report:note(text)
  self.notes[#self.notes + 1] = text
end

--- Mark every finding the base also has as old (debt): `baseKeys` is a
--- set of the base run's keys.
function Report:subtract(baseKeys)
  for _, f in ipairs(self.findings) do
    if baseKeys[f.key] then
      f.new = false
    end
  end
end

function Report:keys()
  local out = {}
  for _, f in ipairs(self.findings) do
    out[f.key] = true
  end
  return out
end

--- { overall, categories = { [key] = score }, blockers, pass }
function Report:score()
  local scores, blockers = {}, 0
  for _, c in ipairs(Report.CATEGORIES) do
    scores[c.key] = 10
  end
  for _, f in ipairs(self.findings) do
    if f.new then
      local sev = Report.SEVERITIES[f.severity]
      if f.severity == "blocker" then
        blockers = blockers + 1
      end
      scores[f.category] = math.max(0, (scores[f.category] or 10) - sev.penalty)
    end
  end
  local overall = 0
  for _, c in ipairs(Report.CATEGORIES) do
    overall = overall + scores[c.key] * c.weight
  end
  overall = math.floor(overall * 10 + 0.5) / 10
  return {
    overall = overall,
    categories = scores,
    blockers = blockers,
    pass = blockers == 0 and overall >= Report.PASS,
  }
end

local function sorted(findings)
  local list = {}
  for _, f in ipairs(findings) do
    list[#list + 1] = f
  end
  table.sort(list, function(a, b)
    local sa, sb = Report.SEVERITIES[a.severity].order, Report.SEVERITIES[b.severity].order
    if sa ~= sb then
      return sa < sb
    end
    if a.category ~= b.category then
      return a.category < b.category
    end
    return a.key < b.key
  end)
  return list
end

local function where(f)
  if f.file and f.line then
    return ("%s:%d"):format(f.file, f.line)
  end
  return f.file
end

local function escapeCell(s)
  return (tostring(s or ""):gsub("|", "\\|"):gsub("\n", " "))
end

local function bar(score)
  local filled = math.floor(score + 0.5)
  return string.rep("█", filled) .. string.rep("░", 10 - filled)
end

--- The report as Markdown (the CI job summary and `audit.md`).
function Report:markdown(meta)
  local s = self:score()
  local out = {}
  local function w(line)
    out[#out + 1] = line or ""
  end
  w(("# Audit: %.1f / 10 %s"):format(s.overall, s.pass and "✅ PASS" or "❌ FAIL"))
  w()
  if meta then
    w(("Branch `%s` against `%s` (%s). Gate: %.1f and no blocker."):format(meta.branch or "?", meta.base or "?",
      meta.mode or "full", Report.PASS))
    w()
  end
  w("| Category | Score | | Checks |")
  w("| --- | --- | --- | --- |")
  for _, c in ipairs(Report.CATEGORIES) do
    w(("| %s | %.1f | `%s` | %s |"):format(c.name, s.categories[c.key], bar(s.categories[c.key]), c.about))
  end
  w()

  local new, old = {}, {}
  for _, f in ipairs(sorted(self.findings)) do
    if f.new then
      new[#new + 1] = f
    else
      old[#old + 1] = f
    end
  end

  w(("## Findings this branch brings in (%d)"):format(#new))
  w()
  if #new == 0 then
    w("Nothing new. Clean.")
  else
    w("| | Category | Finding | Where |")
    w("| --- | --- | --- | --- |")
    for _, f in ipairs(new) do
      w(("| %s | %s | **%s**%s | %s |"):format(Report.SEVERITIES[f.severity].label, f.category, escapeCell(f.title),
        f.detail and ("<br>" .. escapeCell(f.detail)) or "", escapeCell(where(f) or "")))
    end
  end
  w()

  if #old > 0 then
    w(("<details><summary>Debt already on the base (%d, not scored)</summary>"):format(#old))
    w()
    w("| | Category | Finding | Where |")
    w("| --- | --- | --- | --- |")
    for _, f in ipairs(old) do
      w(("| %s | %s | %s | %s |"):format(Report.SEVERITIES[f.severity].label, f.category, escapeCell(f.title),
        escapeCell(where(f) or "")))
    end
    w()
    w("</details>")
    w()
  end

  if #self.notes > 0 then
    w("<details><summary>What was checked</summary>")
    w()
    for _, n in ipairs(self.notes) do
      w("- " .. n)
    end
    w()
    w("</details>")
  end
  return table.concat(out, "\n")
end

--- The same as plain text for a terminal.
function Report:text(meta)
  local s = self:score()
  local out = {}
  local function w(line)
    out[#out + 1] = line or ""
  end
  w(("AUDIT  %.1f / 10  %s"):format(s.overall, s.pass and "PASS" or "FAIL"))
  if meta then
    w(("branch %s against %s (%s)"):format(meta.branch or "?", meta.base or "?", meta.mode or "full"))
  end
  w()
  for _, c in ipairs(Report.CATEGORIES) do
    w(("  %-18s %4.1f  %s"):format(c.name, s.categories[c.key], bar(s.categories[c.key])))
  end
  w()
  local newCount, oldCount = 0, 0
  for _, f in ipairs(sorted(self.findings)) do
    if f.new then
      newCount = newCount + 1
      w(("  [%s] %s: %s%s"):format(Report.SEVERITIES[f.severity].label, f.category, f.title,
        where(f) and ("  (" .. where(f) .. ")") or ""))
      if f.detail then
        w("      " .. f.detail:gsub("\n", "\n      "))
      end
    else
      oldCount = oldCount + 1
    end
  end
  if newCount == 0 then
    w("  No new findings.")
  end
  if oldCount > 0 then
    w()
    w(("  (%d findings were already on the base: see the report's debt list)"):format(oldCount))
  end
  return table.concat(out, "\n")
end

--- Findings as JSON lines-free JSON, for the base comparison and the review skill.
function Report:json(meta)
  local function str(v)
    return '"' .. tostring(v):gsub('[%c"\\]', function(c)
      return ({ ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" })[c]
        or ("\\u%04x"):format(c:byte())
    end) .. '"'
  end
  local function value(v)
    local t = type(v)
    if t == "table" then
      if #v > 0 or next(v) == nil then
        local parts = {}
        for _, x in ipairs(v) do
          parts[#parts + 1] = value(x)
        end
        return "[" .. table.concat(parts, ",") .. "]"
      end
      local keys = {}
      for k in pairs(v) do
        keys[#keys + 1] = k
      end
      table.sort(keys)
      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = str(k) .. ":" .. value(v[k])
      end
      return "{" .. table.concat(parts, ",") .. "}"
    elseif t == "number" or t == "boolean" then
      return tostring(v)
    elseif v == nil then
      return "null"
    end
    return str(v)
  end
  local list = {}
  for _, f in ipairs(sorted(self.findings)) do
    list[#list + 1] = {
      severity = f.severity,
      category = f.category,
      key = f.key,
      title = f.title,
      detail = f.detail,
      file = f.file,
      line = f.line,
      new = f.new,
    }
  end
  return value({ meta = meta or {}, score = self:score(), findings = list, notes = self.notes })
end

return Report
