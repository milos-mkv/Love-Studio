import Foundation

struct ResolutionStore {

    static let folder = ".love-studio/resolution"

    @discardableResult
    static func save(_ config: ResolutionConfig, to projectRoot: URL) throws -> URL {
        let dir  = projectRoot.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(safeName(config.moduleName)).json")
        try JSONEncoder().encode(config).write(to: file)
        return file
    }

    static func loadAll(from projectRoot: URL) -> [ResolutionConfig] {
        let dir = projectRoot.appendingPathComponent(folder)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let cfg  = try? JSONDecoder().decode(ResolutionConfig.self, from: data)
                else { return nil }
                return cfg
            }
    }

    static func delete(_ config: ResolutionConfig, from projectRoot: URL) {
        let file = projectRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("\(safeName(config.moduleName)).json")
        try? FileManager.default.removeItem(at: file)
    }

    @discardableResult
    static func exportLua(_ code: String, moduleName: String, to projectRoot: URL) throws -> URL {
        let file = projectRoot.appendingPathComponent("\(safeName(moduleName).lowercased()).lua")
        try code.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    static func safeName(_ name: String) -> String {
        let s    = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = s.components(separatedBy: CharacterSet.alphanumerics
            .union(.init(charactersIn: "_-")).inverted).joined(separator: "_")
        return safe.isEmpty ? "Resolution" : safe
    }
}
