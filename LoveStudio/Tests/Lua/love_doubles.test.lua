-- love.* doubles: modeled modules (filesystem/timer/graphics), the recursive
-- auto-spy (never crashes), the shared io <-> love.filesystem store, and the
-- love.<module>.real() opt-in.
-- Expected: 6 passed, 0 failed, 0 error.

describe("love doubles", function()
  it("auto-spies never crash on unmodeled calls", function()
    -- a chain of unknown love.* calls must not error and stays indexable/callable
    local w = love.graphics.newImage("nope.png"):getWidth()
    assert.is_not_nil(love.audio.newSource("x", "static"))
    assert.is_not_nil(w)
  end)

  it("love.timer is a controllable clock", function()
    local t0 = love.timer.getTime()
    assert.is_not_nil(t0)
  end)

  it("love.graphics.getWidth/Height return numbers", function()
    assert.is_true(type(love.graphics.getWidth()) == "number")
    assert.is_true(type(love.graphics.getHeight()) == "number")
  end)

  it("love.filesystem is an in-memory store", function()
    love.filesystem.write("save.dat", "hello")
    local data = love.filesystem.read("save.dat")
    assert.are.equal("hello", data)
  end)

  it("io and love.filesystem share one store", function()
    love.filesystem.write("shared.txt", "from-love")
    local f = io.open("shared.txt", "r")
    assert.is_not_nil(f)
    local contents = f:read("a")
    f:close()
    assert.are.equal("from-love", contents)
  end)

  it("love.<module>.real() opt-in is wired", function()
    -- real() must exist on a modeled module; calling it should not crash. (We don't
    -- assert real graphics behavior — no GPU here — only that the opt-in is wired.)
    assert.is_function(love.graphics.real)
    local ok = pcall(function() love.graphics.real() end)
    assert.is_true(ok)
  end)
end)
