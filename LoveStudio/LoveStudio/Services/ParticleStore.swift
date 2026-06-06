import Foundation

struct ParticleStore {

    static let folder = ".love-studio/particles"

    // MARK: - Save

    @discardableResult
    static func save(_ config: ParticleSystemConfig, to projectRoot: URL) throws -> URL {
        let dir = projectRoot.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = safeName(config.name)
        let file = dir.appendingPathComponent("\(safe).json")
        let data = try JSONEncoder().encode(config)
        try data.write(to: file)
        return file
    }

    // MARK: - Load all

    static func loadAll(from projectRoot: URL) -> [ParticleSystemConfig] {
        let dir = projectRoot.appendingPathComponent(folder)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let config = try? JSONDecoder().decode(ParticleSystemConfig.self, from: data)
                else { return nil }
                return config
            }
    }

    // MARK: - Delete

    static func delete(_ config: ParticleSystemConfig, from projectRoot: URL) {
        let file = projectRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("\(safeName(config.name)).json")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Export as Lua

    @discardableResult
    static func exportLua(_ code: String, name: String, to projectRoot: URL) throws -> URL {
        let particlesDir = projectRoot.appendingPathComponent("particles")
        try FileManager.default.createDirectory(at: particlesDir, withIntermediateDirectories: true)
        let file = particlesDir.appendingPathComponent("\(safeName(name)).lua")
        try code.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    // MARK: - Helpers

    private static func safeName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
    }
}
