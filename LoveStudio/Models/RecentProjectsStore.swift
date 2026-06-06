import Foundation

struct RecentProjectEntry: Identifiable, Codable {
    let id: UUID
    let url: URL
    let name: String
    let openedAt: Date

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.openedAt = Date()
    }
}

@Observable
final class RecentProjectsStore {

    static let shared = RecentProjectsStore()

    private(set) var projects: [RecentProjectEntry] = []

    private let key = "recentProjects"
    private let maxCount = 10

    private init() {
        load()
    }

    func add(url: URL) {
        // Remove duplicate if exists
        projects.removeAll { $0.url == url }

        let entry = RecentProjectEntry(url: url)
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
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([RecentProjectEntry].self, from: data)
        else { return }

        // Filter out projects whose folders no longer exist
        projects = decoded.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }
}
