import Foundation

// A `folder | glob` row from settings: a folder relative to the project root paired
// with a glob applied beneath it. The full list is JSON-encoded into one @AppStorage
// string.
struct TestFolderGlob: Codable, Identifiable, Equatable {
    var id = UUID()
    var folder: String   // relative to the project root, e.g. "tests"
    var glob: String     // e.g. "**/*.test.lua"

    init(id: UUID = UUID(), folder: String = "tests", glob: String = "**/*.test.lua") {
        self.id = id
        self.folder = folder
        self.glob = glob
    }
}

extension Array where Element == TestFolderGlob {
    static func decode(from json: String) -> [TestFolderGlob] {
        guard let data = json.data(using: .utf8),
              let rows = try? JSONDecoder().decode([TestFolderGlob].self, from: data)
        else { return [] }
        return rows
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    static var defaultRows: [TestFolderGlob] {
        [TestFolderGlob()]
    }
}

// A glob (folder or file) to exclude from coverage, e.g. "vendor/**" or "main.lua".
// Stored as a JSON list in @AppStorage.
struct CoverageExcludeRow: Codable, Identifiable, Equatable {
    var id = UUID()
    var glob: String

    init(id: UUID = UUID(), glob: String = "") {
        self.id = id
        self.glob = glob
    }
}

extension Array where Element == CoverageExcludeRow {
    static func decode(from json: String) -> [CoverageExcludeRow] {
        guard let data = json.data(using: .utf8),
              let rows = try? JSONDecoder().decode([CoverageExcludeRow].self, from: data)
        else { return [] }
        return rows
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    static var defaultRows: [CoverageExcludeRow] {
        [CoverageExcludeRow(glob: "main.lua"), CoverageExcludeRow(glob: "conf.lua")]
    }
}

// LuaCov's `exclude` entries are Lua patterns, not shell globs. Convert a user glob
// (e.g. "vendor/**") into the equivalent Lua pattern.
enum GlobToLuaPattern {
    static func convert(_ glob: String) -> String {
        var out = ""
        let chars = Array(glob)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    out += ".*"           // ** → any chars incl. separators
                    i += 1
                    if i + 1 < chars.count && chars[i + 1] == "/" { i += 1 }
                } else {
                    out += "[^/]*"        // * → within a path segment
                }
            case "?":
                out += "[^/]"
            // Lua-pattern magic chars must be %-escaped
            case ".", "%", "+", "-", "(", ")", "[", "]", "^", "$":
                out += "%" + String(c)
            default:
                out += String(c)
            }
            i += 1
        }
        return out
    }
}
