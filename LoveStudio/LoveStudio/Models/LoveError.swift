import Foundation

// MARK: - LoveError model

struct LoveError: Identifiable {
    let id = UUID()
    let message: String
    let file: String?
    let line: Int?
    let stackTrace: [StackFrame]

    var shortDescription: String {
        if let file, let line {
            return "\(file):\(line) — \(cleanMessage)"
        }
        return cleanMessage
    }

    var cleanMessage: String {
        // Ukloni "file:line: " prefix ako postoji
        if let range = message.range(of: #"^.*:\d+: "#, options: .regularExpression) {
            return String(message[range.upperBound...])
        }
        return message
    }
}

struct StackFrame: Identifiable {
    let id = UUID()
    let file: String
    let line: Int?
    let context: String  // npr. "in function 'love.draw'"

    var displayName: String {
        if let line { return "\(file):\(line)" }
        return file
    }
}

// MARK: - Parser

struct LoveErrorParser {

    /// Parsira LÖVE stderr output i vraca LoveError ako ga nadje
    static func parse(lines: [String]) -> LoveError? {
        let text = lines.joined(separator: "\n")
        let nsText = text as NSString

        // Podržani formati:
        // 1. "main.lua:42: attempt to index..."
        // 2. "Error: Syntax error: main.lua:10: '=' expected..."
        // 3. "Error in thread 'main':\nmain.lua:42: ..."

        let patterns = [
            // Sa prefiksom "Error:" ili "Syntax error:"
            #"(?:Error:\s*)?(?:Syntax error:\s*)?([^\s:]+\.lua):(\d+):\s*(.+)"#,
        ]

        var errorFile: String?
        var errorLine: Int?
        var errorMessage: String?

        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { continue }
            if let match = re.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) {
                errorFile    = nsText.substring(with: match.range(at: 1))
                errorLine    = Int(nsText.substring(with: match.range(at: 2)))
                errorMessage = nsText.substring(with: match.range(at: 3))
                break
            }
        }

        guard let msg = errorMessage else { return nil }

        // Parsiramo stack trace — podržava i [love "callbacks.lua"] i [C] formate
        let stackPattern = #"^\s+\[?([^\]]+\.lua)"?:(\d+): (in .+)$"#
        var frames: [StackFrame] = []
        if let stackRe = try? NSRegularExpression(pattern: stackPattern, options: .anchorsMatchLines) {
            let matches = stackRe.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let file    = nsText.substring(with: match.range(at: 1))
                let line    = Int(nsText.substring(with: match.range(at: 2)))
                let context = nsText.substring(with: match.range(at: 3))
                frames.append(StackFrame(file: file, line: line, context: context))
            }
        }

        return LoveError(
            message: msg,
            file: errorFile,
            line: errorLine,
            stackTrace: frames
        )
    }

    /// Proverava da li linija izgleda kao LÖVE error
    static func looksLikeError(_ line: String) -> Bool {
        line.contains(".lua:") && (
            line.contains("Error") ||
            line.contains("attempt to") ||
            line.contains("stack traceback") ||
            line.contains(": in ")
        )
    }
}
