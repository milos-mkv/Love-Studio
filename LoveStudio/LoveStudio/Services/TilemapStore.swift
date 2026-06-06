import Foundation

struct TilemapStore {

    static let mapsFolder = ".love-studio/maps"

    static func save(_ config: TilemapConfig, to projectRoot: URL) throws -> URL {
        let dir = projectRoot.appendingPathComponent(mapsFolder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = config.name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let file = dir.appendingPathComponent("\(safe).json")
        let data = try JSONEncoder().encode(config)
        try data.write(to: file)
        return file
    }

    static func loadAll(from projectRoot: URL) -> [TilemapConfig] {
        let dir = projectRoot.appendingPathComponent(mapsFolder)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let config = try? JSONDecoder().decode(TilemapConfig.self, from: data)
                else { return nil }
                return config
            }
    }

    static func delete(_ config: TilemapConfig, from projectRoot: URL) {
        let safe = config.name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let file = projectRoot
            .appendingPathComponent(mapsFolder)
            .appendingPathComponent("\(safe).json")
        try? FileManager.default.removeItem(at: file)
    }

    static func exportLua(_ code: String, name: String, to projectRoot: URL) throws -> URL {
        let tilesDir = projectRoot.appendingPathComponent("tiles")
        try FileManager.default.createDirectory(at: tilesDir, withIntermediateDirectories: true)
        let safe = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let file = tilesDir.appendingPathComponent("\(safe).lua")
        try code.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
