import Foundation

struct SceneManagerStore {

    // Single fixed config file - always scene.json
    private static let configFile = ".love-studio/scene.json"

    @discardableResult
    static func save(_ config: SceneManagerConfig, to projectRoot: URL) throws -> URL {
        let file = projectRoot.appendingPathComponent(configFile)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(config).write(to: file)
        return file
    }

    static func load(from projectRoot: URL) -> SceneManagerConfig {
        let file = projectRoot.appendingPathComponent(configFile)
        guard let data = try? Data(contentsOf: file),
              let cfg  = try? JSONDecoder().decode(SceneManagerConfig.self, from: data)
        else { return SceneManagerConfig() }
        // Always enforce fixed module name
        var fixed = cfg
        fixed.moduleName = "Scene"
        return fixed
    }

    /// Export Scene.lua + all scene template files
    @discardableResult
    static func exportAll(_ config: SceneManagerConfig, to projectRoot: URL) throws -> [URL] {
        var exported: [URL] = []

        // Export main module
        let moduleCode = SceneCodeGenerator.generateModule(config: config)
        let modName    = safeName(config.moduleName)
        let moduleFile = projectRoot.appendingPathComponent("\(modName).lua")
        try moduleCode.write(to: moduleFile, atomically: true, encoding: .utf8)
        exported.append(moduleFile)

        // Export per-scene templates, and merge in any newly enabled callback stubs
        // for scenes that already exist without overwriting the user's code.
        let scenesDir = projectRoot.appendingPathComponent("scenes")
        try FileManager.default.createDirectory(at: scenesDir, withIntermediateDirectories: true)

        for entry in config.entries {
            let fileName: URL
            if !entry.filePath.isEmpty {
                fileName = projectRoot.appendingPathComponent(
                    entry.filePath.hasSuffix(".lua") ? entry.filePath : entry.filePath + ".lua"
                )
            } else {
                fileName = scenesDir.appendingPathComponent("\(SceneCodeGenerator.luaIdent(entry.name)).lua")
            }

            if !FileManager.default.fileExists(atPath: fileName.path) {
                let template = SceneCodeGenerator.generateSceneTemplate(entry: entry, allEntries: config.entries)
                try template.write(to: fileName, atomically: true, encoding: .utf8)
                exported.append(fileName)
            } else if let existing = try? String(contentsOf: fileName, encoding: .utf8) {
                let merged = SceneCodeGenerator.mergeSceneTemplate(
                    existing: existing,
                    entry: entry,
                    allEntries: config.entries
                )
                if merged != existing {
                    try merged.write(to: fileName, atomically: true, encoding: .utf8)
                    exported.append(fileName)
                }
            }
        }

        return exported
    }

    static func safeName(_ name: String) -> String {
        let s    = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = s.components(separatedBy: CharacterSet.alphanumerics
            .union(.init(charactersIn: "_-")).inverted).joined(separator: "_")
        return safe.isEmpty ? "Scene" : safe
    }
}
