import Foundation

// MARK: - conf.lua model

struct ConfLua: Equatable {
    var title           : String         = "Untitled Game"
    var version         : String         = "11.5"
    var width           : Int            = 800
    var height          : Int            = 600
    var fullscreen      : Bool           = false
    var fullscreenType  : FullscreenType = .desktop
    var resizable       : Bool           = false
    var vsync           : Int            = 1
    var msaa            : Int            = 0
    var borderless      : Bool           = false
    var identity        : String         = ""

    // Modules
    var moduleAudio       : Bool = true
    var moduleData        : Bool = true
    var moduleEvent       : Bool = true
    var moduleFont        : Bool = true
    var moduleGraphics    : Bool = true
    var moduleImage       : Bool = true
    var moduleJoystick    : Bool = true
    var moduleKeyboard    : Bool = true
    var moduleMath        : Bool = true
    var moduleMouse       : Bool = true
    var modulePhysics     : Bool = true
    var moduleSound       : Bool = true
    var moduleSystem      : Bool = true
    var moduleThread      : Bool = true
    var moduleTimer       : Bool = true
    var moduleTouchscreen : Bool = true
    var moduleVideo       : Bool = true
    var moduleWindow      : Bool = true

    enum FullscreenType: String, CaseIterable, Identifiable {
        case desktop   = "desktop"
        case exclusive = "exclusive"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .desktop:   return "Desktop (recommended)"
            case .exclusive: return "Exclusive"
            }
        }
    }
}

// MARK: - Parser / Generator

struct ConfLuaParser {

    static func parse(from url: URL) -> ConfLua {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return ConfLua() }
        return parse(string: content)
    }

    static func parse(string: String) -> ConfLua {
        var conf = ConfLua()

        func str(_ key: String) -> String? {
            let pattern = #"t\."# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*"([^"]+)""#
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m  = re.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
                  let r  = Range(m.range(at: 1), in: string) else { return nil }
            return String(string[r])
        }

        func int(_ key: String) -> Int? {
            let pattern = #"t\."# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*(-?\d+)"#
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m  = re.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
                  let r  = Range(m.range(at: 1), in: string) else { return nil }
            return Int(string[r])
        }

        func bool(_ key: String) -> Bool? {
            let pattern = #"t\."# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*(true|false)"#
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m  = re.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
                  let r  = Range(m.range(at: 1), in: string) else { return nil }
            return string[r] == "true"
        }

        if let v = str("title")                 { conf.title = v }
        if let v = str("version")               { conf.version = v }
        if let v = int("window.width")          { conf.width = v }
        if let v = int("window.height")         { conf.height = v }
        if let v = bool("window.fullscreen")    { conf.fullscreen = v }
        if let v = str("window.fullscreentype") { conf.fullscreenType = .init(rawValue: v) ?? .desktop }
        if let v = bool("window.resizable")     { conf.resizable = v }
        if let v = int("window.vsync")          { conf.vsync = v }
        if let v = int("window.msaa")           { conf.msaa = v }
        if let v = bool("window.borderless")    { conf.borderless = v }
        if let v = str("identity")              { conf.identity = v }

        if let v = bool("modules.audio")       { conf.moduleAudio = v }
        if let v = bool("modules.data")        { conf.moduleData = v }
        if let v = bool("modules.event")       { conf.moduleEvent = v }
        if let v = bool("modules.font")        { conf.moduleFont = v }
        if let v = bool("modules.graphics")    { conf.moduleGraphics = v }
        if let v = bool("modules.image")       { conf.moduleImage = v }
        if let v = bool("modules.joystick")    { conf.moduleJoystick = v }
        if let v = bool("modules.keyboard")    { conf.moduleKeyboard = v }
        if let v = bool("modules.math")        { conf.moduleMath = v }
        if let v = bool("modules.mouse")       { conf.moduleMouse = v }
        if let v = bool("modules.physics")     { conf.modulePhysics = v }
        if let v = bool("modules.sound")       { conf.moduleSound = v }
        if let v = bool("modules.system")      { conf.moduleSystem = v }
        if let v = bool("modules.thread")      { conf.moduleThread = v }
        if let v = bool("modules.timer")       { conf.moduleTimer = v }
        if let v = bool("modules.touch")       { conf.moduleTouchscreen = v }
        if let v = bool("modules.video")       { conf.moduleVideo = v }
        if let v = bool("modules.window")      { conf.moduleWindow = v }

        return conf
    }

    // MARK: Generate

    static func generate(_ conf: ConfLua) -> String {
        let mods = modulesBlock(conf)
        let identityLine = conf.identity.isEmpty
            ? "    -- t.identity = \"mygame\""
            : "    t.identity = \"\(conf.identity)\""

        return """
function love.conf(t)
    t.title   = "\(conf.title)"
    t.version = "\(conf.version)"
\(identityLine)

    t.window.width          = \(conf.width)
    t.window.height         = \(conf.height)
    t.window.fullscreen     = \(conf.fullscreen)
    t.window.fullscreentype = "\(conf.fullscreenType.rawValue)"
    t.window.resizable      = \(conf.resizable)
    t.window.vsync          = \(conf.vsync)
    t.window.msaa           = \(conf.msaa)
    t.window.borderless     = \(conf.borderless)
\(mods)end
"""
    }

    private static func modulesBlock(_ conf: ConfLua) -> String {
        let all: [(String, Bool)] = [
            ("audio",    conf.moduleAudio),
            ("data",     conf.moduleData),
            ("event",    conf.moduleEvent),
            ("font",     conf.moduleFont),
            ("graphics", conf.moduleGraphics),
            ("image",    conf.moduleImage),
            ("joystick", conf.moduleJoystick),
            ("keyboard", conf.moduleKeyboard),
            ("math",     conf.moduleMath),
            ("mouse",    conf.moduleMouse),
            ("physics",  conf.modulePhysics),
            ("sound",    conf.moduleSound),
            ("system",   conf.moduleSystem),
            ("thread",   conf.moduleThread),
            ("timer",    conf.moduleTimer),
            ("touch",    conf.moduleTouchscreen),
            ("video",    conf.moduleVideo),
            ("window",   conf.moduleWindow),
        ]
        let disabled = all.filter { !$0.1 }.map { "    t.modules.\($0.0) = false" }
        guard !disabled.isEmpty else { return "\n" }
        return "\n" + disabled.joined(separator: "\n") + "\n\n"
    }
}
