import Foundation
import Network

struct DebugStackFrame: Identifiable {
    let id = UUID()
    let file: String
    let line: Int
    let functionName: String
}

struct DebugVariable: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let type: String
    let scope: String
    let tableKey: String
}

final class DebugSession {
    var onPaused: ((String, Int) -> Void)?
    var onResumed: (() -> Void)?
    var onTerminated: (() -> Void)?
    var onLocals: (([DebugVariable]) -> Void)?

    private let connection: NWConnection
    private var lineBuffer = Data()

    private struct PendingResponse {
        let multiline: Bool
        let handler: (String) -> Void
    }

    private var pending: [PendingResponse] = []
    private var multilineAccum = ""
    private var inMultiline = false

    init(connection: NWConnection) {
        self.connection = connection
        connection.start(queue: .global(qos: .userInitiated))
        receiveNext()
    }

    func cancel() { connection.cancel() }

    func run()      { send("RUN") }
    func step()     { send("STEP") }
    func stepOver() { send("OVER") }
    func stepOut()  { send("OUT") }

    func setBreakpoint(file: String, line: Int)    { send("SETB \(file) \(line)") }
    func deleteBreakpoint(file: String, line: Int) { send("DELB \(file) \(line)") }

    func load(filename: String, source: String, completion: ((String) -> Void)? = nil) {
        let bytes = source.utf8.count
        pending.append(PendingResponse(multiline: false) { result in
            DispatchQueue.main.async { completion?(result) }
        })
        // Send header line, then raw bytes without trailing newline
        let header = ("LOAD \(bytes) \(filename)\n").data(using: .utf8)!
        let body   = source.data(using: .utf8)!
        connection.send(content: header + body, completion: .contentProcessed { _ in })
    }

    func requestStack(completion: @escaping ([DebugStackFrame]) -> Void) {
        pending.append(PendingResponse(multiline: true) { [weak self] raw in
            let frames = Self.parseStack(raw)
            DispatchQueue.main.async { completion(frames) }
            self?.requestLocalsInternal()
        })
        send("STACK")
    }

    func evaluate(_ expression: String, completion: @escaping (String) -> Void) {
        pending.append(PendingResponse(multiline: true) { raw in
            DispatchQueue.main.async {
                completion(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        })
        send("EXEC \(expression)")
    }

    private func requestLocalsInternal() {
        pending.append(PendingResponse(multiline: true) { [weak self] raw in
            let variables = Self.parseLocals(raw)
            DispatchQueue.main.async { self?.onLocals?(variables) }
        })
        send("LOCALS")
    }

    private func send(_ message: String) {
        let data = (message + "\n").data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.lineBuffer.append(data)
                self.processBuffer()
            }
            if isComplete || error != nil {
                DispatchQueue.main.async { self.onTerminated?() }
                return
            }
            self.receiveNext()
        }
    }

    private func processBuffer() {
        while let index = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = lineBuffer[lineBuffer.startIndex..<index]
            lineBuffer = Data(lineBuffer[lineBuffer.index(after: index)...])
            if let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty {
                handleLine(line)
            }
        }
    }

    private func handleLine(_ line: String) {
        if inMultiline {
            if line == "END" {
                inMultiline = false
                let accum = multilineAccum
                multilineAccum = ""
                pending.removeFirst().handler(accum)
            } else if !line.hasPrefix("200 OK") {
                multilineAccum += line + "\n"
            }
            return
        }

        if line.hasPrefix("202 Paused") {
            let parts = line.components(separatedBy: " ")
            if parts.count >= 4, let lineNumber = Int(parts[parts.count - 1]) {
                let file = parts[2..<(parts.count - 1)].joined(separator: " ")
                DispatchQueue.main.async { self.onPaused?(file, lineNumber) }
            }
            return
        }

        guard !pending.isEmpty else { return }
        let next = pending[0]

        if line.hasPrefix("200 OK") {
            if next.multiline {
                inMultiline = true
                multilineAccum = ""
            } else {
                pending.removeFirst().handler("")
            }
        } else if line.hasPrefix("401 Error") {
            let message = line.components(separatedBy: " ").dropFirst(3).joined(separator: " ")
            pending.removeFirst().handler("Error: \(message)")
        }
    }

    private static func parseStack(_ raw: String) -> [DebugStackFrame] {
        var frames: [DebugStackFrame] = []
        guard let pattern = try? NSRegularExpression(
            pattern: #"\{file="([^"]*)",line=(\d+),name="([^"]*)"\}"#
        ) else { return [] }
        let ns = raw as NSString
        pattern.enumerateMatches(in: raw, range: NSRange(raw.startIndex..., in: raw)) { match, _, _ in
            guard let match else { return }
            frames.append(DebugStackFrame(
                file: ns.substring(with: match.range(at: 1)),
                line: Int(ns.substring(with: match.range(at: 2))) ?? 0,
                functionName: ns.substring(with: match.range(at: 3))
            ))
        }
        return frames
    }

    private static func parseLocals(_ raw: String) -> [DebugVariable] {
        var variables: [DebugVariable] = []
        guard let pattern = try? NSRegularExpression(
            pattern: #"\{name="([^"]*)",value="([^"]*)",type="([^"]*)",scope="([^"]*)",tkey="([^"]*)"\}"#
        ) else { return [] }
        let ns = raw as NSString
        pattern.enumerateMatches(in: raw, range: NSRange(raw.startIndex..., in: raw)) { match, _, _ in
            guard let match else { return }
            variables.append(DebugVariable(
                name: ns.substring(with: match.range(at: 1)),
                value: ns.substring(with: match.range(at: 2)),
                type: ns.substring(with: match.range(at: 3)),
                scope: ns.substring(with: match.range(at: 4)),
                tableKey: ns.substring(with: match.range(at: 5))
            ))
        }
        return variables
    }
}
