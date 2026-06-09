import Foundation
import Observation

// MARK: - TestRunner
//
// Runs the user's Lua tests in the bundled `love` run headless (§5.5), parses the
// structured `[[LS_TEST]]` / `[[LS_OUT]]` / `[[LS_COV]]` wire protocol (§3.5) into
// the `TestNode` tree, and exposes results to the Explorer.
//
// Discovery (the pre-run hollow tree, §5.3/§4.1) is a static parse; the run is
// authoritative (an emitted id with no node is created, §4.1).
//
// All tree mutation hops to the main actor (§4.3a).

@MainActor
@Observable
final class TestRunner {

    // MARK: Observable state
    private(set) var roots: [TestNode] = []
    private(set) var summary = TestRunSummary()
    private(set) var isRunning = false
    private(set) var lastReportText: String?     // LuaCov report, for the clickable-% tab (§3.9)
    let coverage = CoverageStore()               // per-line coverage for gutters

    // Callbacks set by the view layer
    var onConsole: ((String) -> Void)?           // user print + TAP → Console
    var onErrorJump: ((String, Int) -> Void)?    // unused here; parity with LoveRunner

    // Settings (mirrored from AppStorage by the view)
    var timeoutSeconds: Double = 30
    var coverageEnabled = false
    var echoResultsToConsole = true   // mirror per-test results into the Console (§3.7)

    // Debugger wiring (supplied by the view, for per-test debug §5.4)
    var debugServer: DebugServer?
    var breakpointManager: BreakpointManager?

    // MARK: Private
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var lineBuffer = ""                   // buffers partial lines across reads (§4.3a)
    private var nodeIndex: [String: TestNode] = [:]
    private var timeoutTimer: Timer?
    private var lastStartedId: String?            // for timeout attribution (§4.3)
    private var isDebugRun = false                // debug runs skip the timeout (breakpoints pause)
    private var scopedAccessActive = false        // security-scoped access held during a run (§Phase G)
    private var scopedRoot: URL?

    // The temp launcher dir for the current run (cleaned up on finish/stop).
    private var launcherDir: URL?

    // MARK: - Discovery (static parse, §5.3)

    /// Parse the configured test files into a provisional `TestNode` tree without
    /// executing them. Called on manual Refresh and FileWatcher changes (§4.6).
    @MainActor
    func discover(projectRoot: URL, rows: [TestFolderGlob]) {
        let files = TestDiscovery.matchingFiles(projectRoot: projectRoot, rows: rows)
        var newRoots: [TestNode] = []
        var index: [String: TestNode] = [:]
        for file in files {
            if let fileNode = TestDiscovery.parse(file: file, projectRoot: projectRoot) {
                newRoots.append(fileNode)
            }
        }
        // index every node by id for fast result correlation
        func indexAll(_ node: TestNode) {
            index[node.id] = node
            node.children.forEach(indexAll)
        }
        newRoots.forEach(indexAll)
        self.roots = newRoots
        self.nodeIndex = index
    }

    // MARK: - Run

    /// Run all tests, a suite, or a single test (filter == a node id, nil == all).
    @MainActor
    func run(projectRoot: URL, rows: [TestFolderGlob], filter: String?, debug: Bool = false) {
        guard !isRunning else { return }
        roots.forEach { $0.resetResults() }
        summary = TestRunSummary()
        lastReportText = nil
        coverage.clear()
        lineBuffer = ""
        lastStartedId = nil

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

        let dir: URL
        do {
            dir = try TestLauncher.build(projectRoot: projectRoot,
                                         kitURL: kitURL,
                                         files: files,
                                         filter: filter,
                                         debug: debug,
                                         coverage: coverageEnabled)
        } catch {
            onConsole?("Test runner: failed to prepare launcher — \(error.localizedDescription)")
            return
        }
        launcherDir = dir
        isDebugRun = debug
        launch(loveApp: loveApp, gameDir: dir, projectRoot: projectRoot)
    }

    /// Debug a single test under mobdebug (§5.4): start the DebugServer listening,
    /// then run just that test with the debug bootstrap that connects to it.
    /// Reuses `DebugServer` (not `runDebug`, which would launch the real game).
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

        // Security-scoped access to the project for the duration of the run, so the
        // spawned `love` can read the user's game (resolved via package.path) — same
        // model as Project/LoveRunner (§Phase G). Released in finishRun().
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
            isRunning = true
            startTimeout()
        } catch {
            onConsole?("Test runner: launch error — \(error.localizedDescription)")
            cleanup()
        }
    }

    // MARK: - Ingest / parse (§3.5, §4.1, §4.3a)

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
        if line.hasPrefix("[[LS_TEST]]") {
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
        let node: TestNode
        if let existing = nodeIndex[rec.id] {
            node = existing
        } else {
            // run-authoritative: an emitted id with no discovered node is created (§4.1)
            node = insertSynthetic(rec)
        }
        node.status = rec.status
        node.durationMs = rec.ms
        node.message = rec.msg.isEmpty ? nil : rec.msg
        if node.file == nil { node.file = rec.file }
        if node.line == nil { node.line = rec.line }
        lastStartedId = rec.id
        bumpSummary(rec.status, ms: rec.ms)

        // ALSO echo a human-readable result to the Console (in addition to driving
        // the Explorer tree) so there's a complete, copy-pasteable run log.
        echoToConsole(rec)
    }

    /// One readable line per result → Console; failures/errors append their message.
    /// Gated by the "echo results to console" setting (§3.7).
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
        // Build/attach a path so data-driven tests still appear (§4.1).
        let leaf = TestNode(id: rec.id, name: rec.name, kind: .test,
                            file: rec.file, line: rec.line)
        // Group under a synthetic root keyed by the file segment of the id.
        let rootKey = rec.id.components(separatedBy: " > ").first ?? rec.id
        if let root = nodeIndex[rootKey] {
            root.children.append(leaf)
        } else {
            let root = TestNode(id: rootKey, name: rootKey, kind: .suite, children: [leaf])
            roots.append(root)
            nodeIndex[rootKey] = root
        }
        nodeIndex[rec.id] = leaf
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

    // MARK: - Timeout (§4.3)

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
        // Attribute the kill to the last-started-unfinished test (§4.3).
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
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        finishRun()
    }

    @MainActor
    private func finishRun() {
        guard isRunning || process != nil else { return }
        timeoutTimer?.invalidate(); timeoutTimer = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        stdoutPipe = nil
        isRunning = false
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
        // Release security-scoped access held for the run (§Phase G).
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
