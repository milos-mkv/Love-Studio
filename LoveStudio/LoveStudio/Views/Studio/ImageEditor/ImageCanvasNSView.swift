import AppKit

// MARK: - Tool

enum ImageTool: String, CaseIterable, Identifiable {
    case pencil     = "Pencil"
    case eraser     = "Eraser"
    case fill       = "Fill"
    case eyedropper = "Eyedropper"
    case line       = "Line"
    case rectangle  = "Rectangle"
    case ellipse    = "Ellipse"
    case select     = "Select"
    case pan        = "Pan"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .pencil:     return "pencil"
        case .eraser:     return "eraser"
        case .fill:       return "drop.fill"
        case .eyedropper: return "eyedropper"
        case .line:       return "line.diagonal"
        case .rectangle:  return "rectangle"
        case .ellipse:    return "oval"
        case .select:     return "rectangle.dashed"
        case .pan:        return "hand.draw"
        }
    }
}

// MARK: - Canvas

final class ImageCanvasNSView: NSView {

    // MARK: - Public properties

    var tool: ImageTool = .pencil
    var drawColor: NSColor = .black
    var secondaryColor: NSColor = .white   // background / dither secondary
    var brushSize: Int = 1
    var showGrid: Bool = true      { didSet { needsDisplay = true } }
    var fillShapes: Bool = false
    var mirrorX: Bool = false
    var mirrorY: Bool = false
    var isDithering: Bool = false
    var zoom: CGFloat = 8.0        { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    // Feature 8: Frame grid overlay
    var showFrameGrid: Bool = false { didSet { needsDisplay = true } }
    var frameGridW: Int = 16        { didSet { needsDisplay = true } }
    var frameGridH: Int = 16        { didSet { needsDisplay = true } }

    var onChanged:     (() -> Void)?
    var onWillChange:  (() -> Void)?
    var onColorPicked: ((NSColor) -> Void)?
    var onCursorMoved: ((Int, Int)?) -> Void = { _ in }
    var onSelectionChanged: (((x:Int,y:Int,w:Int,h:Int)?) -> Void)?

    // Feature 4: Color at cursor callback
    var onColorAtCursor: ((NSColor?) -> Void)?

    // Feature 5: Zoom changed callback
    var onZoomChanged: ((CGFloat) -> Void)?

    // Layer change callback
    var onLayersChanged: (([ImageLayer], Int) -> Void)?

    // MARK: - Image dimensions

    private(set) var imgWidth:  Int = 0
    private(set) var imgHeight: Int = 0

    // MARK: - Layer system

    private(set) var layers: [ImageLayer] = []
    private(set) var activeLayerIndex: Int = 0

    // Composited cache — recomputed when any layer changes
    private var compositedCache: [UInt8] = []
    private var compositedDirty: Bool = true

    // Undo stack stores snapshots of all layers' pixel data
    private var undoStack: [[(UUID, [UInt8])]] = []
    private var redoStack: [[(UUID, [UInt8])]] = []

    // MARK: - Selection

    private var selRect: (x: Int, y: Int, w: Int, h: Int)? = nil {
        didSet { onSelectionChanged?(selRect) }
    }
    private var floatingPixels: [UInt8]? = nil
    private var floatingW: Int = 0
    private var floatingH: Int = 0
    private var floatingOffset: (Int, Int) = (0, 0)
    private var movingSelection: Bool = false
    private var moveDragStart: (Int, Int)? = nil
    private var moveSelOrigin: (Int, Int)? = nil

    // Paste clipboard (internal)
    private var clipboardPixels: [UInt8]? = nil
    private var clipboardW: Int = 0
    private var clipboardH: Int = 0

    // MARK: - Shape preview

    private var previewStart: (Int, Int)? = nil
    private var previewEnd:   (Int, Int)? = nil

    // MARK: - Cached checkerboard pattern (rebuilt only when zoom changes)

    private var checkerPattern: NSColor?
    private var checkerPatternZoom: CGFloat = 0

    // MARK: - Interaction state

    private var spaceDown = false
    private var panLastPoint: CGPoint?
    private var lastPixel: (Int, Int)?
    private var hoverPixel: (Int, Int)?

    // MARK: - Sizing

    private let padding: CGFloat = 40

    override var intrinsicContentSize: NSSize {
        NSSize(width:  CGFloat(imgWidth)  * zoom + padding * 2,
               height: CGFloat(imgHeight) * zoom + padding * 2)
    }

    private var canvasOffset: CGPoint {
        let cw = CGFloat(imgWidth)  * zoom
        let ch = CGFloat(imgHeight) * zoom
        return CGPoint(x: max(padding, (bounds.width  - cw) / 2),
                       y: max(padding, (bounds.height - ch) / 2))
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Compositing helpers

    private func invalidateComposite() {
        compositedDirty = true
        needsDisplay = true
    }

    private func recompositeIfNeeded() {
        guard compositedDirty, imgWidth > 0, imgHeight > 0 else { return }
        compositedCache = LayerCompositor.composite(layers: layers, width: imgWidth, height: imgHeight)
        compositedDirty = false
    }

    // MARK: - Active layer pixel access

    /// Returns pixelData of active layer, or nil if unavailable / locked
    private func activePixelData() -> [UInt8]? {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return nil }
        let layer = layers[activeLayerIndex]
        guard !layer.isLocked else { return nil }
        return layer.pixelData
    }

    private var isActiveLayerEditable: Bool {
        guard !layers.isEmpty, activeLayerIndex >= 0, activeLayerIndex < layers.count else { return false }
        return !layers[activeLayerIndex].isLocked
    }

    // MARK: - Public API

    func newImage(width: Int, height: Int, fill: NSColor = .clear) {
        imgWidth  = max(1, width)
        imgHeight = max(1, height)
        let bg = ImageLayer(name: "Background", width: imgWidth, height: imgHeight)
        if fill != .clear {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            (fill.usingColorSpace(.deviceRGB) ?? fill).getRed(&r, green: &g, blue: &b, alpha: &a)
            let fR = UInt8(min(255, r*255)), fG = UInt8(min(255, g*255))
            let fB = UInt8(min(255, b*255)), fA = UInt8(min(255, a*255))
            for i in 0 ..< imgWidth * imgHeight {
                let base = i * 4
                bg.pixelData[base] = fR; bg.pixelData[base+1] = fG
                bg.pixelData[base+2] = fB; bg.pixelData[base+3] = fA
            }
        }
        layers = [bg]
        activeLayerIndex = 0
        clearState()
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func loadCGImage(_ cg: CGImage) {
        imgWidth  = cg.width
        imgHeight = cg.height
        let layer = ImageLayer(name: "Layer 1", width: imgWidth, height: imgHeight)
        layer.pixelData = Array(repeating: 0, count: imgWidth * imgHeight * 4)
        layer.pixelData.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: base, width: imgWidth, height: imgHeight,
                                      bitsPerComponent: 8, bytesPerRow: imgWidth * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))
        }
        layers = [layer]
        activeLayerIndex = 0
        clearState()
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func loadLayers(_ newLayers: [ImageLayer], width: Int, height: Int) {
        imgWidth = width
        imgHeight = height
        layers = newLayers
        activeLayerIndex = 0
        clearState()
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func currentCGImage() -> CGImage? {
        guard imgWidth > 0, imgHeight > 0 else { return nil }
        // Composite only non-reference layers for export
        let exportLayers = layers.filter { !$0.isReference }
        var composite = LayerCompositor.composite(layers: exportLayers, width: imgWidth, height: imgHeight)
        // Composite floating pixels on active layer
        if let fp = floatingPixels {
            let (fx, fy) = floatingOffset
            for dy in 0 ..< floatingH {
                for dx in 0 ..< floatingW {
                    let sx = fx + dx, sy = fy + dy
                    guard sx >= 0, sx < imgWidth, sy >= 0, sy < imgHeight else { continue }
                    let si = (dy * floatingW + dx) * 4
                    let di = (sy * imgWidth + sx) * 4
                    let a = CGFloat(fp[si + 3]) / 255
                    if a > 0 {
                        composite[di]   = fp[si]; composite[di+1] = fp[si+1]
                        composite[di+2] = fp[si+2]; composite[di+3] = fp[si+3]
                    }
                }
            }
        }
        return composite.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let base = ptr.baseAddress else { return nil }
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: base, width: imgWidth, height: imgHeight,
                                      bitsPerComponent: 8, bytesPerRow: imgWidth * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
    }

    private func clearState() {
        undoStack = []; redoStack = []
        selRect = nil; floatingPixels = nil; movingSelection = false
        previewStart = nil; previewEnd = nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    // MARK: - Undo / Redo

    func pushUndo() {
        let snapshot = layers.map { ($0.id, $0.pixelData) }
        undoStack.append(snapshot)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        commitFloating()
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(layers.map { ($0.id, $0.pixelData) })
        restoreSnapshot(snapshot)
        onChanged?()
    }

    func redo() {
        commitFloating()
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(layers.map { ($0.id, $0.pixelData) })
        restoreSnapshot(snapshot)
        onChanged?()
    }

    private func restoreSnapshot(_ snapshot: [(UUID, [UInt8])]) {
        for (id, data) in snapshot {
            if let idx = layers.firstIndex(where: { $0.id == id }) {
                layers[idx].pixelData = data
            }
        }
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Layer management public API

    func addLayer(name: String = "New Layer") {
        let layer = ImageLayer(name: name, width: imgWidth, height: imgHeight)
        layers.insert(layer, at: activeLayerIndex + 1)
        activeLayerIndex = activeLayerIndex + 1
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func duplicateLayer() {
        guard activeLayerIndex < layers.count else { return }
        let dup = layers[activeLayerIndex].duplicate()
        layers.insert(dup, at: activeLayerIndex + 1)
        activeLayerIndex = activeLayerIndex + 1
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func deleteLayer() {
        guard layers.count > 1 else { return }
        layers.remove(at: activeLayerIndex)
        activeLayerIndex = max(0, activeLayerIndex - 1)
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func moveLayerUp() {
        guard activeLayerIndex < layers.count - 1 else { return }
        layers.swapAt(activeLayerIndex, activeLayerIndex + 1)
        activeLayerIndex += 1
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func moveLayerDown() {
        guard activeLayerIndex > 0 else { return }
        layers.swapAt(activeLayerIndex, activeLayerIndex - 1)
        activeLayerIndex -= 1
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func setActiveLayer(_ index: Int) {
        guard index >= 0, index < layers.count else { return }
        activeLayerIndex = index
        onLayersChanged?(layers, activeLayerIndex)
    }

    func mergeDown() {
        guard activeLayerIndex > 0, activeLayerIndex < layers.count else { return }
        pushUndo()
        let top = layers[activeLayerIndex]
        let bottom = layers[activeLayerIndex - 1]
        let merged = LayerCompositor.composite(layers: [bottom, top], width: imgWidth, height: imgHeight)
        layers[activeLayerIndex - 1].pixelData = merged
        layers[activeLayerIndex - 1].blendMode = .normal
        layers[activeLayerIndex - 1].opacity = 1.0
        layers.remove(at: activeLayerIndex)
        activeLayerIndex -= 1
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func flattenAll() {
        guard layers.count > 1 else { return }
        pushUndo()
        let flat = LayerCompositor.composite(layers: layers.filter { !$0.isReference }, width: imgWidth, height: imgHeight)
        let layer = ImageLayer(name: "Flattened", width: imgWidth, height: imgHeight)
        layer.pixelData = flat
        layers = [layer]
        activeLayerIndex = 0
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func setLayerVisible(_ index: Int, visible: Bool) {
        guard index < layers.count else { return }
        layers[index].visible = visible
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func setLayerOpacity(_ index: Int, opacity: Double) {
        guard index < layers.count else { return }
        layers[index].opacity = opacity
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func setLayerBlendMode(_ index: Int, blendMode: LayerBlendMode) {
        guard index < layers.count else { return }
        layers[index].blendMode = blendMode
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    func setLayerName(_ index: Int, name: String) {
        guard index < layers.count else { return }
        layers[index].name = name
        onLayersChanged?(layers, activeLayerIndex)
    }

    func setLayerLocked(_ index: Int, locked: Bool) {
        guard index < layers.count else { return }
        layers[index].isLocked = locked
        onLayersChanged?(layers, activeLayerIndex)
    }

    func setLayerReference(_ index: Int, isReference: Bool) {
        guard index < layers.count else { return }
        layers[index].isReference = isReference
        invalidateComposite()
        onLayersChanged?(layers, activeLayerIndex)
    }

    // MARK: - Pixel access (operates on active layer)

    private func idx(_ x: Int, _ y: Int) -> Int { (y * imgWidth + x) * 4 }

    private func writePixelRaw(_ flat: Int, _ color: NSColor) {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        let layer = layers[activeLayerIndex]
        guard !layer.isLocked else { return }
        let i = flat * 4
        guard i + 3 < layer.pixelData.count else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (color.usingColorSpace(.deviceRGB) ?? color).getRed(&r, green: &g, blue: &b, alpha: &a)
        layers[activeLayerIndex].pixelData[i]   = UInt8(min(255, r*255))
        layers[activeLayerIndex].pixelData[i+1] = UInt8(min(255, g*255))
        layers[activeLayerIndex].pixelData[i+2] = UInt8(min(255, b*255))
        layers[activeLayerIndex].pixelData[i+3] = UInt8(min(255, a*255))
    }

    func setPixel(x: Int, y: Int, color: NSColor) {
        guard x >= 0, x < imgWidth, y >= 0, y < imgHeight else { return }
        writePixelRaw(y * imgWidth + x, color)
    }

    func getPixelColor(x: Int, y: Int) -> NSColor {
        guard x >= 0, x < imgWidth, y >= 0, y < imgHeight else { return .clear }
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return .clear }
        let pixelData = layers[activeLayerIndex].pixelData
        let i = idx(x, y)
        guard i + 3 < pixelData.count else { return .clear }
        return NSColor(red: CGFloat(pixelData[i])/255, green: CGFloat(pixelData[i+1])/255,
                       blue: CGFloat(pixelData[i+2])/255, alpha: CGFloat(pixelData[i+3])/255)
    }

    private func pixelRaw(_ x: Int, _ y: Int) -> (UInt8,UInt8,UInt8,UInt8) {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return (0,0,0,0) }
        let pixelData = layers[activeLayerIndex].pixelData
        let i = idx(x, y)
        guard i + 3 < pixelData.count else { return (0,0,0,0) }
        return (pixelData[i], pixelData[i+1], pixelData[i+2], pixelData[i+3])
    }

    // MARK: - Feature 4: Color at pixel (reads from composited cache)

    private func colorAt(pixel: (Int, Int)) -> NSColor? {
        recompositeIfNeeded()
        let x = pixel.0, y = pixel.1
        guard x >= 0, x < imgWidth, y >= 0, y < imgHeight,
              !compositedCache.isEmpty else { return nil }
        let i = (y * imgWidth + x) * 4
        guard i + 3 < compositedCache.count else { return nil }
        let r = CGFloat(compositedCache[i])   / 255
        let g = CGFloat(compositedCache[i+1]) / 255
        let b = CGFloat(compositedCache[i+2]) / 255
        let a = CGFloat(compositedCache[i+3]) / 255
        return NSColor(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Drawing primitives

    private func paintAt(x: Int, y: Int, erase: Bool = false) {
        let half = brushSize / 2
        for dy in 0 ..< brushSize {
            for dx in 0 ..< brushSize {
                let px = x - half + dx, py = y - half + dy
                let color = paintColor(px: px, py: py, erase: erase)
                setPixel(x: px, y: py, color: color)
                if mirrorX {
                    let mx = imgWidth - 1 - (x - half + dx)
                    setPixel(x: mx, y: py, color: paintColor(px: mx, py: py, erase: erase))
                }
                if mirrorY {
                    let my = imgHeight - 1 - (y - half + dy)
                    setPixel(x: px, y: my, color: paintColor(px: px, py: my, erase: erase))
                    if mirrorX {
                        let mx = imgWidth - 1 - (x - half + dx)
                        setPixel(x: mx, y: my, color: paintColor(px: mx, py: my, erase: erase))
                    }
                }
            }
        }
        invalidateComposite()
    }

    /// Returns the color to paint at pixel (px, py), respecting dithering mode.
    private func paintColor(px: Int, py: Int, erase: Bool) -> NSColor {
        if erase { return .clear }
        if isDithering { return (px + py) % 2 == 0 ? drawColor : secondaryColor }
        return drawColor
    }

    private func drawLine(from p0:(Int,Int), to p1:(Int,Int), erase: Bool = false) {
        var (x0,y0) = p0; let (x1,y1) = p1
        let dx = abs(x1-x0), dy = abs(y1-y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx - dy
        while true {
            paintAt(x: x0, y: y0, erase: erase)
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 > -dy { err -= dy; x0 += sx }
            if e2 <  dx { err += dx; y0 += sy }
        }
    }

    private func drawRect(x0: Int, y0: Int, x1: Int, y1: Int) {
        let minX = min(x0,x1), maxX = max(x0,x1)
        let minY = min(y0,y1), maxY = max(y0,y1)
        if fillShapes {
            for y in minY...maxY { for x in minX...maxX { setPixel(x:x, y:y, color:drawColor) } }
        } else {
            for x in minX...maxX { setPixel(x:x, y:minY, color:drawColor); setPixel(x:x, y:maxY, color:drawColor) }
            for y in minY...maxY { setPixel(x:minX, y:y, color:drawColor); setPixel(x:maxX, y:y, color:drawColor) }
        }
        invalidateComposite()
    }

    private func drawEllipse(x0: Int, y0: Int, x1: Int, y1: Int) {
        let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
        let rx = abs(x1 - x0) / 2, ry = abs(y1 - y0) / 2
        guard rx > 0 || ry > 0 else { setPixel(x: cx, y: cy, color: drawColor); invalidateComposite(); return }
        if fillShapes {
            for y in max(0, cy-ry) ... min(imgHeight-1, cy+ry) {
                let dy = y - cy
                let dxf = rx > 0 && ry > 0 ? Double(rx) * sqrt(max(0, 1 - Double(dy*dy)/Double(ry*ry))) : Double(rx)
                let dx = Int(dxf)
                for x in max(0, cx-dx) ... min(imgWidth-1, cx+dx) { setPixel(x:x, y:y, color:drawColor) }
            }
        } else {
            var x = 0, y = ry
            var d1 = Double(ry*ry) - Double(rx*rx*ry) + 0.25*Double(rx*rx)
            var dx2 = 2*ry*ry*x, dy2 = 2*rx*rx*y
            while dx2 < dy2 {
                plotEllipsePoints(cx:cx,cy:cy,x:x,y:y)
                if d1 < 0 { x+=1; dx2 += 2*ry*ry; d1 += Double(dx2) + Double(ry*ry) }
                else       { x+=1; y-=1; dx2 += 2*ry*ry; dy2 -= 2*rx*rx; d1 += Double(dx2) - Double(dy2) + Double(ry*ry) }
            }
            var d2 = Double(ry*ry)*Double((x*x)) + Double(rx*rx)*Double(((y-1)*(y-1))) - Double(rx*rx*ry*ry)
            while y >= 0 {
                plotEllipsePoints(cx:cx,cy:cy,x:x,y:y)
                if d2 > 0 { y-=1; dy2 -= 2*rx*rx; d2 += Double(rx*rx) - Double(dy2) }
                else       { y-=1; x+=1; dx2 += 2*ry*ry; dy2 -= 2*rx*rx; d2 += Double(dx2) - Double(dy2) + Double(rx*rx) }
            }
        }
        invalidateComposite()
    }

    private func plotEllipsePoints(cx:Int,cy:Int,x:Int,y:Int) {
        setPixel(x:cx+x,y:cy+y,color:drawColor); setPixel(x:cx-x,y:cy+y,color:drawColor)
        setPixel(x:cx+x,y:cy-y,color:drawColor); setPixel(x:cx-x,y:cy-y,color:drawColor)
    }

    private func floodFill(x: Int, y: Int) {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        guard !layers[activeLayerIndex].isLocked else { return }
        let target = pixelRaw(x, y)
        var fr: CGFloat=0, fg: CGFloat=0, fb: CGFloat=0, fa: CGFloat=0
        (drawColor.usingColorSpace(.deviceRGB) ?? drawColor).getRed(&fr, green:&fg, blue:&fb, alpha:&fa)
        let fR=UInt8(min(255,fr*255)), fG=UInt8(min(255,fg*255))
        let fB=UInt8(min(255,fb*255)), fA=UInt8(min(255,fa*255))
        if target == (fR,fG,fB,fA) { return }
        var stack = [(x,y)]
        while !stack.isEmpty {
            let (cx,cy) = stack.removeLast()
            guard cx>=0,cx<imgWidth,cy>=0,cy<imgHeight else { continue }
            guard pixelRaw(cx,cy) == target else { continue }
            let i = idx(cx,cy)
            guard i + 3 < layers[activeLayerIndex].pixelData.count else { continue }
            layers[activeLayerIndex].pixelData[i]=fR
            layers[activeLayerIndex].pixelData[i+1]=fG
            layers[activeLayerIndex].pixelData[i+2]=fB
            layers[activeLayerIndex].pixelData[i+3]=fA
            stack.append((cx+1,cy)); stack.append((cx-1,cy))
            stack.append((cx,cy+1)); stack.append((cx,cy-1))
        }
        invalidateComposite()
    }

    // MARK: - Bulk operations

    func flipHorizontal() {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        guard isActiveLayerEditable else { return }
        pushUndo()
        let pixelData = layers[activeLayerIndex].pixelData
        var newData = Array(repeating: UInt8(0), count: pixelData.count)
        for y in 0..<imgHeight {
            for x in 0..<imgWidth {
                let si = (y*imgWidth+x)*4, di = (y*imgWidth+(imgWidth-1-x))*4
                for c in 0..<4 { newData[di+c] = pixelData[si+c] }
            }
        }
        layers[activeLayerIndex].pixelData = newData
        invalidateComposite()
        needsDisplay = true; onChanged?()
    }

    func flipVertical() {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        guard isActiveLayerEditable else { return }
        pushUndo()
        let pixelData = layers[activeLayerIndex].pixelData
        var newData = Array(repeating: UInt8(0), count: pixelData.count)
        for y in 0..<imgHeight {
            for x in 0..<imgWidth {
                let si = (y*imgWidth+x)*4, di = ((imgHeight-1-y)*imgWidth+x)*4
                for c in 0..<4 { newData[di+c] = pixelData[si+c] }
            }
        }
        layers[activeLayerIndex].pixelData = newData
        invalidateComposite()
        needsDisplay = true; onChanged?()
    }

    func rotate90CW() {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        guard isActiveLayerEditable else { return }
        pushUndo()
        let pixelData = layers[activeLayerIndex].pixelData
        let newW = imgHeight, newH = imgWidth
        var newData = Array(repeating: UInt8(0), count: newW*newH*4)
        for y in 0..<imgHeight {
            for x in 0..<imgWidth {
                let si = (y*imgWidth+x)*4
                let nx = imgHeight-1-y, ny = x
                let di = (ny*newW+nx)*4
                for c in 0..<4 { newData[di+c] = pixelData[si+c] }
            }
        }
        layers[activeLayerIndex].pixelData = newData
        imgWidth = newW; imgHeight = newH
        invalidateComposite()
        invalidateIntrinsicContentSize(); needsDisplay = true; onChanged?()
    }

    func rotate90CCW() {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        guard isActiveLayerEditable else { return }
        pushUndo()
        let pixelData = layers[activeLayerIndex].pixelData
        let newW = imgHeight, newH = imgWidth
        var newData = Array(repeating: UInt8(0), count: newW*newH*4)
        for y in 0..<imgHeight {
            for x in 0..<imgWidth {
                let si = (y*imgWidth+x)*4
                let nx = y, ny = imgWidth-1-x
                let di = (ny*newW+nx)*4
                for c in 0..<4 { newData[di+c] = pixelData[si+c] }
            }
        }
        layers[activeLayerIndex].pixelData = newData
        imgWidth = newW; imgHeight = newH
        invalidateComposite()
        invalidateIntrinsicContentSize(); needsDisplay = true; onChanged?()
    }

    func resize(newWidth: Int, newHeight: Int) {
        guard newWidth > 0, newHeight > 0 else { return }
        guard !layers.isEmpty else { return }
        pushUndo()
        // Resize all layers
        for i in 0..<layers.count {
            let pixelData = layers[i].pixelData
            var newData = Array(repeating: UInt8(0), count: newWidth*newHeight*4)
            for y in 0..<newHeight {
                for x in 0..<newWidth {
                    let sx = min(imgWidth-1,  Int(Double(x) / Double(newWidth)  * Double(imgWidth)))
                    let sy = min(imgHeight-1, Int(Double(y) / Double(newHeight) * Double(imgHeight)))
                    let si = (sy*imgWidth+sx)*4, di = (y*newWidth+x)*4
                    for c in 0..<4 { newData[di+c] = pixelData[si+c] }
                }
            }
            layers[i].pixelData = newData
        }
        imgWidth = newWidth; imgHeight = newHeight
        invalidateComposite()
        invalidateIntrinsicContentSize(); needsDisplay = true; onChanged?()
    }

    // MARK: - Outline tool
    func addOutline(outlineColor: NSColor) {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        guard isActiveLayerEditable else { return }
        pushUndo()
        let pixelData = layers[activeLayerIndex].pixelData
        var toFill: [Int] = []
        for y in 0..<imgHeight {
            for x in 0..<imgWidth {
                guard pixelData[idx(x,y)+3] == 0 else { continue }
                let neighbors = [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]
                for (nx,ny) in neighbors {
                    guard nx >= 0, nx < imgWidth, ny >= 0, ny < imgHeight else { continue }
                    if pixelData[idx(nx,ny)+3] > 0 { toFill.append(y*imgWidth+x); break }
                }
            }
        }
        for flat in toFill { writePixelRaw(flat, outlineColor) }
        invalidateComposite()
        needsDisplay = true; onChanged?()
    }

    // MARK: - Color replace
    func replaceColor(from fromColor: NSColor, to toColor: NSColor, tolerance: Int = 0) {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        guard isActiveLayerEditable else { return }
        pushUndo()
        var fr: CGFloat=0, fg: CGFloat=0, fb: CGFloat=0, fa: CGFloat=0
        (fromColor.usingColorSpace(.deviceRGB) ?? fromColor).getRed(&fr, green:&fg, blue:&fb, alpha:&fa)
        let fR=Int(fr*255), fG=Int(fg*255), fB=Int(fb*255), fA=Int(fa*255)
        let pixelData = layers[activeLayerIndex].pixelData
        let count = imgWidth * imgHeight
        for i in 0..<count {
            let base = i * 4
            guard base + 3 < pixelData.count else { continue }
            let r=Int(pixelData[base]), g=Int(pixelData[base+1])
            let b=Int(pixelData[base+2]), a=Int(pixelData[base+3])
            if abs(r-fR) <= tolerance && abs(g-fG) <= tolerance &&
               abs(b-fB) <= tolerance && abs(a-fA) <= tolerance {
                writePixelRaw(i, toColor)
            }
        }
        invalidateComposite()
        needsDisplay = true; onChanged?()
    }

    // MARK: - Selection operations

    func copySelection() {
        guard let sel = selRect else { return }
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        let pixelData = layers[activeLayerIndex].pixelData
        clipboardW = sel.w; clipboardH = sel.h
        clipboardPixels = Array(repeating: 0, count: sel.w * sel.h * 4)
        for dy in 0..<sel.h {
            for dx in 0..<sel.w {
                let sx = sel.x+dx, sy = sel.y+dy
                guard sx>=0,sx<imgWidth,sy>=0,sy<imgHeight else { continue }
                let si = (sy*imgWidth+sx)*4, di = (dy*sel.w+dx)*4
                guard di+3 < clipboardPixels!.count, si+3 < pixelData.count else { continue }
                for c in 0..<4 { clipboardPixels![di+c] = pixelData[si+c] }
            }
        }
    }

    func pasteClipboard() {
        guard let cp = clipboardPixels else { return }
        guard isActiveLayerEditable else { return }
        commitFloating()
        pushUndo()
        floatingPixels = cp
        floatingW = clipboardW; floatingH = clipboardH
        floatingOffset = (0, 0)
        selRect = (x:0, y:0, w:clipboardW, h:clipboardH)
        needsDisplay = true
    }

    func deleteSelection() {
        guard let sel = selRect else { return }
        guard isActiveLayerEditable else { return }
        pushUndo()
        for dy in 0..<sel.h {
            for dx in 0..<sel.w { setPixel(x:sel.x+dx, y:sel.y+dy, color:.clear) }
        }
        invalidateComposite()
        selRect = nil; needsDisplay = true; onChanged?()
    }

    func deselect() {
        commitFloating()
        selRect = nil; needsDisplay = true
    }

    func flipSelectionHorizontal() {
        guard let sel = selRect else { return }
        guard isActiveLayerEditable || floatingPixels != nil else { return }
        if floatingPixels == nil { pushUndo(); liftSelection(sel) }
        guard let fp = floatingPixels else { return }
        var newFP = Array(repeating: UInt8(0), count: floatingW * floatingH * 4)
        for y in 0..<floatingH {
            for x in 0..<floatingW {
                let si = (y * floatingW + x) * 4
                let di = (y * floatingW + (floatingW - 1 - x)) * 4
                for c in 0..<4 { newFP[di+c] = fp[si+c] }
            }
        }
        floatingPixels = newFP; needsDisplay = true
    }

    func flipSelectionVertical() {
        guard let sel = selRect else { return }
        guard isActiveLayerEditable || floatingPixels != nil else { return }
        if floatingPixels == nil { pushUndo(); liftSelection(sel) }
        guard let fp = floatingPixels else { return }
        var newFP = Array(repeating: UInt8(0), count: floatingW * floatingH * 4)
        for y in 0..<floatingH {
            for x in 0..<floatingW {
                let si = (y * floatingW + x) * 4
                let di = ((floatingH - 1 - y) * floatingW + x) * 4
                for c in 0..<4 { newFP[di+c] = fp[si+c] }
            }
        }
        floatingPixels = newFP; needsDisplay = true
    }

    func rotateSelection90CW() {
        guard let sel = selRect else { return }
        guard isActiveLayerEditable || floatingPixels != nil else { return }
        if floatingPixels == nil { pushUndo(); liftSelection(sel) }
        guard let fp = floatingPixels else { return }
        let newW = floatingH, newH = floatingW
        var newFP = Array(repeating: UInt8(0), count: newW * newH * 4)
        for y in 0..<floatingH {
            for x in 0..<floatingW {
                let si = (y * floatingW + x) * 4
                let nx = floatingH - 1 - y, ny = x
                let di = (ny * newW + nx) * 4
                for c in 0..<4 { newFP[di+c] = fp[si+c] }
            }
        }
        floatingPixels = newFP; floatingW = newW; floatingH = newH
        if var s = selRect { s.w = newW; s.h = newH; selRect = s }
        needsDisplay = true
    }

    private func commitFloating() {
        guard let fp = floatingPixels else { return }
        guard isActiveLayerEditable else { return }
        let (fx,fy) = floatingOffset
        for dy in 0..<floatingH {
            for dx in 0..<floatingW {
                let tx = fx+dx, ty = fy+dy
                guard tx>=0,tx<imgWidth,ty>=0,ty<imgHeight else { continue }
                let si = (dy*floatingW+dx)*4
                let a = CGFloat(fp[si+3])/255
                if a > 0 { writePixelRaw(ty*imgWidth+tx, NSColor(
                    red: CGFloat(fp[si])/255, green: CGFloat(fp[si+1])/255,
                    blue: CGFloat(fp[si+2])/255, alpha: a)) }
            }
        }
        floatingPixels = nil; movingSelection = false
        invalidateComposite()
    }

    private func liftSelection(_ sel: (x:Int,y:Int,w:Int,h:Int)) {
        guard !layers.isEmpty, activeLayerIndex < layers.count else { return }
        guard isActiveLayerEditable else { return }
        let pixelData = layers[activeLayerIndex].pixelData
        floatingW = sel.w; floatingH = sel.h
        floatingPixels = Array(repeating: 0, count: sel.w*sel.h*4)
        for dy in 0..<sel.h {
            for dx in 0..<sel.w {
                let sx=sel.x+dx, sy=sel.y+dy
                guard sx>=0,sx<imgWidth,sy>=0,sy<imgHeight else { continue }
                let si=(sy*imgWidth+sx)*4, di=(dy*sel.w+dx)*4
                guard di+3 < floatingPixels!.count, si+3 < pixelData.count else { continue }
                for c in 0..<4 { floatingPixels![di+c] = pixelData[si+c] }
                writePixelRaw(sy*imgWidth+sx, .clear)
            }
        }
        floatingOffset = (sel.x, sel.y)
        invalidateComposite()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor(calibratedWhite: 0.18, alpha: 1).cgColor)
        ctx.fill(bounds)
        guard imgWidth > 0, imgHeight > 0 else { return }

        let off = canvasOffset
        ctx.saveGState()
        ctx.translateBy(x: off.x, y: off.y)

        let cw = CGFloat(imgWidth)*zoom, ch = CGFloat(imgHeight)*zoom

        // Transparent background — solid dark fill
        ctx.setFillColor(NSColor(calibratedWhite: 0.22, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))

        // Image — use composited cache
        recompositeIfNeeded()
        // Build display image from composited cache + floating pixels
        var displayData = compositedCache
        if !displayData.isEmpty, let fp = floatingPixels {
            let (fx, fy) = floatingOffset
            for dy in 0 ..< floatingH {
                for dx in 0 ..< floatingW {
                    let sx = fx + dx, sy = fy + dy
                    guard sx >= 0, sx < imgWidth, sy >= 0, sy < imgHeight else { continue }
                    let si = (dy * floatingW + dx) * 4
                    let di = (sy * imgWidth + sx) * 4
                    let a = CGFloat(fp[si + 3]) / 255
                    if a > 0 {
                        displayData[di]   = fp[si]; displayData[di+1] = fp[si+1]
                        displayData[di+2] = fp[si+2]; displayData[di+3] = fp[si+3]
                    }
                }
            }
        }
        if !displayData.isEmpty {
            displayData.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                let cs = CGColorSpaceCreateDeviceRGB()
                guard let bitmapCtx = CGContext(data: base, width: imgWidth, height: imgHeight,
                                               bitsPerComponent: 8, bytesPerRow: imgWidth * 4, space: cs,
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                      let cg = bitmapCtx.makeImage()
                else { return }
                ctx.interpolationQuality = .none
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cw, height: ch))
            }
        }

        // Shape preview overlay
        if let start = previewStart, let end = previewEnd {
            drawShapePreview(ctx: ctx, start: start, end: end)
        }

        // Pencil hover preview
        if tool == .pencil, let hover = hoverPixel {
            drawBrushHoverPreview(ctx: ctx, center: hover)
        }

        // Grid
        if showGrid && zoom >= 3 {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.18).cgColor)
            ctx.setLineWidth(0.5)
            for x in 0...imgWidth {
                ctx.move(to: CGPoint(x:CGFloat(x)*zoom,y:0))
                ctx.addLine(to: CGPoint(x:CGFloat(x)*zoom,y:ch))
            }
            for y in 0...imgHeight {
                ctx.move(to: CGPoint(x:0,y:CGFloat(y)*zoom))
                ctx.addLine(to: CGPoint(x:cw,y:CGFloat(y)*zoom))
            }
            ctx.strokePath()
        }

        // Feature 8: Frame grid overlay
        if showFrameGrid && frameGridW > 0 && frameGridH > 0 {
            ctx.setStrokeColor(NSColor.systemPurple.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(1.0)
            ctx.setLineDash(phase: 0, lengths: [4, 2])
            var fx = 0
            while fx <= imgWidth {
                let sx = CGFloat(fx) * zoom
                ctx.move(to: CGPoint(x: sx, y: 0))
                ctx.addLine(to: CGPoint(x: sx, y: ch))
                fx += frameGridW
            }
            var fy = 0
            while fy <= imgHeight {
                let sy = CGFloat(fy) * zoom
                ctx.move(to: CGPoint(x: 0, y: sy))
                ctx.addLine(to: CGPoint(x: cw, y: sy))
                fy += frameGridH
            }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        // Mirror guides
        if mirrorX {
            ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1); ctx.setLineDash(phase:0,lengths:[4,3])
            let mx = cw/2
            ctx.move(to:CGPoint(x:mx,y:0)); ctx.addLine(to:CGPoint(x:mx,y:ch))
            ctx.strokePath(); ctx.setLineDash(phase:0,lengths:[])
        }
        if mirrorY {
            ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1); ctx.setLineDash(phase:0,lengths:[4,3])
            let my = ch/2
            ctx.move(to:CGPoint(x:0,y:my)); ctx.addLine(to:CGPoint(x:cw,y:my))
            ctx.strokePath(); ctx.setLineDash(phase:0,lengths:[])
        }

        // Selection rect
        if let sel = selRect {
            let sr = CGRect(x:CGFloat(sel.x)*zoom,
                            y:CGFloat(imgHeight-sel.y-sel.h)*zoom,
                            width:CGFloat(sel.w)*zoom,
                            height:CGFloat(sel.h)*zoom)
            ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.12).cgColor)
            ctx.fill(sr)
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5); ctx.setLineDash(phase:0,lengths:[4,3])
            ctx.stroke(sr.insetBy(dx:0.75,dy:0.75))
            ctx.setLineDash(phase:0,lengths:[])
        }

        // Border
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x:0,y:0,width:cw,height:ch))

        ctx.restoreGState()
    }

    // MARK: - Rulers

    private func drawRulers(ctx: CGContext, off: CGPoint, cw: CGFloat, ch: CGFloat) {
        guard imgWidth > 0, imgHeight > 0 else { return }

        let rulerH: CGFloat = 20
        let rulerW: CGFloat = 28
        let tickInterval = rulerTickInterval()

        ctx.saveGState()

        let labelFont = CTFontCreateWithName("Menlo" as CFString, 8, nil)
        let labelAttrs: [CFString: Any] = [
            kCTFontAttributeName: labelFont,
            kCTForegroundColorAttributeName: NSColor.white.withAlphaComponent(0.55).cgColor
        ]

        // Horizontal ruler above canvas (high y in NSView coords = top of screen)
        let hRulerY = off.y + ch  // top edge of canvas in view coords
        ctx.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.85).cgColor)
        ctx.fill(CGRect(x: off.x, y: hRulerY, width: cw, height: rulerH))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(0.5)

        var px = 0
        while px <= imgWidth {
            let screenX = off.x + CGFloat(px) * zoom
            let isMajor = px % (tickInterval * 4) == 0
            let tickHeight: CGFloat = isMajor ? 8 : (px % tickInterval == 0 ? 5 : 3)
            ctx.move(to: CGPoint(x: screenX, y: hRulerY))
            ctx.addLine(to: CGPoint(x: screenX, y: hRulerY + tickHeight))
            if isMajor && px > 0 {
                drawRulerLabel("\(px)", x: screenX + 2, y: hRulerY + 2, attrs: labelAttrs, ctx: ctx)
            }
            px += max(1, tickInterval)
        }
        ctx.strokePath()

        // Vertical ruler left of canvas
        let vRulerX = off.x - rulerW
        ctx.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.85).cgColor)
        ctx.fill(CGRect(x: vRulerX, y: off.y, width: rulerW, height: ch))

        var py = 0
        while py <= imgHeight {
            let screenY = off.y + CGFloat(imgHeight - py) * zoom
            let isMajor = py % (tickInterval * 4) == 0
            let tickWidth: CGFloat = isMajor ? 8 : (py % tickInterval == 0 ? 5 : 3)
            ctx.move(to: CGPoint(x: off.x, y: screenY))
            ctx.addLine(to: CGPoint(x: off.x - tickWidth, y: screenY))
            if isMajor && py > 0 {
                drawRulerLabel("\(py)", x: vRulerX + 2, y: screenY + 2, attrs: labelAttrs, ctx: ctx)
            }
            py += max(1, tickInterval)
        }
        ctx.strokePath()

        ctx.restoreGState()
    }

