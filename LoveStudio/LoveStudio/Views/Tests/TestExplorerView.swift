import SwiftUI
import AppKit

// The Test Explorer: a header toolbar plus a tree of suites/tests with status icons,
// click-to-source, per-test run/debug, failure detail on expand, and a clickable
// coverage %. Lives in the left sidebar's `tests` tab.
struct TestExplorerView: View {
    @Bindable var runner: TestRunner
    let projectRoot: URL?
    let rows: [TestFolderGlob]
    let canRun: Bool                  // false while the game is running/debugging (C9)

    var onJump: ((String, Int) -> Void)?     // click a test → open file at line
    var onOpenReport: ((String) -> Void)?    // click coverage % → open report tab
    var onOpenSettings: (() -> Void)?        // empty-state link → Settings → Runner (B5)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if runner.isRunning {
                toolButton("stop.fill", "Stop", color: .red) { runner.stop() }
            } else {
                toolButton("play.fill", "Run All", color: .green) { runAll() }
                    .disabled(!canRun || projectRoot == nil)
            }
            toolButton("arrow.clockwise", "Refresh") { discover() }
                .disabled(projectRoot == nil)
            // One button; icon reflects the action it will perform. When anything is
            // expanded → shows "collapse all"; when all collapsed → shows "expand all".
            toolButton(allExpanded ? "chevron.up" : "chevron.down",
                       allExpanded ? "Collapse All" : "Expand All") {
                if allExpanded { collapseAll() } else { expandAll() }
            }

            Spacer()

            summaryView

            if let url = Bundle.main.url(forResource: "test-runner-help", withExtension: "md") {
                toolButton("questionmark.circle", "Help") { onOpenReport?(url.path) }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.bar)
    }

    @ViewBuilder
    private var summaryView: some View {
        let s = runner.summary
        if s.total > 0 || runner.isRunning {
            HStack(spacing: 8) {
                // Only failures/errors are worth a count here — the per-suite
                // "(passed/total)" badges already show passes.
                if s.failed > 0 { countPill("\(s.failed)", .red) }
                if s.error > 0  { countPill("\(s.error)", .orange) }

                // Coverage: a pill button (secondary color) when a report exists.
                if let pct = s.coveragePercent {
                    let hasReport = !(runner.lastReportText ?? "").isEmpty
                    Button {
                        if let r = runner.lastReportText, !r.isEmpty { onOpenReport?(reportTempPath(r)) }
                    } label: {
                        Text("Coverage \(String(format: "%.0f%%", pct))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .help(hasReport ? "Open coverage report" : "Run all tests to generate a coverage report")
                    .disabled(!hasReport)
                    .onHover { inside in
                        if inside && hasReport { NSCursor.pointingHand.set() }
                        else { NSCursor.arrow.set() }
                    }
                }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if projectRoot == nil {
            placeholder("Open a project to run tests.")
        } else if runner.roots.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(runner.roots) { node in
                        TestNodeRow(node: node, depth: 0,
                                    isRunning: runner.isRunning, canRun: canRun,
                                    onJump: onJump,
                                    onRunOne: { id in runOne(id) },
                                    onDebugOne: { id in debugOne(id) })
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "flask").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(emptyTitle).font(.subheadline).foregroundStyle(.secondary)
            if !emptyDetail.isEmpty {
                Text(emptyDetail)
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            // SettingsLink is the official macOS 14+ way to open the Settings scene.
            SettingsLink {
                Text(rowsConfigured ? "Edit test folders…" : "Configure test folders…")
            }
            .buttonStyle(.link).font(.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Empty-state messaging
    //
    // Distinguish "no folders set up" from "folders set, but nothing matched" so we
    // don't tell a user who already configured folders to go configure them.

    private var rowsConfigured: Bool {
        rows.contains { !$0.folder.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // Configured folders that don't exist on disk (relative to the project root).
    private var missingFolders: [String] {
        guard let root = projectRoot else { return [] }
        var missing: [String] = []
        for row in rows {
            let f = row.folder.trimmingCharacters(in: .whitespaces)
            guard !f.isEmpty else { continue }
            var isDir: ObjCBool = false
            let path = root.appendingPathComponent(f).path
            if !(FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue) {
                missing.append(f)
            }
        }
        return missing
    }

    private var emptyTitle: String {
        if !rowsConfigured { return "No test folders configured." }
        if !missingFolders.isEmpty { return "Test folder not found." }
        return "No tests found."
    }

    private var emptyDetail: String {
        if !rowsConfigured { return "" }
        if !missingFolders.isEmpty {
            return "Couldn't find: \(missingFolders.joined(separator: ", "))"
        }
        // folders exist but nothing matched the glob
        let globs = rows.map { $0.glob }.filter { !$0.isEmpty }
        return "No files matched \(globs.joined(separator: ", ")). Check your test files and glob."
    }

    // MARK: Actions

    private func discover() {
        guard let root = projectRoot else { return }
        runner.discover(projectRoot: root, rows: rows)
    }
    private func runAll() {
        guard let root = projectRoot else { return }
        if runner.roots.isEmpty { runner.discover(projectRoot: root, rows: rows) }
        runner.run(projectRoot: root, rows: rows, filter: nil)
    }
    private func runOne(_ id: String) {
        guard let root = projectRoot, canRun else { return }
        runner.run(projectRoot: root, rows: rows, filter: id)
    }
    private func debugOne(_ id: String) {
        guard let root = projectRoot, canRun else { return }
        runner.debug(testId: id, projectRoot: root, rows: rows)
    }
    // True if any suite is expanded, so the button offers "collapse".
    private var allExpanded: Bool {
        func anyExpanded(_ n: TestNode) -> Bool {
            (n.kind == .suite && n.isExpanded) || n.children.contains(where: anyExpanded)
        }
        return runner.roots.contains(where: anyExpanded)
    }

    private func setAllExpanded(_ expanded: Bool) {
        func set(_ n: TestNode) {
            if n.kind == .suite { n.isExpanded = expanded }
            n.children.forEach(set)
        }
        runner.roots.forEach(set)
    }
    private func expandAll()   { setAllExpanded(true) }
    private func collapseAll() { setAllExpanded(false) }

    // Persist the coverage report to a temp file so it can open as a tab. The Lua
    // side already wrote it as Markdown with `lsjump://` links — write as-is (no
    // code fence, which would suppress the links).
    private func reportTempPath(_ text: String) -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coverage-report.md")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: Small components

    private func toolButton(_ icon: String, _ help: String, color: Color = .secondary,
                            _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    private func countPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
    }

    private func coverageColor(_ pct: Double) -> Color {
        pct >= 80 ? .green : (pct >= 50 ? .orange : .red)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TestNodeRow

// One row in the tree: status icon + name, disclosure for suites, hover run/debug
// for leaves, and the failure message on expand.
private struct TestNodeRow: View {
    @Bindable var node: TestNode
    let depth: Int
    let isRunning: Bool
    let canRun: Bool
    var onJump: ((String, Int) -> Void)?
    var onRunOne: ((String) -> Void)?
    var onDebugOne: ((String) -> Void)?

    @State private var hovering = false

    private var isSuite: Bool { node.kind == .suite }
    private var status: TestStatus { node.effectiveStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if node.isExpanded {
                if isSuite {
                    ForEach(node.children) { child in
                        TestNodeRow(node: child, depth: depth + 1,
                                    isRunning: isRunning, canRun: canRun,
                                    onJump: onJump, onRunOne: onRunOne, onDebugOne: onDebugOne)
                    }
                } else if node.hasDetail, let msg = node.message {
                    Text(msg)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                        .padding(.leading, CGFloat(depth + 1) * 14 + 28)
                        .padding(.trailing, 10)
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(depth) * 14)

            // disclosure chevron (suites, or failed leaves with detail) — a real
            // Button so the toggle reliably fires (a row-wide onTapGesture can be
            // swallowed by SwiftUI hit-testing).
            if isSuite || node.hasDetail {
                // Plain image — the toggle happens on the row's onTapGesture (a
                // nested Button gets swallowed by the row's contentShape/tap).
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary).frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }

            // status icon (spinner while running)
            if status == .running {
                ProgressView().scaleEffect(0.4).frame(width: 14, height: 14)
            } else {
                Image(systemName: status.iconName)
                    .font(.system(size: 11)).foregroundStyle(status.tint)
                    .frame(width: 14)
            }

            Text(node.name).font(.system(size: 12)).lineLimit(1)

            // Suite/file rows show "(passed/total)".
            if isSuite {
                Text("(\(node.passedCount)/\(node.testCount))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let ms = node.durationMs, ms > 0, !isSuite {
                Text("\(ms)ms").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }

            Spacer()

            // hover actions on leaves
            if !isSuite && hovering && !isRunning && canRun {
                Button { onRunOne?(node.id) } label: {
                    Image(systemName: "play.fill").font(.system(size: 9))
                }.buttonStyle(.plain).foregroundStyle(.green).help("Run test")
                Button { onDebugOne?(node.id) } label: {
                    Image(systemName: "ant.fill").font(.system(size: 9))
                }.buttonStyle(.plain).foregroundStyle(.orange).help("Debug test")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            // Suites and detail-bearing leaves toggle expansion; plain leaves jump.
            if isSuite || node.hasDetail {
                node.isExpanded.toggle()
            } else if let file = node.file, let line = node.line {
                onJump?(file, line)
            }
        }
    }
}
