# Test Runner — Implementation Plan

A plan for adding a **Test Runner** feature to LÖVE Studio: a VS Code–style Test
Explorer in the sidebar that discovers, runs, and reports on unit tests for the
user's LÖVE2D game code.

This document is the blueprint. It records the decisions we made, the rationale
behind them, and a file-by-file build order. All decisions are settled (§8).

---

## 1. Goal

Let a user developing a LÖVE2D game in LÖVE Studio write and run **unit and
integration tests for their own Lua game code** from inside the IDE, with a visual
Test Explorer (tree of suites/tests, pass/fail status, click-to-source) modeled on
VS Code's Test Explorer.

### Test-level scope

This design's headless-with-doubles model (§5.1, §3.3a) covers:

- **Unit tests** — a module in isolation, with `love.*` and the standard library
  doubled. Deterministic, fast.
- **Integration tests** — several modules together, still headless; a test may
  opt into real `os`/`io` per case (§3.3a) where needed.

**End-to-end (e2e) is explicitly NOT covered by v1 — and cannot be done headless.**
E2e means exercising the *real* game through the *real* engine: actual
`love.graphics` rendering, real input, the real frame loop, real audio/window. By
definition those are exactly what our doubles replace — you cannot e2e-test a LÖVE
game without LÖVE, because the engine *is* the system under test, not a fakeable
dependency. E2e therefore requires the **real `love` runtime** (Path 2 in §5.1):
launch the actual game via the `love`-launch machinery `LoveRunner` already has,
drive it with scripted input, and assert on real frames/state — essentially what
LÖVE's own official `testing/` suite does (coroutine-per-test, `waitFrames`, real
graphics capture). This is a **separate harness and a future phase**, not v1. The
architecture reserves Path 2 for it; see §9.

Out of scope for v1: e2e / real-engine tests (future, §9); testing LÖVE Studio's
own Swift code; performance/benchmark tests; CI integration.

---

## 2. The core constraint

LÖVE game code calls `love.*` APIs (`love.graphics`, `love.audio`,
`love.filesystem`, `love.math`, …) that only exist at runtime inside the `love`
binary. Any test that touches those APIs must either:

- run with those APIs **faked** (headless, deterministic), or
- run **inside real `love`** (integration, real GPU/filesystem).

This single fact drove every framework and execution decision below.

**Resolved (§5.1):** v1 runs tests **without `love`, using doubles** — plain
LuaJIT with a fake `love` table. Deterministic, no window, no embedding risk.

---

## 3. Decisions (settled)

### 3.1 Test framework: LuaUnit

**LuaUnit** is the engine (discovery + run + text output). It is a single
pure-Lua file, dependency-free, supports Lua 5.1 / LuaJIT, and embeds cleanly —
no CLI bootstrapping, no `os`/`io`/`debug` reliance, nothing that fights LÖVE's
LuaJIT environment.

### 3.2 Mocking: luassert (standalone)

`luassert` provides `spy` / `stub` / `mock` and works **standalone** — pure Lua
with a single tiny dependency (`say`). It supports Lua 5.1 / LuaJIT and provides
`spy.on`, `stub`, `mock`, and `assert.spy(s).was.called_with(...)` with pluggable
argument matchers.

**We do not hand-write a mocking library** — we vendor luassert + say.

### 3.3 The four-layer Lua stack

```
┌─────────────────────────────────────────────────────────┐
│  Facade (layer 4)        one `require` → describe/it,    │  ← we write
│                          before_each/after_each, assert,  │     (thin)
│                          spy/stub/mock, love stubs,       │
│                          AAA + BDD entry points           │
├─────────────────────────────────────────────────────────┤
│  LÖVE stubs (layer 3)    fakes/spies for love.* (§5.2)    │  ← we write
├─────────────────────────────────────────────────────────┤
│  Mocking (layer 2)       luassert spy/stub/mock + say     │  ← vendored
├─────────────────────────────────────────────────────────┤
│  Engine (layer 1)        LuaUnit: discover, run, output   │  ← vendored
└─────────────────────────────────────────────────────────┘
```

**Layer 4 is a facade, not a re-abstraction.** Its real substance is:

