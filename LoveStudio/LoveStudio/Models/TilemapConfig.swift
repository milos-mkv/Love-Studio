import Foundation

// MARK: - Origin

enum TilemapOrigin: String, Codable, CaseIterable, Identifiable {
    case topLeft  = "topLeft"
    case center   = "center"
    case bottomLeft = "bottomLeft"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft:   return "Top-Left"
        case .center:    return "Center"
        case .bottomLeft: return "Bottom-Left"
        }
    }

    var icon: String {
        switch self {
        case .topLeft:   return "arrow.down.right"
        case .center:    return "scope"
        case .bottomLeft: return "arrow.up.right"
        }
    }
}

// MARK: - Tile Animation

struct TileAnimFrame: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var gid: Int
    var duration: Double  // seconds
}

struct TileAnimation: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var sourceGID: Int             // GID placed on map that triggers this animation
    var frames: [TileAnimFrame]    // sequence to cycle through
    var flipH: Bool = false        // mirror horizontally
    var flipV: Bool = false        // mirror vertically

    var totalDuration: Double { frames.reduce(0) { $0 + $1.duration } }
}

// MARK: - Tileset Info

struct TilesetInfo: Codable, Equatable, Identifiable {
    var id: UUID     = UUID()
    var name: String          // display name (e.g. "Grass")
    var fileName: String      // filename relative to project root (e.g. "tiles/grass.png")

    // Tile global ID encoding: tilesetIndex * GID_STRIDE + localTileIndex
    static let GID_STRIDE = 65536
}

// MARK: - GID Flip Bits

extension TilemapConfig {
    static let FLIP_H:    Int = 1 << 28   // 268435456
    static let FLIP_V:    Int = 1 << 29   // 536870912
    static let FLIP_BITS: Int = 3 << 28   // mask for both flip bits

    /// Strip flip bits from a raw GID to get the real tileset GID.
    static func rawGID(_ gid: Int) -> Int { gid & ~FLIP_BITS }
    static func flipH(_ gid: Int) -> Bool { gid & FLIP_H != 0 }
    static func flipV(_ gid: Int) -> Bool { gid & FLIP_V != 0 }
}

// MARK: - Tile Properties

enum TilePropertyType: String, Codable, CaseIterable {
    case string = "string"
    case int    = "int"
    case float  = "float"
    case bool   = "bool"
    var label: String { rawValue }
}

struct TileProperty: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var key: String   = "key"
    var value: String = ""
    var type: TilePropertyType = .string
}

// MARK: - Map Object

struct MapObject: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = "Object"
    var type: String = "spawn"
    var tileX: Int = 0
    var tileY: Int = 0
    var tileW: Int = 1
    var tileH: Int = 1
    var properties: [TileProperty] = []
}

enum LayerType: String, Codable {
    case tile   = "tile"
    case object = "object"
}

// MARK: - Tile Layer

struct TileLayer: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var visible: Bool = true
    var opacity: Double = 1.0
    var isCollision: Bool  = false
    var isForeground: Bool = false
    var isLocked: Bool = false
    var layerType: LayerType = .tile
    var objects: [MapObject] = []
    var tiles: [Int]  // flat array (y * mapWidth + x), -1 = empty; value = tileset GID

    init(name: String, count: Int) {
        self.name  = name
        self.tiles = Array(repeating: -1, count: count)
    }
}

// MARK: - Tilemap Config

struct TilemapConfig: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String  = "New Tilemap"
    var mapWidth: Int  = 20
    var mapHeight: Int = 15
    var tileSize: Int  = 16
    var tilesets: [TilesetInfo] = []
    var layers: [TileLayer]
    var origin: TilemapOrigin = .topLeft
    var animations: [TileAnimation] = []
    var tileProperties: [String: [TileProperty]] = [:]   // key = "\(gid)"

    var tilesetName: String? {
        get { tilesets.first?.fileName }
    }

    init() {
        layers = [TileLayer(name: "Background", count: 20 * 15),
                  TileLayer(name: "Objects",    count: 20 * 15)]
    }

    mutating func resize(width: Int, height: Int) {
        let newCount = width * height
        for i in layers.indices {
            var newTiles = Array(repeating: -1, count: newCount)
            for y in 0 ..< min(height, mapHeight) {
                for x in 0 ..< min(width, mapWidth) {
                    newTiles[y * width + x] = layers[i].tiles[y * mapWidth + x]
                }
            }
            layers[i].tiles = newTiles
        }
        mapWidth  = width
        mapHeight = height
    }


    static func encodeGID(tilesetIndex: Int, localIndex: Int) -> Int {
        tilesetIndex * TilesetInfo.GID_STRIDE + localIndex
    }

    static func decodeGID(_ gid: Int) -> (tilesetIndex: Int, localIndex: Int) {
        (gid / TilesetInfo.GID_STRIDE, gid % TilesetInfo.GID_STRIDE)
    }
}

// MARK: - Tool

enum TilemapTool: String, CaseIterable, Identifiable {
    case paint    = "Pencil"
    case erase    = "Eraser"
    case fill     = "Fill"
    case rectFill = "Rect Fill"
    case pan      = "Pan"
    case select   = "Select"
    case eyedropper = "Eyedropper"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .paint:    return "pencil"
        case .erase:    return "eraser"
        case .fill:     return "drop.fill"
        case .rectFill: return "square.dashed.inset.filled"
        case .pan:      return "hand.draw"
        case .select:   return "rectangle.dashed"
        case .eyedropper: return "eyedropper"
        }
    }
}
