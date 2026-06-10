-- Assertions: the common luassert checks, AND the pass/fail/error distinction.
-- This file DELIBERATELY contains one failing assertion and one thrown error so
-- the harness can confirm they're classified correctly.
-- Expected: 7 passed, 1 failed, 1 error.

describe("assertions", function()
  it("is_true / is_false", function()
    assert.is_true(true)
    assert.is_false(false)
  end)

  it("is_nil / is_not_nil", function()
    assert.is_nil(nil)
    assert.is_not_nil(0)
  end)

  it("are.equal (primitive ==)", function()
    assert.are.equal(42, 42)
    assert.are.equal("x", "x")
  end)

  it("are.same (deep table equality)", function()
    assert.are.same({ 1, 2, { a = 3 } }, { 1, 2, { a = 3 } })
  end)

  it("are_not.equal", function()
    assert.are_not.equal(1, 2)
  end)

  it("has_error (function must throw)", function()
    assert.has_error(function() error("boom") end)
  end)

  it("plain assert(truthy)", function()
    assert(1 == 1)
  end)

  -- DELIBERATE failure: a clean assertion that does not hold → status "failed".
  it("DELIBERATE FAIL: are.equal mismatch", function()
    assert.are.equal(1, 2)
  end)

  -- DELIBERATE error: the test throws (not an assertion) → status "error".
  it("DELIBERATE ERROR: raises", function()
    error("intentional crash")
  end)
end)
