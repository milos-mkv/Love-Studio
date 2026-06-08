import Foundation

// JSON-RPC client for lua-language-server over stdio. Transport follows
// LoveRunner (Process/Pipe/readabilityHandler); framing/dispatch follows
// DebugSession. GCD throughout.
@Observable
final class LSPClientService {

    enum Status: Equatable {
        case inactive
        case starting
        case active
        case unavailable  // spawn failed or no binary for this arch
    }

    private(set) var status: Status = .inactive

    // Set by StudioView from AppStorage; .none disables spawning.
    var mode: LanguageServerMode = .current

    // MARK: Process + transport

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    // MARK: JSON-RPC state

    private var nextRequestID = 1
    private var responseHandlers: [Int: (Result<Any, LSPError>) -> Void] = [:]
    private var notificationHandlers: [String: (Any) -> Void] = [:]
    private var readBuffer = Data()

    private var rootURL: URL?

    enum LSPError: Error {
        case notRunning
        case server(code: Int, message: String)
        case spawnFailed(Error)
    }

    // MARK: Lifecycle

    func attach(to projectURL: URL) {
        guard mode == .luaCATS else { status = .inactive; return }
        guard process == nil else { return }
        rootURL = projectURL
        start()
    }

    func detach() {
        stop()
        rootURL = nil
    }

