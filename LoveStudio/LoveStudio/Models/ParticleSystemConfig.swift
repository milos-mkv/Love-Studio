import Foundation
import AppKit

// MARK: - Config

struct ParticleSystemConfig: Codable, Equatable {
    var name: String = "New Particles"

    // Emission
    var emissionRate: Double = 80
    var maxParticles: Int    = 500
    var isBurst: Bool        = false
    var burstCount: Int      = 200

    // Lifetime (seconds)
    var lifetimeMin: Double = 0.8
    var lifetimeMax: Double = 2.2

    // Speed (px/sec in preview)
    var speedMin: Double = 60
    var speedMax: Double = 180

    // Direction (degrees; 0=right, 90=up, 180=left, 270=down)
    var directionDeg: Double = 90
    var spreadDeg:    Double = 25

    // Gravity (px/sec², positive=down on screen)
    var gravityX: Double = 0
    var gravityY: Double = 120

    // Attract/repel (positive = attract to emitter center, negative = repel)
    var attractRepelStrength: Double = 0

    // Size
    var sizeStart: Double = 14
    var sizeEnd:   Double = 2

    // Curves: 0=ease-in, 0.5=linear, 1=ease-out
    var sizeCurve:  Double = 0.5
    var alphaCurve: Double = 0.5

    // Start color
    var colorStartR: Double = 1.0
    var colorStartG: Double = 0.55
    var colorStartB: Double = 0.05
    var colorStartA: Double = 1.0

    // End color
    var colorEndR: Double = 0.9
    var colorEndG: Double = 0.1
    var colorEndB: Double = 0.0
    var colorEndA: Double = 0.0

    // Rotation
    var rotationMinDeg: Double = 0
    var rotationMaxDeg: Double = 360
    var rotSpeedMinDeg: Double = -120
    var rotSpeedMaxDeg: Double =  120

    // Emitter
    var emitterRadius: Double = 0
    var emitterShape: ParticleEmitterShape = .point
    var emitterLineLength: Double = 100
    var emitterRectW: Double = 100
    var emitterRectH: Double = 60

    // Shape (ignored when textureName is set)
    var shape: ParticleShape = .circle

    // Blend mode
    var blendMode: ParticleBlendMode = .alpha

    // Damping (linear drag 0–10; reduces speed over lifetime)
    var damping: Double = 0

    // Size variation (0–1; ±factor applied randomly to start/end size)
    var sizeVariation: Double = 0

    // Custom texture (filename relative to project root, nil = circle)
    var textureName: String? = nil

    var startNSColor: NSColor {
        NSColor(red: colorStartR, green: colorStartG, blue: colorStartB, alpha: colorStartA)
    }
    var endNSColor: NSColor {
        NSColor(red: colorEndR, green: colorEndG, blue: colorEndB, alpha: colorEndA)
    }
}

// MARK: - Shape

enum ParticleShape: String, Codable, CaseIterable, Identifiable {
    case circle   = "circle"
    case square   = "square"
    case triangle = "triangle"
    case star     = "star"
    case ring     = "ring"
    case diamond  = "diamond"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .circle:   return "Circle"
        case .square:   return "Square"
        case .triangle: return "Triangle"
        case .star:     return "Star"
        case .ring:     return "Ring"
        case .diamond:  return "Diamond"
        }
    }

    var sfSymbol: String {
        switch self {
        case .circle:   return "circle.fill"
        case .square:   return "square.fill"
        case .triangle: return "triangle.fill"
        case .star:     return "star.fill"
        case .ring:     return "circle"
        case .diamond:  return "diamond.fill"
        }
    }
}

// MARK: - Emitter shape

enum ParticleEmitterShape: String, Codable, CaseIterable, Identifiable {
    case point  = "point"
    case circle = "circle"
    case line   = "line"
    case rect   = "rect"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .point:  return "Point"
        case .circle: return "Circle"
        case .line:   return "Line"
        case .rect:   return "Rect"
        }
    }
}

// MARK: - Blend mode

enum ParticleBlendMode: String, Codable, CaseIterable, Identifiable {
    case alpha     = "alpha"
    case additive  = "add"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alpha:    return "Alpha (default)"
        case .additive: return "Additive  (fire / magic / sparks)"
        }
    }

    /// CGBlendMode used in the live preview
    var cgBlendMode: CGBlendMode {
        switch self {
        case .alpha:    return .normal
        case .additive: return .plusLighter
        }
    }
}

// MARK: - Presets

enum ParticlePreset: String, CaseIterable, Identifiable {
    case fire      = "Fire"
    case explosion = "Explosion"
    case snow      = "Snow"
    case magic     = "Magic"
    case smoke     = "Smoke"
    case confetti  = "Confetti"
    case sparks    = "Sparks"
    case bubbles   = "Bubbles"

    var id: String { rawValue }