    private func rulerTickInterval() -> Int {
        switch zoom {
        case ..<2:  return 32
        case ..<4:  return 16
        case ..<8:  return 8
        case ..<16: return 4
        default:    return 2
        }
    }

    private func drawRulerLabel(_ text: String, x: CGFloat, y: CGFloat,
                                  attrs: [CFString: Any], ctx: CGContext) {
        let attrStr = CFAttributedStringCreate(nil, text as CFString,
                                               attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrStr)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: 1)
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private func drawShapePreview(ctx: CGContext, start: (Int,Int), end: (Int,Int)) {
        let x0=start.0, y0=start.1, x1=end.0, y1=end.1
        var r: CGFloat=0, g: CGFloat=0, b: CGFloat=0, a: CGFloat=0
        (drawColor.usingColorSpace(.deviceRGB) ?? drawColor).getRed(&r,green:&g,blue:&b,alpha:&a)
        ctx.setFillColor(CGColor(red:r,green:g,blue:b,alpha:a*0.85))

        func sq(_ px:Int,_ py:Int) {
            let sy = imgHeight-1-py
            ctx.fill(CGRect(x:CGFloat(px)*zoom,y:CGFloat(sy)*zoom,width:zoom,height:zoom))
        }

        switch tool {
        case .line:
            var (lx,ly)=(x0,y0)
            let dx=abs(x1-x0),dy=abs(y1-y0)
            let sx=lx<x1 ? 1 : -1, sy2=ly<y1 ? 1 : -1
            var err=dx-dy
            while true {
                sq(lx,ly)
                if lx==x1&&ly==y1{break}
                let e2=2*err
                if e2 > -dy{err-=dy;lx+=sx}
                if e2<dx{err+=dx;ly+=sy2}
            }
        case .rectangle:
            let minX=min(x0,x1),maxX=max(x0,x1),minY=min(y0,y1),maxY=max(y0,y1)
            if fillShapes {
                ctx.fill(CGRect(x:CGFloat(minX)*zoom,
                                y:CGFloat(imgHeight-maxY-1)*zoom,
                                width:CGFloat(maxX-minX+1)*zoom,
                                height:CGFloat(maxY-minY+1)*zoom))
            } else {
                for x in minX...maxX { sq(x,minY); sq(x,maxY) }
                for y in minY...maxY { sq(minX,y); sq(maxX,y) }
            }
        case .ellipse:
            let cx=(x0+x1)/2, cy=(y0+y1)/2
            let rx=abs(x1-x0)/2, ry=abs(y1-y0)/2
            if fillShapes {
                for y in (cy-ry)...(cy+ry) {
                    let dy=y-cy
                    let dxf = rx>0&&ry>0 ? Double(rx)*sqrt(max(0,1-Double(dy*dy)/Double(max(1,ry*ry)))) : Double(rx)
                    let dx=Int(dxf)
                    for x in (cx-dx)...(cx+dx) { sq(x,y) }
                }
            } else {
                func ep(_ x:Int,_ y:Int){sq(cx+x,cy+y);sq(cx-x,cy+y);sq(cx+x,cy-y);sq(cx-x,cy-y)}
                var ex=0,ey=ry
                var d1=Double(ry*ry)-Double(rx*rx*ry)+0.25*Double(rx*rx)
                var ddx=2*ry*ry*ex,ddy=2*rx*rx*ey
                while ddx<ddy{ep(ex,ey);if d1<0{ex+=1;ddx+=2*ry*ry;d1+=Double(ddx)+Double(ry*ry)}else{ex+=1;ey-=1;ddx+=2*ry*ry;ddy-=2*rx*rx;d1+=Double(ddx)-Double(ddy)+Double(ry*ry)}}
                var d2=Double(ry*ry)*Double(ex*ex)+Double(rx*rx)*Double((ey-1)*(ey-1))-Double(rx*rx*ry*ry)
                while ey>=0{ep(ex,ey);if d2>0{ey-=1;ddy-=2*rx*rx;d2+=Double(rx*rx)-Double(ddy)}else{ey-=1;ex+=1;ddx+=2*ry*ry;ddy-=2*rx*rx;d2+=Double(ddx)-Double(ddy)+Double(rx*rx)}}
            }
        default: break
        }
    }

