# Test Runner — TestKit Reference

The Test Runner executes unit and integration tests for your LÖVE game's Lua code
**headless** (no window or GPU), **deterministically**, and in **isolation**. To
achieve this, `love.*` and a few standard-library calls run against test **doubles**
by default — see *What `love.*` does in tests* below for how that works and how to
opt back into the real modules when you need them.

---

## What kind of tests can I write?

Tests are usually grouped into three levels, by how much of the game they exercise
at once:

- **Unit test** — checks one small piece in isolation: a single function or module.
  *Example: "a player with 100 health who takes 30 damage has 70 health left."*
  Fast and precise; most of your tests should be these.
- **Integration test** — checks that a few pieces work together correctly.
  *Example: "adding an item to the inventory updates the player's carry weight."*
- **End-to-end (e2e) test** — runs the whole game as a player would: the real
  window, the game loop, rendering, and input, driven frame by frame.
  *Example: "pressing Space on the title screen starts a new game."*

**TestKit covers unit tests and most integration tests.** That's the sweet spot for
game *logic* — rules, state, math, systems — which is where most bugs live and where
fast, repeatable tests pay off the most. (Integration scenarios that depend on real
rendering, input, or the running game loop fall into e2e — see below.)

**e2e is its own kind of testing.** Things that need the live game loop —
`love.draw` output, or "what happens when I press a key" — are the domain of e2e,
which needs the real engine running and a different kind of harness. The good news:
a simple pattern gets you most of the way there today. Keep your game *logic* in
plain modules and your `love.*` callbacks thin, and the vast majority of your game
becomes unit- and integration-testable right now — which is also just cleaner, more
maintainable code.

---

## What's inside TestKit

TestKit bundles a few well-known pure-Lua libraries behind one facade so you only
ever write `describe` / `it` / `assert`. The exact versions are vendored (pinned)
for reproducibility:

