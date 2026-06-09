-- lovetest_coverage.lua — compute the overall coverage % from LuaCov (§3.9)
--
-- We must NOT do hits/max: LuaCov's stats `max` is the highest line number, which
-- includes blank/comment lines. The accurate executable-line count comes from
-- LuaCov's reporter (it line-scans each source). So we run the default reporter to
-- produce the text report file (which the clickable-% tab opens) AND derive the
-- overall percent from the reporter's own hit/miss accounting.

local M = {}

-- Run LuaCov's reporter once, collecting both the overall executable hit/miss
-- counts AND per-line covered/uncovered line numbers per file. Returns:
--   percent  (number|nil), perFile = { [filename] = {hit={lines}, miss={lines}} }
local function analyze(statsfile, reportfile)
  local ok_stats, stats = pcall(require, "luacov.stats")
  if not ok_stats then return nil, {} end
  local data = stats.load(statsfile)
  if not data then return nil, {} end

  local ok_rep, reporter = pcall(require, "luacov.reporter")
  if not ok_rep then return nil, {} end

  local hits, missed = 0, 0
  local perFile = {}
  local currentFile

  local Counter = setmetatable({}, reporter.ReporterBase)
  Counter.__index = Counter
  function Counter:on_new_file(filename)
    currentFile = filename
    perFile[filename] = { hit = {}, miss = {} }
  end
  function Counter:on_hit_line(filename, lineno, _, h)
    if h > 0 then
      hits = hits + 1
      local f = perFile[filename] or perFile[currentFile]
      if f then f.hit[#f.hit + 1] = lineno end
    end
  end
  function Counter:on_mis_line(filename, lineno)
    missed = missed + 1
    local f = perFile[filename] or perFile[currentFile]
    if f then f.miss[#f.miss + 1] = lineno end
  end
  function Counter:on_empty_line() end
  function Counter:on_end_file() end

  -- Emit the human-readable default report to reportfile (for the clickable tab).
  pcall(function() reporter.report() end)

  local ok = pcall(function()
    local r = reporter.ReporterBase.new
      and reporter.ReporterBase.new(Counter, { statsfile = statsfile, reportfile = reportfile })
      or setmetatable({}, Counter)
    r:run()
  end)
  if not ok then return nil, {} end

  local total = hits + missed
  local pct = total > 0 and (hits / total) * 100.0 or nil
  return pct, perFile
end

-- Overall percent only (back-compat).
function M.reportPercent(statsfile, reportfile)
  local pct = analyze(statsfile, reportfile)
  return pct
end

-- Emit overall % AND per-line coverage for gutter rendering (§ coverage gutters).
-- `emit` is the real io.write; `projectRoot` is the absolute project path used to
-- resolve relative file paths (LuaCov tracks files as they were required, which for
-- the game modules is relative to the run's working dir). The editor matches by
-- absolute path, so we normalize here. Lines:
--   [[LS_COV]]{"pct":NN.N}
--   [[LS_COVLINES]]{"file":"<absolute>","hit":[..],"miss":[..]}   (one per file)
function M.emit(statsfile, reportfile, emit, projectRoot)
  local pct, perFile = analyze(statsfile, reportfile)
  if pct then emit(string.format('[[LS_COV]]{"pct":%0.1f}\n', pct)) end
  local function arr(t)
    local parts = {}
    for i = 1, #t do parts[i] = tostring(t[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local function absolutize(file)
    -- already absolute?
    if file:sub(1, 1) == "/" then return file end
    if projectRoot and projectRoot ~= "" then
      return projectRoot:gsub("/+$", "") .. "/" .. file
    end
    return file
  end
  for file, d in pairs(perFile) do
    local abs = absolutize(file)
    local fesc = abs:gsub("\\", "\\\\"):gsub('"', '\\"')
    emit(string.format('[[LS_COVLINES]]{"file":"%s","hit":%s,"miss":%s}\n',
      fesc, arr(d.hit), arr(d.miss)))
  end
end

return M
