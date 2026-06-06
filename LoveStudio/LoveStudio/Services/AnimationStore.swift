import Foundation

struct AnimationStore {

    static let folder = ".love-studio/animations"

    @discardableResult
    static func save(_ config: SpriteAnimationConfig, to projectRoot: URL) throws -> URL {
        let dir = projectRoot.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(safeName(config.moduleName)).json")
        let data = try JSONEncoder().encode(config)
        try data.write(to: file)
        return file
    }

    static func loadAll(from projectRoot: URL) -> [SpriteAnimationConfig] {
        let dir = projectRoot.appendingPathComponent(folder)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let config = try? JSONDecoder().decode(SpriteAnimationConfig.self, from: data) else {
                    return nil
                }
                return config
            }
    }

    static func delete(_ config: SpriteAnimationConfig, from projectRoot: URL) {
        let file = projectRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("\(safeName(config.moduleName)).json")
        try? FileManager.default.removeItem(at: file)
    }

    @discardableResult
    static func exportLua(_ code: String, moduleName: String, to projectRoot: URL) throws -> URL {
        let animationsDir = projectRoot.appendingPathComponent("animations")
        try FileManager.default.createDirectory(at: animationsDir, withIntermediateDirectories: true)
        let file = animationsDir.appendingPathComponent("\(safeName(moduleName)).lua")
        try code.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func safeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "_-")).inverted)
            .joined(separator: "_")
        return safe.isEmpty ? "Animation" : safe
    }
}
