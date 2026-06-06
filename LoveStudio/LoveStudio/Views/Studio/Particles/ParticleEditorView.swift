import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Preview wrapper

struct ParticlePreviewView: NSViewRepresentable {
    let config: ParticleSystemConfig
    var textureImage: NSImage? = nil
    var background: ParticlePreviewBackground = .dark

    func makeNSView(context: Context) -> ParticlePreviewNSView {
        let v = ParticlePreviewNSView()
        v.config       = config
        v.textureImage = textureImage
        v.background   = background
        return v
    }
    func updateNSView(_ v: ParticlePreviewNSView, context: Context) {
        if v.config      != config      { v.config      = config }
        if v.background  != background  { v.background  = background }
        if v.textureImage !== textureImage { v.textureImage = textureImage }
    }
    static func dismantleNSView(_ v: ParticlePreviewNSView, coordinator: ()) { v.stop() }
}

// MARK: - Editor

struct ParticleEditorView: View {
    let projectURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var config            = ParticleSystemConfig()
    @State private var textureImage: NSImage? = nil
    @State private var previewID         = UUID()
    @State private var previewBackground = ParticlePreviewBackground.dark
    @State private var savedConfigs: [ParticleSystemConfig] = []
    @State private var saveStatus        = ""

    // Collapse state for each group
    @State private var showMotion     = true
    @State private var showForces     = true
    @State private var showAppearance = true
    @State private var showEmitter    = true
    @State private var showLifetime   = true

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
        .frame(minWidth: 720, minHeight: 560)
        .onAppear { savedConfigs = ParticleStore.loadAll(from: projectURL) }
    }

    // MARK: - Color bindings

    private var startColorBinding: Binding<Color> {
        Binding(
            get: { Color(red: config.colorStartR, green: config.colorStartG,
                         blue: config.colorStartB, opacity: config.colorStartA) },
            set: { c in
                if let v = NSColor(c).usingColorSpace(.deviceRGB) {
                    config.colorStartR = Double(v.redComponent)
                    config.colorStartG = Double(v.greenComponent)
                    config.colorStartB = Double(v.blueComponent)
                    config.colorStartA = Double(v.alphaComponent)
                }
            }
        )
    }

    private var endColorBinding: Binding<Color> {
        Binding(
            get: { Color(red: config.colorEndR, green: config.colorEndG,
                         blue: config.colorEndB, opacity: config.colorEndA) },
            set: { c in
                if let v = NSColor(c).usingColorSpace(.deviceRGB) {
                    config.colorEndR = Double(v.redComponent)
                    config.colorEndG = Double(v.greenComponent)
                    config.colorEndB = Double(v.blueComponent)
                    config.colorEndA = Double(v.alphaComponent)
                }
            }
        )
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(.pink)
            Text("Particle Editor").font(.headline)

            Divider().frame(height: 20)

            TextField("Name", text: $config.name)
                .textFieldStyle(.plain)
                .frame(width: 150)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .textBackgroundColor)))

            Spacer()

            // Presets
            Menu {
                ForEach(ParticlePreset.allCases) { preset in
                    Button(preset.rawValue) {
                        config    = preset.makeConfig()
                        previewID = UUID()
                    }
                }
            } label: {
                Label("Presets", systemImage: "list.star").font(.caption)
            }
            .menuStyle(.borderlessButton).fixedSize()

            Divider().frame(height: 20)

            // Save
            Button { saveConfig() } label: {
                Label("Save", systemImage: "square.and.arrow.down").font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Save particle config as JSON")

            // Load
            Menu {
                if savedConfigs.isEmpty {
                    Text("No saved particle systems").foregroundStyle(.secondary)
                } else {
                    ForEach(savedConfigs, id: \.name) { cfg in
                        Button(cfg.name) { loadConfig(cfg) }
                    }
                    Divider()
                    ForEach(savedConfigs, id: \.name) { cfg in
                        Button("Delete \(cfg.name)", role: .destructive) { deleteConfig(cfg) }
                    }
                }
            } label: {
                Label("Load", systemImage: "folder").font(.caption)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .onHover { if $0 { savedConfigs = ParticleStore.loadAll(from: projectURL) } }

            // Export
            Button { exportLua() } label: {
                Label("Export Lua", systemImage: "arrow.up.doc").font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .help("Export as particles/<name>.lua in project")

            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .font(.caption2).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: - Left column: preview

    private var leftColumn: some View {
        ZStack {
            ParticlePreviewView(config: config, textureImage: textureImage,
                                background: previewBackground)
                .id(previewID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Background toggle - top trailing
            HStack(spacing: 4) {
                ForEach(ParticlePreviewBackground.allCases, id: \.self) { bg in
                    Button { previewBackground = bg } label: {
                        Image(systemName: bg.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(previewBackground == bg ? Color.accentColor : .secondary)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(previewBackground == bg
                                          ? Color.accentColor.opacity(0.18)
                                          : Color.black.opacity(0.30))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(bg.rawValue.capitalized)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // Burst replay button - bottom trailing
            if config.isBurst {
                Button { previewID = UUID() } label: {
                    Label("Replay", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: 420)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Right column: parameters

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                modeSection
                group("Motion", icon: "hare.fill", expanded: $showMotion) {
                    motionContent
                }
                group("Forces", icon: "arrow.down.circle", expanded: $showForces) {
                    forcesContent
                }
                group("Appearance", icon: "paintpalette", expanded: $showAppearance) {
                    appearanceContent
                }
                group("Lifetime", icon: "clock", expanded: $showLifetime) {
                    lifetimeContent
                }
                group("Emitter & Texture", icon: "circle.dashed", expanded: $showEmitter) {
                    emitterContent
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mode (always visible, no collapse)

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Mode", icon: "slider.horizontal.3")
            HStack(spacing: 12) {
                Toggle("Burst", isOn: $config.isBurst)
                    .toggleStyle(.switch).font(.caption)
                Spacer()
                if config.isBurst {
                    Text("One-shot · \(config.burstCount) particles")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Continuous · \(Int(config.emissionRate))/s")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if config.isBurst {
                row("Burst count", value: Double(config.burstCount), unit: "") {
                    Slider(value: Binding(get: { Double(config.burstCount) },
                                          set: { config.burstCount = Int($0) }),
                           in: 10...1000, step: 10)
                }
            } else {
                row("Rate", value: config.emissionRate, unit: "/s") {
                    Slider(value: $config.emissionRate, in: 1...500, step: 1)
                }
            }
            row("Max particles", value: Double(config.maxParticles), unit: "") {
                Slider(value: Binding(get: { Double(config.maxParticles) },
                                      set: { config.maxParticles = Int($0) }),
                       in: 10...2000, step: 10)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
    }

    // MARK: - Motion content

    @ViewBuilder private var motionContent: some View {
        row("Speed min", value: config.speedMin, unit: "px/s") {
            Slider(value: $config.speedMin, in: 0...800, step: 5)
        }
        row("Speed max", value: config.speedMax, unit: "px/s") {
            Slider(value: $config.speedMax, in: 0...800, step: 5)
        }
        Divider().opacity(0.3)
        row("Direction", value: config.directionDeg, unit: "°") {
            Slider(value: $config.directionDeg, in: 0...360, step: 1)
        }
        HStack(spacing: 6) {
            Text("0°=right  90°=up  180°=left  270°=down")
                .font(.caption2).foregroundStyle(.tertiary)
            Spacer()
        }
        row("Spread (±)", value: config.spreadDeg, unit: "°") {
            Slider(value: $config.spreadDeg, in: 0...360, step: 1)
        }
        Button("All directions (360°)") { config.spreadDeg = 360 }
            .buttonStyle(.bordered).font(.caption2)
    }

    // MARK: - Forces content

    @ViewBuilder private var forcesContent: some View {
        row("Gravity X", value: config.gravityX, unit: "px/s²") {
            Slider(value: $config.gravityX, in: -500...500, step: 5)
        }
        row("Gravity Y", value: config.gravityY, unit: "px/s²") {
            Slider(value: $config.gravityY, in: -500...500, step: 5)
        }
        Text("Positive Y = downward on screen")
            .font(.caption2).foregroundStyle(.tertiary)
        Divider().opacity(0.3)
        row("Attract/Repel", value: config.attractRepelStrength, unit: "", decimals: 1) {
            Slider(value: $config.attractRepelStrength, in: -300...300, step: 5)
        }
        Text("Positive = attract · Negative = repel from emitter")
            .font(.caption2).foregroundStyle(.tertiary)
        Divider().opacity(0.3)
        row("Damping", value: config.damping, unit: "", decimals: 1) {
            Slider(value: $config.damping, in: 0...10, step: 0.1)
        }
        Text("Reduces speed over lifetime - drag / air resistance")
            .font(.caption2).foregroundStyle(.tertiary)
    }

    // MARK: - Appearance content

    @ViewBuilder private var appearanceContent: some View {
        // Size
        sectionLabel("Size", icon: "arrow.up.left.and.arrow.down.right")
        row("Start", value: config.sizeStart, unit: "px") {
            Slider(value: $config.sizeStart, in: 1...80, step: 0.5)
        }
        row("End", value: config.sizeEnd, unit: "px") {
            Slider(value: $config.sizeEnd, in: 0...80, step: 0.5)
        }
        row("Curve", value: config.sizeCurve, unit: "", decimals: 2) {
            Slider(value: $config.sizeCurve, in: 0...1, step: 0.05)
        }
        row("Variation ±", value: config.sizeVariation * 100, unit: "%") {
            Slider(value: $config.sizeVariation, in: 0...1, step: 0.01)
        }
        Text("0 = ease-in · 0.5 = linear · 1 = ease-out")
            .font(.caption2).foregroundStyle(.tertiary)

        Divider().opacity(0.3)

        // Color
        sectionLabel("Color", icon: "paintpalette")
        ColorPicker("Start Color", selection: startColorBinding, supportsOpacity: true)
            .font(.caption)
        ColorPicker("End Color", selection: endColorBinding, supportsOpacity: true)
            .font(.caption)
        row("Alpha curve", value: config.alphaCurve, unit: "", decimals: 2) {
            Slider(value: $config.alphaCurve, in: 0...1, step: 0.05)
        }
        Text("0 = ease-in · 0.5 = linear · 1 = ease-out")
            .font(.caption2).foregroundStyle(.tertiary)

        // Shape picker (procedural)
        if config.textureName == nil || config.textureName!.isEmpty {
            Divider().opacity(0.3)
            sectionLabel("Particle Shape", icon: "square.on.circle")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                      spacing: 6) {
                ForEach(ParticleShape.allCases) { shape in
                    let sel = config.shape == shape
                    Button { config.shape = shape } label: {
                        VStack(spacing: 4) {
                            Image(systemName: shape.sfSymbol)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(sel ? Color.accentColor : .secondary)
                            Text(shape.displayName)
                                .font(.system(size: 10))
                                .foregroundStyle(sel ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(sel ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(sel ? Color.accentColor.opacity(0.5) : Color.clear,
                                                  lineWidth: 1))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Divider().opacity(0.3)

        // Rotation
        sectionLabel("Rotation", icon: "arrow.clockwise")
        row("Start min", value: config.rotationMinDeg, unit: "°") {
            Slider(value: $config.rotationMinDeg, in: 0...360, step: 1)
        }
        row("Start max", value: config.rotationMaxDeg, unit: "°") {
            Slider(value: $config.rotationMaxDeg, in: 0...360, step: 1)
        }
        row("Speed min", value: config.rotSpeedMinDeg, unit: "°/s") {
            Slider(value: $config.rotSpeedMinDeg, in: -720...720, step: 5)
        }
        row("Speed max", value: config.rotSpeedMaxDeg, unit: "°/s") {
            Slider(value: $config.rotSpeedMaxDeg, in: -720...720, step: 5)
        }

        // Blend mode
        Divider().opacity(0.3)
        sectionLabel("Blend Mode", icon: "circle.lefthalf.filled")
        Picker("", selection: $config.blendMode) {
            ForEach(ParticleBlendMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Lifetime content

    @ViewBuilder private var lifetimeContent: some View {
        row("Min", value: config.lifetimeMin, unit: "s", decimals: 1) {
            Slider(value: $config.lifetimeMin, in: 0.1...15, step: 0.1)
        }
        row("Max", value: config.lifetimeMax, unit: "s", decimals: 1) {
            Slider(value: $config.lifetimeMax, in: 0.1...15, step: 0.1)
        }
    }

    // MARK: - Emitter & Texture content

    @ViewBuilder private var emitterContent: some View {
        // Emitter shape
        sectionLabel("Spawn Area", icon: "largecircle.fill.circle")
        Picker("", selection: $config.emitterShape) {
            ForEach(ParticleEmitterShape.allCases) { s in
                Text(s.displayName).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        switch config.emitterShape {
        case .point: EmptyView()
        case .circle:
            row("Radius", value: config.emitterRadius, unit: "px") {
                Slider(value: $config.emitterRadius, in: 0...200, step: 1)
            }
        case .line:
            row("Length", value: config.emitterLineLength, unit: "px") {
                Slider(value: $config.emitterLineLength, in: 10...400, step: 5)
            }
        case .rect:
            row("Width", value: config.emitterRectW, unit: "px") {
                Slider(value: $config.emitterRectW, in: 10...400, step: 5)
            }
            row("Height", value: config.emitterRectH, unit: "px") {
                Slider(value: $config.emitterRectH, in: 10...400, step: 5)
            }
        }

        Divider().opacity(0.3)

        // Texture
        sectionLabel("Texture", icon: "photo")
        HStack(spacing: 10) {
            Group {
                if let img = textureImage {
                    Image(nsImage: img)
                        .resizable().scaledToFit()
                } else {
                    Image(systemName: "circle.fill")
                        .font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(config.textureName ?? "Procedural shape")
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Button("Browse…") { browseTexture() }
                        .buttonStyle(.bordered).font(.caption2)
                    if textureImage != nil {
                        Button("Clear") {
                            textureImage       = nil
                            config.textureName = nil
                        }
                        .buttonStyle(.bordered).font(.caption2)
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: - UI helpers

    /// Collapsible grouped section
    @ViewBuilder
    private func group<Content: View>(
        _ title: String, icon: String,
        expanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row<Content: View>(
        _ label: String, value: Double, unit: String, decimals: Int = 0,
        @ViewBuilder slider: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            slider()
            Text(decimals == 0
                 ? "\(Int(value))\(unit)"
                 : String(format: "%.\(decimals)f\(unit)", value))
                .font(.system(.caption2, design: .monospaced))
                .frame(width: 56, alignment: .trailing)
        }
    }

    // MARK: - Actions

    private func browseTexture() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes  = [.png, .jpeg, .gif, .bmp]
        panel.message              = "Select particle texture image"
        panel.directoryURL         = projectURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var targetURL = url
        if !url.path.hasPrefix(projectURL.path + "/") {
            let imagesDir = projectURL.appendingPathComponent("images")
            try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            let dest = imagesDir.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: url, to: dest)
            }
            targetURL = dest
        }

        if targetURL.path.hasPrefix(projectURL.path + "/") {
            config.textureName = String(targetURL.path.dropFirst(projectURL.path.count + 1))
        } else {
            config.textureName = targetURL.lastPathComponent
        }
        textureImage = NSImage(contentsOf: targetURL)
    }

    private func saveConfig() {
        do {
            try ParticleStore.save(config, to: projectURL)
            savedConfigs = ParticleStore.loadAll(from: projectURL)
            saveStatus = "Saved \(config.name).json"
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
        clearStatusAfterDelay()
    }

    private func loadConfig(_ cfg: ParticleSystemConfig) {
        config    = cfg
        previewID = UUID()
        textureImage = nil
        if let name = cfg.textureName {
            textureImage = NSImage(contentsOf: projectURL.appendingPathComponent(name))
        }
    }

    private func deleteConfig(_ cfg: ParticleSystemConfig) {
        ParticleStore.delete(cfg, from: projectURL)
        savedConfigs = ParticleStore.loadAll(from: projectURL)
    }

    private func exportLua() {
        let code = ParticleCodeGenerator.generate(config: config)
        do {
            let url = try ParticleStore.exportLua(code, name: config.name, to: projectURL)
            saveStatus = "Exported \(url.lastPathComponent)"
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        } catch {
            saveStatus = "Export error: \(error.localizedDescription)"
        }
        clearStatusAfterDelay()
    }

    private func clearStatusAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = "" }
    }
}
