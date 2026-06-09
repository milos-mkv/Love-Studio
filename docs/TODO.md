# Test Runner — TODO

Build checklist for the Test Runner feature. Derived from
[test-runner-plan.md](test-runner-plan.md); section refs (§) point there.

Scope for v1: **unit + integration tests**, headless (plain LuaJIT, `love.*` and
the standard library doubled). E2e is a future phase (§9).

**All decisions are settled** — see [test-runner-plan.md §8](test-runner-plan.md).
Key settled scoping calls: love doubles = common subset modeled + **auto-spy
everything else (recursive spy proxy)** (total coverage, §5.2); discovery =
**static parse → provisional tree, run is authoritative** (§5.3, §4.1), triggered
by FileWatcher + Refresh (§4.6); run actions = **Run All / Suite / Test +
per-test Debug** via one `buildTestLauncher(debug:filter:)` (§5.4).

**Pin before writing `lovetest.lua`** (load-bearing for Phases A/C): the
discovery↔runtime reconciliation rule (§4.1), the recursive auto-spy proxy
(§5.2), and the frozen `[[LS_TEST]]`/`[[LS_OUT]]` wire format (§3.5).

---

## Phase 0 — Risk validation (done)

The high-risk pieces were prototyped and **validated** before committing, then the
throwaway prototypes were removed. Findings (carried into Phase A):

- [x] **Nested lifecycle** — outer→inner before / inner→outer after, `after_each`
      on body-throw, partial teardown on `before_each` throw. All four cases passed.
- [x] **Recursive spy proxy** — one proxy survived all 13 operations (call, method
      chains, arithmetic, concat, length, comparison, equality, tostring, deep chain).
- [x] **User-code boundary** — game module with `love.*` at require-time loads under
      the doubles; `require`-path resolves; **`freshRequire` clears `package.loaded`
      so module state doesn't leak** (control case showed plain `require` leaks);
      auto-spy call is assertable (§3.3b).
- [x] **Runtime confirmed** — the bundled `love` runs plain Lua headless and exits
      0 under real **LuaJIT/5.1** (`t.window=false`, modules off). No standalone
      luajit needed (§5.5).
- [x] **Re-verified lifecycle + proxy under headless `love`** — the full facade
      regression (9 pass / 1 fail / 1 error) ran under the bundled `love` LuaJIT/5.1.
- [x] **Auto-spy wired to real `assert.spy()`** — regression's `spy` test used
      `assert.spy(s).was.called()` against the facade and passed (the luassert
      integration the prototype left open).

---

## Phase A — Vendor the Lua kit

Placed under `LoveStudio/LoveStudio/Resources/TestKit/` (PascalCase to match
`FileIcons/`/`LoveRuntime/`; bundles like the existing `Resources/mobdebug.lua`).
Each lib in its own module namespace so `require` resolves from one `package.path`
root (`TestKit/?.lua;TestKit/?/init.lua`) — **verified loading under headless
`love`.**

- [x] Vendor `luaunit.lua` (engine).
- [x] Vendor `luassert.lua` + `luassert/` + `say/` (mocking). Loads OK; `luassert.spy`
      resolves.
- [x] Vendor `luacov.lua` + `luacov/` (coverage, `lunarmodules`, pure Lua). Loads OK.
      *(Wiring still to do in Phase C:* bootstrap calls `runner.init()` when coverage
      enabled; `exclude` drops the kit + doubles; **text reporter for the true %**
      (not `hits/max` — `max` counts blanks/comments) **and to write the report file**
      the clickable-% tab opens. Emit `[[LS_COV]]{pct}` (§3.9). **No HTML reporter** —
      WKWebView, rejected (§3.8). Pin the exact summary API against the docs.*)
