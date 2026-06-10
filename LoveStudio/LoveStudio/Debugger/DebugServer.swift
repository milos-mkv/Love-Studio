import Foundation
import Network

@Observable
final class DebugServer {
    var isListening  = false
    var isPaused     = false
    var pausedFile   : String?
    var pausedLine   : Int?
    var callStack    : [DebugStackFrame] = []
    var localVars    : [DebugVariable]   = []

    var onPaused       : ((String, Int) -> Void)?
    var onResumed      : (() -> Void)?
    var onLog          : ((String) -> Void)?
    var onDisconnected : (() -> Void)?

    private var listener         : NWListener?
    private(set) var session     : DebugSession?
    private var breakpointManager: BreakpointManager?
    private var projectRootURL   : URL?
    private var lineOffsetFile   : String?
    var lineOffset = 0

    func configure(projectRootURL: URL?, lineOffsetFile: String?, lineOffset: Int) {
        self.projectRootURL = projectRootURL
        self.lineOffsetFile = lineOffsetFile
        self.lineOffset     = lineOffset
    }

    func start(breakpointManager: BreakpointManager) {
        self.breakpointManager = breakpointManager
        guard listener == nil else { return }

        do {
            listener = try NWListener(using: .tcp, on: 8172)
        } catch {
            onLog?("⚠️ Debug server failed to start: \(error.localizedDescription)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isListening = true
                    self?.onLog?("── Debug server listening on :8172 ──")
                case .failed(let error):
                    self?.isListening = false
                    self?.onLog?("⚠️ Debug server error: \(error)")
                default: break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        session?.cancel()
        session = nil
        listener?.cancel()
        listener = nil
        isListening = false
        resetPausedState(clearSessionData: true)
        onResumed?()   // clear any paused-line highlight in the editor
    }

    func resume()   {
        resetPausedState(clearSessionData: true); onResumed?()
        onLog?("▶ Continue"); session?.run()
    }
    func step()     {
        resetPausedState(clearSessionData: true); onResumed?()
        onLog?("↘ Step Into"); session?.step()
    }
    func stepOver() {
        resetPausedState(clearSessionData: true); onResumed?()
        onLog?("↷ Step Over"); session?.stepOver()
    }
    func stepOut()  {
        resetPausedState(clearSessionData: true); onResumed?()
        onLog?("↥ Step Out"); session?.stepOut()
    }

    func addBreakpoint(file: String, line: Int) {
        onLog?("◎ Breakpoint set at \(file):\(line)")
        session?.setBreakpoint(file: file, line: outgoingLine(for: file, requestedLine: line))
    }

    func removeBreakpoint(file: String, line: Int) {
        onLog?("○ Breakpoint removed at \(file):\(line)")
        session?.deleteBreakpoint(file: file, line: outgoingLine(for: file, requestedLine: line))
    }

    func load(file: String, source: String) {
        guard isPaused else {
            onLog?("⚠️ LOAD only works while paused - set a breakpoint first")
            return
        }
        onLog?("↺ Reloading \(file)…")
        session?.load(filename: file, source: source) { [weak self] result in
            if result.hasPrefix("401") {
                self?.onLog?("⚠️ LOAD error: \(result)")
            } else {
                self?.onLog?("✓ \(file) reloaded")
            }
        }
    }

    func evaluate(_ expression: String, completion: @escaping (String) -> Void) {
        guard isPaused else { completion("Not paused"); return }
        session?.evaluate(expression) { [weak self] result in
            self?.onLog?("[EXEC] \(result.prefix(200))")
            completion(result)
        }
    }

    // MARK: Private

    private func accept(_ connection: NWConnection) {
        let session = DebugSession(connection: connection)
        self.session = session

        session.onPaused = { [weak self, weak session] file, line in
            guard let self, self.session === session else { return }
            let normalized = self.normalizedProjectPath(file)
            let realLine   = self.incomingLine(for: normalized, reportedLine: line)
            self.isPaused   = true
            self.pausedFile = normalized
            self.pausedLine = realLine
            self.onPaused?(normalized, realLine)
            self.onLog?("⏸ Paused at \(normalized):\(realLine)")
            session?.requestStack { [weak self] frames in
                self?.callStack = frames.map { frame in
                    let nf = self?.normalizedProjectPath(frame.file) ?? frame.file
                    return DebugStackFrame(
                        file: nf,
                        line: self?.incomingLine(for: nf, reportedLine: frame.line) ?? frame.line,
                        functionName: frame.functionName
                    )
                }
            }
        }

        session.onResumed = { [weak self, weak session] in
            guard let self, self.session === session else { return }
            self.resetPausedState(clearSessionData: true)
            self.onResumed?()
        }

        session.onLocals = { [weak self, weak session] variables in
            guard let self, self.session === session else { return }
            self.localVars = variables
        }

        session.onTerminated = { [weak self, weak session] in
            guard let self, self.session === session else { return }
            self.resetPausedState(clearSessionData: true)
            self.session = nil
            self.onLog?("── Debugger disconnected ──")
            self.onDisconnected?()
        }

        if let breakpointManager {
            for (file, lines) in breakpointManager.breakpoints {
                for line in lines {
                    session.setBreakpoint(file: file, line: outgoingLine(for: file, requestedLine: line))
                }
            }
        }

        session.run()
        onLog?("── Debugger connected ──")
    }

    private func resetPausedState(clearSessionData: Bool) {
        isPaused   = false
        pausedFile = nil
        pausedLine = nil
        if clearSessionData { callStack = []; localVars = [] }
    }

    private func outgoingLine(for file: String, requestedLine: Int) -> Int {
        guard file == lineOffsetFile else { return requestedLine }
        return requestedLine + lineOffset
    }

    private func incomingLine(for file: String, reportedLine: Int) -> Int {
        guard file == lineOffsetFile else { return reportedLine }
        return max(1, reportedLine - lineOffset)
    }

    private func normalizedProjectPath(_ debuggerPath: String) -> String {
        let cleaned = debuggerPath.replacingOccurrences(of: "\\", with: "/")
        guard cleaned != "?" else { return cleaned }

        if let projectRootURL {
            let absolute = URL(fileURLWithPath: cleaned).standardizedFileURL
            let rootPath = projectRootURL.standardizedFileURL.path + "/"
            if absolute.path.hasPrefix(rootPath) {
                return String(absolute.path.dropFirst(rootPath.count))
            }
            let candidate = projectRootURL.appendingPathComponent(cleaned).standardizedFileURL
            if FileManager.default.fileExists(atPath: candidate.path) { return cleaned }
        }

        if !cleaned.contains("/") {
            let matches = breakpointManager?.breakpoints.keys.filter {
                ($0 as NSString).lastPathComponent == cleaned
            } ?? []
            if matches.count == 1 { return matches[0] }
        }

        return cleaned
    }
}
