import Foundation

enum AnimationFrameSelectionMode: String, Codable, CaseIterable, Identifiable {
    case range
    case manual

    var id: String { rawValue }
}

struct SpriteAnimationFrameSelection: Codable, Equatable, Identifiable {
    var id = UUID()
    var row: Int
    var column: Int
    /// Custom display duration in seconds. nil = use clip fps.
    var duration: Double? = nil
    /// How many times to repeat this frame in the exported sequence (≥1).
    var repeatCount: Int = 1

    private enum CodingKeys: String, CodingKey {
        case id, row, column, duration, repeatCount
    }

    init(row: Int, column: Int, duration: Double? = nil, repeatCount: Int = 1) {
        self.row = row
        self.column = column
        self.duration = duration
        self.repeatCount = repeatCount
    }

    init(from decoder: Decoder) throws {
        let c   = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decodeIfPresent(UUID.self,   forKey: .id)          ?? UUID()
        row         = try c.decode(Int.self,              forKey: .row)
        column      = try c.decode(Int.self,              forKey: .column)
        duration    = try c.decodeIfPresent(Double.self,  forKey: .duration)
        repeatCount = try c.decodeIfPresent(Int.self,     forKey: .repeatCount) ?? 1
    }
}

struct SpriteAnimationEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    var framePosition: Int = 0
    var eventName: String = "event"
}

/// Axis-aligned hitbox defined for a specific frame index within a clip.
struct FrameHitbox: Codable, Equatable, Identifiable {
    var id = UUID()
    /// 0-based frame index within the clip.
    var frameIndex: Int = 0
    var x: Double = 0
    var y: Double = 0
    var width: Double = 16
    var height: Double = 16
    var label: String = "body"

    private enum CodingKeys: String, CodingKey {
        case id, frameIndex, x, y, width, height, label
    }

    init(frameIndex: Int = 0, x: Double = 0, y: Double = 0,
         width: Double = 16, height: Double = 16, label: String = "body") {
        self.frameIndex = frameIndex; self.x = x; self.y = y
        self.width = width; self.height = height; self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(UUID.self,   forKey: .id)         ?? UUID()
        frameIndex = try c.decode(Int.self,              forKey: .frameIndex)
        x          = try c.decodeIfPresent(Double.self,  forKey: .x)          ?? 0
        y          = try c.decodeIfPresent(Double.self,  forKey: .y)          ?? 0
        width      = try c.decodeIfPresent(Double.self,  forKey: .width)      ?? 16
        height     = try c.decodeIfPresent(Double.self,  forKey: .height)     ?? 16
        label      = try c.decodeIfPresent(String.self,  forKey: .label)      ?? "body"
    }
}

struct SpriteAnimationClip: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String = "idle"
    var selectionMode: AnimationFrameSelectionMode = .manual
    var startRow: Int = 1
    var startColumn: Int = 1
    var frameCount: Int = 0
    var frames: [SpriteAnimationFrameSelection] = []
    var fps: Double = 12
    var loops: Bool = true
    var flipH: Bool = false
    var flipV: Bool = false
    var events: [SpriteAnimationEvent] = []
    /// Playback speed multiplier (1.0 = normal, 2.0 = double speed, 0.5 = half speed).
    var speed: Double = 1.0
    /// Per-frame hitboxes. Multiple hitboxes can share the same frameIndex.
    var hitboxes: [FrameHitbox] = []
}

struct SpriteAnimationConfig: Codable, Equatable, Identifiable {
    var id = UUID()

    var moduleName: String = "PlayerAnimation"
    var spriteSheetPath: String = ""

    var frameWidth: Int = 32
    var frameHeight: Int = 32

    var marginX: Int = 0
    var marginY: Int = 0
    var spacingX: Int = 0
    var spacingY: Int = 0

    var centerOrigin: Bool = true
    var offsetX: Double = 0
    var offsetY: Double = 0

    var clips: [SpriteAnimationClip] = [SpriteAnimationClip()]

    private enum CodingKeys: String, CodingKey {
        case id
        case moduleName
        case spriteSheetPath
        case frameWidth
        case frameHeight
        case marginX
        case marginY
        case spacingX
        case spacingY
        case centerOrigin
        case offsetX
        case offsetY
        case clips

        // Legacy single-clip keys.
        case clipName
        case selectionMode
        case startRow
        case startColumn
        case frameCount
        case manualFrames
        case fps
        case loops
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        moduleName = try container.decodeIfPresent(String.self, forKey: .moduleName) ?? "PlayerAnimation"
        spriteSheetPath = try container.decodeIfPresent(String.self, forKey: .spriteSheetPath) ?? ""
        frameWidth = try container.decodeIfPresent(Int.self, forKey: .frameWidth) ?? 32
        frameHeight = try container.decodeIfPresent(Int.self, forKey: .frameHeight) ?? 32
        marginX = try container.decodeIfPresent(Int.self, forKey: .marginX) ?? 0
        marginY = try container.decodeIfPresent(Int.self, forKey: .marginY) ?? 0
        spacingX = try container.decodeIfPresent(Int.self, forKey: .spacingX) ?? 0
        spacingY = try container.decodeIfPresent(Int.self, forKey: .spacingY) ?? 0
        centerOrigin = try container.decodeIfPresent(Bool.self, forKey: .centerOrigin) ?? true
        offsetX = try container.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try container.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0

        if let decodedClips = try container.decodeIfPresent([SpriteAnimationClip].self, forKey: .clips),
           !decodedClips.isEmpty {
            clips = decodedClips
        } else {
            let legacyClip = SpriteAnimationClip(
                name: try container.decodeIfPresent(String.self, forKey: .clipName) ?? "run",
                selectionMode: try container.decodeIfPresent(AnimationFrameSelectionMode.self, forKey: .selectionMode) ?? .range,
                startRow: try container.decodeIfPresent(Int.self, forKey: .startRow) ?? 1,
                startColumn: try container.decodeIfPresent(Int.self, forKey: .startColumn) ?? 1,
                frameCount: try container.decodeIfPresent(Int.self, forKey: .frameCount) ?? 6,
                frames: try container.decodeIfPresent([SpriteAnimationFrameSelection].self, forKey: .manualFrames) ?? [],
                fps: try container.decodeIfPresent(Double.self, forKey: .fps) ?? 12,
                loops: try container.decodeIfPresent(Bool.self, forKey: .loops) ?? true
            )
            clips = [legacyClip]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(moduleName, forKey: .moduleName)
        try container.encode(spriteSheetPath, forKey: .spriteSheetPath)
        try container.encode(frameWidth, forKey: .frameWidth)
        try container.encode(frameHeight, forKey: .frameHeight)
        try container.encode(marginX, forKey: .marginX)
        try container.encode(marginY, forKey: .marginY)
        try container.encode(spacingX, forKey: .spacingX)
        try container.encode(spacingY, forKey: .spacingY)
        try container.encode(centerOrigin, forKey: .centerOrigin)
        try container.encode(offsetX, forKey: .offsetX)
        try container.encode(offsetY, forKey: .offsetY)
        try container.encode(clips, forKey: .clips)
    }
}
