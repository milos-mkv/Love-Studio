import Foundation

final class TemplateService {

    static let shared = TemplateService()
    private init() {}

    /// Creates a new project folder at `url` with all files for the given template.
    func createProject(name: String, template: ProjectTemplate, at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        // conf.lua
        let conf = makeConfLua(name: name, template: template)
        try conf.write(to: url.appendingPathComponent("conf.lua"), atomically: true, encoding: .utf8)

        // Template-specific files
        for file in template.files {
            let fileURL = url.appendingPathComponent(file.name)
            let dir = fileURL.deletingLastPathComponent()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: conf.lua generator

    private func makeConfLua(name: String, template: ProjectTemplate) -> String {
        let size = template.windowSize
        return """
function love.conf(t)
    t.title = "\(name)"
    t.version = "11.5"
    t.window.width = \(size.width)
    t.window.height = \(size.height)
    t.window.resizable = false
    t.window.vsync = 1
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    t.console = false
end
"""
    }
}
