import Foundation

// MARK: - FileKind

enum FileKind {
    case lua, image, audio, font, other

    init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "lua":
            self = .lua
        case "png", "jpg", "jpeg", "gif", "bmp", "tga", "hdr":
            self = .image
        case "wav", "ogg", "mp3", "flac":
            self = .audio
        case "ttf", "otf":
            self = .font
        default:
            self = .other
        }
    }

    var icon: String {
        switch self {
        case .lua:   return "doc.text.fill"
        case .image: return "photo.fill"
        case .audio: return "waveform"
        case .font:  return "textformat"
        case .other: return "doc.fill"
        }
    }
}

// MARK: - ProjectItem

@Observable
final class ProjectItem: Identifiable {
    let id: UUID = UUID()
    let url: URL
    let name: String
    let isFolder: Bool
    let kind: FileKind
    var children: [ProjectItem]
    var isExpanded: Bool

    init(url: URL, isFolder: Bool, children: [ProjectItem] = []) {
        self.url = url
        self.name = url.lastPathComponent
        self.isFolder = isFolder
        self.kind = isFolder ? .other : FileKind(url: url)
        self.children = children
        self.isExpanded = false
    }
}

// MARK: - Project

@Observable
final class Project {
    let rootURL: URL
    let name: String
    var items: [ProjectItem] = []

    init(rootURL: URL) {
        self.rootURL = rootURL
        self.name = rootURL.lastPathComponent
    }

    func load() {
        // Pokusaj da resolvujes security-scoped bookmark ako postoji
        let accessURL = resolveStoredBookmark() ?? rootURL
        _ = accessURL.startAccessingSecurityScopedResource()
        items = Project.scan(url: accessURL)
        print("[Project] load() — \(items.count) items at \(accessURL.path)")
    }

    /// Cuva security-scoped bookmark za rootURL (poziva se kada URL ima aktivan scope).
    func saveBookmark() {
        guard let data = try? rootURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: "bookmark_\(rootURL.path.hashValue)")
    }

    private func resolveStoredBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "bookmark_\(rootURL.path.hashValue)")
        else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    func refresh() {
        _ = rootURL.startAccessingSecurityScopedResource()
        let expanded = collectExpandedPaths(from: items)
        items = Project.scan(url: rootURL)
        restoreExpandedPaths(expanded, in: items)
    }

    // Skupi URL-ove svih otvorenih foldera
    private func collectExpandedPaths(from items: [ProjectItem]) -> Set<String> {
        var paths = Set<String>()
        for item in items where item.isFolder {
            if item.isExpanded { paths.insert(item.url.path) }
            paths.formUnion(collectExpandedPaths(from: item.children))
        }
        return paths
    }

    // Vrati expanded state novim itemima na osnovu sacuvanih path-ova
    private func restoreExpandedPaths(_ paths: Set<String>, in items: [ProjectItem]) {
        for item in items where item.isFolder {
            if paths.contains(item.url.path) { item.isExpanded = true }
            restoreExpandedPaths(paths, in: item.children)
        }
    }

    func findItem(url: URL) -> ProjectItem? {
        findItem(url: url, in: items)
    }

    func findItem(id: UUID) -> ProjectItem? {
        findItem(id: id, in: items)
    }

    private func findItem(url: URL, in items: [ProjectItem]) -> ProjectItem? {
        for item in items {
            if item.url == url { return item }
            if item.isFolder, let found = findItem(url: url, in: item.children) { return found }
        }
        return nil
    }

    private func findItem(id: UUID, in items: [ProjectItem]) -> ProjectItem? {
        for item in items {
            if item.id == id { return item }
            if item.isFolder, let found = findItem(id: id, in: item.children) { return found }
        }
        return nil
    }

    // MARK: Scanner

    private static func scan(url: URL) -> [ProjectItem] {
        let fm = FileManager.default
        do {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            return contents
                .sorted { a, b in
                    let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if aIsDir != bIsDir { return aIsDir }
                    return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
                }
                .map { childURL in
                    let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDir {
                        return ProjectItem(url: childURL, isFolder: true, children: scan(url: childURL))
                    } else {
                        return ProjectItem(url: childURL, isFolder: false)
                    }
                }
        } catch {
            print("[Project] scan FAILED: \(error.localizedDescription)")
            return []
        }
    }
}
