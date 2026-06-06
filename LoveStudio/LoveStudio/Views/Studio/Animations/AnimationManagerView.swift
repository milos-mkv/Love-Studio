import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Design tokens

private enum AE {
    static let bg          = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
            : .windowBackgroundColor
    })
    static let panel       = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
            : .controlBackgroundColor
    })
    static let surface     = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1)
            : .textBackgroundColor
    })
    static let field       = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.15, green: 0.15, blue: 0.19, alpha: 1)
            : NSColor(white: 0.93, alpha: 1)
    })
    static let border      = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07)
            : .separatorColor
    })
    static let borderHover = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.13)
            : NSColor.separatorColor.withAlphaComponent(0.6)
    })
    static let accent      = Color.orange
    static let accentSoft  = Color.orange.opacity(0.15)
    static let txt1        = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.88)
            : .labelColor
    })
    static let txt2        = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.50)
            : .secondaryLabelColor
    })
    static let txt3        = Color(nsColor: NSColor(name: nil) { t in
        t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.28)
            : .tertiaryLabelColor
    })
}

// MARK: - Reusable modifiers

private extension View {
    func aeCard() -> some View {
        self
            .background(AE.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AE.border, lineWidth: 1))
    }

    func aeField() -> some View {
        self
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AE.field)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(AE.border, lineWidth: 1))
    }

    func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        Group {
            if let icon {
                Label(title, systemImage: icon)
            } else {
                Text(title)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AE.txt3)
        .textCase(.uppercase)
        .tracking(0.8)
    }
}

// MARK: - Sprite sheet grid picker

private struct SpriteSheetMetrics {
    let imageSize: CGSize
    let columns: Int
    let rows: Int
}

private struct SpriteSheetPickerView: NSViewRepresentable {
    let image: NSImage?
    let frameWidth: Int
    let frameHeight: Int
    let marginX: Int
    let marginY: Int
    let spacingX: Int
    let spacingY: Int
    let zoom: CGFloat
    let selectedFrames: [Int]
    let currentFramePosition: Int?
    let onFrameToggled: (Int) -> Void
    let onFrameRangeAdded: (Int, Int) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor(name: nil) { t in
            t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
                : .controlBackgroundColor
        }

        let picker = SpriteSheetPickerNSView()
        picker.frameWidth = frameWidth
        picker.frameHeight = frameHeight
        picker.marginX = marginX
        picker.marginY = marginY
        picker.spacingX = spacingX
        picker.spacingY = spacingY
        picker.zoom = zoom
        picker.image = image
        picker.selectedFrames = selectedFrames
        picker.currentFramePosition = currentFramePosition
        picker.onFrameToggled = onFrameToggled
        picker.onFrameRangeAdded = onFrameRangeAdded
        picker.frame = NSRect(origin: .zero, size: picker.intrinsicContentSize)
        scrollView.documentView = picker
        context.coordinator.picker = picker

        DispatchQueue.main.async { scrollToCenter(scrollView: scrollView, canvas: picker) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.backgroundColor = NSColor(name: nil) { t in
            t.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
                : .controlBackgroundColor
        }
        guard let picker = context.coordinator.picker else { return }
        let previousZoom = picker.zoom
        picker.frameWidth = frameWidth; picker.frameHeight = frameHeight
        picker.marginX = marginX; picker.marginY = marginY
        picker.spacingX = spacingX; picker.spacingY = spacingY
        picker.zoom = zoom; picker.image = image
        picker.selectedFrames = selectedFrames
        picker.currentFramePosition = currentFramePosition
        picker.onFrameToggled = onFrameToggled
        picker.onFrameRangeAdded = onFrameRangeAdded

        let intrinsic = picker.intrinsicContentSize
        let clipSize  = scrollView.contentView.bounds.size
        let size = NSSize(width: max(intrinsic.width, clipSize.width),
                          height: max(intrinsic.height, clipSize.height))
        if picker.frame.size != size { picker.frame = NSRect(origin: .zero, size: size) }
        if zoom != previousZoom {
            DispatchQueue.main.async { scrollToCenter(scrollView: scrollView, canvas: picker) }
        }
        picker.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { weak var picker: SpriteSheetPickerNSView? }

    private func scrollToCenter(scrollView: NSScrollView, canvas: NSView) {
        let doc = canvas.frame.size; let clip = scrollView.contentView.bounds.size
        scrollView.contentView.scroll(to: CGPoint(x: max(0, (doc.width - clip.width) / 2),
                                                   y: max(0, (doc.height - clip.height) / 2)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

private final class SpriteSheetPickerNSView: NSView {
    var image: NSImage? = nil { didSet { cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil); recomputeGrid(); invalidateIntrinsicContentSize(); needsDisplay = true } }
    var frameWidth:  Int = 32 { didSet { recomputeGrid(); invalidateIntrinsicContentSize(); needsDisplay = true } }
    var frameHeight: Int = 32 { didSet { recomputeGrid(); invalidateIntrinsicContentSize(); needsDisplay = true } }
    var marginX:  Int = 0 { didSet { recomputeGrid(); needsDisplay = true } }
    var marginY:  Int = 0 { didSet { recomputeGrid(); needsDisplay = true } }
    var spacingX: Int = 0 { didSet { recomputeGrid(); needsDisplay = true } }
    var spacingY: Int = 0 { didSet { recomputeGrid(); needsDisplay = true } }
    var zoom: CGFloat = 2.0 { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var selectedFrames: [Int] = [] { didSet { needsDisplay = true } }
    var currentFramePosition: Int? = nil { didSet { needsDisplay = true } }
    var onFrameToggled: ((Int) -> Void)?
    var onFrameRangeAdded: ((Int, Int) -> Void)?

    private let padding: CGFloat = 40
    private var cgImage: CGImage?
    private var columns = 1, rows = 1
    private var hoveredIndex: Int?
    private var lastClickedFrame: Int?
    private var highlightRange: ClosedRange<Int>?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    private var imageDisplaySize: CGSize {
        guard let cgImage else { return CGSize(width: 200, height: 200) }
        return CGSize(width: CGFloat(cgImage.width) * zoom, height: CGFloat(cgImage.height) * zoom)
    }
    override var intrinsicContentSize: NSSize {
        let s = imageDisplaySize; return NSSize(width: s.width + padding * 2, height: s.height + padding * 2)
    }
    private var imageOffset: CGPoint {
        let s = imageDisplaySize
        return CGPoint(x: max(padding, (bounds.width - s.width) / 2),
                       y: max(padding, (bounds.height - s.height) / 2))
    }
    private func recomputeGrid() {
        guard let cgImage else { return }
        let cw = max(1, frameWidth + max(0, spacingX)); let ch = max(1, frameHeight + max(0, spacingY))
        columns = max(1, (max(0, cgImage.width - max(0, marginX)) + max(0, spacingX)) / cw)
        rows    = max(1, (max(0, cgImage.height - max(0, marginY)) + max(0, spacingY)) / ch)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let bgColor = isDark
            ? NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
            : NSColor.controlBackgroundColor
        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(bounds)

        guard let cgImage, let image else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white.withAlphaComponent(0.22)
            ]
            let s = "Load a sprite sheet to get started" as NSString
            let sz = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: bounds.midX - sz.width / 2, y: bounds.midY - sz.height / 2), withAttributes: attrs)
            return
        }

        let offset = imageOffset
        let iw = CGFloat(cgImage.width) * zoom, ih = CGFloat(cgImage.height) * zoom

        ctx.saveGState()
        ctx.translateBy(x: offset.x, y: offset.y)
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: CGRect(x: 0, y: 0, width: iw, height: ih), from: .zero, operation: .copy, fraction: 1)

        // Selected frames
        for index in selectedFrames.indices {
            let fi = selectedFrames[index]
            let rect = cellRect(for: fi, imagePixelHeight: CGFloat(cgImage.height))
            let isCurrent = index == currentFramePosition
            ctx.setFillColor(NSColor.systemOrange.withAlphaComponent(isCurrent ? 0.45 : 0.25).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.systemOrange.withAlphaComponent(isCurrent ? 1 : 0.6).cgColor)
            ctx.setLineWidth(isCurrent ? 2 : 1)
            ctx.stroke(rect)
        }

        // Range highlight
        if let highlightRange {
            ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.22).cgColor)
            for fi in highlightRange { ctx.fill(cellRect(for: fi, imagePixelHeight: CGFloat(cgImage.height))) }
        }

        // Hover
        if let hoveredIndex {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
            ctx.fill(cellRect(for: hoveredIndex, imagePixelHeight: CGFloat(cgImage.height)))
        }

        // Grid lines
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        ctx.setLineWidth(0.5)
        for i in 0 ..< (columns * rows) { ctx.stroke(cellRect(for: i, imagePixelHeight: CGFloat(cgImage.height))) }

        // Frame index labels
        let fontSize = max(6, CGFloat(frameWidth) * zoom * 0.17)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.50)
        ]
        for i in 0 ..< (columns * rows) {
            let rect = cellRect(for: i, imagePixelHeight: CGFloat(cgImage.height))
            ("\(i)" as NSString).draw(at: CGPoint(x: rect.minX + 3, y: rect.minY + 2), withAttributes: attrs)
        }
        ctx.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        let index = frameIndex(for: event)
        if event.modifierFlags.contains(.shift), let lastClickedFrame {
            let lo = min(lastClickedFrame, index), hi = max(lastClickedFrame, index)
            onFrameRangeAdded?(lo, hi); highlightRange = lo...hi; needsDisplay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.highlightRange = nil; self?.needsDisplay = true }
        } else { onFrameToggled?(index); lastClickedFrame = index }
    }
    override func mouseMoved(with event: NSEvent) { hoveredIndex = frameIndex(for: event); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hoveredIndex = nil; needsDisplay = true }

    private func cellRect(for index: Int, imagePixelHeight: CGFloat) -> CGRect {
        let row = index / columns, col = index % columns
        let x    = CGFloat(max(0, marginX)) * zoom + CGFloat(col) * CGFloat(frameWidth + max(0, spacingX)) * zoom
        let yTop = CGFloat(max(0, marginY)) + CGFloat(row) * CGFloat(frameHeight + max(0, spacingY))
        return CGRect(x: x, y: (imagePixelHeight - yTop - CGFloat(frameHeight)) * zoom,
                      width: CGFloat(frameWidth) * zoom, height: CGFloat(frameHeight) * zoom)
    }

    private func frameIndex(for event: NSEvent) -> Int {
        let raw = convert(event.locationInWindow, from: nil), offset = imageOffset
        let lx = (raw.x - offset.x) / zoom, ly = (raw.y - offset.y) / zoom
        guard let cgImage else { return 0 }
        let topY = CGFloat(cgImage.height) - ly
        let xi = lx - CGFloat(max(0, marginX)), yi = topY - CGFloat(max(0, marginY))
        let cw = CGFloat(frameWidth + max(0, spacingX)), ch = CGFloat(frameHeight + max(0, spacingY))
        let col = max(0, min(columns - 1, Int(xi / max(1, cw))))
        let row = max(0, min(rows - 1, Int(yi / max(1, ch))))
        return row * columns + col
    }
}

