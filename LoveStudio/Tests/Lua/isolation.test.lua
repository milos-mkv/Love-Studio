-- Isolation: state must not leak between tests. The love.filesystem store and the
-- deterministic clock reset between tests; required game modules are fresh per file.
-- Expected: 3 passed, 0 failed, 0 error.

describe("isolation", function()
  it("filesystem from a previous test does not leak (write here)", function()
    love.filesystem.write("leak-check.txt", "present")
    assert.are.equal("present", love.filesystem.read("leak-check.txt"))
  end)

  it("the file written in the previous test is gone", function()
    -- between tests the in-memory store is reset, so the prior write is not visible
    local data = love.filesystem.read("leak-check.txt")
    assert.is_nil(data)
  end)

  it("a fresh table is fresh each test", function()
    local t = {}
    assert.are.equal(0, #t)
  end)
end)
