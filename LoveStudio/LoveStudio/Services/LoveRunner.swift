import Foundation
import AppKit

// MARK: - ConsoleLine

struct ConsoleLine: Identifiable {
    let id        = UUID()
    let text      : String
    let kind      : Kind
    let timestamp : Date = .now
    let errorRef  : ErrorRef?   // non-nil when line is a parseable LÖVE error

    init(_ text: String, kind: Kind, errorRef: ErrorRef? = nil) {
        self.text     = text
        self.kind     = kind
        self.errorRef = errorRef
    }

    enum Kind { case stdout, stderr, system }

    struct ErrorRef {
        let file : String   // e.g. "main.lua"
        let line : Int
    }
}

// MARK: - LoveRunner

@Observable
final class LoveRunner {
    private(set) var isRunning   = false
    private(set) var lines       : [ConsoleLine] = []
    private(set) var lastExitCode: Int32? = nil

    // Settings - set by StudioView from AppStorage
    var hotReloadEnabled:  Bool   = true
    var hotReloadDelay:    Double = 0.5
    var clearOnRun:        Bool   = true
    var maxLines:          Int    = 2000
    var debugPort:         Int    = 8172

    // Called when a LÖVE error with file+line is detected
    var onErrorJump: ((String, Int) -> Void)?
    // Called when the process terminates (used by debug session cleanup)
    var onTerminate: (() -> Void)?

    private var process    : Process?
    private var stdoutPipe : Pipe?
    private var stderrPipe : Pipe?

    // Hot reload
    private var hotReloadSources: [DispatchSourceFileSystemObject] = []
    private var hotReloadWorkItem: DispatchWorkItem?
    private var watchedProjectURL: URL?
    private var loveAppURL: URL?

    // Debug - files injected into the project directory for the debug session
    // Kept so we can clean them up precisely on stop/restore.
    private var debugInjectedFiles: [URL] = [] // mobdebug.lua + __ls_debug_main.lua

    private(set) var debugLineOffset    = 0
    private(set) var debugLineOffsetFile: String?

    // MARK: Public API

    func run(projectURL: URL, loveAppURL: URL) {
        runInternal(projectURL: projectURL, loveAppURL: loveAppURL, debugMode: false)
    }

    func runDebug(projectURL: URL, loveAppURL: URL) {
        runInternal(projectURL: projectURL, loveAppURL: loveAppURL, debugMode: true)
    }

    private func runInternal(projectURL: URL, loveAppURL: URL, debugMode: Bool) {
        guard !isRunning else { stop(); return }
        self.watchedProjectURL = projectURL
        self.loveAppURL        = loveAppURL
        lastExitCode = nil
        if clearOnRun { lines = [] }

        cleanupDebugTempDir()   // always remove any leftover temp dir from a previous session

        var gameURL = projectURL
        if debugMode {
            do {
                gameURL = try buildDebugLauncher(for: projectURL)
            } catch {
                append("Error preparing debug runtime: \(error.localizedDescription)", kind: .system)
                return
            }
        }

        launch(projectURL: projectURL, gameURL: gameURL, loveAppURL: loveAppURL, debugMode: debugMode)
        if !debugMode && hotReloadEnabled { startHotReload(projectURL: projectURL) }
    }

    func stop() {
        stopHotReload()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process    = nil
        stdoutPipe = nil
        stderrPipe = nil
        isRunning  = false
        append("■ Stopped", kind: .system)
    }

    func clear() { lines = [] }

    func log(_ text: String, kind: ConsoleLine.Kind = .system) {
        append(text, kind: kind)
    }

    // MARK: Launch

    private func launch(projectURL: URL, gameURL: URL, loveAppURL: URL, debugMode: Bool = false) {
        let execURL = loveAppURL.appendingPathComponent("Contents/MacOS/love")
        guard FileManager.default.isExecutableFile(atPath: execURL.path) else {
            append("love executable not found at: \(execURL.path)", kind: .system)
            return
        }

        lines = []
        append(debugMode ? "🐞 Debug: \(projectURL.lastPathComponent)" : "▶ Running: \(projectURL.lastPathComponent)", kind: .system)

        let p = Process()
        p.executableURL       = execURL
        p.arguments           = [gameURL.path]   // temp launcher dir for debug, project dir otherwise
        p.currentDirectoryURL = projectURL

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError  = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                str.components(separatedBy: "\n").filter { !$0.isEmpty }.forEach {
                    self?.append($0, kind: .stdout)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                str.components(separatedBy: "\n").filter { !$0.isEmpty }.forEach {
                    self?.appendError($0)
                }
            }
        }

