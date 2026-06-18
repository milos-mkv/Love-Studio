import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StudioView: View {

    let projectURL: URL

    @State private var project: Project
    @State private var openTabs: [ProjectItem] = []
    @State private var activeTab: ProjectItem? = nil
    @State private var untitledURLs: Set<URL> = []
    @State private var untitledCount = 0
    @State private var runner       = LoveRunner()
    @State private var testRunner   = TestRunner()
    @State private var gitService   = GitStatusService()
    @State private var debugServer  = DebugServer()
    @State private var lspClient    = LSPClientService()
    @State private var breakpoints  = BreakpointManager()
    @State private var jumpToLine   : Int? = nil
    @State private var isDebugging  = false
    @State private var pausedFile    : String? = nil
    @State private var pausedLine    : Int? = nil
    @State private var pausedFileURL : URL?   = nil
    @State private var fileWatcher  : FileWatcher? = nil
    @State private var pendingTestDiscovery = false   // queued re-discovery (§4.3a)
    @State private var sidebarSelection: SidebarTab = .files

    @AppStorage("runnerHotReload")          private var runnerHotReload: Bool   = true
    @AppStorage("runnerHotReloadDelay")     private var runnerHotReloadDelay: Double = 0.5
    @AppStorage("runnerClearConsole")       private var runnerClearConsole: Bool = true
    @AppStorage("runnerMaxLines")           private var runnerMaxLines: Int     = 2000
    @AppStorage("runnerDebugPort")          private var runnerDebugPort: Int    = 8172
    @AppStorage("editorAnnotationsEnabled") private var annotationsEnabled: Bool = false

    // Test runner settings (§3.7)
    @AppStorage("testRunnerEnabled")  private var testRunnerEnabled: Bool   = true
    @AppStorage("testRunnerTimeout")  private var testRunnerTimeout: Double = 30
    @AppStorage("testRunnerCoverage") private var testRunnerCoverage: Bool  = false
    @AppStorage("testRunnerFolders")  private var testRunnerFoldersJSON: String = ""
    @AppStorage("testRunnerConsole")  private var testRunnerConsole: Bool  = true
    @AppStorage("testRunnerGutters")  private var testRunnerGutters: Bool  = false
    @AppStorage("testRunnerCoverageExcludes") private var testRunnerCoverageExcludes: String = ""

    init(projectURL: URL) {
        self.projectURL = projectURL
        self._project = State(initialValue: Project(rootURL: projectURL))
    }

    private var sidebar: some View {
        SidebarView(project: project, gitService: gitService,
                    selectedTab: $sidebarSelection,
                    testRunner: testRunner,
                    testRunnerEnabled: testRunnerEnabled,
                    testRows: testRows,
                    canRunTests: !runner.isRunning && !isDebugging,
                    onOpen: openFile, onFileURLChanged: fileURLChanged,
                    onJump: { url, line in
                        openFile(ProjectItem(url: url, isFolder: false))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { jumpToLine = line }
                    },
                    onOpenDoc: { path in
                        openFile(ProjectItem(url: URL(fileURLWithPath: path), isFolder: false))
                    })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            EditorAreaView(openTabs: $openTabs, activeTab: $activeTab,
                           untitledURLs: $untitledURLs,
                           projectURL: projectURL,
                           worktreeRefreshToken: gitService.worktreeChangeToken,
                           onFileURLChanged: fileURLChanged,
                           onFileSaved: { url in
                               if url.path.hasPrefix(projectURL.path) {
                                   project.refresh()
                               }
                           },
                           runner: runner,
                           jumpToLine: $jumpToLine,
                           breakpoints: breakpoints,
                           pausedFile: pausedFile,
                           pausedLine: pausedLine,
                           pausedFileURL: pausedFileURL,
                           debugServer: debugServer,
                           isDebugging: isDebugging,
                           gitService: gitService,
                           lspClient: lspClient,
                           onJump: { file, line in
                               guard let fileURL = findFile(named: file) else { return }
                               if activeTab?.url != fileURL {
                                   openFile(ProjectItem(url: fileURL, isFolder: false))
                               }
                               DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { jumpToLine = line }
                           },
                           coverage: testRunner.coverage,
                           coverageGutters: testRunnerEnabled && testRunnerCoverage && testRunnerGutters)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 0.5)
                }
        }
        .toolbar { StudioToolbar(projectURL: projectURL, runner: runner,
                                 debugServer: debugServer, isDebugging: isDebugging,
                                 onDebug: startDebug, onStopDebug: stopDebug,
                                 testRunner: testRunner,
                                 testRunnerEnabled: testRunnerEnabled,
                                 testRows: testRows,
                                 onRunTests: runTests) }
        .environment(runner)
        .navigationTitle("")
        .background(
            Button("") { createNewTab() }
                .keyboardShortcut("n", modifiers: .command)
                .hidden()
        )
        .task { project.load() }
        .onChange(of: gitService.worktreeChangeToken) { _, _ in
            project.refresh()
        }
        .onAppear {
            gitService.attach(to: projectURL)
            // Refresh the LSP definition files on open so they stay current.
            if annotationsEnabled { try? TemplateService.shared.writeLSPFiles(at: projectURL) }
            lspClient.mode = annotationsEnabled ? .luaCATS : .none
            lspClient.attach(to: projectURL)
            setupDebugWiring()
            let watcher = FileWatcher(url: projectURL)
            watcher.onChange = {
                project.refresh()
                // Re-discover tests on file changes (§4.6) — but suppress while a
                // run is in flight (§4.3a); queue it to run on completion.
                guard testRunnerEnabled else { return }
                if testRunner.isRunning {
                    pendingTestDiscovery = true
                } else {
                    testRunner.discover(projectRoot: projectURL, rows: testRows)
                }
            }
            watcher.start()
            fileWatcher = watcher
            runner.onErrorJump = { [self] fileName, lineNumber in
                guard let fileURL = findFile(named: fileName) else { return }
                openFile(ProjectItem(url: fileURL, isFolder: false))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    jumpToLine = lineNumber
                }
            }
            applyRunnerSettings()
            applyTestRunnerSettings()
            // Console output from tests → the bottom-panel console.
            testRunner.onConsole = { line in runner.log(line, kind: .stdout) }
            testRunner.debugServer = debugServer
            testRunner.breakpointManager = breakpoints
            // Initial discovery so the Explorer shows a tree before any run.
            if testRunnerEnabled { testRunner.discover(projectRoot: projectURL, rows: testRows) }
        }
        .modifier(TestRunnerObservers(
            timeout: testRunnerTimeout, coverage: testRunnerCoverage,
            console: testRunnerConsole, foldersJSON: testRunnerFoldersJSON,
            covExcludes: testRunnerCoverageExcludes,
            enabled: testRunnerEnabled, isRunning: testRunner.isRunning,
            applySettings: applyTestRunnerSettings,
            rediscover: { if testRunnerEnabled { testRunner.discover(projectRoot: projectURL, rows: testRows) } },
            onRunStart: { sidebarSelection = .tests },
            onRunFinish: {
                if pendingTestDiscovery {
                    pendingTestDiscovery = false
                    testRunner.discover(projectRoot: projectURL, rows: testRows)
                }
            }))
        .onChange(of: runnerHotReload)      { _, _ in applyRunnerSettings() }
        .onChange(of: runnerHotReloadDelay) { _, _ in applyRunnerSettings() }
        .onChange(of: runnerClearConsole)   { _, _ in applyRunnerSettings() }
        .onChange(of: runnerMaxLines)       { _, _ in applyRunnerSettings() }
        .onChange(of: runnerDebugPort)      { _, _ in applyRunnerSettings() }
        .onChange(of: annotationsEnabled) { _, enabled in
            if enabled {
                try? TemplateService.shared.writeLSPFiles(at: projectURL)
                lspClient.mode = .luaCATS
                lspClient.attach(to: projectURL)
            } else {
                TemplateService.shared.removeLSPFiles(at: projectURL)
                lspClient.mode = .none
                lspClient.detach()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .restartLanguageServer)) { _ in
            lspClient.restart()
        }
        .onReceive(NotificationCenter.default.publisher(for: .diagnosticSeveritiesChanged)) { _ in
            // Rewrite .luarc.json with the new severities and restart so the
            // server re-reads its config.
            TemplateService.shared.rewriteLuarc(at: projectURL)
            lspClient.restart()
        }
        .onDisappear {
            fileWatcher?.stop()
            fileWatcher = nil
            lspClient.detach()
        }
    }

    private func openFile(_ item: ProjectItem) {
        // If a tab for this URL is already open, switch to it instead of adding a duplicate
        if let existing = openTabs.first(where: { $0.url == item.url }) {
            activeTab = existing
        } else {
            openTabs.append(item)
            activeTab = item
        }
    }

    private func createNewTab() {
        untitledCount += 1
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Untitled-\(untitledCount)")
        let item = ProjectItem(url: tempURL, isFolder: false)
        untitledURLs.insert(tempURL)
        openTabs.append(item)
        activeTab = item
    }

    private func setupDebugWiring() {
        breakpoints.onAdd    = { [self] file, line in debugServer.addBreakpoint(file: file, line: line) }
        breakpoints.onRemove = { [self] file, line in debugServer.removeBreakpoint(file: file, line: line) }

        debugServer.onLog = { [self] msg in
            runner.log(msg)
        }

        debugServer.onPaused = { [self] file, line in
            pausedFile = file
            pausedLine = line
            guard let fileURL = findFile(named: file) else { return }
            pausedFileURL = fileURL
            if activeTab?.url != fileURL {
                openFile(ProjectItem(url: fileURL, isFolder: false))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { jumpToLine = line }
            } else {
                jumpToLine = line
            }
        }

        debugServer.onResumed = { [self] in
            pausedFile    = nil
            pausedLine    = nil
            pausedFileURL = nil
        }

        debugServer.onDisconnected = { [self] in
            if isDebugging { stopDebug() }
        }

        runner.onTerminate = { [self] in
            if isDebugging { stopDebug() }
        }
    }

    private func startDebug() {
        guard let loveURL = LoveRuntimeResolver.resolve(preferredExternalURL: nil, preferBundled: true) else { return }
        isDebugging = true
        debugServer.configure(projectRootURL: projectURL, lineOffsetFile: nil, lineOffset: 0)
        debugServer.start(breakpointManager: breakpoints)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            runner.runDebug(projectURL: projectURL, loveAppURL: loveURL)
        }
    }

    private func stopDebug() {
        runner.stop()
        runner.restoreDebugRuntime(in: projectURL)
        debugServer.stop()
        isDebugging   = false
        pausedFile    = nil
        pausedLine    = nil
        pausedFileURL = nil
    }

    private func findFile(named name: String) -> URL? {
        // Normalize: strip leading "./" so "player.lua" and "./player.lua" both work
        let normalized = name.hasPrefix("./") ? String(name.dropFirst(2)) : name

        // If name contains a path separator, try it as a path relative to project root first
        if normalized.contains("/") {
            let candidate = projectURL.appendingPathComponent(normalized).standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }

        // Fall back to searching the whole tree by last path component
        let target = (normalized as NSString).lastPathComponent
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return enumerator.compactMap { $0 as? URL }
            .first { $0.lastPathComponent == target }
    }

    private func applyRunnerSettings() {
        runner.hotReloadEnabled = runnerHotReload
        runner.hotReloadDelay   = runnerHotReloadDelay
        runner.clearOnRun       = runnerClearConsole
        runner.maxLines         = runnerMaxLines
        runner.debugPort        = runnerDebugPort
    }

    private func applyTestRunnerSettings() {
        testRunner.timeoutSeconds       = testRunnerTimeout
        testRunner.coverageEnabled      = testRunnerCoverage
        testRunner.echoResultsToConsole = testRunnerConsole
        // Decode the exclude-glob rows and convert each glob → a LuaCov Lua pattern.
        // LuaCov strips a trailing ".lua" from filenames BEFORE matching excludes
        // (file_included), so we strip it from the user's glob too — otherwise
        // "main.lua" → "main%.lua" would never match the stripped "main".
        func toPattern(_ glob: String) -> String {
            var g = glob
            if g.hasSuffix(".lua") { g = String(g.dropLast(4)) }
            return GlobToLuaPattern.convert(g)
        }
        let excludeRows = [CoverageExcludeRow].decode(from: testRunnerCoverageExcludes)
        var excludes = (excludeRows.isEmpty ? .defaultRows : excludeRows)
            .map { $0.glob.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { toPattern($0) }
        // Also exclude the configured test folders themselves — test files and
        // their helpers/fixtures shouldn't count toward game-code coverage.
        for row in testRows {
            let folder = row.folder.trimmingCharacters(in: .whitespaces)
            if !folder.isEmpty { excludes.append(toPattern(folder + "/**")) }
        }
        testRunner.coverageExcludes = excludes
    }

    /// Run all tests. Mutual exclusion (C9): never while the game runs/debugs.
    private func runTests() {
        guard !runner.isRunning, !isDebugging, !testRunner.isRunning else { return }
        applyTestRunnerSettings()
        testRunner.run(projectRoot: projectURL, rows: testRows, filter: nil)
    }

    /// Configured `folder | glob` rows (§3.7), decoded from @AppStorage, or defaults.
    private var testRows: [TestFolderGlob] {
        let rows = [TestFolderGlob].decode(from: testRunnerFoldersJSON)
        return rows.isEmpty ? .defaultRows : rows
    }

    private func fileURLChanged(oldURL: URL, newURL: URL) {
        guard let idx = openTabs.firstIndex(where: { $0.url == oldURL }) else { return }
        let wasActive = activeTab?.url == oldURL
        // Use item from refreshed project if found, otherwise create one from the new URL
        let newItem = project.findItem(url: newURL) ?? ProjectItem(url: newURL, isFolder: false)
        openTabs[idx] = newItem
        if wasActive { activeTab = newItem }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {

    let project: Project
    var gitService: GitStatusService? = nil
    @Binding var selectedTab : SidebarTab
    var testRunner: TestRunner? = nil
    var testRunnerEnabled: Bool = true
    var testRows: [TestFolderGlob] = []
    var canRunTests: Bool = true
    var onOpen: ((ProjectItem) -> Void)? = nil
    var onFileURLChanged: ((URL, URL) -> Void)? = nil
    var onJump: ((URL, Int) -> Void)? = nil
    var onOpenDoc: ((String) -> Void)? = nil

    @State private var findFocusTrigger : Int = 0

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .frame(minWidth: 200)
        .background(
            Button("") {
                selectedTab = .find
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    findFocusTrigger += 1
                }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .hidden()
        )
    }

    // MARK: Tab Bar

    private var visibleTabs: [SidebarTab] {
        SidebarTab.allCases.filter { $0 != .tests || testRunnerEnabled }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13))
                        Text(tab.title)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(isSelected ? .pink : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if isSelected {
                            Rectangle()
                                .fill(Color.pink)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .background(.bar)
    }

    // MARK: Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .files:
            FileTreeView(project: project, gitService: gitService, onOpen: onOpen, onFileURLChanged: onFileURLChanged)
        case .assets:
            AssetBrowserView(project: project)
        case .find:
            FindInFilesView(project: project, onJump: onJump, focusTrigger: findFocusTrigger)
        case .docs:
            DocsView()
        case .tests:
            if let testRunner {
                TestExplorerView(
                    runner: testRunner,
                    projectRoot: project.rootURL,
                    rows: testRows,
                    canRun: canRunTests,
                    onJump: { file, line in
                        onJump?(URL(fileURLWithPath: file), line)
                    },
                    onOpenReport: { path in onOpenDoc?(path) }
                    // Settings opens via SettingsLink inside the empty state (macOS 14+).
                )
            }
        }
    }

    private func placeholderView(_ title: String, icon: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SidebarTab

private enum SidebarTab: String, CaseIterable, Identifiable {
    case files, assets, find, tests, docs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files:  return "Files"
        case .assets: return "Assets"
        case .find:   return "Find"
        case .tests:  return "Tests"
        case .docs:   return "Docs"
        }
    }

    var icon: String {
        switch self {
        case .files:  return "folder.fill"
        case .assets: return "photo.fill"
        case .find:   return "magnifyingglass"
        case .tests:  return "flask.fill"
        case .docs:   return "book.closed.fill"
        }
    }
}

