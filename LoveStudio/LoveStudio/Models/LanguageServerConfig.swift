import Foundation

// MARK: - LanguageServerMode

enum LanguageServerMode: String, Codable, CaseIterable, Identifiable {
    case none    = "none"
    case luaCATS = "luaCATS"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:    return "Disabled"
        case .luaCATS: return "LuaCATS (lua-language-server)"
        }
    }

    /// Reads the persisted preference without importing SwiftUI.
    /// Services and generators must use this instead of @AppStorage.
    static var current: LanguageServerMode {
        guard UserDefaults.standard.bool(forKey: "editorAnnotationsEnabled") else {
            return .none
        }
        return .luaCATS
    }
}
