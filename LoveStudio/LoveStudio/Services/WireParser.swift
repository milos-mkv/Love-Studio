import Foundation

// MARK: - WireParser
//
// Parses the structured wire lines the Lua facade emits (§3.5). Each line is a
// sentinel prefix followed by a JSON object. Fields are JSON-escaped, so JSON
// decoding recovers text containing `}`, newlines, or the sentinel itself.

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
            status: TestStatus(rawValue: mapStatus(statusRaw)) ?? .error,
            file: obj["file"] as? String ?? "",
            line: intValue(obj["line"]),
            ms: intValue(obj["ms"]),
            msg: obj["msg"] as? String ?? ""
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

    // The facade emits lowercase status strings matching TestStatus raw values,
    // except none need remapping currently. Kept as a seam for safety.
    private static func mapStatus(_ s: String) -> String { s }
}
