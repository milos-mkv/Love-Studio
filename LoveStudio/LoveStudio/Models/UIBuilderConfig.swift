import Foundation
import AppKit
import SwiftUI

// MARK: - Element type

enum UIElementType: String, Codable, CaseIterable, Identifiable {
    case button      = "button"
    case label       = "label"
    case slider      = "slider"
    case checkbox    = "checkbox"
    case radioButton = "radioButton"
    case progressBar = "progressBar"
    case panel       = "panel"
    case textInput   = "textInput"
    case image       = "image"
    case scrollBar   = "scrollBar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .button:      return "Button"
        case .label:       return "Label"
        case .slider:      return "Slider"
        case .checkbox:    return "Checkbox"
        case .radioButton: return "Radio Button"
        case .progressBar: return "Progress Bar"
        case .panel:       return "Panel"
        case .textInput:   return "Text Input"
        case .image:       return "Image"
        case .scrollBar:   return "Scroll Bar"
        }
    }

    var icon: String {
        switch self {
        case .button:      return "rectangle.fill"
        case .label:       return "text.alignleft"
        case .slider:      return "slider.horizontal.3"
        case .checkbox:    return "checkmark.square"
        case .radioButton: return "circle.inset.filled"
        case .progressBar: return "chart.bar.fill"
        case .panel:       return "rectangle.split.2x1"
        case .textInput:   return "rectangle.and.pencil.and.ellipsis"
        case .image:       return "photo"
        case .scrollBar:   return "arrow.up.and.down.square"
        }
    }

    var defaultWidth:  Double { switch self {
        case .button: return 120; case .label: return 160; case .slider: return 200
        case .checkbox: return 140; case .radioButton: return 140; case .progressBar: return 200
        case .panel: return 240; case .textInput: return 200; case .image: return 100
        case .scrollBar: return 16
    }}
    var defaultHeight: Double { switch self {
        case .button: return 36; case .label: return 24; case .slider: return 32
        case .checkbox: return 28; case .radioButton: return 28; case .progressBar: return 20
        case .panel: return 160; case .textInput: return 36; case .image: return 100
        case .scrollBar: return 120
    }}
}

// MARK: - Color helper (stored as RGBA 0–1)

struct UIColor4: Codable, Equatable {
    var r: Double; var g: Double; var b: Double; var a: Double
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    var nsColor: NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }
    var swiftUI: SwiftUI.Color { SwiftUI.Color(red: r, green: g, blue: b).opacity(a) }
    var lua:     String { "{ \(fmt(r)), \(fmt(g)), \(fmt(b)), \(fmt(a)) }" }
    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    static let white      = UIColor4(1, 1, 1)
    static let black      = UIColor4(0, 0, 0)
    static let darkBg     = UIColor4(0.18, 0.18, 0.20)
    static let midGray    = UIColor4(0.35, 0.35, 0.38)
    static let lightGray  = UIColor4(0.75, 0.75, 0.78)
    static let accent     = UIColor4(0.20, 0.55, 1.00)
    static let hoverBg    = UIColor4(0.28, 0.28, 0.32)
    static let pressBg    = UIColor4(0.12, 0.12, 0.14)
    static let border     = UIColor4(0.40, 0.40, 0.45)
    static let transparent = UIColor4(0, 0, 0, 0)
}

// MARK: - Element style

struct UIElementStyle: Codable, Equatable {
    var bgColor:      UIColor4 = .darkBg
    var hoverColor:   UIColor4 = .hoverBg
    var pressColor:   UIColor4 = .pressBg
    var textColor:    UIColor4 = .white
    var borderColor:  UIColor4 = .border
    var accentColor:  UIColor4 = .accent
    var trackColor:   UIColor4 = .midGray
    var thumbColor:   UIColor4 = .lightGray
    var cornerRadius: Double = 6
    var borderWidth:  Double = 1
    var fontSize:     Double = 13
    var padding:      Double = 8
    var thumbSize:    Double = 16
    /// If non-empty, use this Font Manager module + key instead of _getFont()
    var fontManagerModule: String = ""
    var fontManagerKey:    String = ""
}

// MARK: - UI element

struct UIElement: Codable, Identifiable, Equatable {
    var id:      UUID          = UUID()
    var type:    UIElementType = .button
    var name:    String        = "element"
    var label:   String        = "Button"
    var x:       Double        = 20
    var y:       Double        = 20
    var width:   Double        = 120
    var height:  Double        = 36
    var style:   UIElementStyle = UIElementStyle()

    // Slider / Progress Bar
    var value:    Double = 0.5
    var minValue: Double = 0.0
    var maxValue: Double = 1.0

    // Checkbox / Radio
    var checked: Bool = false

    // Text Input
    var placeholder: String = "Enter text…"

    // Image
    var imagePath: String = ""

    // Panel title
    var showTitle: Bool = true

    // Orientation (slider, scrollbar)
    var horizontal: Bool = true

    // Enabled
    var enabled: Bool = true
}

// MARK: - UI builder config

struct UIBuilderConfig: Codable, Equatable, Identifiable {
    var id:           UUID     = UUID()
    var moduleName:   String   = "UI"
    var elements:     [UIElement] = []
    var canvasWidth:  Int      = 800
    var canvasHeight: Int      = 600
    var canvasBg:     UIColor4 = UIColor4(0.12, 0.12, 0.14)
}
