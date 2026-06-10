import AppKit

// Reports mouse enter/exit so the panel can stay up while the pointer is over it.
private final class HoverEffectView: NSVisualEffectView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
}

// Borderless popover that renders multi-line markdown for symbol hover.
final class HoverPanel: NSObject {

    static let shared = HoverPanel()

    private let panel: NSPanel
    private let effectView: HoverEffectView
    private let textView: NSTextView
    private let scrollView: NSScrollView

    private let padding: CGFloat = 8
    private let maxWidth: CGFloat = 480
    private let maxHeight: CGFloat = 320
    private let panelOffset: CGFloat = 6

    private let dismissDelay: TimeInterval = 0.25
    private var dismissWorkItem: DispatchWorkItem?
    private var mouseInsidePanel = false

    private override init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level              = .popUpMenu
        panel.isOpaque           = false
        panel.backgroundColor    = .clear
        panel.hasShadow          = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        effectView = HoverEffectView()
        effectView.material         = .menu
        effectView.blendingMode     = .behindWindow
        effectView.state            = .active
        effectView.wantsLayer       = true
        effectView.layer?.cornerRadius  = 8
        effectView.layer?.masksToBounds = true

        scrollView = NSScrollView()
        scrollView.drawsBackground      = false
        scrollView.hasVerticalScroller  = true
        scrollView.autohidesScrollers   = true
        scrollView.borderType           = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Build the text view with an explicit container so it wraps + measures
        // correctly (a bare NSTextView() has a zero-width container -> empty box).
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 460, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(lm)
        lm.addTextContainer(container)
        textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable        = false
        textView.isSelectable      = true
        textView.drawsBackground   = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        super.init()

        effectView.onMouseEntered = { [weak self] in
            self?.mouseInsidePanel = true
            self?.cancelPendingDismiss()
        }
        effectView.onMouseExited = { [weak self] in
            self?.mouseInsidePanel = false
            self?.dismiss()
        }

        // Hide when the app loses focus (the panel floats above all apps).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }

        let border = CALayer()
        border.borderColor  = NSColor.separatorColor.cgColor
        border.borderWidth  = 0.5
        border.cornerRadius = 8
        border.frame        = effectView.bounds
        border.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        effectView.layer?.addSublayer(border)

        scrollView.documentView = textView
        effectView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: padding),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -padding),
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: padding),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -padding),
        ])
        panel.contentView = effectView
    }

    var isVisible: Bool { panel.isVisible }

    // No-op for empty content so we never flash an empty box.
    func show(markdown: String, anchorScreenRect: NSRect) {
        cancelPendingDismiss()
        let attributed = Self.render(markdown)
        guard attributed.length > 0 else { dismiss(); return }
        textView.textStorage?.setAttributedString(attributed)

        // Measure the rendered text to size the panel.
        let measureWidth = maxWidth - padding * 2
        guard let tc = textView.textContainer, let lm = textView.layoutManager else { return }
        tc.containerSize = NSSize(width: measureWidth, height: .greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: measureWidth, height: maxHeight)
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).size

        let contentW = min(measureWidth, max(120, ceil(used.width)))
        let contentH = min(maxHeight - padding * 2, max(16, ceil(used.height)))
        let panelW = contentW + padding * 2
        let panelH = contentH + padding * 2

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorScreenRect.origin) })
                     ?? NSScreen.main ?? NSScreen.screens[0]
        let vis = screen.visibleFrame

        let aboveY = anchorScreenRect.maxY + panelOffset
        let belowY = anchorScreenRect.minY - panelOffset - panelH
        let originX = max(vis.minX, min(anchorScreenRect.minX, vis.maxX - panelW))
        // Prefer above the symbol; fall back below if it would clip the top.
        let originY = (aboveY + panelH <= vis.maxY) ? aboveY : max(vis.minY, belowY)

        panel.setFrame(NSRect(x: originX, y: originY, width: panelW, height: panelH), display: true)
        panel.orderFront(nil)
    }

    func dismiss() {
        cancelPendingDismiss()
        mouseInsidePanel = false
        panel.orderOut(nil)
    }

    // Dismiss after a short delay unless the pointer reaches the panel first.
    func scheduleDismiss() {
        cancelPendingDismiss()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.mouseInsidePanel else { return }
            self.panel.orderOut(nil)
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay, execute: work)
    }

    private func cancelPendingDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    // Fenced code blocks render monospace; prose renders as inline markdown.
    private static func render(_ markdown: String) -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let mono = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let out = NSMutableAttributedString()

        var inFence = false
        let lines = markdown.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            // Horizontal rule between the diagnostic and docs sections: a full-
            // width line of box-drawing chars in a muted color.
            if !inFence, line.trimmingCharacters(in: .whitespaces) == "---" {
                let rule = String(repeating: "─", count: 80)
                let para = NSMutableParagraphStyle()
                para.lineBreakMode = .byClipping
                let hr = NSAttributedString(string: rule + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.separatorColor,
                    .paragraphStyle: para,
                ])
                out.append(hr)
                continue
            }
            let piece: NSAttributedString
            if inFence {
                piece = NSAttributedString(string: line, attributes: [
                    .font: mono, .foregroundColor: NSColor.labelColor,
                ])
            } else if let md = try? NSAttributedString(
                markdown: line,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                let m = NSMutableAttributedString(attributedString: md)
                let full = NSRange(location: 0, length: m.length)
                m.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
                m.enumerateAttribute(.font, in: full) { value, range, _ in
                    if value == nil { m.addAttribute(.font, value: body, range: range) }
                }
                piece = m
            } else {
                piece = NSAttributedString(string: line, attributes: [
                    .font: body, .foregroundColor: NSColor.labelColor,
                ])
            }
            out.append(piece)
            if i < lines.count - 1 { out.append(NSAttributedString(string: "\n")) }
        }
        return out
    }
}
