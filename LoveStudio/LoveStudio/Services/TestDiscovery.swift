import Foundation

// MARK: - TestDiscovery
//
// Static discovery (§5.3): find test files matching the configured folder/glob
// rows, and parse each into a provisional `TestNode` tree WITHOUT executing it.
// IDs derived here must match what the Lua facade emits at runtime (§4.4); the run
// is authoritative and may add nodes the static parse can't see (§4.1).

enum TestDiscovery {

    // MARK: File matching

    /// Files under each row's folder matching that row's glob (§3.7 semantics).
    static func matchingFiles(projectRoot: URL, rows: [TestFolderGlob]) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()
        let fm = FileManager.default

        for row in rows {
            let base = projectRoot.appendingPathComponent(row.folder, isDirectory: true)
            guard let en = fm.enumerator(at: base,
                                         includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsHiddenFiles]) else { continue }
            let regex = Glob.regex(for: row.glob)
            for case let url as URL in en {
                let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                guard isFile else { continue }
                // match the path relative to the row's folder
                let rel = relativePath(of: url, under: base)
                if regex.firstMatch(in: rel, range: NSRange(rel.startIndex..., in: rel)) != nil {
                    if seen.insert(url.path).inserted { results.append(url) }
                }
            }
        }
        return results.sorted { $0.path < $1.path }   // deterministic order
    }

    private static func relativePath(of url: URL, under base: URL) -> String {
        let b = base.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        if p.hasPrefix(b) {
            return String(p.dropFirst(b.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }

    // MARK: Parse

    /// Parse a test file into a `TestNode` tree of suites/tests. The id form is
    /// `<filename> > describe > ... > it`, matching the facade (§4.4).
    static func parse(file: URL, projectRoot: URL) -> TestNode? {
        guard let src = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let fileLabel = file.lastPathComponent
        let root = TestNode(id: fileLabel, name: fileLabel, kind: .suite,
                            file: file.path, line: 1)

        // A lightweight line-based parser: track describe nesting by brace-less
        // heuristics is unreliable, so we match `describe("name"` / `it("name"` and
        // approximate nesting via a stack closed on matching `end)`. This is a
        // best-effort *provisional* tree; the run is authoritative (§4.1).
        var stack: [TestNode] = [root]
        let lines = src.components(separatedBy: .newlines)

        for (i, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lineNo = i + 1

            if let name = capture(line, keyword: "describe") {
                let parent = stack.last!
                let id = parent === root ? "\(fileLabel) > \(name)" : "\(parent.id) > \(name)"
                let node = TestNode(id: id, name: name, kind: .suite,
                                    file: file.path, line: lineNo)
                parent.children.append(node)
                stack.append(node)
            } else if let name = capture(line, keyword: "it") {
                let parent = stack.last!
                let id = parent === root ? "\(fileLabel) > \(name)" : "\(parent.id) > \(name)"
                let node = TestNode(id: id, name: name, kind: .test,
                                    file: file.path, line: lineNo)
                parent.children.append(node)
            } else if line.hasPrefix("end)") || line == "end" {
                // close the nearest open describe (never pop root)
                if stack.count > 1 { stack.removeLast() }
            }
        }
        return root.children.isEmpty ? root : root
    }

    /// Extract the quoted name from `keyword("name"` / `keyword('name'`.
    private static func capture(_ line: String, keyword: String) -> String? {
        // must start with the keyword followed by ( and a quote
        guard line.hasPrefix(keyword) else { return nil }
        let pattern = "^\(keyword)\\s*\\(\\s*[\"']([^\"']*)[\"']"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: line)
        else { return nil }
        return String(line[r])
    }
}

// MARK: - Glob

/// Minimal glob → NSRegularExpression. Supports `**` (any depth, incl. `/`),
/// `*` (any run except `/`), and `?` (single non-`/`). Everything else literal.
enum Glob {
    static func regex(for glob: String) -> NSRegularExpression {
        var out = "^"
        let chars = Array(glob)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    out += ".*"        // ** → any depth
                    i += 1
                    // swallow an immediately following slash so "**/x" matches "x" too
                    if i + 1 < chars.count && chars[i + 1] == "/" { i += 1 }
                } else {
                    out += "[^/]*"     // * → within a segment
                }
            case "?":
                out += "[^/]"
            case ".", "(", ")", "+", "|", "^", "$", "{", "}", "[", "]", "\\":
                out += "\\\(c)"
            default:
                out.append(c)
            }
            i += 1
        }
        out += "$"
        // fall back to never-match on a bad pattern rather than crashing
        return (try? NSRegularExpression(pattern: out)) ??
               (try! NSRegularExpression(pattern: "$^"))
    }
}