- [x] Write `love_stubs.lua` — `love.*` doubles: models common subset (graphics/
      filesystem/timer/math/event over the **shared in-memory store**, §3.3a);
      **auto-spy every un-modeled call — recursive spy proxy** (never a scalar, so
      `newImage():getWidth()` can't crash); records calls; `love.<module>.real()`
      opt-in (§5.1); `controller.reset()` for lifecycle. **10/10 checks pass under
      headless `love`.**
  - [x] **Bootstrap finding applied:** the generated `main.lua` captures
        `local realQuit = love.event.quit` (and `realWrite = io.write`) before
        installing doubles, and uses them to emit + terminate
        ([TestLauncher.swift](../LoveStudio/LoveStudio/Services/TestLauncher.swift)).
- [x] Write `std_doubles.lua` — `os`/`io`/`debug`/`math.random`/`print` doubles
      for user code, per-test opt-in/out (`apply`/`restoreReal`/`useReal`). **`io.*`
      shares the `love.filesystem` store** (canonical-key normalized); deterministic
      clock + `os.exit` blocked; `math` inherits real fns, `random` deterministic;
      `print` → capture sink. **11/11 checks pass** incl. cross-API fs both directions.
- [x] Write `lovetest.lua` — the **facade**: single-`require` API (`expose(_G)` puts
      describe/it/before_each/after_each/assert/spy/stub/mock into scope); nested
      lifecycle executor; mock-reset between tests; **`freshRequire`** clears
      `package.loaded[<module>]` (§3.3b); installs love+std doubles; **stable
      path-based IDs** (§4.4); **wire emitter** `[[LS_TEST]]`/`[[LS_OUT]]` with
      escaped fields (§3.5). **Verified end-to-end under headless `love`: 5 pass /
      1 (intentional) fail** — nested order, throw→failed, freshRequire isolation,
      captured print, **`assert.spy().was.called()` (luassert integration proven)**.
  - [x] **`love.<module>.real()` opt-in (§5.1)** — implemented in `love_stubs`;
        lifecycle `reset()` restores the double.
  - [x] **Deterministic run order — SETTLED: source-declaration order.** Tests and
        child-`describe`s interleave via a per-node `seq` list, so run order = as
        written (not siblings-before-children — a real bug caught by running it; the
        old all-tests-then-all-children order surprised the nested-order test).
  - [x] **TAP summary emit** — `TAP version 13` + plan + `ok`/`not ok # failed|error`
        + `# passed/failed/error` count, unprefixed → Console (§3.5).
  - [x] **`assert`-fail vs thrown-`error` distinction** — facade wraps luassert so
        failures are tagged (`ASSERT_TAG`), classified `failed`; thrown/runtime errors
        → `error`. Robust (no message string-matching). Verified.
  - [x] **Load-error nodes** — a syntax-broken test file → `<load error>` node with
        `error` status, emitted first (§B5). Verified.
  - [x] **Built + exercised from the CLI via headless `love`** (LuaJIT/5.1, §5.5)
        — the densest correctness surface, before any Swift. Confirmed —
        luaunit's lifecycle is flat `setUp`/`tearDown`, so verify: outer→inner
        before-order, inner→outer after-order, `after_each` still runs when the body
        throws, exception in `before_each` ⇒ `error` + skip body, mock-reset between
        tests.
  - [x] **Facade IDs match discovery's static derivation — VERIFIED.** Ran the same
        file through both: facade-emitted `[[LS_TEST]]` ids and
        `TestDiscovery.parse` ids are **byte-for-byte identical** (top-level +
        nested describes). So results correlate to discovered nodes by id (§4.4);
        the run-authoritative rule (§4.1) only creates nodes for genuinely
        dynamic tests.
- [x] Ship `Resources/test-runner-help.md` — user help (first test, structure,
      assertions, spies/stubs/mocks, what `love.*` does, `real()` opt-in, coverage).
      Bundled, **not** under `TestKit/`. (In-app rendering wiring is Phase D.)
- [x] **Pin vendored libs to tagged releases** — LuaUnit `LUAUNIT_V3_5`, luassert
      `v1.9.0`, say `v1.4.1`, luacov `v0.17.0`; recorded in `TestKit/VENDORED.md`.
      Re-ran full regression after pinning: **9 pass / 1 fail / 1 error** (the two
      intentional), identical to pre-pin.

## Phase B — Swift models

- [x] `Models/TestNode.swift` — `@Observable`: stable `id` (§4.4), `name`, `kind`,
      full `status` enum (each with SF Symbol + tint + severity), `file`, `line`,
      `children`, `durationMs`, `message`; `effectiveStatus` (suite aggregation,
      §Phase D), `find(id:)`, `resetResults()`, `hasDetail`; + `TestRunSummary`
      (counts + coverage %). Mirrors `ProjectItem`. **Type-checks clean vs macOS SDK.**
      Auto-included via the project's synchronized groups (no pbxproj edit needed).

## Phase C — Swift services

- [x] `Services/TestRunner.swift` (`@MainActor @Observable`). **Type-checks clean;
      full pipeline (discovery → launcher → headless `love` → parse) verified e2e on
      a realistic project: 2 pass / 1 fail.**
  - [x] `discover(projectRoot:rows:)` — static parse via `TestDiscovery` (no body
        exec), stable IDs + `file`/`line` (§5.3); provisional tree (§4.1).
  - [x] `run(projectRoot:rows:filter:debug:)` — All / Suite / single via `filter`.
  - [x] structured-line parser (`WireParser`): correlate `[[LS_TEST]]` by **stable
        ID** (§4.4); **unmatched id → created, not dropped** (`insertSynthetic`, §4.1);
        `[[LS_OUT]]` → Console, `[[LS_COV]]{pct}` → coverage %, unprefixed → Console/TAP.
  - [x] **All mutation `@MainActor`** (class-isolated); **buffers partial lines**
        (`ingest`/`lineBuffer`, §4.3a).
  - [x] `stop()` → `cancelled`; timeout kills + attributes to **last-started-
        unfinished id** as `error`/"timed out" (§4.3).
  - [x] **Per-test debug under mobdebug** — `TestLauncher` `debug:true` copies
        `mobdebug.lua` into the launcher dir (on `package.path`) + injects a
        pcall-guarded `mobdebug.start("localhost",8172)` before the filtered test;
        `TestRunner.debug(testId:)` starts the `DebugServer` listening, runs the
        single test, skips the timeout (breakpoints pause), tears the server down on
        finish. **Reuses `DebugServer`, not `runDebug`** (§5.4). Type-checks clean;
        debug-mode launcher verified to run + degrade gracefully with no server.
        *(C9/FileWatcher item moved to Phase E — needs StudioView state.)*
- [x] **Test runtime — done as standalone services** (`TestLauncher` + `TestRunner`
      own their `Process`), not folded into `LoveRunner`. Spawns bundled `love`
      **headless** (`conf.lua` disables window/graphics/audio/…); `package.path` →
      TestKit + project; doubles installed before game `require`; cleanup removes the
      temp launcher dir. Reuses `LoveRuntimeResolver` (§5.5).
  - [x] tees `[[LS_TEST]]`/`[[LS_OUT]]`/`[[LS_COV]]` to the parser; unprefixed/TAP →
        Console. Coverage off ⇒ bootstrap skips `luacov.runner.init()`.
  - [x] **coverage report file** — bootstrap writes LuaCov report to the temp dir;
        `TestRunner.finishRun` reads it into `lastReportText` before cleanup, for the
        clickable-% tab (§3.9). *(End-to-end coverage run not yet exercised — pending.)*
- *(decided, no task)* `Services/LuaRuntimeResolver.swift` **not needed** — reuse
  the existing `LoveRuntimeResolver`; tests spawn the bundled `love` (§5.5).

## Phase D — Swift UI

All views **type-check clean vs the macOS SDK**. Behavioral verification (icons,
clicks, expansion) happens once wired into the running app (Phase E) — tracked in
Verification.

- [x] `Views/Tests/TestExplorerView.swift` — header toolbar (**Run All**, **Stop**
      while running, **Refresh**, **Collapse All**, **`?` Help**, pass/fail summary,
      **+ clickable coverage %** when present, §3.9) + the tree, bound to `TestRunner`.
  - [x] **Coverage % is a button** — writes the report text (code-fenced) to a temp
        `.md` and calls `onOpenReport` to open it as a tab via `MarkdownDocView`;
        disabled when no report exists.
- [x] `TestNodeRow` (private in `TestExplorerView.swift`, like `DebugPanelView`'s
      rows) — recursive disclosure, status icon, name, duration; **hover ▶ Run / 🐞
      Debug** on leaves; suite disclosure; `onTap → onJump(file,line)` for leaves.
  - [x] **Failure detail on expand (B4):** failed/errored leaves are expandable and
        reveal `message` (monospaced, selectable); passing leaves don't expand.
- [x] **Status icons** — driven by `TestStatus.iconName`/`.tint` (Phase B); running
      shows an inline `ProgressView` spinner.
  - [x] **Suite aggregation** — row uses `node.effectiveStatus` (worst child).
- [x] **Empty / misconfigured state (B5):** centered message + **"Configure test
      folders…" link** calling `onOpenSettings`; "Open a project" when none.
- [x] **Failed-to-load test file (B5):** handled by the facade/parser as an `error`
      node (Phase A/C); renders like any error leaf.
- [x] `Views/Tests/MarkdownDocView.swift` (§3.8) — **read-only** block renderer
      (headings/paragraphs/fenced code/bullets/rules + inline `code`), colorScheme-
      aware, no buffer. Used for **both** the help doc and the coverage report.
  - [x] Dispatch branch in `EditorAreaView` (`isTestRunnerDoc`) routes the help doc
        + coverage report to `MarkdownDocView` **read-only, before** the conf/Lua
        fallback (scoped to our two docs, not arbitrary `.md`). Type-checks clean.
  - [x] `?`/coverage buttons open via `onOpenReport`/`onOpenDoc` → `openFile` in the
        editor area; help button resolves the bundled `test-runner-help.md`.

## Phase E — Wire-up

- [x] Added `case tests` to `SidebarTab` (`title` "Tests", `icon` `flask.fill`),
      gated on `testRunnerEnabled` (filtered from `visibleTabs`); `tabContent`
      renders `TestExplorerView` wired to the `TestRunner` state, with `onJump`/
      `onOpenReport`/`onOpenSettings` callbacks. `TestRunner` configured on appear
      (timeout/coverage settings, console sink, debug server, initial discovery).
      Whole app type-checks clean.
- [x] Toolbar **Run Tests** button (`flask.fill`) added to `StudioToolbar`,
      shown when `testRunnerEnabled`, **disabled while `runner.isRunning`/
      `isDebugging`/`testRunner.isRunning`** (C9); `runTests()` also guards. Run/
      Debug already gate on `runner.isRunning`.
- [x] Auto-select the Tests tab on run start — `onChange(of: testRunner.isRunning)`
      sets `sidebarSelection = .tests` (selection lifted to a binding).
- [x] **Mutual exclusion + discovery suppression:** `runTests()` refuses while the
      game runs/debugs (C9); FileWatcher re-discovery is suppressed while a run is in
      flight (`pendingTestDiscovery`) and flushed when the run finishes (§4.3a).
- *(decided, no task)* No keyboard shortcut for v1 (C7) — keymap unchanged.

## Phase F — Settings (§3.7)

- [x] Added a **"Tests" `Section`** to `RunnerSettingsView`. Type-checks clean.
  - [x] `Toggle("Enable Test Runner")` → `@AppStorage("testRunnerEnabled")`.
  - [x] editable **`folder | glob` row list** — `@State [TestFolderGlob]` synced to
        the JSON `@AppStorage("testRunnerFolders")` string (load on appear, persist
        on edit/add/remove); one glob per row.
  - [x] **Run timeout** slider → `@AppStorage("testRunnerTimeout")` (5–300s).
  - [x] **`Toggle("Enable code coverage")`** → `@AppStorage("testRunnerCoverage")`,
        independent of the enable toggle; default off.
  - [x] **`Toggle("Echo test results to console")`** → `@AppStorage("testRunnerConsole")`,
        default on. When on, each `[[LS_TEST]]` result is **also** echoed to the
        Console (✓/✗/⚠ + message) in addition to driving the Explorer tree —
        gated in `TestRunner.echoToConsole`. (Addition beyond original §3.7 list.)
- [x] Gate the sidebar tab + toolbar button on `testRunnerEnabled` (done Phase E);
      coverage init + header % gate on `testRunnerCoverage` (done C/D).
- [x] `TestDiscovery` matches each folder's glob within that folder (folder-scoped)
      — done in Phase C, verified e2e.
- [x] Explorer empty-state "Configure test folders…" link opens Settings via
      `onOpenSettings` (`showSettingsWindow:`) — wired in Phase E.

## Phase G — Sandbox / entitlements (C8)

- [x] **Security-scoped access** — `TestRunner` writes its launcher only to the
      system temp dir (never the sandboxed project, simpler than the debugger), and
      brackets the run with `start/stopAccessingSecurityScopedResource` on the
      project root so the spawned `love` can read the user's game (same model as
      `Project`/`LoveRunner`, §Phase G). Type-checks clean.
