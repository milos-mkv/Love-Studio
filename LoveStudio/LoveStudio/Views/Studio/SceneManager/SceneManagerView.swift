import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Main View

struct SceneManagerView: View {

    let projectURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var config      = SceneManagerConfig()
    @State private var selectedID: SceneEntry.ID? = nil
    @State private var statusMsg   = ""
    @State private var statusOK    = true

    private var selectedEntry: Binding<SceneEntry>? {
        guard let id = selectedID,
              let idx = config.entries.firstIndex(where: { $0.id == id })
        else { return nil }
        return $config.entries[idx]
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                leftColumn
                Divider()

                Group {
                    if let binding = selectedEntry {
                        SceneTransitionPreviewPanel(projectURL: projectURL, entry: binding)
                    } else {
                        centerPlaceholder
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                Group {
                    if let binding = selectedEntry {
                        SceneEntryEditor(
                            projectURL: projectURL,
                            entry: binding,
                            allEntries: config.entries,
                            onSetInitial: { setInitialScene(binding.wrappedValue.id) }
                        )
                    } else {
                        rightPlaceholder
                    }
                }
                .frame(width: 340)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1220, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            config = SceneManagerStore.load(from: projectURL)
            if selectedID == nil { selectedID = config.entries.first?.id }
            ensureSingleInitialScene()
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.stack.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15, weight: .semibold))

            Text("Scene Manager")
                .font(.system(size: 14, weight: .semibold))

            Text("Scene.lua")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

            Spacer()

            if !statusMsg.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: statusOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(statusMsg)
                }
                .font(.system(size: 11))
                .foregroundStyle(statusOK ? Color.green : Color.red)
                .transition(.opacity)
            }

            Button {
                do {
                    try SceneManagerStore.save(config, to: projectURL)
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
                    let exported = try SceneManagerStore.exportAll(config, to: projectURL)
                    flash("Exported \(exported.count) file(s)", ok: true)
                } catch {
                    flash("Export failed: \(error.localizedDescription)", ok: false)
                }
            } label: {
                Label("Export", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
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

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SCENES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(config.entries.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if config.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Click + to add a scene")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach($config.entries) { $entry in
                        SceneEntryRow(projectURL: projectURL, entry: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("Set as Initial") {
                                    setInitialScene(entry.id)
                                }
                                .disabled(entry.isInitial)

                                Divider()

                                Button("Delete", role: .destructive) {
                                    removeScene(entry.id)
                                }
                            }
                    }
                    .onMove { from, to in
                        config.entries.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { idx in
                        config.entries.remove(atOffsets: idx)
                        if !config.entries.contains(where: { $0.id == selectedID }) {
                            selectedID = config.entries.first?.id
                        }
                        ensureSingleInitialScene()
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack(spacing: 4) {
                Button {
                    let name = uniqueName(base: "scene")
                    var entry = SceneEntry(name: name, displayName: name.capitalized)
                    if config.entries.isEmpty { entry.isInitial = true }
                    config.entries.append(entry)
                    selectedID = entry.id
                    ensureSingleInitialScene()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(4)

                Button {
                    guard let id = selectedID else { return }
                    removeScene(id)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain)
                .padding(4)
                .disabled(selectedID == nil)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Placeholders

    private var centerPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Select a scene to preview transitions")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Pick enter/leave effects like Fade, Pop or Slide and replay them here.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rightPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.click")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Select a scene to edit")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func uniqueName(base: String) -> String {
        var idx = 1
        var candidate = base
        while config.entries.contains(where: { $0.name == candidate }) {
            candidate = "\(base)\(idx)"
            idx += 1
        }
        return candidate
    }

    private func removeScene(_ id: SceneEntry.ID) {
        config.entries.removeAll { $0.id == id }
        if selectedID == id { selectedID = config.entries.first?.id }
        ensureSingleInitialScene()
    }

    private func setInitialScene(_ id: SceneEntry.ID) {
        for idx in config.entries.indices {
            config.entries[idx].isInitial = (config.entries[idx].id == id)
        }
    }

    private func ensureSingleInitialScene() {
        guard !config.entries.isEmpty else { return }

        let initialIDs = config.entries.filter(\.isInitial).map(\.id)
        if initialIDs.isEmpty {
            config.entries[0].isInitial = true
            return
        }

        if initialIDs.count > 1, let keepID = initialIDs.first {
            setInitialScene(keepID)
        }
    }

    private func flash(_ msg: String, ok: Bool) {
        statusMsg = msg
        statusOK = ok
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                if statusMsg == msg { statusMsg = "" }
            }
        }
    }
}

// MARK: - Transition Preview

private enum ScenePreviewMode: String, CaseIterable, Identifiable {
    case enter = "Enter"
    case leave = "Leave"

    var id: String { rawValue }
}

private struct SceneTransitionPreviewPanel: View {
    let projectURL: URL
    @Binding var entry: SceneEntry

    @State private var previewMode: ScenePreviewMode = .enter
    @State private var progress: CGFloat = 0

    private var activeEffect: SceneTransitionEffect {
        previewMode == .enter ? entry.enterTransition : entry.leaveTransition
    }

    private var activeEasing: SceneTransitionEasing {
        previewMode == .enter ? entry.enterEasing : entry.leaveEasing
    }

    private var animationDuration: Double {
        max(0.15, entry.transitionDuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Transition Preview", systemImage: "sparkles.rectangle.stack")
                    .font(.system(size: 12, weight: .semibold))

                Divider().frame(height: 16)

                Picker("", selection: $previewMode) {
                    ForEach(ScenePreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: activeEffect.icon)
                    Text(activeEffect.displayName)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: activeEasing.icon)
                    Text(activeEasing.displayName)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                Text(String(format: "%.2fs", animationDuration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1), in: Capsule())

                Button("Replay") { replay() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            GeometryReader { geo in
                let stageSize = CGSize(width: max(320, geo.size.width * 0.58),
                                       height: max(200, geo.size.height * 0.34))
                ZStack {
                    ScenePreviewGrid()

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .frame(width: stageSize.width + 72, height: stageSize.height + 96)

                    ZStack {
                        if previewMode == .enter {
                            sceneCard(
                                title: "Previous Scene",
                                subtitle: "Current screen before transition",
                                accent: .orange
                            )
                            .opacity(0.28)

                            sceneCard(
                                title: entry.displayName.isEmpty ? entry.name : entry.displayName,
                                subtitle: "Entering with \(activeEffect.displayName)",
                                accent: .green
                            )
                            .modifier(SceneTransitionPreviewModifier(
                                effect: activeEffect,
                                easing: activeEasing,
                                progress: progress,
                                entering: true,
                                stageSize: stageSize
                            ))
                        } else {
                            sceneCard(
                                title: "Destination Scene",
                                subtitle: "Scene revealed after exit",
                                accent: .green
                            )
                            .opacity(0.34)

                            sceneCard(
                                title: entry.displayName.isEmpty ? entry.name : entry.displayName,
                                subtitle: "Leaving with \(activeEffect.displayName)",
                                accent: .pink
                            )
                            .modifier(SceneTransitionPreviewModifier(
                                effect: activeEffect,
                                easing: activeEasing,
                                progress: progress,
                                entering: false,
                                stageSize: stageSize
                            ))
                        }
                    }
                    .frame(width: stageSize.width, height: stageSize.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { replay() }
        .onChange(of: previewMode) { _, _ in replay() }
        .onChange(of: entry.enterTransition) { _, _ in replay() }
        .onChange(of: entry.enterEasing) { _, _ in replay() }
        .onChange(of: entry.leaveTransition) { _, _ in replay() }
        .onChange(of: entry.leaveEasing) { _, _ in replay() }
        .onChange(of: entry.transitionDuration) { _, _ in replay() }
    }

    private func replay() {
        progress = 0
        withAnimation(.linear(duration: animationDuration)) {
            progress = 1
        }
    }

    private func sceneCard(title: String, subtitle: String, accent: Color) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image = sceneThumbnailImage(projectURL: projectURL, entry: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .overlay(Color.black.opacity(0.28))
                } else {
                    LinearGradient(
                        colors: [
                            entry.backgroundColor.swiftUI.opacity(0.96),
                            entry.backgroundColor.swiftUI.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    previewChip("enter()")
                    previewChip("update(dt)")
                    previewChip("draw()")
                }
            }
            .padding(18)
        }
    }

    private func previewChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.05), in: Capsule())
    }
}

private struct ScenePreviewGrid: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let step: CGFloat = 28

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }

            ctx.stroke(path, with: .color(Color.primary.opacity(0.035)), lineWidth: 0.5)
        }
    }
}

