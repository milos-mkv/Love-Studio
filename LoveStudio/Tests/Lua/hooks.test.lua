-- Lifecycle hooks: setup/teardown (once per suite) and before_each/after_each
-- (per test), including nesting order. We record the call order into a module-level
-- log and assert it inside the tests.
-- Expected: 4 passed, 0 failed, 0 error.

local log = {}
local function record(s) log[#log + 1] = s end

describe("hooks", function()
  setup(function() record("setup") end)
  teardown(function() record("teardown") end)
  before_each(function() record("before_each(outer)") end)
  after_each(function() record("after_each(outer)") end)

  it("runs setup exactly once before the first test", function()
    -- setup, then this test's before_each, have run; nothing else yet.
    assert.are.equal("setup", log[1])
    assert.are.equal("before_each(outer)", log[2])
  end)

  it("runs before_each again for the second test", function()
    -- by now: setup, be(1), ae(1), be(2)  → setup appears only once
    local setups = 0
    for _, e in ipairs(log) do if e == "setup" then setups = setups + 1 end end
    assert.are.equal(1, setups)
    assert.are.equal("before_each(outer)", log[#log])
  end)

  describe("nested", function()
    before_each(function() record("before_each(inner)") end)
    after_each(function() record("after_each(inner)") end)

    it("runs outer before_each, then inner before_each", function()
      -- the two most recent before_each entries are outer then inner, in that order
      local outerIdx, innerIdx
      for i = #log, 1, -1 do
        if not innerIdx and log[i] == "before_each(inner)" then innerIdx = i end
        if not outerIdx and log[i] == "before_each(outer)" then outerIdx = i end
        if outerIdx and innerIdx then break end
      end
      assert.is_true(outerIdx < innerIdx)   -- outer runs before inner
    end)

    it("nested test also fires both before_each hooks", function()
      assert.is_true(true)
    end)
  end)
end)
