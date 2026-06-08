import Foundation

enum LanguageServerResolver {
    private static let bundledFolderName = "LuaLS"

    // The bundled lua-language-server executable for the host arch, or nil if
    // mode is .none, the arch is unsupported, or the binary is missing.
    static func resolve(mode: LanguageServerMode) -> URL? {
        guard mode == .luaCATS else { return nil }

        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x64"
        #else
        return nil
        #endif

        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent(bundledFolderName)
            .appendingPathComponent(arch)
            .appendingPathComponent("bin")
            .appendingPathComponent("lua-language-server") else { return nil }

        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}