private struct SceneTransitionPreviewModifier: ViewModifier {
    let effect: SceneTransitionEffect
    let easing: SceneTransitionEasing
    let progress: CGFloat
    let entering: Bool
    let stageSize: CGSize

    func body(content: Content) -> some View {
        let state = visualState
        content
            .scaleEffect(state.scale)
            .offset(state.offset)
            .opacity(state.opacity)
    }

    private var visualState: (offset: CGSize, scale: CGFloat, opacity: Double) {
        let t = easedProgress(progress, easing: easing)
        switch effect {
        case .none:
            return (offset: .zero, scale: 1, opacity: entering ? 1 : max(0, 1 - Double(t) * 4))
        case .fade:
            return (offset: .zero, scale: 1, opacity: entering ? Double(t) : Double(1 - t))
        case .pop:
            let scale = entering ? (0.90 + 0.10 * t) : (1.0 - 0.08 * t)
            let opacity = entering ? (0.35 + Double(t) * 0.65) : Double(1 - t)
            return (offset: .zero, scale: scale, opacity: opacity)
        case .slideLeft:
            let dx = entering ? (1 - t) * stageSize.width * 0.82 : -t * stageSize.width * 0.82
            return (offset: CGSize(width: dx, height: 0), scale: 1, opacity: 1)
        case .slideRight:
            let dx = entering ? -(1 - t) * stageSize.width * 0.82 : t * stageSize.width * 0.82
            return (offset: CGSize(width: dx, height: 0), scale: 1, opacity: 1)
        case .slideUp:
            let dy = entering ? (1 - t) * stageSize.height * 0.78 : -t * stageSize.height * 0.78
            return (offset: CGSize(width: 0, height: dy), scale: 1, opacity: 1)
        case .slideDown:
            let dy = entering ? -(1 - t) * stageSize.height * 0.78 : t * stageSize.height * 0.78
            return (offset: CGSize(width: 0, height: dy), scale: 1, opacity: 1)
        }
    }
}

