import SwiftUI
import AppKit

// MARK: - Main View

struct SaveSystemView: View {

    let projectURL: URL
    let onDismiss:  () -> Void

    @State private var config      = SaveSystemConfig()
    @State private var selectedID: SaveField.ID? = nil
    @State private var statusMsg   = ""
    @State private var statusOK    = true
    @State private var showLoad    = false
    @State private var savedConfigs: [SaveSystemConfig] = []
    @State private var previewTab: PreviewTab = .json

    enum PreviewTab: String, CaseIterable { case json = "JSON Preview", code = "Lua Code" }

    private var selectedField: Binding<SaveField>? {
        guard let id = selectedID,
              let idx = config.fields.firstIndex(where: { $0.id == id })
        else { return nil }
        return $config.fields[idx]
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                leftColumn
                Divider()
                centerColumn
                Divider()
                rightColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 960, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 15, weight: .semibold))

            TextField("Module name", text: $config.moduleName)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 120)

            Text("→")
                .foregroundStyle(.secondary)

            TextField("filename.json", text: $config.fileName)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 140)
            Text(".json")
                .font(.system(size: 12)).foregroundStyle(.secondary)

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

            Button { showLoad = true } label: {
                Label("Load", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .popover(isPresented: $showLoad) {
                loadPopover
                    .onAppear { savedConfigs = SaveSystemStore.loadAll(from: projectURL) }
            }

            Button {
                do {
                    try SaveSystemStore.save(config, to: projectURL)
                    flash("Saved", ok: true)
                } catch {
                    flash("Save failed: \(error.localizedDescription)", ok: false)
                }
            } label: { Label("Save", systemImage: "square.and.arrow.down") }
            .buttonStyle(.bordered).controlSize(.small)

            Button {
                do {
                    let url = try SaveSystemStore.exportLua(config, to: projectURL)
                    flash("Exported \(url.lastPathComponent)", ok: true)
                } catch {
                    flash("Export failed: \(error.localizedDescription)", ok: false)
                }
            } label: { Label("Export", systemImage: "arrow.up.forward.square") }
            .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)

            Divider().frame(height: 16)
            Button { onDismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Close")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Left column — field list

    private var leftColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("FIELDS")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(config.fields.count)")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()

            if config.fields.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("Click + to add a field")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedID) {
                    ForEach($config.fields) { $field in
                        SaveFieldRow(field: field).tag(field.id)
                    }
                    .onMove { from, to in config.fields.move(fromOffsets: from, toOffset: to) }
                    .onDelete { idx in config.fields.remove(atOffsets: idx); selectedID = nil }
                }
                .listStyle(.sidebar)
            }

            Divider()
            HStack(spacing: 0) {
                // Quick-add presets
                Menu {
                    Section("Common") {
                        quickAdd("score",       type: .number,  def: "0",       desc: "Player score")
                        quickAdd("level",       type: .number,  def: "1",       desc: "Current level")
                        quickAdd("health",      type: .number,  def: "100",     desc: "Player health")
                        quickAdd("coins",       type: .number,  def: "0",       desc: "Coins collected")
                        quickAdd("highScore",   type: .number,  def: "0",       desc: "Best score ever")
                    }
                    Section("Player") {
                        quickAdd("playerName",  type: .string,  def: "\"Hero\"", desc: "Player name")
                        quickAdd("playTime",    type: .number,  def: "0",       desc: "Total play time (seconds)")
                        quickAdd("deaths",      type: .number,  def: "0",       desc: "Total deaths")
                    }
                    Section("Settings") {
                        quickAdd("musicVolume", type: .number,  def: "1.0",     desc: "Music volume 0–1")
                        quickAdd("sfxVolume",   type: .number,  def: "1.0",     desc: "SFX volume 0–1")
                        quickAdd("fullscreen",  type: .boolean, def: "false",   desc: "Fullscreen mode")
                        quickAdd("difficulty",  type: .string,  def: "\"normal\"", desc: "Difficulty setting")
                        quickAdd("language",    type: .string,  def: "\"en\"",  desc: "UI language code")
                    }
                    Section("Progress") {
                        quickAdd("unlockedLevels", type: .table, def: "{}",     desc: "List of unlocked level IDs")
                        quickAdd("achievements",   type: .table, def: "{}",     desc: "Unlocked achievements")
                        quickAdd("tutorialDone",   type: .boolean, def: "false", desc: "Tutorial completed")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28, height: 28)

                Button {
                    guard let id = selectedID,
                          let idx = config.fields.firstIndex(where: { $0.id == id })
                    else { return }
                    config.fields.remove(at: idx); selectedID = nil
                } label: { Image(systemName: "minus") }
                .buttonStyle(.plain).padding(4)
                .disabled(selectedID == nil)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .frame(width: 210)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func quickAdd(_ name: String, type: SaveFieldType, def: String, desc: String) -> some View {
        Button(name) {
            let field = SaveField(name: name, type: type, defaultValue: def, description: desc)
            config.fields.append(field)
            selectedID = field.id
        }
    }

    // MARK: - Center column — field editor

    private var centerColumn: some View {
        Group {
            if let binding = selectedField {
                SaveFieldEditor(field: binding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.click")
                        .font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("Select a field to edit")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 260)
    }

    // MARK: - Right column — preview

    private var rightColumn: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(PreviewTab.allCases, id: \.self) { tab in
                    let sel = previewTab == tab
                    Button { previewTab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: sel ? .semibold : .regular))
                            .foregroundStyle(sel ? Color.orange : Color.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .overlay(alignment: .bottom) {
                                if sel { Rectangle().fill(Color.orange).frame(height: 2) }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .background(.bar)
            Divider()

            ScrollView {
                Text(previewTab == .json
                     ? SaveCodeGenerator.jsonPreview(config: config)
                     : SaveCodeGenerator.generate(config: config))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: 320)
    }

    // MARK: - Load popover

    private var loadPopover: some View {
        VStack(spacing: 0) {
            Text("Saved Configs").font(.system(size: 12, weight: .semibold)).padding(10)
            Divider()
            if savedConfigs.isEmpty {
                Text("No saved configs.").font(.system(size: 12)).foregroundStyle(.secondary).padding(16)
            } else {
                ForEach(savedConfigs) { cfg in
                    Button {
                        config = cfg; showLoad = false; selectedID = nil
                    } label: {
                        HStack {
                            Text(cfg.moduleName)
                            Spacer()
                            Text("\(cfg.fields.count) fields").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 200)
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

// MARK: - Save Field Row

private struct SaveFieldRow: View {
    let field: SaveField
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(typeColor(field.type).opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: field.type.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(typeColor(field.type))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(field.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(field.type.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if !field.defaultValue.isEmpty {
                        Text("= \(field.defaultValue)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func typeColor(_ t: SaveFieldType) -> Color {
        switch t {
        case .number:  return .blue
        case .string:  return .green
        case .boolean: return .orange
        case .table:   return .purple
        }
    }
}

// MARK: - Save Field Editor

private struct SaveFieldEditor: View {
    @Binding var field: SaveField

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Identity
                SVSection(title: "IDENTITY", icon: "tag") {
                    SVRow(label: "Lua key") {
                        TextField("fieldName", text: $field.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    SVRow(label: "Description") {
                        TextField("e.g. Player score", text: $field.description)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                }

                // Type
                SVSection(title: "TYPE", icon: "tray.2") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(SaveFieldType.allCases) { t in
                            let sel = field.type == t
                            Button { field.type = t } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: t.icon)
                                        .font(.system(size: 12))
                                        .foregroundStyle(sel ? Color.orange : Color.secondary)
                                        .frame(width: 16)
                                    Text(t.displayName)
                                        .font(.system(size: 12, weight: sel ? .semibold : .regular))
                                    Spacer()
                                    if sel {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(sel ? Color.orange.opacity(0.10) : Color.clear)
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(sel ? Color.orange.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Default value
                SVSection(title: "DEFAULT VALUE", icon: "dial.low") {
                    SVRow(label: "Default") {
                        TextField(field.type.defaultPlaceholder, text: $field.defaultValue)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    typeHint
                }

                // Generated snippet
                SVSection(title: "USAGE", icon: "chevron.left.forwardslash.chevron.right") {
                    let key = SaveCodeGenerator.luaIdent(field.name)
                    let Cap = key.prefix(1).uppercased() + key.dropFirst()
                    let mod = "Save"
                    Text("""
-- Read
local val = \(mod).data.\(key)

-- Write (in memory)
\(mod).data.\(key) = newValue

-- Typed getter / setter
local val = \(mod):get\(Cap)()
\(mod):set\(Cap)(newValue)

-- Persist to disk
\(mod):save()
""")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor)))
                        .textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var typeHint: some View {
        switch field.type {
        case .number:
            Text("Lua number literal: 0, 42, 3.14, 1e6")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        case .string:
            Text("Wrap in quotes: \"hello\"  or  \"normal\"")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        case .boolean:
            Text("Must be: true  or  false")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        case .table:
            Text("{} for empty table. Elements are saved as JSON arrays/objects.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Sub-components

private struct SVSection<Content: View>: View {
    let title: String
    let icon:  String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(.bottom, 4)
    }
}

private struct SVRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
        }
    }
}
