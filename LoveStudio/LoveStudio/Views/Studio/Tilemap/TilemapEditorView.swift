import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum P {
    static let sidebar  = Color(nsColor: .controlBackgroundColor)       // light gray in light, dark in dark
    static let canvas   = Color(nsColor: .underPageBackgroundColor)
    static let toolbar  = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.76, alpha: 1)
    })
    static let card     = Color(nsColor: .textBackgroundColor)          // white in light, deep in dark
    static let field    = Color(nsColor: .textBackgroundColor)
    static let border   = Color(nsColor: .separatorColor)
    static let accent   = Color.orange
    static let accentBg = Color.orange.opacity(0.14)
}

// MARK: - Minimap

private struct TilemapMinimapView: View {
    let config: TilemapConfig
    let tilesetImages: [NSImage]
    let activeLayer: Int

    private let maxSize: CGFloat = 160

    private var cellSize: CGFloat {
        let w = maxSize / CGFloat(max(1, config.mapWidth))
        let h = maxSize / CGFloat(max(1, config.mapHeight))
        return max(1, min(w, h))
    }

    private var mapW: CGFloat { CGFloat(config.mapWidth)  * cellSize }
    private var mapH: CGFloat { CGFloat(config.mapHeight) * cellSize }

    var body: some View {
        Canvas { ctx, _ in
            // Background
            ctx.fill(Path(CGRect(x: 0, y: 0, width: mapW, height: mapH)),
                     with: .color(Color(nsColor: .underPageBackgroundColor)))

            // Draw all visible tile layers
            for layer in config.layers where layer.visible && layer.layerType == .tile {
                for (idx, rawgid) in layer.tiles.enumerated() {
                    guard rawgid > 0 else { continue }
                    let gid = rawgid & ~(TilemapConfig.FLIP_H | TilemapConfig.FLIP_V)
                    let col = idx % config.mapWidth
                    let row = idx / config.mapWidth
                    let rect = CGRect(x: CGFloat(col) * cellSize,
                                      y: CGFloat(row) * cellSize,
                                      width: cellSize, height: cellSize)

                    // Try to get tile color from tileset image
                    let (tsIdx, localIdx) = TilemapConfig.decodeGID(gid)
                    if tsIdx < tilesetImages.count,
                       let cgImg = tilesetImages[tsIdx].cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let ts   = config.tileSize
                        let cols = cgImg.width / ts
                        guard cols > 0 else { continue }
                        let tc   = localIdx % cols
                        let tr   = localIdx / cols
                        let crop = CGRect(x: tc * ts, y: tr * ts, width: ts, height: ts)
                        if let tile = cgImg.cropping(to: crop) {
                            ctx.draw(Image(tile, scale: 1, label: Text("")),
                                     in: rect)
                        }
                    } else {
                        ctx.fill(Path(rect), with: .color(.gray.opacity(0.6)))
                    }
                }
            }

            // Collision overlay (semi-transparent red)
            for layer in config.layers where layer.isCollision {
                for (idx, v) in layer.tiles.enumerated() {
                    guard v > 0 else { continue }
                    let col = idx % config.mapWidth
                    let row = idx / config.mapWidth
                    let rect = CGRect(x: CGFloat(col) * cellSize,
                                      y: CGFloat(row) * cellSize,
                                      width: cellSize, height: cellSize)
                    ctx.fill(Path(rect), with: .color(.red.opacity(0.45)))
                }
            }

            // Object layer dots
            for layer in config.layers where layer.visible && layer.layerType == .object {
                for obj in layer.objects {
                    let rect = CGRect(x: CGFloat(obj.tileX) * cellSize,
                                      y: CGFloat(obj.tileY) * cellSize,
                                      width: max(cellSize, CGFloat(obj.tileW) * cellSize),
                                      height: max(cellSize, CGFloat(obj.tileH) * cellSize))
                    ctx.stroke(Path(rect), with: .color(.green.opacity(0.85)), lineWidth: max(0.5, cellSize * 0.15))
                }
            }

            // Active layer highlight border
            if config.layers.indices.contains(activeLayer) {
                ctx.stroke(Path(CGRect(x: 0, y: 0, width: mapW, height: mapH)),
                           with: .color(.orange.opacity(0.5)), lineWidth: 1)
            }
        }
        .frame(width: mapW, height: mapH)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
        .allowsHitTesting(false)
    }
}

// MARK: - Toolbar tooltip

