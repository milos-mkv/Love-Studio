import Foundation

final class TemplateService {

    static let shared = TemplateService()
    private init() {}

    private static let lspDir = ".love-studio"
    private static let luaCATSSubdir = ".love-studio/luacats"

    func createProject(name: String, template: ProjectTemplate, at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        let conf = makeConfLua(name: name, template: template)
        try conf.write(to: url.appendingPathComponent("conf.lua"), atomically: true, encoding: .utf8)

        for file in template.files {
            let fileURL = url.appendingPathComponent(file.name)
            let dir = fileURL.deletingLastPathComponent()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        if LanguageServerMode.current == .luaCATS {
            try writeLSPFiles(at: url)
        }
    }

    func writeLSPFiles(at url: URL) throws {
        let fm = FileManager.default
        let defsDir = url.appendingPathComponent(Self.luaCATSSubdir)
        let loveModsDir = defsDir.appendingPathComponent("love")
        try fm.createDirectory(at: loveModsDir, withIntermediateDirectories: true)

        guard let bundleDefsURL = Bundle.main.url(forResource: "LuaCATS", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }

        for name in try fm.contentsOfDirectory(atPath: bundleDefsURL.appendingPathComponent("love").path) {
            let src = bundleDefsURL.appendingPathComponent("love/\(name)")
            let dst = loveModsDir.appendingPathComponent(name)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
        }
        let srcTop = bundleDefsURL.appendingPathComponent("love.lua")
        let dstTop = defsDir.appendingPathComponent("love.lua")
        if fm.fileExists(atPath: dstTop.path) { try fm.removeItem(at: dstTop) }
        try fm.copyItem(at: srcTop, to: dstTop)

        // Definitions for the test-runner globals so the language server resolves
        // them with autocomplete and signatures.
        try testKitDefs.write(to: defsDir.appendingPathComponent("testkit.lua"),
                              atomically: true, encoding: .utf8)

        try makeLuarc().write(to: url.appendingPathComponent(".luarc.json"), atomically: true, encoding: .utf8)
    }

    func removeLSPFiles(at url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url.appendingPathComponent(".luarc.json"))
        try? fm.removeItem(at: url.appendingPathComponent(Self.lspDir))
    }

    // Rewrite only .luarc.json (e.g. after diagnostic-severity settings change).
    // No-op if the project has no LSP files (annotations off / never written).
    func rewriteLuarc(at url: URL) {
        let luarc = url.appendingPathComponent(".luarc.json")
        guard FileManager.default.fileExists(atPath: luarc.path) else { return }
        try? makeLuarc().write(to: luarc, atomically: true, encoding: .utf8)
        // Keep the test-runner defs in sync alongside the rewritten config.
        let defs = url.appendingPathComponent(Self.luaCATSSubdir).appendingPathComponent("testkit.lua")
        if FileManager.default.fileExists(atPath: defs.deletingLastPathComponent().path) {
            try? testKitDefs.write(to: defs, atomically: true, encoding: .utf8)
        }
    }

    // LuaCATS definitions for the test-runner globals (describe/it/hooks/assert) so
    // the language server resolves them with types and signatures.
    private var testKitDefs: String {
        """
        ---@meta
        -- [LÖVE Studio] Test runner globals (auto-generated). These are injected into
        -- test files at run time by the test facade; this file lets the language
        -- server recognize them with autocomplete + signatures.

        ---Define a test suite (group of tests). May be nested.
        ---@param name string
        ---@param fn fun()
        function describe(name, fn) end

        ---Define a single test case.
        ---@param name string
        ---@param fn fun()
        function it(name, fn) end

        ---Run once before EACH test in the enclosing suite.
        ---@param fn fun()
        function before_each(fn) end

        ---Run once after EACH test in the enclosing suite.
        ---@param fn fun()
        function after_each(fn) end

        ---Run once before ALL tests in the file/suite (setup).
        ---@param fn fun()
        function setup(fn) end

        ---Run once after ALL tests in the file/suite (teardown).
        ---@param fn fun()
        function teardown(fn) end

        ---Assertion library (luassert). Callable, and exposes are/is_*/has/etc.
        ---@class ls.assert
        ---@field are table
        ---@field is_true fun(v: any, msg?: string)
        ---@field is_false fun(v: any, msg?: string)
        ---@field is_nil fun(v: any, msg?: string)
        ---@field is_not_nil fun(v: any, msg?: string)
        ---@field equal fun(a: any, b: any, msg?: string)
        ---@field same fun(a: any, b: any, msg?: string)
        ---@field has_error fun(fn: fun(), msg?: string)
        ---@field spy table
        ---@field stub table
        ---@overload fun(v: any, msg?: string)
        assert = assert
        """
    }

    private func makeLuarc() -> String {
        let overrides = DiagnosticSeverityStore.load()
        // Split into severity remaps (Error/Warning/Hint) and disables (None).
        var severity: [String: String] = [:]
        var disabled: [String] = []
        for (code, level) in overrides.sorted(by: { $0.key < $1.key }) {
            if level == .none { disabled.append(code) } else { severity[code] = level.rawValue }
        }

        var config: [String] = [
            "  \"Lua.workspace.library\": [\".love-studio/luacats\"]",
            "  \"Lua.runtime.version\": \"LuaJIT\"",
            "  \"Lua.runtime.special\": { \"love.filesystem.load\": \"loadfile\" }",
            "  \"Lua.diagnostics.globals\": [\"love\", \"describe\", \"it\", \"before_each\", \"after_each\", \"setup\", \"teardown\"]",
        ]
        if !severity.isEmpty {
            let pairs = severity.sorted { $0.key < $1.key }
                .map { "\"\($0.key)\": \"\($0.value)\"" }
                .joined(separator: ", ")
            config.append("  \"Lua.diagnostics.severity\": { \(pairs) }")
        }
        if !disabled.isEmpty {
            let list = disabled.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
            config.append("  \"Lua.diagnostics.disable\": [\(list)]")
        }
        return "{\n" + config.joined(separator: ",\n") + "\n}\n"
    }

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
