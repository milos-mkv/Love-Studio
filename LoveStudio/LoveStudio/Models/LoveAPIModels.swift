import Foundation

// MARK: - Root

struct LoveAPI: Codable {
    let version: String
    let modules: [LoveModule]
    let callbacks: [LoveFunction]
}

// MARK: - Module

struct LoveModule: Codable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let functions: [LoveFunction]
}

// MARK: - Function

struct LoveFunction: Codable, Identifiable {
    var id: String { signature }
    let name: String
    let signature: String
    let description: String
    let parameters: [LoveParam]
    let returns: [LoveParam]
}

// MARK: - Parameter / Return

struct LoveParam: Codable {
    let name: String
    let type: String
    let description: String
}

// MARK: - Loader

enum LoveAPILoader {
    static let api: LoveAPI = {
        guard let url = Bundle.main.url(forResource: "love_api", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let api = try? JSONDecoder().decode(LoveAPI.self, from: data)
        else {
            return LoveAPI(version: "?", modules: [], callbacks: [])
        }
        return api
    }()

    // Full function name (e.g. "love.graphics.draw") -> its definition, for the
    // static hover fallback used when the language server isn't running.
    private static let functionsByName: [String: LoveFunction] = {
        var map: [String: LoveFunction] = [:]
        for module in api.modules {
            for fn in module.functions {
                map["love.\(module.name).\(fn.name)"] = fn
            }
        }
        for cb in api.callbacks { map["love.\(cb.name)"] = cb }
        return map
    }()

    // Markdown docs for a `love.*` symbol, or nil if unknown. Mirrors the shape
    // of lua-language-server hover output (fenced signature + prose + params).
    static func hoverMarkdown(for name: String) -> String? {
        guard let fn = functionsByName[name] else { return nil }
        var md = "```lua\n\(fn.signature)\n```\n\n\(fn.description)"
        if !fn.parameters.isEmpty {
            md += "\n"
            for p in fn.parameters {
                md += "\n@param `\(p.name)` *\(p.type)* — \(p.description)"
            }
        }
        if !fn.returns.isEmpty {
            md += "\n"
            for r in fn.returns {
                md += "\n@return *\(r.type)* — \(r.description)"
            }
        }
        return md
    }
}
