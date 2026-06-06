import Foundation

enum LuaKeywordCompletions {

    struct Completion {
        let label: String
        let insert: String
    }

    static func completions(for prefix: String) -> [Completion] {
        guard prefix.count >= 2 else { return [] }
        return all.filter { $0.label.hasPrefix(prefix) }
    }

    private static let all: [Completion] = keywords + stdlib + tableLib + stringLib + mathLib + ioLib

    private static let keywords: [Completion] = [
        "and","break","do","else","elseif","end","false","for","function",
        "goto","if","in","local","nil","not","or","repeat","return",
        "then","true","until","while"
    ].map { Completion(label: $0, insert: $0) }

    private static let stdlib: [Completion] = [
        "assert","collectgarbage","dofile","error","getmetatable",
        "ipairs","load","loadfile","next","pairs",
        "pcall","print","rawequal","rawget","rawlen","rawset",
        "require","select","setmetatable","tonumber","tostring",
        "type","unpack","xpcall"
    ].map { Completion(label: $0, insert: "\($0)()") }

    private static let tableLib: [Completion] = [
        "table.insert","table.remove","table.sort",
        "table.concat","table.unpack","table.move","table.pack"
    ].map { Completion(label: $0, insert: "\($0)()") }

    private static let stringLib: [Completion] = [
        "string.byte","string.char","string.dump","string.find",
        "string.format","string.gmatch","string.gsub","string.len",
        "string.lower","string.match","string.rep","string.reverse",
        "string.sub","string.upper"
    ].map { Completion(label: $0, insert: "\($0)()") }

    private static let mathLib: [Completion] = [
        "math.abs","math.ceil","math.cos","math.deg","math.exp",
        "math.floor","math.fmod","math.huge","math.log","math.max",
        "math.min","math.modf","math.pi","math.rad","math.random",
        "math.randomseed","math.sin","math.sqrt","math.tan","math.type"
    ].map { c in
        let isConst = c == "math.huge" || c == "math.pi"
        return Completion(label: c, insert: isConst ? c : "\(c)()")
    }

    private static let ioLib: [Completion] = [
        "io.close","io.flush","io.input","io.lines",
        "io.open","io.output","io.read","io.tmpfile","io.type","io.write"
    ].map { Completion(label: $0, insert: "\($0)()") }
}
