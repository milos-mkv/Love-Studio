import SwiftUI
import AppKit

// A read-only Markdown renderer for the test-runner help doc and the coverage
// report. Renders headings, paragraphs, bullet lists, fenced code (syntax-
// highlighted as Lua), tables, and horizontal rules, with inline bold/italic/code
// and links (jump-to-source and external URLs).

struct MarkdownDocView: View {
    @Environment(\.colorScheme) private var colorScheme
    let url: URL
    // Called when a lsjump:// link is tapped (file path, 1-based line).
    var onJump: ((String, Int) -> Void)?

    @State private var blocks: [Block] = []

    // A line split into plain-text and link segments (for tappable rendering).
    struct Segment: Identifiable {
        let id = UUID()
        let text: String
        let jump: (path: String, line: Int)?   // non-nil → jump-to-source link
        let url: URL?                           // non-nil → open-in-browser link
    }

    // Split a line into text and link segments, recognizing [label](target) where
    // target is a lsjump:// (jump to source) or http(s):// (open in browser) URL.
    // Bare <http(s)://…> autolinks are recognized too.
    private func segments(_ s: String) -> [Segment] {
        var out: [Segment] = []
        var rest = Substring(s)
        func emitPlain(_ t: Substring) {
            // within a plain run, pull out bare <http…> autolinks
            var seg = t
            while let lt = seg.range(of: "<http") {
                if let gt = seg.range(of: ">", range: lt.lowerBound..<seg.endIndex) {
                    let before = seg[..<lt.lowerBound]
                    if !before.isEmpty { out.append(Segment(text: String(before), jump: nil, url: nil)) }
                    let raw = String(seg[seg.index(after: lt.lowerBound)..<gt.lowerBound])
                    out.append(Segment(text: raw, jump: nil, url: URL(string: raw)))
                    seg = seg[gt.upperBound...]
                } else { break }
            }
            if !seg.isEmpty { out.append(Segment(text: String(seg), jump: nil, url: nil)) }
        }
        while let open = rest.range(of: "[") {
            let before = rest[..<open.lowerBound]
            guard let mid = rest.range(of: "](", range: open.upperBound..<rest.endIndex),
                  let close = rest.range(of: ")", range: mid.upperBound..<rest.endIndex) else {
                break
            }
            emitPlain(before)
            let label = String(rest[open.upperBound..<mid.lowerBound])
            let target = String(rest[mid.upperBound..<close.lowerBound])
            if let jump = parseJump(target) {
                out.append(Segment(text: label, jump: jump, url: nil))
            } else if target.hasPrefix("http"), let u = URL(string: target) {
                out.append(Segment(text: label, jump: nil, url: u))
            } else {
                out.append(Segment(text: label, jump: nil, url: nil))
            }
            rest = rest[close.upperBound...]
        }
        emitPlain(rest)
        return out
    }

    private func parseJump(_ target: String) -> (path: String, line: Int)? {
        guard target.hasPrefix("lsjump://") else { return nil }
        let body = String(target.dropFirst("lsjump://".count))
        let parts = body.split(separator: "#", maxSplits: 1)
        let path = parts.first.map { String($0).removingPercentEncoding ?? String($0) } ?? body
        let line = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
        return (path, line)
    }

