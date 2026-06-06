import Foundation

// MARK: - Sprite entry

struct SpriteEntry: Codable, Identifiable, Equatable {
    var id:       UUID   = UUID()
    /// Lua-safe identifier (used as key in quads table)
    var name:     String = "sprite"
    /// Path relative to the LÖVE project root (e.g. "images/player.png")
    var filePath: String = ""
}

// MARK: - Spritesheet config

struct SpritesheetConfig: Codable, Equatable, Identifiable {
    var id:          UUID   = UUID()
    /// Lua module / table name
    var projectName: String = "Sprites"
    var sprites:     [SpriteEntry] = []
    /// Pixels of padding between each sprite in the atlas
    var padding:     Int    = 2
    /// Round atlas dimensions up to the next power of two
    var powerOfTwo:  Bool   = true
    /// Maximum atlas side length in pixels
    var maxSize:     Int    = 4096
    /// Output path for the atlas PNG, relative to project root
    var atlasPath:   String = "sprites/atlas.png"
    /// Automatically crop transparent edges from each sprite before packing
    var trimTransparent: Bool = false
}