// MARK: - Checkerboard

private struct CheckerboardView: View {
    var body: some View {
        GeometryReader { geo in
            let sz: CGFloat = 12
            Canvas { ctx, _ in
                let cols = Int(geo.size.width / sz) + 2, rows = Int(geo.size.height / sz) + 2
                for r in 0..<rows { for c in 0..<cols {
                    ctx.fill(Path(CGRect(x: CGFloat(c)*sz, y: CGFloat(r)*sz, width: sz, height: sz)),
                             with: .color((r+c).isMultiple(of: 2) ? Color.white.opacity(0.10) : Color.black.opacity(0.18)))
                }}
            }
        }
    }
}

// MARK: - Frame drag/drop

private struct FrameDropDelegate: DropDelegate {
    let targetPosition: Int
    @Binding var draggingPosition: Int?
    let onMove: (Int, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        defer { draggingPosition = nil }
        guard let source = draggingPosition else { return false }
        onMove(source, targetPosition); return true
    }
    func dropEntered(info: DropInfo) {
        guard let source = draggingPosition, source != targetPosition else { return }
        onMove(source, targetPosition); draggingPosition = targetPosition
    }
}

// MARK: - Main view

struct AnimationManagerView: View {
    private let leftW: CGFloat  = 296
    private let rightW: CGFloat = 260

    let projectURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var config = SpriteAnimationConfig()
    @State private var spriteSheetImage: NSImage?
    @State private var savedConfigs: [SpriteAnimationConfig] = []
    @State private var saveStatus = ""
    @State private var selectedClipIndex = 0
    @State private var previewClipIndex = 0
    @State private var previewFrame = 0
    @State private var previewPlaying = false
    @State private var previewAccum = 0.0
    @State private var draggingFramePosition: Int?
    @State private var canvasZoom: CGFloat = 2.0
    @State private var previewZoom: CGFloat = 1.0
    @State private var previewBackground: PreviewBackground = .checker
    @State private var previewFlipH: Bool = false
    @State private var previewFlipV: Bool = false

    // Frame editing
    @State private var selectedFrameID: UUID? = nil

    // Onion skin
    @State private var onionSkinEnabled: Bool = false

    // Timeline scrubbing
    @State private var isScrubbing: Bool = false

    // Hitbox editing
    @State private var selectedHitboxID: UUID? = nil

    // Quick row selector
    @State private var showRowSelector = false
    @State private var rowSelectorRow = 1
    @State private var rowSelectorColStart = 1
    @State private var rowSelectorColEnd = 1

    private enum PreviewBackground: String, CaseIterable, Identifiable {
        case checker, black, white, gray
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var color: Color {
            switch self {
            case .checker: .clear
            case .black: .black
            case .white: .white
            case .gray: Color(white: 0.45)
            }
        }
        var icon: String {
            switch self {
            case .checker: "checkerboard.rectangle"
            case .black:   "moon.fill"
            case .white:   "sun.max.fill"
            case .gray:    "circle.lefthalf.filled"
            }
        }
    }

