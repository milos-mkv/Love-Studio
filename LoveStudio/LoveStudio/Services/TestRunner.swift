import Foundation
import Observation

// Runs the user's Lua tests in the bundled `love` binary, parses the wire protocol
// it emits ([[LS_TEST]] / [[LS_OUT]] / [[LS_COV]] / [[LS_TREE]]) into the TestNode
// tree, and exposes results to the Explorer. The run is authoritative: an emitted
// id with no matching node creates one.
@MainActor
@Observable
final class TestRunner {

    private(set) var roots: [TestNode] = []
    private(set) var summary = TestRunSummary()
    private(set) var isRunning = false
    private(set) var lastReportText: String?     // LuaCov report shown in the clickable-% tab
    let coverage = CoverageStore()

    var onConsole: ((String) -> Void)?
    var onErrorJump: ((String, Int) -> Void)?    // parity with LoveRunner; unused here

    // Mirrored from AppStorage by the view.
    var timeoutSeconds: Double = 30
    var coverageEnabled = false
    var coverageExcludes: [String] = []
    var echoResultsToConsole = true

    // Supplied by the view for per-test debugging.
    var debugServer: DebugServer?
    var breakpointManager: BreakpointManager?

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var lineBuffer = ""                   // partial lines across reads
    private var nodeIndex: [String: TestNode] = [:]
    private var timeoutTimer: Timer?
    private var lastStartedId: String?            // for timeout attribution
    private var isDebugRun = false                // debug runs skip the timeout (breakpoints pause)
    private var isCollecting = false              // discovery pass, not a test run
    private var runTreeRebuilt = false            // has this run rebuilt the tree from results yet?
    private var isFilteredRun = false             // single-test/suite run — don't wipe the tree
    private var preservedExpanded = Set<String>() // expansion state carried across a run rebuild
    private var hadPriorTree = false
    private var scopedAccessActive = false
    private var scopedRoot: URL?
    private var launcherDir: URL?                 // temp dir for the current run; cleaned up on finish

    // MARK: - Discovery

    // Build the test tree via a headless collect pass: Lua loads the test files and
    // emits the tree as [[LS_TREE]] lines, so it matches exactly what will run.
    // Called on manual Refresh and FileWatcher changes.
    @MainActor
    func discover(projectRoot: URL, rows: [TestFolderGlob]) {
        guard !isRunning else { return }

        let files = TestDiscovery.matchingFiles(projectRoot: projectRoot, rows: rows)
        guard !files.isEmpty else {
            roots = []; nodeIndex = [:]
            return
        }
        guard let loveApp = LoveRuntimeResolver.bundledLoveAppURL(),
              let kitURL = Bundle.main.url(forResource: "TestKit", withExtension: "bundle")
                        ?? Bundle.main.resourceURL?.appendingPathComponent("TestKit.bundle") else {
            onConsole?("Test runner: could not locate love runtime or TestKit.")
            return
        }

        // preserve expansion across the rebuild; default-open suites on first discovery
        preservedExpanded = []
        for (id, node) in nodeIndex where node.isExpanded { preservedExpanded.insert(id) }
        hadPriorTree = !nodeIndex.isEmpty
        roots = []
        nodeIndex = [:]
        lineBuffer = ""

        let dir: URL
        do {
            dir = try TestLauncher.build(projectRoot: projectRoot, kitURL: kitURL,
                                         files: files, filter: nil, debug: false,
                                         coverage: false, collect: true)
        } catch {
            onConsole?("Test runner: failed to prepare discovery — \(error.localizedDescription)")
            return
        }
        launcherDir = dir
        isCollecting = true
        isDebugRun = false
        launch(loveApp: loveApp, gameDir: dir, projectRoot: projectRoot)
    }

    // MARK: - Run

