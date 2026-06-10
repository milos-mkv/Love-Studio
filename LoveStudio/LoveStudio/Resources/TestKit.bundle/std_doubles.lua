-- std_doubles.lua — deterministic standard-library doubles for user code.
--
-- Installed around the user's code and restored between tests; the framework itself
-- keeps the real os/io/debug for timing, the wire protocol, and tracebacks.
--
--   os.time/date/clock -> fixed, controllable clock
--   os.exit            -> disabled (a test must never kill the process)
--   os.getenv          -> empty
--   io.*               -> in-memory filesystem, shared with love.filesystem
--   math.random        -> deterministic
--   print              -> routed to a capture sink, tagged per test by the facade

local M = {}

-- Canonicalize a path to the key form love_stubs uses so io and love.filesystem
-- share one backing store.
local function canonical(p) return tostring(p):gsub("^/+", "") end

-- An in-memory file handle over the shared store.
local function makeHandle(store, key, mode)
  local buf = store[key] or ""
  local pos = 1
  local writing = mode:find("w") ~= nil
  local appending = mode:find("a") ~= nil
  if writing then buf = ""; store[key] = "" end
  if appending then pos = #buf + 1 end

  local h = {}
  function h:read(fmt)
    fmt = fmt or "l"
    fmt = tostring(fmt):gsub("^%*", "")  -- accept "*a"/"a", "*l"/"l", "*n"/"n"
    if fmt == "a" then
      local rest = buf:sub(pos); pos = #buf + 1; return rest
    elseif fmt == "l" or fmt == "L" then
      if pos > #buf then return nil end
      local nl = buf:find("\n", pos, true)
      local line
      if nl then
        line = buf:sub(pos, fmt == "L" and nl or nl - 1); pos = nl + 1
      else
        line = buf:sub(pos); pos = #buf + 1
      end
      return line
    elseif fmt == "n" then
      local num = buf:match("^%s*(-?%d+%.?%d*)", pos)
      if not num then return nil end
      pos = pos + #buf:match("^%s*", pos) + #num
      return tonumber(num)
    end
    return nil
  end
  function h:write(...)
    for _, v in ipairs({ ... }) do buf = buf .. tostring(v) end
    store[key] = buf
    return h
  end
  function h:lines()
    return function() return h:read("l") end
  end
  function h:close() store[key] = buf; return true end
  function h:seek(whence, offset)
    whence = whence or "cur"; offset = offset or 0
    if whence == "set" then pos = offset + 1
    elseif whence == "cur" then pos = pos + offset
    elseif whence == "end" then pos = #buf + 1 + offset end
    return pos - 1
  end
  return h
end

-- Install the doubles. `fsStore` is the shared path->bytes table (love_stubs.fs.store);
-- `sink` receives user print() output. Returns a controller with apply/restoreReal/reset.
function M.install(fsStore, sink)
  fsStore = fsStore or {}
  sink = sink or function() end

  local clock = 0  -- controllable; deterministic across a test

  local osD = {
    time    = function() return clock end,
    clock   = function() return clock end,
    date    = function(fmt) return tostring(fmt or "fake-date") end,
    getenv  = function() return nil end,
    exit    = function() error("os.exit() is disabled in tests", 2) end,
    -- test-facing control (not real os): advance the deterministic clock
    _advance = function(dt) clock = clock + (dt or 0) end,
    -- pass through harmless real fns
    difftime = os.difftime,
  }

  local ioD = {
    open = function(name, mode)
      mode = mode or "r"
      local key = canonical(name)
      if mode:find("r") and fsStore[key] == nil then
        return nil, name .. ": No such file or directory"
      end
      return makeHandle(fsStore, key, mode)
    end,
    lines = function(name)
      local key = canonical(name)
      local data = fsStore[key]
      if data == nil then error(name .. ": No such file or directory", 2) end
      local h = makeHandle(fsStore, key, "r")
      return h:lines()
    end,
    write = function(...) sink(table.concat({ ... })); return ioD end,
    read  = function() return nil end,  -- no stdin in tests
  }

  local mathD = setmetatable({
    random = function(a, b)
      if a and b then return a + math.floor((b - a) / 2) end
      if a then return math.floor(a / 2) end
      return 0.5
    end,
    randomseed = function() end,
  }, { __index = math })  -- inherit sqrt/floor/etc. from real math

  local printD = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    sink(table.concat(parts, "\t"))
  end

  -- The set of globals we override for user code, and their real originals.
  local overrides = { os = osD, io = ioD, math = mathD, print = printD }
  local reals = { os = os, io = io, math = math, print = print }

  local controller = { os = osD, io = ioD, math = mathD }

  -- Apply / remove the overrides on _G. The facade brackets the user module load
  -- with apply() and restores via real() after each test.
  function controller.apply()
    for k, v in pairs(overrides) do _G[k] = v end
  end
  function controller.restoreReal()
    for k, v in pairs(reals) do _G[k] = v end
  end
  function controller.reset()
    clock = 0   -- fsStore is cleared by love_stubs.reset(); just reset the clock
    controller.restoreReal()
  end

  return controller
end

return M
