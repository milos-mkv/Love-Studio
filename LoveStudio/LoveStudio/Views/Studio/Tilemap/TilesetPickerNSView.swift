import AppKit

// MARK: - Tileset picker — supports single click and drag-rect multi-tile brush selection

final class TilesetPickerNSView: NSView {

    var tilesetImage: NSImage? = nil {
        didSet {
            cgImage = tilesetImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            recomputeGrid()
            invalidateIntrinsicContentSize()
            selStart = 0; selEnd = 0
            needsDisplay = true
        }
    }
    var tileSize: Int = 16 {
        didSet { recomputeGrid(); invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    // Primary selected tile (top-left of brush, for backwards compat)
    var selectedTile: Int {
        get { selStart }
        set { selStart = newValue; selEnd = newValue; needsDisplay = true }
    }

    /// Called with 2-D array of local tile indices (rows × cols) when selection changes
    var onSelectBrush: (([[Int]]) -> Void)?

    var scale: CGFloat = 2.0 {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    private var cgImage: CGImage?
    private var cols: Int = 1
    private var rows: Int = 1

    // Drag selection (flat indices)
    private var selStart: Int = 0
    private var selEnd:   Int = 0

    // Computed selection rect
    private var selMinCol: Int { min(selStart % cols, selEnd % cols) }
    private var selMaxCol: Int { max(selStart % cols, selEnd % cols) }
    private var selMinRow: Int { min(selStart / cols, selEnd / cols) }
    private var selMaxRow: Int { max(selStart / cols, selEnd / cols) }

    override var intrinsicContentSize: NSSize {
        guard let cg = cgImage else { return NSSize(width: 200, height: 200) }
        return NSSize(width: CGFloat(cg.width) * scale,
                      height: CGFloat(cg.height) * scale)
    }

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    private func recomputeGrid() {
        guard let cg = cgImage else { return }
        cols = max(1, Int(cg.width)  / max(1, tileSize))
        rows = max(1, Int(cg.height) / max(1, tileSize))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(bounds)

        guard let cg = cgImage else {
            ctx.setFillColor(NSColor.textBackgroundColor.cgColor)
            ctx.fill(bounds)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let s = "Load tileset image" as NSString
            let sz = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: bounds.midX - sz.width/2, y: bounds.midY - sz.height/2),
                   withAttributes: attrs)
            return
        }

        let ts   = CGFloat(tileSize) * scale
        let imgW = CGFloat(cg.width)  * scale
        let imgH = CGFloat(cg.height) * scale

        NSGraphicsContext.current?.imageInterpolation = .none
        tilesetImage?.draw(in: CGRect(x: 0, y: 0, width: imgW, height: imgH),
                           from: .zero, operation: .copy, fraction: 1.0)

        // Grid
        ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(0.5)
        for c in 0...cols {
            ctx.move(to: CGPoint(x: CGFloat(c) * ts, y: 0))
            ctx.addLine(to: CGPoint(x: CGFloat(c) * ts, y: imgH))
        }
        for r in 0...rows {
            ctx.move(to: CGPoint(x: 0,    y: CGFloat(r) * ts))
            ctx.addLine(to: CGPoint(x: imgW, y: CGFloat(r) * ts))
        }
        ctx.strokePath()

        // Selection highlight (supports multi-tile rect)
        let r0 = selMinRow; let r1 = selMaxRow
        let c0 = selMinCol; let c1 = selMaxCol
        let selX = CGFloat(c0) * ts
        let selY = imgH - CGFloat(r1 + 1) * ts
        let selW = CGFloat(c1 - c0 + 1) * ts
        let selH = CGFloat(r1 - r0 + 1) * ts

        ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.30).cgColor)
        ctx.fill(CGRect(x: selX, y: selY, width: selW, height: selH))
        ctx.setStrokeColor(NSColor.systemYellow.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(CGRect(x: selX + 0.75, y: selY + 0.75,
                          width: selW - 1.5, height: selH - 1.5))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        selStart = tile(for: event)
        selEnd   = selStart
        needsDisplay = true
        fireBrush()
    }

    override func mouseDragged(with event: NSEvent) {
        selEnd = tile(for: event)
        needsDisplay = true
        fireBrush()
    }

    private func tile(for event: NSEvent) -> Int {
        guard let cg = cgImage else { return 0 }
        let loc  = convert(event.locationInWindow, from: nil)
        let ts   = CGFloat(tileSize) * scale
        let imgH = CGFloat(cg.height) * scale
        let col  = max(0, min(cols - 1, Int(loc.x / ts)))
        let row  = max(0, min(rows - 1, Int((imgH - loc.y) / ts)))
        return row * cols + col
    }

    private func fireBrush() {
        var brush: [[Int]] = []
        for r in selMinRow...selMaxRow {
            var rowArr: [Int] = []
            for c in selMinCol...selMaxCol {
                rowArr.append(r * cols + c)
            }
            brush.append(rowArr)
        }
        onSelectBrush?(brush)
    }
}
