import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Design tokens

private enum IP {
    static let sidebar  = Color(nsColor: .controlBackgroundColor)
    static let toolbar  = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.18, alpha: 1) : NSColor(white: 0.76, alpha: 1)
    })
    static let card     = Color(nsColor: .textBackgroundColor)
    static let field    = Color(nsColor: .textBackgroundColor)
    static let border   = Color(nsColor: .separatorColor)
    static let accent   = Color.pink
    static let accentBg = Color.pink.opacity(0.14)
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
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(IP.border.opacity(0.7), lineWidth: 0.5))
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

private struct ImageCanvasView: NSViewRepresentable {
    var tool: ImageTool
    var drawColor: NSColor
    var secondaryColor: NSColor
    var brushSize: Int
    var showGrid: Bool
    @Binding var zoom: CGFloat
    var fillShapes: Bool
    var mirrorX: Bool
    var mirrorY: Bool
    var isDithering: Bool
    var showFrameGrid: Bool
    var frameGridW: Int
    var frameGridH: Int
    var onChanged:          () -> Void
    var onWillChange:       () -> Void
    var onColorPicked:      (NSColor) -> Void
    var onCursorMoved:      ((Int, Int)?) -> Void
    var onSelectionChanged: (((x:Int,y:Int,w:Int,h:Int)?) -> Void)?
    var onColorAtCursor:    ((NSColor?) -> Void)?
    var onLayersChanged:    (([ImageLayer], Int) -> Void)?
    var canvasRef:          (ImageCanvasNSView) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.hasVerticalScroller   = true
        sv.hasHorizontalScroller = true
        sv.autohidesScrollers    = true
        sv.borderType            = .noBorder
        sv.backgroundColor       = NSColor(calibratedWhite: 0.18, alpha: 1)

        let canvas = ImageCanvasNSView()
        apply(to: canvas)
        canvas.frame = NSRect(origin: .zero, size: canvas.intrinsicContentSize)
        sv.documentView = canvas
        context.coordinator.canvas = canvas
        canvasRef(canvas)

