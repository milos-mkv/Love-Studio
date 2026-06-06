import Foundation

struct CameraConfig: Codable, Equatable, Identifiable {
    var id:         UUID   = UUID()
    var moduleName: String = "Camera"

    // ── Follow / lerp ────────────────────────────────────────────────────
    var lerpSpeed:   Double = 0.10   // 0.01–1.0  (how fast camera follows target)
    var roundPixels: Bool   = false  // snap position to integer pixels

    // ── Zoom ─────────────────────────────────────────────────────────────
    var defaultZoom:   Double = 1.0   // initial zoom level
    var zoomLerpSpeed: Double = 0.10  // smooth zoom transition speed

    // ── Shake ─────────────────────────────────────────────────────────────
    var shakeIntensity: Double = 8.0   // max pixel offset per axis
    var shakeDecay:     Double = 0.90  // magnitude multiplier per frame (0.80–0.99)

    // ── Deadzone (camera only moves when target leaves this box) ──────────
    var deadzoneEnabled: Bool   = false
    var deadzoneW:       Double = 100
    var deadzoneH:       Double = 80

    // ── World bounds (clamp so edges of world are never shown) ───────────
    var boundsEnabled: Bool   = false
    var boundsX:       Double = 0
    var boundsY:       Double = 0
    var boundsW:       Double = 1920
    var boundsH:       Double = 1080
}