    // Render a line's segments as a wrapping row with tappable links.
    @ViewBuilder
    private func segmentedLine(_ s: String, font: Font) -> some View {
        let segs = segments(s)
        if segs.contains(where: { $0.jump != nil || $0.url != nil }) {
            HStack(spacing: 0) {
                ForEach(segs) { seg in
                    if let j = seg.jump {
                        Button(seg.text) { onJump?(j.path, j.line) }
                            .buttonStyle(.plain).font(font)
                            .foregroundStyle(Color.accentColor)
                    } else if let u = seg.url {
                        Button(seg.text) { NSWorkspace.shared.open(u) }
                            .buttonStyle(.plain).font(font)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text(seg.text).font(font)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            inlineText(s).font(font)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in
                    view(for: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .onAppear(perform: load)
    }

    // MARK: Render

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block.kind {
        case .heading(let level):
            segmentedLine(block.text, font: .system(size: headingSize(level), weight: .bold))
                .padding(.top, level <= 2 ? 8 : 2)
        case .paragraph:
            segmentedLine(block.text, font: .system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•").font(.system(size: 13)).foregroundStyle(.secondary)
                segmentedLine(block.text, font: .system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
        case .code:
            Text(highlightedLua(block.text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(codeFill))
        case .mono:
            // Aligned table rows: a fixed-width monospace prefix (the columns / the
            // indent+mark) followed by the link. A single fixed character-cell width
            // per prefix keeps the link column aligned across all rows.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(block.text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    monoRow(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(codeFill))
        case .covTable:
            covTable(block.text)
        case .table:
            markdownTable(block.text)
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    // MARK: Markdown pipe table (real Grid; cells may contain links)

    @ViewBuilder
    private func markdownTable(_ text: String) -> some View {
        let rows = text.components(separatedBy: "\n").map { MarkdownDocView.tableCells($0) }
        let header = rows.first ?? []
        let body = Array(rows.dropFirst())
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                    Text(cell).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.leading)
                }
            }
            Divider().gridCellColumns(max(header.count, 1))
            ForEach(Array(body.enumerated()), id: \.offset) { _, cells in
                GridRow {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        segmentedLine(cell, font: .system(size: 13))
                            .gridColumnAlignment(.leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(codeFill))
    }

    // MARK: Coverage table (real Grid — columns + rows align by construction)

    private struct CovRow: Identifiable {
        let id = UUID()
        let isFile: Bool
        let cover: String      // "100.0%" for file rows; "" for function rows
        let lines: String      // "6/6"  for file rows;     "" for function rows
        let mark: String       // "" for file rows; "✓"/"✗" for function rows
        let label: String      // filename or function name (column 4)
        let path: String
        let line: Int
    }

    private func parseCovRows(_ text: String) -> [CovRow] {
        var rows: [CovRow] = []
        for raw in text.components(separatedBy: "\n") {
            let f = raw.components(separatedBy: "|")
            if f.first == "F", f.count >= 6 {
                // F | pct | hit | total | relname | abspath
                rows.append(CovRow(isFile: true,
                                   cover: String(format: "%@%%", f[1]),
                                   lines: "\(f[2])/\(f[3])",
                                   mark: "", label: f[4], path: f[5], line: 1))
            } else if f.first == "M", f.count >= 5 {
                // M | covered(1/0) | name | abspath | line
                rows.append(CovRow(isFile: false,
                                   cover: "", lines: "",
                                   mark: f[1] == "1" ? "✓" : "✗",
                                   label: f[2], path: f[3], line: Int(f[4]) ?? 1))
            }
        }
        return rows
    }

    @ViewBuilder
    private func covTable(_ text: String) -> some View {
        let rows = parseCovRows(text)
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("COVER").gridColumnAlignment(.leading)
                Text("LINES")
                HStack { Text("FILE"); Spacer() }   // FILE column eats the slack
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Divider().gridCellColumns(3)
            ForEach(rows) { r in
                GridRow {
                    Text(r.cover).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(coverColor(r))
                        .gridColumnAlignment(.leading)
                    Text(r.lines).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if !r.isFile {
                            Text(r.mark).font(.system(size: 11))
                                .foregroundStyle(r.mark == "✓" ? .green : .red)
                                .padding(.leading, 14)
                        }
                        Button(r.label) { onJump?(r.path, r.line) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                        Spacer(minLength: 0)   // pin content left, claim remaining width
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(codeFill))
    }

    private func coverColor(_ r: CovRow) -> Color {
        guard r.isFile, let v = Double(r.cover.dropLast()) else { return .secondary }
        return v >= 80 ? .green : (v >= 50 ? .orange : .red)
    }

    // One monospaced table row: a fixed-width prefix plus an optional link. The
    // fixed per-character cell width keeps the link column aligned across rows.
    @ViewBuilder
    private func monoRow(_ line: String) -> some View {
        let monoFont = Font.system(size: 12, design: .monospaced)
        let cell: CGFloat = 7.25   // ~advance of SF Mono at 12pt
        let segs = segments(line)
        if let linkIdx = segs.firstIndex(where: { $0.jump != nil }) {
            // everything before the first link = the aligned prefix (columns/indent)
            let prefix = segs[..<linkIdx].map(\.text).joined()
            let link = segs[linkIdx]
            HStack(spacing: 0) {
                Text(prefix)
                    .font(monoFont)
                    .frame(width: CGFloat(prefix.count) * cell, alignment: .leading)
                if let j = link.jump {
                    Button(link.text) { onJump?(j.path, j.line) }
                        .buttonStyle(.plain).font(monoFont).foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
            }
        } else {
            Text(line).font(monoFont).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Render inline markdown (bold, italic, code) via AttributedString; falls back
    // to plain text on a parse failure.
    private func inlineText(_ s: String) -> Text {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if var attr = try? AttributedString(markdown: s, options: opts) {
            // tint inline-code runs to match the rest of the doc
            for run in attr.runs where run.inlinePresentationIntent == .code {
                attr[run.range].foregroundColor = .accentColor
            }
            return Text(attr)
        }
        return Text(s)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return 22; case 2: return 18; case 3: return 15; default: return 13 }
    }

    // Syntax-highlight a fenced code block as Lua, reusing the editor's highlighter.
    private func highlightedLua(_ code: String) -> AttributedString {
        let theme: LuaTheme = (colorScheme == .light) ? .light : .dark
        let ns = NSMutableAttributedString(string: code)
        let full = NSRange(location: 0, length: (code as NSString).length)
        ns.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: theme.text,
        ], range: full)
        for (range, color) in LuaSyntaxHighlighter().computeAttributes(for: code, theme: theme) {
            ns.addAttribute(.foregroundColor, value: color, range: range)
        }
        return (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(code)
    }

    private var codeFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.05)
                             : Color(nsColor: .controlBackgroundColor).opacity(0.92)
    }

    // MARK: Parse

    private func load() {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            blocks = [Block(kind: .paragraph, text: "Could not load document.")]
            return
        }
        blocks = MarkdownDocView.parse(raw)
    }

    struct Block: Identifiable {
        let id = UUID()
        // `.mono` = monospaced lines that may contain links (aligned table rows).
        // `.table` = a standard markdown pipe table (rows joined by "\n").
        enum Kind { case heading(Int), paragraph, bullet, code, mono, covTable, table, rule }
        let kind: Kind
        let text: String
    }

    static func parse(_ raw: String) -> [Block] {
        var out: [Block] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                out.append(Block(kind: .paragraph, text: paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let kind: Block.Kind =
                    trimmed.hasPrefix("```cov-table") ? .covTable :
                    trimmed.hasPrefix("```mono")      ? .mono : .code
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                out.append(Block(kind: kind, text: code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed == "---" {
                flushParagraph(); out.append(Block(kind: .rule, text: ""))
            } else if let level = headingLevel(trimmed) {
                flushParagraph()
                let text = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                out.append(Block(kind: .heading(level), text: text))
            } else if trimmed.hasPrefix("|"),
                      i + 1 < lines.count,
                      isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                // Markdown pipe table: header row, separator (|---|---|), then body.
                flushParagraph()
                var rows: [String] = [trimmed]      // header
                i += 2                              // skip header + separator
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("|") else { break }
                    rows.append(t); i += 1
                }
                out.append(Block(kind: .table, text: rows.joined(separator: "\n")))
                continue                            // i already advanced
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                // Absorb wrapped/continuation lines (a bullet's text may span several
                // source lines) until a blank line or the next block starts.
                var parts = [String(trimmed.dropFirst(2))]
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty || t == "---" || t.hasPrefix("```")
                        || t.hasPrefix("- ") || t.hasPrefix("* ")
                        || t.hasPrefix("|") || headingLevel(t) != nil { break }
                    parts.append(t); i += 1
                }
                out.append(Block(kind: .bullet, text: parts.joined(separator: " ")))
                continue                            // i already advanced
            } else {
                paragraph.append(trimmed)
            }
            i += 1
        }
        flushParagraph()
        return out
    }

    private static func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes <= 6, line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    // A markdown table separator row (e.g. |---|:--|--:|): only |, -, :, spaces.
    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.hasPrefix("|"), line.contains("-") else { return false }
        return line.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    // Split a "| a | b |" row into trimmed cell strings.
    static func tableCells(_ row: String) -> [String] {
        var r = row.trimmingCharacters(in: .whitespaces)
        if r.hasPrefix("|") { r.removeFirst() }
        if r.hasSuffix("|") { r.removeLast() }
        return r.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
