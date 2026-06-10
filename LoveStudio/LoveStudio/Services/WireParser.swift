import Foundation

// Parses the wire lines the Lua facade emits: a sentinel prefix followed by a JSON
// object. Fields are JSON-escaped, so decoding recovers text containing `}`,
// newlines, or the sentinel itself.
enum WireParser {

    struct TestRecord {
        let id: String
        let name: String
        let status: TestStatus
        let file: String
        let line: Int
        let ms: Int
        let msg: String
    }

    struct OutRecord {
        let id: String
        let text: String
    }

    // MARK: Public

    static func parseTest(_ line: String) -> TestRecord? {
        guard let obj = json(after: "[[LS_TEST]]", in: line) else { return nil }
        guard let id = obj["id"] as? String,
              let statusRaw = obj["status"] as? String else { return nil }
        return TestRecord(
            id: id,
            name: obj["name"] as? String ?? id,
            status: TestStatus(rawValue: statusRaw) ?? .error,
            file: obj["file"] as? String ?? "",
            line: intValue(obj["line"]),
            ms: intValue(obj["ms"]),
            msg: obj["msg"] as? String ?? ""
        )
    }

    struct TreeRecord {
        let id: String
        let name: String
        let file: String
        let line: Int
    }

    // A [[LS_TREE]] line from the discovery pass: one per test, carrying the
    // runtime id/name/file/line.
    static func parseTree(_ line: String) -> TreeRecord? {
        guard let obj = json(after: "[[LS_TREE]]", in: line),
              let id = obj["id"] as? String else { return nil }
        return TreeRecord(
            id: id,
            name: obj["name"] as? String ?? id,
            file: obj["file"] as? String ?? "",
            line: intValue(obj["line"])
        )
    }

    static func parseOut(_ line: String) -> OutRecord? {
        guard let obj = json(after: "[[LS_OUT]]", in: line) else { return nil }
        guard let id = obj["id"] as? String else { return nil }
        return OutRecord(id: id, text: obj["text"] as? String ?? "")
    }

    static func parseCoverage(_ line: String) -> Double? {
        guard let obj = json(after: "[[LS_COV]]", in: line) else { return nil }
        if let n = obj["pct"] as? Double { return n }
        if let n = obj["pct"] as? Int { return Double(n) }
        if let s = obj["pct"] as? String { return Double(s) }
        return nil
    }

    struct CoverageLines {
        let file: String
        let hit: Set<Int>
        let miss: Set<Int>
    }

    static func parseCoverageLines(_ line: String) -> CoverageLines? {
        guard let obj = json(after: "[[LS_COVLINES]]", in: line),
              let file = obj["file"] as? String else { return nil }
        func ints(_ v: Any?) -> Set<Int> {
            guard let arr = v as? [Any] else { return [] }
            return Set(arr.compactMap { intOpt($0) })
        }
        return CoverageLines(file: file, hit: ints(obj["hit"]), miss: ints(obj["miss"]))
    }

    private static func intOpt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        return nil
    }

    // MARK: Private

    private static func json(after prefix: String, in line: String) -> [String: Any]? {
        guard line.hasPrefix(prefix) else { return nil }
        let jsonPart = String(line.dropFirst(prefix.count))
        guard let data = jsonPart.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func intValue(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String, let i = Int(s) { return i }
        return 0
    }
}
