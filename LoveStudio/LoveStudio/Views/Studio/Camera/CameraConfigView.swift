import SwiftUI

// MARK: - Main View

struct CameraConfigView: View {

    let projectURL: URL
    let onDismiss:  () -> Void

    @State private var config       = CameraConfig()
    @State private var statusMsg    = ""
    @State private var statusOK     = true
    @State private var showLoad     = false
    @State private var savedConfigs: [CameraConfig] = []

    // Live preview animation
    @State private var previewTime: Double = 0
    @State private var previewTimer: Timer? = nil
    // Simulated camera position - updated each tick via real lerp math
    @State private var camSimX: CGFloat = 0
    @State private var camSimY: CGFloat = 0
    @State private var previewSizeCache: CGSize = .zero

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
        .frame(width: 880, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear  { startPreview() }
        .onDisappear { previewTimer?.invalidate() }
    }

    // MARK: - Left column (settings)

    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                followSection
                zoomSection
                shakeSection
                deadzoneSection
                boundsSection
            }
            .padding(20)
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Right column (live preview)

    private var rightColumn: some View {
        ZStack(alignment: .topLeading) {
            // Animated canvas - fills the whole right panel
            Canvas { ctx, size in
                drawPreview(ctx: ctx, size: size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))

            // Legend overlay
            VStack(alignment: .leading, spacing: 4) {
                legendItem(color: .orange, label: "Target object")
                legendItem(color: .cyan,   label: "Camera center")
                legendItem(color: .cyan.opacity(0.5), label: "Viewport rect")
                if config.deadzoneEnabled {
                    legendItem(color: .yellow, label: "Deadzone")
                }
            }
            .padding(12)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.metering.center.weighted")
                .foregroundStyle(.cyan)
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

            // Load
            Button { showLoad = true } label: {
                Label("Load", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showLoad) {
                loadPopover
                    .onAppear { savedConfigs = CameraStore.loadAll(from: projectURL) }
            }

            // Save
            Button {
                do {
                    try CameraStore.save(config, to: projectURL)
                    flash("Saved", ok: true)
                } catch {
                    flash("Save failed: \(error.localizedDescription)", ok: false)
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Export
            Button {
                do {
                    let code = CameraCodeGenerator.generate(config: config)
                    try CameraStore.exportLua(code, moduleName: config.moduleName, to: projectURL)
                    flash("Exported \(CameraStore.safeName(config.moduleName)).lua", ok: true)
                } catch {
                    flash("Export failed: \(error.localizedDescription)", ok: false)
                }
            } label: {
                Label("Export", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
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

    // MARK: - Sections

    private var followSection: some View {
        CamSectionCard(title: "FOLLOW", icon: "scope",
            description: "Controls how the camera tracks a target. Call cam:follow(player.x, player.y) every frame in love.update(dt), then cam:update(dt) to apply movement.") {
            VStack(spacing: 10) {
                CamRow(label: "Lerp speed",
                       hint: "How quickly the camera catches up to its target. 0.05 feels cinematic, 0.2 feels responsive, 1.0 snaps instantly with no smoothing.") {
                    CamSlider(value: $config.lerpSpeed, in: 0.01...1.0, format: { String(format: "%.2f", $0) })
                }
                CamRow(label: "Round pixels",
                       hint: "Snaps the camera position to whole pixel values each frame. Eliminates sub-pixel shimmer on pixel-art sprites - leave off for smooth high-res games.") {
                    Toggle("", isOn: $config.roundPixels).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }

    private var zoomSection: some View {
        CamSectionCard(title: "ZOOM", icon: "plus.magnifyingglass",
            description: "Scales the entire world view. Change zoom at runtime with cam:setZoom(z) - the camera transitions smoothly using the lerp speed below.") {
            VStack(spacing: 10) {
                CamRow(label: "Default zoom",
                       hint: "Starting zoom level when the camera is created. 1.0 = 1:1 pixels. 2.0 = zoomed in (world appears larger). 0.5 = zoomed out (more world visible).") {
                    CamSlider(value: $config.defaultZoom, in: 0.1...8.0, format: { String(format: "%.2f×", $0) })
                }
                CamRow(label: "Zoom lerp",
                       hint: "Speed of zoom transitions when cam:setZoom() is called. Low values create a smooth cinematic zoom; 1.0 snaps to the new level immediately.") {
                    CamSlider(value: $config.zoomLerpSpeed, in: 0.01...1.0, format: { String(format: "%.2f", $0) })
                }
            }
        }
    }

    private var shakeSection: some View {
        CamSectionCard(title: "SCREEN SHAKE", icon: "waveform.path.ecg",
            description: "Randomized offset applied each frame to simulate impacts, explosions, or rumble. Trigger it anywhere in your code with cam:shake(intensity).") {
            VStack(spacing: 10) {
                CamRow(label: "Intensity",
                       hint: "Maximum pixel displacement per axis when cam:shake() is called with no argument. For a gun shot try 4–8 px, for an explosion 16–32 px.") {
                    CamSlider(value: $config.shakeIntensity, in: 1...64, format: { "\(Int($0)) px" })
                }
                CamRow(label: "Decay",
                       hint: "The shake magnitude is multiplied by this value every frame. 0.80 = shake fades in ~10 frames (snappy). 0.99 = long rumble that takes ~100 frames to settle.") {
                    CamSlider(value: $config.shakeDecay, in: 0.70...0.99, format: { String(format: "%.2f", $0) })
                }
            }
        }
    }

    private var deadzoneSection: some View {
        CamSectionCard(title: "DEADZONE", icon: "rectangle.dashed",
            description: "An invisible box around the camera center. The camera only moves when the target steps outside this box. Common in platformers to avoid constant vertical drift during jumps.") {
            VStack(spacing: 10) {
                CamRow(label: "Enabled",
                       hint: "When off, the camera follows the target directly every frame. When on, small movements inside the box are ignored - only large movements scroll the view.") {
                    Toggle("", isOn: $config.deadzoneEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if config.deadzoneEnabled {
                    CamRow(label: "Width",
                           hint: "Horizontal size of the deadzone. A wider box means more horizontal walking before the camera scrolls. Shown as the yellow dashed rect in the preview.") {
                        CamSlider(value: $config.deadzoneW, in: 10...600, format: { "\(Int($0)) px" })
                    }
                    CamRow(label: "Height",
                           hint: "Vertical size of the deadzone. Increase this to prevent the camera from moving during short jumps. Decrease it for top-down games that need tight vertical tracking.") {
                        CamSlider(value: $config.deadzoneH, in: 10...400, format: { "\(Int($0)) px" })
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: config.deadzoneEnabled)
        }
    }

    private var boundsSection: some View {
        CamSectionCard(title: "WORLD BOUNDS", icon: "map",
            description: "Prevents the camera from scrolling past the edges of your world. Set X/Y to the top-left corner of the world and W/H to its total size in pixels.") {
            VStack(spacing: 10) {
                CamRow(label: "Enabled",
                       hint: "When on, the camera is clamped so it never reveals empty space outside the defined rectangle. Essential for tiled maps with fixed dimensions.") {
                    Toggle("", isOn: $config.boundsEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if config.boundsEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Top-left origin (X, Y) and total size (W, H) of your world in pixels.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 12) {
                            boundsField("X", value: $config.boundsX)
                            boundsField("Y", value: $config.boundsY)
                            boundsField("W", value: $config.boundsW)
                            boundsField("H", value: $config.boundsH)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: config.boundsEnabled)
        }
    }

    private func boundsField(_ label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 70)
        }
    }

    // MARK: - Live preview canvas

    private func drawPreview(ctx: GraphicsContext, size: CGSize) {
        var ctx = ctx
        let t   = previewTime
        let cx  = size.width  * 0.5
        let cy  = size.height * 0.5

        // Cache size so the timer can compute the same target position
        if previewSizeCache != size {
            DispatchQueue.main.async { previewSizeCache = size }
        }

        // Target moves in a figure-8 path
        let targetX = cx + cos(t * 0.8) * size.width  * 0.3
        let targetY = cy + sin(t * 1.6) * size.height * 0.25

        // Use the simulated camera position (updated by timer via real lerp math)
        // Fall back to center on first frame before the timer initializes it
        let camX: CGFloat = camSimX == 0 ? cx : camSimX
        let camY: CGFloat = camSimY == 0 ? cy : camSimY

        // Shake offset visualization (subtle)
        let shakeAmp = config.shakeIntensity * 0.1 * max(0, sin(t * 12) * 0.3)
        let shakeX   = shakeAmp * sin(t * 30)
        let shakeY   = shakeAmp * cos(t * 23)

        // Grid (represents world)
        ctx.opacity = 0.15
        let gridStep: CGFloat = 20
        var gx: CGFloat = 0
        while gx <= size.width  { ctx.stroke(Path { p in p.move(to: CGPoint(x: gx, y: 0)); p.addLine(to: CGPoint(x: gx, y: size.height)) }, with: .color(.cyan), lineWidth: 0.5); gx += gridStep }
        var gy: CGFloat = 0
        while gy <= size.height { ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: gy)); p.addLine(to: CGPoint(x: size.width, y: gy)) }, with: .color(.cyan), lineWidth: 0.5); gy += gridStep }
        ctx.opacity = 1

        // Camera viewport rect
        let zoom = config.defaultZoom
        let vw   = size.width  / zoom
        let vh   = size.height / zoom
        let vx   = (camX + shakeX) - vw * 0.5
        let vy   = (camY + shakeY) - vh * 0.5
        ctx.stroke(
            Path(roundedRect: CGRect(x: vx, y: vy, width: vw, height: vh), cornerRadius: 4),
            with: .color(.cyan.opacity(0.5)),
            lineWidth: 1.5
        )

        // Deadzone box (centered on camera)
        if config.deadzoneEnabled {
            let dzW = config.deadzoneW * 0.4
            let dzH = config.deadzoneH * 0.4
            ctx.stroke(
                Path(CGRect(x: camX - dzW * 0.5 + shakeX, y: camY - dzH * 0.5 + shakeY, width: dzW, height: dzH)),
                with: .color(.yellow.opacity(0.5)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        }

        // Target dot (the object being followed)
        ctx.fill(
            Path(ellipseIn: CGRect(x: targetX - 5, y: targetY - 5, width: 10, height: 10)),
            with: .color(.orange)
        )

        // Camera center cross
        let cx2 = camX + shakeX
        let cy2 = camY + shakeY
        let cs: CGFloat = 6
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: cx2 - cs, y: cy2))
            p.addLine(to: CGPoint(x: cx2 + cs, y: cy2))
            p.move(to: CGPoint(x: cx2, y: cy2 - cs))
            p.addLine(to: CGPoint(x: cx2, y: cy2 + cs))
        }, with: .color(.cyan), lineWidth: 1.5)

        // Labels
        var tgt = ctx
        tgt.draw(
            Text("target").font(.system(size: 9)).foregroundStyle(Color.orange),
            at: CGPoint(x: targetX + 8, y: targetY - 4)
        )
        tgt.draw(
            Text("camera").font(.system(size: 9)).foregroundStyle(Color.cyan),
            at: CGPoint(x: cx2 + 8, y: cy2 - 4)
        )
    }

    private func startPreview() {
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            previewTime += 1.0 / 30.0

            // Simulate real lerp: cam moves toward target each tick
            let size = previewSizeCache
            guard size.width > 0 else { return }
            let cx = size.width  * 0.5
            let cy = size.height * 0.5
            let t  = previewTime
            let targetX = cx + cos(t * 0.8) * size.width  * 0.3
            let targetY = cy + sin(t * 1.6) * size.height * 0.25
            let lerp = CGFloat(config.lerpSpeed)
            camSimX += (targetX - camSimX) * lerp
            camSimY += (targetY - camSimY) * lerp
        }
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
                    } label: {
                        HStack {
                            Text(cfg.moduleName)
                            Spacer()
                            Text("lerp \(String(format: "%.2f", cfg.lerpSpeed))")
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

    private func flash(_ msg: String, ok: Bool) {
        statusMsg = msg
        statusOK  = ok
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { if statusMsg == msg { statusMsg = "" } }
        }
    }
}

// MARK: - Shared sub-components

private struct CamSectionCard<Content: View>: View {
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
                .padding(.leading, 4)
        }
        .padding(.bottom, 4)
    }
}

private struct CamRow<Content: View>: View {
    let label: String
    let hint:  String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 120, alignment: .leading)
                content()
            }
            if !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CamSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    init(value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) {
        self._value = value
        self.range  = range
        self.format = format
    }

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $value, in: range)
            Text(format(value))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 52, alignment: .trailing)
        }
    }
}
