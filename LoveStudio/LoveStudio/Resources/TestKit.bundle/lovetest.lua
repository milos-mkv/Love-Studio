-- lovetest.lua — the test facade.
--
-- A single require exposes describe/it, the lifecycle hooks, assert/spy/stub/mock
-- (luassert), and the given/test aliases, with the love/std doubles installed
-- underneath. The facade owns the nested-lifecycle executor, stable path-based ids,
-- mock-reset between tests, and the wire emitter; assertions and mocks pass through
-- to luassert.
--
-- Bootstrap usage:
--   local lt = require("lovetest")
--   lt.configure{ emit = io.write }   -- emit is the real io.write
--   lt.loadFile("tests/foo.test.lua")
--   lt.run{ filter = nil }            -- nil = all, or a test id

local luaunit  = require("luaunit")
local assert_  = require("luassert")
local spy      = require("luassert.spy")
local stub     = require("luassert.stub")
local mock     = require("luassert.mock")
local loveStubs = require("love_stubs")
local stdDoubles = require("std_doubles")

local M = {}

local cfg = {
  emit = function(s) io.write(s) end,  -- real io.write; set by the bootstrap before doubles
}
function M.configure(opts)
  opts = opts or {}
  if opts.emit then cfg.emit = opts.emit end
end

-- Escape text for a single-line wire field (it can contain ", newlines, etc.).
local function esc(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
  return s
end

local function emitTest(rec)
  cfg.emit(string.format(
    '[[LS_TEST]]{"id":"%s","name":"%s","status":"%s","file":"%s","line":%d,"ms":%d,"msg":"%s"}\n',
    esc(rec.id), esc(rec.name), rec.status, esc(rec.file), rec.line or 0, rec.ms or 0, esc(rec.msg)))
end
local function emitOut(id, text)
  cfg.emit(string.format('[[LS_OUT]]{"id":"%s","text":"%s"}\n', esc(id), esc(text)))
end

-- The test tree, built by describe/it.
local root = { name = "", setups = {}, teardowns = {}, befores = {}, afters = {},
               children = {}, tests = {}, seq = {}, parent = nil }
local cur  = root
local curFile = "?"

-- Stable path-based id: file > describe > ... > it
local function nodePath(scope)
  local parts, n = {}, scope
  while n and n.parent do table.insert(parts, 1, n.name); n = n.parent end
  return table.concat(parts, " > ")
end
local function testId(scope, name)
  local p = nodePath(scope)
  local base = curFileLabel or curFile
  if p == "" then return base .. " > " .. name end
  return base .. " > " .. p .. " > " .. name
end

function M.describe(name, fn)
  -- `seq` interleaves child describes and tests in declaration order, so tests run
  -- exactly as written rather than all-tests-then-all-children.
  local node = { name = name, setups = {}, teardowns = {}, befores = {}, afters = {},
                 children = {}, tests = {}, seq = {}, parent = cur }
  cur.children[#cur.children + 1] = node
  cur.seq[#cur.seq + 1] = { kind = "describe", node = node }
  local prev = cur; cur = node
  fn()
  cur = prev
end
-- setup/teardown: run ONCE per suite (before the first test / after the last test
-- in the enclosing describe). before_each/after_each run around EVERY test.
function M.setup(fn)       cur.setups[#cur.setups + 1]       = fn end
function M.teardown(fn)    cur.teardowns[#cur.teardowns + 1] = fn end
function M.before_each(fn) cur.befores[#cur.befores + 1]     = fn end
function M.after_each(fn)  cur.afters[#cur.afters + 1]       = fn end
function M.it(name, fn)
  local t = {
    name = name, fn = fn, scope = cur,
    id = testId(cur, name), file = curFile, line = (function()
      local info = debug.getinfo(fn, "S")  -- real debug, framework side
      return info and info.linedefined or 0
    end)(),
  }
  cur.tests[#cur.tests + 1] = t
  cur.seq[#cur.seq + 1] = { kind = "test", test = t }
end

local loveCtl, stdCtl
local capturedSink            -- per-test print capture target

local function installDoubles()
  loveCtl = loveStubs.install()
  stdCtl  = stdDoubles.install(loveStubs.fs.store, function(t)
    if capturedSink then capturedSink(t) end
  end)
end

-- Load a test file; its describe/it calls register into the tree. The chunk name is
-- set to the filename ("@foo.test.lua") so breakpoints — which the editor keys by
-- filename — match lines in the test file.
function M.loadFile(path)
  curFile = path
  curFileLabel = path:match("([^/\\]+)$") or path
  local chunk, err
  local f = io.open(path, "r")
  if f then
    local src = f:read("*a"); f:close()
    chunk, err = load(src, "@" .. curFileLabel)
  else
    chunk, err = loadfile(path)
  end
  if not chunk then
    -- a file that fails to load becomes a synthetic error node in the tree
    local id = (path:match("([^/\\]+)$") or path) .. " > <load error>"
    M.__loadErrors = M.__loadErrors or {}
    M.__loadErrors[#M.__loadErrors + 1] = { id = id, file = path, msg = err }
    return false, err
  end
  setfenv = setfenv  -- 5.1 has setfenv; keep the test file in the global env
  chunk()
  return true
end

-- Clear a module from the require cache so its state is fresh.
function M.freshRequire(name)
  package.loaded[name] = nil
  return require(name)
end

-- Prepend a package searcher that loads project modules with a filename chunk name
-- ("@foo.lua") so breakpoints in game code match (same reason as loadFile). Kit
-- modules keep the default loader. The real io.open is captured up front because the
-- std doubles replace io.open during a run, and the searcher must read real files.
function M.installFilenameChunkLoader(projectRoot)
  local searchers = package.loaders or package.searchers
  if not searchers then return end
  local realOpen = io.open
  local kitMarkers = { "TestKit", "luaunit", "luassert", "say", "luacov", "lfs",
                       "lovetest", "love_stubs", "std_doubles" }
  local function isKit(path)
    for _, m in ipairs(kitMarkers) do if path:find(m, 1, true) then return true end end
    return false
  end
  local function searcher(name)
    local rel = name:gsub("%.", "/")
    for tmpl in package.path:gmatch("[^;]+") do
      local candidate = tmpl:gsub("%?", rel)
      local f = realOpen(candidate, "r")
      if f then
        if isKit(candidate) then f:close(); return nil end
        local src = f:read("*a"); f:close()
        local base = candidate:match("([^/\\]+)$") or candidate
        local chunk, err = load(src, "@" .. base)
        if chunk then return chunk end
        return err
      end
    end
    return nil
  end
  table.insert(searchers, 1, searcher)
end
local function lineage(scope)
  local chain, n = {}, scope
  while n do table.insert(chain, 1, n); n = n.parent end
  return chain
end

-- Distinguishing an assertion failure from a thrown error: luassert raises a plain
-- string, indistinguishable from error("x") by type. The wrapped `assert` (below)
-- re-raises failures tagged with this marker so detection is exact, independent of
-- message wording or language pack.
local ASSERT_TAG = "\1LS_ASSERT\1"
local function isAssertionFailure(e)
  return type(e) == "string" and e:sub(1, #ASSERT_TAG) == ASSERT_TAG
end
local function errString(e)
  e = tostring(e)
  if e:sub(1, #ASSERT_TAG) == ASSERT_TAG then e = e:sub(#ASSERT_TAG + 1) end
  return e
end

local function runOne(test)
  local chain = lineage(test.scope)
  local ran, beforeErr = {}, nil

  -- befores: outer→inner; track completed scopes for matched teardown
  for _, s in ipairs(chain) do
    local ok = true
    for _, b in ipairs(s.befores) do
      local good, e = pcall(b)
      if not good then ok = false; beforeErr = e; break end
    end
    if ok then ran[#ran + 1] = s else break end
  end

  local bodyErr, bodyIsAssertion
  if not beforeErr then
    local good, e = pcall(test.fn)
    if not good then bodyErr = e; bodyIsAssertion = isAssertionFailure(e) end
  end

  -- afters: inner→outer, only for scopes whose befores completed
  for i = #ran, 1, -1 do
    for _, a in ipairs(ran[i].afters) do pcall(a) end
  end

  if beforeErr then
    -- a hook throwing is an error, not an assertion failure
    return "error", "before_each: " .. errString(beforeErr)
  elseif bodyErr then
    -- failed = an assertion didn't hold; error = the test threw
    return (bodyIsAssertion and "failed" or "error"), errString(bodyErr)
  else
    return "passed", ""
  end
end

-- Reset doubles between tests: rebuild love doubles, restore std libs, reset spies.
local function resetBetweenTests()
  if loveCtl then loveCtl.reset() end
  if stdCtl  then stdCtl.reset() end
end

-- Collect tests in declaration order by walking the interleaved `seq`.
local function collect(node, acc)
  for _, entry in ipairs(node.seq) do
    if entry.kind == "test" then
      acc[#acc + 1] = entry.test
    else
      collect(entry.node, acc)
    end
  end
end

function M.run(opts)
  opts = opts or {}
  installDoubles()
  local realClock = os.clock  -- real timing for durations

  local summary = { passed = 0, failed = 0, error = 0 }
  local tap = {}            -- TAP lines, emitted at the end
  local n = 0
  local function tapLine(status, name)
    n = n + 1
    local ok = (status == "passed") and "ok" or "not ok"
    local note = (status == "error") and " # error" or (status == "failed" and " # failed" or "")
    tap[#tap + 1] = string.format("%s %d - %s%s", ok, n, name, note)
  end

  -- Load errors happened before any test ran, so emit them first.
  for _, le in ipairs(M.__loadErrors or {}) do
    emitTest({ id = le.id, name = "<load error>", status = "error",
               file = le.file, line = 0, ms = 0, msg = le.msg })
    summary.error = summary.error + 1
    tapLine("error", le.id)
  end

  local tests = {}
  collect(root, tests)

  -- Each suite's setup() runs once before its first executed test; teardown() runs
  -- once after the last test (at the end here, inner→outer). `entered` records the
  -- suites whose setup has fired, in entry order.
  local entered, enteredSet, setupErrByScope = {}, {}, {}
  local function enterScope(scope)
    -- run setup for every ancestor scope (outer→inner) not yet entered
    local chain = lineage(scope)
    for _, s in ipairs(chain) do
      if not enteredSet[s] then
        enteredSet[s] = true
        entered[#entered + 1] = s
        for _, fn in ipairs(s.setups or {}) do
          local ok, e = pcall(fn)
          if not ok then setupErrByScope[s] = errString(e); break end
        end
      end
    end
  end
  -- did any ancestor scope of `scope` fail its setup?
  local function scopeSetupError(scope)
    for _, s in ipairs(lineage(scope)) do
      if setupErrByScope[s] then return setupErrByScope[s] end
    end
    return nil
  end

  for _, t in ipairs(tests) do
    if opts.filter == nil or t.id == opts.filter
       or (opts.suite and t.id:find(opts.suite, 1, true) == 1) then
      enterScope(t.scope)   -- fire any pending suite setups before this test

      -- capture this test's print() output, tagged with its id
      capturedSink = function(text) emitOut(t.id, text) end
      stdCtl.apply()

      local setupErr = scopeSetupError(t.scope)
      local status, msg, ms
      if setupErr then
        status, msg, ms = "error", "setup: " .. setupErr, 0
      else
        local t0 = realClock()
        status, msg = runOne(t)
        ms = math.floor((realClock() - t0) * 1000)
      end

      stdCtl.restoreReal()
      capturedSink = nil

      emitTest({ id = t.id, name = t.name, status = status,
                 file = t.file, line = t.line, ms = ms, msg = msg })
      summary[status] = (summary[status] or 0) + 1
      tapLine(status, t.id)

      resetBetweenTests()
    end
  end

  -- teardown: once per entered suite, inner→outer (reverse entry order).
  stdCtl.apply()
  for i = #entered, 1, -1 do
    for _, fn in ipairs(entered[i].teardowns or {}) do pcall(fn) end
  end
  stdCtl.restoreReal()

  -- TAP summary to the Console: plan header, body, then counts.
  cfg.emit("TAP version 13\n1.." .. n .. "\n")
  for _, line in ipairs(tap) do cfg.emit(line .. "\n") end
  cfg.emit(string.format("# passed %d  failed %d  error %d\n",
    summary.passed, summary.failed, summary.error))

  return summary
end

-- Discovery: emit the test tree (one [[LS_TREE]] line per test) without running any
-- test bodies. The files are already loaded, so the tree reflects exactly what Lua
-- parsed — every construct and nesting handled correctly.
function M.collect()
  installDoubles()   -- resolve registration-time love.* references; bodies are not run
  for _, le in ipairs(M.__loadErrors or {}) do
    cfg.emit(string.format(
      '[[LS_TREE]]{"id":"%s","name":"%s","file":"%s","line":%d}\n',
      esc(le.id), esc("<load error>"), esc(le.file), 0))
  end
  local tests = {}
  collect(root, tests)
  for _, t in ipairs(tests) do
    cfg.emit(string.format(
      '[[LS_TREE]]{"id":"%s","name":"%s","file":"%s","line":%d}\n',
      esc(t.id), esc(t.name), esc(t.file), t.line or 0))
  end
  stdCtl.restoreReal()   -- don't leave doubles installed after a collect-only pass
end

-- Wrap luassert so its failures are tagged with ASSERT_TAG, letting the executor
-- classify them as `failed` (assertion) vs `error` (thrown). The proxy preserves
-- luassert's call+index shape; only the failure path is tagged.
local function tagPcall(fn)
  return function(...)
    local res = { pcall(fn, ...) }
    if res[1] then
      return table.unpack and table.unpack(res, 2) or unpack(res, 2)
    end
    local e = res[2]
    -- only tag if not already tagged (nested asserts)
    if type(e) == "string" and e:sub(1, #ASSERT_TAG) ~= ASSERT_TAG then
      e = ASSERT_TAG .. e
    end
    error(e, 0)  -- level 0: keep our tagged message verbatim
  end
end

-- Proxy a luassert callable/table, tagging failures and recursively wrapping nested
-- tables/callables (e.g. assert.are -> .equal).
local function wrapAssert(node)
  local t = type(node)
  if t == "function" then
    return tagPcall(node)
  elseif t == "table" then
    return setmetatable({}, {
      __call  = function(_, ...) return tagPcall(node)(...) end,
      __index = function(_, k)
        local v = node[k]
        if type(v) == "function" or type(v) == "table" then
          return wrapAssert(v)
        end
        return v
      end,
    })
  end
  return node
end

-- Public surface.
M.assert = wrapAssert(assert_)
M.spy    = spy
M.stub   = stub
M.mock   = mock
M.given  = M.describe   -- aliases
M.test   = M.it

-- Expose the API as globals so test files read cleanly (no require needed).
function M.expose(env)
  env = env or _G
  env.describe    = M.describe
  env.it          = M.it
  env.setup       = M.setup
  env.teardown    = M.teardown
  env.before_each = M.before_each
  env.after_each  = M.after_each
  env.assert      = M.assert
  env.spy         = M.spy
  env.stub        = M.stub
  env.mock        = M.mock
  env.given       = M.given
  env.test        = M.test
end

return M
