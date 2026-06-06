import Foundation

struct AudioStore {

    static let folder = ".love-studio/audio"

    // MARK: - Save

    @discardableResult
    static func save(_ config: AudioManagerConfig, to projectRoot: URL) throws -> URL {
        let dir = projectRoot.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = safeName(config.managerName)
        let file = dir.appendingPathComponent("\(name).json")
        let data = try JSONEncoder().encode(config)
        try data.write(to: file)
        return file
    }

    // MARK: - Load all

    static func loadAll(from projectRoot: URL) -> [AudioManagerConfig] {
        let dir = projectRoot.appendingPathComponent(folder)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let config = try? JSONDecoder().decode(AudioManagerConfig.self, from: data)
                else { return nil }
                return config
            }
    }

    // MARK: - Delete

    static func delete(_ config: AudioManagerConfig, from projectRoot: URL) {
        let file = projectRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("\(safeName(config.managerName)).json")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Export as Lua

    @discardableResult
    static func exportLua(_ code: String, managerName: String, to projectRoot: URL) throws -> URL {
        let file = projectRoot.appendingPathComponent("Audio.lua")
        try code.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    // MARK: - Helpers

    private static func safeName(_ name: String) -> String {
        let s = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = s
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "_-")).inverted)
            .joined(separator: "_")
        return safe.isEmpty ? "Audio" : safe
    }
}
