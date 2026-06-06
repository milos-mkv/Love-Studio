import AppKit
import Foundation

// MARK: - LoveAPISignatures

enum LoveAPISignatures {
    struct SignatureInfo {
        let params: [String]
        let full: String
    }

    private static let signatures: [String: SignatureInfo] = {
        var map = [String: SignatureInfo]()

        func add(_ name: String, _ params: [String]) {
            let full = "\(name)(\(params.joined(separator: ", ")))"
            map[name] = SignatureInfo(params: params, full: full)
        }

        // love.graphics
        add("love.graphics.draw",            ["drawable", "x", "y", "r", "sx", "sy", "ox", "oy", "kx", "ky"])
        add("love.graphics.print",           ["text", "x", "y", "r", "sx", "sy", "ox", "oy", "kx", "ky"])
        add("love.graphics.printf",          ["text", "x", "y", "limit", "align", "r", "sx", "sy", "ox", "oy", "kx", "ky"])
        add("love.graphics.rectangle",       ["mode", "x", "y", "width", "height", "rx", "ry", "segments"])
        add("love.graphics.circle",          ["mode", "x", "y", "radius", "segments"])
        add("love.graphics.ellipse",         ["mode", "x", "y", "a", "b", "segments"])
        add("love.graphics.line",            ["x1", "y1", "x2", "y2", "..."])
        add("love.graphics.polygon",         ["mode", "vertices"])
        add("love.graphics.points",          ["x1", "y1", "x2", "y2", "..."])
        add("love.graphics.arc",             ["drawmode", "x", "y", "radius", "angle1", "angle2", "segments"])
        add("love.graphics.setColor",        ["red", "green", "blue", "alpha"])
        add("love.graphics.getColor",        [])
        add("love.graphics.setBackgroundColor", ["red", "green", "blue", "alpha"])
        add("love.graphics.newImage",        ["filename", "flags"])
        add("love.graphics.newFont",         ["filename", "size"])
        add("love.graphics.newCanvas",       ["width", "height", "settings"])
        add("love.graphics.newQuad",         ["x", "y", "width", "height", "sw", "sh"])
        add("love.graphics.newShader",       ["code"])
        add("love.graphics.newSpriteBatch",  ["image", "maxsprites", "usage"])
        add("love.graphics.newMesh",         ["vertices", "mode", "usage"])
        add("love.graphics.newText",         ["font", "textstring"])
        add("love.graphics.push",            ["stack"])
        add("love.graphics.pop",             [])
        add("love.graphics.translate",       ["dx", "dy"])
        add("love.graphics.rotate",          ["angle"])
        add("love.graphics.scale",           ["sx", "sy"])
        add("love.graphics.origin",          [])
        add("love.graphics.reset",           [])
        add("love.graphics.setLineWidth",    ["width"])
        add("love.graphics.setFont",         ["font"])
        add("love.graphics.setBlendMode",    ["mode", "alphamode"])
        add("love.graphics.setCanvas",       ["canvas", "..."])
        add("love.graphics.setScissor",      ["x", "y", "width", "height"])
        add("love.graphics.getWidth",        [])
        add("love.graphics.getHeight",       [])
        add("love.graphics.getDimensions",   [])
        add("love.graphics.clear",           ["r", "g", "b", "a"])
        add("love.graphics.present",         [])

        // love.audio
        add("love.audio.newSource",          ["filename", "type"])
        add("love.audio.play",               ["source"])
        add("love.audio.stop",               ["source"])
        add("love.audio.pause",              ["source"])
        add("love.audio.resume",             ["source"])
        add("love.audio.setVolume",          ["volume"])
        add("love.audio.getVolume",          [])
        add("love.audio.setPosition",        ["x", "y", "z"])
        add("love.audio.getPosition",        [])

        // love.math
        add("love.math.random",              ["m", "n"])
        add("love.math.randomNormal",        ["stddev", "mean"])
        add("love.math.noise",               ["x", "y", "z", "w"])
        add("love.math.newTransform",        ["x", "y", "angle", "sx", "sy", "ox", "oy", "kx", "ky"])
        add("love.math.newBezierCurve",      ["vertices"])

        // love.filesystem
        add("love.filesystem.read",          ["name", "size"])
        add("love.filesystem.write",         ["name", "data", "size"])
        add("love.filesystem.append",        ["name", "data", "size"])
        add("love.filesystem.exists",        ["name"])
        add("love.filesystem.getInfo",       ["path", "filtertype"])
        add("love.filesystem.lines",         ["name"])
        add("love.filesystem.newFile",       ["filename", "mode"])
        add("love.filesystem.remove",        ["name"])
        add("love.filesystem.createDirectory", ["name"])
        add("love.filesystem.getDirectoryItems", ["dir"])

        // love.window
        add("love.window.setTitle",          ["title"])
        add("love.window.getTitle",          [])
        add("love.window.setMode",           ["width", "height", "flags"])
        add("love.window.getMode",           [])
        add("love.window.setFullscreen",     ["fullscreen", "fstype"])
        add("love.window.isFullscreen",      [])
        add("love.window.getDimensions",     [])
        add("love.window.getPosition",       [])
        add("love.window.setPosition",       ["x", "y", "displayindex"])
        add("love.window.hasFocus",          [])

        // love.keyboard
        add("love.keyboard.isDown",          ["key", "..."])
        add("love.keyboard.isScancodeDown",  ["scancode", "..."])
        add("love.keyboard.setKeyRepeat",    ["enable"])
        add("love.keyboard.hasTextInput",    [])
        add("love.keyboard.setTextInput",    ["enable", "x", "y", "w", "h"])

        // love.mouse
        add("love.mouse.getPosition",        [])
        add("love.mouse.setPosition",        ["x", "y"])
        add("love.mouse.isDown",             ["button", "..."])
        add("love.mouse.getX",               [])
        add("love.mouse.getY",               [])
        add("love.mouse.setCursor",          ["cursor"])
        add("love.mouse.getRelativeMode",    [])
        add("love.mouse.setRelativeMode",    ["enable"])

        // love.physics
        add("love.physics.newWorld",         ["xg", "yg", "sleep"])
        add("love.physics.newBody",          ["world", "x", "y", "type"])
        add("love.physics.newCircleShape",   ["radius"])
        add("love.physics.newRectangleShape", ["width", "height", "angle"])
        add("love.physics.newPolygonShape",  ["x1", "y1", "x2", "y2", "..."])
        add("love.physics.newFixture",       ["body", "shape", "density"])

        // love.timer
        add("love.timer.getDelta",           [])
        add("love.timer.getFPS",             [])
        add("love.timer.getTime",            [])
        add("love.timer.sleep",              ["seconds"])
        add("love.timer.step",               [])

        return map
    }()