// MARK: - Tab snapshot (Equatable wrapper for onChange diffing)

private struct TabSnapshot: Equatable {
    let id: UUID
    let url: URL
}

// MARK: - TestRunnerObservers
//
// Collapses the test-runner `.onChange` handlers into one modifier. Extracted so
// `StudioView.body`'s modifier chain stays short enough for the Swift type-checker.
private struct TestRunnerObservers: ViewModifier {
    let timeout: Double
    let coverage: Bool
    let console: Bool
    let foldersJSON: String
    let covExcludes: String
    let enabled: Bool
    let isRunning: Bool
    let applySettings: () -> Void
    let rediscover: () -> Void
    let onRunStart: () -> Void
    let onRunFinish: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: timeout)     { _, _ in applySettings() }
            .onChange(of: coverage)    { _, _ in applySettings() }
            .onChange(of: console)     { _, _ in applySettings() }
            .onChange(of: covExcludes) { _, _ in applySettings() }
            .onChange(of: foldersJSON) { _, _ in applySettings(); rediscover() }
            .onChange(of: enabled)     { _, on in if on { rediscover() } }
            .onChange(of: isRunning)   { _, running in running ? onRunStart() : onRunFinish() }
    }
}

// MARK: - Editor Area

private struct EditorAreaView: View {

