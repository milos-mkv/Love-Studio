import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Packer mode

private enum PackerMode: String, CaseIterable, Identifiable {
    case atlas        = "Atlas Packer"
    case tilesetMerge = "Tileset Merge"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .atlas:        return "square.grid.3x3.fill"
        case .tilesetMerge: return "square.stack.3d.up.fill"
        }
    }
}

// MARK: - Main View

struct SpritesheetPackerView: View {

    let projectURL: URL

    // ── Mode ─────────────────────────────────────────────────────────────
    @State private var packerMode: PackerMode = .atlas

    // ── Config (Atlas mode) ───────────────────────────────────────────────
    @State private var config = SpritesheetConfig()
    @State private var selectedID: SpriteEntry.ID? = nil

    // ── Pack result (Atlas mode) ──────────────────────────────────────────
    @State private var packResult: PackResult = PackResult(packed: [], atlasSize: .zero, atlasImage: nil, failed: [])
    @State private var isRepacking = false

    // ── Merge settings (Tileset Merge mode) ───────────────────────────────
    @State private var mergeTileSize: Int = 16
    @State private var mergeMaxWidth: Int = 2048
    @State private var mergePowerOfTwo: Bool = true
    @State private var mergeAtlasPath: String = "tiles/merged.png"
    @State private var mergeResult: TilesetMergeResult? = nil
    @State private var isMerging: Bool = false

    // ── UI state ─────────────────────────────────────────────────────────
    @State private var statusMsg:     String  = ""
    @State private var statusSuccess: Bool    = true
    @State private var showLoadSheet: Bool    = false
    @State private var savedConfigs:  [SpritesheetConfig] = []
    @State private var showAtlasPreview = false

    // ── Drag-drop ────────────────────────────────────────────────────────
    @State private var isDropTargeted = false

