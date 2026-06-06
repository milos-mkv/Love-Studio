import AppKit

final class TilemapCanvasNSView: NSView {

    // MARK: - Public state

    var config: TilemapConfig = TilemapConfig() {
        didSet {
            if config.animations.isEmpty {
                stopAnimPreview()
            } else {
                startAnimPreviewIfNeeded()
            }
            needsDisplay = true
        }
    }
    var activeLayerIndex: Int = 0
    var tool: TilemapTool = .paint {
        didSet {
            guard oldValue != tool else { return }
            if tool != .select {
                selAnchor = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onSelectionChanged(nil)
                }
            }
            needsDisplay = true
        }
    }
    var zoom: CGFloat = 2.0 {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// 2-D brush pattern: outer = rows, inner = cols, values = GIDs (-1 = transparent)
    var brushPattern: [[Int]] = [[0]]
    var tilesetImages: [NSImage] = [] {
        didSet { tilesetCGImages = []; tileCropCache = [:]; needsDisplay = true }
    }
    var showGrid: Bool = true {
        didSet { needsDisplay = true }
    }
    var onConfigChanged: ((TilemapConfig) -> Void)?
    var onChanged: (() -> Void)?
    var onWillChange: (() -> Void)?
    var onCursorMoved: ((Int, Int)?) -> Void = { _ in }
    var onSelectionChanged: ((x: Int, y: Int, w: Int, h: Int)?) -> Void = { _ in }
    var onObjectSelected: ((MapObject?) -> Void)?
    var onTilePicked: ((Int) -> Void)?
    var soloLayerIndex: Int? = nil
    var randomBrush: Bool = false

    // MARK: - Private

    private var tilesetCGImages: [CGImage] = []
    private var tilesetCols: [Int] = []

    // Tile crop cache: avoids calling CGImage.cropping() every frame
    // Key encodes (tilesetIndex << 20 | localIndex) - reset when tilesets change
    private var tileCropCache: [Int32: CGImage] = [:]

    // Cached checkerboard NSColor pattern - rebuilt only when zoom changes
    private var checkerPattern: NSColor?
    private var checkerPatternZoom: CGFloat = 0

    // Animation preview state: sourceGID → current display GID
    private var animState: [Int: Int] = [:]
    private var animTimers: [Int: Double] = [:]
    private var animFrameIdx: [Int: Int] = [:]
    private var animTimer: Timer?
    private var lastAnimTick: CFTimeInterval = 0

    private func startAnimPreviewIfNeeded() {
        guard animTimer == nil, !config.animations.isEmpty else { return }
        lastAnimTick = CACurrentMediaTime()
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/15.0, repeats: true) { [weak self] _ in
            self?.tickAnimPreview()
        }
    }

    private func stopAnimPreview() {
        animTimer?.invalidate()
        animTimer = nil
        animState = [:]
        animTimers = [:]
        animFrameIdx = [:]
    }

    private func tickAnimPreview() {
        let now = CACurrentMediaTime()
        let dt  = now - lastAnimTick
        lastAnimTick = now
        var changed = false
        for anim in config.animations {
            guard !anim.frames.isEmpty else { continue }
            var idx   = animFrameIdx[anim.sourceGID] ?? 0
            var timer = animTimers[anim.sourceGID] ?? 0
            timer += dt
            let dur = anim.frames[idx].duration
            if timer >= dur {
                timer -= dur
                idx = (idx + 1) % anim.frames.count
                animFrameIdx[anim.sourceGID] = idx
                animTimers[anim.sourceGID]   = timer
                animState[anim.sourceGID]    = anim.frames[idx].gid
                changed = true
            } else {
                animTimers[anim.sourceGID] = timer
                if animState[anim.sourceGID] == nil {
                    animState[anim.sourceGID] = anim.frames[idx].gid
                }
            }
        }
        if changed { needsDisplay = true }
    }

    private var spaceDown = false
    private var panLastWindowPoint: CGPoint? = nil

    private var selAnchor: (Int, Int)? = nil
    private var selCurrent: (Int, Int) = (0, 0)

    private var rectAnchor: (Int, Int)? = nil
    private var rectCurrent: (Int, Int) = (0, 0)

    private var selectedObjectID: UUID? = nil
    private var objDragStart: (Int, Int)? = nil

    private var selTileRect: (x: Int, y: Int, w: Int, h: Int)? {
        guard let anchor = selAnchor else { return nil }
        let minX = min(anchor.0, selCurrent.0)
        let minY = min(anchor.1, selCurrent.1)
        let maxX = max(anchor.0, selCurrent.0)
        let maxY = max(anchor.1, selCurrent.1)
        return (x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1)
    }

    // MARK: - Sizing

    private let canvasPadding: CGFloat = 80

    private var mapPixelSize: NSSize {
        NSSize(width:  CGFloat(config.mapWidth)  * CGFloat(config.tileSize) * zoom,
               height: CGFloat(config.mapHeight) * CGFloat(config.tileSize) * zoom)
    }

    override var intrinsicContentSize: NSSize {
        let m = mapPixelSize
        return NSSize(width:  m.width  + canvasPadding * 2,
                      height: m.height + canvasPadding * 2)
    }

    private var mapOffset: CGPoint {
        let m = mapPixelSize
        let ox = round(max(canvasPadding, (bounds.width  - m.width)  / 2))
        let oy = round(max(canvasPadding, (bounds.height - m.height) / 2))
        return CGPoint(x: ox, y: oy)
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Tracking area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        let off = mapOffset
        let loc = CGPoint(x: raw.x - off.x, y: raw.y - off.y)
        let ts  = CGFloat(config.tileSize) * zoom
        let mh  = config.mapHeight
        let col = Int(loc.x / ts)
        let row = mh - 1 - Int(loc.y / ts)
        if col >= 0, col < config.mapWidth, row >= 0, row < config.mapHeight {
            onCursorMoved((col, row))
        } else {
            onCursorMoved(nil)
        }
    }

    override func mouseExited(with event: NSEvent) { onCursorMoved(nil) }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let ts  = CGFloat(config.tileSize) * zoom
        let mw  = max(1, config.mapWidth)
        let mh  = max(1, config.mapHeight)
        let off = mapOffset

        // Compute visible tile range from dirtyRect so we skip off-screen tiles entirely.
        // dirtyRect is in view coords; shift by -off to get canvas-local coords.
        let lx0 = dirtyRect.minX - off.x, lx1 = dirtyRect.maxX - off.x
        let ly0 = dirtyRect.minY - off.y, ly1 = dirtyRect.maxY - off.y
        let visX0 = max(0,      Int(lx0 / ts))
        let visX1 = min(mw - 1, max(0, Int(lx1 / ts)))
        // Canvas Y=0 is bottom; row 0 is top → flip
        let visY0 = max(0,      mh - 1 - max(0, Int(ly1 / ts)))
        let visY1 = min(mh - 1, mh - 1 - max(0, Int(ly0 / ts)))

        // Guard: if visible range is invalid (e.g. dirtyRect outside canvas) skip drawing.
        guard visX0 <= visX1, visY0 <= visY1 else { return }

        ctx.saveGState()
        ctx.translateBy(x: off.x, y: off.y)

        // ── Rebuild CGImage / cols caches when needed ──────────────────
        if tilesetCGImages.count != tilesetImages.count {
            tilesetCGImages = tilesetImages.compactMap {
                $0.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            tilesetCols = tilesetCGImages.map { max(1, Int($0.width) / config.tileSize) }
            tileCropCache = [:]
        }

        // ── Canvas background - solid color fill ─────────────────────
        ctx.setFillColor(NSColor(white: 0.18, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(mw) * ts, height: CGFloat(mh) * ts))

        // ── Layers ─────────────────────────────────────────────────────
        for (li, layer) in config.layers.enumerated() where layer.visible && (soloLayerIndex == nil || li == soloLayerIndex) {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(layer.opacity))
            if layer.layerType == .object {
                drawObjectLayer(layer, ctx: ctx, ts: ts, mw: mw, mh: mh, isActive: li == activeLayerIndex)
            } else if layer.isCollision {
                drawCollisionLayer(layer, ctx: ctx, ts: ts, mw: mw, mh: mh,
                                   visX0: visX0, visX1: visX1, visY0: visY0, visY1: visY1)
            } else {
                drawLayer(layer, ctx: ctx, ts: ts, mw: mw, mh: mh,
                          visX0: visX0, visX1: visX1, visY0: visY0, visY1: visY1)
            }
            ctx.restoreGState()
        }

        // ── Grid ───────────────────────────────────────────────────────
        if showGrid {
            let mapH = CGFloat(mh) * ts
            let mapW = CGFloat(mw) * ts
            ctx.setStrokeColor(gridLineColor.cgColor)
            ctx.setLineWidth(0.5)
            // Vertical lines: span full map height
            for x in visX0...min(mw, visX1 + 1) {
                ctx.move(to: CGPoint(x: CGFloat(x) * ts, y: 0))
                ctx.addLine(to: CGPoint(x: CGFloat(x) * ts, y: mapH))
            }
            // Horizontal lines: span full map width
            // Canvas Y=0 is bottom, rows increase downward from top → flip
            let yStart = mh - visY1 - 1
            let yEnd   = mh - visY0
            if yStart <= yEnd {
                for y in yStart...yEnd {
                    ctx.move(to: CGPoint(x: 0,    y: CGFloat(y) * ts))
                    ctx.addLine(to: CGPoint(x: mapW, y: CGFloat(y) * ts))
                }
            }
            ctx.strokePath()
        }

        // ── Border ─────────────────────────────────────────────────────
        ctx.setStrokeColor(borderLineColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: 0, y: 0, width: CGFloat(mw) * ts, height: CGFloat(mh) * ts))

        // ── Selection rect ─────────────────────────────────────────────
        if tool == .select, let sel = selTileRect {
            let selRect = CGRect(
                x: CGFloat(sel.x) * ts,
                y: CGFloat(mh - sel.y - sel.h) * ts,
                width: CGFloat(sel.w) * ts,
                height: CGFloat(sel.h) * ts
            )
            ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.15).cgColor)
            ctx.fill(selRect)
            ctx.setStrokeColor(NSColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(selRect.insetBy(dx: 0.75, dy: 0.75))
            ctx.setLineDash(phase: 0, lengths: [])
        }

        // ── Rect fill preview ──────────────────────────────────────────
        if tool == .rectFill, let anchor = rectAnchor {
            let minX = min(anchor.0, rectCurrent.0)
            let minY = min(anchor.1, rectCurrent.1)
            let maxX = max(anchor.0, rectCurrent.0)
            let maxY = max(anchor.1, rectCurrent.1)
            let w = maxX - minX + 1, h = maxY - minY + 1
            let previewRect = CGRect(
                x: CGFloat(minX) * ts, y: CGFloat(mh - minY - h) * ts,
                width: CGFloat(w) * ts, height: CGFloat(h) * ts)
            ctx.setFillColor(NSColor.systemOrange.withAlphaComponent(0.20).cgColor)
            ctx.fill(previewRect)
            ctx.setStrokeColor(NSColor.systemOrange.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(previewRect.insetBy(dx: 0.75, dy: 0.75))
            ctx.setLineDash(phase: 0, lengths: [])
        }

        ctx.restoreGState()
    }

    // Cached NSColor pattern checkerboard - one fill call covers entire visible area.
    private func drawCheckerboard(ctx: CGContext, ts: CGFloat, mw: Int, mh: Int,
                                  visX0: Int, visX1: Int, visY0: Int, visY1: Int) {
        if checkerPatternZoom != ts || checkerPattern == nil {
            checkerPatternZoom = ts
            let cell = max(ts, 4)
            let lightColor = checkerboardLightColor
            let darkColor  = checkerboardDarkColor
            let img = NSImage(size: NSSize(width: cell * 2, height: cell * 2), flipped: false) { _ in
                lightColor.setFill()
                NSRect(x: 0,    y: 0,    width: cell, height: cell).fill()
                NSRect(x: cell, y: cell, width: cell, height: cell).fill()
                darkColor.setFill()
                NSRect(x: cell, y: 0,    width: cell, height: cell).fill()
                NSRect(x: 0,    y: cell, width: cell, height: cell).fill()
                return true
            }
            checkerPattern = NSColor(patternImage: img)
        }
        let visRect = CGRect(
            x: CGFloat(visX0) * ts,
            y: CGFloat(mh - visY1 - 1) * ts,
            width: CGFloat(visX1 - visX0 + 1) * ts,
            height: CGFloat(visY1 - visY0 + 1) * ts)
        ctx.saveGState()
        ctx.clip(to: visRect)
        checkerPattern?.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(mw) * ts, height: CGFloat(mh) * ts).fill()
        ctx.restoreGState()
    }

    // Cached CGImage crop for a single tile - avoids CGImage.cropping() every frame.
    private func cachedCrop(tsIdx: Int, localIdx: Int) -> CGImage? {
        let key = Int32(tsIdx) << 20 | Int32(localIdx)
        if let cached = tileCropCache[key] { return cached }
        guard tsIdx < tilesetCGImages.count else { return nil }
        let cg   = tilesetCGImages[tsIdx]
        let cols = tilesetCols[tsIdx]
        let col  = localIdx % cols
        let row  = localIdx / cols
        let srcX = col * config.tileSize
        let srcY = row * config.tileSize
        guard let cropped = cg.cropping(to: CGRect(x: srcX, y: srcY,
                                                    width: config.tileSize,
                                                    height: config.tileSize))
        else { return nil }
        tileCropCache[key] = cropped
        return cropped
    }

    private func drawLayer(_ layer: TileLayer, ctx: CGContext, ts: CGFloat, mw: Int, mh: Int,
                            visX0: Int, visX1: Int, visY0: Int, visY1: Int) {
        ctx.interpolationQuality = .none
        for y in visY0...visY1 {
            for x in visX0...visX1 {
                let storedGID = layer.tiles[y * mw + x]
                guard storedGID >= 0 else { continue }
                let fH       = TilemapConfig.flipH(storedGID)
                let fV       = TilemapConfig.flipV(storedGID)
                let cleanGID = TilemapConfig.rawGID(storedGID)
                let gid      = animState[cleanGID] ?? cleanGID
                let destRect = CGRect(x: CGFloat(x) * ts, y: CGFloat(mh - 1 - y) * ts,
                                      width: ts, height: ts)
                let (tsIdx, localIdx) = TilemapConfig.decodeGID(gid)

                if let tile = cachedCrop(tsIdx: tsIdx, localIdx: localIdx) {
                    if fH || fV {
                        ctx.saveGState()
                        ctx.translateBy(x: destRect.midX, y: destRect.midY)
                        ctx.scaleBy(x: fH ? -1 : 1, y: fV ? -1 : 1)
                        ctx.translateBy(x: -ts / 2, y: -ts / 2)
                        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: ts, height: ts))
                        ctx.restoreGState()
                    } else {
                        ctx.draw(tile, in: destRect)
                    }
                } else {
                    // Fallback: color swatch when no tileset loaded
                    let hue = CGFloat(localIdx % 16) / 16.0
                    ctx.setFillColor(NSColor(hue: hue, saturation: 0.6,
                                            brightness: 0.8, alpha: 0.9).cgColor)
                    ctx.fill(destRect)
                }
            }
        }
    }

    private func drawCollisionLayer(_ layer: TileLayer, ctx: CGContext, ts: CGFloat, mw: Int, mh: Int,
                                    visX0: Int, visX1: Int, visY0: Int, visY1: Int) {
        for y in visY0...visY1 {
            for x in visX0...visX1 {
                let val = layer.tiles[y * mw + x]
                guard val >= 0 else { continue }
                let rect = CGRect(x: CGFloat(x) * ts,
                                  y: CGFloat(mh - 1 - y) * ts,
                                  width: ts, height: ts)
                ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.45).cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.85).cgColor)
                ctx.setLineWidth(max(1.0, ts * 0.08))
                ctx.move(to: CGPoint(x: rect.minX + ts * 0.15, y: rect.minY + ts * 0.15))
                ctx.addLine(to: CGPoint(x: rect.maxX - ts * 0.15, y: rect.maxY - ts * 0.15))
                ctx.move(to: CGPoint(x: rect.maxX - ts * 0.15, y: rect.minY + ts * 0.15))
                ctx.addLine(to: CGPoint(x: rect.minX + ts * 0.15, y: rect.maxY - ts * 0.15))
                ctx.strokePath()
            }
        }
    }

    // MARK: - Keyboard (Space for temporary pan)

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 && !event.isARepeat {
            spaceDown = true; NSCursor.openHand.push()
        } else { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceDown = false; NSCursor.pop() }
        else { super.keyUp(with: event) }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isPanning { beginPan(event); return }

        if tool == .select {
            let (col, row) = tileCoord(for: event)
            // Check object layer first
            if activeLayerIndex < config.layers.count,
               config.layers[activeLayerIndex].layerType == .object {
                let obj = objectAt(tileX: col, tileY: row, in: config.layers[activeLayerIndex])
                selectedObjectID = obj?.id
                onObjectSelected?(obj)
                needsDisplay = true
                return
            }
            guard col >= 0, col < config.mapWidth,
                  row >= 0, row < config.mapHeight else { return }
            selAnchor  = (col, row)
            selCurrent = (col, row)
            onSelectionChanged(selTileRect)
            needsDisplay = true; return
        }

        if tool == .rectFill {
            let (col, row) = tileCoord(for: event)
            guard col >= 0, col < config.mapWidth,
                  row >= 0, row < config.mapHeight else { return }
            rectAnchor  = (col, row)
            rectCurrent = (col, row)
            onWillChange?()
            needsDisplay = true; return
        }

        // Object layer paint/erase
        if activeLayerIndex < config.layers.count,
           config.layers[activeLayerIndex].layerType == .object {
            let (col, row) = tileCoord(for: event)
            guard col >= 0, col < config.mapWidth,
                  row >= 0, row < config.mapHeight else { return }
            if tool == .erase {
                if let idx = config.layers[activeLayerIndex].objects.firstIndex(where: {
                    $0.tileX <= col && col < $0.tileX + $0.tileW &&
                    $0.tileY <= row && row < $0.tileY + $0.tileH
                }) {
                    onWillChange?()
                    config.layers[activeLayerIndex].objects.remove(at: idx)
                    onConfigChanged?(config); onChanged?()
                }
            } else if tool == .paint {
                onWillChange?()
                if let existing = objectAt(tileX: col, tileY: row, in: config.layers[activeLayerIndex]) {
                    selectedObjectID = existing.id
                    onObjectSelected?(existing)
                } else {
                    var newObj = MapObject()
                    newObj.tileX = col
                    newObj.tileY = row
                    config.layers[activeLayerIndex].objects.append(newObj)
                    selectedObjectID = newObj.id
                    onConfigChanged?(config); onChanged?()
                    onObjectSelected?(newObj)
                }
            }
            needsDisplay = true
            return
        }

        if tool == .eyedropper {
            let (col, row) = tileCoord(for: event)
            guard col >= 0, col < config.mapWidth,
                  row >= 0, row < config.mapHeight,
                  activeLayerIndex < config.layers.count else { return }
            let gid = config.layers[activeLayerIndex].tiles[row * config.mapWidth + col]
            if gid >= 0 { onTilePicked?(gid) }
            return
        }

        onWillChange?()
        applyTool(event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning { continuePan(event); return }

        if tool == .select {
            // Object layer select via drag - just track
            if activeLayerIndex < config.layers.count,
               config.layers[activeLayerIndex].layerType == .object {
                return
            }
            let (col, row) = tileCoord(for: event)
            selCurrent = (
                max(0, min(config.mapWidth  - 1, col)),
                max(0, min(config.mapHeight - 1, row))
            )
            onSelectionChanged(selTileRect)
            needsDisplay = true; return
        }

        if tool == .rectFill {
            let (col, row) = tileCoord(for: event)
            rectCurrent = (
                max(0, min(config.mapWidth  - 1, col)),
                max(0, min(config.mapHeight - 1, row))
            )
            needsDisplay = true; return
        }

        // Object layer: skip normal painting on drag
        if activeLayerIndex < config.layers.count,
           config.layers[activeLayerIndex].layerType == .object {
            return
        }

        if tool == .eyedropper {
            let (col, row) = tileCoord(for: event)
            guard col >= 0, col < config.mapWidth,
                  row >= 0, row < config.mapHeight,
                  activeLayerIndex < config.layers.count else { return }
            let gid = config.layers[activeLayerIndex].tiles[row * config.mapWidth + col]
            if gid >= 0 { onTilePicked?(gid) }
            return
        }

        applyTool(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        if panLastWindowPoint != nil { NSCursor.pop() }
        panLastWindowPoint = nil

        if tool == .rectFill, rectAnchor != nil {
            applyRectFill()
            rectAnchor = nil
            needsDisplay = true
        }
    }

    override func otherMouseDown(with event: NSEvent)    { beginPan(event) }
    override func otherMouseDragged(with event: NSEvent) { continuePan(event) }
    override func otherMouseUp(with event: NSEvent)      { panLastWindowPoint = nil; NSCursor.pop() }

    private var isPanning: Bool { spaceDown || tool == .pan }

    private func beginPan(_ event: NSEvent) {
        panLastWindowPoint = event.locationInWindow
        NSCursor.closedHand.push()
    }

    private func continuePan(_ event: NSEvent) {
        guard let last = panLastWindowPoint,
              let sv = enclosingScrollView else { return }
        let current = event.locationInWindow
        let dx = current.x - last.x
        let dy = current.y - last.y
        panLastWindowPoint = current
        var origin = sv.contentView.bounds.origin
        origin.x -= dx; origin.y -= dy
        sv.contentView.scroll(to: origin)
        sv.reflectScrolledClipView(sv.contentView)
    }

    // MARK: - Tile coord helper

    private func tileCoord(for event: NSEvent) -> (Int, Int) {
        let raw = convert(event.locationInWindow, from: nil)
        let off = mapOffset
        let loc = CGPoint(x: raw.x - off.x, y: raw.y - off.y)
        let ts  = CGFloat(config.tileSize) * zoom
        let mh  = config.mapHeight
        let col = Int(loc.x / ts)
        let row = mh - 1 - Int(loc.y / ts)
        return (col, row)
    }

    // MARK: - Tool application

    private func applyTool(event: NSEvent) {
        guard activeLayerIndex < config.layers.count else { return }
        guard !config.layers[activeLayerIndex].isLocked else { return }
        guard tool != .pan, tool != .select, tool != .rectFill, tool != .eyedropper else { return }
        // Object layers handled separately
        guard config.layers[activeLayerIndex].layerType != .object else { return }

        let (tileX, tileY) = tileCoord(for: event)
        guard tileX >= 0, tileX < config.mapWidth,
              tileY >= 0, tileY < config.mapHeight else { return }

        let isCollision = config.layers[activeLayerIndex].isCollision

        switch tool {
        case .paint:
            if isCollision {
                config.layers[activeLayerIndex].tiles[tileY * config.mapWidth + tileX] = 0
            } else {
                paintBrush(atX: tileX, y: tileY)
            }
        case .erase:
            config.layers[activeLayerIndex].tiles[tileY * config.mapWidth + tileX] = -1
        case .fill:
            let replacement = isCollision ? 0 : (brushPattern.first?.first ?? 0)
            let target = config.layers[activeLayerIndex].tiles[tileY * config.mapWidth + tileX]
            guard target != replacement else { return }
            floodFill(layer: activeLayerIndex, x: tileX, y: tileY,
                      target: target, replacement: replacement)
            onConfigChanged?(config); onChanged?(); return
        case .pan, .select, .rectFill, .eyedropper:
            return
        }

        needsDisplay = true
        onConfigChanged?(config)
        onChanged?()
    }

    private func paintBrush(atX originX: Int, y originY: Int) {
        let mw = config.mapWidth, mh = config.mapHeight
        if randomBrush {
            // flatten all non-empty GIDs from brush pattern, pick random one
            let allGIDs = brushPattern.flatMap { $0 }.filter { $0 >= 0 }
            guard !allGIDs.isEmpty else { return }
            let gid = allGIDs[Int.random(in: 0..<allGIDs.count)]
            let tx = originX, ty = originY
            guard tx >= 0, tx < mw, ty >= 0, ty < mh else { return }
            config.layers[activeLayerIndex].tiles[ty * mw + tx] = gid
        } else {
            for (dr, row) in brushPattern.enumerated() {
                for (dc, gid) in row.enumerated() {
                    let tx = originX + dc, ty = originY + dr
                    guard tx >= 0, tx < mw, ty >= 0, ty < mh else { continue }
                    config.layers[activeLayerIndex].tiles[ty * mw + tx] = gid
                }
            }
        }
    }

    private func floodFill(layer: Int, x: Int, y: Int, target: Int, replacement: Int) {
        var stack = [(x, y)]
        let mw = config.mapWidth, mh = config.mapHeight
        while !stack.isEmpty {
            let (cx, cy) = stack.removeLast()
            guard cx >= 0, cx < mw, cy >= 0, cy < mh else { continue }
            let i = cy * mw + cx
            guard config.layers[layer].tiles[i] == target else { continue }
            config.layers[layer].tiles[i] = replacement
            stack.append((cx + 1, cy)); stack.append((cx - 1, cy))
            stack.append((cx, cy + 1)); stack.append((cx, cy - 1))
        }
    }

    private func applyRectFill() {
        guard let anchor = rectAnchor,
              activeLayerIndex < config.layers.count else { return }
        let isCollision = config.layers[activeLayerIndex].isCollision
        let minX = min(anchor.0, rectCurrent.0)
        let minY = min(anchor.1, rectCurrent.1)
        let maxX = max(anchor.0, rectCurrent.0)
        let maxY = max(anchor.1, rectCurrent.1)
        let mw = config.mapWidth, mh = config.mapHeight
        let bRows = brushPattern.count
        let bCols = brushPattern.first?.count ?? 1
        for ty in minY...maxY {
            for tx in minX...maxX {
                guard tx >= 0, tx < mw, ty >= 0, ty < mh else { continue }
                if isCollision {
                    config.layers[activeLayerIndex].tiles[ty * mw + tx] = 0
                } else {
                    let br = (ty - minY) % max(1, bRows)
                    let bc = (tx - minX) % max(1, bCols)
                    guard br < brushPattern.count, bc < brushPattern[br].count else { continue }
                    let gid = brushPattern[br][bc]
                    config.layers[activeLayerIndex].tiles[ty * mw + tx] = gid
                }
            }
        }
        onConfigChanged?(config)
        onChanged?()
    }

    private func objectAt(tileX: Int, tileY: Int, in layer: TileLayer) -> MapObject? {
        layer.objects.first { $0.tileX <= tileX && tileX < $0.tileX + $0.tileW &&
                              $0.tileY <= tileY && tileY < $0.tileY + $0.tileH }
    }

    private func drawObjectLayer(_ layer: TileLayer, ctx: CGContext, ts: CGFloat, mw: Int, mh: Int, isActive: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(ts * 0.25, 7)),
            .foregroundColor: NSColor.white
        ]
        for obj in layer.objects {
            let rect = CGRect(
                x: CGFloat(obj.tileX) * ts,
                y: CGFloat(mh - obj.tileY - obj.tileH) * ts,
                width: CGFloat(obj.tileW) * ts,
                height: CGFloat(obj.tileH) * ts
            )
            let color: NSColor
            switch obj.type {
            case "spawn":   color = NSColor.systemGreen
            case "trigger": color = NSColor.systemBlue
            case "npc":     color = NSColor.systemPurple
            default:        color = NSColor.systemYellow
            }
            ctx.setFillColor(color.withAlphaComponent(isActive ? 0.4 : 0.2).cgColor)
            ctx.fill(rect)
            if obj.id == selectedObjectID {
                ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
                ctx.setLineWidth(2.0)
            } else {
                ctx.setStrokeColor(color.withAlphaComponent(0.7).cgColor)
                ctx.setLineWidth(1.0)
            }
            ctx.stroke(rect)
            let label = obj.name as NSString
            let sz = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2),
                       withAttributes: attrs)
        }
    }

    // MARK: - Appearance

    private var isLightAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    }
    private var checkerboardLightColor: NSColor {
        isLightAppearance ? NSColor(calibratedWhite: 0.94, alpha: 1)
                          : NSColor(calibratedWhite: 0.18, alpha: 1)
    }
    private var checkerboardDarkColor: NSColor {
        isLightAppearance ? NSColor(calibratedWhite: 0.88, alpha: 1)
                          : NSColor(calibratedWhite: 0.14, alpha: 1)
    }
    private var gridLineColor: NSColor {
        isLightAppearance ? NSColor.separatorColor.withAlphaComponent(0.45)
                          : NSColor.white.withAlphaComponent(0.08)
    }
    private var borderLineColor: NSColor {
        isLightAppearance ? NSColor.separatorColor.withAlphaComponent(0.85)
                          : NSColor.white.withAlphaComponent(0.3)
    }
}
