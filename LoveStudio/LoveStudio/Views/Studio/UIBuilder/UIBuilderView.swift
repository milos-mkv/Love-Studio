import SwiftUI
import AppKit
import CoreText
import UniformTypeIdentifiers

private enum UIImagePreviewCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for key: String, loader: () -> NSImage?) -> NSImage? {
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) { return cached }
        guard let image = loader() else { return nil }
        cache.setObject(image, forKey: nsKey)
        return image
    }
}

// MARK: - Main View

struct UIBuilderView: View {

    let projectURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var config        = UIBuilderConfig()
    @State private var selectedID:   UIElement.ID? = nil
    @State private var statusMsg     = ""
    @State private var statusOK      = true
    @State private var showLoad      = false
    @State private var savedConfigs: [UIBuilderConfig] = []
    @State private var canvasZoom: CGFloat = 1.0

    // Drag / resize state
    @State private var draggedID:     UIElement.ID? = nil
    @State private var dragOrigin:    CGPoint       = .zero
    @State private var dragStartPos:  CGPoint       = .zero
    @State private var resizeCorner:  ResizeCorner? = nil   // nil = move, non-nil = resize
    @State private var resizeOriginW: Double        = 0
    @State private var resizeOriginH: Double        = 0

    private enum ResizeCorner { case topLeft, topRight, bottomLeft, bottomRight }

    private var selectedElement: Binding<UIElement>? {
        guard let id = selectedID,
              let idx = config.elements.firstIndex(where: { $0.id == id })
        else { return nil }
        return $config.elements[idx]
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                leftColumn
                Divider()
                canvasColumn
                Divider()
                rightColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1060, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .foregroundStyle(.pink)
                    .font(.system(size: 15, weight: .semibold))

                Text("UI Builder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 18)

            TextField("UI name", text: $config.moduleName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(width: 180)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )

            Spacer()

            if !statusMsg.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: statusOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(statusMsg)
                }
                .font(.system(size: 11))
                .foregroundStyle(statusOK ? .green : .red)
                .transition(.opacity)
            }

