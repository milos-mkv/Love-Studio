import Foundation

// User-configurable per-diagnostic severity overrides for the Lua language
// server. Persisted as JSON in UserDefaults; written into each project's
// .luarc.json (Lua.diagnostics.severity / .disable) by TemplateService.
enum DiagnosticSeverityLevel: String, CaseIterable, Identifiable {
    case error = "Error"
    case warning = "Warning"
    case hint = "Hint"
    case none = "None"   // disables the diagnostic entirely

    var id: String { rawValue }
    var label: String { self == .none ? "Off" : rawValue }
}

// A diagnostic code and the group it belongs to, for the settings UI.
struct DiagnosticCode: Identifiable {
    let id: String        // e.g. "duplicate-set-field"
    let group: String     // e.g. "duplicate"
    var name: String { id }
}

enum DiagnosticCatalog {
    // The full lua-language-server diagnostic set, grouped (luals.github.io/wiki/diagnostics).
    static let all: [DiagnosticCode] = {
        let groups: [String: [String]] = [
            "ambiguity": ["ambiguity-1", "count-down-loop", "different-requires", "newfield-call", "newline-call"],
            "await": ["await-in-sync", "not-yieldable"],
            "codestyle": ["codestyle-check", "name-style-check", "spell-check"],
            "conventions": ["global-element"],
            "duplicate": ["duplicate-index", "duplicate-set-field"],
            "global": ["global-in-nil-env", "lowercase-global", "undefined-env-child", "undefined-global"],
            "luadoc": ["circle-doc-class", "doc-field-no-class", "duplicate-doc-alias", "duplicate-doc-field",
                       "duplicate-doc-param", "incomplete-signature-doc", "missing-global-doc",
                       "missing-local-export-doc", "undefined-doc-class", "undefined-doc-name",
                       "undefined-doc-param", "unknown-cast-variable", "unknown-diag-code", "unknown-operator"],
            "redefined": ["redefined-local"],
            "strict": ["close-non-object", "deprecated", "discard-returns", "invisible"],
            "strong": ["no-unknown"],
            "type-check": ["assign-type-mismatch", "cast-local-type", "cast-type-mismatch", "inject-field",
                           "need-check-nil", "param-type-mismatch", "return-type-mismatch", "undefined-field"],
            "unbalanced": ["missing-fields", "missing-parameter", "missing-return", "missing-return-value",
                           "redundant-parameter", "redundant-return-value", "redundant-value", "unbalanced-assignments"],
            "unused": ["code-after-break", "empty-block", "redundant-return", "trailing-space",
                       "unreachable-code", "unused-function", "unused-label", "unused-local", "unused-vararg"],
        ]
        return groups.keys.sorted().flatMap { group in
            groups[group]!.sorted().map { DiagnosticCode(id: $0, group: group) }
        }
    }()

    static var groupNames: [String] {
        Array(Set(all.map(\.group))).sorted()
    }
}

// Persisted overrides. Only non-default entries are stored.
enum DiagnosticSeverityStore {
    static let defaultsKey = "editorDiagnosticSeverities"

    // The app's own default overrides (applied unless the user changes them):
    // duplicate-set-field is downgraded to Hint because LÖVE callbacks legitimately
    // "redefine" library-declared callbacks.
    static let appDefaults: [String: DiagnosticSeverityLevel] = [
        "duplicate-set-field": .hint,
    ]

    static func load() -> [String: DiagnosticSeverityLevel] {
        guard let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] else {
            return appDefaults
        }
        var map: [String: DiagnosticSeverityLevel] = [:]
        for (k, v) in raw { if let lvl = DiagnosticSeverityLevel(rawValue: v) { map[k] = lvl } }
        return map.isEmpty ? appDefaults : map
    }

    static func save(_ map: [String: DiagnosticSeverityLevel]) {
        let raw = map.mapValues { $0.rawValue }
        UserDefaults.standard.set(raw, forKey: defaultsKey)
    }
}
