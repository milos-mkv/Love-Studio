-- lovetest.lua — the test facade (§3.3, §3.5, §4.4)
--
-- One require gives the user: describe/it, before_each/after_each, assert (luassert),
-- spy/stub/mock (luassert), and the love/std doubles installed underneath. AAA aliases
-- (arrange/act and given/when/then) sit over the same core.
--
-- The facade is a thin coordinator: it owns the nested-lifecycle executor, stable
-- path-based IDs, mock-reset between tests, and the structured wire emitter. Assertions
-- and mocks are pass-through to luassert.
--
-- Usage from the bootstrap:
--   local lt = require("lovetest")
--   lt.configure{ emit = io.write, coverage = false }   -- emit is the REAL io.write
--   -- (test files are loaded via lt.loadFile so doubles + freshRequire apply)
--   lt.loadFile("tests/foo.test.lua")
--   lt.run{ filter = nil }   -- nil = all; or a test id

local luaunit  = require("luaunit")  -- vendored engine (used for asserts/util parity)
local assert_  = require("luassert")
local spy      = require("luassert.spy")
local stub     = require("luassert.stub")
local mock     = require("luassert.mock")
local loveStubs = require("love_stubs")
local stdDoubles = require("std_doubles")

local M = {}

-- ── configuration / wire emit (§3.5) ─────────────────────────────────────────
local cfg = {
  emit = function(s) io.write(s) end,  -- REAL io.write; set by bootstrap before doubles
}
function M.configure(opts)
  opts = opts or {}
  if opts.emit then cfg.emit = opts.emit end
end

-- escape arbitrary text for a single-line wire field (§3.5: text can contain
-- }, newlines, or the sentinel itself). JSON-ish string escaping.
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

-- ── the test tree (built by describe/it) ─────────────────────────────────────
local root = { name = "", befores = {}, afters = {}, children = {}, tests = {}, seq = {}, parent = nil }
local cur  = root
local curFile = "?"

