import Foundation

struct Breakpoint: Identifiable, Equatable {
    let id = UUID()
    let file: String
    let line: Int
}

@Observable
final class BreakpointManager {
    private(set) var breakpoints: [String: Set<Int>] = [:]
    var onAdd: ((String, Int) -> Void)?
    var onRemove: ((String, Int) -> Void)?

    var all: [Breakpoint] {
        breakpoints.flatMap { file, lines in
            lines.sorted().map { Breakpoint(file: file, line: $0) }
        }.sorted {
            if $0.file != $1.file { return $0.file < $1.file }
            return $0.line < $1.line
        }
    }

    func toggle(file: String, line: Int) {
        if has(file: file, line: line) {
            remove(file: file, line: line)
        } else {
            set(file: file, line: line)
        }
    }

    func has(file: String, line: Int) -> Bool {
        breakpoints[file]?.contains(line) ?? false
    }

    func set(file: String, line: Int) {
        let inserted = breakpoints[file, default: []].insert(line).inserted
        if inserted { onAdd?(file, line) }
    }

    func remove(file: String, line: Int) {
        guard breakpoints[file]?.remove(line) != nil else { return }
        if breakpoints[file]?.isEmpty == true { breakpoints[file] = nil }
        onRemove?(file, line)
    }

    func clear() {
        let existing = breakpoints
        breakpoints = [:]
        for (file, lines) in existing {
            for line in lines { onRemove?(file, line) }
        }
    }

    func lines(for file: String) -> Set<Int> {
        breakpoints[file] ?? []
    }
}
