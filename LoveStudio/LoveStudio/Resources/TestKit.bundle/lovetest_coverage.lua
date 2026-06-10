-- Computes coverage from LuaCov. The percentage is derived from the reporter's
-- hit/miss accounting, not stats `max` (which counts blank/comment lines too).

local M = {}

-- Run LuaCov's reporter once, collecting overall hit/miss counts and per-file
-- covered/uncovered line numbers. Returns:
--   percent (number|nil), perFile = { [key] = { hit = {lines}, miss = {lines} } }
local function analyze(statsfile, reportfile, opts)
  local ok_stats, stats = pcall(require, "luacov.stats")
  if not ok_stats then return nil, {} end
  local data = stats.load(statsfile)
  if not data then return nil, {} end

  local ok_rep, reporter = pcall(require, "luacov.reporter")
  if not ok_rep then return nil, {} end

  -- Accumulate per-file, keyed by a normalized path, merging duplicates: LuaCov's
  -- includeuntestedfiles can list a tested file again under a different path form
  -- (relative vs required), producing a phantom all-miss copy. Merging by normalized
  -- key, with hits winning over a same-line miss, removes that double-count.
  local perFile = {}   -- key -> { hit = set, miss = set }  (set: line -> true)
  local currentKey

  -- Collapse the tracked path (absolute) and the includeuntestedfiles scan path
  -- (cwd-relative) to one key: strip the project-root prefix, then a leading "./".
  local root = opts and opts.projectRoot
  local rootPrefix = root and (tostring(root):gsub("/+$", "") .. "/") or nil
  local function normKey(name)
    name = tostring(name):gsub("\\", "/")
    if rootPrefix and name:sub(1, #rootPrefix) == rootPrefix then
      name = name:sub(#rootPrefix + 1)
    end
    name = name:gsub("^%./", "")
    return name
  end

  local Reporter = setmetatable({}, reporter.ReporterBase)
  Reporter.__index = Reporter
  function Reporter:on_new_file(filename)
    currentKey = normKey(filename)
    perFile[currentKey] = perFile[currentKey] or { hit = {}, miss = {} }
  end
  function Reporter:on_hit_line(filename, lineno)
    local f = perFile[normKey(filename)] or perFile[currentKey]
    if f then f.hit[lineno] = true; f.miss[lineno] = nil end  -- a hit wins over a miss
  end
  function Reporter:on_mis_line(filename, lineno)
    local f = perFile[normKey(filename)] or perFile[currentKey]
    if f and not f.hit[lineno] then f.miss[lineno] = true end
  end
  function Reporter:on_empty_line() end
  function Reporter:on_end_file() end

  local conf = {
    statsfile = statsfile,
    reportfile = reportfile,
    includeuntestedfiles = opts and opts.includeUntested or nil,
  }
  local rep, err = Reporter:new(conf)
  if not rep then return nil, {} end
  local ok = pcall(function() rep:run(); rep:close() end)
  if not ok then return nil, {} end

  -- Totals from the deduped sets; convert sets to sorted lists.
  local hits, missed = 0, 0
  local out = {}
  for key, f in pairs(perFile) do
    local hitList, missList = {}, {}
    for ln in pairs(f.hit)  do hitList[#hitList + 1]  = ln end
    for ln in pairs(f.miss) do missList[#missList + 1] = ln end
    table.sort(hitList); table.sort(missList)
    hits = hits + #hitList
    missed = missed + #missList
    out[key] = { hit = hitList, miss = missList }
  end

  local total = hits + missed
  local pct = total > 0 and (hits / total) * 100.0 or nil
  return pct, out
end

-- Emit the overall % and per-file line coverage (absolutized so the editor can
-- match by path), plus write the report file. `emit` is the real io.write.
-- `opts.includeUntested` also counts untested project files at 0% (needs the lfs
-- shim). Emits:
--   [[LS_COV]]{"pct":NN.N}
--   [[LS_COVLINES]]{"file":"<absolute>","hit":[..],"miss":[..]}   (one per file)
function M.emit(statsfile, reportfile, emit, projectRoot, opts)
  opts = opts or {}
  opts.projectRoot = projectRoot
  local pct, perFile = analyze(statsfile, reportfile, opts)
  if pct then emit(string.format('[[LS_COV]]{"pct":%0.1f}\n', pct)) end

  local function arr(t)
    local parts = {}
    for i = 1, #t do parts[i] = tostring(t[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local function absolutize(file)
    if file:sub(1, 1) == "/" then return file end
    if projectRoot and projectRoot ~= "" then
      return projectRoot:gsub("/+$", "") .. "/" .. file
    end
    return file
  end
  local function relativize(file)
    if projectRoot and projectRoot ~= "" then
      local root = projectRoot:gsub("/+$", "") .. "/"
      if file:sub(1, #root) == root then return file:sub(#root + 1) end
    end
    return file
  end

  -- Detect function declarations in a source file and whether each is covered.
  -- A function is "covered" if any line in its body was hit. Recognizes:
  --   function Name(...)        function M.name(...)      function M:method(...)
  --   local function name(...)  Name = function(...)      M.name = function(...)
  local function functionsFor(absPath, hitSet)
    local fns = {}
    local f = io.open(absPath, "r")
    if not f then return fns end
    -- read all lines so we can inspect indentation per line
    local src, lineNo, decls = {}, 0, {}
    for line in f:lines() do
      lineNo = lineNo + 1
      src[lineNo] = line
      local name =
            line:match("^%s*function%s+([%w_%.:]+)%s*%(")
         or line:match("^%s*local%s+function%s+([%w_]+)%s*%(")
         or line:match("^%s*([%w_%.:]+)%s*=%s*function%s*%(")
      if name then decls[#decls + 1] = { name = name, line = lineNo } end
    end
    f:close()
    -- A function is covered iff a BODY line ran. We exclude the decl line (always
    -- runs at module load, defining the function) AND any non-indented line in the
    -- span (a column-0 line like `return M` is module scope, not the function body —
    -- this stops the last function from absorbing trailing top-level code).
    for i, decl in ipairs(decls) do
      local stop = (decls[i + 1] and decls[i + 1].line - 1) or lineNo
      local covered = false
      for ln = decl.line + 1, stop do
        local text = src[ln] or ""
        local indented = text:match("^%s") ~= nil
        if indented and hitSet[ln] then covered = true; break end
      end
      fns[#fns + 1] = { name = decl.name, line = decl.line, covered = covered }
    end
    return fns
  end

  -- per-file gutter data + collect rows for the summary report
  local rows = {}
  for file, d in pairs(perFile) do
    local abs = absolutize(file)
    local fesc = abs:gsub("\\", "\\\\"):gsub('"', '\\"')
    emit(string.format('[[LS_COVLINES]]{"file":"%s","hit":%s,"miss":%s}\n',
      fesc, arr(d.hit), arr(d.miss)))
    local h, m = #d.hit, #d.miss
    local total = h + m
    local hitSet = {}
    for _, ln in ipairs(d.hit) do hitSet[ln] = true end
    rows[#rows + 1] = {
      name = relativize(abs),
      abs = abs,
      hit = h, total = total,
      pct = total > 0 and (h / total * 100.0) or 100.0,
      functions = functionsFor(abs, hitSet),
    }
  end
  table.sort(rows, function(a, b) return a.pct < b.pct end)  -- worst first

  -- Write the Markdown report, worst-covered first. The `cov-table` block is parsed
  -- by the in-app viewer into a Grid; rows are pipe-separated and the names link to
  -- source. "|" is stripped from names/paths since it's the field separator.
  local out = io.open(reportfile, "w")
  if out then
    out:write("# Coverage Report\n\n")
    out:write(string.format("Overall: %.1f%%  (%d files)\n\n", pct or 0, #rows))
    local function clean(s) return (tostring(s):gsub("|", "/")) end
    out:write("```cov-table\n")
    for _, r in ipairs(rows) do
      -- F | pct | hit | total | relname | abspath
      out:write(string.format("F|%.1f|%d|%d|%s|%s\n",
        r.pct, r.hit, r.total, clean(r.name), clean(r.abs)))
      if r.functions then
        for _, fn in ipairs(r.functions) do
          -- M | covered(1/0) | name | abspath | line
          out:write(string.format("M|%d|%s|%s|%d\n",
            fn.covered and 1 or 0, clean(fn.name), clean(r.abs), fn.line))
        end
      end
    end
    out:write("```\n")
    out:close()
  end
end

return M