private struct ToolbarTooltip: ViewModifier {
    let label: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .overlay(alignment: .bottom) {
                if isHovering {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border.opacity(0.7), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                        .offset(y: 34)
                        .fixedSize()
                        .zIndex(999)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

private extension View {
    func toolbarTooltip(_ label: String) -> some View {
        modifier(ToolbarTooltip(label: label))
    }
}

// MARK: - Canvas wrapper

private struct TilemapCanvasView: NSViewRepresentable {
    @Binding var config: TilemapConfig
    var activeLayerIndex: Int
    var brushPattern: [[Int]]
    var tool: TilemapTool
    var tilesetImages: [NSImage]
    var zoom: CGFloat
    var showGrid: Bool
    var onChanged: () -> Void
    var onWillChange: () -> Void
    var onCursorMoved: ((Int, Int)?) -> Void
    var onSelectionChanged: ((x: Int, y: Int, w: Int, h: Int)?) -> Void
    var onObjectSelected: ((MapObject?) -> Void)?
    var soloLayerIndex: Int?
    var randomBrush: Bool
    var onTilePicked: ((Int) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller   = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers    = true
        sv.borderType            = .noBorder
        sv.backgroundColor       = NSColor.controlBackgroundColor

        let canvas = TilemapCanvasNSView()
        canvas.config               = config
        canvas.activeLayerIndex     = activeLayerIndex
        canvas.brushPattern         = brushPattern
        canvas.tool                 = tool
        canvas.tilesetImages        = tilesetImages
        canvas.zoom                 = zoom
        canvas.showGrid             = showGrid
        canvas.onConfigChanged      = { newConfig in config = newConfig }
        canvas.onChanged            = { onChanged() }
        canvas.onWillChange         = { onWillChange() }
        canvas.onCursorMoved        = { onCursorMoved($0) }
        canvas.onSelectionChanged   = { onSelectionChanged($0) }
        canvas.onObjectSelected     = onObjectSelected
        canvas.soloLayerIndex = soloLayerIndex
        canvas.randomBrush    = randomBrush
        canvas.onTilePicked   = onTilePicked
        canvas.frame                = NSRect(origin: .zero, size: canvas.intrinsicContentSize)

        sv.documentView = canvas
        context.coordinator.canvas = canvas
        context.coordinator.scrollView = sv

        DispatchQueue.main.async { scrollToCenter(sv: sv, canvas: canvas) }
        return sv
    }

    private func scrollToCenter(sv: NSScrollView, canvas: NSView) {
        let docSize  = canvas.frame.size
        let clipSize = sv.contentView.bounds.size
        let x = max(0, (docSize.width  - clipSize.width)  / 2)
        let y = max(0, (docSize.height - clipSize.height) / 2)
        sv.contentView.scroll(to: CGPoint(x: x, y: y))
        sv.reflectScrolledClipView(sv.contentView)
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }
        let prevZoom = canvas.zoom
        canvas.config               = config
        canvas.activeLayerIndex     = activeLayerIndex
        canvas.brushPattern         = brushPattern
        canvas.tool                 = tool
        canvas.zoom                 = zoom
        canvas.showGrid             = showGrid
        if canvas.tilesetImages.map(\.size) != tilesetImages.map(\.size) {
            canvas.tilesetImages = tilesetImages
        }
        canvas.onConfigChanged    = { newConfig in config = newConfig }
        canvas.onWillChange       = { onWillChange() }
        canvas.onCursorMoved      = { onCursorMoved($0) }
        canvas.onSelectionChanged = { onSelectionChanged($0) }
        canvas.onObjectSelected   = onObjectSelected
        canvas.soloLayerIndex = soloLayerIndex
        canvas.randomBrush    = randomBrush
        canvas.onTilePicked   = onTilePicked
        let intrinsic  = canvas.intrinsicContentSize
        let clipSize   = sv.contentView.bounds.size
        let size = NSSize(width:  max(intrinsic.width,  clipSize.width),
                          height: max(intrinsic.height, clipSize.height))
        if canvas.frame.size != size {
            canvas.frame = NSRect(origin: .zero, size: size)
        }
        if zoom != prevZoom {
            DispatchQueue.main.async { scrollToCenter(sv: sv, canvas: canvas) }
        }
        canvas.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        weak var canvas: TilemapCanvasNSView?
        weak var scrollView: NSScrollView?
    }
    static func dismantleNSView(_ sv: NSScrollView, coordinator: Coordinator) {}
}

// MARK: - Tileset picker wrapper

private struct TilesetPickerView: NSViewRepresentable {
    var tilesetImage: NSImage?
    var tileSize: Int
    var activeTilesetIdx: Int
    var scale: CGFloat
    var onSelectBrush: ([[Int]]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller   = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers    = true
        sv.borderType            = .noBorder
        sv.backgroundColor       = NSColor.controlBackgroundColor

        let picker = TilesetPickerNSView()
        picker.tilesetImage   = tilesetImage
        picker.tileSize       = tileSize
        picker.scale          = scale
        picker.onSelectBrush  = { onSelectBrush($0) }
        sv.documentView       = picker
        context.coordinator.picker = picker
        DispatchQueue.main.async {
            let intrinsic = picker.intrinsicContentSize
            let clipSize  = sv.contentView.bounds.size
            picker.frame = NSRect(origin: .zero,
                                  size: NSSize(width:  max(intrinsic.width,  clipSize.width),
                                               height: max(intrinsic.height, clipSize.height)))
        }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let picker = context.coordinator.picker else { return }
        if picker.tilesetImage !== tilesetImage { picker.tilesetImage = tilesetImage }
        picker.tileSize = tileSize
        picker.scale    = scale
        let intrinsic = picker.intrinsicContentSize
        let clipSize  = sv.contentView.bounds.size
        let size = NSSize(width:  max(intrinsic.width,  clipSize.width),
                          height: max(intrinsic.height, clipSize.height))
        if picker.frame.size != size { picker.frame = NSRect(origin: .zero, size: size) }
        picker.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { weak var picker: TilesetPickerNSView? }
}

// MARK: - Main editor

struct TilemapEditorView: View {
    let projectURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var config           = TilemapConfig()
    @State private var selectedGID      = 0
    @State private var brushPattern: [[Int]] = [[0]]
    @State private var activeTilesetIdx = 0
    @State private var activeLayer      = 0
    @State private var tool: TilemapTool = .paint
    @State private var zoom: CGFloat    = 2.0
    @State private var tilesetImages: [NSImage] = []
    @State private var generatedCode    = ""
    @State private var copied           = false
    @State private var showCode         = false
    @State private var showGrid         = true
    @State private var savedMaps: [TilemapConfig] = []
    @State private var saveStatus       = ""
    // Undo / Redo
    @State private var undoStack: [[TileLayer]] = []
    @State private var redoStack: [[TileLayer]] = []

    @State private var cursorTile: (Int, Int)? = nil
    @State private var activeSelection: (x: Int, y: Int, w: Int, h: Int)? = nil
    @State private var clipboard: [[Int]] = []
    @State private var brushFlipH = false
    @State private var brushFlipV = false
    @State private var randomBrush = false
    @State private var soloLayerIndex: Int? = nil
    @State private var showMinimap = true

    // Collapsible left panel sections
    @State private var sectionOriginExpanded    = true
    @State private var sectionTileSizeExpanded  = true
    @State private var sectionMapSizeExpanded   = true
    @State private var sectionLayersExpanded    = true

    @State private var selectedObject: MapObject? = nil

    @State private var widthStr      = "20"
    @State private var heightStr     = "15"
    @State private var leftPanelWidth: CGFloat = 240
    @State private var tilesetZoom: CGFloat = 2.0
    @State private var editingAnim: TileAnimation? = nil
    @State private var showAnimationsPopover = false

    // Group animation builder state
    @State private var showGroupAnimPanel = false
    @State private var groupAnimBlocks: [[[Int]]] = []       // [blockIndex][row][col] = GID
    @State private var groupAnimBlockSize: (w: Int, h: Int)? = nil
    @State private var groupAnimDefaultMs: Int = 120
    @State private var groupAnimStatus: String = ""

    private var activeTilesetImage: NSImage? {
        guard activeTilesetIdx < tilesetImages.count else { return nil }
        return tilesetImages[activeTilesetIdx]
    }

    private var effectiveBrush: [[Int]] {
        var b = brushPattern
        if brushFlipV { b = b.reversed() }
        if brushFlipH { b = b.map { $0.reversed() } }
        // Encode flip bits into every GID so single-tile flips work too
        let flipBits = (brushFlipH ? TilemapConfig.FLIP_H : 0)
                     | (brushFlipV ? TilemapConfig.FLIP_V : 0)
        if flipBits != 0 {
            b = b.map { row in row.map { gid in gid >= 0 ? (TilemapConfig.rawGID(gid) | flipBits) : gid } }
        }
        return b
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                leftPanel
                // Resizable drag handle
                P.border
                    .frame(width: 1)
                    .overlay(
                        Color.clear.frame(width: 8)
                            .contentShape(Rectangle())
                            .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                            .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                                leftPanelWidth = max(200, min(400, leftPanelWidth + v.translation.width))
                            })
                    )
                centerCanvas
                    .layoutPriority(1)
                    .frame(minWidth: 0, maxWidth: .infinity)

                P.border.frame(width: 1)
                rightPanel
                    .frame(width: 220)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Group {
                Button("") { undo() }.keyboardShortcut("z", modifiers: .command).opacity(0)
                Button("") { redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).opacity(0)
                Button("") { copySelection() }.keyboardShortcut("c", modifiers: .command).opacity(0)
                Button("") { pasteClipboard() }.keyboardShortcut("v", modifiers: .command).opacity(0)
                Button("") { tool = .paint    }.keyboardShortcut("b", modifiers: []).opacity(0)
                Button("") { tool = .erase    }.keyboardShortcut("e", modifiers: []).opacity(0)
                Button("") { tool = .fill     }.keyboardShortcut("f", modifiers: []).opacity(0)
                Button("") { tool = .rectFill }.keyboardShortcut("r", modifiers: []).opacity(0)
                Button("") { tool = .pan      }.keyboardShortcut("g", modifiers: []).opacity(0)
                Button("") { tool = .select   }.keyboardShortcut("s", modifiers: []).opacity(0)
                Button("") { tool = .eyedropper }.keyboardShortcut("i", modifiers: []).opacity(0)
            }
        )
        .onAppear {
            regenerate()
            savedMaps = TilemapStore.loadAll(from: projectURL)
        }
        .sheet(item: $editingAnim) { anim in
            TileAnimEditorSheet(
                animation: anim,
                tilesetImages: tilesetImages,
                tileSize: config.tileSize,
                activeTilesetIdx: activeTilesetIdx,
                selectedGID: selectedGID,
                onSave: { updated in
                    if let idx = config.animations.firstIndex(where: { $0.id == updated.id }) {
                        config.animations[idx] = updated
                    }
                    regenerate()
                    editingAnim = nil
                },
                onCancel: { editingAnim = nil }
            )
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 8) {

            // ── Map name ───────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(P.accent)
                TextField("Map name", text: $config.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 130)
                    .onChange(of: config.name) { regenerate() }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(P.field, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(P.border, lineWidth: 0.5))

            tbSep

            // ── Zoom ───────────────────────────────────────────────────────
            HStack(spacing: 1) {
                ForEach([CGFloat(1), 2, 3, 4], id: \.self) { z in
                    Button("\(Int(z))×") { zoom = z }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: zoom == z ? .semibold : .regular))
                        .frame(width: 34, height: 26)
                        .background(zoom == z ? P.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(zoom == z ? P.accent : Color.secondary)
                }
            }
            .padding(3)
            .background(P.card, in: RoundedRectangle(cornerRadius: 8))

            tbSep

            // ── Undo / Redo ────────────────────────────────────────────────
            HStack(spacing: 1) {
                tbIconBtn("arrow.uturn.backward", help: "Undo ⌘Z", disabled: undoStack.isEmpty) { undo() }
                tbIconBtn("arrow.uturn.forward",  help: "Redo ⌘⇧Z", disabled: redoStack.isEmpty) { redo() }
            }
            .padding(3)
            .background(P.card, in: RoundedRectangle(cornerRadius: 8))

            tbSep

            // ── Save / Load ────────────────────────────────────────────────
            HStack(spacing: 4) {
                Button { saveMap() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 11))
                        Text("Save").font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(P.card, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain).help("Save map")

                Menu {
                    if savedMaps.isEmpty {
                        Text("No saved maps").foregroundStyle(.secondary)
                    } else {
                        ForEach(savedMaps) { map in Button(map.name) { loadMap(map) } }
                        Divider()
                        ForEach(savedMaps) { map in
                            Button("Delete \(map.name)", role: .destructive) { deleteMap(map) }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder").font(.system(size: 11))
                        Text("Load").font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(P.card, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.secondary)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .onHover { if $0 { savedMaps = TilemapStore.loadAll(from: projectURL) } }
            }

            Spacer()

            // ── Status ─────────────────────────────────────────────────────
            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .padding(.horizontal, 8)
            }

            // ── Export PNG ─────────────────────────────────────────────────
            Button { exportPNG() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "photo.badge.arrow.down").font(.system(size: 11))
                    Text("PNG").font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(P.card, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(P.border, lineWidth: 0.5))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Export map as PNG")

            // ── Export Lua ─────────────────────────────────────────────────
            Button { exportLua() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.doc").font(.system(size: 11))
                    Text("Export Lua").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(P.accent, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain).help("Export as tiles/<name>.lua")

        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(P.sidebar)
    }

    private var tbSep: some View {
        P.border.frame(width: 1, height: 20).opacity(0.7)
    }

    @ViewBuilder
    private func tbIconBtn(_ icon: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 34, height: 26)
                .foregroundStyle(disabled ? Color(nsColor: .tertiaryLabelColor) : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(spacing: 0) {

            // ── Tilesets header ───────────────────────────────────────────
            HStack(spacing: 6) {
                sectionLabel("TILESETS", icon: "photo.stack")
                Spacer()
                Button { browseTileset() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(P.accentBg, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(P.accent)
                }
                .buttonStyle(.plain).help("Add tileset")
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            // Tileset tabs
            if config.tilesets.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(Array(config.tilesets.enumerated()), id: \.element.id) { idx, ts in
                            Button(ts.name) { activeTilesetIdx = idx }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: activeTilesetIdx == idx ? .semibold : .regular))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(activeTilesetIdx == idx ? P.accentBg : P.card,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(activeTilesetIdx == idx ? P.accent.opacity(0.4) : P.border.opacity(0.9), lineWidth: 0.5))
                                .foregroundStyle(activeTilesetIdx == idx ? P.accent : Color.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 6)
            }

            // Active tileset file info
            if !config.tilesets.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.richtext").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(config.tilesets[safe: activeTilesetIdx]?.fileName ?? "")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Remove") { removeTileset(at: activeTilesetIdx) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(P.card, in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 14).padding(.bottom, 8)
            }

            // Tileset picker zoom controls
            HStack(spacing: 4) {
                Text("Zoom").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    tilesetZoom = max(1.0, tilesetZoom - 0.5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(P.card, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(tilesetZoom <= 1.0)

                Text(String(format: "%.0f×", tilesetZoom))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(P.accent)
                    .frame(width: 26, alignment: .center)

                Button {
                    tilesetZoom = min(6.0, tilesetZoom + 0.5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .background(P.card, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .disabled(tilesetZoom >= 6.0)
            }
            .padding(.horizontal, 14).padding(.vertical, 5)

            // Tileset picker
            TilesetPickerView(
                tilesetImage: activeTilesetImage,
                tileSize: config.tileSize,
                activeTilesetIdx: activeTilesetIdx,
                scale: tilesetZoom,
                onSelectBrush: { localBrush in
                    brushPattern = localBrush.map { row in
                        row.map { TilemapConfig.encodeGID(tilesetIndex: activeTilesetIdx, localIndex: $0) }
                    }
                    selectedGID = brushPattern.first?.first ?? 0
                }
            )
            .frame(maxWidth: .infinity).frame(minHeight: 180, maxHeight: 320)
            .background(P.field)

            P.border.frame(height: 1)

            // Settings
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    settingsSection("Origin",    icon: "scope",                 expanded: $sectionOriginExpanded)   { originPickerView }
                    settingsSection("Tile Size", icon: "squareshape.split.2x2", expanded: $sectionTileSizeExpanded) { tileSizePickerView }
                    settingsSection("Map Size",  icon: "ruler",                 expanded: $sectionMapSizeExpanded)  { mapSizeView }
                    settingsSection("Layers",    icon: "square.stack",          expanded: $sectionLayersExpanded)   { layersView }
                }
                .padding(10)
            }
        }
        .frame(width: leftPanelWidth)
        .background(P.sidebar)
    }

    @ViewBuilder private var originPickerView: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(TilemapOrigin.allCases) { o in
                Button {
                    config.origin = o; regenerate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: o.icon).font(.system(size: 11))
                            .foregroundStyle(config.origin == o ? P.accent : Color.secondary)
                            .frame(width: 16)
                        Text(o.label).font(.system(size: 11))
                            .foregroundStyle(config.origin == o ? Color.primary : Color.secondary)
                        Spacer()
                        if config.origin == o {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(P.accent)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(config.origin == o ? P.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var tileSizePickerView: some View {
        HStack(spacing: 3) {
            ForEach([8, 16, 32, 48, 64], id: \.self) { sz in
                Button("\(sz)") { config.tileSize = sz }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: config.tileSize == sz ? .semibold : .regular))
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .background(config.tileSize == sz ? P.accentBg : Color(nsColor: .windowBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(config.tileSize == sz ? P.accent.opacity(0.4) : P.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(config.tileSize == sz ? P.accent : Color.secondary)
            }
        }
    }

    @ViewBuilder private var mapSizeView: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("W").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                TextField("", text: $widthStr)
                    .textFieldStyle(.plain).multilineTextAlignment(.center)
                    .font(.system(size: 12, design: .monospaced)).frame(width: 44)
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .background(P.field, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                    .onSubmit { applyMapSize() }
            }
            Text("×").font(.system(size: 12)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text("H").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                TextField("", text: $heightStr)
                    .textFieldStyle(.plain).multilineTextAlignment(.center)
                    .font(.system(size: 12, design: .monospaced)).frame(width: 44)
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .background(P.field, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                    .onSubmit { applyMapSize() }
            }
            Spacer()
            Button("Apply") { applyMapSize() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(P.accentBg, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(P.accent)
        }
        Text("\(config.mapWidth) × \(config.mapHeight) tiles")
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
    }

    @ViewBuilder private var layersView: some View {
        VStack(spacing: 4) {
            ForEach(Array(config.layers.enumerated()), id: \.element.id) { idx, layer in
                layerRow(idx: idx, layer: layer)
            }

            HStack(spacing: 6) {
                Button {
                    let n = TileLayer(name: "Layer \(config.layers.count + 1)",
                                      count: config.mapWidth * config.mapHeight)
                    config.layers.append(n)
                    activeLayer = config.layers.count - 1
                    regenerate()
                } label: {
                    Label("Add", systemImage: "plus").font(.system(size: 11))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(P.card, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    var n = TileLayer(name: "Objects \(config.layers.count + 1)",
                                      count: config.mapWidth * config.mapHeight)
                    n.layerType = .object
                    config.layers.append(n)
                    activeLayer = config.layers.count - 1
                    regenerate()
                } label: {
                    Label("+ Objects", systemImage: "mappin").font(.system(size: 11))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(P.card, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)

                if config.layers.count > 1 {
                    Button(role: .destructive) {
                        config.layers.remove(at: activeLayer)
                        activeLayer = max(0, activeLayer - 1)
                        regenerate()
                    } label: {
                        Label("Remove", systemImage: "trash").font(.system(size: 11))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(P.card, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder private func layerRow(idx: Int, layer: TileLayer) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Button {
                    let mods = NSEvent.modifierFlags
                    if mods.contains(.option) {
                        // Solo: if already soloing this layer, restore all; otherwise solo it
                        if soloLayerIndex == idx {
                            soloLayerIndex = nil
                        } else {
                            soloLayerIndex = idx
                        }
                    } else {
                        if soloLayerIndex != nil { soloLayerIndex = nil }
                        config.layers[idx].visible.toggle()
                    }
                } label: {
                    let isSolo = soloLayerIndex == idx
                    Image(systemName: isSolo ? "eye.circle.fill" : (layer.visible ? "eye.fill" : "eye.slash"))
                        .font(.system(size: 10))
                        .foregroundStyle(isSolo ? P.accent : (layer.visible ? Color.secondary : Color(nsColor: .tertiaryLabelColor)))
                }
                .buttonStyle(.plain)
                .help("Toggle visibility · ⌥ click to solo")

                Button {
                    config.layers[idx].isCollision.toggle(); regenerate()
                } label: {
                    Image(systemName: layer.isCollision ? "shield.fill" : "shield")
                        .font(.system(size: 10))
                        .foregroundStyle(layer.isCollision ? Color.red : Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.plain).help("Toggle collision")

                Button {
                    config.layers[idx].isForeground.toggle(); regenerate()
                } label: {
                    Image(systemName: layer.isForeground ? "square.2.layers.3d.top.filled" : "square.2.layers.3d")
                        .font(.system(size: 10))
                        .foregroundStyle(layer.isForeground ? Color.blue : Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.plain).help("Foreground - draws above player")

                Button {
                    config.layers[idx].isLocked.toggle()
                } label: {
                    Image(systemName: config.layers[idx].isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 10))
                        .foregroundStyle(config.layers[idx].isLocked ? Color.orange : Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.plain).help("Lock layer - prevents accidental edits")

                TextField("Layer name", text: $config.layers[idx].name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: activeLayer == idx ? .semibold : .regular))
                    .foregroundStyle(activeLayer == idx ? Color.primary : Color.secondary)
                    .onSubmit { regenerate() }

                if config.layers[idx].isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.orange.opacity(0.7))
                }

                Spacer()

                HStack(spacing: 0) {
                    Button { moveLayer(idx, by: -1) } label: {
                        Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain).disabled(idx == 0)
                    Button { moveLayer(idx, by: 1) } label: {
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain).disabled(idx == config.layers.count - 1)
                }
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }

            HStack(spacing: 6) {
                Slider(value: $config.layers[idx].opacity, in: 0...1).controlSize(.mini)
                Text("\(Int(layer.opacity * 100))%")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(layerRowFill(idx: idx, layer: layer))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(layerRowBorder(idx: idx, layer: layer), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { activeLayer = idx }
    }

    private func layerRowFill(idx: Int, layer: TileLayer) -> Color {
        if layer.isCollision {
            return Color.red.opacity(activeLayer == idx ? 0.14 : 0.06)
        } else if layer.isForeground {
            return Color.blue.opacity(activeLayer == idx ? 0.12 : 0.05)
        } else {
            return activeLayer == idx ? P.accentBg : P.card
        }
    }

    private func layerRowBorder(idx: Int, layer: TileLayer) -> Color {
        if layer.isCollision {
            return Color.red.opacity(0.4)
        } else if layer.isForeground {
            return Color.blue.opacity(0.35)
        } else {
            return activeLayer == idx ? P.accent.opacity(0.3) : P.border.opacity(0.9)
        }
    }

    // MARK: - Center canvas

    private var centerCanvas: some View {
        VStack(spacing: 0) {

            // ── Toolbar ───────────────────────────────────────────────────
            HStack(spacing: 6) {
                // Tools
                HStack(spacing: 2) {
                    ForEach(TilemapTool.allCases) { t in
                        Button { tool = t } label: {
                            Image(systemName: t.icon)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 30, height: 28)
                                .background(tool == t ? P.accentBg : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(tool == t ? P.accent : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .toolbarTooltip(t.rawValue)
                    }
                }
                .padding(3)
                .background(P.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))

                // Flip buttons
                HStack(spacing: 2) {
                    Button { brushFlipH.toggle() } label: {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 12))
                            .frame(width: 28, height: 28)
                            .background(brushFlipH ? P.accentBg : P.card, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                            .foregroundStyle(brushFlipH ? P.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .toolbarTooltip("Flip Horizontal")

                    Button { brushFlipV.toggle() } label: {
                        Image(systemName: "arrow.up.and.down")
                            .font(.system(size: 12))
                            .frame(width: 28, height: 28)
                            .background(brushFlipV ? P.accentBg : P.card, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                            .foregroundStyle(brushFlipV ? P.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .toolbarTooltip("Flip Vertical")
                }

                Button { randomBrush.toggle() } label: {
                    Image(systemName: "dice")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                        .background(randomBrush ? P.accentBg : P.card, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                        .foregroundStyle(randomBrush ? P.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .toolbarTooltip("Random Brush")

                tbSep

                // Map info
                Text("\(config.mapWidth) × \(config.mapHeight)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text("\(config.tileSize) px")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)

                Spacer()

                // Cursor
                if let (col, row) = cursorTile {
                    HStack(spacing: 4) {
                        Image(systemName: "cursorarrow").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text("C:\(col) R:\(row)")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(P.card, in: RoundedRectangle(cornerRadius: 5))
                }

                // Grid toggle
                Button { showGrid.toggle() } label: {
                    Image(systemName: showGrid ? "grid" : "grid.slash")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                        .background(showGrid ? P.accentBg : P.card, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                        .foregroundStyle(showGrid ? P.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .toolbarTooltip(showGrid ? "Hide Grid" : "Show Grid")

                Button { showMinimap.toggle() } label: {
                    Image(systemName: "map")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                        .background(showMinimap ? P.accentBg : P.card, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                        .foregroundStyle(showMinimap ? P.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .toolbarTooltip(showMinimap ? "Hide Minimap" : "Show Minimap")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(P.toolbar)

            P.border.frame(height: 1)

            ZStack(alignment: .bottomTrailing) {
                TilemapCanvasView(
                    config: $config,
                    activeLayerIndex: activeLayer,
                    brushPattern: effectiveBrush,
                    tool: tool,
                    tilesetImages: tilesetImages,
                    zoom: zoom,
                    showGrid: showGrid,
                    onChanged: { regenerate() },
                    onWillChange: { pushUndo() },
                    onCursorMoved: { cursorTile = $0 },
                    onSelectionChanged: { activeSelection = $0 },
                    onObjectSelected: { selectedObject = $0 },
                    soloLayerIndex: soloLayerIndex,
                    randomBrush: randomBrush,
                    onTilePicked: { gid in
                        brushPattern = [[gid]]
                        selectedGID  = gid
                        tool = .paint
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(P.canvas)

                if showMinimap {
                    TilemapMinimapView(config: config, tilesetImages: tilesetImages, activeLayer: activeLayer)
                        .padding(12)
                        .transition(.opacity)
                }
            }

        }
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Selected tile preview ─────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("SELECTED TILE", icon: "square.filled.on.square")

                    let (tsIdx, localIdx) = TilemapConfig.decodeGID(selectedGID)
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(P.field)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                                .frame(width: 56, height: 56)
                            if let img = activeTilesetImage,
                               let preview = tilePreviewImage(from: img) {
                                Image(nsImage: preview)
                                    .resizable().interpolation(.none).scaledToFit()
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Text("#\(localIdx)")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(P.accent)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            infoChip("Tileset", "\(tsIdx)")
                            infoChip("Tile", "#\(localIdx)")
                        }
                        Spacer()
                    }
                }
                .padding(14)

                P.border.frame(height: 1)

                tilePropertiesSection

                P.border.frame(height: 1)

                objectLayerPanel

                P.border.frame(height: 1)

                // ── Map info ──────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("MAP INFO", icon: "info.circle")
                    infoRow("Layers",    "\(config.layers.count)")
                    infoRow("Size",      "\(config.mapWidth) × \(config.mapHeight)")
                    infoRow("Tile",      "\(config.tileSize) px")
                    infoRow("Active",    config.layers.indices.contains(activeLayer)
                                         ? config.layers[activeLayer].name : "-")
                }
                .padding(14)

                P.border.frame(height: 1)

                // ── Animations ────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        sectionLabel("ANIMATIONS", icon: "sparkles")
                        Spacer()
                        // Show list popover
                        Button {
                            showAnimationsPopover = true
                        } label: {
                            HStack(spacing: 4) {
                                if !config.animations.isEmpty {
                                    Text("\(config.animations.count)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(P.accent)
                                }
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 10))
                            }
                            .frame(height: 22)
                            .padding(.horizontal, 6)
                            .background(showAnimationsPopover ? P.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(showAnimationsPopover ? P.accent : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Show animations list")
                        .popover(isPresented: $showAnimationsPopover, arrowEdge: .leading) {
                            animationsPopover
                        }

                        // Group anim toggle
                        Button {
                            showGroupAnimPanel.toggle()
                            if !showGroupAnimPanel {
                                groupAnimBlocks = []; groupAnimBlockSize = nil; groupAnimStatus = ""
                            }
                        } label: {
                            Image(systemName: "rectangle.grid.2x2")
                                .font(.system(size: 10))
                                .frame(width: 22, height: 22)
                                .background(showGroupAnimPanel ? P.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(showGroupAnimPanel ? P.accent : Color.secondary)
                        }
                        .buttonStyle(.plain).help("Group tile animation")

                        // Add single anim
                        Button {
                            let a = TileAnimation(sourceGID: selectedGID,
                                                  frames: [TileAnimFrame(gid: selectedGID, duration: 0.12)])
                            config.animations.append(a)
                            regenerate()
                            editingAnim = a
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(P.accentBg, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(P.accent)
                        }
                        .buttonStyle(.plain).help("Add animation for selected tile")
                    }

                    // Group animation builder
                    if showGroupAnimPanel {
                        P.border.frame(height: 1).padding(.vertical, 4)
                        groupAnimPanel
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 180, maxWidth: 220)
        .background(P.sidebar)
    }

    // MARK: - Tile Properties Section

    @ViewBuilder
    private var tilePropertiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                sectionLabel("TILE PROPERTIES", icon: "tag")
                Spacer()
                Button {
                    var props = config.tileProperties["\(selectedGID)"] ?? []
                    props.append(TileProperty())
                    config.tileProperties["\(selectedGID)"] = props
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(P.accentBg, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(P.accent)
                }
                .buttonStyle(.plain).help("Add property")
            }

            let props = config.tileProperties["\(selectedGID)"] ?? []
            if props.isEmpty {
                Text("No properties for this tile.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(props.enumerated()), id: \.element.id) { idx, prop in
                        HStack(spacing: 4) {
                            TextField("key", text: Binding(
                                get: { config.tileProperties["\(selectedGID)"]?[safe: idx]?.key ?? "" },
                                set: { config.tileProperties["\(selectedGID)"]?[idx].key = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 48)
                            .padding(.horizontal, 4).padding(.vertical, 3)
                            .background(P.field, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))

                            TextField("value", text: Binding(
                                get: { config.tileProperties["\(selectedGID)"]?[safe: idx]?.value ?? "" },
                                set: { config.tileProperties["\(selectedGID)"]?[idx].value = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 4).padding(.vertical, 3)
                            .background(P.field, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))

                            Picker("", selection: Binding(
                                get: { config.tileProperties["\(selectedGID)"]?[safe: idx]?.type ?? .string },
                                set: { config.tileProperties["\(selectedGID)"]?[idx].type = $0 }
                            )) {
                                ForEach(TilePropertyType.allCases, id: \.self) { t in
                                    Text(t.label).tag(t)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 52)
                            .font(.system(size: 9))

                            Button {
                                config.tileProperties["\(selectedGID)"]?.remove(at: idx)
                                if config.tileProperties["\(selectedGID)"]?.isEmpty == true {
                                    config.tileProperties.removeValue(forKey: "\(selectedGID)")
                                }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 8))
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    // MARK: - Object Layer Panel

    @ViewBuilder
    private var objectLayerPanel: some View {
        let isObjLayer = config.layers.indices.contains(activeLayer) && config.layers[activeLayer].layerType == .object
        if isObjLayer {
            let objects = config.layers[activeLayer].objects
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("OBJECTS", icon: "mappin")

                if objects.isEmpty {
                    Text("No objects. Use Paint tool to add.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 3) {
                        ForEach(objects) { obj in
                            Button {
                                selectedObject = obj
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(objectColor(for: obj.type))
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(obj.name).font(.system(size: 10, weight: .medium))
                                        Text("\(obj.type) · (\(obj.tileX),\(obj.tileY))").font(.system(size: 9)).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    if selectedObject?.id == obj.id {
                                        Image(systemName: "checkmark").font(.system(size: 8)).foregroundStyle(P.accent)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(
                                    selectedObject?.id == obj.id ? P.accentBg : P.card,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                                    selectedObject?.id == obj.id ? P.accent.opacity(0.4) : P.border.opacity(0.9),
                                    lineWidth: 0.5))
                                .foregroundStyle(Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let sel = selectedObject,
                   let objIdx = config.layers[activeLayer].objects.firstIndex(where: { $0.id == sel.id }) {
                    P.border.frame(height: 1).padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("SELECTED OBJECT", icon: "pencil")

                        HStack(spacing: 6) {
                            Text("Name").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 36, alignment: .leading)
                            TextField("name", text: $config.layers[activeLayer].objects[objIdx].name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(P.field, in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                                .onChange(of: config.layers[activeLayer].objects[objIdx].name) {
                                    if let i = config.layers[activeLayer].objects.firstIndex(where: { $0.id == sel.id }) {
                                        selectedObject = config.layers[activeLayer].objects[i]
                                    }
                                }
                        }

                        HStack(spacing: 6) {
                            Text("Type").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 36, alignment: .leading)
                            TextField("type", text: $config.layers[activeLayer].objects[objIdx].type)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(P.field, in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                                .onChange(of: config.layers[activeLayer].objects[objIdx].type) {
                                    if let i = config.layers[activeLayer].objects.firstIndex(where: { $0.id == sel.id }) {
                                        selectedObject = config.layers[activeLayer].objects[i]
                                    }
                                }
                        }

                        Text("Position: (\(config.layers[activeLayer].objects[objIdx].tileX), \(config.layers[activeLayer].objects[objIdx].tileY))")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)

                        // Object custom properties
                        HStack {
                            Text("Properties").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                if let i = config.layers[activeLayer].objects.firstIndex(where: { $0.id == sel.id }) {
                                    config.layers[activeLayer].objects[i].properties.append(TileProperty())
                                    selectedObject = config.layers[activeLayer].objects[i]
                                }
                            } label: {
                                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                                    .frame(width: 18, height: 18)
                                    .background(P.accentBg, in: RoundedRectangle(cornerRadius: 3))
                                    .foregroundStyle(P.accent)
                            }
                            .buttonStyle(.plain)
                        }

                        let objProps = config.layers[activeLayer].objects[objIdx].properties
                        ForEach(objProps) { prop in
                            HStack(spacing: 4) {
                                if let pi = config.layers[activeLayer].objects[objIdx].properties.firstIndex(where: { $0.id == prop.id }) {
                                    TextField("key", text: $config.layers[activeLayer].objects[objIdx].properties[pi].key)
                                        .textFieldStyle(.plain).font(.system(size: 10, design: .monospaced))
                                        .frame(width: 48).padding(.horizontal, 4).padding(.vertical, 3)
                                        .background(P.field, in: RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                                    TextField("value", text: $config.layers[activeLayer].objects[objIdx].properties[pi].value)
                                        .textFieldStyle(.plain).font(.system(size: 10, design: .monospaced))
                                        .frame(maxWidth: .infinity).padding(.horizontal, 4).padding(.vertical, 3)
                                        .background(P.field, in: RoundedRectangle(cornerRadius: 4))
                                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                                    Button {
                                        if let i = config.layers[activeLayer].objects[objIdx].properties.firstIndex(where: { $0.id == prop.id }) {
                                            config.layers[activeLayer].objects[objIdx].properties.remove(at: i)
                                        }
                                        if let i = config.layers[activeLayer].objects.firstIndex(where: { $0.id == sel.id }) {
                                            selectedObject = config.layers[activeLayer].objects[i]
                                        }
                                    } label: {
                                        Image(systemName: "xmark").font(.system(size: 8))
                                            .frame(width: 18, height: 18)
                                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button(role: .destructive) {
                            config.layers[activeLayer].objects.removeAll { $0.id == sel.id }
                            selectedObject = nil
                            regenerate()
                        } label: {
                            Label("Delete Object", systemImage: "trash").font(.system(size: 11))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(P.card, in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                                .foregroundStyle(Color.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
    }

    private func objectColor(for type: String) -> Color {
        switch type {
        case "spawn":   return Color.green
        case "trigger": return Color.blue
        case "npc":     return Color.purple
        default:        return Color.yellow
        }
    }

    // MARK: - Group animation panel

    // MARK: - Animations Popover

    private var animationsPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(P.accent)
                Text("ANIMATIONS")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(config.animations.count)")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            if config.animations.isEmpty {
                Text("No animations yet.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(config.animations) { anim in
                            HStack(spacing: 7) {
                                animTilePreview(gid: anim.sourceGID)
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("GID \(anim.sourceGID)")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("\(anim.frames.count) fr")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 4) {
                                    Button { editingAnim = anim } label: {
                                        Image(systemName: "pencil").font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain).foregroundStyle(Color.secondary)
                                    Button {
                                        config.animations.removeAll { $0.id == anim.id }
                                        regenerate()
                                    } label: {
                                        Image(systemName: "trash").font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain).foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(P.card, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var groupAnimPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a tile block in the tileset, then Capture. Repeat for each frame.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let size = groupAnimBlockSize {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text("\(size.w)×\(size.h) tiles per block")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }

            // Duration
            HStack(spacing: 6) {
                Text("Duration").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                TextField("", value: $groupAnimDefaultMs, format: .number)
                    .textFieldStyle(.plain).multilineTextAlignment(.center)
                    .frame(width: 40)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(P.field, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                Text("ms").font(.system(size: 10)).foregroundStyle(.tertiary)
            }

            // Captured blocks
            if !groupAnimBlocks.isEmpty {
                VStack(spacing: 3) {
                    ForEach(Array(groupAnimBlocks.enumerated()), id: \.offset) { idx, block in
                        HStack(spacing: 7) {
                            let firstGID = block.first?.first ?? -1
                            if firstGID >= 0 {
                                animTilePreview(gid: firstGID)
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            Text("Frame \(idx + 1)").font(.system(size: 10, weight: .medium))
                            Spacer()
                            Button {
                                groupAnimBlocks.remove(at: idx)
                                if groupAnimBlocks.isEmpty { groupAnimBlockSize = nil }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 8))
                            }
                            .buttonStyle(.plain).foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(P.card, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                    }
                }
            }

            if !groupAnimStatus.isEmpty {
                Text(groupAnimStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(groupAnimStatus.hasPrefix("Created") ? Color.green : P.accent)
            }

            // Action buttons
            HStack(spacing: 6) {
                Button { captureGroupBlock() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 10))
                        Text("Capture").font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .background(P.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(brushPattern.isEmpty || brushPattern.first?.isEmpty == true)

                Button {
                    groupAnimBlocks = []; groupAnimBlockSize = nil; groupAnimStatus = ""
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .frame(width: 30, height: 30)
                        .background(P.card, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
                .buttonStyle(.plain).disabled(groupAnimBlocks.isEmpty)
            }

            Button { createGroupAnimations() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    Text("Create Animations").font(.system(size: 11, weight: .semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(groupAnimBlocks.count >= 2 ? P.accent : P.card, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(groupAnimBlocks.count >= 2 ? Color.white : Color(nsColor: .tertiaryLabelColor))
            }
            .buttonStyle(.plain).disabled(groupAnimBlocks.count < 2)
        }
    }

    // MARK: - Code panel

    private var codePanel: some View {
        VStack(spacing: 0) {
            HStack {
                sectionLabel("LUA CODE", icon: "doc.text")
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(generatedCode, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                        Text(copied ? "Copied!" : "Copy").font(.system(size: 11))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(copied ? Color.green.opacity(0.12) : P.card, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(P.sidebar)

            P.border.frame(height: 1)

            ScrollView([.vertical, .horizontal]) {
                Text(generatedCode)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(P.field)
        }
    }

    // MARK: - View helpers

    @ViewBuilder
    private func settingsSection<C: View>(_ title: String, icon: String, expanded: Binding<Bool>, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                    Spacer()
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(10)
            }
        }
        .background(P.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(P.field, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private func infoChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9)).foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(P.card, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(P.border.opacity(0.9), lineWidth: 0.5))
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
        } icon: {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
    }

    // MARK: - Layer reorder

    private func moveLayer(_ index: Int, by delta: Int) {
        let newIndex = index + delta
        guard newIndex >= 0, newIndex < config.layers.count else { return }
        config.layers.swapAt(index, newIndex)
        if activeLayer == index {
            activeLayer = newIndex
        } else if activeLayer == newIndex {
            activeLayer = index
        }
        regenerate()
    }

    // MARK: - Undo / Redo

    func pushUndo() {
        undoStack.append(config.layers)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack = []
    }

    private func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(config.layers)
        config.layers = snapshot
        regenerate()
    }

    private func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(config.layers)
        config.layers = snapshot
        regenerate()
    }

    // MARK: - Copy / Paste

    private func copySelection() {
        guard let sel = activeSelection,
              config.layers.indices.contains(activeLayer) else { return }
        let layer = config.layers[activeLayer]
        let mw = config.mapWidth
        var rows: [[Int]] = []
        for dy in 0 ..< sel.h {
            var row: [Int] = []
            for dx in 0 ..< sel.w {
                let x = sel.x + dx
                let y = sel.y + dy
                guard x >= 0, x < mw, y >= 0, y < config.mapHeight else {
                    row.append(-1); continue
                }
                row.append(layer.tiles[y * mw + x])
            }
            rows.append(row)
        }
        clipboard = rows
    }

    private func pasteClipboard() {
        guard !clipboard.isEmpty,
              let sel = activeSelection,
              config.layers.indices.contains(activeLayer) else { return }
        pushUndo()
        let mw = config.mapWidth
        let mh = config.mapHeight
        for (dy, row) in clipboard.enumerated() {
            for (dx, gid) in row.enumerated() {
                let x = sel.x + dx
                let y = sel.y + dy
                guard x >= 0, x < mw, y >= 0, y < mh else { continue }
                config.layers[activeLayer].tiles[y * mw + x] = gid
            }
        }
        regenerate()
    }

    // MARK: - Actions

    private func browseTileset() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes  = [.png, .jpeg, .bmp, .gif]
        panel.message              = "Select tileset image"
        panel.allowsMultipleSelection = true
        panel.directoryURL         = projectURL
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let img = NSImage(contentsOf: url) else { continue }
            let name = url.deletingPathExtension().lastPathComponent

            let fileName: String
            let rootPath = projectURL.path
            if url.path.hasPrefix(rootPath + "/") {
                fileName = String(url.path.dropFirst(rootPath.count + 1))
            } else {
                let tilesDir = projectURL.appendingPathComponent("images")
                try? FileManager.default.createDirectory(at: tilesDir, withIntermediateDirectories: true)
                let dest = tilesDir.appendingPathComponent(url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: url, to: dest)
                }
                fileName = "images/\(url.lastPathComponent)"
            }

            let info = TilesetInfo(name: name, fileName: fileName)
            config.tilesets.append(info)
            tilesetImages.append(img)
        }
        activeTilesetIdx = max(0, config.tilesets.count - 1)
        regenerate()
    }

    private func removeTileset(at index: Int) {
        guard index < config.tilesets.count else { return }
        config.tilesets.remove(at: index)
        tilesetImages.remove(at: index)
        activeTilesetIdx = max(0, min(activeTilesetIdx, config.tilesets.count - 1))
        selectedGID = 0
        regenerate()
    }

    private func saveMap() {
        do {
            _ = try TilemapStore.save(config, to: projectURL)
            savedMaps = TilemapStore.loadAll(from: projectURL)
            saveStatus = "Saved ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = "" }
        } catch {
            saveStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func loadMap(_ map: TilemapConfig) {
        undoStack = []
        redoStack = []
        config = map
        tilesetImages = map.tilesets.map { ts in
            NSImage(contentsOf: projectURL.appendingPathComponent(ts.fileName)) ?? NSImage()
        }
        activeTilesetIdx = 0
        selectedGID = 0
        widthStr  = "\(map.mapWidth)"
        heightStr = "\(map.mapHeight)"
        regenerate()
    }

    private func deleteMap(_ map: TilemapConfig) {
        TilemapStore.delete(map, from: projectURL)
        savedMaps = TilemapStore.loadAll(from: projectURL)
    }

    private func exportLua() {
        do {
            let freshCode = TilemapCodeGenerator.generate(config: config)
            let url = try TilemapStore.exportLua(freshCode, name: config.name, to: projectURL)
            saveStatus = "Exported \(url.lastPathComponent) ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { saveStatus = "" }
        } catch {
            saveStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportPNG() {
        guard let image = renderMapToImage() else {
            saveStatus = "PNG render failed"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = "" }
            return
        }
        let panel = NSSavePanel()
        panel.title                  = "Export Map as PNG"
        panel.nameFieldStringValue   = "\(config.name).png"
        panel.allowedContentTypes    = [.png]
        panel.directoryURL           = projectURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let tiff = image.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff),
              let png  = rep.representation(using: .png, properties: [:]) else {
            saveStatus = "PNG encode failed"
            return
        }
        do {
            try png.write(to: url)
            saveStatus = "Exported \(url.lastPathComponent) ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { saveStatus = "" }
        } catch {
            saveStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func renderMapToImage() -> NSImage? {
        let ts  = config.tileSize
        let mw  = config.mapWidth
        let mh  = config.mapHeight
        let w   = mw * ts
        let h   = mh * ts
        guard w > 0, h > 0 else { return nil }

        // Pre-compute CGImages + cols per tileset
        let cgImages: [CGImage] = tilesetImages.compactMap {
            $0.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        let tsCols: [Int] = cgImages.map { max(1, Int($0.width) / ts) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.setFillColor(CGColor(gray: 0, alpha: 0))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none

        for layer in config.layers where layer.visible && !layer.isCollision {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(layer.opacity))
            for y in 0 ..< mh {
                for x in 0 ..< mw {
                    let storedGID = layer.tiles[y * mw + x]
                    guard storedGID >= 0 else { continue }
                    let fH = TilemapConfig.flipH(storedGID)
                    let fV = TilemapConfig.flipV(storedGID)
                    let gid = TilemapConfig.rawGID(storedGID)
                    let (tidx, localIdx) = TilemapConfig.decodeGID(gid)
                    guard tidx < cgImages.count else { continue }
                    let cg   = cgImages[tidx]
                    let cols = tsCols[tidx]
                    let sc   = localIdx % cols
                    let sr   = localIdx / cols
                    let srcRect = CGRect(x: sc * ts, y: sr * ts, width: ts, height: ts)
                    guard let tile = cg.cropping(to: srcRect) else { continue }
                    // CGContext Y=0 is bottom; map row 0 = top → flip
                    let destRect = CGRect(x: x * ts, y: (mh - 1 - y) * ts, width: ts, height: ts)
                    if fH || fV {
                        ctx.saveGState()
                        ctx.translateBy(x: destRect.midX, y: destRect.midY)
                        ctx.scaleBy(x: fH ? -1 : 1, y: fV ? -1 : 1)
                        ctx.translateBy(x: -CGFloat(ts) / 2, y: -CGFloat(ts) / 2)
                        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: ts, height: ts))
                        ctx.restoreGState()
                    } else {
                        ctx.draw(tile, in: destRect)
                    }
                }
            }
            ctx.restoreGState()
        }

        guard let cgOut = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgOut, size: NSSize(width: w, height: h))
    }

    private func applyMapSize() {
        let w = max(1, min(200, Int(widthStr)  ?? config.mapWidth))
        let h = max(1, min(200, Int(heightStr) ?? config.mapHeight))
        widthStr  = "\(w)"
        heightStr = "\(h)"
        config.resize(width: w, height: h)
        regenerate()
    }

    // MARK: - Group animation

    private func captureGroupBlock() {
        let block = brushPattern   // [[GID]], already encoded from tileset picker
        let w = block.first?.count ?? 0
        let h = block.count
        guard w > 0, h > 0 else {
            groupAnimStatus = "Select tiles in the tileset first"
            return
        }
        if let size = groupAnimBlockSize, (size.w != w || size.h != h) {
            groupAnimStatus = "Selection must be \(size.w)×\(size.h) tiles"
            return
        }
        if groupAnimBlockSize == nil { groupAnimBlockSize = (w, h) }
        groupAnimBlocks.append(block)
        groupAnimStatus = "Block \(groupAnimBlocks.count) captured (\(w)×\(h))"
    }

    private func createGroupAnimations() {
        guard let size = groupAnimBlockSize, groupAnimBlocks.count >= 2 else {
            groupAnimStatus = "Need at least 2 blocks"
            return
        }
        var created = 0
        for r in 0 ..< size.h {
            for c in 0 ..< size.w {
                let sourceGID = groupAnimBlocks[0][r][c]
                guard sourceGID >= 0 else { continue }
                var frames: [TileAnimFrame] = []
                for block in groupAnimBlocks {
                    let gid = block[r][c]
                    guard gid >= 0 else { continue }
                    frames.append(TileAnimFrame(gid: gid, duration: Double(groupAnimDefaultMs) / 1000.0))
                }
                guard frames.count > 1 else { continue }
                config.animations.removeAll { $0.sourceGID == sourceGID }
                config.animations.append(TileAnimation(sourceGID: sourceGID, frames: frames))
                created += 1
            }
        }
        regenerate()
        groupAnimBlocks = []
        groupAnimBlockSize = nil
        groupAnimStatus = "Created \(created) animations"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if groupAnimStatus.hasPrefix("Created") { groupAnimStatus = "" }
        }
    }

    private func regenerate() {
        generatedCode = TilemapCodeGenerator.generate(config: config)
    }

    @ViewBuilder
    private func animTilePreview(gid: Int) -> some View {
        let (tsIdx, localIdx) = TilemapConfig.decodeGID(gid)
        if tsIdx < tilesetImages.count,
           let preview = tilePreviewImage(from: tilesetImages[tsIdx], gid: gid) {
            Image(nsImage: preview)
                .resizable().interpolation(.none).scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.orange.opacity(0.3))
                .overlay(Text("\(localIdx)").font(.system(size: 7)).foregroundStyle(.orange))
        }
    }

    private func tilePreviewImage(from img: NSImage) -> NSImage? {
        tilePreviewImage(from: img, gid: selectedGID)
    }

    private func tilePreviewImage(from img: NSImage, gid: Int) -> NSImage? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let (_, localIdx) = TilemapConfig.decodeGID(gid)
        let cols = max(1, Int(cg.width) / config.tileSize)
        let col  = localIdx % cols
        let row  = localIdx / cols
        let srcRect = CGRect(x: col * config.tileSize, y: row * config.tileSize,
                              width: config.tileSize, height: config.tileSize)
        guard let cropped = cg.cropping(to: srcRect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: config.tileSize, height: config.tileSize))
    }
}

// MARK: - Tile Animation Editor Sheet

struct TileAnimEditorSheet: View {
    let tilesetImages: [NSImage]
    let tileSize: Int
    let onSave: (TileAnimation) -> Void
    let onCancel: () -> Void

    @State private var draft: TileAnimation
    @State private var pickerTilesetIdx: Int
    // default duration applied when clicking a tile in the picker
    @State private var defaultDurationMs: Int = 120

    init(animation: TileAnimation, tilesetImages: [NSImage], tileSize: Int,
         activeTilesetIdx: Int, selectedGID: Int,
         onSave: @escaping (TileAnimation) -> Void, onCancel: @escaping () -> Void) {
        self.tilesetImages    = tilesetImages
        self.tileSize         = tileSize
        self.onSave           = onSave
        self.onCancel         = onCancel
        self._draft           = State(initialValue: animation)
        self._pickerTilesetIdx = State(initialValue: min(activeTilesetIdx, max(0, tilesetImages.count - 1)))
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(.orange)
                Text("Tile Animation").font(.headline)

                // Source tile thumb
                tileThumb(gid: draft.sourceGID).frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.orange.opacity(0.5), lineWidth: 1))
                Text("Source tile").font(.caption).foregroundStyle(.secondary)

                Spacer()

                // Default duration field
                HStack(spacing: 5) {
                    Text("Default:").font(.caption2).foregroundStyle(.tertiary)
                    TextField("", value: $defaultDurationMs, format: .number)
                        .textFieldStyle(.plain).frame(width: 38)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
                    Text("ms").font(.caption2).foregroundStyle(.tertiary)
                }

                Divider().frame(height: 20)
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Button("Save") { onSave(draft) }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            Divider()

            HStack(spacing: 0) {

                // ── Left: tileset picker ─────────────────────────────────────
                VStack(spacing: 0) {
                    HStack {
                        Label("Click tile to add frame", systemImage: "cursorarrow.click")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        // Tileset tab switcher - scrollable so many tilesets don't overflow
                        if tilesetImages.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(Array(tilesetImages.enumerated()), id: \.offset) { i, _ in
                                        tilesetTabButton(index: i)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                            .frame(maxWidth: 200)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

                    // The actual tileset grid
                    if pickerTilesetIdx < tilesetImages.count {
                        TilesetFramePickerView(
                            image: tilesetImages[pickerTilesetIdx],
                            tileSize: tileSize,
                            tilesetIdx: pickerTilesetIdx,
                            onTileTapped: { gid in
                                draft.frames.append(
                                    TileAnimFrame(gid: gid,
                                                  duration: max(16, Double(defaultDurationMs)) / 1000.0)
                                )
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack {
                            Spacer()
                            Text("No tileset loaded")
                                .font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 300)
                .background(Color(nsColor: .textBackgroundColor))

                Divider()

                // ── Middle: frame sequence ───────────────────────────────────
                VStack(spacing: 0) {
                    HStack {
                        Text("Frame sequence").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(draft.frames.count) frames · \(String(format: "%.2f", draft.totalDuration))s")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

                    if draft.frames.isEmpty {
                        VStack {
                            Spacer()
                            Image(systemName: "hand.tap").font(.system(size: 28)).foregroundStyle(.tertiary)
                            Text("Click tiles on the left\nto build the sequence")
                                .font(.caption).foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(draft.frames) { frame in
                                    // Resolve current index at action time - never captured stale
                                    let idx = draft.frames.firstIndex(where: { $0.id == frame.id })
                                    if let idx {
                                        HStack(spacing: 8) {
                                            // Index
                                            Text("\(idx + 1)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 16, alignment: .trailing)

                                            // Tile thumb
                                            tileThumb(gid: frame.gid)
                                                .frame(width: 28, height: 28)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                                .overlay(RoundedRectangle(cornerRadius: 3)
                                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))

                                            // Duration field
                                            HStack(spacing: 3) {
                                                TextField("", value: Binding(
                                                    get: { Int(draft.frames[idx].duration * 1000) },
                                                    set: { newVal in
                                                        guard draft.frames.indices.contains(idx) else { return }
                                                        draft.frames[idx].duration = max(16, Double(newVal)) / 1000.0
                                                    }
                                                ), format: .number)
                                                .textFieldStyle(.plain)
                                                .frame(width: 40)
                                                .padding(.horizontal, 5).padding(.vertical, 2)
                                                .background(RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color(nsColor: .textBackgroundColor)))
                                                Text("ms").font(.caption2).foregroundStyle(.tertiary)
                                            }

                                            Spacer()

                                            // Up / Down
                                            HStack(spacing: 2) {
                                                Button {
                                                    guard let i = draft.frames.firstIndex(where: { $0.id == frame.id }), i > 0 else { return }
                                                    draft.frames.swapAt(i, i - 1)
                                                } label: { Image(systemName: "chevron.up").font(.system(size: 8, weight: .semibold)) }
                                                .buttonStyle(.plain).foregroundStyle(.secondary).disabled(idx == 0)

                                                Button {
                                                    guard let i = draft.frames.firstIndex(where: { $0.id == frame.id }), i < draft.frames.count - 1 else { return }
                                                    draft.frames.swapAt(i, i + 1)
                                                } label: { Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)) }
                                                .buttonStyle(.plain).foregroundStyle(.secondary).disabled(idx == draft.frames.count - 1)
                                            }

                                            // Delete
                                            Button {
                                                draft.frames.removeAll { $0.id == frame.id }
                                            } label: {
                                                Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.primary.opacity(0.03)))
                                    }
                                }
                            }
                            .padding(.horizontal, 8).padding(.bottom, 10)
                        }
                    }

                    Divider()
                    // Clear all
                    HStack {
                        Button {
                            draft.frames.removeAll()
                        } label: {
                            Label("Clear all", systemImage: "trash").font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .disabled(draft.frames.isEmpty)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .frame(width: 220)

                Divider()

                // ── Right: live preview ──────────────────────────────────────
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        // Flip toggles
                        flipToggle("H", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", isOn: $draft.flipH)
                        flipToggle("V", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down", isOn: $draft.flipV)
                    }
                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

                    AnimPreviewView(frames: draft.frames, tileSize: tileSize,
                                   tilesetImages: tilesetImages,
                                   flipH: draft.flipH, flipV: draft.flipV)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                    // Frame timing list
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(draft.frames.enumerated()), id: \.offset) { idx, f in
                                HStack(spacing: 6) {
                                    tileThumb(gid: f.gid).frame(width: 16, height: 16)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                    Text("F\(idx + 1)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 20)
                                    Text("\(Int(f.duration * 1000)) ms").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .frame(height: 120)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 780, height: 520)
    }

    @ViewBuilder
    func flipToggle(_ label: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
                Text(label).font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(isOn.wrappedValue ? Color.orange.opacity(0.15) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(isOn.wrappedValue ? Color.orange.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1))
            .foregroundStyle(isOn.wrappedValue ? Color.orange : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Flip \(label == "H" ? "horizontal" : "vertical")")
    }

    @ViewBuilder
    func tilesetTabButton(index i: Int) -> some View {
        let isActive = pickerTilesetIdx == i
        Button("Set \(i + 1)") { pickerTilesetIdx = i }
            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isActive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .buttonStyle(.plain)
    }

    @ViewBuilder
    func tileThumb(gid: Int) -> some View {
        let (tsIdx, localIdx) = TilemapConfig.decodeGID(gid)
        if tsIdx < tilesetImages.count,
           let cg = tilesetImages[tsIdx].cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let cols = max(1, Int(cg.width) / tileSize)
            let src  = CGRect(x: (localIdx % cols) * tileSize,
                              y: (localIdx / cols) * tileSize,
                              width: tileSize, height: tileSize)
            if let cropped = cg.cropping(to: src) {
                Image(nsImage: NSImage(cgImage: cropped,
                                       size: NSSize(width: tileSize, height: tileSize)))
                    .resizable().interpolation(.none).scaledToFill()
            } else { Color.orange.opacity(0.2) }
        } else {
            Color.orange.opacity(0.2)
                .overlay(Text("\(localIdx)").font(.system(size: 7)).foregroundStyle(.orange))
        }
    }
}

// MARK: - Tileset frame picker (click = add frame)

private struct TilesetFramePickerView: NSViewRepresentable {
    let image: NSImage
    let tileSize: Int
    let tilesetIdx: Int
    let onTileTapped: (Int) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller   = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers    = true
        sv.borderType            = .noBorder
        sv.backgroundColor       = NSColor.textBackgroundColor

        let v = TilesetFramePickerNSView()
        v.tilesetImage = image
        v.tileSize     = tileSize
        v.tilesetIdx   = tilesetIdx
        v.onTileTapped = onTileTapped
        v.frame = NSRect(origin: .zero, size: v.intrinsicContentSize)
        sv.documentView = v
        context.coordinator.view = v
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let v = context.coordinator.view else { return }
        if v.tilesetImage !== image { v.tilesetImage = image }
        v.tileSize   = tileSize
        v.tilesetIdx = tilesetIdx
        let intrinsic = v.intrinsicContentSize
        let clip      = sv.contentView.bounds.size
        let size = NSSize(width: max(intrinsic.width, clip.width),
                          height: max(intrinsic.height, clip.height))
        if v.frame.size != size { v.frame = NSRect(origin: .zero, size: size) }
        v.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { weak var view: TilesetFramePickerNSView? }
}

final class TilesetFramePickerNSView: NSView {
    var tilesetImage: NSImage? = nil { didSet { recompute(); needsDisplay = true } }
    var tileSize: Int = 16 { didSet { recompute(); needsDisplay = true } }
    var tilesetIdx: Int = 0
    var onTileTapped: ((Int) -> Void)?

    private var cgImage: CGImage?
    private var cols = 1
    private var rows = 1
    private var hoveredTile: Int? = nil
    private let scale: CGFloat = 2.0

    override var intrinsicContentSize: NSSize {
        guard let cg = cgImage else { return NSSize(width: 200, height: 200) }
        return NSSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func recompute() {
        cgImage = tilesetImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard let cg = cgImage else { return }
        cols = max(1, Int(cg.width)  / max(1, tileSize))
        rows = max(1, Int(cg.height) / max(1, tileSize))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.textBackgroundColor.cgColor)
        ctx.fill(bounds)

        guard let cg = cgImage else {
            let s = "Load a tileset first" as NSString
            s.draw(at: CGPoint(x: 12, y: bounds.midY),
                   withAttributes: [.font: NSFont.systemFont(ofSize: 11),
                                    .foregroundColor: NSColor.secondaryLabelColor])
            return
        }

        let ts   = CGFloat(tileSize) * scale
        let imgW = CGFloat(cg.width)  * scale
        let imgH = CGFloat(cg.height) * scale

        NSGraphicsContext.current?.imageInterpolation = .none
        tilesetImage?.draw(in: CGRect(x: 0, y: 0, width: imgW, height: imgH),
                           from: .zero, operation: .copy, fraction: 1.0)

        // Grid
        ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(0.5)
        for c in 0...cols { ctx.move(to: CGPoint(x: CGFloat(c)*ts, y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(c)*ts, y: imgH)) }
        for r in 0...rows { ctx.move(to: CGPoint(x: 0, y: CGFloat(r)*ts)); ctx.addLine(to: CGPoint(x: imgW, y: CGFloat(r)*ts)) }
        ctx.strokePath()

        // Hover highlight
        if let h = hoveredTile {
            let hc = h % cols, hr = h / cols
            let hx = CGFloat(hc) * ts, hy = imgH - CGFloat(hr + 1) * ts
            ctx.setFillColor(NSColor.systemOrange.withAlphaComponent(0.35).cgColor)
            ctx.fill(CGRect(x: hx, y: hy, width: ts, height: ts))
            ctx.setStrokeColor(NSColor.systemOrange.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(CGRect(x: hx + 0.75, y: hy + 0.75, width: ts - 1.5, height: ts - 1.5))
        }
    }

    private func tileIndex(for event: NSEvent) -> Int? {
        guard let cg = cgImage else { return nil }
        let loc = convert(event.locationInWindow, from: nil)
        let ts  = CGFloat(tileSize) * scale
        let imgH = CGFloat(cg.height) * scale
        let c = Int(loc.x / ts), r = Int((imgH - loc.y) / ts)
        guard c >= 0, c < cols, r >= 0, r < rows else { return nil }
        return r * cols + c
    }

    override func mouseMoved(with event: NSEvent) {
        let prev = hoveredTile
        hoveredTile = tileIndex(for: event)
        if hoveredTile != prev { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredTile = nil; needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let idx = tileIndex(for: event) else { return }
        let gid = TilemapConfig.encodeGID(tilesetIndex: tilesetIdx, localIndex: idx)
        onTileTapped?(gid)
    }
}

// MARK: - Animation Preview

private struct AnimPreviewView: NSViewRepresentable {
    let frames: [TileAnimFrame]
    let tileSize: Int
    let tilesetImages: [NSImage]
    var flipH: Bool = false
    var flipV: Bool = false

    func makeNSView(context: Context) -> AnimPreviewNSView {
        let v = AnimPreviewNSView()
        v.frames = frames
        v.tileSize = tileSize
        v.tilesetImages = tilesetImages
        v.flipH = flipH
        v.flipV = flipV
        v.startTimer()
        return v
    }

    func updateNSView(_ v: AnimPreviewNSView, context: Context) {
        v.frames = frames
        v.tileSize = tileSize
        v.tilesetImages = tilesetImages
        v.flipH = flipH
        v.flipV = flipV
        if frames.isEmpty { v.stopTimer() } else { v.startTimer() }
    }

    static func dismantleNSView(_ v: AnimPreviewNSView, coordinator: ()) {
        v.stopTimer()
    }
}

final class AnimPreviewNSView: NSView {
    var frames: [TileAnimFrame] = [] {
        didSet {
            if frameIdx >= frames.count { frameIdx = 0 }
            needsDisplay = true
        }
    }
    var tileSize: Int = 16
    var tilesetImages: [NSImage] = []
    var flipH: Bool = false { didSet { needsDisplay = true } }
    var flipV: Bool = false { didSet { needsDisplay = true } }

    private var frameIdx = 0
    private var timer: Timer?

    func startTimer() {
        stopTimer()
        guard !frames.isEmpty else { return }
        scheduleNext()
    }

    private func scheduleNext() {
        guard !frames.isEmpty else { return }
        if frameIdx >= frames.count { frameIdx = 0 }
        let dur = frames[frameIdx].duration
        timer = Timer.scheduledTimer(withTimeInterval: dur, repeats: false) { [weak self] _ in
            guard let self, !self.frames.isEmpty else { return }
            self.frameIdx = (self.frameIdx + 1) % self.frames.count
            self.needsDisplay = true
            self.scheduleNext()
        }
    }

    func stopTimer() { timer?.invalidate(); timer = nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(bounds)

        guard !frames.isEmpty else { return }
        let frame   = frames[min(frameIdx, frames.count - 1)]
        let (tsIdx, localIdx) = TilemapConfig.decodeGID(frame.gid)
        guard tsIdx < tilesetImages.count,
              let cg = tilesetImages[tsIdx].cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let cols = max(1, Int(cg.width) / tileSize)
        let col  = localIdx % cols
        let row  = localIdx / cols
        let src  = CGRect(x: col * tileSize, y: row * tileSize,
                           width: tileSize, height: tileSize)
        guard let tile = cg.cropping(to: src) else { return }

        // Draw centered, pixel-perfect, with optional H/V flip
        let scale = min(bounds.width, bounds.height) / CGFloat(tileSize)
        let tw = CGFloat(tileSize) * scale
        let th = CGFloat(tileSize) * scale
        let dest = CGRect(x: bounds.midX - tw/2, y: bounds.midY - th/2, width: tw, height: th)
        ctx.interpolationQuality = .none

        if flipH || flipV {
            ctx.saveGState()
            // Translate to center of dest, apply flip, translate back
            ctx.translateBy(x: dest.midX, y: dest.midY)
            ctx.scaleBy(x: flipH ? -1 : 1, y: flipV ? -1 : 1)
            ctx.translateBy(x: -dest.midX, y: -dest.midY)
            ctx.draw(tile, in: dest)
            ctx.restoreGState()
        } else {
            ctx.draw(tile, in: dest)
        }
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
