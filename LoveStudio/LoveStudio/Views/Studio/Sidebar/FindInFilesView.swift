import SwiftUI
import AppKit

// MARK: - Models

private struct FindResult: Identifiable {
    let id   = UUID()
    let url  : URL
    let line : Int
    let lineText: String
    var relativePath: String = ""
}

private struct FileGroup: Identifiable {
    let id      : String          // relative path
    let url     : URL
    let results : [FindResult]
}

// MARK: - View

struct FindInFilesView: View {
    let project      : Project
    var onJump       : ((URL, Int) -> Void)? = nil
    var focusTrigger : Int = 0              // increment externally to grab focus

    @State private var query       = ""
    @State private var matchCase   = false
    @State private var useRegex    = false
    @State private var luaOnly     = true
    @State private var isSearching = false
    @State private var groups      : [FileGroup] = []
    @State private var searchTask  : Task<Void, Never>?

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: query)        { _, _ in scheduleSearch() }
        .onChange(of: matchCase)    { _, _ in scheduleSearch() }
        .onChange(of: useRegex)     { _, _ in scheduleSearch() }
        .onChange(of: luaOnly)      { _, _ in scheduleSearch() }
        .onChange(of: focusTrigger) { _, _ in searchFocused = true }
    }

    // MARK: Header

    private var headerBar: some View {
        VStack(spacing: 6) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))

                TextField("Search in project…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                } else if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            // Options row
            HStack(spacing: 6) {
                TogglePill(label: "Aa",   icon: nil,              isOn: $matchCase, help: "Match case")
                TogglePill(label: ".*",   icon: nil,              isOn: $useRegex,  help: "Regular expression")
                TogglePill(label: ".lua", icon: nil,              isOn: $luaOnly,   help: "Lua files only")

                Spacer()

                if !groups.isEmpty {
                    let total = groups.reduce(0) { $0 + $1.results.count }
                    Text("\(total) in \(groups.count) file\(groups.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            placeholder("magnifyingglass", "Search in all project files")
        } else if groups.isEmpty && !isSearching {
            placeholder("doc.text.magnifyingglass", "No results for \"\(trimmed)\"")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
                    ForEach(groups) { group in
                        FileGroupSection(group: group, query: query,
                                         matchCase: matchCase, useRegex: useRegex) { result in
                            onJump?(result.url, result.line)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func placeholder(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let q  = query.trimmingCharacters(in: .whitespaces)
        let mc = matchCase
        let rx = useRegex
        let lo = luaOnly
        let root = project.rootURL

        guard !q.isEmpty else { groups = []; isSearching = false; return }

        isSearching = true
        groups = []

        searchTask = Task {
            // Collect all matching files via FileManager (doesn't depend on project tree state)
            let allFiles = collectFiles(in: root, luaOnly: lo)
            var found: [FileGroup] = []

            for fileURL in allFiles {
                guard !Task.isCancelled else { break }
                guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

                let lines   = content.components(separatedBy: .newlines)
                var results : [FindResult] = []

                for (idx, line) in lines.enumerated() {
                    guard !Task.isCancelled else { break }
                    if matches(line: line, query: q, matchCase: mc, useRegex: rx) {
                        let rel = relativePath(of: fileURL, root: root)
                        results.append(FindResult(url: fileURL, line: idx + 1,
                                                  lineText: line.trimmingCharacters(in: .whitespaces),
                                                  relativePath: rel))
                    }
                }

                if !results.isEmpty {
                    let rel = relativePath(of: fileURL, root: root)
                    found.append(FileGroup(id: rel, url: fileURL, results: results))
                }
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                groups      = found
                isSearching = false
            }
        }
    }

    // MARK: Helpers

    private func collectFiles(in root: URL, luaOnly: Bool) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            if luaOnly { return url.pathExtension.lowercased() == "lua" }
            let ext = url.pathExtension.lowercased()
            return ["lua", "txt", "md", "json", "toml", "ini", "cfg"].contains(ext)
        }
        .sorted { $0.path < $1.path }
    }

    private func matches(line: String, query: String, matchCase: Bool, useRegex: Bool) -> Bool {
        if useRegex {
            let opts: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
            guard let re = try? NSRegularExpression(pattern: query, options: opts) else { return false }
            return re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        let hay    = matchCase ? line  : line.lowercased()
        let needle = matchCase ? query : query.lowercased()
        return hay.contains(needle)
    }

    private func relativePath(of url: URL, root: URL) -> String {
        let full = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        if full.hasPrefix(base + "/") { return String(full.dropFirst(base.count + 1)) }
        return url.lastPathComponent
    }
}

// MARK: - Toggle pill

private struct TogglePill: View {
    let label : String
    let icon  : String?
    @Binding var isOn: Bool
    let help  : String

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 3) {
                if let icon { Image(systemName: icon).font(.system(size: 9)) }
                Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isOn ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
            )
            .overlay(Capsule().strokeBorder(isOn ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - File group section

private struct FileGroupSection: View {
    let group     : FileGroup
    let query     : String
    let matchCase : Bool
    let useRegex  : Bool
    let onSelect  : (FindResult) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // File header
            Button { withAnimation(.easeInOut(duration: 0.12)) { isExpanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)

                    Text(group.id)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(group.results.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(group.results) { result in
                        FindResultRow(result: result, query: query,
                                      matchCase: matchCase, useRegex: useRegex) {
                            onSelect(result)
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
    }
}

// MARK: - Single result row

private struct FindResultRow: View {
    let result    : FindResult
    let query     : String
    let matchCase : Bool
    let useRegex  : Bool
    let onTap     : () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 8) {
                Text("\(result.line)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()

                highlightedText
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var highlightedText: some View {
        let text  = result.lineText
        var attr  = AttributedString(text)

        // Apply highlight to all matches
        let hay    = matchCase ? text : text.lowercased()
        let needle = matchCase ? query : query.lowercased()

        if useRegex {
            let opts: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
            if let re = try? NSRegularExpression(pattern: query, options: opts) {
                let matches = re.matches(in: text, range: NSRange(text.startIndex..., in: text))
                for m in matches.reversed() {
                    if let r = Range(m.range, in: text),
                       let al = AttributedString.Index(r.lowerBound, within: attr),
                       let au = AttributedString.Index(r.upperBound, within: attr) {
                        attr[al..<au].backgroundColor = .init(Color.accentColor.opacity(0.35))
                        attr[al..<au].foregroundColor = .init(Color.primary)
                    }
                }
            }
        } else {
            var searchFrom = hay.startIndex
            while let range = hay.range(of: needle, range: searchFrom..<hay.endIndex) {
                if let al = AttributedString.Index(range.lowerBound, within: attr),
                   let au = AttributedString.Index(range.upperBound, within: attr) {
                    attr[al..<au].backgroundColor = .init(Color.accentColor.opacity(0.35))
                    attr[al..<au].foregroundColor = .init(Color.primary)
                }
                searchFrom = range.upperBound
            }
        }

        return Text(attr)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
    }
}
