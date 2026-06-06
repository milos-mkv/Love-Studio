import SwiftUI

// MARK: - Main View

struct ResolutionScalerView: View {

    let projectURL: URL
    let onDismiss:  () -> Void

    @State private var config       = ResolutionConfig()
    @State private var statusMsg    = ""
    @State private var statusOK     = true
    @State private var showLoad     = false
    @State private var savedConfigs: [ResolutionConfig] = []
    @State private var selectedPreset: ResolutionPreset = .r320x180

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                leftColumn
                Divider()
                rightColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 880, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.resize")
                .foregroundStyle(.mint)
                .font(.system(size: 15, weight: .semibold))

            TextField("Module name", text: $config.moduleName)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 160)

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
                    .onAppear { savedConfigs = ResolutionStore.loadAll(from: projectURL) }
            }

            Button {
                do {
                    try ResolutionStore.save(config, to: projectURL)
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
                    let code = ResolutionCodeGenerator.generate(config: config)
                    try ResolutionStore.exportLua(code, moduleName: config.moduleName, to: projectURL)
                    flash("Exported \(ResolutionStore.safeName(config.moduleName)).lua", ok: true)
                } catch {
                    flash("Export failed: \(error.localizedDescription)", ok: false)
                }
            } label: {
                Label("Export", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .controlSize(.small)

            Divider().frame(height: 16)

            Button { onDismiss() } label: {
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

    // MARK: - Left column

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                virtualResolutionSection
                scalingModeSection
                filterSection
                previewWindowSection
            }
            .padding(20)
        }
        .frame(width: 420)
    }

    // MARK: - Virtual resolution

    private var virtualResolutionSection: some View {
        ResSectionCard(title: "VIRTUAL RESOLUTION", icon: "rectangle.on.rectangle",
            description: "The size of the canvas your game renders to. All game coordinates live in this space — independent of the real window size. Choose a small size for a retro pixel-art look.") {
            VStack(alignment: .leading, spacing: 10) {

                // Presets
                ResRow(label: "Preset") {
                    Picker("", selection: $selectedPreset) {
                        ForEach(ResolutionPreset.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    .onChange(of: selectedPreset) { _, p in
                        if let (w, h) = p.size {
                            config.virtualWidth  = w
                            config.virtualHeight = h
                        }
                    }
                }

                // Manual W / H
                ResRow(label: "Width") {
                    HStack(spacing: 6) {
                        TextField("320", value: $config.virtualWidth, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .onChange(of: config.virtualWidth)  { _, _ in selectedPreset = .custom }
                        Text("px")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                }
                ResRow(label: "Height") {
                    HStack(spacing: 6) {
                        TextField("180", value: $config.virtualHeight, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .onChange(of: config.virtualHeight) { _, _ in selectedPreset = .custom }
                        Text("px")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                }

                // Aspect ratio info
                let gcdVal = gcd(config.virtualWidth, config.virtualHeight)
                let arW    = config.virtualWidth  / max(1, gcdVal)
                let arH    = config.virtualHeight / max(1, gcdVal)
                Text("Aspect ratio: \(arW):\(arH)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Scaling mode

    private var scalingModeSection: some View {
        ResSectionCard(title: "SCALING MODE", icon: "arrow.up.left.and.arrow.down.right",
            description: "Defines how the virtual canvas is scaled up to fill the real window. Pixel-perfect is recommended for retro pixel-art games.") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ScalingMode.allCases) { mode in
                    Button {
                        config.scalingMode = mode
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: config.scalingMode == mode
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(config.scalingMode == mode ? .mint : .secondary)
                                .font(.system(size: 14))
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Text(mode.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                Text(mode.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(config.scalingMode == mode
                                      ? Color.mint.opacity(0.08)
                                      : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(config.scalingMode == mode
                                                      ? Color.mint.opacity(0.4)
                                                      : Color.secondary.opacity(0.2),
                                                      lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Filter

    private var filterSection: some View {
        ResSectionCard(title: "TEXTURE FILTER", icon: "camera.filters",
            description: "Controls how pixels are interpolated when the canvas is scaled up. Nearest is the standard choice for pixel-art — it keeps each pixel a hard square.") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(FilterMode.allCases) { mode in
                    Button {
                        config.filterMode = mode
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: config.filterMode == mode
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(config.filterMode == mode ? .mint : .secondary)
                                .font(.system(size: 14))
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(mode.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(config.filterMode == mode
                                      ? Color.mint.opacity(0.08)
                                      : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(config.filterMode == mode
                                                      ? Color.mint.opacity(0.4)
                                                      : Color.secondary.opacity(0.2),
                                                      lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Preview window size

    private var previewWindowSection: some View {
        ResSectionCard(title: "PREVIEW WINDOW SIZE", icon: "macwindow",
            description: "Used only to visualize the scaling in the preview panel. Does not affect the exported Lua code.") {
            VStack(spacing: 8) {
                ResRow(label: "Width") {
                    HStack(spacing: 6) {
                        TextField("1280", value: $config.previewWindowW, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                        Text("px").foregroundStyle(.secondary).font(.system(size: 12))
                    }
                }
                ResRow(label: "Height") {
                    HStack(spacing: 6) {
                        TextField("720", value: $config.previewWindowH, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                        Text("px").foregroundStyle(.secondary).font(.system(size: 12))
                    }
                }

                // Common window presets
                HStack(spacing: 6) {
                    ForEach([("720p", 1280, 720), ("1080p", 1920, 1080), ("1440p", 2560, 1440)], id: \.0) { name, w, h in
                        Button(name) {
                            config.previewWindowW = w
                            config.previewWindowH = h
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
    }

    // MARK: - Right column (preview)

    private var rightColumn: some View {
        VStack(spacing: 0) {
            // Preview canvas
            GeometryReader { geo in
                Canvas { ctx, size in
                    drawScalingPreview(ctx: ctx, size: size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }

            // Stats bar
            Divider()
            statsBar
        }
    }

    private var statsBar: some View {
        let (scale, ox, oy, scaledW, scaledH) = computeScale()
        return HStack(spacing: 20) {
            statItem("Virtual", value: "\(config.virtualWidth) × \(config.virtualHeight)")
            statItem("Scale",   value: String(format: "%.2f×", scale))
            statItem("Offset",  value: "\(Int(ox)), \(Int(oy)) px")
            statItem("Scaled",  value: "\(Int(scaledW)) × \(Int(scaledH))")
            statItem("Mode",    value: config.scalingMode.displayName)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func statItem(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    // MARK: - Scaling preview draw

    private func drawScalingPreview(ctx: GraphicsContext, size: CGSize) {
        var ctx = ctx

        let winW = CGFloat(config.previewWindowW)
        let winH = CGFloat(config.previewWindowH)
        let vw   = CGFloat(config.virtualWidth)
        let vh   = CGFloat(config.virtualHeight)

        // Map window → canvas area (fit window into available space with padding)
        let pad: CGFloat  = 24
        let availW = size.width  - pad * 2
        let availH = size.height - pad * 2
        let fitScale = min(availW / winW, availH / winH)
        let dispWinW = winW * fitScale
        let dispWinH = winH * fitScale
        let winOriginX = (size.width  - dispWinW) * 0.5
        let winOriginY = (size.height - dispWinH) * 0.5

        // Draw window background
        let windowRect = CGRect(x: winOriginX, y: winOriginY, width: dispWinW, height: dispWinH)
        ctx.fill(Path(windowRect), with: .color(Color(white: 0.08)))
        ctx.stroke(Path(windowRect), with: .color(Color(white: 0.3)), lineWidth: 1)

        // Compute scale + offset for the virtual canvas inside the window
        let (rawScale, rawOx, rawOy, _, _) = computeScale()
        let canvasW = vw * CGFloat(rawScale) * fitScale
        let canvasH = vh * CGFloat(rawScale) * fitScale
        let canvasX = winOriginX + rawOx * fitScale
        let canvasY = winOriginY + rawOy * fitScale

        // Checkerboard fill inside virtual canvas (clipped manually to canvasRect)
        let canvasRect = CGRect(x: canvasX, y: canvasY, width: canvasW, height: canvasH)
        let tileSize: CGFloat = 12
        var ty: CGFloat = canvasY
        var rowIdx = 0
        while ty < canvasY + canvasH {
            var tx: CGFloat = canvasX
            var colIdx = 0
            while tx < canvasX + canvasW {
                let tileW = min(tileSize, canvasX + canvasW - tx)
                let tileH = min(tileSize, canvasY + canvasH - ty)
                let c: Color = (rowIdx + colIdx) % 2 == 0
                    ? Color(white: 0.22) : Color(white: 0.18)
                ctx.fill(
                    Path(CGRect(x: tx, y: ty, width: tileW, height: tileH)),
                    with: .color(c)
                )
                tx += tileSize
                colIdx += 1
            }
            ty += tileSize
            rowIdx += 1
        }

        // Virtual canvas border
        ctx.stroke(
            Path(canvasRect),
            with: .color(Color.mint.opacity(0.9)),
            style: StrokeStyle(lineWidth: 1.5)
        )

        // Letterbox bars (areas outside virtual canvas inside window)
        let barColor = Color(white: 0.04)
        // Top bar
        if rawOy > 0 {
            let topBar = CGRect(x: winOriginX, y: winOriginY, width: dispWinW, height: rawOy * fitScale)
            ctx.fill(Path(topBar), with: .color(barColor))
        }
        // Bottom bar
        let bottomBarY = canvasY + canvasH
        if bottomBarY < winOriginY + dispWinH {
            let botBar = CGRect(x: winOriginX, y: bottomBarY, width: dispWinW, height: (winOriginY + dispWinH) - bottomBarY)
            ctx.fill(Path(botBar), with: .color(barColor))
        }
        // Left bar
        if rawOx > 0 {
            let leftBar = CGRect(x: winOriginX, y: canvasY, width: rawOx * fitScale, height: canvasH)
            ctx.fill(Path(leftBar), with: .color(barColor))
        }
        // Right bar
        let rightBarX = canvasX + canvasW
        if rightBarX < winOriginX + dispWinW {
            let rightBar = CGRect(x: rightBarX, y: canvasY, width: (winOriginX + dispWinW) - rightBarX, height: canvasH)
            ctx.fill(Path(rightBar), with: .color(barColor))
        }

        // Corner label: virtual resolution
        ctx.draw(
            Text("\(config.virtualWidth) × \(config.virtualHeight)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.mint),
            at: CGPoint(x: canvasX + 6, y: canvasY + 14),
            anchor: .leading
        )

        // Window size label (top-left of window rect)
        ctx.draw(
            Text("\(config.previewWindowW) × \(config.previewWindowH)  window")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.45)),
            at: CGPoint(x: winOriginX + 6, y: winOriginY + 10),
            anchor: .leading
        )

        // Scale label
        let (scale, _, _, _, _) = computeScale()
        ctx.draw(
            Text(String(format: "%.2f×  %@", scale, config.scalingMode.displayName))
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.45)),
            at: CGPoint(x: winOriginX + 6, y: winOriginY + dispWinH - 6),
            anchor: .leading
        )

        // Pixel grid (only when scale ≥ 3 and virtual res is small)
        if scale >= 3 && vw <= 320 {
            let pixW = fitScale * CGFloat(rawScale)
            ctx.opacity = 0.07
            var px = canvasX
            while px < canvasX + canvasW {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: px, y: canvasY))
                    p.addLine(to: CGPoint(x: px, y: canvasY + canvasH))
                }, with: .color(.white), lineWidth: 0.5)
                px += pixW
            }
            var py = canvasY
            while py < canvasY + canvasH {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: canvasX, y: py))
                    p.addLine(to: CGPoint(x: canvasX + canvasW, y: py))
                }, with: .color(.white), lineWidth: 0.5)
                py += pixW
            }
            ctx.opacity = 1
        }
    }

    // MARK: - Scale computation (mirrors the Lua resize logic)

    private func computeScale() -> (Double, CGFloat, CGFloat, CGFloat, CGFloat) {
        let winW = CGFloat(config.previewWindowW)
        let winH = CGFloat(config.previewWindowH)
        let vw   = CGFloat(config.virtualWidth)
        let vh   = CGFloat(config.virtualHeight)

        let scale: CGFloat
        let ox, oy: CGFloat

        switch config.scalingMode {
        case .pixelPerfect:
            let sx = floor(winW / vw)
            let sy = floor(winH / vh)
            scale = max(1, min(sx, sy))
            ox    = floor((winW - vw * scale) * 0.5)
            oy    = floor((winH - vh * scale) * 0.5)
        case .letterbox:
            scale = min(winW / vw, winH / vh)
            ox    = floor((winW - vw * scale) * 0.5)
            oy    = floor((winH - vh * scale) * 0.5)
        case .stretch:
            scale = 1
            ox    = 0
            oy    = 0
        }

        return (Double(scale), ox, oy, vw * scale, vh * scale)
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
                        syncPreset()
                    } label: {
                        HStack {
                            Text(cfg.moduleName)
                            Spacer()
                            Text("\(cfg.virtualWidth)×\(cfg.virtualHeight)")
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
        .frame(width: 200)
    }

    // MARK: - Helpers

    private func syncPreset() {
        selectedPreset = ResolutionPreset.allCases.first {
            $0.size?.0 == config.virtualWidth && $0.size?.1 == config.virtualHeight
        } ?? .custom
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    private func flash(_ msg: String, ok: Bool) {
        statusMsg = msg
        statusOK  = ok
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { if statusMsg == msg { statusMsg = "" } }
        }
    }
}

// MARK: - Sub-components

private struct ResSectionCard<Content: View>: View {
    let title:       String
    let icon:        String
    var description: String = ""
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
            }
            content()
        }
        .padding(.bottom, 4)
    }
}

private struct ResRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            content()
        }
    }
}
