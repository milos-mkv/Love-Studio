-- Structure: describe/it, nesting, and the given/test aliases.
-- Expected: 5 passed, 0 failed, 0 error.

describe("outer suite", function()
  it("runs a top-level test", function()
    assert.is_true(true)
  end)

  describe("nested suite", function()
    it("runs a nested test", function()
      assert.are.equal(2, 1 + 1)
    end)

    describe("deeply nested", function()
      it("runs a deeply nested test", function()
        assert.are.equal("ab", "a" .. "b")
      end)
    end)
  end)
end)

-- AAA aliases: given == describe, test == it
given("a context (given alias)", function()
  test("works like it (test alias)", function()
    assert.is_not_nil({})
  end)

  test("also runs", function()
    assert.is_false(false)
  end)
end)