    func makeConfig() -> ParticleSystemConfig {
        var c = ParticleSystemConfig()
        switch self {

        case .fire:
            c.name = "Fire"; c.isBurst = false
            c.emissionRate = 90; c.maxParticles = 400
            c.directionDeg = 90; c.spreadDeg = 18
            c.speedMin = 60;  c.speedMax = 160
            c.lifetimeMin = 0.7; c.lifetimeMax = 2.0
            c.gravityX = 0;   c.gravityY = -30
            c.sizeStart = 14; c.sizeEnd = 1
            c.colorStartR = 1;   c.colorStartG = 0.55; c.colorStartB = 0.05; c.colorStartA = 1
            c.colorEndR   = 0.9; c.colorEndG   = 0.08; c.colorEndB   = 0;    c.colorEndA   = 0
            c.rotSpeedMinDeg = -60; c.rotSpeedMaxDeg = 60

        case .explosion:
            c.name = "Explosion"; c.isBurst = true; c.burstCount = 180
            c.emissionRate = 0; c.maxParticles = 300
            c.directionDeg = 0; c.spreadDeg = 180
            c.speedMin = 80;  c.speedMax = 420
            c.lifetimeMin = 0.4; c.lifetimeMax = 1.4
            c.gravityX = 0;   c.gravityY = 350
            c.sizeStart = 18; c.sizeEnd = 2
            c.colorStartR = 1;   c.colorStartG = 0.80; c.colorStartB = 0.1;  c.colorStartA = 1
            c.colorEndR   = 0.8; c.colorEndG   = 0.1;  c.colorEndB   = 0;    c.colorEndA   = 0
            c.rotSpeedMinDeg = -300; c.rotSpeedMaxDeg = 300

        case .snow:
            c.name = "Snow"; c.isBurst = false
            c.emissionRate = 40; c.maxParticles = 300
            c.directionDeg = 270; c.spreadDeg = 40
            c.speedMin = 20;  c.speedMax = 80
            c.lifetimeMin = 3.0; c.lifetimeMax = 6.0
            c.gravityX = 10;  c.gravityY = 25
            c.sizeStart = 6;  c.sizeEnd = 4
            c.colorStartR = 0.9; c.colorStartG = 0.95; c.colorStartB = 1; c.colorStartA = 0.9
            c.colorEndR   = 0.8; c.colorEndG   = 0.9;  c.colorEndB   = 1; c.colorEndA   = 0
            c.rotSpeedMinDeg = -30; c.rotSpeedMaxDeg = 30

        case .magic:
            c.name = "Magic"; c.isBurst = false
            c.emissionRate = 60; c.maxParticles = 250
            c.directionDeg = 90; c.spreadDeg = 180
            c.speedMin = 30;  c.speedMax = 140
            c.lifetimeMin = 0.5; c.lifetimeMax = 1.8
            c.gravityX = 0;   c.gravityY = -60
            c.sizeStart = 10; c.sizeEnd = 0
            c.colorStartR = 1;   c.colorStartG = 0.95; c.colorStartB = 0.3;  c.colorStartA = 1
            c.colorEndR   = 0.6; c.colorEndG   = 0.2;  c.colorEndB   = 1.0;  c.colorEndA   = 0
            c.rotSpeedMinDeg = -180; c.rotSpeedMaxDeg = 180

        case .smoke:
            c.name = "Smoke"; c.isBurst = false
            c.emissionRate = 25; c.maxParticles = 200
            c.directionDeg = 90; c.spreadDeg = 30
            c.speedMin = 20;  c.speedMax = 70
            c.lifetimeMin = 2.0; c.lifetimeMax = 4.5
            c.gravityX = 5;   c.gravityY = -20
            c.sizeStart = 10; c.sizeEnd = 40
            c.colorStartR = 0.5; c.colorStartG = 0.5; c.colorStartB = 0.5; c.colorStartA = 0.55
            c.colorEndR   = 0.3; c.colorEndG   = 0.3; c.colorEndB   = 0.3; c.colorEndA   = 0
            c.rotSpeedMinDeg = -20; c.rotSpeedMaxDeg = 20

        case .confetti:
            c.name = "Confetti"; c.isBurst = true; c.burstCount = 150
            c.emissionRate = 0; c.maxParticles = 250
            c.directionDeg = 90; c.spreadDeg = 80
            c.speedMin = 100; c.speedMax = 320
            c.lifetimeMin = 1.5; c.lifetimeMax = 3.5
            c.gravityX = 0;   c.gravityY = 200
            c.sizeStart = 10; c.sizeEnd = 8
            c.colorStartR = 1; c.colorStartG = 0.3; c.colorStartB = 0.8; c.colorStartA = 1
            c.colorEndR   = 0.3; c.colorEndG = 0.8; c.colorEndB   = 1;   c.colorEndA   = 0.5
            c.rotSpeedMinDeg = -400; c.rotSpeedMaxDeg = 400

        case .sparks:
            c.name = "Sparks"; c.isBurst = false
            c.emissionRate = 120; c.maxParticles = 400
            c.directionDeg = 90; c.spreadDeg = 12
            c.speedMin = 120; c.speedMax = 350
            c.lifetimeMin = 0.2; c.lifetimeMax = 0.8
            c.gravityX = 0;   c.gravityY = 500
            c.sizeStart = 5;  c.sizeEnd = 1
            c.colorStartR = 1;   c.colorStartG = 0.95; c.colorStartB = 0.6; c.colorStartA = 1
            c.colorEndR   = 0.9; c.colorEndG   = 0.4;  c.colorEndB   = 0;   c.colorEndA   = 0
            c.rotSpeedMinDeg = 0; c.rotSpeedMaxDeg = 0

        case .bubbles:
            c.name = "Bubbles"; c.isBurst = false
            c.emissionRate = 20; c.maxParticles = 150
            c.directionDeg = 90; c.spreadDeg = 50
            c.speedMin = 15;  c.speedMax = 60
            c.lifetimeMin = 2.0; c.lifetimeMax = 5.0
            c.gravityX = 0;   c.gravityY = -30
            c.sizeStart = 8;  c.sizeEnd = 18
            c.colorStartR = 0.4; c.colorStartG = 0.8; c.colorStartB = 1; c.colorStartA = 0.6
            c.colorEndR   = 0.2; c.colorEndG   = 0.6; c.colorEndB   = 1; c.colorEndA   = 0
            c.rotSpeedMinDeg = -10; c.rotSpeedMaxDeg = 10
        }
        return c
    }
}
