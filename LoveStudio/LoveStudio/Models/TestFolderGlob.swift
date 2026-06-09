import Foundation

// MARK: - TestFolderGlob
//
// One `folder | glob` row from settings (§3.7): a folder (relative to the project
// root) paired with one glob applied beneath it. The runner uses whatever glob the
// user supplies — no built-in naming convention. The full list is JSON-encoded into
// a single @AppStorage string.

struct TestFolderGlob: Codable, Identifiable, Equatable {
    var id = UUID()
    var folder: String   // e.g. "tests"  (relative to project root)
    var glob: String     // e.g. "**/*.test.lua"

    init(id: UUID = UUID(), folder: String = "tests", glob: String = "**/*.test.lua") {
        self.id = id
        self.folder = folder
        self.glob = glob
    }
}

extension Array where Element == TestFolderGlob {
    /// Decode the JSON-encoded @AppStorage string into rows (empty on failure).
    static func decode(from json: String) -> [TestFolderGlob] {
        guard let data = json.data(using: .utf8),
              let rows = try? JSONDecoder().decode([TestFolderGlob].self, from: data)
        else { return [] }
        return rows
    }

    /// Encode rows to a JSON string for @AppStorage.
    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    /// The default row set.
    static var defaultRows: [TestFolderGlob] {
        [TestFolderGlob()]
    }
}