        p.terminationHandler = { [weak self, weak p] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                // Ignore stale termination from a process replaced during hot reload.
                // Compare by object identity: if self.process is already a different
                // instance, the new process is running and we must not touch its state.
                guard let p, self.process === p else { return }
                self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                let code = proc.terminationStatus
                self.lastExitCode = code
                self.append("■ Finished (exit \(code))", kind: .system)
                self.process    = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
                self.isRunning  = false
                self.restoreDebugRuntime(in: projectURL)
                self.onTerminate?()
            }
        }

        do {
            try p.run()
            self.process    = p
            self.stdoutPipe = outPipe
            self.stderrPipe = errPipe
            isRunning = true
            append("ℹ️ pid \(p.processIdentifier)", kind: .system)
        } catch {
            append("Launch error: \(error.localizedDescription)", kind: .stderr)
        }
    }

    // MARK: Error parsing

    /// Appends a stderr line, attaching ErrorRef if it matches LÖVE error format.
    /// LÖVE errors look like:  `Error\n\nmain.lua:12: attempt to ...`
    /// or inline:              `main.lua:12: ...`
    private func appendError(_ text: String) {
        let ref = parseErrorRef(from: text)
        lines.append(ConsoleLine(text, kind: .stderr, errorRef: ref))
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    private func parseErrorRef(from text: String) -> ConsoleLine.ErrorRef? {
        // Pattern: filename.lua:NUMBER: message
        let pattern = #"^(.+\.lua):(\d+):"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text,
                  range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let fileRange = Range(match.range(at: 1), in: text),
              let lineRange = Range(match.range(at: 2), in: text),
              let lineNum = Int(text[lineRange])
        else { return nil }
        return ConsoleLine.ErrorRef(file: String(text[fileRange]), line: lineNum)
    }

    // MARK: Hot Reload

    private func startHotReload(projectURL: URL) {
        // Cancel sources only - do NOT cancel hotReloadWorkItem here.
        // If a save arrived between workItem dispatch and this main-queue call,
        // cancelling the work item would silently drop that reload.
        hotReloadSources.forEach { $0.cancel() }
        hotReloadSources = []
        let fm = FileManager.default

        // Collect the project root + all subdirectories.
        // Watching directories (not individual files) works with atomic saves:
        // when a file is renamed into place the parent directory fires a .write event.
        var dirs: [URL] = [projectURL]
        if let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    dirs.append(url)
                }
            }
        }

        for dirURL in dirs {
            let fd = open(dirURL.path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: .write,
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                self?.scheduleRestart()
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            hotReloadSources.append(source)
        }

        if !hotReloadSources.isEmpty {
            append("🔥 Hot reload watching \(hotReloadSources.count) director\(hotReloadSources.count == 1 ? "y" : "ies")", kind: .system)
        }
    }

    private func stopHotReload() {
        hotReloadWorkItem?.cancel()
        hotReloadWorkItem = nil
        hotReloadSources.forEach { $0.cancel() }
        hotReloadSources = []
    }

    private func scheduleRestart() {
        hotReloadWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning,
                  let projectURL = self.watchedProjectURL,
                  let loveURL    = self.loveAppURL else { return }
            DispatchQueue.main.async {
                self.append("🔄 Hot reload - restarting…", kind: .system)
                self.stopProcess()
                self.launch(projectURL: projectURL, gameURL: projectURL, loveAppURL: loveURL)
                self.startHotReload(projectURL: projectURL)
            }
        }
        hotReloadWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + hotReloadDelay, execute: work)
    }

    /// Stops only the process (not hot reload watchers).
    private func stopProcess() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process    = nil
        stdoutPipe = nil
        stderrPipe = nil
        isRunning  = false
    }

    // MARK: Append

    private func append(_ text: String, kind: ConsoleLine.Kind) {
        lines.append(ConsoleLine(text, kind: kind))
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    // MARK: Debug Launcher (inject into project - no temp dir, full filesystem access)

    /// Injects mobdebug.lua and a thin bootstrap wrapper into the project directory,
    /// then returns the project URL so LÖVE runs directly from the real project.
    /// This ensures love.filesystem works identically to normal (non-debug) mode -
    /// all asset paths, audio streams, etc., resolve correctly.
    ///
    /// Injected files are tracked in debugInjectedFiles and removed by restoreDebugRuntime().
    private func buildDebugLauncher(for projectURL: URL) throws -> URL {
        guard let mobdebugSource = Bundle.main.url(forResource: "mobdebug", withExtension: "lua") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        debugInjectedFiles = []

        // 1. Copy mobdebug.lua into the project root (will be removed on stop)
        let mobdebugDest = projectURL.appendingPathComponent("mobdebug.lua")
        if fm.fileExists(atPath: mobdebugDest.path) {
            try fm.removeItem(at: mobdebugDest)
        }
        try fm.copyItem(at: mobdebugSource, to: mobdebugDest)
        debugInjectedFiles.append(mobdebugDest)

        // 2. Read the project's real main.lua
        let realMain     = projectURL.appendingPathComponent("main.lua")
        let originalSrc  = (try? String(contentsOf: realMain, encoding: .utf8)) ?? ""

        // 3. Write a wrapper main.lua that starts mobdebug then runs the original source.
        //    We embed the original source as a loaded chunk so:
        //      - No file rename/backup is needed
        //      - Debugger sees correct '@main.lua' chunk name → line numbers are exact
        let escaped = originalSrc
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        // Use a sentinel file instead of embedding the source, to avoid size limits and
        // escaping edge cases. We write the original main to a hidden backup, then load it.
        let backupMain = projectURL.appendingPathComponent("__ls_main_bak.lua")
        try originalSrc.write(to: backupMain, atomically: true, encoding: .utf8)
        debugInjectedFiles.append(backupMain)

        let wrapper = """
-- [LÖVE Studio] debug bootstrap - auto-generated, do not edit
-- This file is removed automatically when the debug session ends.
require('mobdebug').start('localhost', 8172)
local _f = assert(io.open(\(backupMain.path.luaStringLiteral), "r"))
local _src = _f:read("*a"); _f:close()
assert(load(_src, "@main.lua"))()
"""
        // Overwrite main.lua with the wrapper
        try wrapper.write(to: realMain, atomically: true, encoding: .utf8)
        // Track it so we restore it on stop
        debugInjectedFiles.append(realMain)

        debugLineOffset     = 0
        debugLineOffsetFile = nil

        // Return the project URL - LÖVE runs from the real project directory
        return projectURL
    }

    /// Restores main.lua and removes injected debug files from the project.
    func restoreDebugRuntime(in projectURL: URL) {
        cleanupDebugTempDir()
    }

    private func cleanupDebugTempDir() {
        defer {
            debugInjectedFiles  = []
            debugLineOffset     = 0
            debugLineOffsetFile = nil
        }
        let fm = FileManager.default

        // Find the backup and wrapper among injected files
        let backupURL  = debugInjectedFiles.first { $0.lastPathComponent == "__ls_main_bak.lua" }
        let mainURL    = debugInjectedFiles.first { $0.lastPathComponent == "main.lua" }
        let mobdebugURL = debugInjectedFiles.first { $0.lastPathComponent == "mobdebug.lua" }

        // Restore original main.lua from backup
        if let backup = backupURL, let main = mainURL,
           fm.fileExists(atPath: backup.path) {
            let original = (try? String(contentsOf: backup, encoding: .utf8)) ?? ""
            try? original.write(to: main, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: backup)
        }

        // Remove mobdebug.lua
        if let mob = mobdebugURL {
            try? fm.removeItem(at: mob)
        }
    }
}

// MARK: - String helper

private extension String {
    /// Wraps the string in a Lua double-quoted string literal, escaping backslashes and quotes.
    var luaStringLiteral: String {
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