    // ── Sidebar resize ───────────────────────────────────────────────────
    @State private var sidebarWidth: CGFloat    = 220
    @State private var dragStartWidth: CGFloat  = 220
    private let sidebarMin: CGFloat = 160
    private let sidebarMax: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                leftColumn
                    .frame(width: sidebarWidth)
                // Draggable divider
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                sidebarWidth = min(sidebarMax, max(sidebarMin, dragStartWidth + v.translation.width))
                            }
                            .onEnded { _ in dragStartWidth = sidebarWidth }
                    )
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                rightColumn
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { repack() }
        .onChange(of: config) { _, _ in
            if packerMode == .atlas { repack() } else { runMerge() }
        }
        .onChange(of: packerMode) { _, _ in
            if packerMode == .atlas { repack() } else { runMerge() }
        }
        .onChange(of: mergeTileSize)   { _, _ in if packerMode == .tilesetMerge { runMerge() } }
        .onChange(of: mergeMaxWidth)   { _, _ in if packerMode == .tilesetMerge { runMerge() } }
        .onChange(of: mergePowerOfTwo) { _, _ in if packerMode == .tilesetMerge { runMerge() } }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: packerMode.icon)
                .foregroundStyle(.indigo)
                .font(.system(size: 15, weight: .semibold))

            TextField("Module name", text: $config.projectName)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .frame(minWidth: 100, maxWidth: 200)
                .opacity(packerMode == .atlas ? 1 : 0.3)
                .disabled(packerMode != .atlas)

            // Mode toggle
            HStack(spacing: 0) {
                ForEach(PackerMode.allCases) { mode in
                    Button {
                        packerMode = mode
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon).font(.system(size: 10))
                            Text(mode.rawValue).font(.system(size: 11, weight: packerMode == mode ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(packerMode == mode ? Color.indigo.opacity(0.15) : Color.clear)
                        .foregroundStyle(packerMode == mode ? Color.indigo : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            Spacer()

            // Status
            if !statusMsg.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: statusSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(statusMsg)
                }
                .font(.system(size: 11))
                .foregroundStyle(statusSuccess ? Color.green : Color.red)
                .transition(.opacity)
            }

            // Load
            Button { showLoadSheet = true } label: {
                Label("Load", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showLoadSheet) {
                loadPopover
                    .onAppear { savedConfigs = SpritesheetStore.loadAll(from: projectURL) }
            }

            // Save
            Button {
                do {
                    try SpritesheetStore.save(config, to: projectURL)
                    flash("Saved", success: true)
                } catch {
                    flash("Save failed: \(error.localizedDescription)", success: false)
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Export
            Button {
                if packerMode == .tilesetMerge { exportMerge() } else { exportAll() }
            } label: {
                Label("Export", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.small)
            .disabled(packerMode == .atlas ? packResult.packed.isEmpty : mergeResult == nil)

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Left column (sprite list)

    private var leftColumn: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SPRITES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(config.sprites.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Drop zone + list
            ZStack {
                if config.sprites.isEmpty {
                    emptyDropZone
                } else {
                    spriteList
                }
            }
            .onDrop(of: [.fileURL, .image, .png, .jpeg, .tiff, .gif, .bmp, .folder],
                    isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.indigo, lineWidth: 2)
                        .padding(4)
                }
            }

            Divider()

            // Toolbar
            HStack(spacing: 4) {
                Button {
                    openFilePicker()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .padding(4)

                Button {
                    guard let id = selectedID,
                          let idx = config.sprites.firstIndex(where: { $0.id == id })
                    else { return }
                    config.sprites.remove(at: idx)
                    selectedID = nil
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain)
                .padding(4)
                .disabled(selectedID == nil)

                Spacer()

                Button {
                    config.sprites.removeAll()
                    selectedID = nil
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(4)
                .disabled(config.sprites.isEmpty)
                .help("Remove all sprites")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyDropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Drop images here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("or click + to browse")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var spriteList: some View {
        List(selection: $selectedID) {
            ForEach($config.sprites) { $sprite in
                SpriteEntryRow(sprite: $sprite, projectURL: projectURL)
                    .tag(sprite.id)
            }
            .onMove { from, to in
                config.sprites.move(fromOffsets: from, toOffset: to)
            }
            .onDelete { idx in
                config.sprites.remove(atOffsets: idx)
                selectedID = nil
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Right column

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if packerMode == .tilesetMerge {
                    mergeSettingsPanel
                    mergeMappingPanel
                    mergePreviewPanel
                } else if let id = selectedID,
                   let idx = config.sprites.firstIndex(where: { $0.id == id }) {
                    spriteDetailPanel(binding: $config.sprites[idx])
                } else {
                    settingsPanel
                    atlasPreviewPanel
                }
            }
            .padding(16)
        }
    }

    // MARK: - Merge settings panel

    private var mergeSettingsPanel: some View {
        PackerSectionCard(title: "MERGE SETTINGS", icon: "gearshape") {
            VStack(spacing: 10) {
                PackerRow(label: "Output path") {
                    TextField("tiles/merged.png", text: $mergeAtlasPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
                PackerRow(label: "Tile size") {
                    HStack(spacing: 6) {
                        Picker("", selection: $mergeTileSize) {
                            ForEach([8, 16, 32, 48, 64], id: \.self) { s in
                                Text("\(s) px").tag(s)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 80)
                        Text("All sheets must use the same tile size")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                PackerRow(label: "Max width") {
                    Picker("", selection: $mergeMaxWidth) {
                        Text("512").tag(512)
                        Text("1024").tag(1024)
                        Text("2048").tag(2048)
                        Text("4096").tag(4096)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 80)
                }
                PackerRow(label: "Power of 2") {
                    Toggle("", isOn: $mergePowerOfTwo)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Merge GID mapping panel

    private var mergeMappingPanel: some View {
        PackerSectionCard(title: "GID MAPPING", icon: "number.square") {
            if isMerging {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .frame(height: 60)
            } else if let result = mergeResult {
                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Sheet").frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                        Text("Size").frame(minWidth: 70, alignment: .center)
                        Text("Grid").frame(minWidth: 56, alignment: .center)
                        Text("First GID").frame(minWidth: 64, alignment: .trailing)
                        Text("Last GID").frame(minWidth: 64, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    ForEach(Array(result.sheets.enumerated()), id: \.offset) { i, sheet in
                        HStack(spacing: 0) {
                            Text(URL(fileURLWithPath: sheet.entry.filePath).lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                            Text("\(Int(sheet.nsImage.size.width))×\(Int(sheet.nsImage.size.height))")
                                .frame(minWidth: 70, alignment: .center)
                                .foregroundStyle(.secondary)
                            Text("\(sheet.cols)×\(sheet.rows)")
                                .frame(minWidth: 56, alignment: .center)
                                .foregroundStyle(.secondary)
                            Text("\(sheet.firstGID)")
                                .frame(minWidth: 64, alignment: .trailing)
                                .foregroundStyle(.green)
                            Text("\(sheet.firstGID + sheet.cols * sheet.rows - 1)")
                                .frame(minWidth: 64, alignment: .trailing)
                                .foregroundStyle(.orange)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(i % 2 == 0 ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    }

                    if !result.failed.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text("\(result.failed.count) sheet(s) could not be loaded")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                        .padding(.top, 8)
                    }

                    HStack {
                        Text("Merged: \(result.mergedCols) cols × \(result.mergedRows) rows · \(Int(result.atlasSize.width))×\(Int(result.atlasSize.height)) px")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 6)
                }
            } else if config.sprites.isEmpty {
                Text("Add sprite sheets to the list on the left.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Merge preview panel

    private var mergePreviewPanel: some View {
        PackerSectionCard(title: "MERGED PREVIEW", icon: "photo.stack") {
            if let result = mergeResult, let img = result.atlasImage {
                VStack(spacing: 8) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(checkerboard().clipShape(RoundedRectangle(cornerRadius: 6)))
                        .cornerRadius(6)
                        .onTapGesture { showAtlasPreview = true }
                        .sheet(isPresented: $showAtlasPreview) {
                            VStack(spacing: 12) {
                                Text("Merged Tileset - \(Int(result.atlasSize.width)) × \(Int(result.atlasSize.height))")
                                    .font(.headline)
                                ScrollView([.horizontal, .vertical]) {
                                    Image(nsImage: img).resizable().scaledToFit()
                                        .background(checkerboard()).padding()
                                }
                                Button("Close") { showAtlasPreview = false }
                                    .buttonStyle(.borderedProminent).tint(.indigo)
                            }
                            .padding()
                            .frame(minWidth: 600, minHeight: 500)
                        }
                    Text("\(Int(result.atlasSize.width)) × \(Int(result.atlasSize.height)) px · \(result.sheets.count) tilesets merged")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if !isMerging {
                Text("Add sprite sheets to see the merged preview.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: 80)
            }
        }
    }

    // MARK: - Sprite detail

    private func spriteDetailPanel(binding: Binding<SpriteEntry>) -> some View {
        VStack(alignment: .leading, spacing: 14) {

            // Sprite preview
            let url = resolveURL(binding.wrappedValue.filePath)
            if let img = url.flatMap({ NSImage(contentsOf: $0) }) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .background(checkerboard().clipShape(RoundedRectangle(cornerRadius: 8)))
                    .cornerRadius(8)
                Text("\(Int(img.size.width)) × \(Int(img.size.height)) px")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            PackerSectionCard(title: "SPRITE", icon: "photo") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Name")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        TextField("lua_key", text: binding.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    HStack {
                        Text("File")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        TextField("images/player.png", text: binding.filePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        Button {
                            pickFileForSprite(binding: binding)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            // Pack position (read-only)
            if let packed = packResult.packed.first(where: { $0.entry.id == binding.wrappedValue.id }) {
                PackerSectionCard(title: "PACKED POSITION", icon: "rectangle.dashed") {
                    HStack(spacing: 16) {
                        packInfo("x", value: Int(packed.rect.origin.x))
                        packInfo("y", value: Int(packed.rect.origin.y))
                        packInfo("w", value: Int(packed.rect.size.width))
                        packInfo("h", value: Int(packed.rect.size.height))
                    }
                }
            }
        }
    }

    private func packInfo(_ label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 13, design: .monospaced))
        }
        .frame(minWidth: 48)
    }

    // MARK: - Settings panel

    private var settingsPanel: some View {
        PackerSectionCard(title: "ATLAS SETTINGS", icon: "gearshape") {
            VStack(spacing: 10) {
                PackerRow(label: "Atlas path") {
                    TextField("sprites/atlas.png", text: $config.atlasPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
                PackerRow(label: "Padding") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(config.padding) },
                            set: { config.padding = Int($0) }
                        ), in: 0...32, step: 1)
                        Text("\(config.padding) px")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                PackerRow(label: "Max size") {
                    Picker("", selection: $config.maxSize) {
                        Text("512").tag(512)
                        Text("1024").tag(1024)
                        Text("2048").tag(2048)
                        Text("4096").tag(4096)
                        Text("8192").tag(8192)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 80)
                }
                PackerRow(label: "Power of 2") {
                    Toggle("", isOn: $config.powerOfTwo)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                PackerRow(label: "Trim alpha") {
                    Toggle("", isOn: $config.trimTransparent)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Atlas preview

    private var atlasPreviewPanel: some View {
        PackerSectionCard(title: "ATLAS PREVIEW", icon: "photo.stack") {
            VStack(spacing: 8) {
                if isRepacking {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                        .frame(height: 200)
                } else if let img = packResult.atlasImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(
                            checkerboard()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        )
                        .cornerRadius(6)
                        .onTapGesture { showAtlasPreview = true }
                        .sheet(isPresented: $showAtlasPreview) {
                            atlasFullPreview(img: img)
                        }

                    HStack {
                        Text("\(Int(packResult.atlasSize.width)) × \(Int(packResult.atlasSize.height)) px")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(packResult.packed.count) sprites")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if !packResult.failed.isEmpty {
                            Text("\(packResult.failed.count) missing")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("Add sprites to see the atlas preview.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                }
            }
        }
    }

    private func atlasFullPreview(img: NSImage) -> some View {
        VStack(spacing: 12) {
            Text("Atlas Preview - \(Int(packResult.atlasSize.width)) × \(Int(packResult.atlasSize.height))")
                .font(.headline)
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .background(checkerboard())
                    .padding()
            }
            Button("Close") { showAtlasPreview = false }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
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
                        config = cfg
                        showLoadSheet = false
                    } label: {
                        HStack {
                            Text(cfg.projectName)
                            Spacer()
                            Text("\(cfg.sprites.count) sprites")
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

    // MARK: - Packing

    private func repack() {
        isRepacking = true
        let cfg = config
        let url = projectURL
        Task.detached(priority: .userInitiated) {
            let result = SpritesheetPacker.pack(config: cfg, projectURL: url)
            await MainActor.run {
                packResult   = result
                isRepacking  = false
            }
        }
    }

    // MARK: - Tileset merge

    private func runMerge() {
        guard !config.sprites.isEmpty else { mergeResult = nil; return }
        isMerging = true
        let sprites   = config.sprites
        let tileSize  = mergeTileSize
        let maxWidth  = mergeMaxWidth
        let pow2      = mergePowerOfTwo
        let url       = projectURL
        Task.detached(priority: .userInitiated) {
            let result = TilesetMerger.merge(
                sprites: sprites, tileSize: tileSize,
                maxAtlasWidth: maxWidth,
                powerOfTwo: pow2, projectURL: url)
            await MainActor.run {
                mergeResult = result
                isMerging   = false
            }
        }
    }

    private func exportMerge() {
        guard let result = mergeResult else { return }
        guard let pngData = TilesetMerger.pngData(from: result) else {
            flash("Failed to render merged tileset.", success: false)
            return
        }
        do {
            try SpritesheetStore.exportAtlas(pngData, atlasPath: mergeAtlasPath, to: projectURL)
            flash("Exported \(URL(fileURLWithPath: mergeAtlasPath).lastPathComponent)", success: true)
        } catch {
            flash("Export failed: \(error.localizedDescription)", success: false)
        }
    }

    // MARK: - Export

    private func exportAll() {
        guard !packResult.packed.isEmpty else { return }

        do {
            // Write PNG atlas
            guard let pngData = SpritesheetPacker.pngData(from: packResult) else {
                flash("Failed to render atlas image.", success: false)
                return
            }
            try SpritesheetStore.exportAtlas(pngData, atlasPath: config.atlasPath, to: projectURL)

            // Write Lua module
            let code = SpritesheetCodeGenerator.generate(config: config, packResult: packResult)
            try SpritesheetStore.exportLua(code, projectName: config.projectName, to: projectURL)

            // Write JSON metadata
            let json = SpritesheetCodeGenerator.generateJSON(config: config, packResult: packResult)
            try SpritesheetStore.exportJSON(json, projectName: config.projectName, to: projectURL)

            flash("Exported \(SpritesheetStore.safeName(config.projectName)).lua + .json + atlas", success: true)
        } catch {
            flash("Export failed: \(error.localizedDescription)", success: false)
        }
    }

    // MARK: - File picking

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .bmp, .tiff, .folder]
        panel.directoryURL = projectURL
        panel.message = "Select images or folders (folders are scanned recursively)"

        if panel.runModal() == .OK {
            addURLs(expandURLs(panel.urls))
        }
    }

    /// Expands any folder URLs into all image files found recursively inside them.
    private func expandURLs(_ urls: [URL]) -> [URL] {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif"]
        var result: [URL] = []
        let fm = FileManager.default

        for url in urls {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                // Recursively find all image files in this folder
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    guard imageExts.contains(fileURL.pathExtension.lowercased()) else { continue }
                    result.append(fileURL)
                }
            } else {
                if imageExts.contains(url.pathExtension.lowercased()) {
                    result.append(url)
                }
            }
        }

        // Sort alphabetically so the order is consistent
        return result.sorted { $0.path < $1.path }
    }

    private func pickFileForSprite(binding: Binding<SpriteEntry>) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .bmp, .tiff]
        panel.directoryURL = projectURL

        if panel.runModal() == .OK, let url = panel.url {
            binding.filePath.wrappedValue = relativePath(url)
            if binding.wrappedValue.name == "sprite" || binding.wrappedValue.name.isEmpty {
                binding.name.wrappedValue = SpritesheetCodeGenerator.luaIdent(
                    url.deletingPathExtension().lastPathComponent
                )
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            // loadDataRepresentation is the most reliable API for Finder drag-and-drop on macOS.
            // loadObject(ofClass: URL.self) silently fails because URL doesn't implement
            // NSItemProviderReading for public.file-url in the way SwiftUI expects.
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    let expanded = self.expandURLs([url])
                    DispatchQueue.main.async { self.addURLs(expanded) }
                }
            }
        }
        return true
    }

    private func addURLs(_ urls: [URL]) {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif"]
        var duplicateCount = 0
        for url in urls {
            guard imageExts.contains(url.pathExtension.lowercased()) else { continue }
            let name = SpritesheetCodeGenerator.luaIdent(url.deletingPathExtension().lastPathComponent)
            let path = relativePath(url)
            if config.sprites.contains(where: { $0.filePath == path }) {
                duplicateCount += 1
                continue
            }
            config.sprites.append(SpriteEntry(name: name, filePath: path))
        }
        if duplicateCount > 0 {
            flash("\(duplicateCount) duplicate\(duplicateCount > 1 ? "s" : "") skipped", success: false)
        }
    }

    // MARK: - Helpers

    private func relativePath(_ url: URL) -> String {
        let proj = projectURL.standardized.path
        let file = url.standardized.path
        if file.hasPrefix(proj + "/") {
            return String(file.dropFirst(proj.count + 1))
        }
        return file
    }

    private func resolveURL(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return projectURL.appendingPathComponent(path)
    }

    private func flash(_ msg: String, success: Bool) {
        statusMsg     = msg
        statusSuccess = success
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { if statusMsg == msg { statusMsg = "" } }
        }
    }

    private func checkerboard() -> some View {
        Canvas { ctx, size in
            let s: CGFloat = 8
            var dark = true
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                dark = Int(y / s) % 2 == 0
                while x < size.width {
                    ctx.fill(
                        Path(CGRect(x: x, y: y, width: s, height: s)),
                        with: .color(dark ? Color(white: 0.8) : Color(white: 0.95))
                    )
                    dark.toggle()
                    x += s
                }
                y += s
            }
        }
    }
}

// MARK: - Sprite entry row

private struct SpriteEntryRow: View {
    @Binding var sprite: SpriteEntry
    let projectURL: URL

    @State private var isEditing = false
    @FocusState private var nameFocused: Bool

    private var thumbnail: NSImage? {
        guard !sprite.filePath.isEmpty else { return nil }
        let url = sprite.filePath.hasPrefix("/")
            ? URL(fileURLWithPath: sprite.filePath)
            : projectURL.appendingPathComponent(sprite.filePath)
        return NSImage(contentsOf: url)
    }

    var body: some View {
        HStack(spacing: 8) {
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 1) {
                if isEditing {
                    TextField("lua_key", text: $sprite.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .onSubmit { isEditing = false }
                        .onExitCommand { isEditing = false }
                } else {
                    Text(sprite.name.isEmpty ? "(unnamed)" : sprite.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            isEditing = true
                            nameFocused = true
                        }
                }
                Text(sprite.filePath.isEmpty ? "no file" : URL(fileURLWithPath: sprite.filePath).lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Shared sub-components

private struct PackerSectionCard<Content: View>: View {
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

private struct PackerRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .leading)
            content()
        }
    }
}
