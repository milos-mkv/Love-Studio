import SwiftUI
import UniformTypeIdentifiers

// MARK: - FileTreeView

struct FileTreeView: View {

    let project: Project
    var gitService: GitStatusService? = nil
    var onOpen: ((ProjectItem) -> Void)? = nil
    var onFileURLChanged: ((URL, URL) -> Void)? = nil

    @State private var editingItemID: UUID?
    @State private var selectedItemID: UUID?
    @State private var deleteTarget: ProjectItem?
    @State private var showDeleteConfirm = false
    @State private var isRootDropTarget = false
    @State private var previewItem: ProjectItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(project.items) { item in
                        FileTreeRow(
                            item: item,
                            projectRootURL: project.rootURL,
                            gitService: gitService,
                            depth: 0,
                            selectedItemID: $selectedItemID,
                            editingItemID: $editingItemID,
                            onRename: rename,
                            onNewFile:   { url in createItem(in: url, isFolder: false) },
                            onNewFolder: { url in createItem(in: url, isFolder: true) },
                            onDelete: { item in
                                deleteTarget = item
                                showDeleteConfirm = true
                            },
                            onRefresh: { project.refresh() },
                            onPreview: { item in previewItem = item },
                            onOpen: { item in onOpen?(item) },
                            onFileURLChanged: onFileURLChanged
                        )
                    }

