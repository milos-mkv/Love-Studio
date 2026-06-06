import Foundation

// MARK: - FileWatcher
//
// Watches a directory tree recursively using DispatchSourceFileSystemObject.
// One source per directory - new sub-directories are picked up automatically
// because we re-scan on every change event.
//
// Usage:
//   let watcher = FileWatcher(url: projectRoot) { watcher.stop() /* already handled */ }
//   watcher.onChange = { project.refresh() }
//   watcher.start()
//   // later:
//   watcher.stop()

final class FileWatcher {

    /// Called on the main queue after a debounce whenever the watched tree changes.
    var onChange: (() -> Void)?

    private let root: URL
    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var debounceWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "dev.lovestudio.filewatcher", qos: .utility)

    // How long to wait after the last FS event before firing onChange.
    // 300 ms is enough to batch rapid saves / code-gen writes.
    private let debounceInterval: TimeInterval = 0.3

    init(url: URL) {
        self.root = url
    }

    deinit { stop() }

    // MARK: - Start / Stop

    func start() {
        watchDirectory(root)
    }

    func stop() {
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
        debounceWork?.cancel()
    }

    // MARK: - Internal

    private func watchDirectory(_ url: URL) {
        guard sources[url] == nil else { return }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .link],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleChange(at: url)
        }

        source.setCancelHandler {
            close(fd)
        }

        sources[url] = source
        source.resume()

        // Also watch all existing sub-directories
        scanSubdirectories(of: url)
    }

    private func scanSubdirectories(of url: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let childURL as URL in enumerator {
            let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { watchDirectory(childURL) }
        }
    }

    private func handleChange(at url: URL) {
        // Re-scan for any new sub-directories that appeared
        scanSubdirectories(of: url)

        // Debounce - cancel previous pending fire, schedule a new one
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
