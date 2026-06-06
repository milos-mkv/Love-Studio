import SwiftUI

// MARK: - DocsView

struct DocsView: View {
    private let api = LoveAPILoader.api
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText        = ""
    @State private var selectedModule:   String?       = nil
    @State private var selectedFunction: LoveFunction? = nil

    private var moduleNames: [String] { api.modules.map(\.name) }

    private var totalFunctionCount: Int {
        api.modules.reduce(api.callbacks.count) { $0 + $1.functions.count }
    }

    private var currentFunctions: [LoveFunction] {
        let base: [LoveFunction]
        if let mod = selectedModule {
            base = api.modules.first(where: { $0.name == mod })?.functions ?? []
        } else {
            base = api.callbacks
        }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private var allSearchResults: [(module: String, fn: LoveFunction)] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        var results: [(String, LoveFunction)] = []
        for mod in api.modules {
            for fn in mod.functions where fn.name.lowercased().contains(q) || fn.description.lowercased().contains(q) {
                results.append((mod.name, fn))
            }
        }
        for fn in api.callbacks where fn.name.lowercased().contains(q) || fn.description.lowercased().contains(q) {
            results.append(("callbacks", fn))
        }
        return results
    }

    private var currentModuleName:  String { selectedModule ?? "callbacks" }
    private var currentModuleLabel: String { selectedModule.map { "love.\($0)" } ?? "Callbacks" }
    private var fullPrefix:         String { selectedModule.map { "love.\($0)." } ?? "love." }

    var body: some View {
        VStack(spacing: 0) {
            docsHeader
            Divider()
            if searchText.isEmpty { normalLayout } else { searchLayout }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: Header

    private var docsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.36, green: 0.78, blue: 1.0))
                Text("LÖVE Docs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    DocsMetaBadge(text: "v\(api.version)",              tint: .blue)
                    DocsMetaBadge(text: "\(moduleNames.count + 1) groups", tint: .teal)
                    DocsMetaBadge(text: "\(totalFunctionCount) funcs",   tint: .orange)
                }
            }

            Text("API reference and callback overview directly in the sidebar.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .semibold))
                TextField("Search functions, callbacks, or descriptions…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    DocsMetaBadge(text: "\(allSearchResults.count)", tint: .accentColor)
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(searchFieldBackground))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(searchFieldBorder, lineWidth: 1) }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
        .background(.bar)
    }

    private var searchFieldBackground: Color {
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.62)
            : Color(nsColor: .textBackgroundColor).opacity(0.98)
    }
    private var searchFieldBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color(nsColor: .separatorColor).opacity(0.68)
    }

    // MARK: Normal Layout

    private var normalLayout: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ModuleChip(
                        label: "Callbacks",
                        icon: moduleStyle(for: "callbacks").icon,
                        color: moduleStyle(for: "callbacks").color,
                        isSelected: selectedModule == nil
                    ) { selectedModule = nil; selectedFunction = nil }

                    ForEach(moduleNames, id: \.self) { name in
                        let style = moduleStyle(for: name)
                        ModuleChip(label: name, icon: style.icon, color: style.color, isSelected: selectedModule == name) {
                            selectedModule = name; selectedFunction = nil
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 10)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))

            Divider()

            DocsSectionHero(
                title: currentModuleLabel,
                subtitle: "\(currentFunctions.count) available item(s)",
                icon: moduleStyle(for: currentModuleName).icon,
                tint: moduleStyle(for: currentModuleName).color
            )
            .padding(.horizontal, 12).padding(.top, 12)

            functionList(currentFunctions, prefix: fullPrefix, module: currentModuleName)
        }
    }

    // MARK: Search Layout

    private var searchLayout: some View {
        let results = allSearchResults
        return VStack(spacing: 0) {
            DocsSectionHero(
                title: "Search Results",
                subtitle: results.isEmpty
                    ? "No matches for \"\(searchText)\""
                    : "\(results.count) match(es) for \"\(searchText)\"",
                icon: "sparkle.magnifyingglass",
                tint: .accentColor
            )
            .padding(.horizontal, 12).padding(.top, 12)

            if results.isEmpty {
                DocsEmptyState(icon: "magnifyingglass", title: "No results", subtitle: "Try a shorter query or search by module/function name.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results, id: \.fn.id) { item in
                            DocsRow(
                                fn: item.fn,
                                prefix: item.module == "callbacks" ? "love." : "love.\(item.module).",
                                moduleName: item.module,
                                isSelected: selectedFunction?.id == item.fn.id
                            ) { selectedFunction = item.fn }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                }
                .sheet(item: $selectedFunction) { fn in
                    FunctionDetailView(fn: fn, prefix: selectedPrefix(for: fn))
                }
            }
        }
    }

    private func functionList(_ fns: [LoveFunction], prefix: String, module: String) -> some View {
        Group {
            if fns.isEmpty {
                DocsEmptyState(icon: "doc.text.magnifyingglass", title: "No functions", subtitle: "There are no items in this section right now.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(fns) { fn in
                            DocsRow(fn: fn, prefix: prefix, moduleName: module, isSelected: selectedFunction?.id == fn.id) {
                                selectedFunction = fn
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                }
                .sheet(item: $selectedFunction) { fn in
                    FunctionDetailView(fn: fn, prefix: prefix)
                }
            }
        }
    }

    private func selectedPrefix(for function: LoveFunction) -> String {
        for module in api.modules where module.functions.contains(where: { $0.id == function.id }) {
            return "love.\(module.name)."
        }
        return "love."
    }

    private func moduleStyle(for module: String) -> (icon: String, color: Color) {
        switch module {
        case "callbacks":  return ("arrow.triangle.2.circlepath", .orange)
        case "graphics":   return ("paintbrush.fill",             .pink)
        case "audio":      return ("waveform",                    .teal)
        case "filesystem": return ("folder.fill",                 .yellow)
        case "keyboard":   return ("keyboard.fill",               .blue)
        case "mouse":      return ("cursorarrow",                 .indigo)
        case "math":       return ("function",                    .green)
        case "timer":      return ("timer",                       .orange)
        case "window":     return ("macwindow",                   .gray)
        case "physics":    return ("bolt.fill",                   .purple)
        case "system":     return ("cpu",                         .brown)
        case "event":      return ("arrow.left.arrow.right",      .cyan)
        case "joystick":   return ("gamecontroller.fill",         .red)
        case "touch":      return ("hand.point.up.left.fill",     .mint)
        case "video":      return ("video.fill",                  .secondary)
        default:           return ("square.grid.2x2",             .accentColor)
        }
    }
}

