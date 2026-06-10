import Foundation

// Finds the test files that match the configured folder/glob rows. The test tree
// itself is built at runtime by the Lua collect pass (see TestRunner.discover),
// not parsed here.
enum TestDiscovery {

    // Files under each row's folder whose relative path matches the row's glob.
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
                let rel = relativePath(of: url, under: base)
                if regex.firstMatch(in: rel, range: NSRange(rel.startIndex..., in: rel)) != nil,
                   seen.insert(url.path).inserted {
                    results.append(url)
                }
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    private static func relativePath(of url: URL, under base: URL) -> String {
        let b = base.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        if p.hasPrefix(b) {
            return String(p.dropFirst(b.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }
}

// Minimal glob → NSRegularExpression: ** matches any depth (including /),
// * matches within a path segment, ? matches a single non-/ character.
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
                    out += ".*"
                    i += 1
                    if i + 1 < chars.count && chars[i + 1] == "/" { i += 1 }
                } else {
                    out += "[^/]*"
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
        return (try? NSRegularExpression(pattern: out))
            ?? (try! NSRegularExpression(pattern: "$^"))
    }
}
