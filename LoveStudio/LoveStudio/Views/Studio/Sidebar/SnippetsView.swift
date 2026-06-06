import SwiftUI
import AppKit

// MARK: - Model

struct LoveSnippet: Identifiable, Decodable, Hashable {
    let id          : String
    let title       : String
    let category    : String
    let description : String
    let code        : String
    let tags        : [String]
}

// MARK: - Library

private final class SnippetLibrary {
    static let shared = SnippetLibrary()

    let snippets   : [LoveSnippet]
    let categories : [String]

    private init() {
        if let url  = Bundle.main.url(forResource: "snippets", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([LoveSnippet].self, from: data) {
            self.snippets = list.sorted {
                $0.category == $1.category
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending
            }
        } else {
            self.snippets = []
        }
        self.categories = Array(Set(self.snippets.map(\.category)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// MARK: - View

struct SnippetsView: View {

    var onInsert: ((String) -> Void)? = nil

    @AppStorage("snippets.favorites") private var favoritesRaw: String = ""
    @AppStorage("snippets.recent")    private var recentRaw:    String = ""

    @State private var searchText         = ""
    @State private var selectedCategory   = "all"
    @State private var selectedSnippetID  : String? = nil
    @State private var copiedID           : String? = nil

    private let lib = SnippetLibrary.shared

    private var favoriteIDs : [String] { favoritesRaw.isEmpty ? [] : favoritesRaw.components(separatedBy: ",") }
    private var recentIDs   : [String] { recentRaw.isEmpty    ? [] : recentRaw.components(separatedBy: ",") }

    private var categories: [String] {
        ["favorites", "recent", "all"] + lib.categories
    }

    private var filteredSnippets: [LoveSnippet] {
        let base = snippets(for: selectedCategory)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            [$0.title, $0.category, $0.description, $0.code, $0.tags.joined(separator: " ")]
                .joined(separator: "\n").lowercased().contains(q)
        }
    }

    private var selectedSnippet: LoveSnippet? {
        if let id = selectedSnippetID, let s = filteredSnippets.first(where: { $0.id == id }) { return s }
        return filteredSnippets.first
    }

    var body: some View {
        HStack(spacing: 0) {
            categoriesColumn.frame(width: 160)
            Divider()
            snippetsColumn.frame(width: 240)
            Divider()
            previewColumn.frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncSelection() }
        .onChange(of: selectedCategory) { _, _ in syncSelection() }
        .onChange(of: searchText)       { _, _ in syncSelection() }
    }

    // MARK: - Categories Column

    private var categoriesColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Categories")
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(categories, id: \.self) { cat in
                        let isSelected = selectedCategory == cat
                        Button { selectedCategory = cat } label: {
                            HStack(spacing: 6) {
                                Text(categoryLabel(cat))
                                    .font(.system(size: 11))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                Spacer(minLength: 0)
                                Text("\(count(for: cat))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(isSelected ? .primary : .tertiary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(
                                        isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06)
                                    ))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Snippets Column

    private var snippetsColumn: some View {
        VStack(spacing: 0) {
            columnHeader("Snippets")

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
                TextField("Search…", text: $searchText).textFieldStyle(.plain).font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary).font(.system(size: 11))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
            .padding(8)

            Divider()

            if filteredSnippets.isEmpty {
                Text("No snippets").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredSnippets) { snippet in
                            let isSelected = selectedSnippet?.id == snippet.id
                            Button { selectedSnippetID = snippet.id } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(snippet.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        HStack(spacing: 5) {
                                            Text(snippet.category.capitalized)
                                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                                            if isFavorite(snippet.id) {
                                                Image(systemName: "heart.fill")
                                                    .font(.system(size: 9)).foregroundStyle(.pink)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    // MARK: - Preview Column

    private var previewColumn: some View {
        VStack(spacing: 0) {
            // Header with actions
            HStack(spacing: 8) {
                columnHeader("Preview")
                Spacer()
                if let snippet = selectedSnippet {
                    Button { toggleFavorite(snippet.id) } label: {
                        Image(systemName: isFavorite(snippet.id) ? "heart.fill" : "heart")
                            .font(.system(size: 12))
                            .foregroundStyle(isFavorite(snippet.id) ? .pink : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite(snippet.id) ? "Remove from favorites" : "Add to favorites")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(snippet.code, forType: .string)
                        recordRecent(snippet.id)
                        copiedID = snippet.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedID == snippet.id { copiedID = nil }
                        }
                    } label: {
                        Label(copiedID == snippet.id ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(copiedID == snippet.id ? .green : .primary)
                    }
                    .buttonStyle(.bordered)

                    if let onInsert {
                        Button {
                            onInsert(snippet.code)
                            recordRecent(snippet.id)
                        } label: {
                            Label("Insert", systemImage: "plus.app.fill").font(.system(size: 11))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.trailing, 10)

            Divider()

            if let snippet = selectedSnippet {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Title + category badge
                        HStack(alignment: .center, spacing: 8) {
                            Text(snippet.title).font(.headline)
                            Text(snippet.category.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }

                        Text(snippet.description)
                            .font(.caption).foregroundStyle(.secondary)

                        if !snippet.tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(snippet.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 999).fill(Color.primary.opacity(0.07)))
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Code").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                Spacer()
                                Text("\(snippet.code.components(separatedBy: .newlines).count) lines")
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                SnippetCodeView(code: snippet.code)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(NSColor.textBackgroundColor).opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("Select a snippet").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryLabel(_ cat: String) -> String {
        switch cat {
        case "favorites": return "Favorites"
        case "recent":    return "Recent"
        case "all":       return "All"
        default:          return cat.capitalized
        }
    }

    private func snippets(for cat: String) -> [LoveSnippet] {
        switch cat {
        case "favorites": return favoriteIDs.compactMap { id in lib.snippets.first { $0.id == id } }
        case "recent":    return recentIDs.compactMap   { id in lib.snippets.first { $0.id == id } }
        case "all":       return lib.snippets
        default:          return lib.snippets.filter { $0.category == cat }
        }
    }

    private func count(for cat: String) -> Int { snippets(for: cat).count }

    private func isFavorite(_ id: String) -> Bool { favoriteIDs.contains(id) }

    private func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.insert(id, at: 0) }
        favoritesRaw = ids.joined(separator: ",")
    }

    private func recordRecent(_ id: String) {
        var ids = recentIDs.filter { $0 != id }
        ids.insert(id, at: 0)
        recentRaw = ids.prefix(20).joined(separator: ",")
    }

    private func syncSelection() {
        if let id = selectedSnippetID, filteredSnippets.contains(where: { $0.id == id }) { return }
        selectedSnippetID = filteredSnippets.first?.id
    }
}

// MARK: - Syntax-highlighted code view

private struct SnippetCodeView: View {
    let code: String

    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    @State private var attributed: AttributedString = AttributedString()

    private var theme: LuaTheme {
        switch appAppearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return colorScheme == .light ? .light : .dark
        }
    }

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: code + appAppearance) { attributed = build() }
            .onChange(of: colorScheme) { _, _ in attributed = build() }
    }

    private func build() -> AttributedString {
        let highlighter = LuaSyntaxHighlighter()
        let ns = NSMutableAttributedString(string: code)
        let full = NSRange(location: 0, length: (code as NSString).length)
        ns.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: theme.text
        ], range: full)
        for (range, color) in highlighter.computeAttributes(for: code, theme: theme) {
            ns.addAttribute(.foregroundColor, value: color, range: range)
        }
        return (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(code)
    }
}