-- stable path-based id: file > describe > ... > it  (§4.4)
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
  -- `seq` interleaves child describes and tests in source-declaration order so the
  -- run order is exactly as written (§ deterministic run order), not all-tests-
  -- then-all-children.
  local node = { name = name, befores = {}, afters = {}, children = {}, tests = {},
                 seq = {}, parent = cur }
  cur.children[#cur.children + 1] = node
  cur.seq[#cur.seq + 1] = { kind = "describe", node = node }
  local prev = cur; cur = node
  fn()
  cur = prev
end
function M.before_each(fn) cur.befores[#cur.befores + 1] = fn end
function M.after_each(fn)  cur.afters[#cur.afters + 1]  = fn end
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

-- ── doubles + freshRequire (§3.3a, §3.3b) ────────────────────────────────────
local loveCtl, stdCtl
local capturedSink            -- per-test print capture target

local function installDoubles()
  loveCtl = loveStubs.install()
  stdCtl  = stdDoubles.install(loveStubs.fs.store, function(t)
    if capturedSink then capturedSink(t) end
  end)
end

-- Load a user test file with doubles active and a clean require cache (§3.3b).
-- The test file's describe/it calls register into the tree.
function M.loadFile(path)
  curFile = path
  curFileLabel = path:match("([^/\\]+)$") or path
  -- clear any cached game modules so file-to-file state doesn't leak (§3.3b)
  -- (the bootstrap may also pass an explicit module list to fresh-require)
  local chunk, err = loadfile(path)
  if not chunk then
    -- a file that fails to LOAD becomes a synthetic error test (§B5)
    local id = (path:match("([^/\\]+)$") or path) .. " > <load error>"
    M.__loadErrors = M.__loadErrors or {}
    M.__loadErrors[#M.__loadErrors + 1] = { id = id, file = path, msg = err }
    return false, err
  end
  setfenv = setfenv  -- 5.1 has setfenv; keep test file in global env so it sees describe/it
  chunk()
  return true
end

-- clear a game module from the require cache so its state is fresh (§3.3b)
function M.freshRequire(name)
  package.loaded[name] = nil
  return require(name)
end

-- ── lifecycle executor (validated Phase 0) ───────────────────────────────────
local function lineage(scope)
  local chain, n = {}, scope
  while n do table.insert(chain, 1, n); n = n.parent end
  return chain
end

-- Assertion vs error distinction (§Phase D). luassert raises a plain string, so we
-- can't tell it apart from error("x") by type. Instead the facade-exposed `assert`
-- (see below) wraps luassert and re-raises failures tagged with this marker, making
-- detection exact and independent of message wording / language packs.
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
    -- a hook blowing up is an error, not an assertion failure
    return "error", "before_each: " .. errString(beforeErr)
  elseif bodyErr then
    -- failed = a clean assertion didn't hold; error = the test threw/crashed (§Phase D)
    return (bodyIsAssertion and "failed" or "error"), errString(bodyErr)
  else
    return "passed", ""
  end
end

-- mock-reset between tests: rebuild love doubles, restore real std libs, reset spies
local function resetBetweenTests()
  if loveCtl then loveCtl.reset() end
  if stdCtl  then stdCtl.reset() end
end

-- ── run ──────────────────────────────────────────────────────────────────────
-- collect tests in source-declaration order by walking the interleaved `seq`
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
  local realClock = os.clock  -- real timing for durations (framework side)

  local summary = { passed = 0, failed = 0, error = 0 }
  local tap = {}            -- accumulated TAP lines (emitted unprefixed at the end)
  local n = 0
  local function tapLine(status, name)
    n = n + 1
    local ok = (status == "passed") and "ok" or "not ok"
    local note = (status == "error") and " # error" or (status == "failed" and " # failed" or "")
    tap[#tap + 1] = string.format("%s %d - %s%s", ok, n, name, note)
  end

  -- Load errors happened before any test ran — emit them first (§B5, ordering).
  for _, le in ipairs(M.__loadErrors or {}) do
    emitTest({ id = le.id, name = "<load error>", status = "error",
               file = le.file, line = 0, ms = 0, msg = le.msg })
    summary.error = summary.error + 1
    tapLine("error", le.id)
  end

  local tests = {}
  collect(root, tests)

  for _, t in ipairs(tests) do
    if opts.filter == nil or t.id == opts.filter
       or (opts.suite and t.id:find(opts.suite, 1, true) == 1) then
      -- set up per-test print capture, tagged with this test id (§4.5)
      capturedSink = function(text) emitOut(t.id, text) end
      stdCtl.apply()

      local t0 = realClock()
      local status, msg = runOne(t)
      local ms = math.floor((realClock() - t0) * 1000)

      stdCtl.restoreReal()
      capturedSink = nil

      emitTest({ id = t.id, name = t.name, status = status,
                 file = t.file, line = t.line, ms = ms, msg = msg })
      summary[status] = (summary[status] or 0) + 1
      tapLine(status, t.id)

      resetBetweenTests()
    end
  end

  -- TAP summary → Console (unprefixed, §3.5). Plan header + body + plan count.
  cfg.emit("TAP version 13\n1.." .. n .. "\n")
  for _, line in ipairs(tap) do cfg.emit(line .. "\n") end
  cfg.emit(string.format("# passed %d  failed %d  error %d\n",
    summary.passed, summary.failed, summary.error))

  return summary
end

-- ── tagged assert wrapper ────────────────────────────────────────────────────
-- Wrap luassert so any failure it raises is prefixed with ASSERT_TAG, letting the
-- executor classify it as `failed` (assertion) vs `error` (thrown). The wrapper
-- mirrors luassert's call+index shape: `assert(cond)`, `assert.are.equal(a,b)`,
-- `assert.spy(s).was.called()` all still work; only the failure path is tagged.
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

local function wrapAssert(node)
  -- node is a luassert callable/table; return a proxy that tags failures and
  -- recursively wraps nested tables/callables (e.g. assert.are -> .equal).
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

-- ── public surface (facade) ──────────────────────────────────────────────────
M.assert = wrapAssert(assert_)
M.spy    = spy
M.stub   = stub
M.mock   = mock
-- AAA aliases over the same core
M.given  = M.describe
M.test   = M.it

-- Convenience: expose describe/it/etc. as globals so test files read cleanly.
function M.expose(env)
  env = env or _G
  env.describe    = M.describe
  env.it          = M.it
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
