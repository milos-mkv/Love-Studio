import Foundation

// MARK: - Font entry

enum FontSource: String, Codable, CaseIterable, Identifiable {
    case `default` = "default"   // love.graphics.newFont(size)
    case file      = "file"      // love.graphics.newFont("path", size)
    case imageFont = "imageFont" // love.graphics.newImageFont("path", glyphs)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:   return "Default (built-in)"
        case .file:      return "TTF / OTF file"
        case .imageFont: return "Image font"
        }
    }

    var icon: String {
        switch self {
        case .default:   return "textformat"
        case .file:      return "doc.text"
        case .imageFont: return "photo.on.rectangle"
        }
    }
}

struct FontEntry: Codable, Identifiable, Equatable {
    var id:        UUID       = UUID()
    /// Lua identifier used as the key in the fonts table
    var name:      String     = "body"
    var source:    FontSource = .default
    /// Path relative to LÖVE project root (e.g. "fonts/Roboto.ttf")
    var filePath:  String     = ""
    /// Glyph string for image fonts
    var glyphs:    String     = " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,!?"
    var size:      Int        = 14
    /// Fallback size if file not found at runtime
    var fallback:  Int        = 12
    /// Preview text shown in the UI
    var previewText: String   = "The quick brown fox jumps over the lazy dog"
    // Outline / stroke
    var outlineEnabled: Bool  = false
    /// Outline thickness in pixels
    var outlineSize:    Int   = 2
    /// Outline color as RGBA 0–255
    var outlineR: Int = 0
    var outlineG: Int = 0
    var outlineB: Int = 0
    var outlineA: Int = 255
}

// MARK: - Font manager config

struct FontManagerConfig: Codable, Equatable, Identifiable {
    var id:         UUID    = UUID()
    var moduleName: String  = "Fonts"
    var entries:    [FontEntry] = []
}