            Button { showLoad = true } label: {
                Label("Load", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showLoad) {
                loadPopover
                    .onAppear { savedConfigs = UIBuilderStore.loadAll(from: projectURL) }
            }

            Button {
                do {
                    try UIBuilderStore.save(config, to: projectURL)
                    flash("Saved", ok: true)
                } catch {
                    flash("Save failed: \(error.localizedDescription)", ok: false)
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                do {
                    let code = UICodeGenerator.generate(config: config)
                    try UIBuilderStore.exportLua(code, moduleName: config.moduleName, to: projectURL)
                    flash("Exported \(UIBuilderStore.safeName(config.moduleName)).lua", ok: true)
                } catch {
                    flash("Export failed: \(error.localizedDescription)", ok: false)
                }
            } label: {
                Label("Export", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            .controlSize(.small)

            Divider().frame(height: 16)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Left column (element list)

    private var leftColumn: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("ELEMENTS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(config.elements.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Add element menu
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                spacing: 6
            ) {
                ForEach(UIElementType.allCases) { type in
                    Button {
                        addElement(type: type)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.system(size: 12))
                            Text(type.displayName)
                                .font(.system(size: 9))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.pink.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.pink.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.pink)
                    .help("Add \(type.displayName)")
                }
            }
            .padding(8)

            Divider()

            // List
            if config.elements.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Click a type above\nto add an element")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach($config.elements) { $el in
                        UIElementRow(element: el)
                            .tag(el.id)
                    }
                    .onMove { from, to in config.elements.move(fromOffsets: from, toOffset: to) }
                    .onDelete { idx in
                        config.elements.remove(atOffsets: idx)
                        selectedID = nil
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            // Bottom toolbar
            HStack(spacing: 4) {
                Spacer()
                Button {
                    guard let id = selectedID,
                          let idx = config.elements.firstIndex(where: { $0.id == id })
                    else { return }
                    config.elements.remove(at: idx)
                    selectedID = nil
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(4)
                .disabled(selectedID == nil)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(width: 260)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Canvas column (preview)

    private var canvasColumn: some View {
        VStack(spacing: 0) {
            // Toolbar bar
            HStack(spacing: 8) {
                Text("Canvas")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("W", value: $config.canvasWidth, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .font(.system(size: 11))
                Text("×")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                TextField("H", value: $config.canvasHeight, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .font(.system(size: 11))

                Spacer()

                Text("Click element to select")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Divider().frame(height: 14)

                // Zoom controls
                Button {
                    canvasZoom = max(0.25, canvasZoom - 0.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Zoom out")

                Text("\(Int(canvasZoom * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 38)

                Button {
                    canvasZoom = min(4.0, canvasZoom + 0.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Zoom in")

                Button {
                    canvasZoom = 1.0
                } label: {
                    Image(systemName: "1.magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reset zoom")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Preview canvas
            ZStack {
                // Dot-grid background
                Color(nsColor: .underPageBackgroundColor)
                    .overlay(
                        Canvas { ctx, size in
                            var ctx = ctx
                            ctx.opacity = 0.18
                            let step: CGFloat = 20
                            var x: CGFloat = 0
                            while x < size.width {
                                var y: CGFloat = 0
                                while y < size.height {
                                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                             with: .color(.secondary))
                                    y += step
                                }
                                x += step
                            }
                        }
                    )

                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        // Canvas outline shadow
                        Canvas { ctx, _ in
                            drawCanvas(ctx: ctx,
                                       canvasW: CGFloat(config.canvasWidth),
                                       canvasH: CGFloat(config.canvasHeight))
                        }
                        .frame(width:  CGFloat(config.canvasWidth),
                               height: CGFloat(config.canvasHeight))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    let loc = CGPoint(
                                        x: value.startLocation.x / canvasZoom,
                                        y: value.startLocation.y / canvasZoom
                                    )

                                    // ── Initialize on first change ────────────────────
                                    if draggedID == nil {
                                        // Check corner handles first (only for selected element)
                                        if let selID = selectedID,
                                           let el = config.elements.first(where: { $0.id == selID }),
                                           let corner = hitCorner(at: loc, element: el) {
                                            draggedID     = selID
                                            resizeCorner  = corner
                                            dragOrigin    = CGPoint(x: el.x, y: el.y)
                                            resizeOriginW = el.width
                                            resizeOriginH = el.height
                                            dragStartPos  = loc
                                        } else if let hit = hitElement(at: loc) {
                                            // Normal move
                                            draggedID    = hit.id
                                            resizeCorner = nil
                                            dragOrigin   = CGPoint(x: hit.x, y: hit.y)
                                            dragStartPos = loc
                                            selectedID   = hit.id
                                        }
                                    }

                                    guard let id  = draggedID,
                                          let idx = config.elements.firstIndex(where: { $0.id == id })
                                    else { return }

                                    let dx = value.translation.width  / canvasZoom
                                    let dy = value.translation.height / canvasZoom

                                    if let corner = resizeCorner {
                                        // ── Resize ────────────────────────────────────
                                        let minSz: Double = 16
                                        switch corner {
                                        case .bottomRight:
                                            config.elements[idx].width  = max(minSz, resizeOriginW + dx)
                                            config.elements[idx].height = max(minSz, resizeOriginH + dy)
                                        case .bottomLeft:
                                            let newW = max(minSz, resizeOriginW - dx)
                                            config.elements[idx].x     = dragOrigin.x + (resizeOriginW - newW)
                                            config.elements[idx].width  = newW
                                            config.elements[idx].height = max(minSz, resizeOriginH + dy)
                                        case .topRight:
                                            let newH = max(minSz, resizeOriginH - dy)
                                            config.elements[idx].y      = dragOrigin.y + (resizeOriginH - newH)
                                            config.elements[idx].width   = max(minSz, resizeOriginW + dx)
                                            config.elements[idx].height  = newH
                                        case .topLeft:
                                            let newW = max(minSz, resizeOriginW - dx)
                                            let newH = max(minSz, resizeOriginH - dy)
                                            config.elements[idx].x      = dragOrigin.x + (resizeOriginW - newW)
                                            config.elements[idx].y      = dragOrigin.y + (resizeOriginH - newH)
                                            config.elements[idx].width   = newW
                                            config.elements[idx].height  = newH
                                        }
                                    } else {
                                        // ── Move ──────────────────────────────────────
                                        config.elements[idx].x = max(0, dragOrigin.x + dx)
                                        config.elements[idx].y = max(0, dragOrigin.y + dy)
                                    }
                                }
                                .onEnded { value in
                                    let dist = hypot(value.translation.width, value.translation.height)
                                    if dist < 4 {
                                        let loc = CGPoint(x: value.startLocation.x / canvasZoom,
                                                          y: value.startLocation.y / canvasZoom)
                                        selectElementAt(loc)
                                    }
                                    draggedID    = nil
                                    resizeCorner = nil
                                }
                        )
                    }
                    .frame(width:  CGFloat(config.canvasWidth)  * canvasZoom,
                           height: CGFloat(config.canvasHeight) * canvasZoom)
                    .scaleEffect(canvasZoom, anchor: .topLeading)
                    .padding(32)
                }
            }
        }
        .frame(minWidth: 500)
    }

    // MARK: - Right column (properties)

    private var rightColumn: some View {
        Group {
            if let binding = selectedElement {
                ScrollView {
                    UIElementPropertiesView(element: binding, projectURL: projectURL)
                        .padding(16)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.click")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Select an element\nto edit its properties")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 260)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Font loading for canvas preview

    /// Returns a SwiftUI Font for the element: tries to load the actual TTF file from
    /// the Font Manager config, falls back to .system(size:).
    private func previewFont(for element: UIElement) -> Font {
        let s = element.style
        let size = CGFloat(s.fontSize)
        guard !s.fontManagerModule.isEmpty, !s.fontManagerKey.isEmpty else {
            return .system(size: size)
        }
        // Find the matching FontEntry in saved configs
        let configs = FontManagerStore.loadAll(from: projectURL)
        guard let cfg = configs.first(where: { FontManagerStore.safeName($0.moduleName) == s.fontManagerModule }),
              let entry = cfg.entries.first(where: { FontCodeGenerator.luaIdent($0.name) == s.fontManagerKey }),
              entry.source == .file,
              !entry.filePath.isEmpty
        else {
            return .system(size: size)
        }
        let fontURL = entry.filePath.hasPrefix("/")
            ? URL(fileURLWithPath: entry.filePath)
            : projectURL.appendingPathComponent(entry.filePath)
        if let cfArray = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL),
           let descs = cfArray as? [CTFontDescriptor],
           let desc = descs.first {
            return Font(CTFontCreateWithFontDescriptor(desc, size, nil) as NSFont)
        }
        return .system(size: size)
    }

    /// Returns the FontEntry for an element if it has outline enabled, otherwise nil.
    private func outlineEntry(for element: UIElement) -> FontEntry? {
        let s = element.style
        guard !s.fontManagerModule.isEmpty, !s.fontManagerKey.isEmpty else { return nil }
        let configs = FontManagerStore.loadAll(from: projectURL)
        guard let cfg = configs.first(where: { FontManagerStore.safeName($0.moduleName) == s.fontManagerModule }),
              let entry = cfg.entries.first(where: { FontCodeGenerator.luaIdent($0.name) == s.fontManagerKey }),
              entry.outlineEnabled else { return nil }
        return entry
    }

    /// Draw text with optional outline onto the canvas context.
    private func drawText(_ ctx: inout GraphicsContext, text: String, at point: CGPoint,
                          anchor: UnitPoint = .center, font: Font, color: Color, element: UIElement) {
        if let ol = outlineEntry(for: element) {
            let olColor = Color(red: Double(ol.outlineR)/255, green: Double(ol.outlineG)/255,
                                blue: Double(ol.outlineB)/255, opacity: Double(ol.outlineA)/255)
            let s = CGFloat(ol.outlineSize)
            for dx in stride(from: -s, through: s, by: 1) {
                for dy in stride(from: -s, through: s, by: 1) {
                    if dx == 0 && dy == 0 { continue }
                    ctx.draw(Text(text).font(font).foregroundStyle(olColor),
                             at: CGPoint(x: point.x + dx, y: point.y + dy), anchor: anchor)
                }
            }
        }
        ctx.draw(Text(text).font(font).foregroundStyle(color), at: point, anchor: anchor)
    }

    // MARK: - Canvas draw

    private func drawCanvas(ctx: GraphicsContext, canvasW: CGFloat, canvasH: CGFloat) {
        var ctx = ctx

        // Canvas background
        ctx.fill(Path(CGRect(x: 0, y: 0, width: canvasW, height: canvasH)),
                 with: .color(config.canvasBg.swiftUI))

        // Draw each element
        for el in config.elements {
            drawElement(ctx: &ctx, element: el, selected: el.id == selectedID)
        }
    }

    private func drawElement(ctx: inout GraphicsContext, element: UIElement, selected: Bool) {
        let x  = CGFloat(element.x)
        let y  = CGFloat(element.y)
        let w  = CGFloat(element.width)
        let h  = CGFloat(element.height)
        let s  = element.style
        let r  = CGFloat(s.cornerRadius)
        let rect = CGRect(x: x, y: y, width: w, height: h)

        switch element.type {

        case .button:
            ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(s.bgColor.swiftUI))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: r), with: .color(s.borderColor.swiftUI), lineWidth: CGFloat(s.borderWidth))
            let textPad = min(CGFloat(s.padding), max(2, w - 4))
            drawText(&ctx, text: element.label,
                     at: CGPoint(x: x + textPad, y: y + h * 0.5),
                     anchor: .leading,
                     font: previewFont(for: element), color: s.textColor.swiftUI, element: element)

        case .label:
            drawText(&ctx, text: element.label, at: CGPoint(x: x + w * 0.5, y: y + h * 0.5),
                     font: previewFont(for: element), color: s.textColor.swiftUI, element: element)

        case .slider:
            // Track
            let trackRect = CGRect(x: x, y: y + h * 0.5 - 3, width: w, height: 6)
            ctx.fill(Path(roundedRect: trackRect, cornerRadius: 3), with: .color(s.trackColor.swiftUI))
            // Fill
            let t       = CGFloat((element.value - element.minValue) / max(0.001, element.maxValue - element.minValue))
            let fillRect = CGRect(x: x, y: y + h * 0.5 - 3, width: w * t, height: 6)
            ctx.fill(Path(roundedRect: fillRect, cornerRadius: 3), with: .color(s.accentColor.swiftUI))
            // Thumb
            let thumbX  = x + t * w
            let thumbSz = CGFloat(s.thumbSize)
            ctx.fill(Path(ellipseIn: CGRect(x: thumbX - thumbSz * 0.5, y: y + h * 0.5 - thumbSz * 0.5, width: thumbSz, height: thumbSz)),
                     with: .color(s.thumbColor.swiftUI))

        case .checkbox:
            let sz = h - 4
            let bx = x + 2, by = y + 2
            let boxRect = CGRect(x: bx, y: by, width: sz, height: sz)
            ctx.fill(Path(roundedRect: boxRect, cornerRadius: 4),
                     with: .color(element.checked ? s.accentColor.swiftUI : s.bgColor.swiftUI))
            ctx.stroke(Path(roundedRect: boxRect, cornerRadius: 4),
                       with: .color(s.borderColor.swiftUI), lineWidth: CGFloat(s.borderWidth))
            if element.checked {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: bx + 4, y: by + sz * 0.5))
                    p.addLine(to: CGPoint(x: bx + sz * 0.35, y: by + sz - 4))
                    p.addLine(to: CGPoint(x: bx + sz - 4, y: by + 4))
                }, with: .color(s.textColor.swiftUI), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            drawText(&ctx, text: element.label, at: CGPoint(x: x + sz + 20, y: y + h * 0.5),
                     anchor: .leading, font: previewFont(for: element), color: s.textColor.swiftUI, element: element)

        case .radioButton:
            let rr  = (h - 4) * 0.5
            let cx2 = x + rr + 2, cy2 = y + h * 0.5
            ctx.fill(Path(ellipseIn: CGRect(x: cx2 - rr, y: cy2 - rr, width: rr * 2, height: rr * 2)),
                     with: .color(element.checked ? s.accentColor.swiftUI : s.bgColor.swiftUI))
            ctx.stroke(Path(ellipseIn: CGRect(x: cx2 - rr, y: cy2 - rr, width: rr * 2, height: rr * 2)),
                       with: .color(s.borderColor.swiftUI), lineWidth: CGFloat(s.borderWidth))
            if element.checked {
                let ir = rr * 0.45
                ctx.fill(Path(ellipseIn: CGRect(x: cx2 - ir, y: cy2 - ir, width: ir * 2, height: ir * 2)),
                         with: .color(s.textColor.swiftUI))
            }
            drawText(&ctx, text: element.label, at: CGPoint(x: cx2 + rr + 8, y: y + h * 0.5),
                     anchor: .leading, font: previewFont(for: element), color: s.textColor.swiftUI, element: element)

        case .progressBar:
            ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(s.trackColor.swiftUI))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: r), with: .color(s.borderColor.swiftUI), lineWidth: CGFloat(s.borderWidth))
            let t   = CGFloat((element.value - element.minValue) / max(0.001, element.maxValue - element.minValue))
            let fillW = max(0, (w - 2) * t)
            if fillW > 0 {
                ctx.fill(Path(roundedRect: CGRect(x: x + 1, y: y + 1, width: fillW, height: h - 2), cornerRadius: max(0, r - 1)),
                         with: .color(s.accentColor.swiftUI))
            }
            drawText(&ctx, text: String(format: "%d%%", Int(t * 100)), at: CGPoint(x: x + w * 0.5, y: y + h * 0.5),
                     font: previewFont(for: element), color: s.textColor.swiftUI, element: element)

        case .panel:
            ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(s.bgColor.swiftUI))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: r), with: .color(s.borderColor.swiftUI), lineWidth: CGFloat(s.borderWidth))
            drawText(&ctx, text: element.label, at: CGPoint(x: x + CGFloat(s.padding), y: y + CGFloat(s.padding) + CGFloat(s.fontSize) * 0.5),
                     anchor: .leading, font: previewFont(for: element), color: s.textColor.swiftUI, element: element)

        case .textInput:
            ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(s.bgColor.swiftUI))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: r), with: .color(s.borderColor.swiftUI), lineWidth: CGFloat(s.borderWidth))
            ctx.draw(Text(element.placeholder).font(previewFont(for: element)).foregroundStyle(s.textColor.swiftUI.opacity(0.4)),
                     at: CGPoint(x: x + CGFloat(s.padding), y: y + h * 0.5), anchor: .leading)

        case .image:
            let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
            let shapePath = shape.path(in: rect)
            ctx.fill(shapePath, with: .color(s.bgColor.swiftUI))

            if let image = previewImage(for: element) {
                ctx.draw(Image(nsImage: image), in: rect)
            } else {
                ctx.draw(Text("[ image ]").font(previewFont(for: element)).foregroundStyle(s.textColor.swiftUI.opacity(0.5)),
                         at: CGPoint(x: x + w * 0.5, y: y + h * 0.5))
            }

            ctx.stroke(shapePath, with: .color(s.borderColor.swiftUI), lineWidth: CGFloat(s.borderWidth))

        case .scrollBar:
            ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(s.trackColor.swiftUI))
            let thumbH  = max(20, h * 0.25)
            let travel  = h - thumbH
            let thumbY2 = y + CGFloat(element.value) * travel
            ctx.fill(Path(roundedRect: CGRect(x: x + 2, y: thumbY2, width: w - 4, height: thumbH), cornerRadius: 4),
                     with: .color(s.thumbColor.swiftUI))
        }

        // Selection highlight
        if selected {
            let isDragging = element.id == draggedID
            ctx.stroke(
                Path(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: r + 2),
                with: .color(isDragging ? .yellow : .pink),
                style: StrokeStyle(lineWidth: isDragging ? 2 : 1.5, dash: isDragging ? [] : [4, 3])
            )
            // Corner handles
            let handles: [CGPoint] = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY),
            ]
            for pt in handles {
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                         with: .color(isDragging ? .yellow : .pink))
            }
        }
    }

    // MARK: - Canvas interaction

    private func selectElementAt(_ location: CGPoint) {
        selectedID = hitElement(at: location)?.id
    }

    private func hitElement(at location: CGPoint) -> UIElement? {
        config.elements.last(where: { el in
            CGRect(x: el.x, y: el.y, width: el.width, height: el.height).contains(location)
        })
    }

    /// Returns which corner handle (if any) the point is within ~10 canvas-px of.
    private func hitCorner(at loc: CGPoint, element el: UIElement) -> ResizeCorner? {
        let r: CGFloat = 10 / canvasZoom   // hit radius scales with zoom
        let corners: [(ResizeCorner, CGPoint)] = [
            (.topLeft,     CGPoint(x: el.x,            y: el.y)),
            (.topRight,    CGPoint(x: el.x + el.width, y: el.y)),
            (.bottomLeft,  CGPoint(x: el.x,            y: el.y + el.height)),
            (.bottomRight, CGPoint(x: el.x + el.width, y: el.y + el.height)),
        ]
        return corners.first(where: { _, pt in
            hypot(loc.x - pt.x, loc.y - pt.y) <= r
        })?.0
    }

    // MARK: - Add element

    private func addElement(type: UIElementType) {
        let name  = uniqueName(base: type.rawValue)
        var el    = UIElement(type: type,
                              name: name,
                              label: type.displayName,
                              x: Double.random(in: 20...200),
                              y: Double.random(in: 20...200),
                              width: type.defaultWidth,
                              height: type.defaultHeight)
        // sensible defaults per type
        switch type {
        case .label:       el.style.bgColor = .transparent
        case .progressBar: el.value = 0.6
        case .checkbox:    el.checked = false
        case .scrollBar:   el.horizontal = false
        default: break
        }
        config.elements.append(el)
        selectedID = el.id
    }

    private func uniqueName(base: String) -> String {
        var idx = 1
        var candidate = base
        while config.elements.contains(where: { $0.name == candidate }) {
            candidate = "\(base)\(idx)"
            idx += 1
        }
        return candidate
    }

    private func previewImage(for element: UIElement) -> NSImage? {
        guard !element.imagePath.isEmpty else { return nil }
        let url = resolvedImageURL(for: element.imagePath)
        return UIImagePreviewCache.image(for: url.path) {
            NSImage(contentsOf: url)
        }
    }

    private func resolvedImageURL(for path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return projectURL.appendingPathComponent(path)
    }

    // MARK: - Load popover

    private var loadPopover: some View {
        VStack(spacing: 0) {
            Text("Saved Configs")
                .font(.system(size: 12, weight: .semibold))
                .padding(10)
            Divider()
            if savedConfigs.isEmpty {
                Text("No saved configs.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ForEach(savedConfigs) { cfg in
                    Button {
                        config   = cfg
                        showLoad = false
                        selectedID = nil
                    } label: {
                        HStack {
                            Text(cfg.moduleName)
                            Spacer()
                            Text("\(cfg.elements.count) elements")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 220)
    }

    // MARK: - Helpers

    private func flash(_ msg: String, ok: Bool) {
        statusMsg = msg; statusOK = ok
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { if statusMsg == msg { statusMsg = "" } }
        }
    }
}

// MARK: - Element row

private struct UIElementRow: View {
    let element: UIElement
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: element.type.icon)
                .font(.system(size: 12))
                .foregroundStyle(.pink)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(element.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(element.type.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Properties panel

private struct UIElementPropertiesView: View {
    @Binding var element: UIElement
    let projectURL: URL

    @State private var fontConfigs: [FontManagerConfig] = []
    @State private var imageImportStatus = ""
    @State private var imageImportOK = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: element.type.icon).foregroundStyle(.pink)
                Text(element.type.displayName).font(.headline)
            }

            // Identity
            PropSection(title: "IDENTITY") {
                PropRow(label: "Name") {
                    TextField("name", text: $element.name)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                }
                PropRow(label: "Label") {
                    TextField("label", text: $element.label)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                }
                PropRow(label: "Enabled") {
                    Toggle("", isOn: $element.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }

            // Position & size
            PropSection(title: "POSITION & SIZE") {
                HStack(spacing: 8) {
                    numField("X", value: $element.x)
                    numField("Y", value: $element.y)
                }
                HStack(spacing: 8) {
                    numField("W", value: $element.width)
                    numField("H", value: $element.height)
                }
            }

            // Type-specific
            typeSpecificSection

            // Style
            PropSection(title: "STYLE") {
                colorRow("Background",   color: $element.style.bgColor)
                colorRow("Text",         color: $element.style.textColor)
                colorRow("Border",       color: $element.style.borderColor)
                colorRow("Accent",       color: $element.style.accentColor)
                colorRow("Hover",        color: $element.style.hoverColor)
                if element.type == .slider || element.type == .scrollBar {
                    colorRow("Track",    color: $element.style.trackColor)
                    colorRow("Thumb",    color: $element.style.thumbColor)
                }
                PropRow(label: "Radius") {
                    numField("", value: $element.style.cornerRadius)
                }
                PropRow(label: "Border W") {
                    numField("", value: $element.style.borderWidth)
                }
                fontPickerRow
                PropRow(label: "Font size") {
                    let locked = !element.style.fontManagerKey.isEmpty
                    HStack(spacing: 6) {
                        numField("", value: $element.style.fontSize)
                            .disabled(locked)
                            .opacity(locked ? 0.4 : 1)
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                PropRow(label: "Padding") {
                    numField("", value: $element.style.padding)
                }
            }
        }
        .onAppear { fontConfigs = FontManagerStore.loadAll(from: projectURL) }
    }

    // MARK: - Font Manager picker

    @ViewBuilder
    private var fontPickerRow: some View {
        if !fontConfigs.isEmpty && fontConfigs.contains(where: { !$0.entries.isEmpty }) {
            PropRow(label: "Font") {
                Menu {
                    Button("None (default size)") {
                        element.style.fontManagerModule = ""
                        element.style.fontManagerKey    = ""
                    }
                    Divider()
                    ForEach(fontConfigs) { cfg in
                        let mod = FontManagerStore.safeName(cfg.moduleName)
                        Section(mod) {
                            ForEach(cfg.entries) { e in
                                let key = FontCodeGenerator.luaIdent(e.name)
                                Button("\(e.name)  (\(e.size)px)") {
                                    element.style.fontManagerModule = mod
                                    element.style.fontManagerKey    = key
                                    element.style.fontSize          = Double(e.size)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if element.style.fontManagerKey.isEmpty {
                            Text("Default")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(element.style.fontManagerModule)·\(element.style.fontManagerKey)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.yellow)
                        }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var typeSpecificSection: some View {
        switch element.type {
        case .slider, .progressBar:
            PropSection(title: "VALUE") {
                PropRow(label: "Value") {
                    HStack {
                        Slider(value: $element.value, in: element.minValue...element.maxValue)
                        Text(String(format: "%.2f", element.value))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 40)
                    }
                }
                HStack(spacing: 8) {
                    numField("Min", value: $element.minValue)
                    numField("Max", value: $element.maxValue)
                }
            }
        case .checkbox, .radioButton:
            PropSection(title: "STATE") {
                PropRow(label: "Checked") {
                    Toggle("", isOn: $element.checked).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        case .textInput:
            PropSection(title: "TEXT INPUT") {
                PropRow(label: "Placeholder") {
                    TextField("placeholder", text: $element.placeholder)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                }
            }
        case .image:
            PropSection(title: "IMAGE") {
                PropRow(label: "Path") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            TextField("images/img.png", text: $element.imagePath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))

                            Button("Choose") {
                                chooseImageFile()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !imageImportStatus.isEmpty {
                            Text(imageImportStatus)
                                .font(.system(size: 10))
                                .foregroundColor(imageImportOK ? .secondary : .red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        case .scrollBar:
            PropSection(title: "SCROLL BAR") {
                PropRow(label: "Value") {
                    HStack {
                        Slider(value: $element.value, in: 0...1)
                        Text(String(format: "%.2f", element.value))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 40)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private func numField(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 64)
        }
    }

    private func colorRow(_ label: String, color: Binding<UIColor4>) -> some View {
        PropRow(label: label) {
            ColorPicker("", selection: Binding(
                get: { Color(red: color.r.wrappedValue, green: color.g.wrappedValue, blue: color.b.wrappedValue, opacity: color.a.wrappedValue) },
                set: { newColor in
                    let c = NSColor(newColor)
                    color.wrappedValue = UIColor4(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
                }
            ))
            .labelsHidden()
            .frame(width: 28, height: 22)
        }
    }

    private func chooseImageFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Image"
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        do {
            let resolvedPath = try importImageFile(from: selectedURL)
            element.imagePath = resolvedPath
            imageImportStatus = "Using \(resolvedPath)"
            imageImportOK = true
        } catch {
            imageImportStatus = error.localizedDescription
            imageImportOK = false
        }
    }

    private func importImageFile(from sourceURL: URL) throws -> String {
        let fileManager = FileManager.default
        let projectRoot = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()

        if isInsideProject(source, root: projectRoot) {
            return relativePath(from: projectRoot, to: source)
        }

        let imagesDir = projectRoot.appendingPathComponent("images", isDirectory: true)
        try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)

        let destination = uniqueImportURL(for: source, in: imagesDir)
        try fileManager.copyItem(at: source, to: destination)
        return "images/\(destination.lastPathComponent)"
    }

    private func isInsideProject(_ fileURL: URL, root projectRoot: URL) -> Bool {
        let rootPath = projectRoot.path.hasSuffix("/") ? projectRoot.path : projectRoot.path + "/"
        return fileURL.path == projectRoot.path || fileURL.path.hasPrefix(rootPath)
    }

    private func relativePath(from rootURL: URL, to fileURL: URL) -> String {
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        if fileURL.path.hasPrefix(rootPath) {
            return String(fileURL.path.dropFirst(rootPath.count))
        }
        return fileURL.lastPathComponent
    }

    private func uniqueImportURL(for sourceURL: URL, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let ext = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent

        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let name = "\(baseName)-\(index)"
            candidate = directory.appendingPathComponent(name).appendingPathExtension(ext)
            index += 1
        }

        return candidate
    }
}

// MARK: - Shared sub-components

private struct PropSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct PropRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            content()
        }
    }
}