- *(decided, no task)* **No new entitlement** — tests spawn the same bundled `love`
  Run/Debug already launch, so execution is already cleared (§5.5).

## Discovery triggers (§4.6) — wired during C/E

- [x] Re-discover on **manual Refresh** — Refresh button in the `TestExplorerView`
      header → `discover()` (`TestExplorerView.swift:37`).
- [x] Re-discover on **file changes** via the existing `FileWatcher` — `watcher.onChange`
      in `StudioView` re-discovers; **suppressed while a run is in flight**
      (`pendingTestDiscovery`) and **flushed on completion** via
      `onChange(of: testRunner.isRunning)` (§4.3a).

---

## Verification

Build: **`xcodebuild` BUILD SUCCEEDED.** (Caught + fixed a real packaging bug —
the synchronized-group resource phase flattened `TestKit/`'s nested `init.lua`/
`util.lua` into one dir, colliding; renamed to **`TestKit.bundle`** so it copies as
an opaque tree. `love.app` flattens to `Resources/love.app`, which the resolver
already handles.) **Engine behaviors below verified end-to-end through the SHIPPED
app bundle** (`TestKit.bundle` + bundled `love.app`); items needing the GUI on
screen are marked *(visual pending)*.

- [x] Passing / failing / erroring statuses + counts correct (`p=3 f=1 e=1` run).
      *(Icon rendering itself = visual pending.)*