// MARK: - DocsMetaBadge

private struct DocsMetaBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint.opacity(0.95))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay { Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 1) }
    }
}

// MARK: - DocsSectionHero

private struct DocsSectionHero: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.18))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cardFill))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cardBorder, lineWidth: 1) }
    }

    private var cardFill:   Color { colorScheme == .dark ? Color.white.opacity(0.04) : Color(nsColor: .controlBackgroundColor) }
    private var cardBorder: Color { colorScheme == .dark ? Color.white.opacity(0.06) : Color(nsColor: .separatorColor).opacity(0.62) }
}

// MARK: - DocsEmptyState

private struct DocsEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }
}

// MARK: - ModuleChip

private struct ModuleChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let label:      String
    let icon:       String
    let color:      Color
    let isSelected: Bool
    let action:     () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? color : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(isSelected ? color.opacity(0.17) : unselectedFill))
            .overlay { Capsule().strokeBorder(isSelected ? color.opacity(0.38) : unselectedBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private var unselectedFill:   Color { colorScheme == .dark ? Color.white.opacity(0.04) : Color(nsColor: .controlBackgroundColor) }
    private var unselectedBorder: Color { colorScheme == .dark ? Color.white.opacity(0.06) : Color(nsColor: .separatorColor).opacity(0.60) }
}

// MARK: - DocsRow

private struct DocsRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let fn:         LoveFunction
    let prefix:     String
    let moduleName: String
    let isSelected: Bool
    let action:     () -> Void

    @State private var isHovering = false

    private var style: (icon: String, color: Color) {
        switch moduleName {
        case "callbacks":  return ("arrow.triangle.2.circlepath", .orange)
        case "graphics":   return ("paintbrush.fill",             .pink)
        case "audio":      return ("waveform",                    .teal)
        case "filesystem": return ("folder.fill",                 .yellow)
        case "keyboard":   return ("keyboard.fill",               .blue)
        case "mouse":      return ("cursorarrow",                 .indigo)
        case "math":       return ("function",                    .green)
        case "timer":      return ("timer",                       .orange)
        case "window":     return ("macwindow",                   .gray)
        case "physics":    return ("bolt.fill",                   .purple)
        case "system":     return ("cpu",                         .brown)
        case "event":      return ("arrow.left.arrow.right",      .cyan)
        case "joystick":   return ("gamecontroller.fill",         .red)
        case "touch":      return ("hand.point.up.left.fill",     .mint)
        case "video":      return ("video.fill",                  .secondary)
        default:           return ("square.grid.2x2",             .accentColor)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.color.opacity(0.15))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: style.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(style.color)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(prefix)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11, design: .monospaced))
                        Text(fn.name)
                            .foregroundStyle(.primary)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    Text(fn.description)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 6) {
                        TinyInfoBadge(text: moduleName == "callbacks" ? "callback" : moduleName, tint: style.color)
                        if !fn.parameters.isEmpty { TinyInfoBadge(text: "\(fn.parameters.count) param", tint: .secondary) }
                        if !fn.returns.isEmpty    { TinyInfoBadge(text: "\(fn.returns.count) return",   tint: .secondary) }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovering ? hoverFill : baseFill))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.30) : baseBorder, lineWidth: 1)
            }
    }

    private var baseFill:  Color { colorScheme == .dark ? Color.white.opacity(0.03) : Color(nsColor: .controlBackgroundColor).opacity(0.98) }
    private var hoverFill: Color { colorScheme == .dark ? Color.white.opacity(0.05) : Color(nsColor: .controlBackgroundColor) }
    private var baseBorder: Color { colorScheme == .dark ? Color.white.opacity(0.05) : Color(nsColor: .separatorColor).opacity(0.58) }
}