    static func signature(for functionName: String) -> (params: [String], full: String)? {
        guard let info = signatures[functionName] else { return nil }
        return (info.params, info.full)
    }
}

// MARK: - SignatureHintPanel

final class SignatureHintPanel: NSObject {

    // MARK: Shared instance

    static let shared = SignatureHintPanel()

    // MARK: Private state

    private let panel: NSPanel
    private let effectView: NSVisualEffectView
    private let label: NSTextField
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat   = 5
    private let maxWidth: CGFloat          = 600
    private let cornerRadius: CGFloat      = 8
    private let panelOffset: CGFloat       = 4   // gap between cursor rect and panel

    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var appMonitorTokens: [NSObjectProtocol] = []

    // MARK: Init

    private override init() {
        // Panel
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level                 = .popUpMenu
        panel.isOpaque              = false
        panel.backgroundColor       = .clear
        panel.hasShadow             = true
        panel.ignoresMouseEvents    = true
        panel.collectionBehavior    = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Blur background
        effectView = NSVisualEffectView()
        effectView.material         = .menu
        effectView.blendingMode     = .behindWindow
        effectView.state            = .active
        effectView.wantsLayer       = true
        effectView.layer?.cornerRadius  = 8
        effectView.layer?.masksToBounds = true

        // Border layer (added after layer is ready)
        // Label
        label = NSTextField(labelWithString: "")
        label.isEditable            = false
        label.isSelectable          = false
        label.drawsBackground       = false
        label.isBezeled             = false
        label.maximumNumberOfLines  = 1
        label.lineBreakMode         = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        // Border
        let borderLayer          = CALayer()
        borderLayer.borderColor  = NSColor.separatorColor.cgColor
        borderLayer.borderWidth  = 0.5
        borderLayer.cornerRadius = 8
        borderLayer.frame        = effectView.bounds
        borderLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        effectView.layer?.addSublayer(borderLayer)

        // Layout
        effectView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: effectView.topAnchor, constant: verticalPadding),
            label.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -verticalPadding)
        ])

        panel.contentView = effectView
    }

    // MARK: Public API

    var isVisible: Bool { panel.isVisible }

    /// Show the signature hint panel near the cursor.
    /// - Parameters:
    ///   - signature: Full function signature string, e.g. `"love.graphics.draw(drawable, x, y)"`.
    ///   - activeParam: Zero-based index of the currently active parameter.
    ///   - cursorScreenRect: The bounding rect of the cursor/caret in screen coordinates.
    func show(signature: String, activeParam: Int, cursorScreenRect: NSRect) {
        label.attributedStringValue = buildAttributedString(signature: signature, activeParam: activeParam)

        // Size to fit
        let fittingSize = label.fittingSize
        let panelWidth  = min(fittingSize.width + horizontalPadding * 2, maxWidth)
        let panelHeight = fittingSize.height + verticalPadding * 2

        // Determine position: prefer below cursor, fall back above
        let screen      = NSScreen.screens.first(where: { $0.frame.contains(cursorScreenRect.origin) })
                          ?? NSScreen.main
                          ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame

        let preferredX  = cursorScreenRect.minX
        let belowY      = cursorScreenRect.minY - panelOffset - panelHeight
        let aboveY      = cursorScreenRect.maxY + panelOffset

        let originX     = max(screenFrame.minX,
                              min(preferredX, screenFrame.maxX - panelWidth))
        let originY: CGFloat
        if belowY >= screenFrame.minY {
            originY = belowY
        } else {
            originY = aboveY
        }

        let panelFrame = NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight)
        panel.setFrame(panelFrame, display: false)
        panel.orderFront(nil)
        startMonitors()
    }

    /// Hide the signature hint panel.
    func dismiss() {
        panel.orderOut(nil)
        stopMonitors()
    }

    // MARK: Monitors

    private func startMonitors() {
        guard mouseMonitor == nil else { return }

        // Global: clicks outside the app
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismiss()
        }

        // Local: clicks inside the app
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.dismiss()
            return event
        }

        guard appMonitorTokens.isEmpty else { return }
        let nc = NotificationCenter.default
        let t1 = nc.addObserver(forName: NSApplication.didResignActiveNotification,
                                object: nil, queue: .main) { [weak self] _ in
            self?.dismiss()
        }
        let t2 = nc.addObserver(forName: NSWindow.didResignKeyNotification,
                                object: nil, queue: .main) { [weak self] _ in
            self?.dismiss()
        }
        appMonitorTokens = [t1, t2]
    }

    private func stopMonitors() {
        if let m = mouseMonitor      { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        appMonitorTokens.forEach { NotificationCenter.default.removeObserver($0) }
        appMonitorTokens = []
    }

    // MARK: Attributed string builder

    private func buildAttributedString(signature: String, activeParam: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Typography
        let font         = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let boldFont     = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .bold)
        let primaryColor = NSColor.labelColor
        let secondaryColor = NSColor.secondaryLabelColor
        let accentColor  = NSColor.controlAccentColor

        func append(_ text: String, color: NSColor, font: NSFont) {
            result.append(NSAttributedString(string: text, attributes: [
                .foregroundColor: color,
                .font: font
            ]))
        }

        // Parse: split at first '('
        guard let parenOpen = signature.firstIndex(of: "(") else {
            append(signature, color: primaryColor, font: font)
            return result
        }

        let funcName   = String(signature[signature.startIndex ..< parenOpen])
        let afterParen = String(signature[signature.index(after: parenOpen)...])

        // Strip trailing ')'
        let paramsRaw: String
        if afterParen.hasSuffix(")") {
            paramsRaw = String(afterParen.dropLast())
        } else {
            paramsRaw = afterParen
        }

        // Function name
        append(funcName, color: primaryColor, font: font)
        append("(", color: primaryColor, font: font)

        // Split params — naive comma split (suitable for LÖVE API flat param lists)
        if paramsRaw.isEmpty {
            append(")", color: primaryColor, font: font)
            return result
        }

        let params = paramsRaw.components(separatedBy: ", ")
        for (index, param) in params.enumerated() {
            let isActive = index == activeParam
            append(param,
                   color: isActive ? accentColor : secondaryColor,
                   font:  isActive ? boldFont    : font)
            if index < params.count - 1 {
                append(", ", color: secondaryColor, font: font)
            }
        }

        append(")", color: primaryColor, font: font)
        return result
    }
}
