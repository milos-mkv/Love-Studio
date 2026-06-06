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
}
