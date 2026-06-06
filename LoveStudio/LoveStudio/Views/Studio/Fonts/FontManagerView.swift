import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreText

// MARK: - Main View

struct FontManagerView: View {

    let projectURL: URL
    let onDismiss:  () -> Void

    @State private var config        = FontManagerConfig()
    @State private var selectedID:   FontEntry.ID? = nil
    @State private var statusMsg     = ""
    @State private var statusOK      = true
    @State private var showLoad      = false
    @State private var savedConfigs: [FontManagerConfig] = []

    private var selectedEntry: Binding<FontEntry>? {
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
                rightColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "textformat.size")
                .foregroundStyle(.yellow)
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
                    .onAppear { savedConfigs = FontManagerStore.loadAll(from: projectURL) }
            }

            Button {
                do {
                    try FontManagerStore.save(config, to: projectURL)
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
                    let code = FontCodeGenerator.generate(config: config)
                    try FontManagerStore.exportLua(code, moduleName: config.moduleName, to: projectURL)
                    flash("Exported \(FontManagerStore.safeName(config.moduleName)).lua", ok: true)
                } catch {
                    flash("Export failed: \(error.localizedDescription)", ok: false)
                }
            } label: {
                Label("Export", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
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
        VStack(spacing: 0) {
            HStack {
                Text("FONTS")
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
                    Image(systemName: "textformat.size")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Click + to add a font")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach($config.entries) { $entry in
                        FontEntryRow(entry: entry)
                            .tag(entry.id)
                    }
                    .onMove { from, to in config.entries.move(fromOffsets: from, toOffset: to) }
                    .onDelete { idx in
                        config.entries.remove(atOffsets: idx)
                        selectedID = nil
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack(spacing: 4) {
                Button {
                    let name = uniqueName(base: "font")
                    let entry = FontEntry(name: name)
                    config.entries.append(entry)
                    selectedID = entry.id
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(4)

                Button {
                    guard let id = selectedID,
                          let idx = config.entries.firstIndex(where: { $0.id == id })
                    else { return }
                    config.entries.remove(at: idx)
                    selectedID = nil
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
        .frame(width: 200)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Right column

    private var rightColumn: some View {
        Group {
            if let binding = selectedEntry {
                FontEntryEditor(entry: binding, projectURL: projectURL)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.click")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Select a font to edit")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
                        selectedID = nil
                    } label: {
                        HStack {
                            Text(cfg.moduleName)
                            Spacer()
                            Text("\(cfg.entries.count) fonts")
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

    private func uniqueName(base: String) -> String {
        var idx = 1
        var candidate = base
        while config.entries.contains(where: { $0.name == candidate }) {
            candidate = "\(base)\(idx)"
            idx += 1
        }
        return candidate
    }

    private func flash(_ msg: String, ok: Bool) {
        statusMsg = msg; statusOK = ok
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { if statusMsg == msg { statusMsg = "" } }
        }
    }
}

// MARK: - Font entry row

private struct FontEntryRow: View {
    let entry: FontEntry
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.source.icon)
                .font(.system(size: 12))
                .foregroundStyle(.yellow)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(entry.source.displayName)  ·  \(entry.size)px")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Font entry editor

private struct FontEntryEditor: View {
    @Binding var entry: FontEntry
    let projectURL: URL

    // Load system fonts for the picker
    @State private var systemFonts: [String] = []
    @State private var useSystemFont = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Identity
                FMSection(title: "IDENTITY", icon: "tag") {
                    FMRow(label: "Lua key") {
                        TextField("name", text: $entry.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }

                // Source type
                FMSection(title: "SOURCE", icon: entry.source.icon) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(FontSource.allCases) { src in
                            let isSelected = entry.source == src
                            Button {
                                entry.source = src
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.yellow : Color.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(src.displayName)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(sourceHint(src))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? Color.yellow.opacity(0.08) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(isSelected ? Color.yellow.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // File path (for file + imageFont)
                if entry.source != .default {
                    FMSection(title: "FILE", icon: "folder") {
                        VStack(spacing: 8) {
                            FMRow(label: "Path") {
                                HStack(spacing: 6) {
                                    TextField(entry.source == .imageFont ? "fonts/font.png" : "fonts/font.ttf",
                                              text: $entry.filePath)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                    Button {
                                        pickFile()
                                    } label: {
                                        Image(systemName: "folder")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            // File exists indicator
                            let url = resolveURL(entry.filePath)
                            let exists = url.flatMap { try? $0.checkResourceIsReachable() } ?? false
                            if !entry.filePath.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(exists ? .green : .red)
                                    Text(exists ? "File found on disk" : "File not found - will use fallback size \(entry.fallback)px at runtime")
                                        .foregroundStyle(exists ? Color.secondary : Color.orange)
                                }
                                .font(.system(size: 10))
                            }

                            if entry.source == .imageFont {
                                FMRow(label: "Glyphs") {
                                    TextField("ABCD…", text: $entry.glyphs)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                            }
                        }
                    }
                }

                // Size
                FMSection(title: "SIZE", icon: "textformat.size") {
                    VStack(spacing: 8) {
                        FMRow(label: "Size") {
                            HStack(spacing: 8) {
                                Slider(value: Binding(
                                    get: { Double(entry.size) },
                                    set: { entry.size = Int($0) }
                                ), in: 6...128, step: 1)
                                Text("\(entry.size) px")
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 46, alignment: .trailing)
                            }
                        }
                        if entry.source == .file {
                            FMRow(label: "Fallback") {
                                HStack(spacing: 8) {
                                    Slider(value: Binding(
                                        get: { Double(entry.fallback) },
                                        set: { entry.fallback = Int($0) }
                                    ), in: 6...64, step: 1)
                                    Text("\(entry.fallback) px")
                                        .font(.system(size: 11, design: .monospaced))
                                        .frame(width: 46, alignment: .trailing)
                                }
                            }
                            Text("Used if the font file is not found at runtime.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Outline
                if entry.source != .imageFont {
                    FMSection(title: "OUTLINE", icon: "circle.dashed") {
                        VStack(spacing: 8) {
                            Toggle(isOn: $entry.outlineEnabled) {
                                Text("Enable outline")
                                    .font(.system(size: 12))
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            if entry.outlineEnabled {
                                FMRow(label: "Thickness") {
                                    HStack(spacing: 8) {
                                        Slider(value: Binding(
                                            get: { Double(entry.outlineSize) },
                                            set: { entry.outlineSize = Int($0) }
                                        ), in: 1...8, step: 1)
                                        Text("\(entry.outlineSize) px")
                                            .font(.system(size: 11, design: .monospaced))
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                }

                                FMRow(label: "Color") {
                                    HStack(spacing: 8) {
                                        ColorPicker("", selection: Binding(
                                            get: {
                                                Color(red: Double(entry.outlineR) / 255,
                                                      green: Double(entry.outlineG) / 255,
                                                      blue: Double(entry.outlineB) / 255,
                                                      opacity: Double(entry.outlineA) / 255)
                                            },
                                            set: { color in
                                                let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
                                                entry.outlineR = Int((resolved.redComponent   * 255).rounded())
                                                entry.outlineG = Int((resolved.greenComponent * 255).rounded())
                                                entry.outlineB = Int((resolved.blueComponent  * 255).rounded())
                                                entry.outlineA = Int((resolved.alphaComponent * 255).rounded())
                                            }
                                        ), supportsOpacity: true)
                                        .labelsHidden()
                                        .frame(width: 32, height: 22)

                                        Text("R:\(entry.outlineR) G:\(entry.outlineG) B:\(entry.outlineB) A:\(entry.outlineA)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text("Outline is drawn by offsetting the text in all directions - performance cost grows with thickness.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // Preview
                FMSection(title: "PREVIEW", icon: "eye") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Preview text", text: $entry.previewText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))

                        // Live preview using closest system font approximation
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                            ZStack {
                                // Outline layer (simulated via shadow)
                                if entry.outlineEnabled {
                                    let olColor = Color(
                                        red: Double(entry.outlineR) / 255,
                                        green: Double(entry.outlineG) / 255,
                                        blue: Double(entry.outlineB) / 255,
                                        opacity: Double(entry.outlineA) / 255
                                    )
                                    Text(entry.previewText.isEmpty ? "The quick brown fox" : entry.previewText)
                                        .font(previewFont())
                                        .foregroundStyle(olColor)
                                        .shadow(color: olColor, radius: 0, x:  CGFloat(entry.outlineSize), y: 0)
                                        .shadow(color: olColor, radius: 0, x: -CGFloat(entry.outlineSize), y: 0)
                                        .shadow(color: olColor, radius: 0, x: 0, y:  CGFloat(entry.outlineSize))
                                        .shadow(color: olColor, radius: 0, x: 0, y: -CGFloat(entry.outlineSize))
                                        .lineLimit(3)
                                }
                                Text(entry.previewText.isEmpty ? "The quick brown fox" : entry.previewText)
                                    .font(previewFont())
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                            }
                            .padding(12)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)

                        HStack(spacing: 12) {
                            previewStat("Size", "\(entry.size)px")
                            previewStat("Source", entry.source.displayName)
                            if entry.source == .file {
                                previewStat("File", URL(fileURLWithPath: entry.filePath).lastPathComponent)
                            }
                        }

                        Text("Preview uses a system font approximation. Final appearance depends on the font file loaded in LÖVE2D.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                // Generated Lua snippet
                FMSection(title: "GENERATED CODE", icon: "chevron.left.forwardslash.chevron.right") {
                    Text(luaSnippet())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        .textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func previewFont() -> Font {
        // Try to load the actual font file for live preview
        if entry.source == .file, !entry.filePath.isEmpty,
           let url = resolveURL(entry.filePath),
           let cfArray = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL),
           let descs = cfArray as? [CTFontDescriptor],
           let desc = descs.first {
            let ctFont = CTFontCreateWithFontDescriptor(desc, CGFloat(entry.size), nil)
            return Font(ctFont as NSFont)
        }
        return .system(size: CGFloat(entry.size))
    }

    private func previewStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11))
                .lineLimit(1)
        }
    }

    private func luaSnippet() -> String {
        let key = FontCodeGenerator.luaIdent(entry.name)
        var lines: [String] = []
        switch entry.source {
        case .default:
            lines.append("_fonts.\(key) = love.graphics.newFont(\(entry.size))")
        case .file:
            let path = entry.filePath.isEmpty ? "fonts/\(entry.name).ttf" : entry.filePath
            lines.append("_fonts.\(key) = love.graphics.newFont(\"\(path)\", \(entry.size))")
        case .imageFont:
            let path = entry.filePath.isEmpty ? "fonts/\(entry.name).png" : entry.filePath
            lines.append("_fonts.\(key) = love.graphics.newImageFont(\"\(path)\", \"...\")")
        }
        if entry.outlineEnabled {
            let r = String(format: "%.3f", Double(entry.outlineR) / 255.0)
            let g = String(format: "%.3f", Double(entry.outlineG) / 255.0)
            let b = String(format: "%.3f", Double(entry.outlineB) / 255.0)
            let a = String(format: "%.3f", Double(entry.outlineA) / 255.0)
            lines.append("_outlines.\(key) = { size = \(entry.outlineSize),")
            lines.append("    r = \(r), g = \(g), b = \(b), a = \(a) }")
        }
        return lines.joined(separator: "\n")
    }

    private func sourceHint(_ src: FontSource) -> String {
        switch src {
        case .default:   return "love.graphics.newFont(size) - no file needed"
        case .file:      return "love.graphics.newFont(\"path\", size) - TTF or OTF"
        case .imageFont: return "love.graphics.newImageFont(\"path\", glyphs) - bitmap"
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = entry.source == .imageFont
            ? [UTType.png, UTType.jpeg, UTType.tiff]
            : [UTType(filenameExtension: "ttf")!, UTType(filenameExtension: "otf")!]
        panel.directoryURL = projectURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Copy the file into <project>/fonts/ if it's not already inside the project
        let fontsDir = projectURL.appendingPathComponent("fonts")
        let destURL  = fontsDir.appendingPathComponent(url.lastPathComponent)
        let proj     = projectURL.standardized.path
        let file     = url.standardized.path

        if file.hasPrefix(proj + "/") {
            // Already inside project - just use relative path
            entry.filePath = String(file.dropFirst(proj.count + 1))
        } else {
            // External file - copy into fonts/
            do {
                try FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: url, to: destURL)
                entry.filePath = "fonts/\(url.lastPathComponent)"
            } catch {
                // Copy failed - fall back to absolute path
                entry.filePath = file
            }
        }
    }

    private func resolveURL(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return projectURL.appendingPathComponent(path)
    }
}

// MARK: - Sub-components

private struct FMSection<Content: View>: View {
    let title: String
    let icon:  String
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

private struct FMRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            content()
        }
    }
}
