import Foundation

// MARK: - Scaling mode

enum ScalingMode: String, Codable, CaseIterable, Identifiable {
    case pixelPerfect = "pixelPerfect"
    case letterbox    = "letterbox"
    case stretch      = "stretch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pixelPerfect: return "Pixel-perfect"
        case .letterbox:    return "Letterbox"
        case .stretch:      return "Stretch"
        }
    }

    var description: String {
        switch self {
        case .pixelPerfect:
            return "Largest integer multiplier that fits the window. No blurring, perfectly sharp pixels. Black bars may appear."
        case .letterbox:
            return "Scale to fill window while keeping aspect ratio. Non-integer scale — use nearest filter to avoid blur."
        case .stretch:
            return "Fill the entire window, ignoring aspect ratio. May distort the image on non-matching screen sizes."
        }
    }

    var icon: String {
        switch self {
        case .pixelPerfect: return "square.grid.2x2"
        case .letterbox:    return "rectangle.arrowtriangle.2.outward"
        case .stretch:      return "arrow.up.left.and.arrow.down.right"
        }
    }
}

// MARK: - Filter mode

enum FilterMode: String, Codable, CaseIterable, Identifiable {
    case nearest = "nearest"
    case linear  = "linear"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nearest: return "Nearest (pixel-art)"
        case .linear:  return "Linear (smooth)"
        }
    }

    var description: String {
        switch self {
        case .nearest: return "Each pixel stays a sharp square. Best for pixel-art and retro games."
        case .linear:  return "Pixels are blended when scaled. Better for high-res art or smooth upscaling."
        }
    }
}

// MARK: - Common virtual resolution presets

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case custom      = "Custom"
    case r320x180    = "320 × 180"
    case r384x216    = "384 × 216"
    case r480x270    = "480 × 270"
    case r640x360    = "640 × 360"
    case r320x240    = "320 × 240  (4:3)"
    case r256x224    = "256 × 224  (SNES)"
    case r160x144    = "160 × 144  (Game Boy)"
    case r256x144    = "256 × 144"

    var id: String { rawValue }

    var size: (Int, Int)? {
        switch self {
        case .custom:   return nil
        case .r320x180: return (320, 180)
        case .r384x216: return (384, 216)
        case .r480x270: return (480, 270)
        case .r640x360: return (640, 360)
        case .r320x240: return (320, 240)
        case .r256x224: return (256, 224)
        case .r160x144: return (160, 144)
        case .r256x144: return (256, 144)
        }
    }
}

// MARK: - Resolution config

struct ResolutionConfig: Codable, Equatable, Identifiable {
    var id:           UUID        = UUID()
    var moduleName:   String      = "Resolution"

    // Virtual canvas size (the "game" resolution)
    var virtualWidth:  Int = 320
    var virtualHeight: Int = 180

    // How the canvas is scaled to fill the window
    var scalingMode:  ScalingMode = .pixelPerfect
    var filterMode:   FilterMode  = .nearest

    // Preview window size (used only for the UI preview — not written to Lua)
    var previewWindowW: Int = 1280
    var previewWindowH: Int = 720
}
