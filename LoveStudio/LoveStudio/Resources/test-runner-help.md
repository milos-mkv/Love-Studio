# Writing Tests in LÖVE Studio

The Test Runner runs unit and integration tests for your LÖVE game's Lua code —
fast, headless, and deterministic. Your `love.*` calls are replaced with test
**doubles** so tests don't need a window, a GPU, or real files.

---

## A first test

Create a file matching one of your configured test globs (Settings → Runner →
Tests), e.g. `tests/player_test.lua`:

```lua
describe("Player", function()
  it("takes damage", function()
    local Player = require("game.player")
    local p = Player.new()
    p:takeDamage(30)
    assert.are.equal(70, p.hp)
  end)
end)
```

`describe`, `it`, `before_each`, `after_each`, `assert`, `spy`, `stub`, and `mock`
are all available globally — no `require` needed for them.

---

## Structure

```lua
describe("Inventory", function()
  local inv

  before_each(function()       -- runs before every `it` in this block
    inv = require("game.inventory").new()
  end)

  after_each(function()        -- runs after every `it`, even if it failed
    inv = nil
  end)

  it("starts empty", function()
    assert.are.equal(0, inv:count())
  end)

  describe("after adding an item", function()
    before_each(function() inv:add("sword") end)   -- nests with the outer hook

    it("has one item", function()
      assert.are.equal(1, inv:count())
    end)
  end)
end)
```

Hooks nest: outer `before_each` runs before inner, inner `after_each` before
outer. Tests run in the order written.

---

## Assertions

Assertions come from `luassert`:

```lua
assert.is_true(x)
assert.is_false(x)
assert.is_nil(x)
assert.is_not_nil(x)
assert.are.equal(expected, actual)        -- ==
assert.are.same(expected, actual)         -- deep table equality
assert.has_error(function() ... end)      -- the function must throw
```

A failed assertion marks the test **failed** (red ✗). A test that throws or
crashes is marked **error** (orange ⚠).

---

## Spies, stubs, and mocks

```lua
it("calls the callback", function()
  local cb = spy.new(function() end)
  doThing(cb)
  assert.spy(cb).was.called()
  assert.spy(cb).was.called_with(42)
end)

it("stubs a method", function()
  local s = stub(myObject, "save")   -- replaces save, records calls
  myObject:doWork()
  assert.stub(s).was.called()
  s:revert()
end)
```

---

## What `love.*` does in tests

By default every `love.*` call is a **double**:

- Common calls behave usefully — `love.filesystem` is an in-memory filesystem,
  `love.timer.getTime()` is a controllable clock, `love.graphics.getWidth()`
  returns a fixed size.
- Everything else is an **auto-spy**: it never crashes, records that it was
  called, and returns a value you can keep calling/indexing. So
  `love.graphics.newImage("x"):getWidth()` is always safe in a test.

`love.filesystem` and `io` share one in-memory store, so a test can write with one
and read with the other.

### Testing the real API

If a test needs the genuine LÖVE module, opt in for that module:

```lua
it("uses real graphics", function()
  love.graphics.real()                       -- this test uses the real love.graphics
  local img = love.graphics.newImage("assets/p.png")
  -- ...
end)
```

The double is restored automatically for the next test. Real-module tests are less
deterministic and may need a graphics context — use them only where the double
isn't enough.

---

## Tips

- **Test plain modules, not callbacks.** Logic inside `love.load`/`love.update`/
  `love.draw` can't be called directly. Put testable logic in plain modules that
  `return` something, and call those from your callbacks.
- **Isolation is automatic.** Each test file gets a fresh copy of your modules, so
  state from one test doesn't leak into the next.
- **`print` output** from a test appears in the Console, tagged to that test.
- **Click a failure** in the Test Explorer to jump to the line.

---

## Coverage

Enable **Settings → Runner → Tests → Enable code coverage** to see an overall
coverage percentage in the Test panel after a run. Click the percentage to open
the full per-file report.
