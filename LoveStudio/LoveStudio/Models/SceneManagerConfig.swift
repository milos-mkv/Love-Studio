import Foundation
import CoreGraphics

enum SceneTransitionEffect: String, Codable, CaseIterable, Identifiable {
    case none        = "none"
    case fade        = "fade"
    case pop         = "pop"
    case slideLeft   = "slide_left"
    case slideRight  = "slide_right"
    case slideUp     = "slide_up"
    case slideDown   = "slide_down"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:       return "None"
        case .fade:       return "Fade"
        case .pop:        return "Pop"
        case .slideLeft:  return "Slide Left"
        case .slideRight: return "Slide Right"
        case .slideUp:    return "Slide Up"
        case .slideDown:  return "Slide Down"
        }
    }

    var icon: String {
        switch self {
        case .none:       return "circle.slash"
        case .fade:       return "circle.lefthalf.filled"
        case .pop:        return "arrow.up.left.and.arrow.down.right"
        case .slideLeft:  return "arrow.left.square"
        case .slideRight: return "arrow.right.square"
        case .slideUp:    return "arrow.up.square"
        case .slideDown:  return "arrow.down.square"
        }
    }
}

enum SceneTransitionEasing: String, Codable, CaseIterable, Identifiable {
    case linear    = "linear"
    case easeIn    = "ease_in"
    case easeOut   = "ease_out"
    case easeInOut = "ease_in_out"
    case bounce    = "bounce"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linear:    return "Linear"
        case .easeIn:    return "Ease In"
        case .easeOut:   return "Ease Out"
        case .easeInOut: return "Ease In-Out"
        case .bounce:    return "Bounce"
        }
    }

    var icon: String {
        switch self {
        case .linear:    return "line.diagonal"
        case .easeIn:    return "arrow.right"
        case .easeOut:   return "arrow.left"
        case .easeInOut: return "arrow.left.and.right"
        case .bounce:    return "waveform.path.ecg"
        }
    }
}

enum SceneCompleteTrigger: String, Codable, CaseIterable, Identifiable {
    case none   = "none"
    case timer  = "timer"
    case manual = "manual"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return "None"
        case .timer:  return "Timer"
        case .manual: return "Manual / Condition"
        }
    }
}

enum SceneCompleteAction: String, Codable, CaseIterable, Identifiable {
    case none   = "none"
    case `switch` = "switch"
    case push   = "push"
    case pop    = "pop"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return "None"
        case .switch: return "Switch"
        case .push:   return "Push"
        case .pop:    return "Pop"
        }
    }
}

// MARK: - Scene Entry

struct SceneEntry: Codable, Identifiable, Equatable {
    var id:           UUID    = UUID()
    var name:         String  = "menu"
    var displayName:  String  = "Main Menu"
    var filePath:     String  = ""
    var isInitial:    Bool    = false
    var nodePosition: CGPoint = .zero
    var backgroundColor: UIColor4 = UIColor4(0.10, 0.10, 0.15)
    var thumbnailPath: String = ""

    var hasEnter:        Bool = true
    var hasLeave:        Bool = true
    var hasPause:        Bool = false
    var hasResume:       Bool = false
    var hasLoad:         Bool = true
    var hasUpdate:       Bool = true
    var hasDraw:         Bool = true
    var hasKeypressed:   Bool = false
    var hasKeyreleased:  Bool = false
    var hasMousepressed: Bool = false
    var hasMousereleased: Bool = false
    var hasMousemoved:   Bool = false
    var hasWheelmoved:   Bool = false
    var hasTextinput:    Bool = false
    var hasResize:       Bool = false
    var hasTransitionStart: Bool = false
    var hasExitComplete: Bool = false

    var enterTransition: SceneTransitionEffect = .fade
    var enterEasing: SceneTransitionEasing = .easeInOut
    var leaveTransition: SceneTransitionEffect = .fade
    var leaveEasing: SceneTransitionEasing = .easeInOut
    var transitionDuration: Double = 0.35

    var completeTrigger: SceneCompleteTrigger = .none
    var completeAction: SceneCompleteAction = .none
    var completeTarget: String = ""
    var completeDelay: Double = 1.0
}

// MARK: - Scene Manager Config

struct SceneManagerConfig: Codable, Equatable, Identifiable {
    var id:         UUID         = UUID()
    var moduleName: String       = "Scene"
    var entries:    [SceneEntry] = []
}