    private func drawBrushHoverPreview(ctx: CGContext, center: (Int, Int)) {
        let pixels = affectedPixels(for: center)
        guard !pixels.isEmpty else { return }

        ctx.saveGState()
        for (px, py) in pixels {
            let sy = imgHeight - 1 - py
            let rect = CGRect(x: CGFloat(px) * zoom, y: CGFloat(sy) * zoom, width: zoom, height: zoom)
            let previewColor = paintColor(px: px, py: py, erase: false).withAlphaComponent(0.35)
            ctx.setFillColor(previewColor.cgColor)
            ctx.fill(rect)

            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(max(0.75, min(1.5, zoom * 0.12)))
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        }
        ctx.restoreGState()
    }

    private func affectedPixels(for center: (Int, Int)) -> [(Int, Int)] {
        guard imgWidth > 0, imgHeight > 0 else { return [] }

        var seen = Set<Int>()
        var pixels: [(Int, Int)] = []
        let half = brushSize / 2

        func appendPixel(_ x: Int, _ y: Int) {
            guard x >= 0, x < imgWidth, y >= 0, y < imgHeight else { return }
            let key = y * imgWidth + x
            guard seen.insert(key).inserted else { return }
            pixels.append((x, y))
        }

        for dy in 0..<brushSize {
            for dx in 0..<brushSize {
                let px = center.0 - half + dx
                let py = center.1 - half + dy
                appendPixel(px, py)

                if mirrorX {
                    appendPixel(imgWidth - 1 - px, py)
                }
                if mirrorY {
                    appendPixel(px, imgHeight - 1 - py)
                }
                if mirrorX && mirrorY {
                    appendPixel(imgWidth - 1 - px, imgHeight - 1 - py)
                }
            }
        }

        return pixels
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 && !event.isARepeat { spaceDown=true; NSCursor.openHand.push(); return }
        if event.keyCode == 51 || event.keyCode == 117 { deleteSelection(); return } // Delete/Backspace
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "c": copySelection()
            case "v": pasteClipboard()
            case "d": deselect()
            default: break
            }
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceDown=false; NSCursor.pop() }
        else { super.keyUp(with: event) }
    }

    // MARK: - Mouse

    private var isPanning: Bool { spaceDown || tool == .pan }

    private func pixelCoord(for event: NSEvent) -> (Int, Int)? {
        let loc = convert(event.locationInWindow, from: nil)
        let off = canvasOffset
        let px = Int((loc.x - off.x) / zoom)
        let py = imgHeight - 1 - Int((loc.y - off.y) / zoom)
        guard px>=0,px<imgWidth,py>=0,py<imgHeight else { return nil }
        return (px, py)
    }

    override func mouseMoved(with event: NSEvent) {
        let pixel = pixelCoord(for: event)
        onCursorMoved(pixel)
        updateHoverPixel(pixel)
        // Feature 4: report color at cursor (from composited view)
        if let p = pixel {
            onColorAtCursor?(colorAt(pixel: p))
        } else {
            onColorAtCursor?(nil)
        }
    }
    override func mouseExited(with event: NSEvent) {
        onCursorMoved(nil)
        updateHoverPixel(nil)
        onColorAtCursor?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isPanning { panLastPoint = event.locationInWindow; NSCursor.closedHand.push(); return }
        guard let (x,y) = pixelCoord(for: event) else { return }
        updateHoverPixel((x, y))

        switch tool {
        case .eyedropper:
            // Eyedropper reads from composited view
            if let color = colorAt(pixel: (x, y)) {
                onColorPicked?(color)
            }
            return

        case .fill:
            guard isActiveLayerEditable else { return }
            onWillChange?(); pushUndo()
            floodFill(x:x,y:y); needsDisplay=true; onChanged?(); return

        case .pencil, .eraser:
            guard isActiveLayerEditable else { return }
            onWillChange?(); pushUndo()
            paintAt(x:x,y:y,erase:tool == .eraser)
            lastPixel=(x,y); needsDisplay=true

        case .line, .rectangle, .ellipse:
            guard isActiveLayerEditable else { return }
            onWillChange?()
            previewStart=(x,y); previewEnd=(x,y); needsDisplay=true

        case .select:
            if let sel = selRect, x>=sel.x, x<sel.x+sel.w, y>=sel.y, y<sel.y+sel.h {
                guard isActiveLayerEditable || floatingPixels != nil else { return }
                if floatingPixels == nil { pushUndo(); liftSelection(sel) }
                movingSelection=true
                moveDragStart=(x,y); moveSelOrigin=(floatingOffset.0, floatingOffset.1)
            } else {
                commitFloating()
                selRect=nil; previewStart=(x,y); previewEnd=(x,y); needsDisplay=true
            }

        case .pan: break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning {
            guard let last=panLastPoint, let sv=enclosingScrollView else { return }
            let cur=event.locationInWindow
            var o=sv.contentView.bounds.origin
            o.x -= cur.x-last.x; o.y -= cur.y-last.y
            panLastPoint=cur
            sv.contentView.scroll(to:o); sv.reflectScrolledClipView(sv.contentView); return
        }
        guard let (x,y) = pixelCoord(for: event) else { return }
        updateHoverPixel((x, y))
        // Feature 4: report color during drag
        onColorAtCursor?(colorAt(pixel: (x, y)))

        switch tool {
        case .pencil, .eraser:
            let prev=lastPixel ?? (x,y)
            drawLine(from:prev,to:(x,y),erase:tool == .eraser)
            lastPixel=(x,y); needsDisplay=true; onChanged?()

        case .line, .rectangle, .ellipse:
            previewEnd=(x,y); needsDisplay=true

        case .select:
            if movingSelection, let ds=moveDragStart, let so=moveSelOrigin {
                let dx=x-ds.0, dy=y-ds.1
                floatingOffset=(so.0+dx, so.1+dy)
                if var sel=selRect { sel.x=so.0+dx; sel.y=so.1+dy; selRect=sel }
                needsDisplay=true
            } else {
                previewEnd=(x,y); needsDisplay=true
            }

        default: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if panLastPoint != nil { NSCursor.pop() }
        panLastPoint=nil

        switch tool {
        case .pencil, .eraser:
            lastPixel=nil; onChanged?()

        case .line:
            if let s=previewStart, let e=previewEnd {
                pushUndo(); drawLine(from:s,to:e); previewStart=nil; previewEnd=nil
                invalidateComposite(); needsDisplay=true; onChanged?()
            }

        case .rectangle:
            if let s=previewStart, let e=previewEnd {
                pushUndo(); drawRect(x0:s.0,y0:s.1,x1:e.0,y1:e.1); previewStart=nil; previewEnd=nil
                needsDisplay=true; onChanged?()
            }

        case .ellipse:
            if let s=previewStart, let e=previewEnd {
                pushUndo(); drawEllipse(x0:s.0,y0:s.1,x1:e.0,y1:e.1); previewStart=nil; previewEnd=nil
                needsDisplay=true; onChanged?()
            }

        case .select:
            if movingSelection { movingSelection=false; moveDragStart=nil; moveSelOrigin=nil }
            else if let s=previewStart, let e=previewEnd {
                let minX=min(s.0,e.0), minY=min(s.1,e.1)
                let w=abs(e.0-s.0)+1, h=abs(e.1-s.1)+1
                selRect = w>1||h>1 ? (x:minX,y:minY,w:w,h:h) : nil
                previewStart=nil; previewEnd=nil; needsDisplay=true
            }

        default: break
        }
    }

    override func otherMouseDown(with event: NSEvent)    { panLastPoint=event.locationInWindow; NSCursor.closedHand.push() }
    override func otherMouseDragged(with event: NSEvent) {
        guard let last=panLastPoint, let sv=enclosingScrollView else { return }
        let cur=event.locationInWindow
        var o=sv.contentView.bounds.origin
        o.x-=cur.x-last.x; o.y-=cur.y-last.y
        panLastPoint=cur; sv.contentView.scroll(to:o); sv.reflectScrolledClipView(sv.contentView)
    }
    override func otherMouseUp(with event: NSEvent) { panLastPoint=nil; NSCursor.pop() }

    private func updateHoverPixel(_ pixel: (Int, Int)?) {
        guard hoverPixel?.0 != pixel?.0 || hoverPixel?.1 != pixel?.1 else { return }
        hoverPixel = pixel
        needsDisplay = true
    }

    // MARK: - Feature 5: Scroll wheel zoom

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY
            let factor: CGFloat = delta > 0 ? 1.25 : 0.8
            let newZoom = (zoom * factor).clamped(to: 1...32)
            let levels: [CGFloat] = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32]
            zoom = levels.min(by: { abs($0 - newZoom) < abs($1 - newZoom) }) ?? newZoom
            invalidateIntrinsicContentSize()
            needsDisplay = true
            onZoomChanged?(zoom)
            return
        }
        super.scrollWheel(with: event)
    }
}

// MARK: - CGFloat clamped helper

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private func ==(l:(UInt8,UInt8,UInt8,UInt8),r:(UInt8,UInt8,UInt8,UInt8)) -> Bool {
    l.0==r.0&&l.1==r.1&&l.2==r.2&&l.3==r.3
}