// MARK: - TinyInfoBadge

private struct TinyInfoBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint == .secondary ? Color.secondary : tint.opacity(0.92))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(tint == .secondary ? neutralFill : tint.opacity(0.13)))
    }

    private var neutralFill: Color { colorScheme == .dark ? Color.white.opacity(0.06) : Color(nsColor: .separatorColor).opacity(0.14) }
}

// MARK: - FunctionDetailView

struct FunctionDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let fn:     LoveFunction
    let prefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        Text(prefix)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14, design: .monospaced))
                        Text(fn.name)
                            .foregroundStyle(.primary)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    HStack(spacing: 6) {
                        DocsMetaBadge(text: "LÖVE \(LoveAPILoader.api.version)", tint: .blue)
                        DocsMetaBadge(text: "\(fn.parameters.count) params",     tint: .teal)
                        DocsMetaBadge(text: "\(fn.returns.count) returns",        tint: .orange)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DetailSection(title: "Signature", icon: "signature") {
                        Text(fn.signature)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(signatureFill))
                    }

                    DetailSection(title: "Description", icon: "text.alignleft") {
                        Text(fn.description).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }

                    if !fn.parameters.isEmpty {
                        DetailSection(title: "Parameters", icon: "arrow.right.circle") {
                            VStack(spacing: 8) {
                                ForEach(fn.parameters, id: \.name) { ParamRow(param: $0) }
                            }
                        }
                    }

                    if !fn.returns.isEmpty {
                        DetailSection(title: "Returns", icon: "arrow.left.circle") {
                            VStack(spacing: 8) {
                                ForEach(fn.returns, id: \.name) { ParamRow(param: $0) }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 520)
    }

    private var signatureFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color(nsColor: .controlBackgroundColor).opacity(0.92)
    }
}

// MARK: - DetailSection

private struct DetailSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon:  String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(sectionFill))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(sectionBorder, lineWidth: 1) }
    }

    private var sectionFill:   Color { colorScheme == .dark ? Color.white.opacity(0.035) : Color(nsColor: .controlBackgroundColor).opacity(0.98) }
    private var sectionBorder: Color { colorScheme == .dark ? Color.white.opacity(0.05)  : Color(nsColor: .separatorColor).opacity(0.60) }
}

// MARK: - ParamRow

private struct ParamRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let param: LoveParam

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(param.name).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(param.type)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
            .frame(width: 120, alignment: .leading)

            Text(param.description).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(rowFill))
    }

    private var rowFill: Color { colorScheme == .dark ? Color.white.opacity(0.04) : Color(nsColor: .controlBackgroundColor).opacity(0.98) }
}