| Library  | Version | What it provides                                          | Docs |
|----------|---------|-----------------------------------------------------------|------|
| LuaUnit  | 3.5     | Runs the tests and decides pass / fail / error.           | [docs](https://luaunit.readthedocs.io) |
| luassert | 1.9.0   | The `assert.*` checks and the `spy` / `stub` / `mock` tools. | [docs](https://github.com/lunarmodules/luassert) |
| say      | 1.4.1   | Formats luassert's failure messages (used by luassert).   | [docs](https://github.com/lunarmodules/say) |
| LuaCov   | 0.17.0  | Measures which lines ran, for the coverage report.        | [docs](https://lunarmodules.github.io/luacov/) |

On top of those, TestKit adds its own hand-written pieces:

| Component     | What it provides                                                  |
|---------------|------------------------------------------------------------------|
| lovetest      | The facade you write against: `describe` / `it`, the lifecycle hooks, the tagged `assert`, and test discovery. |
| love doubles  | Safe stand-ins for the `love.*` modules, so tests run with no window or GPU. |
| std doubles   | Controlled `os` / `io` / `math.random` / `print`, so tests stay deterministic. |

You don't `require` any of these — the runner injects the API as globals.

---

## A first test

A test is just a small piece of code that checks your game code does what you
expect. You give it some input, run your function, and state what the answer
*should* be. If it matches, the test passes (green ✓); if not, it fails (red ✗) and
shows you what went wrong.

Here's a complete one. It checks that a player with 100 HP has 70 left after taking
30 damage:

```lua
describe("Player", function()        -- a group of related tests
  it("takes damage", function()      -- one test, named in plain English
    local Player = require("game.player")   -- load the code you're testing
    local p = Player.new()

    p:takeDamage(30)                        -- do the thing

    assert.are.equal(70, p.hp)              -- check the result: hp should be 70
  end)
end)
```

That's the whole pattern: **`describe`** names a group, **`it`** is a single test,
and **`assert`** states what you expect. Everything you need — `describe`, `it`,
`assert`, and the rest below — is available automatically; you never `require` the
test tools themselves.

### The fastest way to start

You don't have to memorize the shape. Open the **Snippets** panel (bottom of the
window) and look under **testing** — there are ready-made starting points:

- **Minimal Test File** — the smallest possible test, to fill in.
- **Full Test File** — shows every setup/cleanup hook with comments.
- **Test Using love.\* Doubles** — for code that calls `love.*`.

Insert one, save it under your tests folder (e.g. `tests/player.test.lua`), and it
shows up in the Test panel ready to run.

**A note on naming.** You may see `given` and `test` in other people's tests —
they're just other names for `describe` and `it` and behave identically. So this:

```lua
given("a fresh player", function()
  test("starts at full hp", function()
    assert.are.equal(100, Player.new().hp)
  end)
end)
```

does exactly the same thing as the `describe` / `it` version above. Use whichever
reads better to you.

---

## Structure & lifecycle hooks

```lua
describe("Inventory", function()
  local inv

  -- runs ONCE, before the first test in this suite
  setup(function()
    -- expensive one-time prep shared by every test (e.g. load a fixture)
  end)

  -- runs ONCE, after the last test in this suite
  teardown(function()
    -- release whatever setup() created
  end)

  -- runs before EVERY test — use it to build fresh state
  before_each(function()
    inv = require("game.inventory").new()
  end)

  -- runs after EVERY test, even if it failed
  after_each(function()
    inv = nil
  end)

  it("starts empty", function()
    assert.are.equal(0, inv:count())
  end)

  -- describes can nest; the inner before_each runs after the outer one
  describe("after adding an item", function()
    before_each(function() inv:add("sword") end)

    it("has one item", function()
      assert.are.equal(1, inv:count())
    end)
  end)
end)
```

- **`setup` / `teardown`** run once per `describe`, around the whole suite.
- **`before_each` / `after_each`** run around every `it`.
- **Hooks nest:** outer `before_each` runs before inner; inner `after_each` before
  outer. Tests run in the order written.

---

## Assertions

From luassert (wrapped so failures are reported precisely):

```lua
assert(value)                             -- truthy
assert.is_true(x)        assert.is_false(x)
assert.is_nil(x)         assert.is_not_nil(x)
assert.are.equal(a, b)                    -- == (identity / primitive equality)
assert.are.same(a, b)                     -- deep table equality
assert.are_not.equal(a, b)
assert.has_error(function() ... end)      -- the function must throw
```

- A **failed assertion** marks the test **failed** (red ✗).
- A test that **throws / crashes** is marked **error** (orange ⚠) — distinct from a
  failed assertion.

---

## Test doubles (spies, stubs, mocks)

*New to testing? You can skip this section for now — come back when a plain
`assert` isn't enough.*

Think of **test doubles** like stunt doubles in movies: they stand in for the
complex or awkward parts of your system, so you can test how the rest of your game
performs without those parts actually running. Instead of really saving a file,
hitting the network, or playing a sound during a test, you swap in a stand-in — then
check how your code used it.

Three kinds, from lightest to heaviest:

- **spy** — *watches* a function (the real one still runs), so you can ask how it
  was called.
- **stub** — *replaces* a function so it does nothing, so the real side effect
  never happens — and you can still check it was called.
- **mock** — applies a spy (or, with `mock(t, true)`, a stub) to *every* function on
  a table at once.

### Spy — watch a function

A **spy** wraps a function so you can later ask: *was it called? how many times?
with what arguments?* The real function still runs.

```lua
it("calls the callback when done", function()
  local onDone = spy.new(function() end)   -- a stand-in function we can watch

  doWork(onDone)                            -- run your code, passing the spy in

  assert.spy(onDone).was.called()           -- it was called at least once
  assert.spy(onDone).was.called(1)          -- exactly once
  assert.spy(onDone).was.called_with(42)    -- and with the argument 42
end)
```

### Stub — replace a function so it does nothing

A **stub** is like a spy, but it **replaces** a real method so it *doesn't* run —
handy when the real one is slow, hits the disk/network, or you just want to confirm
it was called without side effects.

```lua
it("saves the game after a checkpoint", function()
  local s = stub(saveSystem, "save")   -- replace save() — it won't actually save

  reachCheckpoint()

  assert.stub(s).was.called()          -- but we can confirm it WAS asked to save
  s:revert()                           -- put the real save() back
end)
```

### Mock — spy on (or stub) a whole table at once

A **mock** applies spies or stubs to *every* function on a table in one step —
useful when a module has several methods you want to watch or neutralize together.
By default it uses **spies** (the real functions still run); pass `true` as the
second argument to use **stubs** (the real functions are replaced and do nothing):

```lua
it("sends a ping over the network", function()
  local net = mock(require("game.net"), true)  -- true → stub every function

  net.send("ping")                             -- the stub runs; nothing is really sent

  assert.stub(net.send).was.called_with("ping")
  mock.revert(net)                             -- restore the real module
end)
```

Leave off the `true` (`mock(require("game.net"))`) and you get spies instead — the
real functions run, but you can still check how they were called with `assert.spy`.

These come from luassert; `spy`, `stub`, and `mock` are available globally in tests.

---

## What `love.*` does in tests

By default every `love.*` call is a **double**:

- **Common calls behave usefully.** `love.filesystem` is an in-memory filesystem,
  `love.timer.getTime()` is a controllable clock, `love.graphics.getWidth()`
  returns a fixed size, `love.math.random` is deterministic.
- **Everything else is an auto-spy.** It never crashes, records that it was called,
  and returns a value you can keep calling and indexing — so
  `love.graphics.newImage("x"):getWidth()` is always safe.

`love.filesystem` and `io` share **one** in-memory store, so a test can write with
one and read with the other.

### Using the real module

If a test genuinely needs a real LÖVE subsystem, opt in for that module:

```lua
it("uses real graphics", function()
  love.graphics.real()                    -- this test uses the genuine love.graphics
  local img = love.graphics.newImage("assets/p.png")
  -- ...
end)
```

The double is restored automatically for the next test. Real-module tests are less
deterministic and may need a graphics context — use them only where the double
isn't enough.

---

## Standard library in tests

A non-deterministic standard-library call — the wall clock, real disk I/O, the
random generator — would make a test's result depend on *when* and *where* it runs.
To prevent that, the runner substitutes deterministic doubles for the following
while a test executes. Unlike the `love.*` modules, these have **no per-test
opt-out**; they are controlled by the framework so that a given test always
produces the same result.

- **`os.time` / `os.clock` / `os.date`** — a fixed, controllable clock; no real
  time passes during a test.
- **`os.exit`** — disabled; raises an error so a test cannot kill the runner.
- **`os.getenv`** — returns `nil`, so no ambient environment leaks into tests.
- **`io.*`** (`open`, `lines`, …) — the same in-memory filesystem as
  `love.filesystem`.
- **`math.random`** — deterministic; fixed values rather than real randomness.
- **`print`** — routed to the Console, tagged to the current test.

Because `io.*` and `love.filesystem` share one in-memory store, a fixture written
through either is readable through the other.

---

## Debugging a test

Set a breakpoint (click the gutter) in a **test** or in the **game code it calls**,
then click the 🐞 next to a test in the Test Explorer. Execution pauses at the
breakpoint with the call stack and variables in the Debug panel — step / continue
as usual. Running a test in debug mode focuses the Debug panel; a normal run
focuses the Console.

---

## Coverage

Enable **Settings → Runner → Tests → Enable code coverage** to measure line
coverage on a full run (LuaCov). The Test panel header shows an overall
**Coverage %** pill — click it for the per-file / per-function report (file and
function names are links that jump to the source). Coverage runs on **Run All**
only, not single-test runs.

---

## Tips

- **Test plain modules, not callbacks.** The test runner runs your tests and then
  exits immediately — it never starts LÖVE's game loop, so `love.update` /
  `love.draw` are never called during a test. (And even if they were, they return
  nothing to check; they just change state.) So put your real logic in plain modules
  that take inputs and `return` results, then call those modules from your
  callbacks. The modules are easy to test; the callbacks stay thin.
- **Isolation is automatic.** Each test gets fresh module state (a clean `require`
  cache), so one test can't leak into the next.
- **`print` output** from a test appears in the Console, tagged to that test.
- **Click a failure** in the Test Explorer to jump to its line.
- **File naming.** Match your configured globs (e.g. `*.test.lua` under `tests/`).
  The Explorer re-discovers automatically when you add or edit a test file.
