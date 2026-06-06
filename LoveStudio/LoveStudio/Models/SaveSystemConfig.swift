import Foundation

// MARK: - Save Field Type

enum SaveFieldType: String, Codable, CaseIterable, Identifiable {
    case number  = "number"
    case string  = "string"
    case boolean = "boolean"
    case table   = "table"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .number:  return "Number"
        case .string:  return "String"
        case .boolean: return "Boolean"
        case .table:   return "Table"
        }
    }

    var icon: String {
        switch self {
        case .number:  return "number"
        case .string:  return "text.alignleft"
        case .boolean: return "switch.2"
        case .table:   return "list.bullet"
        }
    }

    var defaultPlaceholder: String {
        switch self {
        case .number:  return "0"
        case .string:  return "\"\""
        case .boolean: return "false"
        case .table:   return "{}"
        }
    }
}

// MARK: - Save Field

struct SaveField: Codable, Identifiable, Equatable {
    var id:           UUID          = UUID()
    /// Lua key used in Save.data
    var name:         String        = "score"
    var type:         SaveFieldType = .number
    /// Default value as a Lua literal string
    var defaultValue: String        = "0"
    /// Optional description shown as a comment in generated code
    var description:  String        = ""
}

// MARK: - Save System Config

struct SaveSystemConfig: Codable, Equatable, Identifiable {
    var id:         UUID        = UUID()
    var moduleName: String      = "Save"
    /// Filename written to love.filesystem (without extension)
    var fileName:   String      = "savegame"
    var fields:     [SaveField] = []
}
