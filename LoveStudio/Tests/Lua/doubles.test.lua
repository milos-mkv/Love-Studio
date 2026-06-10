-- Test doubles: spy, stub, mock (from luassert).
-- Expected: 5 passed, 0 failed, 0 error.

describe("spy", function()
  it("records calls and arguments", function()
    local cb = spy.new(function() end)
    cb(42)
    cb(43)
    assert.spy(cb).was.called()
    assert.spy(cb).was.called(2)
    assert.spy(cb).was.called_with(42)
  end)

  it("lets the real function still run", function()
    local hit = false
    local s = spy.new(function() hit = true end)
    s()
    assert.is_true(hit)
  end)
end)

describe("stub", function()
  it("replaces a method and records the call", function()
    local obj = { save = function() error("real save must not run") end }
    local s = stub(obj, "save")
    obj.save()                       -- the stub runs instead of the real save
    assert.stub(s).was.called()
    s:revert()
    assert.is_function(obj.save)
  end)
end)

describe("mock", function()
  it("mock(t, true) stubs every function (real does NOT run)", function()
    local mod = { send = function() error("no") end, recv = function() error("no") end }
    local m = mock(mod, true)           -- true = stub (replace); without it, spies
    m.send("ping")                      -- the stub runs, so error("no") never fires
    assert.stub(m.send).was.called_with("ping")
    mock.revert(m)
  end)

  it("mock(t) spies — the real function still runs", function()
    local ran = false
    local mod = { f = function() ran = true return "real" end }
    local m = mock(mod)                 -- no second arg → spy (real runs)
    local result = m.f()
    assert.is_true(ran)
    assert.are.equal("real", result)
    assert.spy(m.f).was.called()
    mock.revert(m)
  end)

  it("revert restores the originals", function()
    local mod = { f = function() return "real" end }
    local m = mock(mod, true)
    mock.revert(m)
    assert.are.equal("real", mod.f())
  end)
end)
