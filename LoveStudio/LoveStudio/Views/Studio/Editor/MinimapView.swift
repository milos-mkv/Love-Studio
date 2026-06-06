import AppKit

final class MinimapView: NSView {

    static let width: CGFloat = 80

    var onScrollFraction: ((CGFloat) -> Void)?

    var theme: LuaTheme = .dark {
        didSet {
            layer?.backgroundColor = theme.lineNumberBg.cgColor
            needsDisplay = true
        }
    }
    var lines: [NSAttributedString] = [] { didSet { needsDisplay = true } }
    var visibleFraction: CGFloat = 0 { didSet { needsDisplay = true } }
    var scrollFraction: CGFloat  = 0 { didSet { needsDisplay = true } }

    private let lineHeight: CGFloat = 2.0
    private let linePad:    CGFloat = 0.5

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = theme.lineNumberBg.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(theme.lineNumberBg.cgColor)
        ctx.fill(bounds)
        guard !lines.isEmpty else { return }

        let totalLinesHeight = CGFloat(lines.count) * (lineHeight + linePad)
        let scale = totalLinesHeight > bounds.height ? bounds.height / totalLinesHeight : 1.0
        // Actual content area height inside the minimap (may be less than bounds.height)
        let contentAreaH = min(totalLinesHeight * scale, bounds.height)
        let startY = bounds.height

        for (i, attrLine) in lines.enumerated() {
            let y = startY - CGFloat(i + 1) * (lineHeight + linePad) * scale
            let lineStr = attrLine.string
            let trimmed = lineStr.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let indent = lineStr.prefix(while: { $0 == " " || $0 == "\t" }).count
            let indentX = min(CGFloat(indent) * 1.5, bounds.width * 0.5)
            let contentLen = CGFloat(trimmed.count) * 2.0
            let maxW = bounds.width - indentX - 2
            let w = min(contentLen, maxW)
            guard w > 0 else { continue }
            let color = dominantColor(of: attrLine) ?? theme.lineNumber
            ctx.setFillColor(color.withAlphaComponent(0.75).cgColor)
            ctx.fill(CGRect(x: indentX + 2, y: y, width: w, height: lineHeight * scale))
        }

        // Viewport indicator is constrained to the content area, not the full minimap height
        let vpH = max(visibleFraction * contentAreaH, 4)
        let contentTop = bounds.height           // AppKit: high Y = screen top
        let contentBottom = contentTop - contentAreaH
        let vpY = contentBottom + (1.0 - scrollFraction) * (contentAreaH - vpH)
        ctx.setFillColor(theme.text.withAlphaComponent(0.07).cgColor)
        ctx.fill(CGRect(x: 0, y: vpY, width: bounds.width, height: vpH))
        ctx.setStrokeColor(theme.text.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(CGRect(x: 0, y: vpY, width: bounds.width, height: vpH))
    }

    override func mouseDown(with event: NSEvent) { scroll(with: event) }
    override func mouseDragged(with event: NSEvent) { scroll(with: event) }

    private func scroll(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let fraction = max(0, min(1, 1.0 - loc.y / bounds.height))
        onScrollFraction?(fraction)
    }

    private func dominantColor(of attr: NSAttributedString) -> NSColor? {
        let str = attr.string
        guard let idx = str.firstIndex(where: { !$0.isWhitespace }) else { return nil }
        let nsIdx = str.distance(from: str.startIndex, to: idx)
        guard nsIdx < attr.length else { return nil }
        return attr.attribute(.foregroundColor, at: nsIdx, effectiveRange: nil) as? NSColor
    }
}
