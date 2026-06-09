import Foundation
import Observation

// MARK: - CoverageStore
//
// Per-file, per-line coverage from the last run (§ coverage gutters). Populated
// from `[[LS_COVLINES]]` lines; read by the editor's gutter to color lines
// covered (green) / uncovered (red). Keyed by absolute file path.

@Observable
final class CoverageStore {
    struct FileCoverage {
        var hit: Set<Int> = []
        var miss: Set<Int> = []
    }

    private(set) var byFile: [String: FileCoverage] = [:]

    /// True while there is coverage data to display (gates gutter rendering).
    var hasData: Bool { !byFile.isEmpty }

    func clear() { byFile = [:] }

    func set(file: String, hit: Set<Int>, miss: Set<Int>) {
        byFile[normalize(file)] = FileCoverage(hit: hit, miss: miss)
    }

    /// Coverage for a file, looked up by absolute path (normalized).
    func coverage(forPath path: String) -> FileCoverage? {
        byFile[normalize(path)]
    }

    private func normalize(_ p: String) -> String {
        URL(fileURLWithPath: p).standardizedFileURL.path
    }
}