    // Run all tests, a suite, or a single test (filter == a node id, nil == all).
    @MainActor
    func run(projectRoot: URL, rows: [TestFolderGlob], filter: String?, debug: Bool = false) {
        guard !isRunning else { return }
        // Surface the relevant bottom panel: Debug for a debug run, Console otherwise.
        NotificationCenter.default.post(name: .testRunStarted, object: nil,
                                        userInfo: ["debug": debug])
        isFilteredRun = (filter != nil)
        lineBuffer = ""
        lastStartedId = nil
        preservedExpanded = []

        // A FULL run resets the summary and clears coverage (it will recompute both).
        // A FILTERED run does neither: it shows only that test's result, and keeps
        // the last full run's coverage % / report rather than blanking them.
        if !isFilteredRun {
            summary = TestRunSummary()
            lastReportText = nil
            coverage.clear()
        }

        // A FULL run (no filter) is authoritative — it rebuilds the tree from the
        // emitted results (so the static-parse nesting can't create duplicates).
        // A FILTERED run must NOT wipe the tree, or every other test would vanish.
        runTreeRebuilt = isFilteredRun   // filtered → skip the rebuild-on-first-result
        if isFilteredRun {
            // The other (not-run-this-time) tests go NEUTRAL; only the targeted
            // node(s) will get a fresh result from this run.
            for (_, node) in nodeIndex where node.kind == .test {
                node.status = .notRun
                node.durationMs = nil
                node.message = nil
            }
        } else {
            roots.forEach { $0.resetResults() }   // full run: all back to neutral
        }

        guard let loveApp = LoveRuntimeResolver.bundledLoveAppURL(),
              let kitURL = Bundle.main.url(forResource: "TestKit", withExtension: "bundle")
                        ?? Bundle.main.resourceURL?.appendingPathComponent("TestKit.bundle") else {
            onConsole?("Test runner: could not locate love runtime or TestKit.")
            return
        }

        let files = TestDiscovery.matchingFiles(projectRoot: projectRoot, rows: rows)
        guard !files.isEmpty else {
            onConsole?("Test runner: no test files matched the configured folders/globs.")
            return
        }

        // Coverage only makes sense for a FULL run — a single-test run would report
        // a misleading whole-project %. Skip it for filtered runs (and keep the last
        // full-run coverage shown instead of overwriting it with a partial number).
        let coverageForRun = coverageEnabled && !isFilteredRun

        let dir: URL
        do {
            dir = try TestLauncher.build(projectRoot: projectRoot,
                                         kitURL: kitURL,
                                         files: files,
                                         filter: filter,
                                         debug: debug,
                                         coverage: coverageForRun,
                                         coverageExcludes: coverageExcludes)
        } catch {
            onConsole?("Test runner: failed to prepare launcher — \(error.localizedDescription)")
            return
        }
        launcherDir = dir
        isDebugRun = debug
        launch(loveApp: loveApp, gameDir: dir, projectRoot: projectRoot)
    }

    // Debug a single test under mobdebug: start the DebugServer listening, then run
    // just that test with the debug bootstrap that connects to it.
    @MainActor
    func debug(testId: String, projectRoot: URL, rows: [TestFolderGlob]) {
        guard !isRunning else { return }
        guard let server = debugServer, let bpm = breakpointManager else {
            onConsole?("Test runner: debugger not available.")
            return
        }
        server.configure(projectRootURL: projectRoot, lineOffsetFile: nil, lineOffset: 0)
        server.start(breakpointManager: bpm)   // listen on :8172 before the test connects
        run(projectRoot: projectRoot, rows: rows, filter: testId, debug: true)
    }

    @MainActor
    func stop() {
        guard isRunning else { return }
        markUnfinishedAsCancelled()
        terminate()
    }

    // MARK: - Launch (headless love)

