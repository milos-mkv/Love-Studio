import Foundation

struct RecentProjectEntry: Identifiable, Codable {
    let id: UUID
    let name: String
    let path: String          // samo za prikaz, nije za pristup
    let bookmarkData: Data    // security-scoped bookmark za stvarni pristup

    var url: URL? {
        resolveBookmark()
    }

    init?(url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }

        self.id           = UUID()
        self.name         = url.lastPathComponent
        self.path         = url.path
        self.bookmarkData = bookmark
    }

    /// Resolvuje bookmark nazad u URL i pocinje security-scoped access.
    /// Vraca URL samo ako folder i dalje postoji i bookmark je validan.
    func resolveBookmark() -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Bookmark je zastareo ali mozda je jos uvek dostupan
            print("[RecentProjectsStore] Stale bookmark for \(name)")
        }

        return resolved
    }

    /// Pocinje security-scoped access i vraca URL.
    /// Pozivalac je odgovoran da pozove stopAccessingSecurityScopedResource() kada zavrsi.
    func accessURL() -> URL? {
        guard let url = resolveBookmark() else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}

// MARK: - RecentProjectsStore

@Observable
final class RecentProjectsStore {

    static let shared = RecentProjectsStore()

    private(set) var projects: [RecentProjectEntry] = []

    private let key      = "recentProjects_v2"
    private let maxCount = 10

    private init() {
        load()
    }

    func add(url: URL) {
        // Ukloni duplikat po path-u
        projects.removeAll { $0.path == url.path }

        guard let entry = RecentProjectEntry(url: url) else {
            print("[RecentProjectsStore] Failed to create bookmark for \(url.path)")
            return
        }

        projects.insert(entry, at: 0)

        if projects.count > maxCount {
            projects = Array(projects.prefix(maxCount))
        }

        save()
    }

    func remove(id: UUID) {
        projects.removeAll { $0.id == id }
        save()
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        guard
            let data    = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([RecentProjectEntry].self, from: data)
        else { return }

        // Zadrzavamo sve — korisnik ce videti gresku ako folder ne postoji
        projects = decoded
    }
}