    // Sandbox blocks the server from writing next to its binary, so its log and
    // generated-meta dirs are redirected into the app container.
    private static func supportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("LanguageServer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func start() {
        guard let execURL = LanguageServerResolver.resolve(mode: mode) else {
            status = .unavailable
            return
        }
        guard let rootURL else { status = .unavailable; return }

        let p = Process()
        p.executableURL = execURL
        let support = Self.supportDir()
        let logPath = support.appendingPathComponent("log", isDirectory: true)
        let metaPath = support.appendingPathComponent("meta", isDirectory: true)
        try? FileManager.default.createDirectory(at: logPath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: metaPath, withIntermediateDirectories: true)
        p.arguments = ["--logpath=\(logPath.path)", "--metapath=\(metaPath.path)"]

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.ingest(data) }
        }

        // Drain stderr so the pipe never fills and blocks the server.
        errPipe.fileHandleForReading.readabilityHandler = { h in
            _ = h.availableData
        }

        p.terminationHandler = { [weak self, weak p] _ in
            DispatchQueue.main.async {
                guard let self, let p, self.process === p else { return }
                self.teardownProcessState()
                if self.status != .inactive { self.status = .unavailable }
            }
        }

        do {
            try p.run()
            process = p
            stdinPipe = inPipe
            stdoutPipe = outPipe
            stderrPipe = errPipe
            status = .starting
            sendInitialize(rootURL: rootURL)
        } catch {
            status = .unavailable
            process = nil
        }
    }

    func stop() {
        guard let target = process else { status = .inactive; return }
        // The identity guards stop a restart's new process from being torn down
        // by this call's shutdown reply or fallback timer.
        request("shutdown", params: NSNull()) { [weak self, weak target] _ in
            guard let self, let target, self.process === target else { return }
            self.notify("exit", params: NSNull())
            self.teardownProcess()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak target] in
            guard let self, let target, self.process === target else { return }
            self.teardownProcess()
        }
    }

    func restart() {
        let root = rootURL
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, let root else { return }
            self.attach(to: root)
        }
    }

    private func teardownProcess() {
        process?.terminate()
        teardownProcessState()
        status = .inactive
    }

    private func teardownProcessState() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        responseHandlers.removeAll()
        readBuffer.removeAll()
        openDocuments.removeAll()
        diagnostics.removeAll()
    }

    // MARK: JSON-RPC send

    func request(_ method: String, params: Any, completion: @escaping (Result<Any, LSPError>) -> Void) {
        guard let stdinPipe else { completion(.failure(.notRunning)); return }
        let id = nextRequestID
        nextRequestID += 1
        responseHandlers[id] = completion

        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        writeMessage(message, to: stdinPipe)
    }

    func notify(_ method: String, params: Any) {
        guard let stdinPipe else { return }
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ]
        writeMessage(message, to: stdinPipe)
    }

    func onNotification(_ method: String, handler: @escaping (Any) -> Void) {
        notificationHandlers[method] = handler
    }

    private func writeMessage(_ message: [String: Any], to pipe: Pipe) {
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        let header = "Content-Length: \(body.count)\r\n\r\n".data(using: .utf8)!
        pipe.fileHandleForWriting.write(header + body)
    }

    // MARK: JSON-RPC receive (Content-Length framed)

    private func ingest(_ data: Data) {
        readBuffer.append(data)
        while let message = takeFramedMessage() {
            dispatch(message)
        }
    }

    // Pull one complete LSP message out of readBuffer, or nil if incomplete.
    private func takeFramedMessage() -> [String: Any]? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = readBuffer.range(of: separator) else { return nil }

        let headerData = readBuffer[readBuffer.startIndex..<headerEnd.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else {
            readBuffer.removeSubrange(readBuffer.startIndex...headerEnd.lowerBound)
            return nil
        }

        var contentLength = 0
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                contentLength = Int(parts[1]) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        let available = readBuffer.distance(from: bodyStart, to: readBuffer.endIndex)
        guard available >= contentLength else { return nil }  // wait for more data

        let bodyEnd = readBuffer.index(bodyStart, offsetBy: contentLength)
        let bodyData = readBuffer[bodyStart..<bodyEnd]
        readBuffer.removeSubrange(readBuffer.startIndex..<bodyEnd)

        return (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
    }

    private func dispatch(_ message: [String: Any]) {
        // Response to one of our requests (has an id we issued).
        if let id = message["id"] as? Int, let handler = responseHandlers[id] {
            responseHandlers[id] = nil
            if let error = message["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? 0
                let msg = error["message"] as? String ?? "unknown"
                handler(.failure(.server(code: code, message: msg)))
            } else {
                handler(.success(message["result"] ?? NSNull()))
            }
            return
        }

        // Server-initiated notification.
        if let method = message["method"] as? String, message["id"] == nil {
            notificationHandlers[method]?(message["params"] ?? NSNull())
            return
        }

        // Server-initiated request: reply with null so it isn't left waiting.
        if let id = message["id"], message["method"] != nil, let stdinPipe {
            let reply: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": NSNull()]
            writeMessage(reply, to: stdinPipe)
        }
    }

    // MARK: initialize

    private func sendInitialize(rootURL: URL) {
        let params: [String: Any] = [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "rootUri": rootURL.absoluteString,
            "capabilities": [
                "textDocument": [
                    "completion": ["completionItem": ["snippetSupport": false]],
                    "hover": ["contentFormat": ["markdown", "plaintext"]],
                    "signatureHelp": [:],
                    "publishDiagnostics": [:],
                ],
            ],
        ]
        request("initialize", params: params) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.notify("initialized", params: [String: Any]())
                self.registerDiagnosticsHandler()
                self.status = .active
            case .failure:
                self.status = .unavailable
                self.teardownProcess()
            }
        }
    }

    // MARK: Document sync (textDocument/did*)

    // Open documents: URI -> current version.
    private var openDocuments: [String: Int] = [:]

    func isOpen(_ url: URL) -> Bool { openDocuments[url.absoluteString] != nil }

    func documentVersion(_ url: URL) -> Int? { openDocuments[url.absoluteString] }

    func didOpen(_ url: URL, text: String) {
        guard status == .active else { return }
        let uri = url.absoluteString
        guard openDocuments[uri] == nil else { return }
        openDocuments[uri] = 1
        notify("textDocument/didOpen", params: [
            "textDocument": [
                "uri": uri,
                "languageId": "lua",
                "version": 1,
                "text": text,
            ],
        ])
    }

    @discardableResult
    func didChange(_ url: URL, text: String) -> Int? {
        guard status == .active else { return nil }
        let uri = url.absoluteString
        guard let current = openDocuments[uri] else { return nil }
        let version = current + 1
        openDocuments[uri] = version
        notify("textDocument/didChange", params: [
            "textDocument": ["uri": uri, "version": version],
            "contentChanges": [["text": text]],  // full-document sync
        ])
        return version
    }

    func didSave(_ url: URL) {
        guard status == .active, openDocuments[url.absoluteString] != nil else { return }
        notify("textDocument/didSave", params: [
            "textDocument": ["uri": url.absoluteString],
        ])
    }

    func didClose(_ url: URL) {
        guard status == .active else { return }
        let uri = url.absoluteString
        guard openDocuments[uri] != nil else { return }
        openDocuments[uri] = nil
        diagnostics[uri] = nil
        notify("textDocument/didClose", params: [
            "textDocument": ["uri": uri],
        ])
    }

    // LSP keys documents by URI, so a rename is a close of the old + open of the new.
    func didRename(from oldURL: URL, to newURL: URL, text: String) {
        didClose(oldURL)
        didOpen(newURL, text: text)
    }

    // MARK: Diagnostics (textDocument/publishDiagnostics)

    enum DiagnosticSeverity: Int {
        case error = 1, warning = 2, information = 3, hint = 4
    }

    struct Diagnostic: Identifiable {
        let id = UUID()
        let message: String
        let severity: DiagnosticSeverity
        // 0-based positions in realText space.
        let startLine: Int
        let startCharacter: Int
        let endLine: Int
        let endCharacter: Int
        // Original server dict, echoed back as codeAction context.
        let raw: [String: Any]
    }

    private(set) var diagnostics: [String: [Diagnostic]] = [:]

    func diagnostics(for url: URL) -> [Diagnostic] {
        diagnostics[url.absoluteString] ?? []
    }

    var diagnosticCounts: (errors: Int, warnings: Int) {
        var e = 0, w = 0
        for list in diagnostics.values {
            for d in list {
                if d.severity == .error { e += 1 }
                else if d.severity == .warning { w += 1 }
            }
        }
        return (e, w)
    }

    private func registerDiagnosticsHandler() {
        onNotification("textDocument/publishDiagnostics") { [weak self] params in
            guard let self, let obj = params as? [String: Any],
                  let uri = obj["uri"] as? String else { return }

            // Drop a batch computed against a stale version so squiggles never
            // land on text the server didn't analyze.
            if let incoming = obj["version"] as? Int,
               let current = self.openDocuments[uri],
               incoming != current {
                return
            }

            let rawList = obj["diagnostics"] as? [[String: Any]] ?? []
            let parsed: [Diagnostic] = rawList.compactMap { d in
                guard let message = d["message"] as? String,
                      let range = d["range"] as? [String: Any],
                      let start = range["start"] as? [String: Any],
                      let end = range["end"] as? [String: Any],
                      let sl = start["line"] as? Int, let sc = start["character"] as? Int,
                      let el = end["line"] as? Int, let ec = end["character"] as? Int else { return nil }
                let sev = DiagnosticSeverity(rawValue: d["severity"] as? Int ?? 1) ?? .error
                return Diagnostic(message: message, severity: sev,
                                  startLine: sl, startCharacter: sc, endLine: el, endCharacter: ec, raw: d)
            }
            self.diagnostics[uri] = parsed
        }
    }

    // MARK: Language features (completion, signatureHelp)

    struct CompletionResult {
        let label: String
        let insertText: String
    }

    struct SignatureResult {
        let label: String
        let activeParameter: Int
    }

    // A server-computed quick-fix: a WorkspaceEdit, a Command, or both.
    struct CodeAction {
        let title: String
        fileprivate let edit: [String: Any]?
        fileprivate let command: [String: Any]?
    }

    // Request quick-fixes for the diagnostics overlapping the given 0-based range.
    func requestCodeActions(_ url: URL, startLine: Int, startCharacter: Int,
                            endLine: Int, endCharacter: Int,
                            diagnostics: [Diagnostic],
                            completion: @escaping ([CodeAction]) -> Void) {
        guard status == .active, isOpen(url) else { completion([]); return }
        let params: [String: Any] = [
            "textDocument": ["uri": url.absoluteString],
            "range": [
                "start": ["line": startLine, "character": startCharacter],
                "end": ["line": endLine, "character": endCharacter],
            ],
            "context": ["diagnostics": diagnostics.map { $0.raw }],
        ]
        request("textDocument/codeAction", params: params) { result in
            DispatchQueue.main.async { completion(Self.parseCodeActions(result)) }
        }
    }

    private static func parseCodeActions(_ result: Result<Any, LSPError>) -> [CodeAction] {
        guard case .success(let value) = result, let list = value as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let title = item["title"] as? String else { return nil }
            return CodeAction(title: title,
                              edit: item["edit"] as? [String: Any],
                              command: item["command"] as? [String: Any])
        }
    }

    // Apply the action's edit (editApplier writes it to the live buffer) then its
    // command via workspace/executeCommand.
    func apply(_ action: CodeAction,
               editApplier: @escaping (_ uri: String, _ edits: [[String: Any]]) -> Void) {
        if let edit = action.edit, let changes = edit["changes"] as? [String: [[String: Any]]] {
            for (uri, edits) in changes { editApplier(uri, edits) }
        }
        if let command = action.command, let cmd = command["command"] as? String {
            var params: [String: Any] = ["command": cmd]
            if let args = command["arguments"] { params["arguments"] = args }
            request("workspace/executeCommand", params: params) { _ in }
        }
    }

    func requestCompletion(_ url: URL, line: Int, character: Int,
                           completion: @escaping ([CompletionResult]) -> Void) {
        guard status == .active, isOpen(url) else { completion([]); return }
        let params: [String: Any] = [
            "textDocument": ["uri": url.absoluteString],
            "position": ["line": line, "character": character],
        ]
        request("textDocument/completion", params: params) { result in
            DispatchQueue.main.async { completion(Self.parseCompletion(result)) }
        }
    }

    func requestHover(_ url: URL, line: Int, character: Int,
                      completion: @escaping (String?) -> Void) {
        guard status == .active, isOpen(url) else { completion(nil); return }
        let params: [String: Any] = [
            "textDocument": ["uri": url.absoluteString],
            "position": ["line": line, "character": character],
        ]
        request("textDocument/hover", params: params) { result in
            DispatchQueue.main.async { completion(Self.parseHover(result)) }
        }
    }

    private static func parseHover(_ result: Result<Any, LSPError>) -> String? {
        guard case .success(let value) = result, let obj = value as? [String: Any] else { return nil }
        // contents may be MarkupContent, a MarkedString, or an array of either.
        let contents = obj["contents"]
        if let markup = contents as? [String: Any], let v = markup["value"] as? String {
            return v.isEmpty ? nil : v
        }
        if let s = contents as? String {
            return s.isEmpty ? nil : s
        }
        if let arr = contents as? [Any] {
            let parts: [String] = arr.compactMap { el in
                if let s = el as? String { return s }
                if let d = el as? [String: Any] { return d["value"] as? String }
                return nil
            }
            let joined = parts.joined(separator: "\n\n")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    func requestSignatureHelp(_ url: URL, line: Int, character: Int,
                              completion: @escaping (SignatureResult?) -> Void) {
        guard status == .active, isOpen(url) else { completion(nil); return }
        let params: [String: Any] = [
            "textDocument": ["uri": url.absoluteString],
            "position": ["line": line, "character": character],
        ]
        request("textDocument/signatureHelp", params: params) { result in
            DispatchQueue.main.async { completion(Self.parseSignatureHelp(result)) }
        }
    }

    private static func parseCompletion(_ result: Result<Any, LSPError>) -> [CompletionResult] {
        guard case .success(let value) = result else { return [] }
        // Result is either CompletionItem[] or { items: CompletionItem[] }.
        let items: [[String: Any]]
        if let list = value as? [[String: Any]] {
            items = list
        } else if let obj = value as? [String: Any], let list = obj["items"] as? [[String: Any]] {
            items = list
        } else {
            return []
        }
        return items.compactMap { item in
            guard let label = item["label"] as? String else { return nil }
            // Prefer insertText, then textEdit.newText, else the label.
            let insert = (item["insertText"] as? String)
                ?? ((item["textEdit"] as? [String: Any])?["newText"] as? String)
                ?? label
            return CompletionResult(label: label, insertText: insert)
        }
    }

    private static func parseSignatureHelp(_ result: Result<Any, LSPError>) -> SignatureResult? {
        guard case .success(let value) = result,
              let obj = value as? [String: Any],
              let sigs = obj["signatures"] as? [[String: Any]], !sigs.isEmpty else { return nil }
        let activeSig = obj["activeSignature"] as? Int ?? 0
        let sig = sigs[min(activeSig, sigs.count - 1)]
        guard let label = sig["label"] as? String else { return nil }
        // activeParameter can live on the SignatureHelp or the signature.
        let activeParam = (sig["activeParameter"] as? Int)
            ?? (obj["activeParameter"] as? Int)
            ?? 0
        return SignatureResult(label: label, activeParameter: activeParam)
    }
}