- [~] Click-to-source — `onJump(file,line)` wired to `openFile` + `jumpToLine`
      (Phase E); jump path is the same proven Run/Debug mechanism. *(Visual pending.)*
- [~] **Timeout attribution** — Swift logic verified by inspection: each `[[LS_TEST]]`
      updates `lastStartedId`; `handleTimeout` marks the last-started-unfinished node
      `error`/"timed out", reserves `cancelled` for user Stop. *(Live-fire with a real
      hang depends on stdout flush timing before the kill — needs in-app run to fully
      confirm the hung test's start registered; logic is correct.)*
- [x] **Stable-ID distinctness** — `A > works` and `B > works` stay separate nodes.
- [x] **Data-driven tests** — 3 runtime-generated `it()`s appear with results (§4.1).
- [x] **Nested lifecycle** — `bO,bI,x` order correct; `after_each` runs on throw.
- [x] **Auto-spy object chain** — `newImage():getWidth() + 5` doesn't crash (§5.2).
- [x] **Cross-API filesystem** — `love.filesystem.write` ↔ `io.open` share store (§3.3a).
- [x] **`print` capture + delimiter safety** — user `print` flows via `[[LS_OUT]]`;
      a test printing `[[LS_TEST]]{fake}` does NOT corrupt the tree (verified).
- [~] Empty/misconfigured state + settings link — built (Phase D/E); load-error →
      error node verified at engine level (Phase A). *(Visual pending.)*
- [x] **Mutual exclusion** — `runTests()` guards `!runner.isRunning && !isDebugging
      && !testRunner.isRunning`; toolbar button disabled accordingly (Phase E).
- [~] `?` Help opens `test-runner-help.md` read-only via `MarkdownDocView` —
      dispatch + bundle resource present in built app. *(Visual pending.)*
- [x] **Coverage on:** verified e2e through the real `TestLauncher` — `[[LS_COV]]`
      % + `[[LS_COVLINES]]` (absolute paths) emitted; **only the user's game code**
      (kit/bootstrap/test files excluded); a deliberately-uncovered line correctly
      reported as `miss`; executable-line based (LuaCov reporter, not `hits/max`).
      Root cause of earlier bug: LuaCov reporter resolves source relative to cwd —
      the app runs with cwd = project root (`currentDirectoryURL`), so it resolves.
      **coverage off (default):** no `runner.init()`, no `[[LS_COV]]` (§3.9).
- [~] **Clicking the %** opens the report tab — `lastReportText` captured before
      cleanup (Phase C), `onOpenReport` → `MarkdownDocView` (Phase D/E), report file
      removed with the temp launcher dir. Wired + type-checks. *(Visual pending.)*
- [x] **`love.<module>.real()`** — verified through the shipped bundle:
      `love.timer.real()` returns non-nil (genuine module); lifecycle `reset()`
      restores the double after each test (§5.1).

---

## Future — not v1

- [ ] **§9 — e2e / real-engine tests (Path 2).** Real `love` runtime via
      `LoveRunner`'s existing launch path; scripted input; assert on real frames.
      Shares the Explorer UI + result protocol; e2e tests routed to the real-`love`
      backend.
- [ ] Per-project override of folder/glob rows (currently global only).
- [x] **Editor gutter coverage** — pulled into scope and built: `[[LS_COVLINES]]`
      → `CoverageStore` → `LineNumberRulerView` draws green/red stripes per line;
      gated by its own `testRunnerGutters` toggle (default off, only shown when
      coverage is on). Lua side verified (correct hit/miss); editor stripe drawing
      type-checks (visual confirmation pending app launch — Verification).
- [ ] **Coverage UI beyond v1** — a `ReporterBase` subclass emitting a colorized
      report our viewer styles. (Overall % + clickable report + gutters now ship.)