    @MainActor
    private func launch(loveApp: URL, gameDir: URL, projectRoot: URL) {
        let exec = LoveRuntimeResolver.executableURL(in: loveApp)
        guard FileManager.default.isExecutableFile(atPath: exec.path) else {
            onConsole?("Test runner: love executable not found.")
            cleanup()
            return
        }

        // Hold security-scoped access for the run so the spawned `love` can read the
        // user's project. Released in finishRun().
        scopedAccessActive = projectRoot.startAccessingSecurityScopedResource()
        scopedRoot = projectRoot

        let p = Process()
        p.executableURL = exec
        p.arguments = [gameDir.path]
        p.currentDirectoryURL = projectRoot

        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe   // love prints Lua errors to stderr; fold in

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.ingest(s) }
        }

        p.terminationHandler = { [weak self, weak p] _ in
            Task { @MainActor [weak self, weak p] in
                guard let self, self.process === p else { return }
                self.finishRun()
            }
        }

        do {
            try p.run()
            process = p
            stdoutPipe = outPipe
            // `isRunning` drives the run UI and the auto-switch to the Tests panel.
            // The discovery pass is background work, so it leaves isRunning false
            // (tracking its lifecycle via isCollecting) to avoid stealing focus.
            if !isCollecting { isRunning = true; startTimeout() }
        } catch {
            onConsole?("Test runner: launch error — \(error.localizedDescription)")
            cleanup()
        }
    }

    // MARK: - Ingest / parse

    @MainActor
    private func ingest(_ chunk: String) {
        lineBuffer += chunk
        while let nl = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<nl])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: nl)...])
            handle(line: line)
        }
    }

    @MainActor
    private func handle(line: String) {
        if line.hasPrefix("[[LS_TREE]]") {
            if let rec = WireParser.parseTree(line) { applyTreeRecord(rec) }
        } else if line.hasPrefix("[[LS_TEST]]") {
            if let rec = WireParser.parseTest(line) { applyResult(rec) }
        } else if line.hasPrefix("[[LS_OUT]]") {
            if let out = WireParser.parseOut(line) { onConsole?(out.text) }
        } else if line.hasPrefix("[[LS_COVLINES]]") {
            if let cl = WireParser.parseCoverageLines(line) {
                coverage.set(file: cl.file, hit: cl.hit, miss: cl.miss)
            }
        } else if line.hasPrefix("[[LS_COV]]") {
            if let pct = WireParser.parseCoverage(line) { summary.coveragePercent = pct }
        } else {
            // unprefixed → TAP / love diagnostics → Console
            onConsole?(line)
        }
    }

    @MainActor
    private func applyResult(_ rec: WireParser.TestRecord) {
        // The run is authoritative: on the first result, rebuild the tree from the
        // emitted ids so the displayed tree always matches what actually ran.
        if !runTreeRebuilt {
            runTreeRebuilt = true
            // preserve open suites across the rebuild; hadPriorTree distinguishes a
            // first run (default-open) from the user having collapsed everything.
            hadPriorTree = !nodeIndex.isEmpty
            for (id, node) in nodeIndex where node.isExpanded { preservedExpanded.insert(id) }
            roots = []
            nodeIndex = [:]
        }
        let node: TestNode
        if let existing = nodeIndex[rec.id] {
            node = existing
        } else {
            node = insertSynthetic(rec)
        }
        node.status = rec.status
        node.durationMs = rec.ms
        node.message = rec.msg.isEmpty ? nil : rec.msg
        if node.file == nil { node.file = rec.file }
        if node.line == nil { node.line = rec.line }
        lastStartedId = rec.id
        bumpSummary(rec.status, ms: rec.ms)

        echoToConsole(rec)
    }

    // One readable line per result to the Console (failures/errors append their
    // message), gated by the "echo results to console" setting.
    @MainActor
    private func echoToConsole(_ rec: WireParser.TestRecord) {
        guard echoResultsToConsole else { return }
        let glyph: String
        switch rec.status {
        case .passed:  glyph = "✓"
        case .failed:  glyph = "✗"
        case .error:   glyph = "⚠"
        case .skipped: glyph = "–"
        default:       glyph = "•"
        }
        let dur = rec.ms > 0 ? " (\(rec.ms)ms)" : ""
        onConsole?("\(glyph) \(rec.id)\(dur)")
        if !rec.msg.isEmpty {
            // indent multi-line messages so they read as detail under the result
            let indented = rec.msg
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "    \($0)" }
                .joined(separator: "\n")
            onConsole?(indented)
        }
    }

    @MainActor
    private func insertSynthetic(_ rec: WireParser.TestRecord) -> TestNode {
        return ensureTestNode(id: rec.id, name: rec.name, file: rec.file, line: rec.line)
    }

    // Apply one [[LS_TREE]] record from discovery: ensure the suite path and leaf
    // exist (structure only, no status).
    @MainActor
    private func applyTreeRecord(_ rec: WireParser.TreeRecord) {
        _ = ensureTestNode(id: rec.id, name: rec.name, file: rec.file, line: rec.line)
    }

    // Fetch or build the test node for `id`, creating any missing suite ancestors
    // from the id's " > " segments.
    @MainActor
    private func ensureTestNode(id: String, name: String, file: String, line: Int) -> TestNode {
        if let existing = nodeIndex[id] { return existing }
        let segments = id.components(separatedBy: " > ")
        guard segments.count >= 1 else {
            let leaf = TestNode(id: id, name: name, kind: .test, file: file, line: line)
            roots.append(leaf); nodeIndex[id] = leaf; return leaf
        }
        var parent: TestNode?
        var accumulatedID = ""
        for (i, seg) in segments.enumerated() {
            accumulatedID = accumulatedID.isEmpty ? seg : "\(accumulatedID) > \(seg)"
            let isLeaf = (i == segments.count - 1)
            if isLeaf {
                let leaf = TestNode(id: id, name: name, kind: .test, file: file, line: line)
                if let parent { parent.children.append(leaf) } else { roots.append(leaf) }
                nodeIndex[id] = leaf
                return leaf
            }
            if let existing = nodeIndex[accumulatedID] {
                parent = existing
            } else {
                let suite = TestNode(id: accumulatedID, name: seg, kind: .suite, file: file)
                suite.isExpanded = preservedExpanded.contains(accumulatedID) || !hadPriorTree
                if let parent { parent.children.append(suite) } else { roots.append(suite) }
                nodeIndex[accumulatedID] = suite
                parent = suite
            }
        }
        let leaf = TestNode(id: id, name: name, kind: .test, file: file, line: line)
        nodeIndex[id] = leaf
        return leaf
    }

    private func bumpSummary(_ status: TestStatus, ms: Int) {
        summary.totalMs += ms
        switch status {
        case .passed:  summary.passed += 1
        case .failed:  summary.failed += 1
        case .error:   summary.error += 1
        case .skipped: summary.skipped += 1
        default: break
        }
    }

    // MARK: - Timeout

    @MainActor
    private func startTimeout() {
        timeoutTimer?.invalidate()
        guard !isDebugRun else { return }   // breakpoints pause indefinitely; no timeout while debugging
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleTimeout() }
        }
    }

    @MainActor
    private func handleTimeout() {
        guard isRunning else { return }
        // Attribute the kill to the last-started, unfinished test.
        if let id = lastStartedId, let node = nodeIndex[id], node.status == .running || node.status == .notRun {
            node.status = .error
            node.message = "Timed out after \(Int(timeoutSeconds))s"
            summary.error += 1
        }
        onConsole?("Test runner: timed out after \(Int(timeoutSeconds))s — process killed.")
        terminate()
    }

    @MainActor
    private func markUnfinishedAsCancelled() {
        for (_, node) in nodeIndex where node.kind == .test && (node.status == .running || node.status == .notRun) {
            node.status = .cancelled
        }
    }

    // MARK: - Teardown

    @MainActor
    private func terminate() {
        // Stop the debug server first: a process paused at a breakpoint is blocked in
        // mobdebug's socket receive and won't die on terminate() until that unblocks.
        if isDebugRun { debugServer?.stop(); isDebugRun = false }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        finishRun(drainPipe: false)
    }

    @MainActor
    private func finishRun(drainPipe: Bool = true) {
        guard isRunning || process != nil else { return }
        timeoutTimer?.invalidate(); timeoutTimer = nil
        // On a normal finish, drain the pipe to catch the final chunk (which carries
        // [[LS_COV]]) that the async readabilityHandler may not have delivered yet.
        // Skipped on a force-stop: `availableData` blocks until EOF, and a process
        // paused at a breakpoint may not have died yet, which would hang the UI.
        if drainPipe, let fh = stdoutPipe?.fileHandleForReading {
            fh.readabilityHandler = nil
            let remaining = fh.availableData
            if !remaining.isEmpty, let s = String(data: remaining, encoding: .utf8) {
                ingest(s)
            }
            if !lineBuffer.isEmpty {
                let leftover = lineBuffer
                lineBuffer = ""
                handle(line: leftover)
            }
        } else {
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        }
        process = nil
        stdoutPipe = nil
        isRunning = false

        // A discovery (collect) pass only built the tree — no results/coverage.
        if isCollecting {
            isCollecting = false
            if scopedAccessActive, let root = scopedRoot {
                root.stopAccessingSecurityScopedResource()
            }
            scopedAccessActive = false
            scopedRoot = nil
            cleanup()
            return
        }

        // Read the coverage report (if any) before cleaning the launcher dir.
        if coverageEnabled, let dir = launcherDir {
            let report = dir.appendingPathComponent("luacov.report.out")
            lastReportText = try? String(contentsOf: report, encoding: .utf8)
        }
        // Tear down the debug server after a debug run.
        if isDebugRun {
            debugServer?.stop()
            isDebugRun = false
        }
        if scopedAccessActive, let root = scopedRoot {
            root.stopAccessingSecurityScopedResource()
        }
        scopedAccessActive = false
        scopedRoot = nil
        cleanup()
    }

    private func cleanup() {
        if let dir = launcherDir { try? FileManager.default.removeItem(at: dir) }
        launcherDir = nil
    }
}
