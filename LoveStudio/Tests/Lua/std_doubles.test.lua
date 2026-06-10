-- Standard-library doubles: deterministic os/io/math.random, and os.exit disabled.
-- Expected: 5 passed, 0 failed, 0 error.

describe("std doubles", function()
  it("math.random is deterministic", function()
    -- the double returns fixed values, so repeated calls agree
    local a = math.random()
    local b = math.random()
    assert.are.equal(a, b)
    -- ranged form is also deterministic
    assert.are.equal(math.random(1, 10), math.random(1, 10))
  end)

  it("math still has the real helpers", function()
    assert.are.equal(2, math.floor(2.9))
    assert.are.equal(3, math.max(1, 3, 2))
  end)

  it("os.time / os.clock are a fixed clock", function()
    assert.are.equal(os.time(), os.time())
    assert.is_true(type(os.clock()) == "number")
  end)

  it("os.exit is disabled (raises instead of killing the process)", function()
    assert.has_error(function() os.exit(0) end)
  end)

  it("io writes/reads through the in-memory store", function()
    local f = io.open("std.txt", "w")
    f:write("line1\n"); f:write("line2\n"); f:close()
    local r = io.open("std.txt", "r")
    assert.are.equal("line1", r:read("l"))
    assert.are.equal("line2", r:read("l"))
    r:close()
  end)
end)