    @Binding var openTabs: [ProjectItem]
    @Binding var activeTab: ProjectItem?
    @Binding var untitledURLs: Set<URL>
    var projectURL: URL? = nil
    var worktreeRefreshToken: Int = 0
    var onFileURLChanged: ((URL, URL) -> Void)? = nil
    var onFileSaved: ((URL) -> Void)? = nil
    var runner      : LoveRunner? = nil
    var jumpToLine  : Binding<Int?> = .constant(nil)
    var breakpoints : BreakpointManager? = nil
    var pausedFile    : String? = nil
    var pausedLine    : Int? = nil
    var pausedFileURL : URL?   = nil
    var debugServer   : DebugServer? = nil
    var isDebugging  = false
    var gitService   : GitStatusService? = nil
    var lspClient    : LSPClientService? = nil
    var onJump      : ((String, Int) -> Void)? = nil
    var coverage     : CoverageStore? = nil      // per-line coverage for gutters
    var coverageGutters = false                  // gated by setting

    @AppStorage("appAppearance")         private var appAppearance: String = "system"
    @AppStorage("editorFontSize")        private var editorFontSize: Double = 13
    @AppStorage("editorFontName")        private var editorFontName: String = ""
    @AppStorage("editorTabWidth")        private var editorTabWidth: Int = 4
    @AppStorage("editorLineNumbers")     private var editorLineNumbers: Bool = true
    @AppStorage("editorMinimap")         private var editorMinimap: Bool = true
    @AppStorage("editorAutoCloseBraces") private var editorAutoCloseBraces: Bool = true
    @AppStorage("editorHighlightLine")   private var editorHighlightLine: Bool = true
    @AppStorage("editorWordWrap")        private var editorWordWrap: Bool = false
    @AppStorage("editorAutoSave")        private var editorAutoSave: Bool = false
    @AppStorage("editorAutoSaveDelay")   private var editorAutoSaveDelay: Double = 2.0
    @AppStorage("editorAnnotationsEnabled") private var annotationsEnabled: Bool = false
    @AppStorage("editorDocHoverEnabled")    private var docHoverEnabled: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var editorTheme: LuaTheme {
        switch appAppearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return colorScheme == .light ? .light : .dark
        }
    }

    // Text buffer per file URL
    @State private var textBuffers: [URL: String] = [:]
    @State private var dirtyURLs: Set<URL> = []
    @State private var saveErrorMessage: String? = nil
    @State private var autoSaveTimer: Timer? = nil
    @State private var confViewAsLua: Bool = false
    @State private var cursorLine: Int = 1
    @State private var cursorColumn: Int = 1
    @State private var consolePanelHeight: CGFloat = 180
    @State private var dragStartHeight: CGFloat = 180
    @State private var isDragging = false
    @State private var panelCollapsed = false
    @State private var heightBeforeCollapse: CGFloat = 180

    /// True for the Test Runner's own Markdown docs — the bundled help file and the
    /// temp coverage report — which render read-only via `MarkdownDocView` (§3.8).
    /// Deliberately NOT "any .md": only our two docs, so project .md files still edit.
    private func isTestRunnerDoc(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "md" else { return false }
        if url.lastPathComponent == "test-runner-help.md" { return true }
        if url.lastPathComponent == "coverage-report.md",
           url.path.hasPrefix(FileManager.default.temporaryDirectory.path) { return true }
        return false
    }

    private var activeText: Binding<String> {
        Binding(
            get: { activeTab.flatMap { textBuffers[$0.url] } ?? "" },
            set: {
                guard let url = activeTab?.url else { return }
                textBuffers[url] = $0
                dirtyURLs.insert(url)
                scheduleAutoSave()
            }
        )
    }

    private func scheduleAutoSave() {
        guard editorAutoSave else { return }
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: editorAutoSaveDelay, repeats: false) { _ in
            for url in self.dirtyURLs {
                guard let item = self.openTabs.first(where: { $0.url == url }),
                      !self.untitledURLs.contains(url) else { continue }
                self.saveFile(item: item)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            if !openTabs.isEmpty {
                TabBarView(
                    tabs: openTabs,
                    activeTab: $activeTab,
                    dirtyURLs: dirtyURLs,
                    onClose: closeTab
                )
                Divider()
            }

            // Editor or placeholder
            if let item = activeTab {
                let isConf = item.url.lastPathComponent == "conf.lua" && !untitledURLs.contains(item.url)
                // Test Runner docs (help + coverage report) render read-only as
                // Markdown, BEFORE the conf/Lua fallback so they aren't loaded as
                // editable text (§3.8). Scoped to our docs (bundle help or a temp
                // coverage report), not arbitrary project .md files.
                if isTestRunnerDoc(item.url) {
                    MarkdownDocView(url: item.url, onJump: onJump)
                        .id(item.id)
                } else if isConf && !confViewAsLua {
                    ConfEditorView(confURL: item.url, onSaved: { url in
                        onFileSaved?(url)
                        // Reload text buffer so switching to Lua view shows fresh content
                        if let text = try? String(contentsOf: url, encoding: .utf8) {
                            textBuffers[url] = text
                            dirtyURLs.remove(url)
                        }
                    })
                    .id(item.id)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            confViewAsLua = true
                            loadActiveFile()
                        } label: {
                            Label("View as Lua", systemImage: "doc.plaintext")
                                .font(.system(size: 11))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                    }
                } else {
                    LuaEditorView(
                        text: activeText,
                        onSave: { saveFile(item: item) },
                        theme: editorTheme,
                        fileURL: item.url,
                        fontSize: CGFloat(editorFontSize),
                        fontName: editorFontName,
                        showLineNumbers: editorLineNumbers,
                        showMinimap: editorMinimap,
                        tabWidth: editorTabWidth,
                        highlightCurrentLine: editorHighlightLine,
                        autoCloseBraces: editorAutoCloseBraces,
                        wordWrap: editorWordWrap,
                        onFontSizeChange: { editorFontSize = Double($0) },
                        onTextChange: isLuaTextBuffer(item.url)
                            ? { lspClient?.didChange(item.url, text: $0) }
                            : nil,
                        lspClient: isLuaTextBuffer(item.url) ? lspClient : nil,
                        lspDocumentURL: isLuaTextBuffer(item.url) ? item.url : nil,
                        docHoverEnabled: docHoverEnabled,
                        diagnostics: isLuaTextBuffer(item.url)
                            ? (lspClient?.diagnostics(for: item.url) ?? [])
                            : [],
                        onCursorChange: { line, col in
                            cursorLine = line
                            cursorColumn = col
                        },
                        jumpToLine: jumpToLine,
                        breakpoints: breakpoints,
                        pausedLine: pausedFileURL == item.url ? pausedLine : nil,
                        currentFile: item.url.lastPathComponent,
                        coverageHit: coverageGutters ? (coverage?.coverage(forPath: item.url.path)?.hit ?? []) : [],
                        coverageMiss: coverageGutters ? (coverage?.coverage(forPath: item.url.path)?.miss ?? []) : []
                    )
                    .id(item.id)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if isConf {
                            Button {
                                confViewAsLua = false
                            } label: {
                                Label("View as Editor", systemImage: "gearshape.2")
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                        }
                    }
                }
            } else {
                editorPlaceholder
            }

            // Editor status bar — code tabs only (absent in visual tool views,
            // which aren't mounted inside EditorAreaView).
            if let item = activeTab {
                EditorStatusBar(
                    fileURL: item.url,
                    isLua: isLuaTextBuffer(item.url),
                    annotationsEnabled: annotationsEnabled,
                    cursorLine: cursorLine,
                    cursorColumn: cursorColumn,
                    lspClient: lspClient
                )
            }

            // Console / Debug panel
            ConsolePanelView(
                height: $consolePanelHeight,
                dragStartHeight: $dragStartHeight,
                isDragging: $isDragging,
                collapsed: $panelCollapsed,
                runner: runner,
                debugServer: debugServer,
                breakpoints: breakpoints,
                isDebugging: isDebugging,
                gitService: gitService,
                projectURL: projectURL,
                onJump: onJump,
                onInsert: { code in
                    guard let url = activeTab?.url else { return }
                    let current = textBuffers[url] ?? ""
                    textBuffers[url] = current + (current.isEmpty ? "" : "\n\n") + code
                    dirtyURLs.insert(url)
                }
            )
            .frame(height: panelCollapsed ? 28 : consolePanelHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: activeTab?.id) { _, _ in
            loadActiveFile()
            // Reset to visual editor when navigating away from conf.lua
            if activeTab?.url.lastPathComponent != "conf.lua" {
                confViewAsLua = false
            }
        }
        .onChange(of: worktreeRefreshToken) { _, _ in
            reloadOpenFilesFromDisk()
        }
        .onChange(of: lspClient?.status) { _, status in
            // Server became ready (e.g. annotations toggled on mid-session): open
            // any already-loaded Lua tabs the keystroke/load paths missed.
            guard status == .active else { return }
            for tab in openTabs where isLuaTextBuffer(tab.url) {
                lspOpenIfNeeded(tab.url)
            }
        }
        .onChange(of: confViewAsLua) { _, asLua in
            // conf.lua's mode toggle is a sync event: opening the Lua text buffer
            // or closing it as the visual editor takes over.
            guard let url = activeTab?.url, url.lastPathComponent == "conf.lua" else { return }
            if asLua { lspOpenIfNeeded(url) } else { lspCloseIfNeeded(url) }
        }
        .onChange(of: openTabs.map { TabSnapshot(id: $0.id, url: $0.url) }) { oldSnaps, newSnaps in
            // Detect URL changes (rename/move) and migrate textBuffers keys.
            // Match by stable tab ID so that add/remove operations never
            // cause zip-by-position to pair unrelated tabs.
            let oldByID = Dictionary(uniqueKeysWithValues: oldSnaps.map { ($0.id, $0.url) })
            for snap in newSnaps {
                if let oldURL = oldByID[snap.id], oldURL != snap.url {
                    if let text = textBuffers[oldURL] {
                        textBuffers[snap.url] = text
                        textBuffers.removeValue(forKey: oldURL)
                    }
                    // Rename/move: server keys by URI — close old, open new.
                    if let lspClient, lspClient.isOpen(oldURL) {
                        lspClient.didRename(from: oldURL, to: snap.url,
                                            text: textBuffers[snap.url] ?? "")
                    }
                }
            }
        }
        .alert("Save Failed", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    // MARK: LSP document sync

    // A tab is a Lua text buffer the server should track when it's a .lua file
    // and (for conf.lua) the Lua text view is mounted, not the visual editor.
    private func isLuaTextBuffer(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "lua" else { return false }
        let isConf = url.lastPathComponent == "conf.lua" && !untitledURLs.contains(url)
        if isConf { return confViewAsLua }  // only synced in "View as Lua" mode
        return true
    }

    // Open this URL on the server if it qualifies and its text is loaded.
    private func lspOpenIfNeeded(_ url: URL) {
        guard let lspClient, isLuaTextBuffer(url), let text = textBuffers[url] else { return }
        lspClient.didOpen(url, text: text)
    }

    private func lspCloseIfNeeded(_ url: URL) {
        lspClient?.didClose(url)
    }

    // MARK: Load / Save / Close

    private func loadActiveFile() {
        guard let item = activeTab else { return }
        guard textBuffers[item.url] == nil else { return }
        // Untitled files have no content on disk - start with empty buffer
        if untitledURLs.contains(item.url) {
            textBuffers[item.url] = ""
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let text = (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
            DispatchQueue.main.async {
                textBuffers[item.url] = text
                lspOpenIfNeeded(item.url)
            }
        }
    }

    private func reloadOpenFilesFromDisk() {
        let urlsToReload = openTabs.map(\.url).filter { url in
            !untitledURLs.contains(url) && !dirtyURLs.contains(url)
        }
        guard !urlsToReload.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            var refreshedBuffers: [URL: String] = [:]
            for url in urlsToReload {
                guard FileManager.default.fileExists(atPath: url.path),
                      let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                refreshedBuffers[url] = text
            }

            guard !refreshedBuffers.isEmpty else { return }
            DispatchQueue.main.async {
                for (url, text) in refreshedBuffers {
                    textBuffers[url] = text
                    // Keystroke didChange won't fire for an external swap; push
                    // full text so the server doesn't keep stale pre-reload content.
                    lspClient?.didChange(url, text: text)
                }
            }
        }
    }

    private func saveFile(item: ProjectItem) {
        guard let text = textBuffers[item.url] else { return }
        if untitledURLs.contains(item.url) {
            showSavePanel(for: item, text: text)
            return
        }
        dirtyURLs.remove(item.url)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try text.write(to: item.url, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async {
                    self.dirtyURLs.insert(item.url)   // mark dirty again - not saved
                    self.saveErrorMessage = "\(item.name): \(error.localizedDescription)"
                }
            }
        }
        // If debugging and paused, hot-reload the saved file into the running VM
        if isDebugging, item.url.pathExtension == "lua" {
            debugServer?.load(file: item.url.lastPathComponent, source: text)
        }
        if isLuaTextBuffer(item.url) { lspClient?.didSave(item.url) }
    }

    private func showSavePanel(for item: ProjectItem, text: String) {
        let panel = NSSavePanel()
        panel.title = "Save File"
        panel.nameFieldStringValue = item.name
        panel.directoryURL = projectURL
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.begin { response in
            guard response == .OK, let destURL = panel.url else { return }
            do {
                try text.write(to: destURL, atomically: true, encoding: .utf8)
            } catch { return }
            // Replace untitled item with real one
            let newItem = ProjectItem(url: destURL, isFolder: false)
            if let idx = openTabs.firstIndex(where: { $0.id == item.id }) {
                openTabs[idx] = newItem
            }
            if activeTab?.id == item.id { activeTab = newItem }
            textBuffers[destURL] = text
            textBuffers.removeValue(forKey: item.url)
            dirtyURLs.remove(item.url)
            untitledURLs.remove(item.url)
            lspOpenIfNeeded(destURL)   // untitled buffer just became a real .lua file
            onFileSaved?(destURL)
        }
    }

    private func closeTab(_ item: ProjectItem) {
        if dirtyURLs.contains(item.url) {
            let alert = NSAlert()
            alert.messageText = "Save \"\(item.name)\"?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:  // Save
                saveFile(item: item)
                // For untitled the save panel is async - don't close yet, panel handles it
                if untitledURLs.contains(item.url) { return }
            case .alertSecondButtonReturn: break  // Don't Save - just close
            default: return  // Cancel
            }
        }
        discardTab(item)
    }

    private func discardTab(_ item: ProjectItem) {
        lspCloseIfNeeded(item.url)
        textBuffers.removeValue(forKey: item.url)
        dirtyURLs.remove(item.url)
        untitledURLs.remove(item.url)
        guard let idx = openTabs.firstIndex(where: { $0.id == item.id }) else { return }
        openTabs.remove(at: idx)
        if activeTab?.id == item.id {
            activeTab = openTabs.indices.contains(idx) ? openTabs[idx] : openTabs.last
        }
    }

    // MARK: Editor placeholder

    private var editorPlaceholder: some View {
        VStack {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 42, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Open a file to start editing")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }

}

// MARK: - File Icon

struct FileIconView: View {
    let ext: String
    var size: CGFloat = 14

    private static let svgMap: [String: String] = [
        "lua": "lua", "love": "love2d",
        "json": "json", "js": "js", "ts": "ts",
        "py": "py", "cpp": "cpp", "c": "c",
        "xml": "xml", "html": "html", "css": "css",
        "md": "markdown", "sh": "sh", "yaml": "yaml", "yml": "yaml"
    ]

    var body: some View {
        if let name = Self.svgMap[ext],
           let url = Bundle.main.url(forResource: name, withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.pink)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackIcon)
                .font(.system(size: size - 2))
                .foregroundStyle(fallbackColor)
                .frame(width: size, height: size)
        }
    }

    private var fallbackIcon: String {
        switch ext {
        case "png", "jpg", "jpeg", "gif", "bmp", "webp": return "photo.fill"
        case "mp3", "ogg", "wav", "flac":                return "music.note"
        case "ttf", "otf":                               return "textformat"
        default:                                          return "doc.fill"
        }
    }

    private var fallbackColor: Color {
        switch ext {
        case "png", "jpg", "jpeg", "gif", "bmp", "webp": return .blue
        case "mp3", "ogg", "wav", "flac":                return .purple
        case "ttf", "otf":                               return .orange
        default:                                          return .secondary
        }
    }
}

