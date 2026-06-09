import SwiftUI
import AppKit

struct SettingsView: View {

    private enum Tab: String, CaseIterable {
        case general  = "General"
        case editor   = "Editor"
        case runner   = "Runner"
        case keymap   = "Keymap"

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .editor:  return "chevron.left.forwardslash.chevron.right"
            case .runner:  return "play.circle"
            case .keymap:  return "keyboard"
            }
        }
    }

    @State private var selectedTab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18))
                            Text(tab.rawValue)
                                .font(.system(size: 11))
                        }
                        .frame(width: 80, height: 52)
                        .background(selectedTab == tab
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear)
                        .foregroundStyle(selectedTab == tab
                            ? Color.accentColor
                            : Color.secondary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Divider()

            Group {
                switch selectedTab {
                case .general: GeneralSettingsView()
                case .editor:  EditorSettingsView()
                case .runner:  RunnerSettingsView()
                case .keymap:  KeymapSettingsView()
                }
            }
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {

    @AppStorage("appAppearance")       private var appAppearance: String = "system"
    @AppStorage("sidebarWidth")        private var sidebarWidth: Double = 220
    @AppStorage("consolePanelHeight")  private var consolePanelHeight: Double = 180
    @AppStorage("restoreLastProject")  private var restoreLastProject: Bool = true
    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch: Bool = true

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appAppearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appAppearance) { _, v in applyAppearance(v) }
            } header: {
                Label("Appearance", systemImage: "paintbrush")
            }

            Section {
                Toggle("Reopen last project on launch", isOn: $restoreLastProject)
                Toggle("Show Welcome screen on launch", isOn: $showWelcomeOnLaunch)
            } header: {
                Label("Startup", systemImage: "house")
            }

            Section {
                LabeledContent("Sidebar width") {
                    HStack {
                        Slider(value: $sidebarWidth, in: 160...400, step: 10)
                            .frame(width: 140)
                        Text("\(Int(sidebarWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                LabeledContent("Console height") {
                    HStack {
                        Slider(value: $consolePanelHeight, in: 80...400, step: 10)
                            .frame(width: 140)
                        Text("\(Int(consolePanelHeight)) pt")
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            } header: {
                Label("Layout", systemImage: "rectangle.split.3x1")
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
        .onAppear { applyAppearance(appAppearance) }
    }

    private func applyAppearance(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }
}

// MARK: - Editor

private struct EditorSettingsView: View {

    @AppStorage("editorFontSize")        private var editorFontSize: Double = 13
    @AppStorage("editorFontName")        private var editorFontName: String = ""
    @AppStorage("editorTabWidth")        private var editorTabWidth: Int = 4
    @AppStorage("editorLineNumbers")     private var editorLineNumbers: Bool = true
    @AppStorage("editorMinimap")         private var editorMinimap: Bool = true
    @AppStorage("editorAutoCloseBraces") private var editorAutoCloseBraces: Bool = true
    @AppStorage("editorHighlightLine")   private var editorHighlightLine: Bool = true
    @AppStorage("editorWordWrap")        private var editorWordWrap: Bool = false
    @AppStorage("editorAutoSave")             private var editorAutoSave: Bool = false
    @AppStorage("editorAutoSaveDelay")        private var editorAutoSaveDelay: Double = 2.0
    @AppStorage("editorAnnotationsEnabled")   private var annotationsEnabled: Bool = false
    @AppStorage("editorDocHoverEnabled")      private var docHoverEnabled: Bool = true
    @State private var showDiagnosticSettings = false

    private let monoFonts: [String] = {
        let families = NSFontManager.shared.availableFontFamilies
        let known = ["SF Mono", "Menlo", "Monaco", "Courier New", "Fira Code",
                     "JetBrains Mono", "Hack", "Source Code Pro", "Inconsolata",
                     "IBM Plex Mono", "Cascadia Code", "Victor Mono"]
        return known.filter { families.contains($0) }
    }()

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: $editorFontName) {
                    Text("System Monospaced").tag("")
                    if !monoFonts.isEmpty {
                        Divider()
                        ForEach(monoFonts, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                LabeledContent("Font Size") {
                    Stepper("\(Int(editorFontSize)) pt",
                            value: $editorFontSize,
                            in: 8...32, step: 1)
                }
                Picker("Tab Width", selection: $editorTabWidth) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }
            } header: {
                Label("Text", systemImage: "textformat")
            }

            Section {
                Toggle("Show line numbers", isOn: $editorLineNumbers)
                Toggle("Show minimap", isOn: $editorMinimap)
                Toggle("Highlight current line", isOn: $editorHighlightLine)
                Toggle("Word wrap", isOn: $editorWordWrap)
                Toggle("Auto-close brackets & quotes", isOn: $editorAutoCloseBraces)
                Toggle("Show documentation on hover", isOn: $docHoverEnabled)
            } header: {
                Label("Display", systemImage: "eye")
            }

            Section {
                Toggle("Auto-save", isOn: $editorAutoSave)
                if editorAutoSave {
                    LabeledContent("Delay") {
                        HStack {
                            Slider(value: $editorAutoSaveDelay, in: 0.5...10, step: 0.5)
                                .frame(width: 120)
                            Text(String(format: "%.1f s", editorAutoSaveDelay))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Label("Saving", systemImage: "square.and.arrow.down")
            }
            Section {
                Toggle("Enable type annotations (LuaCATS)", isOn: $annotationsEnabled)
                if annotationsEnabled {
                    Text("Adds LuaCATS type annotation comments to generated Lua code and enables the language server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Language server") {
                        Button("Restart") {
                            NotificationCenter.default.post(name: .restartLanguageServer, object: nil)
                        }
                        .controlSize(.small)
                    }
                    Button("Advanced…") { showDiagnosticSettings = true }
                        .controlSize(.small)
                }
            } header: {
                Label("Language Server", systemImage: "chevron.left.forwardslash.chevron.right")
            } footer: {
                if annotationsEnabled {
                    Text("Restart applies to the active project window. The editor's status bar shows live server state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
        .sheet(isPresented: $showDiagnosticSettings) {
            DiagnosticSeveritySettingsView()
        }
    }
}

// MARK: - Diagnostic severity settings

private struct DiagnosticSeveritySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var overrides: [String: DiagnosticSeverityLevel] = DiagnosticSeverityStore.load()
    @State private var search = ""

    private var filteredGroups: [(group: String, codes: [DiagnosticCode])] {
        let matches = DiagnosticCatalog.all.filter {
            search.isEmpty || $0.id.localizedCaseInsensitiveContains(search)
        }
        let byGroup = Dictionary(grouping: matches, by: \.group)
        return byGroup.keys.sorted().map { ($0, byGroup[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Diagnostic Severity").font(.headline)
                Spacer()
                Button("Reset to Defaults") {
                    overrides = DiagnosticSeverityStore.appDefaults
                }
                .controlSize(.small)
            }
            .padding()

            Divider()

            List {
                ForEach(filteredGroups, id: \.group) { entry in
                    Section(entry.group) {
                        ForEach(entry.codes) { code in
                            HStack {
                                Text(code.name)
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Picker("", selection: bindingFor(code.id)) {
                                    ForEach(DiagnosticSeverityLevel.allCases) { lvl in
                                        Text(lvl.label).tag(Optional(lvl))
                                    }
                                    Text("Default").tag(Optional<DiagnosticSeverityLevel>.none)
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 110)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Filter diagnostics")

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Apply") {
                    DiagnosticSeverityStore.save(overrides)
                    NotificationCenter.default.post(name: .diagnosticSeveritiesChanged, object: nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
    }

    // Picker binds to an optional level; nil = use LuaLS default (no override).
    private func bindingFor(_ code: String) -> Binding<DiagnosticSeverityLevel?> {
        Binding(
            get: { overrides[code] },
            set: { newValue in
                if let newValue { overrides[code] = newValue } else { overrides[code] = nil }
            }
        )
    }
}

// MARK: - Runner

private struct RunnerSettingsView: View {

    @AppStorage("runnerHotReload")         private var hotReload: Bool = true
    @AppStorage("runnerHotReloadDelay")    private var hotReloadDelay: Double = 0.5
    @AppStorage("runnerClearConsole")      private var clearConsoleOnRun: Bool = true
    @AppStorage("runnerScrollToBottom")    private var scrollToBottom: Bool = true
    @AppStorage("runnerMaxLines")          private var maxLines: Int = 2000
    @AppStorage("runnerDebugPort")         private var debugPort: Int = 8172
    @AppStorage("runnerShowExitCode")      private var showExitCode: Bool = true

    // Test runner settings (§3.7)
    @AppStorage("testRunnerEnabled")  private var testRunnerEnabled: Bool = true
    @AppStorage("testRunnerTimeout")  private var testRunnerTimeout: Double = 30
    @AppStorage("testRunnerCoverage") private var testRunnerCoverage: Bool = false
    @AppStorage("testRunnerGutters")  private var testRunnerGutters: Bool = false
    @AppStorage("testRunnerConsole")  private var testRunnerConsole: Bool = true
    @AppStorage("testRunnerFolders")  private var testRunnerFoldersJSON: String = ""

    // Editable row list, synced to the JSON string above.
    @State private var testRows: [TestFolderGlob] = []

    var body: some View {
        Form {
            Section {
                Toggle("Enable hot reload", isOn: $hotReload)
                if hotReload {
                    LabeledContent("Debounce delay") {
                        HStack {
                            Slider(value: $hotReloadDelay, in: 0.1...2.0, step: 0.1)
                                .frame(width: 120)
                            Text(String(format: "%.1f s", hotReloadDelay))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Label("Hot Reload", systemImage: "flame")
            }

            Section {
                Toggle("Clear console on run", isOn: $clearConsoleOnRun)
                Toggle("Scroll to bottom on new output", isOn: $scrollToBottom)
                Toggle("Show exit code on finish", isOn: $showExitCode)
                LabeledContent("Max console lines") {
                    Stepper("\(maxLines)", value: $maxLines,
                            in: 500...10000, step: 500)
                }
            } header: {
                Label("Console", systemImage: "terminal")
            }

            Section {
                LabeledContent("Debug port") {
                    HStack {
                        TextField("", text: Binding(
                            get: { String(debugPort) },
                            set: { if let v = Int($0), v > 0, v < 65536 { debugPort = v } }
                        ))
                        .frame(width: 64)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        Text("(MobDebug default: 8172)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            } header: {
                Label("Debugger", systemImage: "ant")
            }

            Section {
                Toggle("Enable Test Runner", isOn: $testRunnerEnabled)

                if testRunnerEnabled {
                    LabeledContent("Run timeout") {
                        HStack {
                            Slider(value: $testRunnerTimeout, in: 5...300, step: 5)
                                .frame(width: 120)
                            Text("\(Int(testRunnerTimeout)) s")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }

                    Toggle("Enable code coverage", isOn: $testRunnerCoverage)
                    if testRunnerCoverage {
                        Toggle("Show coverage in editor gutter", isOn: $testRunnerGutters)
                            .padding(.leading, 16)
                    }
                    Toggle("Echo test results to console", isOn: $testRunnerConsole)

                    // Editable folder | glob rows. One glob per row (§3.7).
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Test folders")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach($testRows) { $row in
                            HStack(spacing: 6) {
                                TextField("folder", text: $row.folder)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 130)
                                Text("|").foregroundStyle(.tertiary)
                                TextField("glob (e.g. **/*.test.lua)", text: $row.glob)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    testRows.removeAll { $0.id == row.id }
                                    persistRows()
                                } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Remove row")
                            }
                        }
                        Button {
                            testRows.append(TestFolderGlob(folder: "tests", glob: "**/*.lua"))
                            persistRows()
                        } label: {
                            Label("Add folder", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    }
                    .onChange(of: testRows) { _, _ in persistRows() }
                }
            } header: {
                Label("Tests", systemImage: "flask")
            }
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
        .onAppear(perform: loadRows)
    }

    private func loadRows() {
        let decoded = [TestFolderGlob].decode(from: testRunnerFoldersJSON)
        testRows = decoded.isEmpty ? .defaultRows : decoded
    }

    private func persistRows() {
        testRunnerFoldersJSON = testRows.encoded()
    }
}

// MARK: - Keymap

private struct KeymapSettingsView: View {

    private let shortcuts: [(action: String, shortcut: String, icon: String)] = [
        ("Run project",          "⌘R",       "play.fill"),
        ("Stop",                 "⌘.",       "stop.fill"),
        ("Debug",                "⌘⇧D",     "ant.fill"),
        ("Save file",            "⌘S",       "square.and.arrow.down"),
        ("New file",             "⌘N",       "doc.badge.plus"),
        ("Close tab",            "⌘W",       "xmark"),
        ("Find in file",         "⌘F",       "magnifyingglass"),
        ("Find in project",      "⌘⇧F",     "folder.badge.magnifyingglass"),
        ("Toggle console",       "⌘⇧C",     "terminal"),
        ("Jump to line",         "⌘L",       "arrow.right.to.line"),
        ("Comment/uncomment",    "⌘/",       "text.badge.minus"),
        ("Increase font size",   "⌘+",       "textformat.size.larger"),
        ("Decrease font size",   "⌘-",       "textformat.size.smaller"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keyboard shortcuts are fixed and cannot be changed in this version.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            List {
                ForEach(shortcuts, id: \.action) { item in
                    HStack {
                        Image(systemName: item.icon)
                            .frame(width: 18)
                            .foregroundStyle(.secondary)
                        Text(item.action)
                        Spacer()
                        Text(item.shortcut)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .padding(.vertical, 1)
                }
            }
            .listStyle(.inset)
            .frame(height: 300)
            .padding(.bottom, 8)
        }
    }
}