private func sceneThumbnailURL(projectURL: URL, entry: SceneEntry) -> URL? {
    guard !entry.thumbnailPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let url = projectURL.appendingPathComponent(entry.thumbnailPath)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

private func sceneThumbnailImage(projectURL: URL, entry: SceneEntry) -> NSImage? {
    guard let url = sceneThumbnailURL(projectURL: projectURL, entry: entry) else { return nil }
    return NSImage(contentsOf: url)
}

private func easedProgress(_ t: CGFloat, easing: SceneTransitionEasing) -> CGFloat {
    let clamped = min(max(t, 0), 1)
    switch easing {
    case .linear:
        return clamped
    case .easeIn:
        return clamped * clamped
    case .easeOut:
        let inv = 1 - clamped
        return 1 - inv * inv
    case .easeInOut:
        if clamped < 0.5 {
            return 2 * clamped * clamped
        }
        let inv = -2 * clamped + 2
        return 1 - (inv * inv) / 2
    case .bounce:
        let n1: CGFloat = 7.5625
        let d1: CGFloat = 2.75
        if clamped < 1 / d1 {
            return n1 * clamped * clamped
        } else if clamped < 2 / d1 {
            let x = clamped - 1.5 / d1
            return n1 * x * x + 0.75
        } else if clamped < 2.5 / d1 {
            let x = clamped - 2.25 / d1
            return n1 * x * x + 0.9375
        } else {
            let x = clamped - 2.625 / d1
            return n1 * x * x + 0.984375
        }
    }
}

// MARK: - Scene Entry Row

private struct SceneEntryRow: View {
    let projectURL: URL
    let entry: SceneEntry

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let image = sceneThumbnailImage(projectURL: projectURL, entry: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(entry.backgroundColor.swiftUI)
                        Image(systemName: entry.isInitial ? "flag.fill" : "photo")
                            .font(.system(size: 11))
                            .foregroundStyle(entry.isInitial ? .white : .white.opacity(0.9))
                    }
                }
            }
            .frame(width: 38, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(entry.isInitial ? Color.green.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if entry.isInitial {
                        Text("initial")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(entry.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Scene Entry Editor

private struct SceneEntryEditor: View {
    let projectURL: URL
    @Binding var entry: SceneEntry
    let allEntries: [SceneEntry]
    let onSetInitial: () -> Void

    @State private var thumbnailImportStatus = ""
    @State private var thumbnailImportOK = true

    private var initialBinding: Binding<Bool> {
        Binding(
            get: { entry.isInitial },
            set: { newValue in
                if newValue {
                    onSetInitial()
                } else {
                    entry.isInitial = false
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SMSection(title: "IDENTITY", icon: "tag") {
                    SMRow(label: "Lua key") {
                        TextField("name", text: $entry.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }

                    SMRow(label: "Display") {
                        TextField("Display Name", text: $entry.displayName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    Toggle(isOn: initialBinding) {
                        HStack(spacing: 4) {
                            Image(systemName: "flag.fill").foregroundStyle(.green)
                            Text("Initial scene").font(.system(size: 12))
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                SMSection(title: "FILE", icon: "doc.text") {
                    SMRow(label: "Path") {
                        TextField("scenes/\(entry.name).lua", text: $entry.filePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                    Text("Leave empty to auto-generate at scenes/\(entry.name).lua")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                SMSection(title: "APPEARANCE", icon: "paintpalette") {
                    SMRow(label: "Background") {
                        HStack(spacing: 10) {
                            ColorPicker("", selection: Binding(
                                get: { entry.backgroundColor.swiftUI },
                                set: { newColor in
                                    let color = NSColor(newColor)
                                    entry.backgroundColor = UIColor4(
                                        Double(color.redComponent),
                                        Double(color.greenComponent),
                                        Double(color.blueComponent),
                                        Double(color.alphaComponent)
                                    )
                                }
                            ), supportsOpacity: true)
                            .labelsHidden()
                            .frame(width: 28, height: 22)

                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(entry.backgroundColor.swiftUI)
                                .frame(width: 34, height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )

                            Text(String(format: "rgba(%.0f, %.0f, %.0f, %.2f)",
                                        entry.backgroundColor.r * 255,
                                        entry.backgroundColor.g * 255,
                                        entry.backgroundColor.b * 255,
                                        entry.backgroundColor.a))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Text("Used in the transition preview and exported Scene.lua background fill.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    SMRow(label: "Thumbnail") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                TextField("images/scene-thumb.png", text: $entry.thumbnailPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))

                                Button("Choose") {
                                    chooseThumbnailFile()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if !thumbnailImportStatus.isEmpty {
                                Text(thumbnailImportStatus)
                                    .font(.system(size: 10))
                                    .foregroundColor(thumbnailImportOK ? .secondary : .red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                SMSection(title: "TRANSITIONS", icon: "sparkles") {
                    transitionPickerRow("Enter Fx", effect: $entry.enterTransition)
                    easingPickerRow("In Ease", easing: $entry.enterEasing)
                    transitionPickerRow("Leave Fx", effect: $entry.leaveTransition)
                    easingPickerRow("Out Ease", easing: $entry.leaveEasing)
                    SMRow(label: "Duration") {
                        HStack(spacing: 6) {
                            TextField("0.35", value: $entry.transitionDuration, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(width: 76)
                            Text("seconds")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("The center preview uses these same values, and the exported Scene.lua applies them when scenes switch.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SMSection(title: "ON COMPLETE", icon: "forward.end") {
                    SMRow(label: "Trigger") {
                        Picker("Trigger", selection: $entry.completeTrigger) {
                            ForEach(SceneCompleteTrigger.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SMRow(label: "Action") {
                        Picker("Action", selection: $entry.completeAction) {
                            ForEach(SceneCompleteAction.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if entry.completeAction == .switch || entry.completeAction == .push {
                        SMRow(label: "Target") {
                            Picker("Target", selection: $entry.completeTarget) {
                                Text("Choose scene").tag("")
                                ForEach(allEntries.filter { $0.id != entry.id }) { candidate in
                                    Text(candidate.displayName).tag(candidate.name)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if entry.completeTrigger == .timer {
                        SMRow(label: "Delay") {
                            HStack(spacing: 6) {
                                TextField("1.00", value: $entry.completeDelay, format: .number.precision(.fractionLength(2)))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 76)
                                Text("seconds")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text("Use Timer for automatic flow, or Manual / Condition and call Scene:complete() from your scene code.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SMSection(title: "LIFECYCLE", icon: "arrow.triangle.2.circlepath") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        callbackToggle("enter",        "Enter",        icon: "arrow.right.circle", binding: $entry.hasEnter)
                        callbackToggle("leave",        "Leave",        icon: "arrow.left.circle", binding: $entry.hasLeave)
                        callbackToggle("pause",        "Pause",        icon: "pause.circle", binding: $entry.hasPause)
                        callbackToggle("resume",       "Resume",       icon: "play.circle", binding: $entry.hasResume)
                        callbackToggle("transitionStart", "Transition Start", icon: "sparkles", binding: $entry.hasTransitionStart)
                        callbackToggle("exitComplete", "Exit Complete", icon: "flag.checkered", binding: $entry.hasExitComplete)
                        callbackToggle("load",         "Load",         icon: "square.and.arrow.down", binding: $entry.hasLoad)
                        callbackToggle("update(dt)",   "Update",       icon: "clock.arrow.2.circlepath", binding: $entry.hasUpdate)
                        callbackToggle("draw",         "Draw",         icon: "paintbrush", binding: $entry.hasDraw)
                        callbackToggle("keypressed",   "Keypressed",   icon: "keyboard", binding: $entry.hasKeypressed)
                        callbackToggle("keyreleased",  "Keyreleased",  icon: "keyboard.chevron.compact.down", binding: $entry.hasKeyreleased)
                        callbackToggle("mousepressed", "Mousepressed", icon: "cursorarrow.click", binding: $entry.hasMousepressed)
                        callbackToggle("mousereleased", "Mousereleased", icon: "cursorarrow.click.2", binding: $entry.hasMousereleased)
                        callbackToggle("mousemoved",   "Mousemoved",   icon: "cursorarrow.motionlines", binding: $entry.hasMousemoved)
                        callbackToggle("wheelmoved",   "Wheelmoved",   icon: "scroll", binding: $entry.hasWheelmoved)
                        callbackToggle("textinput",    "Textinput",    icon: "textbox", binding: $entry.hasTextinput)
                        callbackToggle("resize",       "Resize",       icon: "arrow.up.left.and.arrow.down.right", binding: $entry.hasResize)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
    }

    private func transitionPickerRow(_ label: String, effect: Binding<SceneTransitionEffect>) -> some View {
        SMRow(label: label) {
            Picker(label, selection: effect) {
                ForEach(SceneTransitionEffect.allCases) { option in
                    Label(option.displayName, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func easingPickerRow(_ label: String, easing: Binding<SceneTransitionEasing>) -> some View {
        SMRow(label: label) {
            Picker(label, selection: easing) {
                ForEach(SceneTransitionEasing.allCases) { option in
                    Label(option.displayName, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func callbackToggle(_ key: String, _ label: String, icon: String, binding: Binding<Bool>) -> some View {
        let isOn = binding.wrappedValue
        return Button {
            binding.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isOn ? Color.green : Color.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 11, weight: .medium))
                    Text(key).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.green : Color.secondary)
                    .font(.system(size: 13))
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? Color.green.opacity(0.07) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isOn ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func chooseThumbnailFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Scene Thumbnail"
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        do {
            let resolvedPath = try importThumbnailFile(from: selectedURL)
            entry.thumbnailPath = resolvedPath
            thumbnailImportStatus = "Using \(resolvedPath)"
            thumbnailImportOK = true
        } catch {
            thumbnailImportStatus = error.localizedDescription
            thumbnailImportOK = false
        }
    }

    private func importThumbnailFile(from sourceURL: URL) throws -> String {
        let fileManager = FileManager.default
        let projectRoot = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()

        if isInsideProject(source, root: projectRoot) {
            return relativePath(from: projectRoot, to: source)
        }

        let imagesDir = projectRoot.appendingPathComponent("images/scene-thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)

        let destination = uniqueImportURL(for: source, in: imagesDir)
        try fileManager.copyItem(at: source, to: destination)
        return "images/scene-thumbnails/\(destination.lastPathComponent)"
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

// MARK: - Sub-components

private struct SMSection<Content: View>: View {
    let title: String
    let icon: String
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
            content()
        }
        .padding(.bottom, 4)
    }
}

private struct SMRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
        }
    }
}
