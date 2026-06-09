-- love_stubs.lua — test doubles for the love.* API (§5.1, §5.2)
--
-- Default behavior: every love.* call is doubled. The common subset is modeled
-- faithfully; everything else returns a *recursive spy proxy* so no call ever
-- crashes a test (a scalar default would crash the object path, e.g.
-- love.graphics.newImage():getWidth()).
--
-- A test may opt into the REAL module for a subsystem via love.<module>.real()
-- (§5.1); the lifecycle reset restores the double afterward.
--
-- This module installs a global `love` table and returns a controller used by
-- the facade to reset state between tests and to swap in real modules.

local M = {}

-- The shared in-memory filesystem store (path -> bytes), shared with std_doubles'
-- io.* via M.fs so a test can write via love.filesystem and read via io (§3.3a).
M.fs = M.fs or { store = {} }

-- ── recursive spy proxy ──────────────────────────────────────────────────────
-- Survives call, index/method-chain, arithmetic, concat, length, comparison,
-- tostring. Records calls in `.calls` for assertion. (Validated in Phase 0.)
local function makeSpy(path)
  local calls = {}
  local proxy
  local mt = {
    __call = function(_, ...)
      calls[#calls + 1] = { ... }
      return makeSpy(path)
    end,
    __index = function(_, k)
      if k == "calls" then return calls end
      if k == "__spyPath" then return path end
      return makeSpy(path .. "." .. tostring(k))
    end,
    __add = function() return 0 end,
    __sub = function() return 0 end,
    __mul = function() return 0 end,
    __div = function() return 0 end,
    __mod = function() return 0 end,
    __unm = function() return 0 end,
    __concat = function(a, b)
      -- one side is the proxy; return the other side's string form
      if a == proxy then return tostring(b) else return tostring(a) end
    end,
    __len = function() return 0 end,
    __eq = function() return false end,
    __lt = function() return false end,
    __le = function() return false end,
    __tostring = function() return "<love-spy:" .. path .. ">" end,
  }
  proxy = setmetatable({}, mt)
  return proxy
end
M.makeSpy = makeSpy

-- ── faithfully-modeled common subset ─────────────────────────────────────────
-- Built fresh on each reset so state never leaks between tests.
local function buildModeled(fs)
  local time = 0  -- controllable clock for love.timer (deterministic)

  local graphics = {
    -- record draws as spies but return nothing; object constructors return
    -- recursive spies so chained methods are safe.
    newImage       = function() return makeSpy("love.graphics.newImage()") end,
    newQuad        = function() return makeSpy("love.graphics.newQuad()") end,
    newCanvas      = function() return makeSpy("love.graphics.newCanvas()") end,
    newFont        = function() return makeSpy("love.graphics.newFont()") end,
    newSpriteBatch = function() return makeSpy("love.graphics.newSpriteBatch()") end,
    draw      = makeSpy("love.graphics.draw"),
    print     = makeSpy("love.graphics.print"),
    setColor  = makeSpy("love.graphics.setColor"),
    getWidth  = function() return 800 end,
    getHeight = function() return 600 end,
  }

  local function canonical(path) return tostring(path):gsub("^/+", "") end
  local filesystem = {
    write = function(name, data)
      fs.store[canonical(name)] = tostring(data); return true
    end,
    read = function(name)
      local d = fs.store[canonical(name)]
      if d == nil then return nil, "could not open file" end
      return d, #d
    end,
    getInfo = function(name)
      local d = fs.store[canonical(name)]
      if d == nil then return nil end
      return { type = "file", size = #d }
    end,
    remove = function(name) fs.store[canonical(name)] = nil; return true end,
  }

  local timer = {
    getTime  = function() return time end,
    step     = function() return 0 end,
    getDelta = function() return 0 end,
    -- test-facing control (not a real love API): advance the clock
    _advance = function(dt) time = time + (dt or 0) end,
  }

  local math = {
    random = function(a, b)
      -- deterministic: midpoint, not real randomness
      if a and b then return a + math.floor((b - a) / 2) end
      if a then return math.floor(a / 2) end
      return 0.5
    end,
    randomseed = function() end,
  }

  local event = {
    quit = makeSpy("love.event.quit"),
    push = makeSpy("love.event.push"),
  }

  return {
    graphics = graphics, filesystem = filesystem,
    timer = timer, math = math, event = event,
  }
end

-- ── install ──────────────────────────────────────────────────────────────────
-- Returns a controller: { reset(), useReal(name), G } where G is the love table.
function M.install()
  local modeled = buildModeled(M.fs)
  local realModules = {}        -- name -> real impl when a test opts in
  local love = {}

  -- love is a table whose missing keys become recursive spies (auto-spy).
  setmetatable(love, {
    __index = function(_, k)
      if realModules[k] ~= nil then return realModules[k] end
      if modeled[k] ~= nil then return modeled[k] end
      local s = makeSpy("love." .. k)
      rawset(love, k, s)  -- cache so identity is stable within a test
      return s
    end,
  })

  -- Attach a .real() opener to each modeled module so a test can opt in (§5.1).
  -- love.<module>.real() swaps in the genuine implementation for this test.
  for name, mod in pairs(modeled) do
    if type(mod) == "table" then
      mod.real = function()
        realModules[name] = M.realImpl and M.realImpl(name) or mod
        rawset(love, name, realModules[name])
        return realModules[name]
      end
    end
  end

  local controller = {}
  controller.G = love

  function controller.reset()
    -- rebuild modeled state, drop opted-in real modules, clear cached spies,
    -- and clear the shared fs store (§3.3a lifecycle reset).
    modeled = buildModeled(M.fs)
    realModules = {}
    for k in pairs(love) do rawset(love, k, nil) end
    for k in pairs(M.fs.store) do M.fs.store[k] = nil end
    for name, mod in pairs(modeled) do
      if type(mod) == "table" then
        mod.real = function()
          realModules[name] = M.realImpl and M.realImpl(name) or mod
          rawset(love, name, realModules[name])
          return realModules[name]
        end
      end
    end
  end

  -- Optional hook the runner sets so .real() can fetch the genuine love module
  -- (under headless love with that module enabled). Default: no-op (returns nil).
  M.realImpl = M.realImpl or function() return nil end

  _G.love = love
  return controller
end

return M
