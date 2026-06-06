import Foundation

// MARK: - Audio source type

enum AudioSourceType: String, Codable, CaseIterable, Identifiable {
    case `static` = "static"   // Loaded fully into RAM - ideal for short SFX
    case stream   = "stream"   // Decoded on-the-fly - ideal for music / long clips

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .static: return "Static (SFX)"
        case .stream: return "Stream (Music)"
        }
    }

    var sfSymbol: String {
        switch self {
        case .static: return "speaker.wave.2.fill"
        case .stream: return "music.note"
        }
    }
}

// MARK: - Audio group

enum AudioGroup: String, Codable, CaseIterable, Identifiable {
    case sfx     = "sfx"
    case music   = "music"
    case ambient = "ambient"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sfx:     return "SFX"
        case .music:   return "Music"
        case .ambient: return "Ambient"
        }
    }

    var sfSymbol: String {
        switch self {
        case .sfx:     return "bolt.fill"
        case .music:   return "music.note"
        case .ambient: return "leaf.fill"
        }
    }

    var color: String {
        switch self {
        case .sfx:     return "yellow"
        case .music:   return "teal"
        case .ambient: return "green"
        }
    }
}

// MARK: - Audio entry

struct AudioEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()

    /// Lua-safe identifier used as the key in _sources table
    var name: String = "sound"

    /// Path relative to the LÖVE project root (e.g. "sounds/shoot.wav")
    var filePath: String = ""

    var sourceType: AudioSourceType = .static
    var group:      AudioGroup      = .sfx
    var volume:     Double          = 1.0   // 0–1
    var pitch:      Double          = 1.0   // 0.5–2
    var looping:    Bool            = false

    /// Name of an AudioEffect to attach (empty = no effect)
    var effectName: String = ""

    // Variation
    var pitchVariation:  Double = 0.0   // ± fraction applied randomly per play (0–0.5)
    var volumeVariation: Double = 0.0   // ± fraction applied randomly per play (0–0.5)

    // Concurrency
    var maxInstances: Int = 0           // 0 = unlimited

    // Fade
    var fadeInDuration:  Double = 0.0   // seconds (0 = instant)
    var fadeOutDuration: Double = 0.0   // seconds (0 = instant)

    // Spatial audio
    var spatial:     Bool   = false
    var minDistance: Double = 100.0     // px - full volume within this radius
    var maxDistance: Double = 500.0     // px - silent beyond this radius
    var rolloff:     Double = 1.0       // attenuation curve steepness
}

// MARK: - Effect type

enum AudioEffectType: String, Codable, CaseIterable, Identifiable {
    case reverb   = "reverb"
    case lowpass  = "lowpass"
    case highpass = "highpass"
    case echo     = "echo"
    case chorus   = "chorus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reverb:   return "Reverb"
        case .lowpass:  return "Low-pass"
        case .highpass: return "High-pass"
        case .echo:     return "Echo / Delay"
        case .chorus:   return "Chorus"
        }
    }

    var sfSymbol: String {
        switch self {
        case .reverb:   return "waveform.path.ecg.rectangle"
        case .lowpass:  return "waveform.path"
        case .highpass: return "waveform"
        case .echo:     return "arrow.trianglehead.2.counterclockwise.rotate.90"
        case .chorus:   return "music.note.list"
        }
    }

    var description: String {
        switch self {
        case .reverb:   return "Simulates room acoustics / reverb tail"
        case .lowpass:  return "Muffles high frequencies (e.g. sound through a wall)"
        case .highpass: return "Removes low frequencies (e.g. radio effect)"
        case .echo:     return "Repeating delay / echo"
        case .chorus:   return "Slight pitch modulation for a 'chorus' feel"
        }
    }
}

// MARK: - Effect parameters (union of all possible fields)

struct AudioEffectParams: Codable, Equatable {
    // Common
    var volume: Double = 1.0        // 0–1

    // Reverb
    var decayTime:  Double = 1.5    // 0.1–20  seconds
    var density:    Double = 0.9    // 0–1
    var diffusion:  Double = 0.8    // 0–1

    // Lowpass / Highpass
    var highGain: Double = 0.1      // 0–1  (lowpass: how much high freq survives)
    var lowGain:  Double = 0.1      // 0–1  (highpass: how much low freq survives)

    // Echo
    var delay:    Double = 0.25     // 0–0.5  seconds
    var feedback: Double = 0.5      // 0–1

    // Echo spread (stereo)
    var spread:   Double = 0.5      // 0–1

    // Chorus
    var rate:  Double = 1.1         // 0–10  Hz
    var depth: Double = 0.5         // 0–1
}

// MARK: - Audio effect

struct AudioEffect: Codable, Identifiable, Equatable {
    var id:     UUID              = UUID()
    var name:   String            = "myEffect"   // Lua identifier / display name
    var type:   AudioEffectType   = .reverb
    var params: AudioEffectParams = AudioEffectParams()
    var enabled: Bool             = true
}

// MARK: - Audio manager config

struct AudioManagerConfig: Codable, Equatable, Identifiable {
    var id: UUID = UUID()

    /// Name used for the returned Lua table (e.g. "Audio")
    var managerName: String = "Audio"

    var entries: [AudioEntry] = []
    var effects: [AudioEffect] = []

    // Group volume multipliers (0–1)
    var masterVolume:  Double = 1.0
    var sfxVolume:     Double = 1.0
    var musicVolume:   Double = 0.8
    var ambientVolume: Double = 0.7
}