1. A single namespace — one `require` exposes everything.
2. Normalizing the assertion surface (LuaUnit stays the runner; the user never
   sees `luaunit.assertEquals` — assertions route through one consistent style,
   leaning on luassert's).
3. A `describe`/`it`/`before_each`/`after_each` executor over LuaUnit (a scope
   stack).
4. **Lifecycle ⇄ mock-reset coordination**: `before_each`/`after_each` must also
   auto-restore luassert stubs/spies and reset the love-stub state between tests.
   The **nested-lifecycle executor** (outer→inner before, inner→outer after,
   `after_each` still running on body-throw, partial teardown when `before_each`
   throws) was **prototyped and validated** before committing — all four cases
   passed. `lovetest.lua` implements it (adding mock-reset + the wire-format emit)
   and is exercised under headless `love` early in Phase A.
5. Both AAA (`arrange`/`act`/`assert`) and BDD (`describe`/`it`) entry points
   over the same core.

Everywhere else the facade is **pass-through** to the vendored libs. A facade fn
that is `return luassert.spy(...)` is good; one that reimplements `luassert.spy`
is the trap to avoid.

### 3.3a Standard-library doubles (`os` / `io` / `debug` / …)

Since tests run headless in plain LuaJIT, the user's game code would otherwise see
the **full** standard library — more permissive than LÖVE production (which
sandboxes parts of it) and non-deterministic (`os.time`, `math.random`, real
`io`). So we **double the standard library for user code**, the same way we double
`love.*` — as part of layer 3.

**Decision: deterministic fakes for user code, with per-test opt-in/out.**

The doubled globals (defaults):

| Global | Doubled behavior for user code |
| ------ | ------------------------------ |
| `os.time` / `os.date` / `os.clock` | controllable fake clock (advance manually); deterministic |
| `os.exit` | **stubbed** — a test must never kill the process |
| `os.getenv` | returns controlled/empty values |
| `io.*` (open/read/write/lines) | in-memory filesystem, spy-able — **shared store with `love.filesystem`** (see below) |
| `math.random` / `randomseed` | seeded for determinism |
| `print` | routed to captured output |
| `require` / `package.path` | resolves the vendored kit + the user's game modules |

**Critical subtlety — double what *user code* sees, not the framework.** LuaUnit
and luassert legitimately need the *real* `os`/`io`/`debug`:

- LuaUnit uses real `os.time`/`os.clock` for its own **test-duration timing**.
- The runner writes structured result lines + TAP via real `print`/`io.write`
  (**this output channel must stay real**).
- LuaUnit/luassert use real `debug.traceback` / `debug.getinfo` for **failure
  locations and stack traces** — so `debug` stays real (doubling it naively breaks
  error reporting).

So this is a **per-symbol policy at the user-code boundary**, not a blanket global
swap: the facade installs the fakes around the user's module-under-test and the
framework retains the real libs it depends on.

**Per-test opt-in/out:** the facade exposes a way for an individual test to
relax the sandbox (use real `os`/`io` for an integration-style test) or tighten it,
rather than one fixed global policy. Defaults are the deterministic fakes above;
a test can override per case.

**One in-memory filesystem behind two API surfaces.** `std_doubles.lua`'s `io.*`
and `love_stubs.lua`'s `love.filesystem.*` (modeled in the common subset, §5.2)
**share a single backing store** (`path → bytes`) — not two independent ones. They
remain distinct *API surfaces* (different signatures, different path semantics)
over one store, so a test that writes via `love.filesystem.write` and reads back
via `io.open` (a plausible cross-API integration case, which v1 scope includes)
sees its own data instead of silently reading nil. The lifecycle hook that resets
spies between tests (§3.3, point 4) also clears this store, so state doesn't leak
across tests. **Path-normalization is the one real design point:**
`love.filesystem` is PhysFS (virtual root, sandboxed, no OS-absolute paths) while
`io` takes real OS-style paths — so normalize both to a single canonical key form
on the way into the store rather than storing two path conventions. Pick the
canonical key form when building the doubles (Phase A); the rest is plumbing.

### 3.3b The user-code boundary (how game code loads + isolation)

How a test reaches the user's game code — **prototyped and validated** against a
realistic game module before committing; all checks passed.

- **Load order.** The runner installs the `love` + std doubles **before** any game
  code is required, so a module that calls `love.*` *at require-time*
  (`local img = love.graphics.newImage(...)` at file top level — common in real
  games) loads without crashing: the auto-spy proxy (§5.2) absorbs the call.
- **`require`-path.** `package.path` is set to the project root so the game's own
  `require("src.foo")` conventions resolve; test files `require("lovetest")` for
  the facade and `require(<module-under-test>)` for the code they test.
- **Module-not-callback constraint (document for users).** Logic living *inside*
  `love.load`/`love.update`/`love.draw` isn't directly callable without a `love`
  loop. **Testable code must live in plain modules** that return something a test
  can `require`. This is a real constraint we impose on the user — it belongs in
  `test-runner-help.md` (§3.8), not just here.
- **`require`-cache isolation (critical — new rule).** Lua caches modules in
  `package.loaded`, so a module's top-level/mutable state **persists across tests**
  by default — test A mutating a game module leaks into test B. The facade must
  **clear `package.loaded[<game module>]` between test files** (a `freshRequire`)
  so each file gets a clean module instance. **This is NOT covered by the
  lifecycle mock-reset (§3.3, point 4)** — that resets spies, not the `require`
  cache. The validation's control case confirmed plain `require` shares state; the
  `freshRequire` path resets it. Decide the granularity in Phase A: reset
  per-file (safe default) vs per-test (stricter, slower).

### 3.4 Vendoring

The Lua libraries (LuaUnit, luassert, `say`, the love stubs, the facade) are
**vendored into this repo manually** and **bundled into the app build** — placed
under `Resources/` alongside the existing
[`mobdebug.lua`](../LoveStudio/LoveStudio/Resources/mobdebug.lua). They are NOT
downloaded by the running app.

At test time they are **injected into the project and cleaned up afterward**,
reusing the exact pattern the debugger already implements in
[`LoveRunner.buildDebugLauncher` / `cleanupDebugTempDir`](../LoveStudio/LoveStudio/Services/LoveRunner.swift)
(see lines ~313–398). Copy the kit in, run, restore/remove. The project stays
clean.

### 3.5 Output: structured lines drive the UI; TAP is a console summary

The Test Explorer is a **visual** tree, so the data feeding it must be
**structured**, not scraped from human text. Therefore:

- The **facade emits one structured result line per test** (sentinel-prefixed):

  ```
  [[LS_TEST]]{id=…,name=…,status=…,file=…,line=…,ms=…,msg=…}
  ```

  The `id` field is **mandatory** and is the stable path-based ID (§4.4) Swift
  correlates on — *not* `name`. This is the same structured-line technique the
  debugger's value inspector already uses in
  [`DebugValueInspector`](../LoveStudio/LoveStudio/Views/Debug/DebugPanelView.swift)
  (~line 293). Swift parses these into `TestNode`s that drive the tree. **This is
  the UI's data source.**
- **Captured user output gets its own sentinel:**

  ```
  [[LS_OUT]]{id=…,text=…}
  ```

  User `print`/stdout produced while a test runs (§4.5) is emitted as `[[LS_OUT]]`
  lines tagged with the running test's `id`, **not** left as bare text on the
  pipe. This lets the Swift parser **demux the shared stdout by prefix**:
  `[[LS_TEST]]` → result, `[[LS_OUT]]` → captured output, **anything else → TAP**.
  Without distinct prefixes the parser cannot tell captured `print` from TAP from
  a stray double's output.
- **TAP** (LuaUnit's built-in format) is emitted **additionally** at the end of a
  run into the existing **Console** tab as a human-readable, copy-pasteable
  summary. It is *not* the UI data source — it's a secondary textual artifact.

Line kinds, demuxed by prefix: `[[LS_TEST]]` → Explorer; `[[LS_OUT]]` →
Console (per-test); `[[LS_COV]]{pct=…}` → coverage % in the Explorer header
(§3.9); unprefixed TAP → Console (run summary).

> **Contract freeze (build order):** these exact field names are the Lua↔Swift
> wire format. Lock the field list **before Phase C** — both the Lua emitter
> (`lovetest.lua`, Phase A) and the Swift parser (`TestRunner`, Phase C) build
> against it byte-for-byte. `TestNode`'s fields (Phase B) must be expressible in
> the `[[LS_TEST]]` line; co-design B and this format rather than letting Phase A
> fix it unilaterally.

### 3.6 UI placement: a 5th sidebar tab

The Test Explorer is a **tall, narrow tree**, which fits the **left sidebar**, not
the short-and-wide bottom panel. We add a fifth tab to the existing horizontal
[`SidebarTab`](../LoveStudio/LoveStudio/Views/Studio/StudioView.swift) row
(`files, assets, find, docs` → add `tests`), with the **`flask.fill` SF Symbol**
and title "Tests". We keep the existing row layout (icon + label, equal-width
columns) — five fit in the 200pt sidebar.

**Icon: SF Symbol `flask.fill`** — no custom SVG needed. `flask.fill` is a
built-in SF Symbol (matches VS Code's Test Explorer metaphor) and is consistent
with the other sidebar tabs, which all use SF Symbols
([`SidebarTab.icon`](../LoveStudio/LoveStudio/Views/Studio/StudioView.swift)).
(A custom SVG in the [`Resources/FileIcons/`](../LoveStudio/LoveStudio/Resources/FileIcons/)
style was considered for brand consistency but is unnecessary.)

(Considered and not taken for v1: an icon-only tab row, or a separate VS
Code–style vertical activity bar. Either remains a future option if the row gets
crowded.)

### 3.7 Settings

Settings, **global**, stored via `@AppStorage` like every other setting, and
placed **under the existing Runner tab** in
[`SettingsView`](../LoveStudio/LoveStudio/Views/Settings/SettingsView.swift)
(`RunnerSettingsView`) as a new "Tests" section — not a new settings tab.

1. **Enable Test Runner** — a single `Toggle`, exactly like "Enable hot reload",
   keyed `@AppStorage("testRunnerEnabled")` (default `true`). When off, the 5th
   sidebar tab (§3.6) and the Run-Tests toolbar button are hidden.

2. **Test folders + globs** — a **list of `folder | glob` rows**. Each row pairs
   a folder (the search root, relative to the project root) with one glob applied
   beneath it. The runner uses whatever glob the user supplies — there is **no
   built-in naming convention**; the glob alone decides what matches (e.g. `**`
   for any depth).

   - **One glob per row.** To match two patterns in the same folder, add two rows.
     This keeps the model a flat two-column table matching the `folder | glob`
     notation.
   - **Storage:** the array of `{folder, glob}` rows is **JSON-encoded into one
     `@AppStorage` string** (stays in the established `@AppStorage` world; no new
     persistence machinery, since `@AppStorage` doesn't hold arrays directly).
   - **UI:** an editable two-column list (folder + glob) inside the Runner form;
     each folder has a "Choose…" picker / path field; add/remove rows.
   - **Scope: global** — the same rows apply to every project (per-project override
     is a possible future addition, not v1).
   - **Discovery semantics (§4.1/§5.3):** for each row, search *that folder* for
     files matching *that row's* glob. A glob matches only within its paired
     folder — not project-wide.

3. **Test timeout** — `@AppStorage("testRunnerTimeout")`, the max seconds a run
   may take before it is killed (§4.3). A `Stepper`/`Slider` like the existing
   runner controls; default e.g. 30 s. Bounds the infinite-loop case.

4. **Enable code coverage** — `@AppStorage("testRunnerCoverage")`, its **own,
   independent** toggle (§3.9). Separate from "Enable Test Runner" (#1): the Test
   panel can be on while coverage is off. When off, LuaCov's `runner.init()` is not
   called (no line-hook overhead) and no `[[LS_COV]]` line is emitted, so the
   header shows no %. Gating hierarchy: #1 gates the whole feature; #4 gates *only*
   coverage within it. (Default: off — coverage adds run overhead, so opt-in.)

v1 ships code coverage, scoped minimally: **show the overall coverage percentage
in the Test panel** (in/near the Explorer header summary, alongside the
pass/fail/duration counts), and **clicking the % opens the full coverage report as
a read-only tab**. No editor gutter coloring for v1 — that's future (TODO).

**Gated by its own setting.** Coverage has a dedicated toggle
`@AppStorage("testRunnerCoverage")` (§3.7 #4), independent of the Test Runner
enable toggle. Off by default (it adds run overhead). When off, the bootstrap skips
`runner.init()` entirely and emits no `[[LS_COV]]` line; the header simply shows no
%.

**Mechanism: vendor LuaCov.** Facts below are from the LuaCov docs
([`/lunarmodules/luacov`](https://github.com/lunarmodules/luacov)), not memory:

- **Same family, same vendoring model.** LuaCov is from `lunarmodules` (like
  luassert/say), pure Lua — drops into `Resources/testkit/` and bundles/injects
  exactly like the rest of the kit.
- **Programmatic start.** Call `require("luacov.runner").init(config)` from our
  test bootstrap (we own it) — no CLI `lua -lluacov` needed.
- **LuaJIT is supported** (the docs reference LuaJIT's single global debug hook
  directly). It rides `debug.sethook` line hooks — so `debug` must be **real**
  during the run (consistent with §3.3a keeping `debug` real for the framework).
  The residual concern is *performance* (line hooks force the JIT to the
  interpreter), **not correctness**; `runner.pause()/resume()` and the optional
  `cluacov` C-hook exist if it bites.
- **Filter to user code via config.** `include`/`exclude`/`modules` patterns in
  the config (a `.luacov` table) — set `exclude` to drop our kit, luassert, and
  the love/std doubles so the % reflects the **user's** source only.
- **Don't hand-divide the stats.** `luacov.stats.load()` gives per-file `max`
  (highest line number) + hit lines — but `max` includes blank/comment lines, so
  `hits/max` is **wrong**. Use LuaCov's **reporter/analysis** to get true
  executable-line coverage, then surface the overall %. (Pin the exact API for the
  summary number in Phase A, against the docs — not guessed.)
- **Reporters: text and HTML built-in** (per the docs), plus a `ReporterBase` you
  can subclass (`on_hit_line` hook). We use the **text reporter** — **not HTML**:
  HTML would need a `WKWebView`, re-incurring the sandbox/second-window cost we
  rejected in §3.8. Optionally subclass `ReporterBase` later to emit a
  colorizable format our viewer styles (covered vs uncovered lines) — polish, not
  v1 baseline.

**Wire-up — the percentage:** the bootstrap emits the computed overall % as a
structured line (reuse the §3.5 protocol, `[[LS_COV]]{pct=…}` — add it to the
frozen field list) so the Swift `TestRunner` parses it and the Explorer header
renders it.

**Wire-up — the clickable report tab.** Clicking the header % **opens the full
LuaCov text report as a read-only tab**, reusing the §3.8 mechanism exactly (the
`EditorAreaView` read-only-doc dispatch + a viewer like `MarkdownDocView`). This
needs the report *file*, not just the % over the wire: the bootstrap configures
LuaCov's `reportfile`, LuaCov writes the text report into the project, and we
**read it back and clean it up via the existing inject/`cleanupDebugTempDir`
pattern** (same as `mobdebug.lua`). The header % stays clickable only when a report
exists (coverage was on and a run completed). The report viewer is the **same `MarkdownDocView`** as the help
doc — one read-only renderer, two documents. Since LuaCov's text reporter emits
**plain text** (not Markdown), v1 **wraps the report in a code fence** so it renders
as readable monospace preformatted text through the Markdown renderer (no custom
reporter needed). Emitting real Markdown via a `ReporterBase` subclass is the
future-polish path (same hook as colorization). Tab-opening plumbing is identical
to §3.8.

### 3.8 In-app documentation: a read-only Markdown editor tab

The Test Runner ships **user documentation for the wrapper testing service** —
how to write a test against the facade, configure folder/glob rows, and read the
statuses — rendered **in-app**, not in an external browser. (A browser opening a
local HTML file was considered and rejected: under the app sandbox it re-incurs
the security-scoped-resource dance for no benefit, loses light/dark sync, and
opens a second window for a one-page help doc.)

**Mechanism: open it as an editor tab.** The editor area
([`EditorAreaView`](../LoveStudio/LoveStudio/Views/Studio/StudioView.swift)) already
renders multiple content kinds keyed by file URL (`conf.lua` → `ConfEditorView`,
else → `LuaEditorView`, fed by `textBuffers[url]`). The help doc rides the same
tab machinery:

- Ship **`test-runner-help.md`** in the app bundle (`Resources/`, alongside the
  testkit, §3.4 / Phase A).
- A **`?` button in the `TestExplorerView` header** (beside Run All / Stop /
  Refresh / Collapse) resolves the bundled file's URL and calls the existing
  `openFile(ProjectItem(url:))`, so it opens as a normal tab — close / reopen /
  switch all work for free.
- A new **`MarkdownDocView`** (Phase D) renders it: a ~60-line **block renderer**
  (headings, paragraphs, code blocks, lists) styled to match the app's existing
  documentation look — reuse `DocsView`'s visual language (`DetailSection`-style
  cards, the `signatureFill` monospace background for code blocks,
  `colorScheme`-aware). **Read-only** — no text buffer, no dirty state.

**Implementation gotcha (URL-keyed tabs).** Tabs are keyed by URL and the editor
dispatch infers content kind from the path, so two things are required: (a) the
dispatch in `EditorAreaView` must branch on the help doc **before** the
conf/Lua fallback and route it to `MarkdownDocView` read-only — otherwise
`LuaEditorView` loads it as editable, dirtyable text; and (b) the tab needs a
stable URL — the bundle resource path is fine (untitled files already set the
precedent for non-project URLs in `openTabs`). The tab icon reuses the existing
`FileIconView` `.md → markdown` SVG mapping.

**Scope:** this branch matches *this* help doc specifically, **not** "any `.md`
file." Rendering arbitrary Markdown this way would mean a tab-kind refactor
(making a tab an enum `.file`/`.doc`/… rather than always a URL) — deliberately
out of scope for v1; revisit only if non-file tabs multiply. Authoring the
content of `test-runner-help.md` is a separate task (hand-written), not part of
the wiring above.

---

## 4. Architecture

### 4.1 Discovery vs results

VS Code's Test Explorer shows the tree of tests **before** running them (hollow
circles), then fills in pass/fail. This requires the runner to separate:

- **Discovery** — statically find the facade's `describe`/`it` blocks (and/or
  LuaUnit `Test*` functions) and build a `TestNode` tree *without executing test
  bodies*, capturing each test's `file` + `line`.
- **Results** — run, and update each node's status from the structured result
  lines.

> Discovery granularity is an open sub-decision — see §5.3.

**The statically-discovered tree is provisional; the run is authoritative.**
The static parse (§5.3) and the runtime emitter (§3.5) derive the stable ID
(§4.4) **independently** — the parser from source structure, the facade from the
live scope stack as `describe`/`it` actually execute. They agree for statically
spelled tests, but diverge for tests the parser cannot see:

- **Data-driven tests** — `for _, c in ipairs(cases) do it(c.name, …) end`
  produces N tests at runtime but **zero** to a static parser.
- **Computed names** — `it(someVar, …)` has no statically-readable name.

**Reconciliation rule:** a `[[LS_TEST]]` result whose `id` matches no
discovered node is **not dropped** — it is **created** and inserted into the tree
under its path. The static tree seeds the hollow up-front view; the run's emitted
nodes are the source of truth and may **add, rename, or remove** nodes after
execution. UI consequence: data-driven tests appear (or refine) only after a run,
and the Explorer should treat the pre-run tree as provisional rather than
authoritative.

### 4.2 Execution mode

Tests run via a **new run-mode in `LoveRunner`**, a sibling to `run` and
`runDebug`. The runtime is **settled (§5.5): the already-bundled `love` binary run
headless** — `conf.lua` disables window/graphics/audio, `main.lua` is our test
bootstrap. **No standalone `luajit` is bundled** — verified that `love` runs plain
Lua headless under real LuaJIT/5.1 and exits cleanly (§5.5).

We reuse `LoveRunner`'s existing `Process` + stdout/stderr pipe plumbing
([`LoveRunner.launch`](../LoveStudio/LoveStudio/Services/LoveRunner.swift) ~line
117) and its `file.lua:NN:` error parsing
([`parseErrorRef`](../LoveStudio/LoveStudio/Services/LoveRunner.swift) ~line 201)
so failures get clickable jump-to-source for free. Hot reload stays off in test
mode (as it does in debug mode).

> **Note:** pass/fail comes from the **structured output stream**, never the
> process exit code.

### 4.3 Run lifecycle: stop, timeout, and mutual exclusion

- **Stop.** A run is cancellable. The Test Explorer exposes a Stop action that
  terminates the spawned headless-`love` process, reusing `LoveRunner`'s existing
  `stop()`/process-termination path. In-flight nodes return to `notRun` (or a
  `cancelled` state); already-reported nodes keep their result.
- **Timeout.** Game code can infinite-loop, so runs are bounded by a
  **configurable timeout** (`@AppStorage("testRunnerTimeout")`, §3.7) — applied
  **per run**. On timeout the process is killed. With a single LuaJIT process the
  kill signal does **not** identify which test hung, so the offender is inferred
  from the incremental emit trail: the **last `id` that emitted a start but never
  a `[[LS_TEST]]` result** is marked `error` ("timed out"); every test after it
  that never started is left `notRun`. Reserve `cancelled` for user-initiated
  Stop, not timeout. (This is parser logic, not a new setting — the timeout
  control and the Stop action already exist; the parser just attributes the kill
  correctly instead of leaving the tree ambiguous.) Default: e.g. 30 s per run.
- **Mutual exclusion (C9).** Tests **do not run while the game is running or
  debugging** (`runner.isRunning` / `isDebugging`). The Run-Tests action is
  disabled in that state, mirroring how the existing Run/Debug controls gate on
  `runner.isRunning`. Likewise, Run/Debug is unavailable while tests are running.

### 4.3a Concurrency: tree mutation stays on the main actor

The structured-line parser (§Phase C) consumes stdout from a `Process`
readability handler, which fires on a **background queue**. The `TestNode` tree is
`@Observable` and read by SwiftUI on the **main actor**, so **every** node
mutation (status transition, node insert/rename from §4.1, message/duration fill)
must hop to `@MainActor` before it touches the tree — otherwise it's the same
lost-update class seen elsewhere when a background producer races a main-thread
reader. Buffer partial lines across reads (a chunk may split mid-line) and treat
per-`id` transitions (`running → passed`/`failed`/`error`) as ordered.

Additionally, **suppress `FileWatcher`-triggered re-discovery (§4.6) while a run
is in flight** (gate on `!isRunning`): a debounced re-discovery firing mid-run
would rebuild the very tree the parser is writing into. Queue it and run once on
completion.

### 4.4 Stable test identity (output ↔ tree correlation)

Result lines must map to the **correct** `TestNode`, and names are not unique
(two `describe` blocks can each contain `it("works")`). So every node carries a
**stable, path-based ID** — the ordered chain of enclosing
file + `describe`/suite + test, e.g. `combat.test.lua > Damage > applies armor`.
The facade emits this **same ID** in each structured result line, and Swift
correlates by ID, **not by display name**. Discovery (§4.1) assigns the IDs;
results look them up. (Best practice: deterministic, collision-free, order-stable.)

### 4.5 Per-test output capture (B3)

User `print` / stdout produced while a test runs is **captured and routed to the
Console** (the existing bottom-panel Console tab), so a developer can see a
failing test's output. The facade emits it as **`[[LS_OUT]]{id=…,text=…}`** lines
(§3.5) tagged with the running test's ID (§4.4) — a distinct sentinel from
`[[LS_TEST]]` so the Swift parser demuxes captured output from results and TAP by
prefix. At minimum it lands in the Console stream interleaved with the run; the
`id` tag also allows associating output with its specific test.

### 4.6 Discovery triggers (B6)

(Re)discovery runs on:

- **Manual Refresh** — the Refresh action in the Explorer header.
- **File changes** — via the existing
  [`FileWatcher`](../LoveStudio/LoveStudio/Services/FileWatcher.swift): when a file
  under a configured test folder is added/removed/edited, re-run discovery (debounced)
  so the tree stays current. (Reuses the watcher the runner already uses for hot
  reload; tests just subscribe for the discovery refresh.)

---

## 5. Execution decisions (settled)

These shape the implementation; all are now decided.

### 5.1 LÖVE-stub philosophy — SETTLED: headless love, doubles by default

> **DECISION: tests run inside the bundled `love` run *headless* (window/graphics/
> audio disabled), with `love.*` replaced by test doubles by default.** A test can
> **opt into the real modules** where it needs the genuine API (see "Opt-in to real
> modules" below). Using `love` as the LuaJIT host (not a separate `luajit`) is
> §5.5; doubles-as-default keeps unit tests fast and deterministic.
>
> **Note:** an earlier draft said "tests run *without* `love`." That changed once we
> verified `love` runs plain Lua headless under real LuaJIT/5.1 (§5.5) — we now use
> `love` as the host with modules disabled. The doubles model is unchanged; only the
> host is. "Embedding risk" is mitigated because the **window/render loop is off**,
> not because `love` is absent.

LÖVE's official `testing/` suite was investigated as a possible source of
ready-made `love.*` fakes. **It is not reusable** — it runs *inside real
(headless) LÖVE* and exercises the **actual** API (it even captures real graphics
output). It is an integration harness for LÖVE itself, not a mocking kit for user
code. So nobody hands us love stubs; we write them.

- **Path 1 — Headless doubles (CHOSEN).** We hand-write fake `love.*` modules as
  spies (common subset + auto-spy for un-modeled calls). Tests run in **plain
  LuaJIT, no window** — fast, deterministic, and they **sidestep every embedding
  risk** because we never run inside `love`. Cost: we build and maintain the
  doubles (bounded, in our control, and the core source of the feature's value).
- **Path 2 — Real headless LÖVE (not chosen).** Tests run inside actual LÖVE;
  no fakes to build, but render-loop / `quit` / headless-window handling, slower
  and less deterministic tests, real GPU/filesystem effects. Possible future
  opt-in "integration mode," not v1.

**Consequences of running in headless `love`:**

- The test runtime is the **already-bundled `love`** run headless (§5.5) — no
  separate `luajit` to acquire/bundle/sign, reusing `LoveRunner`'s launch path.
- The window/graphics/audio modules are **off** by default; the doubles install
  over `love.*` before any game code is required.
- `package.path` is set to find the vendored kit + the user's game modules.

**Opt-in to real modules (per test).** Because we host on real `love`, a test can
ask for the *genuine* `love.*` API instead of the double — the test code says so,
inline, no settings:

```lua
love.graphics.real()   -- this test uses the real love.graphics, not the double
local img = love.graphics.newImage("p.png")   -- real call
```

- **Granularity: whole-module** (`love.<module>.real()`) for v1 — a test typically
  either exercises a real subsystem or doesn't; this reads cleanly and avoids
  threading a flag through every call. A per-call flag can come later if demanded.
- **Mechanism:** `real()` swaps that module's double for the real implementation
  for the duration of the test, and the lifecycle reset (§3.3, point 4) restores
  the double afterward so it doesn't leak. Calling `real()` on a module whose
  hardware backing is off (e.g. graphics needs a GPU context) is the user's risk —
  document that real-graphics tests are less deterministic and may need a context.
- **Default stays doubled.** You reach for `real()` only where you mean it; every
  other call gets the fast, deterministic double. This folds the old "e2e wall"
  (§9) into a gradient: doubled → real-module-headless → (future) real+window.

### 5.2 love-double scope — SETTLED: full coverage via auto-spy

> **DECISION: faithfully model the common subset, auto-spy everything else.**

Coverage is **total** — no `love.*` call ever crashes a test. The split is only
about *fidelity*:

- **Common subset — faithfully modeled.** The handful of
  `love.graphics`/`filesystem`/`audio`/`timer`/`math`/`event` calls real game
  logic actually uses get realistic, controllable behavior (e.g. fake in-memory
  filesystem — **sharing one backing store with the `io.*` double, §3.3a** —
  controllable timer).
- **Everything else — auto-spy.** Any un-modeled `love.*` call (including methods
  on object types like `Image`/`Quad`/`Canvas`/`SpriteBatch`/`Font`/`Source` and
  rarely-used modules) is **intercepted, recorded, and returns a recursive spy
  proxy** — it never errors. Assertions can still inspect that it was called.

  **The return value must be a self-propagating proxy, not a scalar.** A scalar
  default (`nil`/`0`/`""`) breaks the "never crashes" guarantee on the object
  path: `love.graphics.newImage("x")` returning `nil` makes the very next
  `img:getWidth()` index a scalar and crash — exactly the `Image`/`Quad`/`Canvas`
  cases listed above. So an auto-spied call returns a **proxy table** whose
  metatable propagates itself:

  ```lua
  local function makeSpy()
    local rec = setmetatable({ calls = {} }, {
      __call  = function(self, ...) self.calls[#self.calls+1] = {...}; return makeSpy() end,
      __index = function() return makeSpy() end,      -- :method() → another spy
      __add = function() return 0 end,  __sub = function() return 0 end,
      __mul = function() return 0 end,  __div = function() return 0 end,
      __concat = function() return "" end, __len = function() return 0 end,
      __tostring = function() return "<spy>" end,
      -- extend with other metamethods as real tests demand
    })
    return rec
  end
  ```

  So the proxy survives being **called**, **indexed** (method chains), and used in
  **arithmetic/concatenation/length** — the operations un-modeled return values
  realistically flow into. "Sane default" undersells it: the default *is* a
  recursive spy object.
- **Grow by demand.** When a real test needs a specific un-modeled call to behave
  realistically, promote it from auto-spy to a faithful model — driven by an
  actual test, so the behavior is correct and verified.

*Why not hand-model the entire API up front:* it's a large, release-drifting
surface most tests never exercise, and auto-spy already delivers total
"nothing-breaks" coverage. Speculative modeling risks subtly-wrong behavior with
no test to check it. Realism follows demand.

> **Validated before committing.** A prototype proxy survived all 13 operations
> real game code applies to a `love.*` return — call, method chains, every
> arithmetic op, concat, length, comparison, equality, `tostring`, deep chaining,
> calling a call-result. The Phase-A implementation re-runs this under headless
> `love` (LuaJIT/5.1) — note `__pairs`/`__len` differ from 5.x, so verify there.

### 5.3 Test discovery method — SETTLED: static parse

> **DECISION: static parse.** (This is the discovery *mechanism* — distinct from
> the discovery *triggers* in §4.6, which are FileWatcher + manual Refresh.)

Parse the test files for the facade's `describe`/`it` blocks (and/or LuaUnit
`Test*` functions) **without executing bodies**, to build the `TestNode` tree with
the stable IDs (§4.4) and `file`/`line` for each node. This populates the tree with
hollow "not-run" circles up front — matching the VS Code Test Explorer shape — and
the parse is what runs on each trigger from §4.6. (A `--list` dry-run was an
alternative; static parse avoids spawning a process just to enumerate.)

### 5.4 Per-test action granularity — SETTLED: Run All / Suite / Test + debug

> **DECISION: Run All, Run Suite, Run Test, and per-test Debug.**

- **Run All** — the whole tree.
- **Run Suite** — a `describe`/suite node and its descendants.
- **Run Test** — a single leaf, via the hover ▶.
- **Debug Test** — run a single test under the existing **mobdebug** debugger
  (the hover debug icon in the screenshot). This reuses
  [`DebugServer`](../LoveStudio/LoveStudio/Debugger/DebugServer.swift), the
  `mobdebug.lua` vendoring, and `cleanupDebugTempDir` — but **not**
  `buildDebugLauncher` / `runDebug`, which launch the real `love` binary running
  the actual game. A debugged *test* runs in **LuaJIT with the love/std doubles**
  (no `love`, no game), so it is the **test** launcher plus mobdebug, not the
  existing debug path.

  **Reconcile as one parameterized launcher**, not two divergent paths:

  ```
  buildTestLauncher(for: project, debug: Bool, filter: TestID?)
    • spawn the bundled `love`, headless (conf.lua: window/modules off)  (§5.5)
    • package.path → testkit + user game          (always)
    • install love + std doubles before game code (always)
    • if debug: inject mobdebug.lua, start it, point it at DebugServer
    • filter: run only the matching test id (nil → run all / suite)
  ```

  Run Test → `debug: false`; Debug Test → `debug: true`. mobdebug runs fine under
  love's LuaJIT, so the debug branch is small — but plan it in Phase C as "test
  launcher + mobdebug," **not** as `runDebug` dropping in unchanged (it would
  launch the game, not the test). Net: **reuse `DebugServer`; do not reuse
  `runDebug`.**

### 5.5 Runtime — SETTLED: the bundled `love`, run headless (no separate luajit)

> **DECISION: spawn the already-bundled `love` binary headless. No standalone
> `luajit` is acquired or bundled.**

**Verified, not assumed.** The bundled
[`love`](../LoveStudio/LoveStudio/Resources/LoveRuntime/love.app) (LOVE 11.5) was
run against a temp game whose `conf.lua` sets `t.window = false` and disables
graphics/audio/window modules, and whose `main.lua` printed a sentinel and called
`love.event.quit(0)`. Result: it ran headless, emitted the output, and **exited 0
cleanly** — under **real LuaJIT, `_VERSION = "Lua 5.1"`**.

This collapses the earlier "acquire + bundle + code-sign + entitlement-clear a
`luajit` binary" plan to nothing:

- **No new binary.** Reuse the `love` already bundled and signed; spawn it via
  `LoveRunner`'s existing launch path. No `LuaRuntimeResolver` — the existing
  [`LoveRuntimeResolver`](../LoveStudio/LoveStudio/Services/LoveRuntimeResolver.swift)
  already finds `love`.
- **Real runtime for free.** Tests run under the *same* LuaJIT/5.1 the shipped game
  uses — so the "verify under LuaJIT" note (§5.2/§3.3) is satisfied by construction
  (the host *is* LuaJIT/5.1).
- **Mechanism.** `buildTestLauncher` writes a temp dir: a `conf.lua` that disables
  window/graphics/audio (for doubled tests) and a `main.lua` bootstrap that installs
  the doubles, sets `package.path`, requires the user's code, runs the tests, emits
  `[[LS_TEST]]`/`[[LS_OUT]]`/`[[LS_COV]]`, and calls `love.event.quit()`. Inject/
  clean up via the existing `cleanupDebugTempDir` pattern.
- **Real-module tests (§5.1)** simply generate a `conf.lua` that leaves the needed
  modules enabled.

---

## 6. File-by-file build order

### Phase A — Vendor the Lua kit (manual + fetched into repo)

Place under `LoveStudio/LoveStudio/Resources/testkit/`:

- `luaunit.lua` — engine (vendored).
- `luassert/` + `say/` — mocking (vendored).
- `luacov/` — coverage (vendored, `lunarmodules`, pure Lua); `runner.init()` from
  the bootstrap, `exclude` set to drop the kit/doubles, **text reporter** for the
  true % **and** the report file the clickable-% tab opens (§3.9).
- `love_stubs.lua` — the love fakes (we write; scope per §5.2).
- `std_doubles.lua` — the `os`/`io`/`debug`/`math.random`/`print` doubles for user
  code (§3.3a), with the per-test opt-in/out hooks.
- `lovetest.lua` — **the facade** (we write): single-`require` API, `describe`/
  `it`/`before_each`/`after_each` executor, assertion normalization, lifecycle ⇄
  mock-reset, AAA + BDD entry points, **stable path-based test IDs (§4.4)**,
  **structured result-line emitter** — `[[LS_TEST]]` (incl. mandatory `id`) +
  `[[LS_OUT]]` for captured output + `[[LS_COV]]{pct}` when coverage is on
  (§3.5/§4.5/§3.9) — + TAP summary. The facade's IDs
  must match what discovery derives statically; mismatches are reconciled by the
  run-authoritative rule (§4.1). **Build and exercise this file from the CLI via
  headless `love`** (the confirmed LuaJIT/5.1 host, §5.5) **before any Swift exists**
  — it's the densest correctness
  surface (nested before/after ordering, throw handling). luaunit's native
  lifecycle is flat `setUp`/`tearDown`, so the facade owns: outer→inner
  before-ordering, inner→outer after-ordering, `after_each` still running when the
  body throws, and an exception in `before_each` ⇒ `error` + skip body.

These bundle into the app like the existing `Resources/mobdebug.lua`.

Also ship the user-facing help doc in the bundle (not under `testkit/`, since
it's not injected into projects):

- `Resources/test-runner-help.md` — user documentation for the wrapper testing
  service, rendered in-app via the docs editor tab (§3.8, Phase D). Hand-authored;
  bundled, never downloaded.

### Phase B — Swift models

- `Models/TestNode.swift` — `@Observable`: `id` (stable path-based ID, §4.4),
  `name`, `kind` (`.suite`/`.test`),
  `status` (`.notRun`/`.running`/`.passed`/`.failed`/`.error`/`.skipped`/`.cancelled`),
  `file`, `line`, `children: [TestNode]`, `duration`, `message` (failure/error
  detail shown on expand, §Phase D). Mirrors the `@Observable` tree style of
  [`ProjectItem`](../LoveStudio/LoveStudio/Models/Project.swift).

### Phase C — Swift services

- `Services/TestRunner.swift` — `@Observable`, the `*Store`-style service:
  - `discover(projectURL:) -> [TestNode]` (per §5.3) — builds the **provisional**
    hollow tree; the run supersedes it (§4.1).
  - `run(...)` for all / a suite / a single node (per §5.4).
  - the **structured-line parser** mapping `[[LS_TEST]]` lines back onto nodes by
    **stable ID (§4.4), not name**, reusing `parseErrorRef` for failure file/line.
    A result whose `id` matches no node is **created**, not dropped (§4.1).
    Routes `[[LS_OUT]]` lines to the Console, `[[LS_COV]]{pct}` to the header %
    (§3.9); treats unprefixed output as TAP.
    **All tree mutation hops to `@MainActor`** (§4.3a); buffers partial lines.
  - **coverage report** (when `testRunnerCoverage` on): after the run, read the
    LuaCov text report file the bootstrap wrote into the project, hold its
    contents (or URL) so the clickable % can open it as a tab (§3.9), and remove
    it via `cleanupDebugTempDir`.
  - `stop()` to cancel an in-flight run (§4.3) → `cancelled`; enforces the
    configured timeout, attributing the kill to the last-started-unfinished `id`
    as `error`/"timed out" (§4.3).
  - holds the `[TestNode]` tree + run summary; refuses to run while the game is
    running/debugging (§4.3, C9); suppresses re-discovery while `isRunning`
    (§4.3a).
- **Extend `LoveRunner`** with a test run-mode (sibling to `run`/`runDebug`):
  a single **`buildTestLauncher(for:debug:filter:)`** (§5.4) — spawns the
  **bundled `love` headless** (temp `conf.lua` disables window/graphics/audio;
  real-module tests leave the needed modules on, §5.1) (§5.5), sets `package.path`
  to the vendored kit + the user's game, installs the `love` + std doubles before
  requiring game code, and (when `debug: true`) injects `mobdebug.lua` pointed at
  `DebugServer`. `filter` selects all / suite / single test. Cleanup via the
  existing `cleanupDebugTempDir`. **Reuses `DebugServer`, not `runDebug`** (§5.4).
  Tee `[[LS_TEST]]`/`[[LS_OUT]]`/`[[LS_COV]]` to `TestRunner`; tee final TAP to the
  Console.
- **No `LuaRuntimeResolver`** — the existing
  [`LoveRuntimeResolver`](../LoveStudio/LoveStudio/Services/LoveRuntimeResolver.swift)
  already locates `love` (§5.5).

### Phase D — Swift UI

- `Views/Tests/TestExplorerView.swift` — header toolbar + the tree. Header actions:
  **Run All**, **Stop** (visible while running, §4.3), **Refresh** (re-discover,
  §4.6), **Collapse All**, a **`?` Help** button (opens the docs tab, §3.8) + a
  pass/fail/duration summary **and the coverage % when enabled** (from `[[LS_COV]]`,
  §3.9; hidden when `testRunnerCoverage` is off). **The % is a button** — clicking
  it opens the LuaCov text report as a read-only tab via the §3.8 mechanism
  (clickable only when a report exists). Header pattern follows the bottom panel's
  header row
  ([`StudioView`](../LoveStudio/LoveStudio/Views/Studio/StudioView.swift) ~lines
  916–973).
- `Views/Tests/TestNodeRow.swift` — recursive disclosure row (like
  [`FileTreeView`](../LoveStudio/LoveStudio/Views/Studio/StudioView.swift)) +
  status icon + name + hover ▶/debug (per §5.4); `onTap → onJump(file, line)`
  (the same hook used by `CallStackRow`/`BreakpointRow` in
  [`DebugPanelView`](../LoveStudio/LoveStudio/Views/Debug/DebugPanelView.swift)).
  - **Failure detail on expand (B4):** a failed/errored test node is expandable;
    expanding reveals its `message` (assertion text / error + stack), styled like
    the monospaced rows in `DebugPanelView`. Passing nodes don't expand.
- **Empty / misconfigured states (B5):** when no test rows are configured, or
  configured folders yield zero tests, the Explorer shows a centered message with
  a **link to the Tests settings** (deep-link to the Runner settings tab), using
  the existing `placeholder` style. A **test file that fails to load** (e.g. a
  syntax error) appears as an **`error` node** with the load error as its
  message — it is never silently dropped.
- **Status iconography** — all SF Symbols (no custom SVG), one per `TestNode.status`:

  | Status | SF Symbol | Color |
  | ------ | --------- | ----- |
  | Passed | `checkmark.circle.fill` | green |
  | Failed (assertion) | `xmark.circle.fill` | red |
  | Error (threw/crashed) | `exclamationmark.triangle.fill` | orange |
  | Not run | `circle` | secondary |
  | Running | `ProgressView()` spinner (inline, like the debug panel) | accent |
  | Skipped | `minus.circle` | secondary |

  - **Suite aggregation:** a suite node's icon reflects its children — error if any
    errored, else failed if any failed, else running if any running, else passed
    if all passed, else not-run. (Matches VS Code.)
  - **Failed vs Error are distinct:** red ✗ for a clean assertion failure, orange
    ⚠️ for a test that threw/crashed. The error state is recommended but optional
    for v1 (could collapse into "failed" initially).

- `Views/Tests/MarkdownDocView.swift` (§3.8) — a **read-only** block renderer for
  the bundled `test-runner-help.md`: parse into blocks (headings, paragraphs, code
  blocks, lists) and style to match the app's docs look (reuse `DocsView`'s
  `DetailSection`-style cards, `signatureFill` monospace for code blocks,
  `colorScheme`-aware). No text buffer, no dirty state. **Also add a dispatch
  branch in `EditorAreaView`** (in `StudioView.swift`) that routes the help doc to
  this view **before** the conf/Lua fallback (otherwise `LuaEditorView` loads it
  as editable text); the `?` button in the Explorer header opens it via the
  existing `openFile(ProjectItem(url:))` using the bundle resource URL.

### Phase E — Wire-up

- Add `case tests` to
  [`SidebarTab`](../LoveStudio/LoveStudio/Views/Studio/StudioView.swift) (~line
  334): `title` "Tests", `icon` `flask.fill`, and a `tabContent` branch (~line
  304) rendering `TestExplorerView`.
- Add a toolbar **Run Tests** button beside Run/Debug in `StudioToolbar`
  (~lines 1288–1328), **disabled while `runner.isRunning` or `isDebugging`** (C9,
  §4.3) — and conversely Run/Debug disabled while tests run.
- Optional: auto-select the Tests tab on test-run start, mirroring
  `if isDebugging { selectedTab = .debug }` (~line 990).
- No keyboard shortcut for v1 (C7) — the
  [keymap list](../LoveStudio/LoveStudio/Views/Settings/SettingsView.swift) is left
  unchanged.

### Phase F — Settings (§3.7)

- In [`SettingsView`](../LoveStudio/LoveStudio/Views/Settings/SettingsView.swift),
  add a **"Tests" `Section`** to `RunnerSettingsView` with:
  - `Toggle("Enable Test Runner", …)` bound to `@AppStorage("testRunnerEnabled")`.
  - an editable **list of `folder | glob` rows** (array of `{folder, glob}`,
    JSON-encoded into one `@AppStorage` string), with add/remove rows. The
    runner uses whatever glob the user supplies — no built-in naming convention.
  - a **Test timeout** control bound to `@AppStorage("testRunnerTimeout")` (§3.7,
    §4.3).
  - a separate **`Toggle("Enable code coverage")`** bound to
    `@AppStorage("testRunnerCoverage")` (§3.7 #4, §3.9) — independent of the
    enable toggle; default off.
- Gate the sidebar tab (Phase E) and toolbar button on `testRunnerEnabled`;
  gate coverage init + the header % on `testRunnerCoverage` (independent gates).
- `TestRunner.discover` walks each folder and matches *that folder's* patterns
  within it (patterns are folder-scoped, not project-wide).
- The Explorer's empty-state link (B5) deep-links here (open Settings → Runner).

### Phase G — Sandbox / entitlements (C8)

Writing the injected test kit into the project directory and spawning a process
that reads it must work under the app sandbox. Reuse the **security-scoped
resource** pattern `Project` already uses
([`Project.saveBookmark` / `startAccessingSecurityScopedResource`](../LoveStudio/LoveStudio/Models/Project.swift)
~lines 78–101) — the same mechanism the debugger relies on when injecting
`mobdebug.lua`. **No new entitlement is expected** — tests spawn the same bundled
`love` that Run/Debug already launch (§5.5), so its execution is already
entitlement-cleared. (This is simpler than the earlier plan, which would have
needed a *new* `luajit` binary cleared to execute under
[`LoveStudio.entitlements`](../LoveStudio/LoveStudio/LoveStudio.entitlements).)

---

## 7. Risk register

Running **headless with doubles** (§5.1) — plain LuaJIT, no `love` — retires most
of these by construction. Kept for the record:

1. **Process ownership** — a runner that assumes it owns the process would fight a
   render loop and exit code. *Retired:* we never run inside `love`; LuaUnit is
   invoked programmatically in plain LuaJIT.
2. **`os`/`io`/`debug` under LÖVE's sandbox** — restricted functions crashing deep
   in vendored code. *Retired:* LuaUnit + luassert are small and pure, and run in
   plain LuaJIT (no LÖVE sandbox).
3. **LuaJIT/5.1 seams** — version-conditional code in a dependency. *Mitigated:*
   the vendored libs support 5.1/LuaJIT.
4. **Discovery/`require` path confusion** — mixing plain-Lua paths with
   `love.filesystem` virtual paths. *Retired:* there is no `love.filesystem` —
   discovery and loading are entirely on plain Lua paths.
5. **Output parsing is load-bearing** — pass/fail comes from the output stream,
   not an exit code. *Mitigated:* we own the facade's structured format, so
   parsing is against a format we control, not a scraped one. Distinct sentinels
   (`[[LS_TEST]]`/`[[LS_OUT]]`/TAP, §3.5) let the parser demux the shared stdout
   by prefix. **Still a real remaining risk** (`io.write`/FFI can reach fd 1
   below the `print` double and bypass capture — acceptable for v1).
6. **Off-main tree mutation** — the parser runs on the `Process` stdout
   background queue and mutates the `@Observable` `TestNode` tree SwiftUI reads on
   the main actor; a naive implementation races (lost updates / UI corruption).
   *Mitigated by design (§4.3a):* all mutation hops to `@MainActor`; partial
   lines buffered; re-discovery suppressed while `isRunning`. **Real — must be
   built in from the start, not retrofitted.**
7. **Discovery vs runtime ID divergence** — static parse and the runtime emitter
   derive IDs independently, so data-driven / computed-name tests exist at runtime
   but not in the static tree. *Mitigated by design (§4.1):* run is authoritative;
   an unmatched result is **created**, not dropped; the pre-run tree is
   provisional. **Real** — the reconciliation rule must be implemented or
   data-driven tests silently vanish.

---

## 8. Status summary

| Concern | Decision |
|---|---|
| Engine | **LuaUnit** (vendored) |
| Mocking | **luassert** spy/stub/mock + `say` (vendored) |
| Facade | one `require` API tying it together, emits structured lines + TAP |
| UI data source | **structured result lines (`[[LS_TEST]]`, mandatory `id`) → `TestNode` tree** (visual) |
| Output channels | **`[[LS_TEST]]` → Explorer; `[[LS_OUT]]` → Console (per-test); `[[LS_COV]]{pct}` → header %; TAP → Console (summary)**, demuxed by prefix; §3.5 |
| Sidebar | **5th `SidebarTab`**, flask icon, existing row layout |
| Bundling | **manual vendor in repo → inject at run time** (debugger pattern) |
| **Execution** | **SETTLED — headless, no `love`, using doubles** (Path 1); §5.1 |
| Test runtime | **SETTLED — spawn the already-bundled `love` HEADLESS (no separate luajit); verified runs plain Lua under real LuaJIT/5.1 + exits 0**; §5.5 |
| Real-module opt-in | **SETTLED — doubled by default; a test calls `love.<module>.real()` to use the genuine API (whole-module, v1); restored after via lifecycle reset**; §5.1 |
| Settings | **SETTLED — global `@AppStorage`, under Runner tab**: enable toggle + folder/glob rows + timeout + **separate coverage toggle**; §3.7 |
| Code coverage | **SETTLED (v1) — overall % in Test panel via vendored LuaCov (`runner.init()`, `exclude` kit, text reporter for true %); clicking the % opens the report as a read-only tab (§3.8 mechanism); gated by its own `testRunnerCoverage` toggle, default off; gutters = future**; §3.9 |
| stdlib doubles | **SETTLED — deterministic fakes for user code, per-test opt-in/out; `io` + `love.filesystem` share one in-memory store (canonical-key normalized)**; framework keeps real `os`/`io`/`debug`; §3.3a |
| Test levels | **SETTLED — v1 = unit + integration (headless); e2e is future (real `love`, Path 2)**; §1, §9 |
| Run lifecycle | **SETTLED — stop + configurable timeout; no run while game runs/debugs**; §4.3 |
| Test identity | **SETTLED — stable path-based IDs, correlate by ID not name; ID is a mandatory `[[LS_TEST]]` field**; §4.4, §3.5 |
| Per-test output | **SETTLED — captured user `print`/stdout → `[[LS_OUT]]` → Console**; §4.5 |
| Failure detail | **SETTLED — shown on node expand**; Phase D (B4) |
| Empty/error states | **SETTLED — message + settings link; failed-to-load file → error node**; Phase D (B5) |
| Discovery triggers | **SETTLED — FileWatcher + manual Refresh**; §4.6 |
| Entitlements | **SETTLED — reuse security-scoped pattern; spawns the same bundled `love` as Run/Debug, so no new entitlement**; Phase G (C8) |
| Keyboard shortcut | **SETTLED — none for v1**; (C7) |
| love-double scope | **SETTLED — common subset modeled, auto-spy everything else returns a recursive spy proxy (total coverage)**; §5.2 |
| In-app docs | **SETTLED — user help as a read-only Markdown editor tab; `?` button in Explorer header; bundled `test-runner-help.md`**; §3.8 |
| Discovery method | **SETTLED — static parse builds a *provisional* tree; the run is authoritative (unmatched results created, not dropped)** (triggers: FileWatcher + Refresh); §5.3, §4.1, §4.6 |
| Per-test actions | **SETTLED — Run All / Suite / Test + per-test Debug via one `buildTestLauncher(debug:filter:)`; reuses `DebugServer`, not `runDebug`**; §5.4 |
| Concurrency | **SETTLED — all `TestNode` mutation on `@MainActor`; re-discovery suppressed while running; timeout offender inferred from emit trail**; §4.3a, §4.3 |
| Risk prototypes | **VALIDATED — nested lifecycle + recursive spy proxy prototyped before committing; re-verified during Phase A under headless `love` (LuaJIT/5.1, §5.5)**; §5.2 |
| User-code boundary | **VALIDATED — game load under doubles, `require`-path, and `package.loaded` reset confirmed against a realistic module**; new `freshRequire` isolation rule; §3.3b |

**All decisions are settled, and the high-risk Lua pieces were prototyped and
validated** (nested lifecycle + recursive spy proxy — both ran green). The runtime
is settled and **verified**: the bundled `love` runs the kit headless under real
LuaJIT/5.1 (§5.5), so there's no luajit to procure. **Proceed to build.** The
prototypes were throwaway and have been removed; Phase A re-establishes them as the
real `lovetest.lua`/`love_stubs.lua`, exercised under headless `love`.

Pin these three before writing `lovetest.lua`, since they are load-bearing for
Phases A/C: the discovery↔runtime reconciliation rule (§4.1), the recursive
auto-spy proxy (§5.2), and the frozen `[[LS_TEST]]`/`[[LS_OUT]]` wire format (§3.5).

---

## 9. Future phase: e2e / real-engine tests (Path 2)

Not v1. End-to-end tests need the **real `love` runtime** — the engine is the
system under test, so doubles don't apply (§1). When we build it:

- **Reuse the existing launch path.** `LoveRunner` already launches the real game
  via the bundled `love`
  ([`run` / `launch`](../LoveStudio/LoveStudio/Services/LoveRunner.swift)). An e2e
  run mode runs the *actual* project (no doubled modules), headless if possible.
- **Drive + assert on real state.** Inject scripted input and assert on real
  frames/window/state — the model LÖVE's official `testing/` suite uses
  (coroutine-per-test, `waitFrames`/`waitSeconds`, real graphics capture).
- **Re-incurs the deferred risks** (render loop ownership, `quit`/exit-code
  handling, determinism) — which is exactly why it's a separate phase, not v1.
- **Shares the UI.** The same Test Explorer tree, status icons, and structured
  result-line protocol apply; only the execution backend differs. An e2e test
  would be marked as such (separate folder/glob rows, or a per-test annotation) so
  the runner routes it to the real-`love` backend instead of headless LuaJIT.
