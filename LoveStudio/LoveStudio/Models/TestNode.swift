import Foundation
import SwiftUI

// MARK: - TestStatus

enum TestStatus: String {
    case notRun
    case running
    case passed
    case failed     // a clean assertion didn't hold
    case error      // the test threw / crashed (distinct from `failed`)
    case skipped
    case cancelled  // user-initiated Stop (not timeout)

    // SF Symbol shown in the Explorer row.
    var iconName: String {
        switch self {
        case .passed:    return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .error:     return "exclamationmark.triangle.fill"
        case .notRun:    return "circle"
        case .running:   return "circle.dotted"          // row may show a spinner instead
        case .skipped:   return "minus.circle"
        case .cancelled: return "slash.circle"
        }
    }

    var tint: Color {
        switch self {
        case .passed:            return .green
        case .failed:            return .red
        case .error:             return .orange
        case .running:           return .accentColor
        case .notRun, .skipped, .cancelled:
            return .secondary
        }
    }

    // Severity order for suite aggregation (a parent rolls up its worst child):
    // error > failed > running > notRun > skipped/cancelled > passed.
    var severity: Int {
        switch self {
        case .error:     return 5
        case .failed:    return 4
        case .running:   return 3
        case .notRun:    return 2
        case .cancelled: return 1
        case .skipped:   return 1
        case .passed:    return 0
        }
    }
}

// MARK: - TestKind

enum TestKind {
    case suite   // a `describe` block
    case test    // a leaf `it`
}

// MARK: - TestNode

// A node in the Test Explorer tree: leaves are tests, suites group children. `id`
// is the stable path-based identifier the Lua facade emits (e.g.
// "combat.test.lua > Damage > applies armor"); results correlate by id, not name.
@Observable
final class TestNode: Identifiable {
    let id: String
    let name: String
    let kind: TestKind

    var file: String?
    var line: Int?

    var children: [TestNode]
    var isExpanded: Bool

    // Result fields (filled by a run; meaningful for `.test` leaves).
    var status: TestStatus
    var durationMs: Int?
    var message: String?      // failure / error detail, shown on expand

    init(id: String,
         name: String,
         kind: TestKind,
         file: String? = nil,
         line: Int? = nil,
         children: [TestNode] = [],
         status: TestStatus = .notRun) {
        self.id = id
        self.name = name
        self.kind = kind
        self.file = file
        self.line = line
        self.children = children
        self.isExpanded = false
        self.status = status
        self.durationMs = nil
        self.message = nil
    }

    // MARK: Aggregation

    // For a suite, the rolled-up status of its descendants (worst child wins);
    // for a leaf, just its own status.
    var effectiveStatus: TestStatus {
        guard kind == .suite, !children.isEmpty else { return status }
        var worst = TestStatus.passed
        for child in children {
            let s = child.effectiveStatus
            if s.severity > worst.severity { worst = s }
        }
        return worst
    }

    // A failed/errored leaf is expandable to reveal its message.
    var hasDetail: Bool {
        kind == .test && (status == .failed || status == .error) && (message?.isEmpty == false)
    }

    // MARK: Counts (for the suite "(passed/total)" badge)

    var testCount: Int {
        kind == .test ? 1 : children.reduce(0) { $0 + $1.testCount }
    }

    var passedCount: Int {
        if kind == .test { return status == .passed ? 1 : 0 }
        return children.reduce(0) { $0 + $1.passedCount }
    }

    // MARK: Lookup

    func find(id: String) -> TestNode? {
        if self.id == id { return self }
        for child in children {
            if let found = child.find(id: id) { return found }
        }
        return nil
    }

    // Reset this subtree's leaves to .notRun before a run.
    func resetResults() {
        if kind == .test {
            status = .notRun
            durationMs = nil
            message = nil
        }
        for child in children { child.resetResults() }
    }
}

// MARK: - Run summary

struct TestRunSummary {
    var passed = 0
    var failed = 0
    var error = 0
    var skipped = 0
    var totalMs = 0
    var coveragePercent: Double?   // nil unless coverage was enabled

    var total: Int { passed + failed + error + skipped }
}