// MARK: - Editor Status Bar

// Thin VS Code-style strip at the bottom of the code-editing surface. Passive
// indicator: LSP status (click for restart), line:col, language, diagnostics.
// Uses the app's chrome tokens (.bar, separatorColor, GitToolbarPill idiom) and
// semantic colors so it reads correctly in light/dark/system.
private struct EditorStatusBar: View {
    let fileURL: URL
    let isLua: Bool
    let annotationsEnabled: Bool
    let cursorLine: Int
    let cursorColumn: Int
    var lspClient: LSPClientService? = nil

    @State private var showLSPPopover = false

    private var language: String {
        switch fileURL.pathExtension.lowercased() {
        case "lua": return "Lua"
        case "json": return "JSON"
        default: return fileURL.pathExtension.isEmpty ? "Plain Text" : fileURL.pathExtension.uppercased()
        }
    }

    private var lspStatus: LSPClientService.Status { lspClient?.status ?? .inactive }

    private var lspColor: Color {
        switch lspStatus {
        case .active:      return Color(NSColor.systemGreen)
        case .starting:    return Color(NSColor.systemYellow)
        case .unavailable: return Color(NSColor.systemRed)
        case .inactive:    return Color(NSColor.secondaryLabelColor)
        }
    }

    private var lspText: String {
        switch lspStatus {
        case .active:      return "Lua Language Server"
        case .starting:    return "Lua Language Server…"
        case .unavailable: return "Lua Language Server (unavailable)"
        case .inactive:    return "Lua Language Server (off)"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // LSP status — only shown when the annotations feature is enabled.
            // Reflects the real client state regardless of the active file type.
            if annotationsEnabled {
                Button { showLSPPopover = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(lspColor)
                        Text(lspText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(lspStatus == .unavailable
                      ? "Language server unavailable — using built-in completion"
                      : "Lua language server")
                .popover(isPresented: $showLSPPopover, arrowEdge: .top) {
                    lspPopover
                }
            }

            Spacer()

            // Diagnostics counts (errors / warnings)
            if isLua, let counts = lspClient?.diagnosticCounts, counts.errors + counts.warnings > 0 {
                HStack(spacing: 8) {
                    if counts.errors > 0 {
                        Label("\(counts.errors)", systemImage: "xmark.octagon.fill")
                            .foregroundStyle(Color(NSColor.systemRed))
                    }
                    if counts.warnings > 0 {
                        Label("\(counts.warnings)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(NSColor.systemYellow))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .labelStyle(.titleAndIcon)
            }

            Text("Ln \(cursorLine), Col \(cursorColumn)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Text(language)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(NSColor.separatorColor)).frame(height: 0.5)
        }
    }

    @ViewBuilder private var lspPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lua Language Server")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 6) {
                Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(lspColor)
                Text(statusDescription).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button("Restart Language Server") {
                lspClient?.restart()
                showLSPPopover = false
            }
            .controlSize(.small)
            if !isLua {
                Text("Active for Lua files in this project. The current file isn't Lua.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    private var statusDescription: String {
        switch lspStatus {
        case .active:      return "Active"
        case .starting:    return "Starting…"
        case .unavailable: return "Unavailable — using built-in completion"
        case .inactive:    return "Off"
        }
    }
}

// MARK: - Tab Bar

private struct TabBarView: View {
    let tabs: [ProjectItem]
    @Binding var activeTab: ProjectItem?
    let dirtyURLs: Set<URL>
    let onClose: (ProjectItem) -> Void

    @State private var hoveredTab: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    TabItemView(
                        tab: tab,
                        isActive: activeTab?.id == tab.id,
                        isHovered: hoveredTab == tab.id,
                        isDirty: dirtyURLs.contains(tab.url),
                        onSelect: { activeTab = tab },
                        onClose: { onClose(tab) }
                    )
                    .onHover { hoveredTab = $0 ? tab.id : nil }
                }
            }
        }
        .frame(height: 34)
        .background(.bar)
    }
}

private struct TabItemView: View {
    let tab: ProjectItem
    let isActive: Bool
    let isHovered: Bool
    let isDirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var closeHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Button(action: onSelect) {
                HStack(spacing: 5) {
                    // File type icon - SVG from bundle, fallback to SF Symbol
                    if tab.url.lastPathComponent == "conf.lua" {
                        Image(systemName: "gearshape.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 1.0, green: 0.28, blue: 0.58))
                            .frame(width: 13, height: 13)
                    } else {
                        FileIconView(ext: tab.url.pathExtension.lowercased(), size: 13)
                    }

                    Text(tab.name)
                        .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Close / dirty indicator
            ZStack {
                if isDirty && !closeHovered {
                    // Dirty dot - click also closes/saves
                    Button { onClose() } label: {
                        Circle()
                            .fill(Color.primary.opacity(0.45))
                            .frame(width: 7, height: 7)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .onHover { closeHovered = $0 }
                } else if isHovered || isActive || closeHovered {
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(closeHovered ? .primary : .secondary)
                            .frame(width: 14, height: 14)
                            .background(
                                Circle()
                                    .fill(closeHovered
                                          ? Color.primary.opacity(0.12)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { closeHovered = $0 }
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            ZStack(alignment: .bottom) {
                if isActive {
                    Color.primary.opacity(0.06)
                    Rectangle()
                        .fill(Color.pink)
                        .frame(height: 2)
                } else if isHovered {
                    Color.primary.opacity(0.04)
                }
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 0.5)
        }
    }

}

// MARK: - Console Panel

private struct ConsolePanelView: View {

    @Binding var height: CGFloat
    @Binding var dragStartHeight: CGFloat
    @Binding var isDragging: Bool
    @Binding var collapsed: Bool
    var runner      : LoveRunner?
    var debugServer : DebugServer?
    var breakpoints : BreakpointManager?
    var isDebugging  = false
    var gitService  : GitStatusService? = nil
    var projectURL  : URL? = nil
    var onJump      : ((String, Int) -> Void)?
    var onInsert    : ((String) -> Void)?

    @State private var selectedTab: BottomTab = .console

    enum BottomTab { case console, debug, git, snippets }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            // Header: tabs left, grab handle center, actions right
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    tabButton(.console,  icon: "terminal.fill",         label: "Console")
                    tabButton(.debug,    icon: "ant.fill",              label: "Debug")
                    tabButton(.git,      icon: "arrow.triangle.branch", label: "Git")
                    tabButton(.snippets, icon: "curlybraces",           label: "Snippets")
                }
                .padding(.horizontal, 8)

                // Draggable spacer between tabs and actions
                ZStack {
                    Color.clear
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .cursor(.resizeUpDown)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if !isDragging { isDragging = true; dragStartHeight = height }
                            height = max(80, min(600, dragStartHeight - value.translation.height))
                        }
                        .onEnded { _ in isDragging = false }
                )

                // Actions
                HStack(spacing: 8) {
                    if !collapsed {
                        if selectedTab == .console, let runner, !runner.lines.isEmpty {
                            Button { runner.clear() } label: {
                                Image(systemName: "trash").font(.system(size: 11))
                            }
                            .buttonStyle(.plain).foregroundStyle(.tertiary).help("Clear console")
                        }
                        if selectedTab == .debug, let debugServer, debugServer.isPaused {
                            DebugActionButton(icon: "arrow.down.to.line", label: "Step Into",  action: { debugServer.step() })
                            DebugActionButton(icon: "arrow.uturn.right",  label: "Step Over",  action: { debugServer.stepOver() })
                            DebugActionButton(icon: "arrow.up.to.line",   label: "Step Out",   action: { debugServer.stepOut() })
                            DebugActionButton(icon: "play.fill",          label: "Continue",   action: { debugServer.resume() }, color: .green)
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            collapsed.toggle()
                        }
                    } label: {
                        Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(collapsed ? "Expand panel" : "Collapse panel")
                }
                .padding(.trailing, 12)
            }
            .frame(height: 28)
            .background(.bar)
            .overlay(isDragging ? Color.primary.opacity(0.04) : Color.clear)

            Divider()

            if !collapsed {
                switch selectedTab {
                case .console:  consoleContent
                case .debug:    debugContent
                case .git:      gitContent
                case .snippets: SnippetsView(onInsert: onInsert)
                }
            }
        }
        .onChange(of: isDebugging) { _, debugging in
            if debugging { selectedTab = .debug }
        }
        .onReceive(NotificationCenter.default.publisher(for: .testRunStarted)) { note in
            // Debug test run → show Debug panel; normal test run → show Console.
            let isDebug = (note.userInfo?["debug"] as? Bool) ?? false
            selectedTab = isDebug ? .debug : .console
        }
    }

    private func tabButton(_ tab: BottomTab, icon: String, label: String) -> some View {
        let isSelected = selectedTab == tab
        return Button { selectedTab = tab } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var consoleContent: some View {
        Group {
            if let runner, !runner.lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(runner.lines) { line in
                                ConsoleLineView(line: line, onErrorJump: runner.onErrorJump)
                                    .id(line.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .background(.windowBackground)
                    .onChange(of: runner.lines.count) { _, _ in
                        if let last = runner.lines.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            } else {
                placeholder("terminal", "Run your project to see output here")
            }
        }
    }

    @ViewBuilder
    private var debugContent: some View {
        if let debugServer, let breakpoints {
            VStack(spacing: 0) {
                // Debug panel headers
                HStack(spacing: 0) {
                    debugHeader("CALL STACK").frame(width: 210, alignment: .leading)
                    Divider()
                    debugHeader("VARIABLES").frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    debugHeader("BREAKPOINTS").frame(width: 190, alignment: .leading)
                }
                .frame(height: 22)
                .background(.bar)
                Divider()
                DebugPanelView(
                    debugServer: debugServer,
                    breakpoints: breakpoints,
                    isDebugging: isDebugging,
                    onJump: onJump
                )
                .background(.windowBackground)
            }
        } else {
            placeholder("ant", "Start a debug session to inspect variables and breakpoints")
        }
    }

    private func debugHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
    }

    @ViewBuilder
    private var gitContent: some View {
        if let gitService, let projectURL {
            GitPanelView(git: gitService, projectURL: projectURL)
        } else {
            placeholder("arrow.triangle.branch", "No project loaded")
        }
    }

    private func placeholder(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.tertiary)
            Text(text).font(.caption).foregroundStyle(.quaternary).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}

// MARK: - Console Line View

private struct ConsoleLineView: View {

    let line: ConsoleLine
    var onErrorJump: ((String, Int) -> Void)?

    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp
            Text(Self.timeFormatter.string(from: line.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .leading)
                .padding(.top, 1)

            // Message
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .underline(isHovered && line.errorRef != nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(isHovered && line.errorRef != nil
            ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if let ref = line.errorRef {
                onErrorJump?(ref.file, ref.line)
            }
        }
        .cursor(line.errorRef != nil ? .pointingHand : .arrow)
    }

    private var textColor: Color {
        switch line.kind {
        case .stdout: return .primary
        case .stderr: return Color(NSColor.systemRed)
        case .system:
            // Exit 0 → green, exit != 0 → red, other system → secondary
            if line.text.hasPrefix("■ Finished") {
                return line.text.contains("exit 0") ? Color(NSColor.systemGreen) : Color(NSColor.systemRed)
            }
            return .secondary
        }
    }
}

// MARK: - Debug Action Button

private struct DebugActionButton: View {
    let icon   : String
    let label  : String
    let action : () -> Void
    var color  : Color = .primary

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .overlay(alignment: .top) {
            if isHovered {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: -2)
                    .offset(y: -26)
                    .fixedSize()
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - NSCursor helper

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.set() } else { NSCursor.arrow.set() }
        }
    }
}

// MARK: - Toolbar

private enum StudioTool: String, CaseIterable, Identifiable {
    case particles         = "Particle Editor"
    case audioManager      = "Audio Manager"
    case animations        = "Animations"
    case tilemapEditor     = "Tilemap Editor"
    case imageEditor       = "Image Editor"
    case spritesheetPacker = "Spritesheet Packer"
    case cameraConfig      = "Camera Config"
    case resolutionScaler  = "Resolution Scaler"
    case uiBuilder         = "UI Builder"
    case fontManager       = "Font Manager"
    case sceneManager      = "Scene Manager"
    case saveSystem        = "Save System"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .particles:         return "sparkles"
        case .audioManager:      return "waveform"
        case .animations:        return "figure.run"
        case .tilemapEditor:     return "squareshape.split.3x3"
        case .imageEditor:       return "paintbrush.pointed.fill"
        case .spritesheetPacker: return "square.grid.3x3.fill"
        case .cameraConfig:      return "camera.metering.center.weighted"
        case .resolutionScaler:  return "square.resize"
        case .uiBuilder:         return "rectangle.3.group"
        case .fontManager:       return "textformat.size"
        case .sceneManager:      return "rectangle.stack.fill"
        case .saveSystem:        return "externaldrive.fill"
        }
    }

    var color: Color {
        switch self {
        case .particles:         return .purple
        case .audioManager:      return .teal
        case .animations:        return .orange
        case .tilemapEditor:     return .blue
        case .imageEditor:       return .pink
        case .spritesheetPacker: return .indigo
        case .cameraConfig:      return .cyan
        case .resolutionScaler:  return .mint
        case .uiBuilder:         return .pink
        case .fontManager:       return .yellow
        case .sceneManager:      return .green
        case .saveSystem:        return .orange
        }
    }
}

private struct StudioToolbar: ToolbarContent {

    let projectURL  : URL
    var runner      : LoveRunner
    var debugServer : DebugServer
    var isDebugging : Bool
    var onDebug     : () -> Void
    var onStopDebug : () -> Void
    var testRunner       : TestRunner? = nil
    var testRunnerEnabled: Bool = true
    var testRows         : [TestFolderGlob] = []
    var onRunTests       : () -> Void = {}
    @State private var showLoveMissingAlert = false
    @State private var showExport = false

    var body: some ToolbarContent {
        // Title with heart - left aligned
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 0) {
                    Text(projectURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                    Text("LÖVE Studio")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
            .padding(.leading, 12)
            .padding(.trailing, 20)
        }

        // Right - Run controls + Tools
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                guard let loveURL = LoveRuntimeResolver.resolve(
                    preferredExternalURL: nil, preferBundled: true)
                else {
                    showLoveMissingAlert = true
                    return
                }
                print("[LoveStudio] Using love.app at: \(loveURL.path)")
                runner.run(projectURL: projectURL, loveAppURL: loveURL)
            } label: {
                Image(systemName: "play.fill")
                    .foregroundColor(runner.isRunning ? .secondary : .green)
            }
            .help("Run project (⌘R)")
            .disabled(runner.isRunning)
            .keyboardShortcut("r", modifiers: .command)
            .alert("LÖVE Not Found", isPresented: $showLoveMissingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Install LÖVE from love2d.org or place love.app in /Applications.")
            }

            Button {
                if isDebugging { onStopDebug() } else { runner.stop() }
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundColor(runner.isRunning ? .red : .secondary)
            }
            .help("Stop")
            .disabled(!runner.isRunning)

            // Debug button
            Button {
                if isDebugging { onStopDebug() } else { onDebug() }
            } label: {
                Image(systemName: "ant.fill")
                    .foregroundColor(isDebugging ? .orange : (runner.isRunning ? .secondary : .primary))
            }
            .help(isDebugging ? "Stop Debugging" : "Debug (⌘⌥R)")
            .disabled(runner.isRunning && !isDebugging)
            .keyboardShortcut("r", modifiers: [.command, .option])

            // Run Tests — disabled while the game runs/debugs (C9, §4.3).
            if testRunnerEnabled, let testRunner {
                Button {
                    onRunTests()
                } label: {
                    Image(systemName: "flask.fill")
                        .foregroundColor(testRunner.isRunning ? .secondary
                                         : ((runner.isRunning || isDebugging) ? .secondary : .green))
                }
                .help("Run Tests")
                .disabled(runner.isRunning || isDebugging || testRunner.isRunning)
            }

            Divider()

            Button {
                showExport = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export project")
            .sheet(isPresented: $showExport) {
                ExportWizardView(project: Project(rootURL: projectURL))
            }

            ToolsMenuButton(projectURL: projectURL)
        }
    }
}

// MARK: - Tools Menu Button

private struct ToolsMenuButton: View {
    let projectURL: URL
    @State private var showPopover        = false
    @Environment(\.openWindow) private var openWindow

    @State private var showCameraConfig      = false
    @State private var showResolutionScaler  = false
    @State private var showFontManager       = false
    @State private var showSaveSystem        = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .help("Tools")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ToolsPopover(onSelectTool: { tool in
                showPopover = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    switch tool {
                    case .particles:         openWindow(id: "particle-editor", value: projectURL)
                    case .audioManager:      openWindow(id: "audio-manager", value: projectURL)
                    case .animations:        openWindow(id: "animation-editor", value: projectURL)
                    case .tilemapEditor:     openWindow(id: "tilemap-editor", value: projectURL)
                    case .imageEditor:       openWindow(id: "image-editor", value: projectURL)
                    case .spritesheetPacker: openWindow(id: "spritesheet-packer", value: projectURL)
                    case .cameraConfig:      showCameraConfig       = true
                    case .resolutionScaler:  showResolutionScaler   = true
                    case .uiBuilder:         openWindow(id: "ui-builder", value: projectURL)
                    case .fontManager:       showFontManager        = true
                    case .sceneManager:      openWindow(id: "scene-manager", value: projectURL)
                    case .saveSystem:        showSaveSystem         = true
                    }
                }
            })
        }

        .sheet(isPresented: $showCameraConfig) {
            CameraConfigView(projectURL: projectURL) {
                showCameraConfig = false
            }
        }
        .sheet(isPresented: $showResolutionScaler) {
            ResolutionScalerView(projectURL: projectURL) {
                showResolutionScaler = false
            }
        }
        .sheet(isPresented: $showFontManager) {
            FontManagerView(projectURL: projectURL) {
                showFontManager = false
            }
        }
        .sheet(isPresented: $showSaveSystem) {
            SaveSystemView(projectURL: projectURL) {
                showSaveSystem = false
            }
        }
    }
}

private struct ToolsPopover: View {
    let onSelectTool: (StudioTool) -> Void

    @State private var hoveredTool: StudioTool?

    var body: some View {
        VStack(spacing: 4) {
            ForEach(StudioTool.allCases) { tool in
                Button {
                    onSelectTool(tool)
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tool.color.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(tool.color)
                            }
                        Text(tool.rawValue)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(hoveredTool == tool ? Color.primary.opacity(0.07) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredTool = $0 ? tool : nil }
            }
        }
        .padding(8)
        .frame(width: 240)
    }
}

// MARK: - Preview

#Preview {
    StudioView(projectURL: URL(filePath: "/tmp/MyGame"))
}