        canvas.becomeFirstResponder()
        DispatchQueue.main.async { scrollToCenter(sv: sv, canvas: canvas) }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let canvas = context.coordinator.canvas else { return }
        let prevZoom = canvas.zoom
        apply(to: canvas)
        let intrinsic = canvas.intrinsicContentSize
        let clip      = sv.contentView.bounds.size
        let size = NSSize(width:  max(intrinsic.width,  clip.width),
                          height: max(intrinsic.height, clip.height))
        if canvas.frame.size != size { canvas.frame = NSRect(origin: .zero, size: size) }
        if zoom != prevZoom { DispatchQueue.main.async { scrollToCenter(sv: sv, canvas: canvas) } }
        canvas.needsDisplay = true
    }

    private func apply(to canvas: ImageCanvasNSView) {
        canvas.tool            = tool
        canvas.drawColor       = drawColor
        canvas.secondaryColor  = secondaryColor
        canvas.brushSize       = brushSize
        canvas.showGrid        = showGrid
        canvas.zoom            = zoom
        canvas.fillShapes      = fillShapes
        canvas.mirrorX         = mirrorX
        canvas.mirrorY         = mirrorY
        canvas.isDithering     = isDithering
        canvas.showFrameGrid   = showFrameGrid
        canvas.frameGridW      = frameGridW
        canvas.frameGridH      = frameGridH
        canvas.onChanged            = { onChanged() }
        canvas.onWillChange         = { onWillChange() }
        canvas.onColorPicked        = { onColorPicked($0) }
        canvas.onCursorMoved        = { onCursorMoved($0) }
        canvas.onSelectionChanged   = onSelectionChanged
        canvas.onColorAtCursor      = onColorAtCursor
        canvas.onZoomChanged        = { newZoom in
            DispatchQueue.main.async { zoom = newZoom }
        }
        canvas.onLayersChanged = onLayersChanged
    }

    private func scrollToCenter(sv: NSScrollView, canvas: NSView) {
        let d = canvas.frame.size, c = sv.contentView.bounds.size
        sv.contentView.scroll(to: CGPoint(x: max(0,(d.width-c.width)/2),
                                          y: max(0,(d.height-c.height)/2)))
        sv.reflectScrolledClipView(sv.contentView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { weak var canvas: ImageCanvasNSView? }
}

// MARK: - New Image Sheet

private struct NewImageSheet: View {
    @State private var widthStr  = "32"
    @State private var heightStr = "32"
    @State private var fillColor = Color.white
    var onCreate: (Int, Int, NSColor) -> Void
    var onCancel: () -> Void

    private let presets = [(8,8),(16,16),(32,32),(64,64),(128,128),(256,256)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.badge.plus").foregroundStyle(.pink)
                Text("New Image").font(.headline)
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(presets, id: \.0) { w, h in
                    Button("\(w)×\(h)") {
                        widthStr = "\(w)"; heightStr = "\(h)"
                    }
                    .buttonStyle(.bordered).font(.caption2)
                    .tint(widthStr == "\(w)" && heightStr == "\(h)" ? .pink : .secondary)
                }
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width").font(.caption2).foregroundStyle(.secondary)
                    TextField("W", text: $widthStr)
                        .textFieldStyle(.plain).frame(width: 60)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor)))
                }
                Text("×").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height").font(.caption2).foregroundStyle(.secondary)
                    TextField("H", text: $heightStr)
                        .textFieldStyle(.plain).frame(width: 60)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor)))
                }
                Text("px").foregroundStyle(.tertiary).font(.caption)
            }

            HStack(spacing: 8) {
                Text("Fill").font(.caption2).foregroundStyle(.secondary)
                ColorPicker("", selection: $fillColor, supportsOpacity: true).labelsHidden()
                Button("Transparent") { fillColor = .clear }.font(.caption2).buttonStyle(.bordered)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Button("Create") {
                    let w = max(1, min(2048, Int(widthStr)  ?? 32))
                    let h = max(1, min(2048, Int(heightStr) ?? 32))
                    onCreate(w, h, NSColor(fillColor))
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Resize Sheet

private struct ResizeSheet: View {
    let currentW: Int
    let currentH: Int
    @State private var widthStr:  String
    @State private var heightStr: String
    @State private var keepAspect = true
    var onResize: (Int, Int) -> Void
    var onCancel: () -> Void

    init(currentW: Int, currentH: Int, onResize: @escaping (Int, Int) -> Void, onCancel: @escaping () -> Void) {
        self.currentW = currentW
        self.currentH = currentH
        self._widthStr  = State(initialValue: "\(currentW)")
        self._heightStr = State(initialValue: "\(currentH)")
        self.onResize = onResize
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.pink)
                Text("Resize Image").font(.headline)
                Spacer()
            }

            Text("Current: \(currentW) × \(currentH) px")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width").font(.caption2).foregroundStyle(.secondary)
                    TextField("W", text: $widthStr)
                        .textFieldStyle(.plain).frame(width: 70)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor)))
                        .onChange(of: widthStr) { _, val in
                            guard keepAspect, let w = Int(val), w > 0, currentW > 0 else { return }
                            let h = max(1, Int(round(Double(w) * Double(currentH) / Double(currentW))))
                            heightStr = "\(h)"
                        }
                }
                Text("×").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height").font(.caption2).foregroundStyle(.secondary)
                    TextField("H", text: $heightStr)
                        .textFieldStyle(.plain).frame(width: 70)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor)))
                        .onChange(of: heightStr) { _, val in
                            guard keepAspect, let h = Int(val), h > 0, currentH > 0 else { return }
                            let w = max(1, Int(round(Double(h) * Double(currentW) / Double(currentH))))
                            widthStr = "\(w)"
                        }
                }
                Text("px").foregroundStyle(.tertiary).font(.caption)
            }

            Toggle("Keep aspect ratio", isOn: $keepAspect).font(.caption2)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Button("Resize") {
                    let w = max(1, min(4096, Int(widthStr)  ?? currentW))
                    let h = max(1, min(4096, Int(heightStr) ?? currentH))
                    onResize(w, h)
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

// MARK: - Project Image Picker Sheet

private struct ProjectImageEntry: Identifiable {
    let id = UUID()
    let name: String
    let dir: URL
    var thumbnail: NSImage? = nil
}

private struct ProjectImagePickerSheet: View {
    let projectURL: URL
    var onPick: (String) -> Void
    var onCancel: () -> Void

    @State private var entries: [ProjectImageEntry] = []
    @State private var selected: String? = nil
    @State private var loaded = false

    private let columns = [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "photo.stack").foregroundStyle(.pink)
                Text("Load from Project").font(.headline)
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
            }

            if !loaded {
                ProgressView("Scanning…").frame(maxWidth: .infinity, minHeight: 120)
            } else if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("No saved images found in .love-studio/images/")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(entries) { entry in
                            let isSelected = selected == entry.name
                            VStack(spacing: 5) {
                                Group {
                                    if let img = entry.thumbnail {
                                        Image(nsImage: img)
                                            .resizable()
                                            .interpolation(.none)
                                            .aspectRatio(contentMode: .fit)
                                    } else {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.15))
                                            .overlay(Image(systemName: "photo")
                                                .foregroundStyle(.secondary.opacity(0.5)))
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .background(Color(nsColor: NSColor(white: 0.2, alpha: 1)))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? Color.pink : Color.primary.opacity(0.15),
                                                lineWidth: isSelected ? 2 : 0.5)
                                )

                                Text(entry.name)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(isSelected ? .pink : .primary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selected = entry.name }
                        }
                    }
                    .padding(4)
                }
                .frame(minHeight: 180, maxHeight: 360)
            }

            Divider()

            HStack {
                Spacer()
                Button("Open") {
                    if let name = selected { onPick(name) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { scanEntries() }
    }

    private func scanEntries() {
        let imagesDir = projectURL
            .appendingPathComponent(".love-studio")
            .appendingPathComponent("images")
        let fm = FileManager.default
        guard let subs = try? fm.contentsOfDirectory(
            at: imagesDir, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { loaded = true; return }

        var result: [ProjectImageEntry] = []
        for sub in subs {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: sub.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            // Try to load thumbnail: prefer {name}.png inside folder, else first layer PNG
            let name = sub.lastPathComponent
            var thumb: NSImage? = nil
            let flatPNG = sub.appendingPathComponent("\(name).png")
            if fm.fileExists(atPath: flatPNG.path) {
                thumb = NSImage(contentsOf: flatPNG)
            }
            if thumb == nil {
                if let files = try? fm.contentsOfDirectory(atPath: sub.path),
                   let layerFile = files.first(where: { $0.hasPrefix("layer_") && $0.hasSuffix(".png") }) {
                    thumb = NSImage(contentsOf: sub.appendingPathComponent(layerFile))
                }
            }
            result.append(ProjectImageEntry(name: name, dir: sub, thumbnail: thumb))
        }

        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        entries = result
        loaded = true
    }
}

// MARK: - Color Replace Popover

private struct ColorReplacePopover: View {
    @Binding var fromColor: Color
    @Binding var toColor: Color
    @Binding var tolerance: Double
    var onApply: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "eyedropper.halffull").foregroundStyle(.pink)
                Text("Color Replace").font(.headline)
                Spacer()
            }

            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("From").font(.caption2).foregroundStyle(.secondary)
                    ColorPicker("", selection: $fromColor, supportsOpacity: true)
                        .labelsHidden().frame(width: 44, height: 28)
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    Text("To").font(.caption2).foregroundStyle(.secondary)
                    ColorPicker("", selection: $toColor, supportsOpacity: true)
                        .labelsHidden().frame(width: 44, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Tolerance").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(tolerance))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $tolerance, in: 0...128, step: 1)
                    .tint(IP.accent)
            }

            Divider()

            HStack {
                Button("Cancel", action: onDismiss).buttonStyle(.bordered)
                Spacer()
                Button("Apply") { onApply(); onDismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - Main Editor

struct ImageEditorView: View {
    let projectURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var canvas: ImageCanvasNSView? = nil

    // Layer state
    @State private var layers: [ImageLayer] = []
    @State private var activeLayerIndex: Int = 0
    @State private var imageName: String = "untitled"

    // Tool state
    @State private var tool:       ImageTool = .pencil
    @State private var fgColor:    Color     = .black
    @State private var bgColor:    Color     = .white
    @State private var brushSize:  Int       = 1
    @State private var zoom:       CGFloat   = 8
    @State private var showGrid:   Bool      = true
    @State private var fillShapes: Bool      = false
    @State private var mirrorX:    Bool      = false
    @State private var mirrorY:    Bool      = false
    @State private var isDithering: Bool     = false

    // HSB state (driven from fgColor)
    @State private var hsbHue:        Double = 0
    @State private var hsbSat:        Double = 0
    @State private var hsbBri:        Double = 0
    @State private var hsbAlpha:      Double = 1
    @State private var updatingHSB:   Bool   = false

    // Feature 1: Hex color input
    @State private var hexString: String = "000000"
    @State private var updatingHex: Bool = false

    // Color history (last 8 used)
    @State private var colorHistory:  [Color] = []

    private let panelWidth: CGFloat = 300

    // UI state
    @State private var canUndo        = false
    @State private var canRedo        = false
    @State private var cursorPos:     (Int, Int)? = nil
    @State private var selectionInfo: (x:Int,y:Int,w:Int,h:Int)? = nil
    @State private var imageSize:     (Int, Int)  = (0, 0)
    @State private var saveStatus     = ""
    @State private var showNew           = false
    @State private var showResize        = false
    @State private var showColorReplace  = false
    @State private var showProjectLoad   = false
    @State private var currentURL:    URL? = nil

    // Feature 3: Tile preview
    @State private var showTilePreview = false
    @State private var tilePreviewRefresh = 0

    // Feature 4: Cursor color
    @State private var cursorColor: NSColor? = nil

    // Feature 6: Fit to window
    @State private var canvasViewSize: CGSize = .zero

    // Feature 8: Frame grid
    @State private var showFrameGrid = false
    @State private var frameGridW = 16
    @State private var frameGridH = 16
    @State private var frameGridWStr = "16"
    @State private var frameGridHStr = "16"

    // Color replace state
    @State private var replaceFrom:   Color  = .black
    @State private var replaceTo:     Color  = .white
    @State private var replaceTol:    Double = 0

    // Feature 2: Custom palette
    private let defaultPalette: [Color] = [
        .black, .white,
        Color(nsColor: NSColor(calibratedRed: 0.93, green: 0.21, blue: 0.22, alpha: 1)),
        Color(nsColor: NSColor(calibratedRed: 0.21, green: 0.65, blue: 0.29, alpha: 1)),
        Color(nsColor: NSColor(calibratedRed: 0.21, green: 0.47, blue: 0.88, alpha: 1)),
        Color(nsColor: NSColor(calibratedRed: 1.00, green: 0.76, blue: 0.03, alpha: 1)),
        Color(nsColor: NSColor(calibratedRed: 1.00, green: 0.50, blue: 0.00, alpha: 1)),
        Color(nsColor: NSColor(calibratedRed: 0.60, green: 0.20, blue: 0.80, alpha: 1)),
        Color(nsColor: NSColor(calibratedRed: 0.00, green: 0.74, blue: 0.83, alpha: 1)),
        Color(nsColor: NSColor(calibratedRed: 0.95, green: 0.61, blue: 0.73, alpha: 1)),
        Color(nsColor: NSColor(calibratedRed: 0.42, green: 0.27, blue: 0.18, alpha: 1)),
        Color(nsColor: NSColor(calibratedWhite: 0.5, alpha: 1)),
    ]
    @State private var customPalette: [Color] = []
    @State private var swatchHovering: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            IP.border.frame(height: 1)
            HStack(spacing: 0) {
                leftPanel
                    .frame(width: panelWidth)
                IP.border.frame(width: 1)
                canvasArea
                IP.border.frame(width: 1)
                rightPanel
                    .frame(width: 300)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(
            Group {
                Button("") { canvas?.undo(); syncUndoState() }
                    .keyboardShortcut("z", modifiers: .command).opacity(0)
                Button("") { canvas?.redo(); syncUndoState() }
                    .keyboardShortcut("z", modifiers: [.command, .shift]).opacity(0)
                Button("") { canvas?.copySelection() }
                    .keyboardShortcut("c", modifiers: .command).opacity(0)
                Button("") { canvas?.pasteClipboard(); syncUndoState() }
                    .keyboardShortcut("v", modifiers: .command).opacity(0)
                Button("") { tool = .pencil }.keyboardShortcut("b", modifiers: []).opacity(0)
                Button("") { tool = .eraser }.keyboardShortcut("e", modifiers: []).opacity(0)
                Button("") { tool = .fill }.keyboardShortcut("f", modifiers: []).opacity(0)
                Button("") { tool = .eyedropper }.keyboardShortcut("i", modifiers: []).opacity(0)
                Button("") { tool = .line }.keyboardShortcut("l", modifiers: []).opacity(0)
                Button("") { tool = .rectangle }.keyboardShortcut("r", modifiers: []).opacity(0)
                Button("") { tool = .ellipse }.keyboardShortcut("o", modifiers: []).opacity(0)
                Button("") { tool = .select }.keyboardShortcut("s", modifiers: []).opacity(0)
                Button("") { tool = .pan }.keyboardShortcut("g", modifiers: []).opacity(0)
                Button("") { let t = fgColor; fgColor = bgColor; bgColor = t }.keyboardShortcut("x", modifiers: []).opacity(0)
            }
        )
        .sheet(isPresented: $showNew) {
            NewImageSheet(
                onCreate: { w, h, fill in
                    canvas?.newImage(width: w, height: h, fill: fill)
                    imageSize = (w, h)
                    currentURL = nil
                    syncUndoState()
                    showNew = false
                },
                onCancel: { showNew = false }
            )
        }
        .sheet(isPresented: $showProjectLoad) {
            ProjectImagePickerSheet(
                projectURL: projectURL,
                onPick: { name in
                    showProjectLoad = false
                    loadProjectImage(name: name)
                },
                onCancel: { showProjectLoad = false }
            )
        }
        .sheet(isPresented: $showResize) {
            ResizeSheet(
                currentW: imageSize.0,
                currentH: imageSize.1,
                onResize: { w, h in
                    canvas?.pushUndo()
                    canvas?.resize(newWidth: w, newHeight: h)
                    imageSize = (w, h)
                    syncUndoState()
                    showResize = false
                },
                onCancel: { showResize = false }
            )
        }
        .onChange(of: fgColor) { _, newColor in
            guard !updatingHSB else { return }
            decomposeFgToHSB(newColor)
            // Feature 1: sync hex
            if !updatingHex {
                hexString = hexFromColor(newColor)
            }
        }
        .onChange(of: frameGridWStr) { _, v in
            if let val = Int(v), val > 0 { frameGridW = val }
        }
        .onChange(of: frameGridHStr) { _, v in
            if let val = Int(v), val > 0 { frameGridH = val }
        }
        .onAppear {
            customPalette = defaultPalette
            loadPalette()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            // Title
            HStack(spacing: 6) {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(IP.accent)
                Text("Image Editor")
                    .font(.system(size: 13, weight: .semibold))
            }

            tbSep

            // New / Load / Save
            Button { showNew = true } label: {
                Label("New", systemImage: "doc.badge.plus")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .toolbarTooltip("New Image")

            Button { showProjectLoad = true } label: {
                Label("Load", systemImage: "photo.stack")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .toolbarTooltip("Load from project (.love-studio)")

            Button { importImage() } label: {
                Label("Import", systemImage: "square.and.arrow.down.on.square")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .toolbarTooltip("Import image from disk")

            Button { saveWithLayers() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 11))
                    Text("Save").font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(IP.accent, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(canvas == nil || imageSize == (0, 0))
            .toolbarTooltip("Save Image")

            Button { exportPNG() } label: {
                Label("Export", systemImage: "arrow.up.doc")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(canvas == nil || imageSize == (0, 0))
            .toolbarTooltip("Export as PNG")

            // Feature 7: Save As
            Button { saveImageAs() } label: {
                Label("Save As", systemImage: "square.and.arrow.down.on.square")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(canvas == nil || imageSize == (0, 0))
            .toolbarTooltip("Save As…")

            if !saveStatus.isEmpty {
                Text(saveStatus).font(.caption2).foregroundStyle(.secondary)
            }

            tbSep

            // Flip / Rotate
            HStack(spacing: 1) {
                tbIconBtn("arrow.left.and.right.righttriangle.left.righttriangle.right",
                          help: "Flip Horizontal") {
                    canvas?.pushUndo(); canvas?.flipHorizontal(); syncUndoState()
                }
                tbIconBtn("arrow.up.and.down.righttriangle.up.righttriangle.down",
                          help: "Flip Vertical") {
                    canvas?.pushUndo(); canvas?.flipVertical(); syncUndoState()
                }
                tbIconBtn("rotate.right", help: "Rotate 90° CW") {
                    canvas?.pushUndo(); canvas?.rotate90CW(); syncUndoState()
                }
                tbIconBtn("rotate.left", help: "Rotate 90° CCW") {
                    canvas?.pushUndo(); canvas?.rotate90CCW(); syncUndoState()
                }
            }
            .padding(3)
            .background(IP.card, in: RoundedRectangle(cornerRadius: 8))
            .disabled(imageSize == (0, 0))

            tbSep

            // Outline
            Button {
                canvas?.addOutline(outlineColor: NSColor(fgColor))
                syncUndoState()
            } label: {
                Label("Outline", systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(imageSize == (0, 0))
            .toolbarTooltip("Add 1px outline using FG color")

            // Color Replace
            Button {
                replaceFrom = fgColor
                showColorReplace = true
            } label: {
                Label("Replace", systemImage: "eyedropper.halffull")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(imageSize == (0, 0))
            .toolbarTooltip("Replace color across image")
            .popover(isPresented: $showColorReplace, arrowEdge: .bottom) {
                ColorReplacePopover(
                    fromColor: $replaceFrom,
                    toColor:   $replaceTo,
                    tolerance: $replaceTol,
                    onApply: {
                        canvas?.replaceColor(from: NSColor(replaceFrom),
                                             to:   NSColor(replaceTo),
                                             tolerance: Int(replaceTol))
                        syncUndoState()
                    },
                    onDismiss: { showColorReplace = false }
                )
            }

            // Resize
            Button { showResize = true } label: {
                Label("Resize", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .disabled(imageSize == (0, 0))
            .toolbarTooltip("Resize Image")

            Spacer(minLength: 8)

            if imageSize != (0, 0) {
                Text("\(imageSize.0) × \(imageSize.1) px")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            tbSep

            // Zoom
            HStack(spacing: 1) {
                ForEach([CGFloat(1), 2, 4, 8, 16], id: \.self) { z in
                    Button("\(Int(z))×") { zoom = z }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: zoom == z ? .semibold : .regular))
                        .frame(width: 34, height: 26)
                        .background(zoom == z ? IP.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(zoom == z ? IP.accent : Color.secondary)
                }
            }
            .padding(3)
            .background(IP.card, in: RoundedRectangle(cornerRadius: 8))

            // Feature 6: Fit button
            Button {
                guard imageSize != (0, 0) else { return }
                let fitZoom = min(canvasViewSize.width / CGFloat(imageSize.0),
                                  canvasViewSize.height / CGFloat(imageSize.1))
                zoom = max(1, min(16, floor(fitZoom)))
            } label: {
                Image(systemName: "aspectratio")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(imageSize == (0, 0))
            .toolbarTooltip("Fit to Window")

            tbSep

            // Grid toggle
            Button { showGrid.toggle() } label: {
                Image(systemName: showGrid ? "grid" : "grid.slash")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(showGrid ? IP.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(showGrid ? IP.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .toolbarTooltip("Toggle Grid")

            // Feature 3: Tile preview toggle
            Button { showTilePreview.toggle() } label: {
                Image(systemName: "squareshape.split.3x3")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(showTilePreview ? IP.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(showTilePreview ? IP.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .toolbarTooltip("Tile Preview")

            // Feature 8: Frame grid toggle in toolbar
            Button { showFrameGrid.toggle() } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(showFrameGrid ? IP.accentBg : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(showFrameGrid ? IP.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .toolbarTooltip("Frame Grid Overlay")

            tbSep

            // Undo / Redo
            HStack(spacing: 1) {
                tbIconBtn("arrow.uturn.backward", help: "Undo ⌘Z", disabled: !canUndo) {
                    canvas?.undo(); syncUndoState()
                }
                tbIconBtn("arrow.uturn.forward", help: "Redo ⌘⇧Z", disabled: !canRedo) {
                    canvas?.redo(); syncUndoState()
                }
            }
            .padding(3)
            .background(IP.card, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: false)
        }
        .background(IP.toolbar)
    }

    private var tbSep: some View {
        IP.border.frame(width: 1, height: 20).opacity(0.7)
    }

    @ViewBuilder
    private func tbIconBtn(_ icon: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(disabled ? Color(nsColor: .tertiaryLabelColor) : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .toolbarTooltip(help)
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Colors ──────────────────────────────────────────────
                sectionHeader("Colors", icon: "paintpalette.fill")

                VStack(spacing: 10) {
                    // FG / BG swatches
                    HStack(spacing: 0) {
                        // Stacked swatches
                        ZStack(alignment: .topLeading) {
                            // BG square (back)
                            ColorPicker("", selection: $bgColor, supportsOpacity: true)
                                .labelsHidden()
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(bgColor)
                                        .frame(width: 30, height: 30)
                                        .overlay(RoundedRectangle(cornerRadius: 5)
                                            .stroke(IP.border, lineWidth: 1))
                                )
                                .offset(x: 18, y: 18)
                                .opacity(0.001)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(bgColor)
                                        .frame(width: 30, height: 30)
                                        .overlay(RoundedRectangle(cornerRadius: 5)
                                            .stroke(IP.border, lineWidth: 1))
                                        .offset(x: 18, y: 18)
                                        .allowsHitTesting(false)
                                )

                            // FG square (front)
                            ColorPicker("", selection: $fgColor, supportsOpacity: true)
                                .labelsHidden()
                                .frame(width: 38, height: 38)
                                .opacity(0.001)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(fgColor)
                                        .frame(width: 38, height: 38)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(IP.border, lineWidth: 1.5)
                                        )
                                        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                                        .allowsHitTesting(false)
                                )
                        }
                        .frame(width: 58, height: 58)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            // Swap button
                            Button {
                                let tmp = fgColor
                                fgColor = bgColor
                                bgColor = tmp
                            } label: {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 22)
                                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Swap FG ↔ BG  (X)")

                            // Reset to black/white
                            Button {
                                fgColor = .black; bgColor = .white
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 22)
                                    .background(IP.card, in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Reset to Black / White")
                        }
                    }
                    .padding(.bottom, 2)

                    // FG/BG labels
                    HStack(spacing: 0) {
                        Text("FG").font(.system(size: 9)).foregroundStyle(.secondary)
                        Spacer()
                        Text("BG").font(.system(size: 9)).foregroundStyle(.secondary).offset(x: -4)
                    }
                    .padding(.top, -6)

                    IP.border.frame(height: 1).padding(.vertical, 2)

                    // HSB Sliders
                    VStack(spacing: 4) {
                        hsbRow("H", value: $hsbHue,   displayValue: "\(Int(hsbHue * 360))°")
                        hsbRow("S", value: $hsbSat,   displayValue: "\(Int(hsbSat * 100))%")
                        hsbRow("B", value: $hsbBri,   displayValue: "\(Int(hsbBri * 100))%")
                        hsbRow("A", value: $hsbAlpha, displayValue: "\(Int(hsbAlpha * 100))%")
                    }

                    // Feature 1: Hex color input
                    HStack(spacing: 4) {
                        Text("#")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        TextField("000000", text: $hexString)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(IP.field, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                            .onSubmit {
                                if let color = colorFromHex(hexString) {
                                    updatingHex = true
                                    fgColor = color
                                    updatingHex = false
                                }
                            }
                            .onChange(of: hexString) { _, val in
                                // Clamp to 6 chars
                                if val.count > 6 {
                                    hexString = String(val.prefix(6))
                                }
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                sectionDivider()

                // ── History ──────────────────────────────────────────────
                if !colorHistory.isEmpty {
                    sectionHeader("History", icon: "clock")
                    colorSwatchGrid(colors: colorHistory, columns: 10, size: 22) { i in
                        addToHistory(fgColor)
                        fgColor = colorHistory[i]
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    sectionDivider()
                }

                // ── Palette ──────────────────────────────────────────────
                sectionHeader("Palette", icon: "swatchpalette") {
                    // Feature 2: Add fgColor to palette
                    Button {
                        customPalette.append(fgColor)
                        savePalette()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(IP.card, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Add current FG color to palette")
                }

                // Feature 2: Custom palette with remove on hover
                customPaletteGrid
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)

                sectionDivider()

                // ── Tools ─────────────────────────────────────────────────
                sectionHeader("Tools", icon: "pencil.and.ruler")
                VStack(spacing: 6) {
                    let cols = 4
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: cols),
                        spacing: 4
                    ) {
                        ForEach(ImageTool.allCases) { t in
                            Button {
                                tool = t
                                if t != .pencil && t != .eraser { isDithering = false }
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: t.icon)
                                        .font(.system(size: 13))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(tool == t ? IP.accentBg : IP.card)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(tool == t ? IP.accent.opacity(0.6) : IP.border.opacity(0.5), lineWidth: tool == t ? 1 : 0.5)
                                )
                                .foregroundStyle(tool == t ? IP.accent : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(t.rawValue)
                        }
                    }

                    // Contextual toggles
                    if tool == .rectangle || tool == .ellipse {
                        toggleChip(
                            fillShapes ? "Filled" : "Outline",
                            icon: fillShapes ? "rectangle.fill" : "rectangle",
                            active: fillShapes
                        ) { fillShapes.toggle() }
                    }
                    if tool == .pencil || tool == .eraser {
                        toggleChip(
                            isDithering ? "Dither ON" : "Dither",
                            icon: "checkerboard.rectangle",
                            active: isDithering
                        ) { isDithering.toggle() }
                        .help("Alternates FG/BG colors in checkerboard pattern")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                sectionDivider()

                // ── Brush ─────────────────────────────────────────────────
                sectionHeader("Brush", icon: "circle.fill")
                HStack(spacing: 6) {
                    ForEach([1, 2, 3, 4, 6, 8], id: \.self) { s in
                        Button { brushSize = s } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(brushSize == s ? IP.accentBg : IP.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(brushSize == s ? IP.accent.opacity(0.6) : IP.border.opacity(0.5),
                                                    lineWidth: brushSize == s ? 1 : 0.5)
                                    )
                                    .frame(width: 30, height: 30)
                                Circle()
                                    .fill(brushSize == s ? IP.accent : Color.primary.opacity(0.7))
                                    .frame(width: min(CGFloat(s) * 2.5, 22),
                                           height: min(CGFloat(s) * 2.5, 22))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("\(s)px")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                sectionDivider()

                // ── Frame Grid (Feature 8) ─────────────────────────────────
                sectionHeader("Frame Grid", icon: "square.grid.2x2")
                VStack(spacing: 6) {
                    toggleChip(
                        showFrameGrid ? "Enabled" : "Disabled",
                        icon: "square.grid.2x2",
                        active: showFrameGrid
                    ) { showFrameGrid.toggle() }

                    if showFrameGrid {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("W").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                                TextField("16", text: $frameGridWStr)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 6).padding(.vertical, 4)
                                    .background(IP.field, in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("H").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                                TextField("16", text: $frameGridHStr)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 6).padding(.vertical, 4)
                                    .background(IP.field, in: RoundedRectangle(cornerRadius: 5))
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                sectionDivider()

                // ── Mirror ────────────────────────────────────────────────
                sectionHeader("Mirror", icon: "rectangle.on.rectangle.slash")
                HStack(spacing: 6) {
                    mirrorChip("X", icon: "arrow.left.and.right", active: mirrorX) { mirrorX.toggle() }
                        .help("Mirror horizontally")
                    mirrorChip("Y", icon: "arrow.up.and.down", active: mirrorY) { mirrorY.toggle() }
                        .help("Mirror vertically")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                // ── Cursor ────────────────────────────────────────────────
                if let (x, y) = cursorPos {
                    sectionDivider()
                    HStack(spacing: 6) {
                        Image(systemName: "cursorarrow").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("x: \(x)   y: \(y)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)

                        // Feature 4: Color swatch and hex at cursor
                        if let cc = cursorColor {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(nsColor: cc))
                                .frame(width: 12, height: 12)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(IP.border, lineWidth: 0.5))
                            Text(nsColorToHex(cc))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                Spacer(minLength: 16)
            }
        }
        .background(IP.sidebar)
    }

    // MARK: - Feature 2: Custom palette grid

    private var customPaletteGrid: some View {
        let size: CGFloat = 24
        let columns = 8
        let spacing: CGFloat = 4
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(size), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(customPalette.indices, id: \.self) { i in
                ZStack(alignment: .topTrailing) {
                    Button {
                        addToHistory(fgColor)
                        fgColor = customPalette[i]
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(customPalette[i])
                            .frame(width: size, height: size)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(fgColor == customPalette[i]
                                            ? IP.accent : Color.primary.opacity(0.2),
                                            lineWidth: fgColor == customPalette[i] ? 2 : 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    // Remove button on hover
                    if swatchHovering.contains(i) {
                        Button {
                            customPalette.remove(at: i)
                            swatchHovering.remove(i)
                            savePalette()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 10, height: 10)
                                .background(Color.black.opacity(0.7), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 3, y: -3)
                    }
                }
                .onHover { hovering in
                    if hovering {
                        swatchHovering.insert(i)
                    } else {
                        swatchHovering.remove(i)
                    }
                }
            }
        }
    }

    // MARK: - Panel sub-views

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(IP.accent.opacity(0.8))
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .default))
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func sectionDivider() -> some View {
        IP.border.frame(height: 1)
    }

    @ViewBuilder
    private func colorSwatchGrid(colors: [Color], columns: Int, size: CGFloat,
                                  onTap: @escaping (Int) -> Void) -> some View {
        let spacing: CGFloat = 4
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: spacing), count: columns),
                  spacing: spacing) {
            ForEach(colors.indices, id: \.self) { i in
                Button { onTap(i) } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colors[i])
                        .frame(width: size, height: size)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(fgColor == colors[i]
                                        ? IP.accent : Color.primary.opacity(0.2),
                                        lineWidth: fgColor == colors[i] ? 2 : 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func hsbRow(_ label: String, value: Binding<Double>, displayValue: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 11, alignment: .leading)

            Slider(value: value, in: 0...1)
                .tint(IP.accent)
                .controlSize(.mini)
                .onChange(of: value.wrappedValue) { _, _ in rebuildFgFromHSB() }

            Text(displayValue)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func toggleChip(_ label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 10))
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? IP.accentBg : IP.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(active ? IP.accent.opacity(0.5) : IP.border.opacity(0.5), lineWidth: active ? 1 : 0.5)
            )
            .foregroundStyle(active ? IP.accent : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mirrorChip(_ label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 10, weight: .semibold))
            }
            .frame(width: 52, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? IP.accentBg : IP.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(active ? IP.accent.opacity(0.5) : IP.border.opacity(0.5), lineWidth: active ? 1 : 0.5)
            )
            .foregroundStyle(active ? IP.accent : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionButton(_ icon: String, label: String, destructive: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 8))
            }
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(IP.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Canvas area

    private var canvasArea: some View {
        ZStack {
            ImageCanvasView(
                tool:           tool,
                drawColor:      NSColor(fgColor),
                secondaryColor: NSColor(bgColor),
                brushSize:      brushSize,
                showGrid:       showGrid,
                zoom:           $zoom,
                fillShapes:     fillShapes,
                mirrorX:        mirrorX,
                mirrorY:        mirrorY,
                isDithering:    isDithering,
                showFrameGrid:  showFrameGrid,
                frameGridW:     frameGridW,
                frameGridH:     frameGridH,
                onChanged:     {
                    syncUndoState()
                    tilePreviewRefresh += 1
                },
                onWillChange:  {
                    addToHistory(fgColor)
                    canvas?.pushUndo()
                },
                onColorPicked: { c in
                    let picked = Color(nsColor: c)
                    addToHistory(fgColor)
                    fgColor = picked
                    tool = .pencil
                },
                onCursorMoved: { cursorPos = $0 },
                onSelectionChanged: { selectionInfo = $0 },
                onColorAtCursor: { cursorColor = $0 },
                onLayersChanged: { newLayers, newActive in
                    DispatchQueue.main.async {
                        layers = newLayers
                        activeLayerIndex = newActive
                    }
                },
                canvasRef: { ref in
                    DispatchQueue.main.async {
                        canvas = ref
                        imageSize = (ref.imgWidth, ref.imgHeight)
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { canvasViewSize = geo.size }
                        .onChange(of: geo.size) { _, s in canvasViewSize = s }
                }
            )

            // Feature 3: Tile preview overlay
            if showTilePreview {
                tilePreviewOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(true)
            }
        }
    }

    // MARK: - Feature 3: Tile preview

    @ViewBuilder
    private var tilePreviewOverlay: some View {
        let cellSize: CGFloat = 60
        let gridSize: CGFloat = cellSize * 3

        VStack(spacing: 8) {
            HStack {
                Text("Tile Preview")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button { showTilePreview = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(IP.card, in: Circle())
                }
                .buttonStyle(.plain)
            }

            if let cgImg = canvas?.currentCGImage() {
                let img = Image(decorative: cgImg, scale: 1.0)
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { _ in
                                img
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
                .id(tilePreviewRefresh)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: gridSize, height: gridSize)
                    .overlay(Text("No image").font(.caption2).foregroundStyle(.secondary))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IP.border.opacity(0.7), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .frame(maxWidth: gridSize + 40)
    }

    // MARK: - Helpers

    private func syncUndoState() {
        canUndo = canvas?.canUndo ?? false
        canRedo = canvas?.canRedo ?? false
        if let c = canvas { imageSize = (c.imgWidth, c.imgHeight) }
    }

    // MARK: - Color history

    private func addToHistory(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.deviceRGB)
        guard let ns else { return }
        var a: CGFloat = 0
        ns.getHue(nil, saturation: nil, brightness: nil, alpha: &a)

        colorHistory.removeAll { existing in
            let en = NSColor(existing).usingColorSpace(.deviceRGB)
            return en == ns
        }
        colorHistory.insert(color, at: 0)
        if colorHistory.count > 8 { colorHistory = Array(colorHistory.prefix(8)) }
    }

    // MARK: - HSB sync

    private func decomposeFgToHSB(_ color: Color) {
        let ns = (NSColor(color).usingColorSpace(.deviceRGB)) ?? NSColor(color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        updatingHSB = true
        hsbHue   = Double(h)
        hsbSat   = Double(s)
        hsbBri   = Double(b)
        hsbAlpha = Double(a)
        updatingHSB = false
    }

    private func rebuildFgFromHSB() {
        guard !updatingHSB else { return }
        updatingHSB = true
        fgColor = Color(hue: hsbHue, saturation: hsbSat, brightness: hsbBri, opacity: hsbAlpha)
        updatingHSB = false
    }

    // MARK: - Feature 1: Hex helpers

    private func hexFromColor(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(min(255, r * 255))
        let gi = Int(min(255, g * 255))
        let bi = Int(min(255, b * 255))
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }

    private func colorFromHex(_ hex: String) -> Color? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6,
              let val = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    private func nsColorToHex(_ color: NSColor) -> String {
        let ns = color.usingColorSpace(.deviceRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(min(255, r*255)), Int(min(255, g*255)), Int(min(255, b*255)))
    }

    // MARK: - Feature 2: Palette persistence

    private var paletteFileURL: URL {
        projectURL.appendingPathComponent(".love-studio/image-palette.json")
    }

    private func savePalette() {
        let hexArray = customPalette.map { hexFromColor($0) }
        guard let data = try? JSONSerialization.data(withJSONObject: hexArray) else { return }
        let dir = paletteFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: paletteFileURL)
    }

    private func loadPalette() {
        guard let data = try? Data(contentsOf: paletteFileURL),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return }
        let colors = arr.compactMap { colorFromHex($0) }
        if !colors.isEmpty { customPalette = colors }
    }

    // MARK: - Load / Save

    /// Load an image saved in .love-studio/images/{name}/
    private func loadProjectImage(name: String) {
        guard let result = ImageLayerDocument.load(name: name, projectRoot: projectURL) else {
            saveStatus = "Could not load \(name)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = "" }
            return
        }
        imageName  = name
        canvas?.loadLayers(result.layers, width: result.width, height: result.height)
        imageSize  = (result.width, result.height)
        // Point currentURL at the flat PNG if it exists
        let flatPNG = ImageLayerDocument.layerDir(name: name, projectRoot: projectURL)
            .appendingPathComponent("\(name).png")
        currentURL = FileManager.default.fileExists(atPath: flatPNG.path) ? flatPNG : nil
        syncUndoState()
    }

    /// Import any image from disk via native open panel
    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes  = [.png, .jpeg, .bmp, .gif, .tiff]
        panel.canChooseFiles        = true
        panel.canChooseDirectories  = false
        panel.directoryURL          = projectURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let name = url.deletingPathExtension().lastPathComponent
        imageName  = name
        currentURL = url

        guard let nsImg = NSImage(contentsOf: url),
              let cg    = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        canvas?.loadCGImage(cg)
        imageSize = (cg.width, cg.height)
        syncUndoState()
    }

    private func exportPNG() {
        guard let cg = canvas?.currentCGImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.png]
        panel.directoryURL         = projectURL
        panel.nameFieldStringValue = "\(imageName).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writePNG(cg, to: url)
    }

    private func saveImage() {
        guard let cg = canvas?.currentCGImage() else { return }

        if let url = currentURL {
            writePNG(cg, to: url)
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes  = [.png]
            panel.directoryURL         = projectURL
            panel.nameFieldStringValue = "image.png"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            currentURL = url
            writePNG(cg, to: url)
        }
    }

    // Feature 7: Save As
    private func saveImageAs() {
        guard let cg = canvas?.currentCGImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = currentURL?.deletingLastPathComponent() ?? projectURL
        panel.nameFieldStringValue = currentURL?.lastPathComponent ?? "image.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        currentURL = url
        writePNG(cg, to: url)
    }

    private func writePNG(_ cg: CGImage, to url: URL) {
        let img  = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        guard let tiff = img.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff),
              let png  = rep.representation(using: .png, properties: [:]) else {
            saveStatus = "Failed to encode PNG"
            return
        }
        do {
            try png.write(to: url)
            saveStatus = "Saved \(url.lastPathComponent) ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = "" }
        } catch {
            saveStatus = "Save failed"
        }
    }

    // MARK: - Layer Save

    private func saveWithLayers() {
        guard let c = canvas else { return }
        let canvasLayers = c.layers
        guard !canvasLayers.isEmpty else { saveImage(); return }

        // If name is still default, prompt for one
        if imageName == "untitled" {
            promptForName { name in
                imageName = name
                doSaveLayers(c, layers: canvasLayers)
            }
        } else {
            doSaveLayers(c, layers: canvasLayers)
        }
    }

    private func promptForName(completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Name this image"
        alert.informativeText = "Enter a name used to save layer data in .love-studio/"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        tf.placeholderString = "image name"
        tf.stringValue = imageName == "untitled" ? "" : imageName
        alert.accessoryView = tf
        tf.becomeFirstResponder()
        if alert.runModal() == .alertFirstButtonReturn {
            let name = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(name.isEmpty ? "untitled" : name)
        }
    }

    private func doSaveLayers(_ c: ImageCanvasNSView, layers canvasLayers: [ImageLayer]) {
        do {
            try ImageLayerDocument.save(layers: canvasLayers, name: imageName,
                                         width: imageSize.0, height: imageSize.1,
                                         to: projectURL)
            let n = canvasLayers.count
            saveStatus = "Saved \(imageName) (\(n) layer\(n == 1 ? "" : "s")) ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = "" }
        } catch {
            saveStatus = "Save failed: \(error.localizedDescription)"
        }
        // Also export flattened PNG next to the project or to currentURL
        if let cg = c.currentCGImage() {
            let exportURL: URL
            if let url = currentURL {
                exportURL = url
            } else {
                // Save flattened PNG inside the .love-studio images folder
                let dir = ImageLayerDocument.layerDir(name: imageName, projectRoot: projectURL)
                exportURL = dir.appendingPathComponent("\(imageName).png")
                currentURL = exportURL
            }
            writePNG(cg, to: exportURL)
        }
    }

    // MARK: - Layers Panel

    @ViewBuilder
    // MARK: - Right panel

    private var rightPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Image Info ────────────────────────────────────────────
                sectionHeader("Image Info", icon: "info.circle") { EmptyView() }
                VStack(spacing: 6) {
                    // Editable image name
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(IP.accent.opacity(0.7))
                        TextField("image name", text: $imageName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(IP.field, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                    }
                    infoRow("Size",   imageSize != (0,0) ? "\(imageSize.0) × \(imageSize.1) px" : "-")
                    infoRow("Layers", "\(layers.count)")
                    if let url = currentURL {
                        infoRow("File", url.lastPathComponent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                sectionDivider()

                // ── Selection Info ────────────────────────────────────────
                if let sel = selectionInfo {
                    sectionHeader("Selection", icon: "rectangle.dashed") { EmptyView() }
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("Size", "\(sel.w) × \(sel.h)")
                        infoRow("At",   "\(sel.x), \(sel.y)")
                        HStack(spacing: 4) {
                            actionButton("doc.on.doc",      label: "Copy")  { canvas?.copySelection() }
                            actionButton("doc.on.clipboard",label: "Paste") { canvas?.pasteClipboard(); syncUndoState() }
                            actionButton("trash",           label: "Del", destructive: true) {
                                canvas?.pushUndo(); canvas?.deleteSelection(); syncUndoState()
                            }
                        }
                        HStack(spacing: 4) {
                            actionButton("arrow.left.and.right.righttriangle.left.righttriangle.right",
                                         label: "Flip H") { canvas?.flipSelectionHorizontal(); syncUndoState() }
                            actionButton("arrow.up.and.down.righttriangle.up.righttriangle.down",
                                         label: "Flip V") { canvas?.flipSelectionVertical(); syncUndoState() }
                            actionButton("rotate.right", label: "Rot") { canvas?.rotateSelection90CW(); syncUndoState() }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    sectionDivider()
                }

                // ── Layers ────────────────────────────────────────────────
                layersPanel

                Spacer(minLength: 16)
            }
        }
        .background(IP.sidebar)
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Layers panel

    private var layersPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
        sectionHeader("Layers", icon: "square.stack") {
            HStack(spacing: 4) {
                Button {
                    canvas?.addLayer()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(IP.card, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Add Layer")

                Menu {
                    Button("Flatten All") { canvas?.flattenAll() }
                    Button("Merge Down") { canvas?.mergeDown() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(IP.card, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(IP.border.opacity(0.9), lineWidth: 0.5))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18, height: 18)
                .help("Layer Options")
            }
        }

        VStack(spacing: 3) {
            // Display layers in reverse (top layer shown first)
            ForEach(Array(layers.indices.reversed()), id: \.self) { i in
                let layer = layers[i]
                let isActive = i == activeLayerIndex
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        // Visibility toggle
                        Button {
                            canvas?.setLayerVisible(i, visible: !layer.visible)
                        } label: {
                            Image(systemName: layer.visible ? "eye" : "eye.slash")
                                .font(.system(size: 10))
                                .foregroundStyle(layer.visible ? Color.primary : Color.secondary.opacity(0.4))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)

                        // Lock toggle
                        Button {
                            canvas?.setLayerLocked(i, locked: !layer.isLocked)
                        } label: {
                            Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                                .font(.system(size: 9))
                                .foregroundStyle(layer.isLocked ? IP.accent : Color.secondary.opacity(0.7))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)

                        // Name
                        TextField(
                            "Layer name",
                            text: Binding(
                                get: { layers.indices.contains(i) ? layers[i].name : layer.name },
                                set: { canvas?.setLayerName(i, name: $0) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                        .italic(layer.isReference)
                        .foregroundStyle(isActive ? IP.accent : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isActive ? Color.white.opacity(0.08) : Color.clear)
                        )
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(minHeight: 30)

                    // Opacity slider for active layer
                    if isActive {
                        HStack(spacing: 4) {
                            Text("Opacity")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { layer.opacity },
                                set: { canvas?.setLayerOpacity(i, opacity: $0) }
                            ), in: 0...1)
                            .tint(IP.accent)
                            .controlSize(.mini)
                            Text("\(Int(layer.opacity * 100))%")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? IP.accentBg : IP.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isActive ? IP.accent.opacity(0.6) : IP.border.opacity(0.5),
                                lineWidth: isActive ? 1 : 0.5)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    canvas?.setActiveLayer(i)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)

        // Action buttons for active layer
        if !layers.isEmpty {
            HStack(spacing: 4) {
                actionButton("arrow.up", label: "Up") { canvas?.moveLayerUp() }
                    .help("Move layer up")
                actionButton("arrow.down", label: "Down") { canvas?.moveLayerDown() }
                    .help("Move layer down")
                actionButton("doc.on.doc", label: "Dup") { canvas?.duplicateLayer() }
                    .help("Duplicate layer")
                actionButton("arrow.down.to.line.alt", label: "Merge") { canvas?.mergeDown() }
                    .help("Merge down")
                actionButton("trash", label: "Del", destructive: true) { canvas?.deleteLayer() }
                    .help("Delete layer")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        } // VStack
    }
}
