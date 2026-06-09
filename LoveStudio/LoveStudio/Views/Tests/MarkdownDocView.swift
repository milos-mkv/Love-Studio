import SwiftUI

// MARK: - MarkdownDocView
//
// A read-only Markdown block renderer (§3.8) used for the bundled test-runner help
// doc AND the coverage report (the report is plain text wrapped in a code fence by
// the caller). No text buffer, no dirty state. Styled to match DocsView's look.
//
// Supported blocks: headings (#…######), paragraphs, fenced code (```), bullet
// lists (-/*), and horizontal rules (---). Inline `code` spans are rendered.

struct MarkdownDocView: View {
    @Environment(\.colorScheme) private var colorScheme
    let url: URL

    @State private var blocks: [Block] = []

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
            Text(block.text)
                .font(.system(size: headingSize(level), weight: .bold))
                .padding(.top, level <= 2 ? 8 : 2)
        case .paragraph:
            inlineText(block.text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•").font(.system(size: 13)).foregroundStyle(.secondary)
                inlineText(block.text).font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
        case .code:
            Text(block.text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(codeFill))
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    /// Render inline `code` spans within a line; everything else plain.
    private func inlineText(_ s: String) -> Text {
        var result = Text("")
        var rest = Substring(s)
        while let open = rest.firstIndex(of: "`") {
            result = result + Text(rest[..<open])
            let after = rest.index(after: open)
            if let close = rest[after...].firstIndex(of: "`") {
                let codeSpan = rest[after..<close]
                result = result + Text(codeSpan)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.accentColor)
                rest = rest[rest.index(after: close)...]
            } else {
                result = result + Text(rest[open...])
                rest = rest[rest.endIndex...]
            }
        }
        result = result + Text(rest)
        return result
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level { case 1: return 22; case 2: return 18; case 3: return 15; default: return 13 }
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
        enum Kind { case heading(Int), paragraph, bullet, code, rule }
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
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                out.append(Block(kind: .code, text: code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed == "---" {
                flushParagraph(); out.append(Block(kind: .rule, text: ""))
            } else if let level = headingLevel(trimmed) {
                flushParagraph()
                let text = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                out.append(Block(kind: .heading(level), text: text))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                out.append(Block(kind: .bullet, text: String(trimmed.dropFirst(2))))
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
}