                    // Prazan prostor na dnu kao drop zona za root
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(rootDropOverlay)
            .onDrop(of: [UTType.fileURL, UTType.folder], isTargeted: $isRootDropTarget) { providers in
                dropIntoRoot(providers: providers)
                return true
            }
        }
        .confirmationDialog(
            "Delete \"\(deleteTarget?.name ?? "")\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let t = deleteTarget { deleteItem(t) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        // Delete key kada je item selektovan
        .onKeyPress(.deleteForward) { triggerDeleteSelected(); return .handled }
        .onKeyPress(.delete)        { triggerDeleteSelected(); return .handled }
        .sheet(item: $previewItem) { item in
            AssetPreviewSheet(item: item)
        }
    }

    // MARK: Root Drop

    private var rootDropOverlay: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.pink, lineWidth: 2)
            .padding(4)
            .opacity(isRootDropTarget ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isRootDropTarget)
            .allowsHitTesting(false)
    }

    private func dropIntoRoot(providers: [NSItemProvider]) {
        for provider in providers {
            // fileURL pokriva i fajlove i foldere iz Finder-a
            let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                ? UTType.fileURL.identifier
                : UTType.folder.identifier

            provider.loadItem(forTypeIdentifier: type, options: nil) { data, _ in
                let sourceURL: URL?

                if let url = data as? URL {
                    sourceURL = url
                } else if let urlData = data as? Data {
                    sourceURL = URL(dataRepresentation: urlData, relativeTo: nil)
                } else {
                    sourceURL = nil
                }

                guard let src = sourceURL else { return }
                copyToRoot(from: src)
            }
        }
    }

    private func copyToRoot(from sourceURL: URL) {
        // Ne radimo nista ako je vec u root-u
        let alreadyInRoot = sourceURL.deletingLastPathComponent().path == project.rootURL.path
        guard !alreadyInRoot else { return }

        let finalDest = uniqueDestination(for: sourceURL, in: project.rootURL)

        // Interni drag (unutar projekta) → move, eksterni (Finder) → copy
        let isInternal = sourceURL.path.hasPrefix(project.rootURL.path)

        DispatchQueue.main.async {
            do {
                if isInternal {
                    try FileManager.default.moveItem(at: sourceURL, to: finalDest)
                    project.refresh()
                    onFileURLChanged?(sourceURL, finalDest)
                } else {
                    try FileManager.default.copyItem(at: sourceURL, to: finalDest)
                    project.refresh()
                }
            } catch {
                print("[FileTree] Drop failed: \(error.localizedDescription)")
            }
        }
    }

    private func uniqueDestination(for sourceURL: URL, in folder: URL) -> URL {
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let ext  = sourceURL.pathExtension
        var dest = folder.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let newName = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
            dest = folder.appendingPathComponent(newName)
            counter += 1
        }
        return dest
    }

    private func triggerDeleteSelected() {
        guard editingItemID == nil else { return } // ne brisemo dok je rename aktivan
        guard let id = selectedItemID,
              let item = project.findItem(id: id)
        else { return }
        deleteTarget = item
        showDeleteConfirm = true
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            Text(project.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button { createItem(in: project.rootURL, isFolder: false) } label: {
                Image(systemName: "doc.badge.plus").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("New File")

            Button { createItem(in: project.rootURL, isFolder: true) } label: {
                Image(systemName: "folder.badge.plus").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("New Folder")

            Button {
                _ = project.rootURL.startAccessingSecurityScopedResource()
                project.refresh()
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Refresh")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Actions

    private func createItem(in folder: URL, isFolder: Bool) {
        let baseName = isFolder ? "NewFolder" : "NewFile.lua"
        var target = folder.appendingPathComponent(baseName)
        var counter = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let base = isFolder ? "NewFolder" : "NewFile"
            let ext  = isFolder ? "" : ".lua"
            target = folder.appendingPathComponent("\(base)\(counter)\(ext)")
            counter += 1
        }

        do {
            if isFolder {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                FileManager.default.createFile(atPath: target.path, contents: Data())
            }
            // Otvori parent folder pre refresh-a da ostane otvoren
            if let parentItem = project.findItem(url: folder) {
                parentItem.isExpanded = true
            }
            project.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let created = project.findItem(url: target) {
                    selectedItemID = created.id
                    editingItemID  = created.id
                }
            }
        } catch {
            print("Create failed: \(error)")
        }
    }

    private func rename(item: ProjectItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        let parent  = item.url.deletingLastPathComponent()
        let dest    = parent.appendingPathComponent(trimmed)
        let oldURL  = item.url
        let fm      = FileManager.default

        // On case-insensitive filesystems (macOS APFS/HFS+), renaming
        // "Audio.lua" → "audio.lua" reports dest as already existing.
        // Two-step rename via a temporary name works around this.
        let isCaseOnlyRename = trimmed.lowercased() == item.name.lowercased()
        if isCaseOnlyRename {
            let tmp = parent.appendingPathComponent("__ls_rename_tmp_\(UUID().uuidString)")
            try? fm.moveItem(at: oldURL, to: tmp)
            try? fm.moveItem(at: tmp, to: dest)
        } else {
            guard !fm.fileExists(atPath: dest.path) else { return }
            try? fm.moveItem(at: oldURL, to: dest)
        }
        project.refresh()
        onFileURLChanged?(oldURL, dest)
    }

    private func deleteItem(_ item: ProjectItem) {
        try? FileManager.default.removeItem(at: item.url)
        project.refresh()
    }
}

// MARK: - FileTreeRow

struct FileTreeRow: View {

    let item: ProjectItem
    let projectRootURL: URL
    var gitService: GitStatusService? = nil
    let depth: Int
    @Binding var selectedItemID: UUID?
    @Binding var editingItemID: UUID?

    let onRename:          (ProjectItem, String) -> Void
    let onNewFile:         (URL) -> Void
    let onNewFolder:       (URL) -> Void
    let onDelete:          (ProjectItem) -> Void
    let onRefresh:         () -> Void
    let onPreview:         (ProjectItem) -> Void
    let onOpen:            (ProjectItem) -> Void
    var onFileURLChanged:  ((URL, URL) -> Void)? = nil

    @State private var isHovered    = false
    @State private var isDropTarget = false
    @State private var editingText  = ""
    @FocusState private var isFocused: Bool

    private var isSelected: Bool { selectedItemID == item.id }
    private var isEditing:  Bool { editingItemID  == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
            if item.isFolder && item.isExpanded {
                ForEach(item.children) { child in
                    FileTreeRow(
                        item: child,
                        projectRootURL: projectRootURL,
                        gitService: gitService,
                        depth: depth + 1,
                        selectedItemID: $selectedItemID,
                        editingItemID: $editingItemID,
                        onRename: onRename,
                        onNewFile: onNewFile,
                        onNewFolder: onNewFolder,
                        onDelete: onDelete,
                        onRefresh: onRefresh,
                        onPreview: onPreview,
                        onOpen: onOpen,
                        onFileURLChanged: onFileURLChanged
                    )
                }
            }
        }
    }
    // MARK: Row Content

    private var rowContent: some View {
        HStack(spacing: 4) {
            // Indentation
            Color.clear.frame(width: CGFloat(depth) * 16)

            // Chevron
            if item.isFolder {
                Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .frame(width: 12)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            item.isExpanded.toggle()
                        }
                    }
            } else {
                Color.clear.frame(width: 12)
            }

            // Icon
            FileItemIcon(item: item, isSelected: isSelected)
                .frame(width: 16, height: 16)

            // Name or rename TextField
            if isEditing {
                TextField("", text: $editingText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { editingItemID = nil }
                    .padding(.vertical, 1)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.accentColor, lineWidth: 1.5)
                            )
                    )
            } else {
                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundStyle(rowTextColor)
                    .lineLimit(1)
            }

            Spacer()

            if let gitIndicator {
                GitTreeStatusBadge(indicator: gitIndicator, isSelected: isSelected)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            selectedItemID = item.id
            if item.isFolder {
                withAnimation(.easeInOut(duration: 0.15)) {
                    item.isExpanded.toggle()
                }
            } else if item.kind == .image || item.kind == .audio || item.kind == .font {
                onPreview(item)
            } else if item.kind == .lua || item.kind == .other {
                onOpen(item)
            }
        }
        .contextMenu { contextMenuItems }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTarget) { providers in
            guard item.isFolder else { return false }
            handleDrop(providers: providers, into: item.url)
            return true
        }
        .onChange(of: editingItemID) { _, newVal in
            if newVal == item.id {
                editingText = item.name
                // Delay focus slightly so TextField is rendered first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFocused = true
                }
            }
        }
    }

    private var rowTextColor: Color {
        if isSelected { return .white }
        if let indicator = gitIndicator {
            return indicator.color
        }
        return .primary
    }

    private var gitIndicator: GitTreeIndicator? {
        if item.isFolder {
            return aggregatedGitIndicator(for: item)
        }
        guard let gitService,
              let relativePath = relativeGitPath(for: item.url),
              let state = gitService.statuses[relativePath] else { return nil }
        return GitTreeIndicator(state: state, count: nil)
    }

    private func aggregatedGitIndicator(for item: ProjectItem) -> GitTreeIndicator? {
        guard let gitService else { return nil }

        var count = 0
        var highest: GitTreeIndicator? = nil

        func visit(_ current: ProjectItem) {
            if current.isFolder {
                for child in current.children {
                    visit(child)
                }
                return
            }

            guard let relativePath = relativeGitPath(for: current.url),
                  let state = gitService.statuses[relativePath] else { return }

            count += 1
            let candidate = GitTreeIndicator(state: state, count: nil)
            if highest == nil || candidate.priority > highest!.priority {
                highest = candidate
            }
        }

        visit(item)

        guard var highest else { return nil }
        highest.count = count
        return highest
    }

    private func relativeGitPath(for url: URL) -> String? {
        let rootPath = projectRootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return nil }

        var relative = String(filePath.dropFirst(rootPath.count))
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative.isEmpty ? nil : relative
    }

    // MARK: Background

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(
                isDropTarget  ? Color.pink.opacity(0.15)  :
                isSelected    ? Color.accentColor          :
                isHovered     ? Color.primary.opacity(0.07):
                                Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isDropTarget ? Color.pink.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .padding(.horizontal, 4)
    }

    // MARK: Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if item.isFolder {
            Button("New File")   { onNewFile(item.url)   }
            Button("New Folder") { onNewFolder(item.url) }
            Divider()
        }
        if !item.isFolder && (item.kind == .image || item.kind == .audio || item.kind == .font) {
            Button("Preview") { onPreview(item) }
            Divider()
        }
        if !item.isFolder && (item.kind == .lua || item.kind == .other) {
            Button("Open") { onOpen(item) }
            Divider()
        }
        Button("Rename") {
            selectedItemID = item.id
            editingText    = item.name
            editingItemID  = item.id
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(
                item.url.path,
                inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path
            )
        }
        Divider()
        Button("Delete", role: .destructive) { onDelete(item) }
    }

    // MARK: Drag & Drop

    private func handleDrop(providers: [NSItemProvider], into folder: URL) {
        for provider in providers {
            let typeID = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                ? UTType.fileURL.identifier
                : UTType.folder.identifier

            provider.loadItem(forTypeIdentifier: typeID, options: nil) { data, _ in
                let sourceURL: URL?
                if let url = data as? URL { sourceURL = url }
                else if let d = data as? Data { sourceURL = URL(dataRepresentation: d, relativeTo: nil) }
                else { sourceURL = nil }

                guard let src = sourceURL else { return }

                // Non cadere in se stesso
                guard !folder.path.hasPrefix(src.path) else { return }

                // Non cadere nella stessa cartella
                guard src.deletingLastPathComponent().path != folder.path else { return }

                var dest = folder.appendingPathComponent(src.lastPathComponent)
                var counter = 1
                let name = src.deletingPathExtension().lastPathComponent
                let ext  = src.pathExtension
                while FileManager.default.fileExists(atPath: dest.path) {
                    let newName = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
                    dest = folder.appendingPathComponent(newName)
                    counter += 1
                }

                DispatchQueue.main.async {
                    do {
                        try FileManager.default.moveItem(at: src, to: dest)
                        onRefresh()
                        onFileURLChanged?(src, dest)
                    } catch {
                        print("[FileTree] Folder drop failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: Rename

    private func commitRename() {
        onRename(item, editingText)
        editingItemID = nil
    }

    // MARK: Icon Color (used for SF Symbol fallback tint)

    private var iconColor: Color {
        if item.isFolder { return .pink }
        switch item.kind {
        case .lua:   return .cyan
        case .image: return .green
        case .audio: return .orange
        case .font:  return .purple
        case .other: return .secondary
        }
    }
}

private struct GitTreeIndicator {
    let text: String
    let color: Color
    var count: Int?

    let priority: Int

    init(state: GitFileState, count: Int?) {
        self.count = count

        if case .unmerged = state.status {
            let c = state.status.color
            self.text = state.status.label
            self.color = Color(red: c.r, green: c.g, blue: c.b)
            self.priority = 6
            return
        }

        if state.hasStagedChanges {
            let staged = GitFileStatus.added.color
            self.text = "A"
            self.color = Color(red: staged.r, green: staged.g, blue: staged.b)
            self.priority = 5
            return
        }

        let c = state.status.color
        self.text = state.status.label
        self.color = Color(red: c.r, green: c.g, blue: c.b)
        switch state.status {
        case .deleted:  self.priority = 4
        case .modified: self.priority = 3
        case .renamed:  self.priority = 2
        case .added:    self.priority = 1
        case .unmerged: self.priority = 6
        }
    }
}

private struct GitTreeStatusBadge: View {
    let indicator: GitTreeIndicator
    let isSelected: Bool

    var body: some View {
        Text(indicator.text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(isSelected ? Color.white.opacity(0.92) : indicator.color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.16) : indicator.color.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.24) : indicator.color.opacity(0.28),
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - FileItemIcon

private struct FileItemIcon: View {
    let item: ProjectItem
    let isSelected: Bool

    /// Extenzije koje imaju Devicon SVG u bundle-u
    private static let deviconExtensions: Set<String> = [
        "lua", "html", "htm", "css", "js", "ts",
        "py", "c", "cpp", "h", "hpp",
        "sh", "bash", "yaml", "yml", "json", "xml", "md", "markdown"
    ]

    private var ext: String { item.url.pathExtension.lowercased() }

    /// Mapira ekstenziju na ime SVG fajla u Resources/FileIcons/
    private var deviconName: String? {
        switch ext {
        case "lua":               return "lua"
        case "love":              return "love2d"
        case "html", "htm":       return "html"
        case "css":               return "css"
        case "js":                return "js"
        case "ts":                return "ts"
        case "py":                return "py"
        case "c":                 return "c"
        case "cpp", "h", "hpp":   return "cpp"
        case "sh", "bash":        return "sh"
        case "yaml", "yml":       return "yaml"
        case "json":              return "json"
        case "xml":               return "xml"
        case "md", "markdown":    return "markdown"
        default:                  return nil
        }
    }

    var body: some View {
        Group {
            if item.isFolder {
                // Folder — SF Symbol sa bojom
                Image(systemName: item.isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : Color.pink)
            } else if item.url.lastPathComponent == "conf.lua" {
                // Special conf.lua icon
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : Color(red: 1.0, green: 0.28, blue: 0.58))
            } else if let name = deviconName,
                      let url = Bundle.main.url(forResource: name, withExtension: "svg"),
                      let img = NSImage(contentsOf: url) {
                // Devicon SVG — template mode za tintovanje
                Image(nsImage: img)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(isSelected ? Color.white : Color.pink)
            } else {
                // SF Symbol fallback (image, audio, font, other)
                Image(systemName: item.kind.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : sfIconColor)
            }
        }
    }

    private var sfIconColor: Color {
        switch item.kind {
        case .image: return .green
        case .audio: return .orange
        case .font:  return .purple
        default:     return .secondary
        }
    }
}
