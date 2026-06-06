import Foundation

struct SpritesheetStore {

    static let folder = ".love-studio/spritesheet"

    // MARK: - Save

    @discardableResult
    static func save(_ config: SpritesheetConfig, to projectRoot: URL) throws -> URL {
        let dir = projectRoot.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(safeName(config.projectName)).json")
        let data = try JSONEncoder().encode(config)
        try data.write(to: file)
        print("[SpritesheetStore] Saved to: \(file.path)")
        return file
    }

    // MARK: - Load all

    static func loadAll(from projectRoot: URL) -> [SpritesheetConfig] {
        let dir = projectRoot.appendingPathComponent(folder)
        print("[SpritesheetStore] Loading from: \(dir.path)")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else {
            print("[SpritesheetStore] Directory not found or empty")
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> SpritesheetConfig? in
                guard let data = try? Data(contentsOf: url) else {
                    print("[SpritesheetStore] Failed to read: \(url.lastPathComponent)")
                    return nil
                }
                do {
                    return try JSONDecoder().decode(SpritesheetConfig.self, from: data)
                } catch {
                    print("[SpritesheetStore] Decode error for \(url.lastPathComponent): \(error)")
                    return nil
                }
            }
    }

    // MARK: - Delete

    static func delete(_ config: SpritesheetConfig, from projectRoot: URL) {
        let file = projectRoot
            .appendingPathComponent(folder)
            .appendingPathComponent("\(safeName(config.projectName)).json")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - Export Lua + atlas PNG

    @discardableResult
    static func exportJSON(_ json: String, projectName: String, to projectRoot: URL) throws -> URL {
        let file = projectRoot.appendingPathComponent("\(safeName(projectName).lowercased()).json")
        try json.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @discardableResult
    static func exportLua(_ code: String, projectName: String, to projectRoot: URL) throws -> URL {
        let file = projectRoot.appendingPathComponent("\(safeName(projectName).lowercased()).lua")
        try code.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @discardableResult
    static func exportAtlas(_ data: Data, atlasPath: String, to projectRoot: URL) throws -> URL {
        let file = projectRoot.appendingPathComponent(atlasPath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file)
        return file
    }

    // MARK: - Helpers

    static func safeName(_ name: String) -> String {
        let s    = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = s
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "_-")).inverted)
            .joined(separator: "_")
        return safe.isEmpty ? "Sprites" : safe
    }
}