    private var safeClipIndex: Int {
        config.clips.isEmpty ? 0 : min(selectedClipIndex, config.clips.count - 1)
    }
    private var currentClip: SpriteAnimationClip? {
        guard !config.clips.isEmpty else { return nil }
        return config.clips[safeClipIndex]
    }
    private var currentPreviewClip: SpriteAnimationClip? {
        guard !config.clips.isEmpty else { return nil }
        return config.clips[min(previewClipIndex, config.clips.count - 1)]
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(AE.border)
            HStack(spacing: 0) {
                leftPanel
                Divider().overlay(AE.border)
                centerCanvas
                Divider().overlay(AE.border)
                rightPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(AE.bg)
        .onAppear {
            savedConfigs = AnimationStore.loadAll(from: projectURL)
            loadSpriteSheetImageIfNeeded()
        }
        .onChange(of: config.spriteSheetPath) { _, _ in loadSpriteSheetImageIfNeeded() }
        .onChange(of: config.frameWidth)  { _, _ in sanitizeSelectionsAfterGridChange() }
        .onChange(of: config.frameHeight) { _, _ in sanitizeSelectionsAfterGridChange() }
        .onChange(of: config.marginX)     { _, _ in sanitizeSelectionsAfterGridChange() }
        .onChange(of: config.marginY)     { _, _ in sanitizeSelectionsAfterGridChange() }
        .onChange(of: config.spacingX)    { _, _ in sanitizeSelectionsAfterGridChange() }
        .onChange(of: config.spacingY)    { _, _ in sanitizeSelectionsAfterGridChange() }
        .onDisappear { previewPlaying = false }
        .onReceive(Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()) { _ in
            advancePreviewTick()
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AE.accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "figure.run")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AE.accent)
                }
                Text("Animation Editor")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AE.txt1)
            }

            Rectangle().fill(AE.border).frame(width: 1, height: 18)

            TextField("Module name", text: $config.moduleName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AE.txt1)
                .frame(width: 170)
                .aeField()

            Spacer()

            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(AE.txt3)
                    .transition(.opacity)
            }

            Menu {
                if savedConfigs.isEmpty {
                    Text("No saved animations").foregroundStyle(AE.txt3)
                } else {
                    ForEach(savedConfigs) { loaded in
                        Button(loaded.moduleName) { loadConfig(loaded) }
                    }
                    Divider()
                    ForEach(savedConfigs) { loaded in
                        Button("Delete \(loaded.moduleName)", role: .destructive) {
                            AnimationStore.delete(loaded, from: projectURL)
                            savedConfigs = AnimationStore.loadAll(from: projectURL)
                        }
                    }
                }
            } label: {
                Label("Load", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 12))
                    .foregroundStyle(AE.txt2)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                do {
                    try AnimationStore.save(sanitizedConfig, to: projectURL)
                    savedConfigs = AnimationStore.loadAll(from: projectURL)
                    flash("Saved")
                } catch { flash("Save failed") }
            } label: {
                Text("Save")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AE.txt2)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(AE.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(AE.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                let code = AnimationCodeGenerator.generate(config: sanitizedConfig)
                do {
                    let url = try AnimationStore.exportLua(code, moduleName: sanitizedConfig.moduleName, to: projectURL)
                    flash("Exported → \(url.lastPathComponent)")
                } catch { flash("Export failed") }
            } label: {
                Label("Export Lua", systemImage: "arrow.up.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(canExport ? AE.accent : AE.accent.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canExport)

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AE.panel)
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                spritesheetSection
                clipsSection
                frameStripSection
                eventsSection
            }
            .padding(12)
        }
        .frame(width: leftW)
        .background(AE.panel)
    }

    // MARK: Spritesheet section

    private var spritesheetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Sprite Sheet", icon: "photo.on.rectangle")

            HStack(spacing: 8) {
                Button(action: chooseSpriteSheet) {
                    Label("Choose", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AE.accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(AE.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(AE.accent.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Auto-detect grid button
                if spriteSheetImage != nil {
                    Button(action: autoDetectGrid) {
                        Label("Detect Grid", systemImage: "sparkle.magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AE.txt2)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(AE.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(AE.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Auto-detect frame size from image dimensions")
                }

                if !config.spriteSheetPath.isEmpty {
                    Button {
                        config.spriteSheetPath = ""; spriteSheetImage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(AE.txt3)
                            .frame(width: 22, height: 22)
                            .background(AE.surface)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(AE.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !config.spriteSheetPath.isEmpty {
                Text(config.spriteSheetPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AE.txt3)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AE.field)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(AE.border, lineWidth: 1))
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    numField("W",  value: $config.frameWidth)
                    numField("H",  value: $config.frameHeight)
                    numField("MX", value: $config.marginX)
                    numField("MY", value: $config.marginY)
                }
                HStack(spacing: 6) {
                    numField("SX", value: $config.spacingX)
                    numField("SY", value: $config.spacingY)
                    Spacer()
                }
            }

            if let m = spriteSheetMetrics {
                HStack(spacing: 6) {
                    Image(systemName: "squareshape.split.3x3")
                        .font(.system(size: 9))
                        .foregroundStyle(AE.txt3)
                    Text("\(Int(m.imageSize.width))×\(Int(m.imageSize.height)) · \(m.columns) cols × \(m.rows) rows")
                        .font(.system(size: 11))
                        .foregroundStyle(AE.txt3)
                }
            }
        }
        .padding(12)
        .aeCard()
    }

    // MARK: Clips section

    private var clipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Animations", icon: "film.stack")
                Spacer()
                HStack(spacing: 4) {
                    Button { duplicateClip() } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(AE.txt3)
                            .frame(width: 22, height: 22)
                            .background(AE.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(AE.border))
                    }
                    .buttonStyle(.plain)
                    .disabled(config.clips.isEmpty)
                    .help("Duplicate")

                    Button { addClip() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AE.accent)
                            .frame(width: 22, height: 22)
                            .background(AE.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(AE.accent.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                    .help("Add animation")
                }
            }

            VStack(spacing: 2) {
                ForEach(Array(config.clips.enumerated()), id: \.element.id) { idx, clip in
                    clipRow(index: idx, clip: clip)
                }
            }
        }
        .padding(12)
        .aeCard()
    }

    private func clipRow(index: Int, clip: SpriteAnimationClip) -> some View {
        let nameB = Binding<String>(
            get: { index < config.clips.count ? config.clips[index].name : "" },
            set: { if index < config.clips.count { config.clips[index].name = $0 } }
        )
        let fpsB = Binding<Double>(
            get: { index < config.clips.count ? config.clips[index].fps : 12 },
            set: { if index < config.clips.count { config.clips[index].fps = $0 } }
        )
        let speedB = Binding<Double>(
            get: { index < config.clips.count ? config.clips[index].speed : 1.0 },
            set: { if index < config.clips.count { config.clips[index].speed = max(0.1, $0) } }
        )
        let isSel = selectedClipIndex == index

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSel ? AE.accent : Color.clear)
                .frame(width: 2, height: 28)
                .padding(.trailing, 8)

            Button { selectedClipIndex = index } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(isSel ? AE.accent : AE.txt3)

                    if isSel {
                        TextField("name", text: nameB)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AE.txt1)
                            .frame(maxWidth: 80)
                    } else {
                        Text(clip.name.isEmpty ? "anim\(index)" : clip.name)
                            .font(.system(size: 12))
                            .foregroundStyle(isSel ? AE.txt1 : AE.txt2)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                TextField("fps", value: fpsB, format: .number)
                    .textFieldStyle(.plain)
                    .frame(width: 30)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AE.txt2)
                    .multilineTextAlignment(.center)
                Text("fps")
                    .font(.system(size: 9))
                    .foregroundStyle(AE.txt3)
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(AE.field)
            .clipShape(Capsule())
            .onTapGesture { selectedClipIndex = index }

            if isSel && abs(speedB.wrappedValue - 1.0) > 0.01 {
                HStack(spacing: 2) {
                    Image(systemName: "hare.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(AE.accent)
                    Text(String(format: "%.1f×", speedB.wrappedValue))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AE.accent)
                }
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(AE.accentSoft)
                .clipShape(Capsule())
            }

            Button { guard index < config.clips.count else { return }; config.clips[index].loops.toggle() } label: {
                Image(systemName: clip.loops ? "repeat" : "repeat.1")
                    .font(.system(size: 10))
                    .foregroundStyle(clip.loops ? Color.blue : AE.txt3)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button { removeClip(at: index) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(AE.txt3)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(isSel ? AE.accent.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(isSel ? AE.accent.opacity(0.25) : Color.clear, lineWidth: 1))
    }

    // MARK: Frame strip

    private var frameStripSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Frames", icon: "list.number")
                Spacer()

                // Quick row selector
                if spriteSheetImage != nil {
                    Button {
                        if let m = spriteSheetMetrics {
                            rowSelectorColEnd = m.columns
                        }
                        showRowSelector = true
                    } label: {
                        Label("Add Row", systemImage: "plus.square.on.square")
                            .font(.system(size: 10))
                            .foregroundStyle(AE.txt3)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(AE.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(AE.border))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showRowSelector, arrowEdge: .bottom) {
                        rowSelectorPopover
                    }
                }

                if let c = currentClip, !resolvedFrames(for: c).isEmpty {
                    Button("Clear") { clearFrames(); selectedFrameID = nil }
                        .font(.system(size: 10))
                        .foregroundStyle(AE.txt3)
                        .buttonStyle(.plain)
                }
            }

            if let clip = currentClip {
                let frames = resolvedFrames(for: clip)
                if frames.isEmpty {
                    Text("Click frames in the spritesheet to build the animation.")
                        .font(.system(size: 11))
                        .foregroundStyle(AE.txt3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(frames.enumerated()), id: \.element.id) { pos, frame in
                                frameThumbnail(position: pos, frame: frame)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    let dur = Double(frames.count) / max(1, clip.fps)
                    let effDur = dur / max(0.01, clip.speed)
                    HStack(spacing: 6) {
                        Text("\(frames.count) frames · \(Int(clip.fps)) fps · \(String(format: "%.2f", dur))s")
                            .font(.system(size: 10))
                            .foregroundStyle(AE.txt3)
                        if abs(clip.speed - 1.0) > 0.01 {
                            Text("(\(String(format: "%.2f", effDur))s @ \(String(format: "%.1f×", clip.speed)))")
                                .font(.system(size: 10))
                                .foregroundStyle(AE.accent)
                        }
                    }

                    // Speed control
                    HStack(spacing: 8) {
                        Image(systemName: "hare.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AE.txt3)
                        Slider(value: Binding(
                            get: { safeClipIndex < config.clips.count ? config.clips[safeClipIndex].speed : 1.0 },
                            set: { if safeClipIndex < config.clips.count { config.clips[safeClipIndex].speed = max(0.1, $0) } }
                        ), in: 0.1...4.0)
                        Text(String(format: "%.2f×", clip.speed))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(clip.speed == 1.0 ? AE.txt3 : AE.accent)
                            .frame(width: 36, alignment: .trailing)
                        Button {
                            if safeClipIndex < config.clips.count { config.clips[safeClipIndex].speed = 1.0 }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9))
                                .foregroundStyle(AE.txt3)
                        }
                        .buttonStyle(.plain)
                        .opacity(abs(clip.speed - 1.0) > 0.01 ? 1 : 0)
                    }

                    // Inline frame editor (shown when a frame is selected)
                    if let fid = selectedFrameID,
                       safeClipIndex < config.clips.count,
                       let frameIdx = config.clips[safeClipIndex].frames.firstIndex(where: { $0.id == fid }) {
                        frameEditorRow(frameIdx: frameIdx, clip: config.clips[safeClipIndex])
                    }
                }
            }
        }
        .padding(12)
        .aeCard()
    }

    private var rowSelectorPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD FRAMES")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AE.txt3)
                .tracking(0.8)

            // Row stepper
            HStack(spacing: 8) {
                Text("Row")
                    .font(.system(size: 11))
                    .foregroundStyle(AE.txt2)
                    .frame(width: 36, alignment: .leading)
                Stepper(value: $rowSelectorRow, in: 1...max(1, spriteSheetMetrics?.rows ?? 1)) {
                    Text("\(rowSelectorRow)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AE.txt1)
                        .frame(width: 28)
                }
            }

            // Column range
            HStack(spacing: 8) {
                Text("Cols")
                    .font(.system(size: 11))
                    .foregroundStyle(AE.txt2)
                    .frame(width: 36, alignment: .leading)
                TextField("", value: $rowSelectorColStart, format: .number)
                    .textFieldStyle(.plain)
                    .frame(width: 36)
                    .multilineTextAlignment(.center)
                    .aeField()
                Text("–")
                    .font(.system(size: 11))
                    .foregroundStyle(AE.txt3)
                TextField("", value: $rowSelectorColEnd, format: .number)
                    .textFieldStyle(.plain)
                    .frame(width: 36)
                    .multilineTextAlignment(.center)
                    .aeField()
            }

            // All columns shortcut
            if let m = spriteSheetMetrics, m.columns > 1 {
                Button("All \(m.columns) columns") {
                    rowSelectorColStart = 1
                    rowSelectorColEnd   = m.columns
                }
                .font(.system(size: 10))
                .foregroundStyle(AE.txt3)
                .buttonStyle(.plain)
            }

            Divider().overlay(AE.border)

            HStack {
                Button("Cancel") { showRowSelector = false }
                    .font(.system(size: 11))
                    .foregroundStyle(AE.txt3)
                    .buttonStyle(.plain)
                Spacer()
                Button("Add Frames") {
                    addRowRange(row: rowSelectorRow, colStart: rowSelectorColStart, colEnd: rowSelectorColEnd)
                    showRowSelector = false
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AE.accent)
                .buttonStyle(.plain)
                .disabled(spriteSheetMetrics == nil)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(AE.panel)
    }

    private func frameEditorRow(frameIdx: Int, clip: SpriteAnimationClip) -> some View {
        let defaultMs = Int(1000.0 / max(1, clip.fps))
        let hasCustomDur = config.clips[safeClipIndex].frames[frameIdx].duration != nil
        let hasRepeat    = config.clips[safeClipIndex].frames[frameIdx].repeatCount > 1

        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AE.accent)
                        .frame(width: 3, height: 12)
                    Text("Frame \(frameIdx + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AE.txt1)
                }
                Spacer()
                Button { selectedFrameID = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(AE.txt3)
                        .frame(width: 18, height: 18)
                        .background(AE.field)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().overlay(AE.border)

            // Duration row
            HStack(spacing: 0) {
                // Label column
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                        .foregroundStyle(AE.txt3)
                    Text("Duration")
                        .font(.system(size: 11))
                        .foregroundStyle(AE.txt2)
                }
                .frame(width: 80, alignment: .leading)
                .padding(.leading, 10)

                Spacer()

                if hasCustomDur {
                    HStack(spacing: 6) {
                        TextField("ms", value: Binding(
                            get: {
                                guard safeClipIndex < config.clips.count,
                                      frameIdx < config.clips[safeClipIndex].frames.count else { return defaultMs }
                                return Int((config.clips[safeClipIndex].frames[frameIdx].duration ?? Double(defaultMs)/1000) * 1000)
                            },
                            set: {
                                guard safeClipIndex < config.clips.count,
                                      frameIdx < config.clips[safeClipIndex].frames.count else { return }
                                config.clips[safeClipIndex].frames[frameIdx].duration = max(1, Double($0)) / 1000.0
                            }
                        ), format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AE.accent)
                        .frame(width: 52)
                        .multilineTextAlignment(.center)
                        .aeField()

                        Text("ms")
                            .font(.system(size: 11))
                            .foregroundStyle(AE.txt3)

                        Button {
                            guard safeClipIndex < config.clips.count,
                                  frameIdx < config.clips[safeClipIndex].frames.count else { return }
                            config.clips[safeClipIndex].frames[frameIdx].duration = nil
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(AE.txt3)
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.plain)
                        .help("Reset to clip default")
                    }
                    .padding(.trailing, 10)
                } else {
                    HStack(spacing: 8) {
                        Text("\(defaultMs) ms")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AE.txt3)

                        Button("Override") {
                            guard safeClipIndex < config.clips.count,
                                  frameIdx < config.clips[safeClipIndex].frames.count else { return }
                            config.clips[safeClipIndex].frames[frameIdx].duration = Double(defaultMs) / 1000.0
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AE.accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(AE.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .buttonStyle(.plain)
                    }
                    .padding(.trailing, 10)
                }
            }
            .padding(.vertical, 8)

            Divider().overlay(AE.border)

            // Repeat row
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "repeat")
                        .font(.system(size: 10))
                        .foregroundStyle(AE.txt3)
                    Text("Repeat")
                        .font(.system(size: 11))
                        .foregroundStyle(AE.txt2)
                }
                .frame(width: 80, alignment: .leading)
                .padding(.leading, 10)

                Spacer()

                HStack(spacing: 8) {
                    Text("\(config.clips[safeClipIndex].frames[frameIdx].repeatCount)×")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(hasRepeat ? AE.accent : AE.txt2)
                        .frame(width: 28, alignment: .trailing)

                    Stepper("", value: Binding(
                        get: {
                            guard safeClipIndex < config.clips.count,
                                  frameIdx < config.clips[safeClipIndex].frames.count else { return 1 }
                            return config.clips[safeClipIndex].frames[frameIdx].repeatCount
                        },
                        set: {
                            guard safeClipIndex < config.clips.count,
                                  frameIdx < config.clips[safeClipIndex].frames.count else { return }
                            config.clips[safeClipIndex].frames[frameIdx].repeatCount = max(1, $0)
                        }
                    ), in: 1...99)
                    .labelsHidden()

                    if hasRepeat {
                        Text("= \(Int(Double(config.clips[safeClipIndex].frames[frameIdx].repeatCount) * (config.clips[safeClipIndex].frames[frameIdx].duration ?? Double(defaultMs)/1000) * 1000))ms total")
                            .font(.system(size: 10))
                            .foregroundStyle(AE.txt3)
                    }
                }
                .padding(.trailing, 10)
            }
            .padding(.vertical, 8)

            Divider().overlay(AE.border)

            // Hitbox section
            hitboxSection(frameIdx: frameIdx)
        }
        .background(AE.field.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AE.accent.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private func hitboxSection(frameIdx: Int) -> some View {
        let hitboxes = safeClipIndex < config.clips.count ? config.clips[safeClipIndex].hitboxes.filter { $0.frameIndex == frameIdx } : []

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 9))
                        .foregroundStyle(AE.txt3)
                    Text("Hitboxes")
                        .font(.system(size: 11))
                        .foregroundStyle(AE.txt2)
                }
                Spacer()
                Button {
                    guard safeClipIndex < config.clips.count else { return }
                    let hb = FrameHitbox(frameIndex: frameIdx)
                    config.clips[safeClipIndex].hitboxes.append(hb)
                    selectedHitboxID = hb.id
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AE.accent)
                        .frame(width: 18, height: 18)
                        .background(AE.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Add hitbox")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            ForEach(hitboxes) { hb in
                if let hbIdx = config.clips[safeClipIndex].hitboxes.firstIndex(where: { $0.id == hb.id }) {
                    hitboxRow(hbIdx: hbIdx)
                }
            }

            if hitboxes.isEmpty {
                Text("No hitboxes for this frame")
                    .font(.system(size: 10))
                    .foregroundStyle(AE.txt3)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
    }

    private func hitboxRow(hbIdx: Int) -> some View {
        let hb = config.clips[safeClipIndex].hitboxes[hbIdx]
        let isSelHB = selectedHitboxID == hb.id

        return VStack(alignment: .leading, spacing: 0) {
            // Row header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 6, height: 6)
                TextField("label", text: Binding(
                    get: { safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count ? config.clips[safeClipIndex].hitboxes[hbIdx].label : "" },
                    set: { if safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count { config.clips[safeClipIndex].hitboxes[hbIdx].label = $0 } }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(AE.txt1)
                Spacer()
                Button { selectedHitboxID = isSelHB ? nil : hb.id } label: {
                    Image(systemName: isSelHB ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(AE.txt3)
                }
                .buttonStyle(.plain)
                Button {
                    guard safeClipIndex < config.clips.count,
                          hbIdx < config.clips[safeClipIndex].hitboxes.count else { return }
                    config.clips[safeClipIndex].hitboxes.remove(at: hbIdx)
                    if selectedHitboxID == hb.id { selectedHitboxID = nil }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundStyle(AE.txt3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)

            if isSelHB {
                Divider().overlay(AE.border)
                // XYWH grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    hitboxField("X", val: Binding(
                        get: { safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count ? config.clips[safeClipIndex].hitboxes[hbIdx].x : 0 },
                        set: { if safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count { config.clips[safeClipIndex].hitboxes[hbIdx].x = $0 } }
                    ))
                    hitboxField("Y", val: Binding(
                        get: { safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count ? config.clips[safeClipIndex].hitboxes[hbIdx].y : 0 },
                        set: { if safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count { config.clips[safeClipIndex].hitboxes[hbIdx].y = $0 } }
                    ))
                    hitboxField("W", val: Binding(
                        get: { safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count ? config.clips[safeClipIndex].hitboxes[hbIdx].width : 16 },
                        set: { if safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count { config.clips[safeClipIndex].hitboxes[hbIdx].width = max(1, $0) } }
                    ))
                    hitboxField("H", val: Binding(
                        get: { safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count ? config.clips[safeClipIndex].hitboxes[hbIdx].height : 16 },
                        set: { if safeClipIndex < config.clips.count && hbIdx < config.clips[safeClipIndex].hitboxes.count { config.clips[safeClipIndex].hitboxes[hbIdx].height = max(1, $0) } }
                    ))
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
        .background(isSelHB ? Color.green.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func hitboxField(_ label: String, val: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AE.txt3)
                .frame(width: 12)
            TextField("0", value: val, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AE.txt1)
                .multilineTextAlignment(.center)
                .aeField()
        }
    }

    private func frameThumbnail(position: Int, frame: SpriteAnimationFrameSelection) -> some View {
        let hasEvent      = currentClip?.events.contains { $0.framePosition == position } ?? false
        let isDrag        = draggingFramePosition == position
        let isSelected    = selectedFrameID == frame.id
        let hasCustomDur  = frame.duration != nil
        let hasRepeat     = frame.repeatCount > 1

        return VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(AE.field)
                    .frame(width: 48, height: 48)

                if let img = croppedImage(for: frame) {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                        .frame(width: 48, height: 48)
                }

                // Remove button
                Button { removeFrame(at: position); if isSelected { selectedFrameID = nil } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AE.txt2)
                        .background(Circle().fill(AE.bg))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)

                // Event badge
                if hasEvent {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.yellow)
                        .padding(2)
                        .background(Circle().fill(AE.bg.opacity(0.8)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(3)
                }

                // Repeat badge - top-left
                if hasRepeat {
                    Text("×\(frame.repeatCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AE.accent)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(AE.accentSoft)
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 2).padding(.top, 2)
                        .offset(x: -4)
                }

                // Duration badge - bottom-right (only when custom)
                if hasCustomDur, let dur = frame.duration {
                    Text("\(Int(dur * 1000))ms")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
                        .padding(.horizontal, 3).padding(.vertical, 2)
                        .background(Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.18))
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(3)
                }
            }
            .frame(width: 48, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isSelected ? AE.accent : (isDrag ? AE.accent.opacity(0.5) : AE.border),
                        lineWidth: isSelected || isDrag ? 2 : 1
                    )
            )
            .opacity(isDrag ? 0.5 : 1)
            .onTapGesture {
                // Materialize before editing so frame index is stable
                if safeClipIndex < config.clips.count {
                    materializeClipFrames(at: safeClipIndex)
                }
                selectedFrameID = isSelected ? nil : frame.id
            }
            .contextMenu {
                Button("Edit Duration & Repeat") {
                    if safeClipIndex < config.clips.count {
                        materializeClipFrames(at: safeClipIndex)
                    }
                    selectedFrameID = frame.id
                }
                if hasCustomDur {
                    Button("Clear Custom Duration", role: .destructive) {
                        guard safeClipIndex < config.clips.count,
                              let idx = config.clips[safeClipIndex].frames.firstIndex(where: { $0.id == frame.id })
                        else { return }
                        config.clips[safeClipIndex].frames[idx].duration = nil
                    }
                }
                if hasRepeat {
                    Button("Clear Repeat Count", role: .destructive) {
                        guard safeClipIndex < config.clips.count,
                              let idx = config.clips[safeClipIndex].frames.firstIndex(where: { $0.id == frame.id })
                        else { return }
                        config.clips[safeClipIndex].frames[idx].repeatCount = 1
                    }
                }
                Divider()
                Button("Remove Frame", role: .destructive) {
                    removeFrame(at: position)
                    if isSelected { selectedFrameID = nil }
                }
            }

            Text("\(frame.row),\(frame.column)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(AE.txt3)
        }
        .onDrag {
            draggingFramePosition = position
            return NSItemProvider(object: "\(position)" as NSString)
        }
        .onDrop(of: [.text], delegate: FrameDropDelegate(
            targetPosition: position,
            draggingPosition: $draggingFramePosition,
            onMove: moveFrame
        ))
    }

    // MARK: Events section

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("Events", icon: "bolt.fill")
                Spacer()
                Button { addEvent() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AE.accent)
                        .frame(width: 20, height: 20)
                        .background(AE.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(AE.accent.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(currentClip.map { resolvedFrames(for: $0).isEmpty } ?? true)
                .help("Add event")
            }

            if let clip = currentClip {
                let frameCount = resolvedFrames(for: clip).count
                if clip.events.isEmpty {
                    Text("No events. Add one to fire callbacks on specific frames.")
                        .font(.system(size: 11))
                        .foregroundStyle(AE.txt3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 4) {
                        ForEach(Array(clip.events.enumerated()), id: \.element.id) { ei, _ in
                            eventRow(clipIndex: safeClipIndex, eventIndex: ei, frameCount: frameCount)
                        }
                    }
                }
            }
        }
        .padding(12)
        .aeCard()
    }

    private func eventRow(clipIndex: Int, eventIndex: Int, frameCount: Int) -> some View {
        let posB = Binding<Int>(
            get: {
                guard clipIndex < config.clips.count, eventIndex < config.clips[clipIndex].events.count else { return 0 }
                return config.clips[clipIndex].events[eventIndex].framePosition
            },
            set: {
                guard clipIndex < config.clips.count, eventIndex < config.clips[clipIndex].events.count else { return }
                config.clips[clipIndex].events[eventIndex].framePosition = max(0, min($0, max(0, frameCount - 1)))
            }
        )
        let nameB = Binding<String>(
            get: {
                guard clipIndex < config.clips.count, eventIndex < config.clips[clipIndex].events.count else { return "" }
                return config.clips[clipIndex].events[eventIndex].eventName
            },
            set: {
                guard clipIndex < config.clips.count, eventIndex < config.clips[clipIndex].events.count else { return }
                config.clips[clipIndex].events[eventIndex].eventName = $0
            }
        )

        return HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8))
                .foregroundStyle(.yellow)
                .frame(width: 16)

            TextField("#", value: posB, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AE.txt1)
                .frame(width: 32)
                .multilineTextAlignment(.center)
                .aeField()

            TextField("event name", text: nameB)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(AE.txt1)
                .frame(maxWidth: .infinity)
                .aeField()

            Button {
                guard clipIndex < config.clips.count, eventIndex < config.clips[clipIndex].events.count else { return }
                config.clips[clipIndex].events.remove(at: eventIndex)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(AE.txt3)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(AE.field.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Center canvas

    private var centerCanvas: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let m = spriteSheetMetrics {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 10))
                            .foregroundStyle(AE.txt3)
                        Text("\(Int(m.imageSize.width))×\(Int(m.imageSize.height)) px · \(m.columns)×\(m.rows) grid")
                            .font(.system(size: 11))
                            .foregroundStyle(AE.txt3)
                    }
                } else {
                    Text("Select a sprite sheet to begin")
                        .font(.system(size: 11))
                        .foregroundStyle(AE.txt3)
                }

                Spacer()

                // Onion skin toggle
                Button {
                    onionSkinEnabled.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.forward.dottedline.fill")
                            .font(.system(size: 11))
                        Text("Onion")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(onionSkinEnabled ? AE.accent : AE.txt3)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(onionSkinEnabled ? AE.accentSoft : AE.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(onionSkinEnabled ? AE.accent.opacity(0.4) : AE.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Toggle onion skin preview")

                HStack(spacing: 2) {
                    Text("Zoom")
                        .font(.system(size: 10))
                        .foregroundStyle(AE.txt3)
                    ForEach([CGFloat(1), 2, 3, 4], id: \.self) { z in
                        Button("\(Int(z))×") { canvasZoom = z }
                            .font(.system(size: 11, weight: canvasZoom == z ? .semibold : .regular))
                            .foregroundStyle(canvasZoom == z ? AE.accent : AE.txt2)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(canvasZoom == z ? AE.accentSoft : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(AE.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(AE.border, lineWidth: 1))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AE.panel)

            Divider().overlay(AE.border)

            SpriteSheetPickerView(
                image: spriteSheetImage,
                frameWidth:  max(1, config.frameWidth),
                frameHeight: max(1, config.frameHeight),
                marginX:  max(0, config.marginX),
                marginY:  max(0, config.marginY),
                spacingX: max(0, config.spacingX),
                spacingY: max(0, config.spacingY),
                zoom: canvasZoom,
                selectedFrames: currentClip.map(selectedFrameIndices(for:)) ?? [],
                currentFramePosition: previewPlaying ? previewFrame : nil,
                onFrameToggled:    { toggleFrame($0) },
                onFrameRangeAdded: { addFrameRange(from: $0, to: $1) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AE.bg)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                previewSection
                moduleSettingsSection
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .frame(width: rightW)
        .background(AE.panel)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Preview", icon: "play.fill")

            if !config.clips.isEmpty {
                Picker("", selection: $previewClipIndex) {
                    ForEach(Array(config.clips.enumerated()), id: \.offset) { i, clip in
                        Text(clip.name.isEmpty ? "anim\(i)" : clip.name).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .onChange(of: previewClipIndex) { _, i in
                    previewFrame = 0; previewAccum = 0
                    if i < config.clips.count {
                        previewFlipH = config.clips[i].flipH
                        previewFlipV = config.clips[i].flipV
                    }
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(previewBackground == .checker ? AE.bg : previewBackground.color)

                if previewBackground == .checker {
                    CheckerboardView().clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                previewFrameView
                    .scaleEffect(previewZoom)

                // Hitbox overlay
                if let clip = currentPreviewClip, previewFrame < resolvedFrames(for: clip).count {
                    let hitboxes = clip.hitboxes.filter { $0.frameIndex == previewFrame }
                    if !hitboxes.isEmpty {
                        let fw = CGFloat(max(1, config.frameWidth))
                        let fh = CGFloat(max(1, config.frameHeight))
                        let displaySize: CGFloat = 180 * previewZoom // 200 - 2*10 padding
                        let scale = min(displaySize / fw, displaySize / fh)
                        let drawW = fw * scale
                        let drawH = fh * scale
                        // Origin in frame-local pixels (same as LÖVE draw origin)
                        let originX = config.centerOrigin ? fw / 2 : CGFloat(config.offsetX)
                        let originY = config.centerOrigin ? fh / 2 : CGFloat(config.offsetY)

                        Canvas { ctx, size in
                            let ox = (size.width  - drawW) / 2
                            let oy = (size.height - drawH) / 2
                            // Canvas position of the origin point
                            let originPx = ox + originX * scale
                            let originPy = oy + originY * scale
                            for hb in hitboxes {
                                let r = CGRect(
                                    x: originPx + CGFloat(hb.x) * scale,
                                    y: originPy + CGFloat(hb.y) * scale,
                                    width:  CGFloat(hb.width)  * scale,
                                    height: CGFloat(hb.height) * scale
                                )
                                ctx.stroke(Path(r), with: .color(.green.opacity(0.9)), lineWidth: 1.5)
                                ctx.fill(Path(r), with: .color(.green.opacity(0.15)))
                                // Draw a small cross at origin for reference
                                let crossSize: CGFloat = 4
                                var cross = Path()
                                cross.move(to:    CGPoint(x: originPx - crossSize, y: originPy))
                                cross.addLine(to: CGPoint(x: originPx + crossSize, y: originPy))
                                cross.move(to:    CGPoint(x: originPx, y: originPy - crossSize))
                                cross.addLine(to: CGPoint(x: originPx, y: originPy + crossSize))
                                ctx.stroke(cross, with: .color(.orange.opacity(0.8)), lineWidth: 1)
                            }
                        }
                    }
                }
            }
            .frame(width: 200, height: 200)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AE.border, lineWidth: 1))
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
            HStack(spacing: 6) {
                Button { previewPlaying.toggle() } label: {
                    Image(systemName: previewPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(previewPlaying ? AE.accent : AE.txt1)
                        .frame(width: 30, height: 28)
                        .background(previewPlaying ? AE.accentSoft : AE.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(previewPlaying ? AE.accent.opacity(0.4) : AE.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button { previewPlaying = false; previewFrame = 0; previewAccum = 0 } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AE.txt2)
                        .frame(width: 30, height: 28)
                        .background(AE.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(AE.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 2) {
                    ForEach([CGFloat(1), 2, 4], id: \.self) { z in
                        Button("\(Int(z))×") { previewZoom = z }
                            .font(.system(size: 10, weight: previewZoom == z ? .semibold : .regular))
                            .foregroundStyle(previewZoom == z ? AE.accent : AE.txt3)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(previewZoom == z ? AE.accentSoft : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .buttonStyle(.plain)
                    }
                }
                .background(AE.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(AE.border, lineWidth: 1))

                Menu {
                    ForEach(PreviewBackground.allCases) { bg in
                        Button {
                            previewBackground = bg
                        } label: {
                            Label(bg.label, systemImage: previewBackground == bg ? "checkmark" : bg.icon)
                        }
                    }
                } label: {
                    Image(systemName: previewBackground.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(AE.txt2)
                        .frame(width: 28, height: 28)
                        .background(AE.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(AE.border, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Flip buttons row
            HStack(spacing: 6) {
                flipPreviewButton("H", isOn: Binding(
                    get: { previewFlipH },
                    set: { v in
                        previewFlipH = v
                        if previewClipIndex < config.clips.count { config.clips[previewClipIndex].flipH = v }
                    }
                ))
                flipPreviewButton("V", isOn: Binding(
                    get: { previewFlipV },
                    set: { v in
                        previewFlipV = v
                        if previewClipIndex < config.clips.count { config.clips[previewClipIndex].flipV = v }
                    }
                ))
                Spacer()
            }
            } // end VStack

            if let clip = currentPreviewClip {
                let frames = resolvedFrames(for: clip)
                HStack {
                    Text("Frame")
                        .font(.system(size: 10))
                        .foregroundStyle(AE.txt3)
                    Spacer()
                    Text("\(min(previewFrame + 1, max(1, frames.count))) / \(max(1, frames.count))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AE.txt2)
                }
                HStack {
                    Text("\(Int(clip.fps)) fps · \(clip.loops ? "loop" : "once")\(abs(clip.speed - 1.0) > 0.01 ? " · \(String(format: "%.1f×", clip.speed))" : "")")
                        .font(.system(size: 10))
                        .foregroundStyle(AE.txt3)
                    Spacer()
                    let dur = Double(frames.count) / max(1, clip.fps)
                    Text(String(format: "%.2fs", dur))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AE.txt2)
                }

                // Timeline scrub bar
                if frames.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timeline")
                            .font(.system(size: 9))
                            .foregroundStyle(AE.txt3)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(AE.field)
                                    .frame(height: 8)

                                // Frame ticks
                                ForEach(0..<frames.count, id: \.self) { i in
                                    let x = geo.size.width * CGFloat(i) / CGFloat(frames.count - 1)
                                    Rectangle()
                                        .fill(AE.border)
                                        .frame(width: 1, height: 8)
                                        .offset(x: x)
                                }

                                // Progress fill
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(AE.accent.opacity(0.5))
                                    .frame(width: frames.count > 1 ? geo.size.width * CGFloat(previewFrame) / CGFloat(frames.count - 1) : 0, height: 8)

                                // Thumb
                                let thumbX = frames.count > 1 ? geo.size.width * CGFloat(previewFrame) / CGFloat(frames.count - 1) : 0
                                Circle()
                                    .fill(AE.accent)
                                    .frame(width: 12, height: 12)
                                    .offset(x: thumbX - 6, y: 0)
                            }
                            .frame(height: 12)
                            .contentShape(Rectangle().size(CGSize(width: geo.size.width, height: 20)))
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                guard frames.count > 1 else { return }
                                isScrubbing = true
                                previewPlaying = false
                                let frac = max(0, min(1, value.location.x / geo.size.width))
                                previewFrame = min(frames.count - 1, Int(frac * CGFloat(frames.count - 1) + 0.5))
                                previewAccum = 0
                            }.onEnded { _ in isScrubbing = false })
                        }
                        .frame(height: 12)
                    }
                }
            }
        }
        .padding(12)
        .aeCard()
    }

    private var moduleSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Module Settings", icon: "gearshape")

            Toggle("Center origin", isOn: $config.centerOrigin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
                .foregroundStyle(AE.txt2)

            if !config.centerOrigin {
                infoFieldRow("Origin X") {
                    TextField("0", value: Binding(
                        get: { Int(config.offsetX.rounded()) },
                        set: { config.offsetX = Double($0) }
                    ), format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AE.txt1)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                    .aeField()
                }
                infoFieldRow("Origin Y") {
                    TextField("0", value: Binding(
                        get: { Int(config.offsetY.rounded()) },
                        set: { config.offsetY = Double($0) }
                    ), format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AE.txt1)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                    .aeField()
                }
            }

            if let clip = currentClip {
                let frames = resolvedFrames(for: clip)
                Divider().overlay(AE.border)
                infoRow("Animations", value: "\(config.clips.count)")
                infoRow("Selected",   value: clip.name.isEmpty ? "anim" : clip.name)
                infoRow("Frames",     value: "\(frames.count)")
                infoRow("Events",     value: "\(clip.events.count)")
                infoRow("Duration",   value: String(format: "%.2fs", Double(frames.count) / max(1, clip.fps)))
            }
        }
        .padding(12)
        .aeCard()
    }

    // MARK: - Shared sub-builders

    @ViewBuilder
    private var previewFrameView: some View {
        if let clip = currentPreviewClip {
            let frames = resolvedFrames(for: clip)
            if !frames.isEmpty, previewFrame < frames.count,
               let img = croppedImage(for: frames[previewFrame]) {
                ZStack {
                    // Onion skin: previous frame
                    if onionSkinEnabled && previewFrame > 0,
                       let prevImg = croppedImage(for: frames[previewFrame - 1]) {
                        Image(nsImage: prevImg)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                            .scaleEffect(x: previewFlipH ? -1 : 1, y: previewFlipV ? -1 : 1)
                            .opacity(0.3)
                            .colorMultiply(.red)
                    }
                    // Onion skin: next frame
                    if onionSkinEnabled && previewFrame + 1 < frames.count,
                       let nextImg = croppedImage(for: frames[previewFrame + 1]) {
                        Image(nsImage: nextImg)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                            .scaleEffect(x: previewFlipH ? -1 : 1, y: previewFlipV ? -1 : 1)
                            .opacity(0.3)
                            .colorMultiply(.blue)
                    }
                    // Current frame
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .scaleEffect(x: previewFlipH ? -1 : 1, y: previewFlipV ? -1 : 1)
                }
            } else {
                placeholderFilm
            }
        } else {
            placeholderFilm
        }
    }

    private var placeholderFilm: some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 28))
                .foregroundStyle(AE.txt3)
            Text("No frames")
                .font(.system(size: 10))
                .foregroundStyle(AE.txt3)
        }
    }

    private func flipPreviewButton(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn.wrappedValue ? AE.accent : AE.txt2)
                .frame(width: 28, height: 28)
                .background(isOn.wrappedValue ? AE.accentSoft : AE.surface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isOn.wrappedValue ? AE.accent.opacity(0.4) : AE.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Flip \(label == "H" ? "horizontal" : "vertical")")
    }

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AE.txt3)
            Text(text.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AE.txt3)
                .tracking(0.8)
        }
    }

    private func numField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .center, spacing: 3) {
            TextField(label, value: value, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AE.txt1)
                .multilineTextAlignment(.center)
                .frame(width: 48)
                .padding(.vertical, 5)
                .background(AE.field)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(AE.border, lineWidth: 1))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AE.txt3)
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(AE.txt3)
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(AE.txt2)
        }
    }

    private func infoFieldRow<F: View>(_ label: String, @ViewBuilder field: () -> F) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(AE.txt3)
            Spacer()
            field()
        }
    }

    // MARK: - Logic

    private var spriteSheetMetrics: SpriteSheetMetrics? {
        guard let img = spriteSheetImage else { return nil }
        let w = Int(img.size.width), h = Int(img.size.height)
        guard w > 0, h > 0 else { return nil }
        let fw = max(1, config.frameWidth), fh = max(1, config.frameHeight)
        let uw = max(0, w - max(0, config.marginX)), uh = max(0, h - max(0, config.marginY))
        let cols = max(1, (uw + max(0, config.spacingX)) / max(1, fw + max(0, config.spacingX)))
        let rows = max(1, (uh + max(0, config.spacingY)) / max(1, fh + max(0, config.spacingY)))
        return SpriteSheetMetrics(imageSize: CGSize(width: w, height: h), columns: cols, rows: rows)
    }

    private var canExport: Bool {
        !config.spriteSheetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && config.clips.contains { !resolvedFrames(for: $0).isEmpty }
    }

    private var sanitizedConfig: SpriteAnimationConfig {
        var s = config
        s.moduleName = s.moduleName.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.moduleName.isEmpty { s.moduleName = "Animation" }
        s.frameWidth  = max(1, s.frameWidth);  s.frameHeight = max(1, s.frameHeight)
        s.marginX     = max(0, s.marginX);     s.marginY     = max(0, s.marginY)
        s.spacingX    = max(0, s.spacingX);    s.spacingY    = max(0, s.spacingY)
        if s.clips.isEmpty { s.clips = [SpriteAnimationClip()] }
        s.clips = s.clips.enumerated().map { idx, clip in
            let resolved = resolvedFrames(for: clip)
            var c = clip
            c.name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if c.name.isEmpty { c.name = idx == 0 ? "idle" : "anim\(idx)" }
            c.fps = max(1, c.fps); c.startRow = max(1, c.startRow); c.startColumn = max(1, c.startColumn)
            c.frameCount = max(1, c.frameCount); c.frames = resolved; c.selectionMode = .manual
            c.events = c.events.compactMap { ev in
                let t = ev.eventName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return nil }
                var ce = ev; ce.eventName = t
                ce.framePosition = max(0, min(ce.framePosition, max(0, resolved.count - 1)))
                return ce
            }
            return c
        }
        return s
    }

    private func chooseSpriteSheet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .bmp]
        panel.message = "Select sprite sheet image"
        panel.directoryURL = projectURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var target = url
        if !url.path.hasPrefix(projectURL.path + "/") {
            let dir = projectURL.appendingPathComponent("images")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: url, to: dest) }
            target = dest
        }
        config.spriteSheetPath = target.path.hasPrefix(projectURL.path + "/")
            ? String(target.path.dropFirst(projectURL.path.count + 1))
            : target.lastPathComponent
        spriteSheetImage = NSImage(contentsOf: target)
        sanitizeSelectionsAfterGridChange()
    }

    /// Heuristic auto-detect: find frame size (from common pixel-art sizes) that divides
    /// the image evenly and gives the highest-scoring grid (prefers square frames + more frames).
    private func autoDetectGrid() {
        guard let img = spriteSheetImage else { return }
        let iw = Int(img.size.width), ih = Int(img.size.height)
        let mx = max(0, config.marginX), my = max(0, config.marginY)
        let uw = max(1, iw - mx), uh = max(1, ih - my)
        let candidates = [8, 12, 16, 24, 32, 48, 64, 96, 128, 256]

        var best: (fw: Int, fh: Int, score: Double) = (config.frameWidth, config.frameHeight, -1)

        for fw in candidates {
            guard fw <= uw, uw % fw == 0 else { continue }
            for fh in candidates {
                guard fh <= uh, uh % fh == 0 else { continue }
                let cols = uw / fw, rows = uh / fh
                // Prefer square frames; reward more frame variety (log scale)
                let squareness = 1.0 - abs(Double(fw) - Double(fh)) / Double(max(fw, fh))
                let variety    = log(Double(cols * rows) + 1)
                let score      = squareness * variety
                if score > best.score {
                    best = (fw, fh, score)
                }
            }
        }

        guard best.score >= 0 else { return }
        config.frameWidth  = best.fw
        config.frameHeight = best.fh
        flash("Detected \(best.fw)×\(best.fh)")
    }

    private func loadConfig(_ loaded: SpriteAnimationConfig) {
        config = loaded; selectedClipIndex = 0; previewClipIndex = 0
        previewFrame = 0; previewAccum = 0; previewPlaying = false
        selectedFrameID = nil
        loadSpriteSheetImageIfNeeded(); sanitizeSelectionsAfterGridChange()
    }

    private func loadSpriteSheetImageIfNeeded() {
        guard !config.spriteSheetPath.isEmpty else { spriteSheetImage = nil; return }
        spriteSheetImage = NSImage(contentsOf: projectURL.appendingPathComponent(config.spriteSheetPath))
    }

    private func flash(_ msg: String) {
        saveStatus = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if saveStatus == msg { saveStatus = "" } }
    }

    private func advancePreviewTick() {
        guard previewPlaying, let clip = currentPreviewClip else { return }
        let frames = resolvedFrames(for: clip); guard !frames.isEmpty else { return }
        previewAccum += 1.0/60.0
        let defaultInterval = 1.0 / max(1, clip.fps)
        let f = previewFrame < frames.count ? frames[previewFrame] : nil
        // Respect per-frame duration and repeat count for the preview
        let interval = (f?.duration ?? defaultInterval) * Double(max(1, f?.repeatCount ?? 1))
        while previewAccum >= interval {
            previewAccum -= interval
            if previewFrame + 1 < frames.count { previewFrame += 1 }
            else if clip.loops { previewFrame = 0 }
            else { previewFrame = max(0, frames.count - 1); previewPlaying = false; break }
        }
    }

    private func resolvedFrames(for clip: SpriteAnimationClip) -> [SpriteAnimationFrameSelection] {
        if clip.selectionMode == .manual || !clip.frames.isEmpty { return validatedFrames(clip.frames) }
        guard let m = spriteSheetMetrics else { return [] }
        let sr = max(1, min(clip.startRow, m.rows)), sc = max(1, min(clip.startColumn, m.columns))
        let start = (sr - 1) * m.columns + (sc - 1)
        let count = max(1, min(clip.frameCount, max(1, m.columns * m.rows - start)))
        return (0..<count).map { offset in
            let abs = start + offset
            return SpriteAnimationFrameSelection(row: abs / m.columns + 1, column: abs % m.columns + 1)
        }
    }

    private func validatedFrames(_ frames: [SpriteAnimationFrameSelection]) -> [SpriteAnimationFrameSelection] {
        guard let m = spriteSheetMetrics else { return frames }
        return frames.filter { $0.row >= 1 && $0.row <= m.rows && $0.column >= 1 && $0.column <= m.columns }
    }

    private func selectedFrameIndices(for clip: SpriteAnimationClip) -> [Int] {
        guard let m = spriteSheetMetrics else { return [] }
        return resolvedFrames(for: clip).compactMap { f in
            guard f.row >= 1, f.column >= 1, f.row <= m.rows, f.column <= m.columns else { return nil }
            return (f.row - 1) * m.columns + (f.column - 1)
        }
    }

    private func frameForIndex(_ index: Int) -> SpriteAnimationFrameSelection? {
        guard let m = spriteSheetMetrics, index >= 0 else { return nil }
        let r = index / m.columns + 1, c = index % m.columns + 1
        guard r <= m.rows, c <= m.columns else { return nil }
        return SpriteAnimationFrameSelection(row: r, column: c)
    }

    private func toggleFrame(_ index: Int) {
        guard safeClipIndex < config.clips.count, let frame = frameForIndex(index) else { return }
        materializeClipFrames(at: safeClipIndex)
        if let ei = config.clips[safeClipIndex].frames.firstIndex(where: { $0.row == frame.row && $0.column == frame.column }) {
            let removedID = config.clips[safeClipIndex].frames[ei].id
            config.clips[safeClipIndex].frames.remove(at: ei)
            removeEventsIfNeeded(afterRemovingFrameAt: ei)
            if selectedFrameID == removedID { selectedFrameID = nil }
        } else {
            config.clips[safeClipIndex].frames.append(frame)
        }
        previewFrame = 0
    }

    private func addFrameRange(from lower: Int, to upper: Int) {
        guard safeClipIndex < config.clips.count else { return }
        materializeClipFrames(at: safeClipIndex)
        for i in lower...upper {
            guard let f = frameForIndex(i) else { continue }
            if !config.clips[safeClipIndex].frames.contains(where: { $0.row == f.row && $0.column == f.column }) {
                config.clips[safeClipIndex].frames.append(f)
            }
        }
        previewFrame = 0
    }

    private func addRowRange(row: Int, colStart: Int, colEnd: Int) {
        guard safeClipIndex < config.clips.count, let m = spriteSheetMetrics else { return }
        materializeClipFrames(at: safeClipIndex)
        let clampedRow = max(1, min(row, m.rows))
        let cs = max(1, min(colStart, m.columns))
        let ce = max(cs, min(colEnd, m.columns))
        for col in cs...ce {
            let frame = SpriteAnimationFrameSelection(row: clampedRow, column: col)
            if !config.clips[safeClipIndex].frames.contains(where: { $0.row == frame.row && $0.column == frame.column }) {
                config.clips[safeClipIndex].frames.append(frame)
            }
        }
        previewFrame = 0
        selectedFrameID = nil
    }

    private func materializeClipFrames(at index: Int) {
        guard index < config.clips.count else { return }
        let frames = resolvedFrames(for: config.clips[index])
        config.clips[index].frames = frames; config.clips[index].selectionMode = .manual
        config.clips[index].frameCount = max(1, frames.count)
    }

    private func removeFrame(at position: Int) {
        guard safeClipIndex < config.clips.count else { return }
        materializeClipFrames(at: safeClipIndex)
        guard position < config.clips[safeClipIndex].frames.count else { return }
        config.clips[safeClipIndex].frames.remove(at: position)
        removeEventsIfNeeded(afterRemovingFrameAt: position)
        previewFrame = 0
    }

    private func clearFrames() {
        guard safeClipIndex < config.clips.count else { return }
        materializeClipFrames(at: safeClipIndex)
        config.clips[safeClipIndex].frames.removeAll()
        config.clips[safeClipIndex].events.removeAll()
        previewFrame = 0
    }

    private func moveFrame(from source: Int, to destination: Int) {
        guard safeClipIndex < config.clips.count, source != destination else { return }
        materializeClipFrames(at: safeClipIndex)
        guard source < config.clips[safeClipIndex].frames.count,
              destination < config.clips[safeClipIndex].frames.count else { return }
        let f = config.clips[safeClipIndex].frames.remove(at: source)
        config.clips[safeClipIndex].frames.insert(f, at: destination)
        previewFrame = min(previewFrame, max(0, config.clips[safeClipIndex].frames.count - 1))
    }

    private func removeEventsIfNeeded(afterRemovingFrameAt position: Int) {
        guard safeClipIndex < config.clips.count else { return }
        config.clips[safeClipIndex].events = config.clips[safeClipIndex].events.compactMap { ev in
            if ev.framePosition == position { return nil }
            var a = ev; if a.framePosition > position { a.framePosition -= 1 }; return a
        }
    }

    private func addClip() {
        let clip = SpriteAnimationClip(name: "anim\(config.clips.count)")
        config.clips.append(clip)
        selectedClipIndex = config.clips.count - 1
        previewClipIndex  = selectedClipIndex
        previewFrame = 0
        selectedFrameID = nil
    }

    private func duplicateClip() {
        guard !config.clips.isEmpty else { return }
        var copy = config.clips[safeClipIndex]; copy.id = UUID()
        copy.name = (copy.name.isEmpty ? "anim" : copy.name) + "_copy"
        copy.events = copy.events.map { var e = $0; e.id = UUID(); return e }
        copy.frames = copy.frames.map { var f = $0; f.id = UUID(); return f }
        config.clips.append(copy)
        selectedClipIndex = config.clips.count - 1
        previewClipIndex  = selectedClipIndex
        previewFrame = 0
        selectedFrameID = nil
    }

    private func removeClip(at index: Int) {
        guard config.clips.count > 1, index < config.clips.count else { return }
        config.clips.remove(at: index)
        selectedClipIndex = max(0, min(selectedClipIndex, config.clips.count - 1))
        previewClipIndex  = max(0, min(previewClipIndex,  config.clips.count - 1))
        previewFrame = 0
        selectedFrameID = nil
    }

    private func addEvent() {
        guard safeClipIndex < config.clips.count else { return }
        let fc = resolvedFrames(for: config.clips[safeClipIndex]).count
        guard fc > 0 else { return }
        config.clips[safeClipIndex].events.append(SpriteAnimationEvent(framePosition: 0, eventName: "event"))
    }

    private func sanitizeSelectionsAfterGridChange() {
        guard !config.clips.isEmpty else { return }
        for i in config.clips.indices {
            config.clips[i].frames = validatedFrames(config.clips[i].frames)
            let fc = resolvedFrames(for: config.clips[i]).count
            config.clips[i].events = config.clips[i].events.compactMap { ev in
                let t = ev.eventName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return nil }
                var a = ev; a.eventName = t
                a.framePosition = max(0, min(ev.framePosition, max(0, fc - 1)))
                return a
            }
        }
        previewFrame = 0
    }

    private func croppedImage(for frame: SpriteAnimationFrameSelection) -> NSImage? {
        guard let img = spriteSheetImage,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rect = frameRect(for: frame),
              let cropped = cg.cropping(to: rect.integral) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: rect.width, height: rect.height))
    }

    private func frameRect(for frame: SpriteAnimationFrameSelection) -> CGRect? {
        guard let m = spriteSheetMetrics,
              frame.row >= 1, frame.column >= 1,
              frame.row <= m.rows, frame.column <= m.columns else { return nil }
        let fw = CGFloat(max(1, config.frameWidth)), fh = CGFloat(max(1, config.frameHeight))
        let sx = CGFloat(max(0, config.spacingX)), sy = CGFloat(max(0, config.spacingY))
        let mx = CGFloat(max(0, config.marginX)),  my = CGFloat(max(0, config.marginY))
        return CGRect(x: mx + CGFloat(frame.column - 1) * (fw + sx),
                      y: my + CGFloat(frame.row    - 1) * (fh + sy),
                      width: fw, height: fh)
    }
}
