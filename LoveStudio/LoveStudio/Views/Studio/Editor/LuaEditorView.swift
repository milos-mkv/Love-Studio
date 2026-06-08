import SwiftUI
import AppKit

// MARK: - Notification Names

extension Notification.Name {
    static let insertSnippet     = Notification.Name("LoveStudio.insertSnippet")
    static let editorSearchAction = Notification.Name("LoveStudio.editorSearchAction")
    // Posted by Settings' "Restart Language Server" button; observed by StudioView.
    static let restartLanguageServer = Notification.Name("LoveStudio.restartLanguageServer")
    // Posted when diagnostic-severity overrides change; StudioView rewrites .luarc.json.
    static let diagnosticSeveritiesChanged = Notification.Name("LoveStudio.diagnosticSeveritiesChanged")
}

// MARK: - LuaEditorView (NSViewRepresentable)

struct LuaEditorView: NSViewRepresentable {
    @Binding var text: String
    var onSave: (() -> Void)?
    var theme: LuaTheme = .dark
    var fileURL: URL? = nil
    var fontSize: CGFloat = 13
    var fontName: String = ""
    var showLineNumbers    = true
    var showMinimap        = true
    var tabWidth           = 4
    var highlightCurrentLine = true
    var autoCloseBraces    = true
    var wordWrap           = false
    var autoFocus          = true
    var onFontSizeChange: ((CGFloat) -> Void)?
    // Debounced full-text push for LSP didChange (Lua tabs only; nil otherwise).
    var onTextChange: ((String) -> Void)?
    // When set and the server is active, language features route through LSP;
    // otherwise the static LoveAPI tables are used.
    var lspClient    : LSPClientService? = nil
    var lspDocumentURL: URL? = nil
    var docHoverEnabled = true
    var diagnostics  : [LSPClientService.Diagnostic] = []
    // Reports the caret's 1-based (line, column) for the status bar.
    var onCursorChange: ((Int, Int) -> Void)? = nil
    var jumpToLine   : Binding<Int?> = .constant(nil)
    var breakpoints  : BreakpointManager? = nil
    var pausedLine   : Int? = nil
    var currentFile  : String = ""

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = LuaTextView(frame: .zero)
        textView.editorFontSize = fontSize
        textView.editorFontName = fontName
        textView.showsLineNumbers = showLineNumbers
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
        textView.configure(scrollView: scrollView)
        textView.theme = theme
        textView.delegate = context.coordinator
        textView.onSave = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSave?()
        }
        textView.onFontSizeChange = { [weak coordinator = context.coordinator] size in
            coordinator?.parent.onFontSizeChange?(size)
        }
        textView.isEditable = true
        textView.boundFileURL = fileURL

        scrollView.documentView = textView
        context.coordinator.textView = textView
        textView.loadText(text)

        // Minimap
        let minimap = MinimapView()
        minimap.translatesAutoresizingMaskIntoConstraints = false
        minimap.theme = theme
        context.coordinator.minimapView = minimap

        container.addSubview(scrollView)
        container.addSubview(minimap)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: minimap.leadingAnchor),

            minimap.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            minimap.topAnchor.constraint(equalTo: container.topAnchor),
            minimap.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            minimap.widthAnchor.constraint(equalToConstant: MinimapView.width),
        ])

        // Sync scroll → minimap
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        // Minimap click → scroll editor
        minimap.onScrollFraction = { [weak scrollView, weak textView] fraction in
            guard let sv = scrollView, let tv = textView else { return }
            let docH = tv.frame.height
            let clipH = sv.contentView.bounds.height
            let maxScroll = max(docH - clipH, 0)
            sv.contentView.scroll(to: NSPoint(x: 0, y: fraction * maxScroll))
            sv.reflectScrolledClipView(sv.contentView)
        }

        context.coordinator.scrollView = scrollView

        if autoFocus {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.theme.background != theme.background {
            textView.theme = theme
        }
        if let minimap = context.coordinator.minimapView, minimap.theme.background != theme.background {
            minimap.theme = theme
        }
        if textView.editorFontSize != fontSize {
            textView.editorFontSize = fontSize
        }
        if textView.editorFontName != fontName {
            textView.editorFontName = fontName
        }
        if textView.showsLineNumbers != showLineNumbers {
            textView.showsLineNumbers = showLineNumbers
        }
        if let minimap = context.coordinator.minimapView {
            minimap.isHidden = !showMinimap
        }
        if textView.editorTabWidth != tabWidth {
            textView.editorTabWidth = tabWidth
        }
        if textView.highlightCurrentLine != highlightCurrentLine {
            textView.highlightCurrentLine = highlightCurrentLine
        }
        if textView.autoCloseBraces != autoCloseBraces {
            textView.autoCloseBraces = autoCloseBraces
        }
        textView.textContainer?.widthTracksTextView = !wordWrap
        if wordWrap {
            textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
        } else {
            textView.isHorizontallyResizable = true
        }

        textView.boundFileURL = fileURL

        guard !context.coordinator.isEditing else { return }
        let effectiveString = textView.isFoldingActive ? textView.realText : textView.string
        if effectiveString != text {
            context.coordinator.isEditing = true
            textView.loadText(text)
            context.coordinator.isEditing = false
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.lineNumberRuler?.needsDisplay = true
        }
        context.coordinator.refreshMinimap()

        // Breakpoints & paused line
        textView.pausedLine = pausedLine
        textView.lineNumberRuler?.breakpoints = breakpoints
        textView.lineNumberRuler?.currentFile = currentFile

        // LSP hover: give the text view the client + doc URL for mouse-rest hover.
        textView.lspClient = lspClient
        textView.lspDocumentURL = lspDocumentURL
        textView.docHoverEnabled = docHoverEnabled

        // LSP diagnostics: squiggles + gutter markers (highest severity per line).
        textView.diagnostics = diagnostics
        var gutter: [Int: LSPClientService.DiagnosticSeverity] = [:]
        for d in diagnostics {
            let line = d.startLine + 1   // realText 0-based -> gutter 1-based
            if let existing = gutter[line], existing.rawValue <= d.severity.rawValue { continue }
            gutter[line] = d.severity
        }
        textView.lineNumberRuler?.diagnosticLines = gutter

        if let line = jumpToLine.wrappedValue {
            jumpToLine.wrappedValue = nil
            DispatchQueue.main.async {
                textView.scrollToLine(line)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, parent: self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var parent: LuaEditorView
        weak var textView: LuaTextView?
        weak var scrollView: NSScrollView?
        weak var minimapView: MinimapView?
        var isEditing = false
        private var bracketHighlightRanges: [NSRange] = []
        private var completionWorkItem: DispatchWorkItem?
        private var previousTextLength = 0
        private var minimapWorkItem: DispatchWorkItem?
        private var didChangeWorkItem: DispatchWorkItem?
        private var cachedMinimapSource: String = ""
        private var cachedMinimapLines: [NSAttributedString] = []
        private var lastHighlightedLineRect: NSRect = .zero

        init(text: Binding<String>, parent: LuaEditorView) {
            self.text = text
            self.parent = parent
            super.init()
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        // MARK: Minimap sync

        @objc func scrollDidChange(_ notification: Notification) {
            refreshMinimap()
            HoverPanel.shared.dismiss()
        }

        func scheduleMinimapRefresh() {
            minimapWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refreshMinimap() }
            minimapWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }

        // Debounced LSP didChange — sibling of the minimap refresh (GCD, no async).
        // No-op when onTextChange is nil (non-Lua tabs / LSP off).
        func scheduleDidChange(_ text: String) {
            guard parent.onTextChange != nil else { return }
            didChangeWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.parent.onTextChange?(text) }
            didChangeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }

        func refreshMinimap() {
            guard let sv = scrollView, let tv = textView, let minimap = minimapView else { return }
            let source = tv.isFoldingActive ? tv.realText : tv.string

            // Rebuild attributed lines only when source has changed
            if source != cachedMinimapSource {
                cachedMinimapSource = source
                let theme = tv.theme
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self else { return }
                    let colorAttrs = tv.isJsonFile
                        ? tv.jsonHighlighter.computeAttributes(for: source, theme: theme)
                        : LuaSyntaxHighlighter().computeAttributes(for: source, theme: theme)
                    let full = NSMutableAttributedString(string: source)
                    let fullRange = NSRange(location: 0, length: full.length)
                    full.addAttribute(.foregroundColor, value: theme.lineNumber, range: fullRange)
                    for (range, color) in colorAttrs {
                        if range.location + range.length <= full.length {
                            full.addAttribute(.foregroundColor, value: color, range: range)
                        }
                    }
                    var attrLines: [NSAttributedString] = []
                    (source as NSString).enumerateSubstrings(
                        in: NSRange(location: 0, length: (source as NSString).length),
                        options: .byLines
                    ) { _, range, _, _ in
                        guard range.location + range.length <= full.length else { return }
                        attrLines.append(full.attributedSubstring(from: range))
                    }
                    DispatchQueue.main.async { [weak self, weak minimap] in
                        guard let self else { return }
                        self.cachedMinimapLines = attrLines
                        minimap?.lines = attrLines
                    }
                }
            } else {
                minimap.lines = cachedMinimapLines
            }
            let docH  = tv.frame.height
            let clipH = sv.contentView.bounds.height
            let scrollY = sv.contentView.bounds.origin.y
            let maxScroll = max(docH - clipH, 0)
            minimap.visibleFraction = clipH / max(docH, 1)
            minimap.scrollFraction  = maxScroll > 0 ? scrollY / maxScroll : 0
        }

        // MARK: Bracket matching

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let lm = tv.layoutManager else { return }
            reportCursorPosition(tv)
            // Invalidate previous and current line so the highlight moves cleanly
            if let lm = tv.layoutManager, lm.numberOfGlyphs > 0 {
                let sel = tv.selectedRange()
                let caretGlyph = min(lm.glyphIndexForCharacter(at: min(sel.location, tv.string.utf16.count)),
                                     max(0, lm.numberOfGlyphs - 1))
                var fr = NSRange()
                let lineRect = lm.lineFragmentRect(forGlyphAt: caretGlyph, effectiveRange: &fr)
                let inset = tv.textContainerInset.height

                let newDirty = NSRect(x: tv.bounds.minX,
                                     y: lineRect.minY + inset - 2,
                                     width: tv.bounds.width,
                                     height: lineRect.height + 4)

                // Also redraw the previously highlighted line to clear it
                if lastHighlightedLineRect != .zero {
                    let oldDirty = NSRect(x: tv.bounds.minX,
                                         y: lastHighlightedLineRect.minY + inset - 2,
                                         width: tv.bounds.width,
                                         height: lastHighlightedLineRect.height + 4)
                    tv.setNeedsDisplay(oldDirty)
                }
                tv.setNeedsDisplay(newDirty)
                lastHighlightedLineRect = lineRect
            } else {
                tv.setNeedsDisplay(tv.visibleRect)
            }
            for r in bracketHighlightRanges { lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r) }
            bracketHighlightRanges = []
            let str = tv.string as NSString
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return }
            for checkPos in [sel.location, sel.location - 1] {
                guard checkPos >= 0 && checkPos < str.length else { continue }
                let ch = str.character(at: checkPos)
                guard let (open, close, forward) = bracketPair(for: ch) else { continue }
                guard let matchPos = findMatchingBracket(str: str, at: checkPos,
                                                          open: open, close: close, forward: forward) else { break }
                let r1 = NSRange(location: checkPos, length: 1)
                let r2 = NSRange(location: matchPos, length: 1)
                let color = NSColor.systemYellow.withAlphaComponent(0.40)
                lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: r1)
                lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: r2)
                bracketHighlightRanges = [r1, r2]
                break
            }
        }

        private func bracketPair(for ch: unichar) -> (open: unichar, close: unichar, forward: Bool)? {
            switch ch {
            case 40:  return (40, 41, true)
            case 41:  return (40, 41, false)
            case 91:  return (91, 93, true)
            case 93:  return (91, 93, false)
            case 123: return (123, 125, true)
            case 125: return (123, 125, false)
            default:  return nil
            }
        }

        private func findMatchingBracket(str: NSString, at pos: Int,
                                          open: unichar, close: unichar, forward: Bool) -> Int? {
            var depth = 1
            var i = forward ? pos + 1 : pos - 1
            while i >= 0 && i < str.length {
                let ch = str.character(at: i)
                if ch == (forward ? open : close)  { depth += 1 }
                if ch == (forward ? close : open)  { depth -= 1 }
                if depth == 0 { return i }
                i += forward ? 1 : -1
            }
            return nil
        }

        func textDidChange(_ notification: Notification) {
            guard !isEditing, let tv = notification.object as? NSTextView else { return }
            isEditing = true
            let realText = (tv as? LuaTextView)?.realText ?? tv.string
            text.wrappedValue = realText
            isEditing = false
            scheduleMinimapRefresh()
            scheduleDidChange(realText)
            HoverPanel.shared.dismiss()

            let newLength = tv.string.utf16.count
            let isInsertion = newLength > previousTextLength
            previousTextLength = newLength

            if isInsertion {
                triggerCompletion(for: tv)
            } else {
                completionWorkItem?.cancel()
                CompletionPanel.shared.dismiss()
            }

            triggerSignatureHint(for: tv)
        }

        // Reports the caret's 1-based (line, column) in realText space.
        private func reportCursorPosition(_ tv: NSTextView) {
            guard let onCursor = parent.onCursorChange else { return }
            let ltv = tv as? LuaTextView
            let bufLoc = tv.selectedRange().location
            let realLoc = ltv?.realLocation(forBufferLocation: bufLoc) ?? bufLoc
            let text = (ltv?.realText ?? tv.string) as NSString
            let loc = min(realLoc, text.length)
            var line = 1
            var lineStart = 0
            text.enumerateSubstrings(in: NSRange(location: 0, length: loc),
                                     options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
                line += 1
                lineStart = enclosing.location + enclosing.length
            }
            onCursor(line, loc - lineStart + 1)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if CompletionPanel.shared.isVisible {
                switch selector {
                case #selector(NSResponder.moveUp(_:)):
                    CompletionPanel.shared.moveSelection(by: -1)
                    return true
                case #selector(NSResponder.moveDown(_:)):
                    CompletionPanel.shared.moveSelection(by: 1)
                    return true
                case #selector(NSResponder.insertTab(_:)),
                     #selector(NSResponder.insertNewline(_:)):
                    CompletionPanel.shared.acceptCurrentSelection()
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    CompletionPanel.shared.dismiss()
                    return true
                case #selector(NSResponder.deleteBackward(_:)),
                     #selector(NSResponder.deleteForward(_:)):
                    completionWorkItem?.cancel()
                    CompletionPanel.shared.dismiss()
                    return false
                default:
                    break
                }
            }

            if selector == #selector(NSResponder.insertNewline(_:)) {
                return handleSmartNewline(in: textView)
            }
            return false
        }

        // MARK: Auto-indent

        private func handleSmartNewline(in tv: NSTextView) -> Bool {
            let str = tv.string as NSString
            let sel = tv.selectedRange()
            let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
            let currentLine = str.substring(with: lineRange)
            var indent = ""
            for ch in currentLine {
                if ch == " " || ch == "\t" { indent.append(ch) } else { break }
            }
            let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let indentOpeners = ["then", "do", "else", "elseif", "repeat"]
            let addsIndent = indentOpeners.contains(where: { trimmed.hasSuffix($0) })
                || trimmed.hasPrefix("function ")
                || trimmed.contains(" function ")
            let newIndent = addsIndent ? indent + "    " : indent
            tv.insertText("\n" + newIndent, replacementRange: sel)
            return true
        }

        // MARK: Completion trigger

        private func triggerCompletion(for tv: NSTextView) {
            completionWorkItem?.cancel()

            let sel = tv.selectedRange()
            guard sel.location > 0 else { CompletionPanel.shared.dismiss(); return }
            let str      = tv.string as NSString
            let lastChar = str.character(at: sel.location - 1)
            guard isIdentChar(lastChar) || lastChar == 46 else {
                CompletionPanel.shared.dismiss(); return
            }

            var start = sel.location
            while start > 0 {
                let c = str.character(at: start - 1)
                if isIdentChar(c) || c == 46 { start -= 1 } else { break }
            }
            let prefixLen = sel.location - start
            guard prefixLen >= 2 else { CompletionPanel.shared.dismiss(); return }

            let prefix = str.substring(with: NSRange(location: start, length: prefixLen))
            let insertStart = start

            // LSP path: ask the server, fall back to static tables on empty.
            if lspActive {
                let work = DispatchWorkItem { [weak self, weak tv] in
                    guard let self, let tv, let url = self.parent.lspDocumentURL else { return }
                    let pos = self.lspPosition(for: sel.location, in: tv)
                    self.parent.lspClient?.requestCompletion(url, line: pos.line, character: pos.character) { [weak self, weak tv] results in
                        guard let self, let tv else { return }
                        if results.isEmpty {
                            self.showStaticCompletion(prefix: prefix, insertStart: insertStart, sel: sel, tv: tv)
                            return
                        }
                        let suggestions = results.map { CompletionSuggestion(label: $0.label, insert: $0.insertText) }
                        self.presentCompletion(suggestions, prefix: prefix, insertStart: insertStart, sel: sel, tv: tv)
                    }
                }
                completionWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
                return
            }

            // Static path (LSP off / inactive).
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                self.showStaticCompletion(prefix: prefix, insertStart: insertStart, sel: sel, tv: tv)
            }
            completionWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        // Build suggestions from the static LoveAPI/keyword tables and present them.
        private func showStaticCompletion(prefix: String, insertStart: Int, sel: NSRange, tv: NSTextView) {
            var suggestions: [CompletionSuggestion] = []
            let word = prefix.components(separatedBy: ".").last ?? prefix

            suggestions += LuaKeywordCompletions.completions(for: word)
                .map { CompletionSuggestion(label: $0.label, insert: $0.insert) }

            if prefix.lowercased().hasPrefix("love") {
                suggestions += LoveAPICompletions.completions(for: prefix)
                    .map { label in
                        let ins = label.components(separatedBy: ".").count >= 3 ? "\(label)()" : label
                        return CompletionSuggestion(label: label, insert: ins)
                    }
            }

            var seen = Set<String>()
            suggestions = suggestions.filter { seen.insert($0.label).inserted }

            let isExact = suggestions.contains(where: { $0.label == prefix || $0.insert == prefix })
            guard !suggestions.isEmpty && !isExact else {
                CompletionPanel.shared.dismiss(); return
            }
            presentCompletion(suggestions, prefix: prefix, insertStart: insertStart, sel: sel, tv: tv)
        }

        // Show/update the panel with the given suggestions (shared by both paths).
        private func presentCompletion(_ suggestions: [CompletionSuggestion],
                                       prefix: String, insertStart: Int, sel: NSRange, tv: NSTextView) {
            guard !suggestions.isEmpty else { CompletionPanel.shared.dismiss(); return }
            let cursorScreenRect = tv.firstRect(forCharacterRange: sel, actualRange: nil)

            CompletionPanel.shared.onAccept = { [weak tv] suggestion in
                guard let tv else { return }
                let end   = tv.selectedRange().location
                let range = NSRange(location: insertStart, length: max(0, end - insertStart))
                tv.insertText(suggestion.insert, replacementRange: range)
            }
            CompletionPanel.shared.onDismiss = nil

            if CompletionPanel.shared.isVisible {
                CompletionPanel.shared.update(completions: suggestions)
            } else {
                CompletionPanel.shared.show(completions: suggestions, cursorScreenRect: cursorScreenRect)
            }
        }

        private func isIdentChar(_ c: unichar) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
        }

        // MARK: LSP routing helpers

        // True when an active Lua server should handle language features for this tab.
        private var lspActive: Bool {
            guard let client = parent.lspClient, parent.lspDocumentURL != nil else { return false }
            return client.status == .active
        }

        // Selection location -> 0-based LSP (line, char) in realText space.
        private func lspPosition(for bufferLocation: Int, in tv: NSTextView) -> (line: Int, character: Int) {
            let ltv = tv as? LuaTextView
            let text = ltv?.realText ?? tv.string
            let ns = text as NSString
            let realLoc = ltv?.realLocation(forBufferLocation: bufferLocation) ?? bufferLocation
            let loc = min(realLoc, ns.length)
            // Count newlines strictly before loc -> correct 0-based line.
            var line = 0
            var lineStart = 0
            var i = 0
            while i < loc {
                if ns.character(at: i) == 10 { line += 1; lineStart = i + 1 }
                i += 1
            }
            return (line, loc - lineStart)
        }

        // MARK: Signature hint

        private func triggerSignatureHint(for tv: NSTextView) {
            let sel = tv.selectedRange()
            guard sel.location > 0 else { SignatureHintPanel.shared.dismiss(); return }

            // LSP path: let the server compute the active signature + parameter.
            if lspActive, let url = parent.lspDocumentURL {
                let pos = lspPosition(for: sel.location, in: tv)
                parent.lspClient?.requestSignatureHelp(url, line: pos.line, character: pos.character) { [weak self, weak tv] sig in
                    guard let self, let tv else { return }
                    guard let sig else { self.triggerSignatureHintStatic(for: tv); return }
                    let cursorRect = tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)
                    SignatureHintPanel.shared.show(signature: sig.label,
                                                   activeParam: sig.activeParameter,
                                                   cursorScreenRect: cursorRect)
                }
                return
            }

            triggerSignatureHintStatic(for: tv)
        }

        private func triggerSignatureHintStatic(for tv: NSTextView) {
            let sel = tv.selectedRange()
            guard sel.location > 0 else { SignatureHintPanel.shared.dismiss(); return }
            let str = tv.string as NSString

            // Walk backwards from cursor to find the innermost unclosed '('
            var depth = 0
            var commaCount = 0
            var i = sel.location - 1
            var foundOpenParen = false
            var openParenPos = -1
            while i >= 0 {
                let ch = str.character(at: i)
                if ch == 41 { // )
                    depth += 1
                } else if ch == 40 { // (
                    if depth == 0 {
                        foundOpenParen = true
                        openParenPos = i
                        break
                    }
                    depth -= 1
                } else if ch == 44 && depth == 0 { // ,
                    commaCount += 1
                } else if ch == 10 { // newline - don't cross lines
                    break
                }
                i -= 1
            }

            guard foundOpenParen && openParenPos > 0 else {
                SignatureHintPanel.shared.dismiss(); return
            }

            // Extract the function name before '('
            let nameEnd = openParenPos
            var nameStart = nameEnd - 1
            // Walk back over ident chars and dots (for love.graphics.draw etc.)
            while nameStart > 0 {
                let c = str.character(at: nameStart - 1)
                if isIdentChar(c) || c == 46 { nameStart -= 1 } else { break }
            }
            let funcName = str.substring(with: NSRange(location: nameStart, length: nameEnd - nameStart))
            guard !funcName.isEmpty, let sigInfo = LoveAPISignatures.signature(for: funcName) else {
                SignatureHintPanel.shared.dismiss(); return
            }

            let cursorRect = tv.firstRect(forCharacterRange: sel, actualRange: nil)
            SignatureHintPanel.shared.show(
                signature: sigInfo.full,
                activeParam: commaCount,
                cursorScreenRect: cursorRect
            )
        }
    }
}

// MARK: - LuaTheme

struct LuaTheme {
    let background: NSColor
    let text: NSColor
    let keyword: NSColor
    let string: NSColor
    let comment: NSColor
    let number: NSColor
    let functionName: NSColor
    let love: NSColor
    let stdlib: NSColor
    let method: NSColor
    let lineNumber: NSColor
    let lineNumberBg: NSColor
    let currentLineBg: NSColor
    let selectionBg: NSColor

    static func named(_ name: String) -> LuaTheme { name == "light" ? .light : .dark }

    static let light = LuaTheme(
        background:    NSColor(calibratedWhite: 0.98, alpha: 1),
        text:          NSColor(calibratedWhite: 0.10, alpha: 1),
        keyword:       NSColor(calibratedRed: 0.00, green: 0.35, blue: 0.70, alpha: 1),
        string:        NSColor(calibratedRed: 0.65, green: 0.18, blue: 0.08, alpha: 1),
        comment:       NSColor(calibratedRed: 0.25, green: 0.50, blue: 0.25, alpha: 1),
        number:        NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.42, alpha: 1),
        functionName:  NSColor(calibratedRed: 0.50, green: 0.35, blue: 0.00, alpha: 1),
        love:          NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.45, alpha: 1),
        stdlib:        NSColor(calibratedRed: 0.05, green: 0.50, blue: 0.65, alpha: 1),
        method:        NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.05, alpha: 1),
        lineNumber:    NSColor(calibratedWhite: 0.60, alpha: 1),
        lineNumberBg:  NSColor.white,
        currentLineBg: NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1),
        selectionBg:   NSColor(calibratedRed: 0.70, green: 0.84, blue: 1.00, alpha: 1)
    )

    static let dark = LuaTheme(
        background:    NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.15, alpha: 1),
        text:          NSColor(calibratedWhite: 0.82, alpha: 1),
        keyword:       NSColor(calibratedRed: 0.45, green: 0.68, blue: 0.90, alpha: 1),
        string:        NSColor(calibratedRed: 0.72, green: 0.82, blue: 0.62, alpha: 1),
        comment:       NSColor(calibratedWhite: 0.40, alpha: 1),
        number:        NSColor(calibratedRed: 0.78, green: 0.68, blue: 0.52, alpha: 1),
        functionName:  NSColor(calibratedWhite: 0.75, alpha: 1),
        love:          NSColor(calibratedRed: 0.45, green: 0.78, blue: 0.72, alpha: 1),
        stdlib:        NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.90, alpha: 1),
        method:        NSColor(calibratedRed: 0.85, green: 0.75, blue: 0.40, alpha: 1),
        lineNumber:    NSColor(calibratedWhite: 0.32, alpha: 1),
        lineNumberBg:  NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.13, alpha: 1),
        currentLineBg: NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.20, alpha: 1),
        selectionBg:   NSColor(calibratedRed: 0.20, green: 0.35, blue: 0.52, alpha: 1)
    )
}

// MARK: - LuaSyntaxHighlighter

final class LuaSyntaxHighlighter {
    private struct Token {
        let pattern: NSRegularExpression
        let key: KeyPath<LuaTheme, NSColor>
    }

    private static let tokens: [Token] = build()

    private static func build() -> [Token] {
        func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }
        return [
            Token(pattern: rx(#"--\[(=*)\[[\s\S]*?\]\1\]"#, .dotMatchesLineSeparators), key: \.comment),
            Token(pattern: rx(#"--[^\n]*"#), key: \.comment),
            Token(pattern: rx(#"\[(=*)\[[\s\S]*?\]\1\]"#, .dotMatchesLineSeparators), key: \.string),
            Token(pattern: rx(#""(?:[^"\\\n]|\\.)*""#), key: \.string),
            Token(pattern: rx(#"'(?:[^'\\\n]|\\.)*'"#), key: \.string),
            Token(pattern: rx(#"\blove\.[a-zA-Z_.0-9]+"#), key: \.love),
            Token(pattern: rx(#"\b(?:math|table|string|io|os|coroutine|package|utf8)\.[a-zA-Z_][a-zA-Z0-9_]*"#), key: \.stdlib),
            Token(pattern: rx(#"\b(?:assert|collectgarbage|error|getmetatable|ipairs|next|pairs|pcall|print|rawget|rawset|require|select|setmetatable|tonumber|tostring|type|unpack|xpcall)\b"#), key: \.stdlib),
            Token(pattern: rx(#"(?<=:)[a-zA-Z_][a-zA-Z0-9_]*(?=\s*\()"#), key: \.method),
            Token(pattern: rx(#"\b(and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|self|then|true|until|while)\b"#), key: \.keyword),
            Token(pattern: rx(#"\b0[xX][0-9A-Fa-f]+"#), key: \.number),
            Token(pattern: rx(#"\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#), key: \.number),
            Token(pattern: rx(#"\b([A-Za-z_]\w*)\s*(?=\()"#), key: \.functionName),
        ]
    }

    func computeAttributes(for source: String, theme: LuaTheme) -> [(NSRange, NSColor)] {
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        var result: [(NSRange, NSColor)] = []
        for token in Self.tokens.reversed() {
            token.pattern.enumerateMatches(in: source, range: fullRange) { match, _, _ in
                guard let range = match?.range, range.length > 0 else { return }
                result.append((range, theme[keyPath: token.key]))
            }
        }
        return result
    }
}

// MARK: - JSON Syntax Highlighter

final class JsonSyntaxHighlighter {
    private struct Token {
        let pattern: NSRegularExpression
        let key: KeyPath<LuaTheme, NSColor>
    }

    private static let tokens: [Token] = build()

    private static func build() -> [Token] {
        func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: options)
        }
        return [
            Token(pattern: rx(#""(?:[^"\\]|\\.)*""#), key: \.string),
            Token(pattern: rx(#"-?\b\d+\.?\d*(?:[eE][+-]?\d+)?\b"#), key: \.number),
            Token(pattern: rx(#"\b(?:true|false|null)\b"#), key: \.keyword),
        ]
    }

    func computeAttributes(for source: String, theme: LuaTheme) -> [(NSRange, NSColor)] {
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        var result: [(NSRange, NSColor)] = []
        var occupied = IndexSet()
        for token in Self.tokens {
            token.pattern.enumerateMatches(in: source, range: fullRange) { match, _, _ in
                guard let range = match?.range, range.length > 0 else { return }
                let end = range.location + range.length
                guard end <= source.utf16.count else { return }
                if occupied.intersects(integersIn: range.location ..< end) { return }
                let isKey: Bool = {
                    let nsSource = source as NSString
                    var i = end
                    while i < nsSource.length {
                        let c = nsSource.character(at: i)
                        if c == 32 || c == 9 { i += 1; continue }
                        return c == 58
                    }
                    return false
                }()
                let color = isKey ? theme.functionName : theme[keyPath: token.key]
                occupied.insert(integersIn: range.location ..< end)
                result.append((range, color))
            }
        }
        return result
    }
}

// MARK: - LuaTextView

final class LuaTextView: NSTextView {
    var theme: LuaTheme = .dark { didSet { applyTheme() } }
    var editorFontSize: CGFloat = 13 {
        didSet {
            lineNumberRuler?.fontSize = max(10, editorFontSize - 2)
            applyTheme()
        }
    }
    var editorFontName: String = "" { didSet { applyTheme() } }
    var showsLineNumbers = true { didSet { applyLineNumberVisibility() } }
    var editorTabWidth: Int = 4
    var highlightCurrentLine: Bool = true { didSet { setNeedsDisplay(bounds) } }
    var autoCloseBraces: Bool = true

    weak var lineNumberRuler: LineNumberRulerView?
    var onSave: (() -> Void)?
    var onFontSizeChange: ((CGFloat) -> Void)?
    var boundFileURL: URL?
    var pausedLine: Int? { didSet { setNeedsDisplay(bounds) } }

    // LSP diagnostics for this buffer (realText-space positions). Setting them
    // repaints squiggles (temporary attributes) and refreshes the gutter.
    var diagnostics: [LSPClientService.Diagnostic] = [] {
        didSet { applyDiagnosticSquiggles(); lineNumberRuler?.needsDisplay = true }
    }
    private var squiggleRanges: [NSRange] = []

    weak var lspClient: LSPClientService?
    var lspDocumentURL: URL?
    var docHoverEnabled = true
    private var hoverTrackingArea: NSTrackingArea?
    private var hoverWorkItem: DispatchWorkItem?
    private var lastHoverCharIndex: Int = NSNotFound   // char a popover is currently shown for
    private var hoverPendingCharIndex: Int = NSNotFound // char the timer is scheduled for

    func editorFont(size: CGFloat? = nil) -> NSFont {
        let s = size ?? editorFontSize
        if !editorFontName.isEmpty, let f = NSFont(name: editorFontName, size: s) { return f }
        return NSFont.monospacedSystemFont(ofSize: s, weight: .regular)
    }

    private let highlighter = LuaSyntaxHighlighter()
    let jsonHighlighter = JsonSyntaxHighlighter()
    private var highlightTask: DispatchWorkItem?

    var isJsonFile: Bool { boundFileURL?.pathExtension.lowercased() == "json" }
    var isLuaBuffer: Bool { boundFileURL?.pathExtension.lowercased() == "lua" }
    private var suppressDidChangeHandling = false
    private let deferredHighlightCharacterThreshold = 40_000
    private let plainTextModeCharacterThreshold = 120_000

    // MARK: Code folding

    struct FoldRegion {
        let openerLine: Int
        var placeholderRange: NSRange
        let originalText: String
        let hiddenLineCount: Int
    }

    var foldRegions: [FoldRegion] = []
    var isFoldingActive: Bool { !foldRegions.isEmpty }

    private static let foldOpenerPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"^\s*(function\s|local\s+function\s|if\s|for\s|while\s|do\b|repeat\b|[\w.:]+\s*=\s*function\s*\(|.*function\s*\([^)]*\)\s*(?:--[^\n]*)?\s*$)"#)
    }()

    // Matches lines that end with { (table/block openers), ignoring trailing whitespace/comments
    private static let tableOpenerPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\{\s*(?:--[^\n]*)?\s*$"#)
    }()

    var realText: String {
        guard !foldRegions.isEmpty else { return string }
        let ns = NSMutableString(string: string)
        for region in foldRegions.sorted(by: { $0.placeholderRange.location > $1.placeholderRange.location }) {
            ns.replaceCharacters(in: region.placeholderRange, with: region.originalText)
        }
        return ns as String
    }

    func unfoldAll() {
        guard let ts = textStorage, !foldRegions.isEmpty else { return }
        for region in foldRegions.sorted(by: { $0.placeholderRange.location > $1.placeholderRange.location }) {
            let attrStr = NSAttributedString(string: region.originalText, attributes: [
                .font: editorFont(),
                .foregroundColor: theme.text
            ])
            ts.replaceCharacters(in: region.placeholderRange, with: attrStr)
        }
        foldRegions = []
        lineNumberRuler?.needsDisplay = true
        scheduleHighlight()
    }

    func scrollToLine(_ targetLine: Int) {
        unfoldAll()
        let text = self.string
        var currentLine = 1
        var idx = text.startIndex
        while idx < text.endIndex {
            if currentLine == targetLine {
                let nsLoc = text.distance(from: text.startIndex, to: idx)
                if let nlRange = text.range(of: "\n", range: idx..<text.endIndex) {
                    let nsLen = text.distance(from: idx, to: nlRange.lowerBound)
                    let r = NSRange(location: nsLoc, length: max(1, nsLen))
                    scrollRangeToVisible(r)
                    setSelectedRange(NSRange(location: nsLoc, length: 0))
                } else {
                    let nsLen = text.distance(from: idx, to: text.endIndex)
                    let r = NSRange(location: nsLoc, length: nsLen)
                    scrollRangeToVisible(r)
                    setSelectedRange(NSRange(location: nsLoc, length: 0))
                }
                return
            }
            if let nlRange = text.range(of: "\n", range: idx..<text.endIndex) {
                currentLine += 1
                idx = nlRange.upperBound
            } else {
                break
            }
        }
    }

    func toggleFold(atLine lineNumber: Int) {
        guard let ts = textStorage else { return }
        if let idx = foldRegions.firstIndex(where: { $0.openerLine == lineNumber }) {
            let region = foldRegions[idx]
            let attrStr = NSAttributedString(string: region.originalText, attributes: [
                .font: editorFont(),
                .foregroundColor: theme.text
            ])
            suppressDidChangeHandling = true
            ts.replaceCharacters(in: region.placeholderRange, with: attrStr)
            suppressDidChangeHandling = false
            let delta = (region.originalText as NSString).length - region.placeholderRange.length
            foldRegions.remove(at: idx)
            for i in foldRegions.indices where foldRegions[i].placeholderRange.location > region.placeholderRange.location {
                foldRegions[i].placeholderRange.location += delta
            }
            lineNumberRuler?.needsDisplay = true
            scheduleHighlight()
            return
        }
        // Unfold any inner folds that fall within the region we're about to fold.
        // This ensures originalText is always clean, unfolded text - preventing
        // nested fold region corruption on unfold.
        let previewLines = ts.string.components(separatedBy: "\n")
        let previewEnd = findFoldEnd(from: lineNumber, lines: previewLines)
        let innerLines = foldRegions
            .map(\.openerLine)
            .filter { $0 > lineNumber && $0 < previewEnd }
            .sorted(by: >) // unfold innermost first to keep offsets stable
        for innerLine in innerLines { toggleFold(atLine: innerLine) }

        let fullText = ts.string
        let lines = fullText.components(separatedBy: "\n")
        guard lineNumber >= 1 && lineNumber < lines.count else { return }
        let startBodyLine = lineNumber + 1
        let endLine = findFoldEnd(from: lineNumber, lines: lines)
        guard startBodyLine <= endLine && startBodyLine <= lines.count else { return }
        let bodyStartRange = rangeForLine(startBodyLine, in: fullText)
        guard bodyStartRange.location != NSNotFound else { return }
        let bodyEndLoc: Int
        if endLine <= lines.count {
            let endLineRange = rangeForLine(endLine, in: fullText)
            bodyEndLoc = endLineRange.location != NSNotFound ? endLineRange.location : (fullText as NSString).length
        } else {
            bodyEndLoc = (fullText as NSString).length
        }
        let bodyRange = NSRange(location: bodyStartRange.location, length: max(0, bodyEndLoc - bodyStartRange.location))
        guard bodyRange.length > 0 else { return }
        let originalText = (fullText as NSString).substring(with: bodyRange)
        let hiddenLines = endLine - startBodyLine
        let placeholder = " ⋯ \(hiddenLines) lines\n"
        let placeholderAttr = NSMutableAttributedString(string: placeholder)
        placeholderAttr.addAttributes([
            .font: editorFont(size: editorFontSize * 0.88),
            .foregroundColor: NSColor.secondaryLabelColor
        ], range: NSRange(location: 0, length: placeholderAttr.length))
        suppressDidChangeHandling = true
        ts.replaceCharacters(in: bodyRange, with: placeholderAttr)
        suppressDidChangeHandling = false
        let placeholderRange = NSRange(location: bodyRange.location, length: placeholderAttr.length)
        let delta = placeholderAttr.length - bodyRange.length
        for i in foldRegions.indices where foldRegions[i].placeholderRange.location >= bodyRange.location {
            foldRegions[i].placeholderRange.location += delta
        }
        foldRegions.append(FoldRegion(openerLine: lineNumber, placeholderRange: placeholderRange,
                                       originalText: originalText, hiddenLineCount: hiddenLines))
        lineNumberRuler?.needsDisplay = true
        scheduleHighlight()
    }

    var foldedLines: Set<Int> { Set(foldRegions.map(\.openerLine)) }

    func isFoldable(lineNum: Int, in text: String) -> Bool {
        let lines = text.components(separatedBy: "\n")
        guard lineNum >= 1 && lineNum <= lines.count else { return false }
        let line = lines[lineNum - 1]
        let range = NSRange(line.startIndex..., in: line)
        if Self.foldOpenerPattern.firstMatch(in: line, range: range) != nil { return true }
        // Table/block: line ends with {, and the matching } is on a LATER line
        if Self.tableOpenerPattern.firstMatch(in: line, range: range) != nil {
            let endLine = findTableFoldEnd(from: lineNum, lines: lines)
            return endLine > lineNum + 1  // need at least 1 hidden line between { and }
        }
        return false
    }

    func findFoldEnd(from openerLine: Int, lines: [String]) -> Int {
        guard openerLine >= 1, openerLine <= lines.count else { return lines.count }
        let line = lines[openerLine - 1]
        let range = NSRange(line.startIndex..., in: line)
        // Table/brace fold: use bracket matching
        if Self.tableOpenerPattern.firstMatch(in: line, range: range) != nil {
            return findTableFoldEnd(from: openerLine, lines: lines)
        }
        // Keyword fold: indent-based
        let openerIndent = indentLevel(of: lines[openerLine - 1])
        for lineNum in (openerLine + 1)...lines.count {
            let content = lines[lineNum - 1]
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && indentLevel(of: content) <= openerIndent { return lineNum }
        }
        return lines.count
    }

    /// Find the line containing the matching `}` for a `{`-ending opener line.
    /// Returns the line number of the `}` line, or openerLine if not found.
    private func findTableFoldEnd(from openerLine: Int, lines: [String]) -> Int {
        var depth = 0
        for lineNum in openerLine...lines.count {
            let line = lines[lineNum - 1]
            for ch in line {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 { return lineNum }
                }
            }
        }
        return openerLine // no match found
    }

    private func indentLevel(of line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 }
            else if ch == "\t" { count += 4 }
            else { break }
        }
        return count
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func configure(scrollView: NSScrollView) {
        isEditable = true
        isSelectable = true
        isRichText = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled  = false
        isAutomaticDashSubstitutionEnabled   = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled    = false
        isAutomaticLinkDetectionEnabled      = false
        isContinuousSpellCheckingEnabled     = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainerInset = NSSize(width: 4, height: 8)
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                               height: CGFloat.greatestFiniteMagnitude)
        let spaceWidth = ("    " as NSString).size(
            withAttributes: [.font: editorFont()]
        ).width
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = spaceWidth
        defaultParagraphStyle = paragraphStyle

        let ruler = LineNumberRulerView(scrollView: scrollView)
        ruler.theme    = theme
        ruler.fontName = editorFontName
        ruler.fontSize = max(10, editorFontSize - 2)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        lineNumberRuler = ruler

        applyTheme()
        applyLineNumberVisibility()
    }

    private func applyTheme() {
        backgroundColor = theme.background
        insertionPointColor = theme.text
        selectedTextAttributes = [.backgroundColor: theme.selectionBg]
        lineNumberRuler?.theme    = theme
        lineNumberRuler?.fontName = editorFontName
        let f = editorFont()
        let spaceWidth = ("    " as NSString).size(withAttributes: [.font: f]).width
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = spaceWidth
        defaultParagraphStyle = paragraphStyle
        // Update typing attributes without touching existing foreground colors
        typingAttributes = [.font: f, .foregroundColor: theme.text]
        if let textStorage, textStorage.length > 0 {
            textStorage.beginEditing()
            textStorage.addAttribute(.font, value: f,
                range: NSRange(location: 0, length: textStorage.length))
            textStorage.endEditing()
        }
        scheduleHighlight(delay: 0)
    }

    private func applyLineNumberVisibility() {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.hasVerticalRuler = showsLineNumbers
        scrollView.rulersVisible = showsLineNumbers
        lineNumberRuler?.ruleThickness = showsLineNumbers ? 44 : 0
        lineNumberRuler?.needsDisplay = true
    }

    override func didChangeText() {
        super.didChangeText()
        lineNumberRuler?.needsDisplay = true
        guard !suppressDidChangeHandling else { return }
        scheduleHighlight()
    }

    private func scheduleHighlight(delay: TimeInterval? = nil) {
        highlightTask?.cancel()
        guard string.count < plainTextModeCharacterThreshold else { return }
        let task = DispatchWorkItem { [weak self] in self?.runHighlight() }
        highlightTask = task
        let effectiveDelay: TimeInterval
        if let d = delay {
            effectiveDelay = d
        } else {
            // Adaptive delay: larger files get more breathing room
            switch string.count {
            case 0..<5_000:   effectiveDelay = 0.08
            case 5_000..<20_000: effectiveDelay = 0.15
            case 20_000..<60_000: effectiveDelay = 0.25
            default:          effectiveDelay = 0.40
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveDelay, execute: task)
    }

    private func runHighlight() {
        guard let textStorage else { return }
        let source = textStorage.string
        let theme = self.theme
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let attributes = self.isJsonFile
                ? self.jsonHighlighter.computeAttributes(for: source, theme: theme)
                : self.highlighter.computeAttributes(for: source, theme: theme)
            DispatchQueue.main.async {
                guard let textStorage = self.textStorage, textStorage.string == source else { return }
                textStorage.beginEditing()
                textStorage.addAttribute(.foregroundColor, value: theme.text,
                    range: NSRange(location: 0, length: textStorage.length))
                for (range, color) in attributes {
                    textStorage.addAttribute(.foregroundColor, value: color, range: range)
                }
                textStorage.endEditing()
            }
        }
    }

    func loadText(_ text: String) {
        highlightTask?.cancel()
        unfoldAll()
        suppressDidChangeHandling = true
        string = text
        suppressDidChangeHandling = false
        lineNumberRuler?.needsDisplay = true
        guard let textStorage else { return }
        textStorage.beginEditing()
        textStorage.addAttribute(.foregroundColor, value: theme.text,
            range: NSRange(location: 0, length: textStorage.length))
        textStorage.addAttribute(.font,
            value: editorFont(),
            range: NSRange(location: 0, length: textStorage.length))
        textStorage.endEditing()
        guard text.count < plainTextModeCharacterThreshold else { return }
        let delay = text.count > deferredHighlightCharacterThreshold ? 0.45 : 0.08
        scheduleHighlight(delay: delay)
    }

    override func shouldChangeText(in affectedRange: NSRange, replacementString: String?) -> Bool {
        for region in foldRegions {
            let intersection = NSIntersectionRange(affectedRange, region.placeholderRange)
            if intersection.length > 0 || affectedRange.location == region.placeholderRange.location {
                toggleFold(atLine: region.openerLine)
                return false
            }
        }
        guard super.shouldChangeText(in: affectedRange, replacementString: replacementString) else { return false }
        let insertLen = (replacementString as NSString?)?.length ?? 0
        let delta = insertLen - affectedRange.length
        if delta != 0 {
            for i in foldRegions.indices where foldRegions[i].placeholderRange.location > affectedRange.location {
                foldRegions[i].placeholderRange.location += delta
            }
        }
        return true
    }

    private func isIdentChar(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95
    }

    // MARK: Active line highlight

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager else { return }

        let sel = selectedRange()
        let caretIndex = min(sel.location, string.utf16.count)
        let glyphIndex = lm.isValidGlyphIndex(caretIndex)
            ? lm.glyphIndexForCharacter(at: caretIndex)
            : max(0, lm.numberOfGlyphs - 1)
        guard lm.numberOfGlyphs > 0 || string.isEmpty else { return }
        let lineRect: NSRect
        if lm.numberOfGlyphs == 0 {
            lineRect = NSRect(x: 0, y: textContainerInset.height,
                              width: bounds.width,
                              height: ceil(lm.defaultLineHeight(for: editorFont())))
        } else {
            let clampedGlyph = min(glyphIndex, lm.numberOfGlyphs - 1)
            var fragRange = NSRange()
            let frag = lm.lineFragmentRect(forGlyphAt: clampedGlyph, effectiveRange: &fragRange)
            lineRect = NSRect(
                x: bounds.minX,
                y: frag.minY + textContainerInset.height,
                width: bounds.width,
                height: frag.height
            )
        }
        guard rect.intersects(lineRect) else { return }
        if highlightCurrentLine {
            theme.currentLineBg.setFill()
            lineRect.fill()
        }

        // Paused line (debugger) - yellow highlight
        if let paused = pausedLine {
            drawLineHighlight(forLine: paused, color: NSColor.systemYellow.withAlphaComponent(0.25), in: rect)
        }
    }

    private func drawLineHighlight(forLine targetLine: Int, color: NSColor, in rect: NSRect) {
        guard let lm = layoutManager else { return }
        let text = string as NSString
        var glyphIdx = 0
        var lineNum  = 1
        let total    = lm.numberOfGlyphs
        while glyphIdx < total {
            var glyphRange = NSRange()
            let frag = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: &glyphRange)
            let charIdx = lm.characterIndexForGlyph(at: glyphIdx)
            let isStart = charIdx == 0 || text.character(at: charIdx - 1) == 10
            if isStart && lineNum == targetLine {
                let hlRect = NSRect(x: bounds.minX, y: frag.minY + textContainerInset.height,
                                    width: bounds.width, height: frag.height)
                if rect.intersects(hlRect) {
                    color.setFill()
                    hlRect.fill()
                }
                return
            }
            let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let lastIdx = NSMaxRange(charRange) - 1
            if lastIdx >= 0 && lastIdx < text.length && text.character(at: lastIdx) == 10 { lineNum += 1 }
            glyphIdx = NSMaxRange(glyphRange)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else { super.keyDown(with: event); return }
        switch event.charactersIgnoringModifiers {
        case "s":
            onSave?()
        case "/":
            toggleLineComment()
            return
        case "f":
            unfoldAll()
            triggerFinder(.showFindInterface)
        case "g":
            triggerFinder(event.modifierFlags.contains(.shift) ? .previousMatch : .nextMatch)
        case "h":
            unfoldAll()
            triggerFinder(.showReplaceInterface)
        case "+", "=":
            editorFontSize = min(32, editorFontSize + 1)
            onFontSizeChange?(editorFontSize)
        case "-":
            editorFontSize = max(8, editorFontSize - 1)
            onFontSizeChange?(editorFontSize)
        default:
            super.keyDown(with: event)
        }
    }

    override func insertTab(_ sender: Any?) {
        insertText(String(repeating: " ", count: editorTabWidth), replacementRange: selectedRange())
    }

    // MARK: Auto-close brackets/quotes

    private static let closingChar: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"
    ]

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard autoCloseBraces,
              let ch = (string as? String).flatMap({ $0.count == 1 ? $0.first : nil }),
              let closing = Self.closingChar[ch]
        else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let sel = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        // If next char is already the closing char, just skip over it
        let str = self.string as NSString
        if sel.length == 0, sel.location < str.length,
           str.character(at: sel.location) == closing.utf16.first {
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }
        // Wrap selection or insert pair
        if sel.length > 0 {
            let selected = str.substring(with: sel)
            super.insertText("\(ch)\(selected)\(closing)", replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
        } else {
            super.insertText("\(ch)\(closing)", replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        }
    }

    // MARK: Copy/Cut - map folded buffer range → real text

    override func copy(_ sender: Any?) {
        guard isFoldingActive else { super.copy(sender); return }
        let real = selectedRealText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(real, forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard isFoldingActive else { super.cut(sender); return }
        let real = selectedRealText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(real, forType: .string)
        // Delete the selected range from the buffer normally
        insertText("", replacementRange: selectedRange())
    }

    /// Maps a buffer (possibly-folded) location to its location in realText.
    /// When no folds are active this is the identity. Used for LSP positions.
    func realLocation(forBufferLocation bufLoc: Int) -> Int {
        guard isFoldingActive else { return bufLoc }
        let sorted = foldRegions.sorted { $0.placeholderRange.location < $1.placeholderRange.location }
        var real = bufLoc
        for fold in sorted {
            let placeholderEnd = NSMaxRange(fold.placeholderRange)
            if placeholderEnd <= bufLoc {
                // Fold is entirely before the location: add back the hidden length.
                real += (fold.originalText as NSString).length - fold.placeholderRange.length
            } else {
                break  // folds are sorted; nothing further can precede bufLoc
            }
        }
        return real
    }

    /// Maps a realText location back to a buffer (possibly-folded) location.
    /// Inverse of realLocation(forBufferLocation:). Identity when unfolded.
    /// Returns nil if the realText location falls inside a folded region.
    func bufferLocation(forRealLocation realLoc: Int) -> Int? {
        guard isFoldingActive else { return realLoc }
        let sorted = foldRegions.sorted { $0.placeholderRange.location < $1.placeholderRange.location }
        var buf = realLoc
        var realCursor = 0
        var bufCursor = 0
        for fold in sorted {
            let beforeLen = fold.placeholderRange.location - bufCursor
            let realChunkEnd = realCursor + beforeLen
            if realLoc < realChunkEnd {
                return bufCursor + (realLoc - realCursor)  // before this fold
            }
            let hiddenLen = (fold.originalText as NSString).length
            if realLoc < realChunkEnd + hiddenLen {
                return nil  // inside a collapsed fold — not visible
            }
            realCursor = realChunkEnd + hiddenLen
            bufCursor = NSMaxRange(fold.placeholderRange)
            buf = bufCursor + (realLoc - realCursor)
        }
        return buf
    }

    // Maps a 0-based realText (line, character) to a buffer character location.
    private func bufferLocation(realLine: Int, realCharacter: Int) -> Int? {
        let realText = self.realText as NSString
        var line = 0
        var lineStart = 0
        if realLine > 0 {
            var found = false
            realText.enumerateSubstrings(in: NSRange(location: 0, length: realText.length),
                                         options: [.byLines, .substringNotRequired]) { _, _, enclosing, stop in
                line += 1
                if line == realLine {
                    lineStart = enclosing.location + enclosing.length
                    found = true
                    stop.pointee = true
                }
            }
            if !found { return nil }
        }
        let realLoc = min(lineStart + realCharacter, realText.length)
        return bufferLocation(forRealLocation: realLoc)
    }

    // Underline diagnostic ranges with squiggles via temporary attributes
    // (same mechanism as bracket matching). Cleared and reapplied on change.
    private func applyDiagnosticSquiggles() {
        guard let lm = layoutManager else { return }
        for r in squiggleRanges {
            lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: r)
            lm.removeTemporaryAttribute(.underlineColor, forCharacterRange: r)
        }
        squiggleRanges = []

        let bufLen = (string as NSString).length
        for diag in diagnostics {
            guard let startLoc = bufferLocation(realLine: diag.startLine, realCharacter: diag.startCharacter) else { continue }
            let endLoc = bufferLocation(realLine: diag.endLine, realCharacter: diag.endCharacter) ?? (startLoc + 1)
            let length = max(1, min(endLoc, bufLen) - startLoc)
            guard startLoc >= 0, startLoc < bufLen else { continue }
            let range = NSRange(location: startLoc, length: min(length, bufLen - startLoc))
            let color: NSColor = diag.severity == .warning ? .systemYellow : .systemRed
            lm.addTemporaryAttribute(.underlineStyle,
                                     value: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
                                     forCharacterRange: range)
            lm.addTemporaryAttribute(.underlineColor, value: color, forCharacterRange: range)
            squiggleRanges.append(range)
            // Diagnostic message is shown via the unified hover panel (fireHover),
            // not an NSToolTip — so there's a single combined box.
        }
    }

    // Diagnostics whose range covers the given buffer character location.
    private func diagnosticsCovering(bufferLocation loc: Int) -> [LSPClientService.Diagnostic] {
        diagnostics.filter { diag in
            guard let s = bufferLocation(realLine: diag.startLine, realCharacter: diag.startCharacter) else { return false }
            let e = bufferLocation(realLine: diag.endLine, realCharacter: diag.endCharacter) ?? (s + 1)
            return loc >= s && loc < max(e, s + 1)
        }
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        // Hover works with or without the language server (static fallback below),
        // gated on the doc-hover setting, for Lua buffers only.
        guard docHoverEnabled, isLuaBuffer,
              let lm = layoutManager, let tc = textContainer, lm.numberOfGlyphs > 0 else { return }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerInset.width,
                                     y: point.y - textContainerInset.height)
        let charIndex = lm.characterIndexForGlyph(at: lm.glyphIndex(for: containerPoint, in: tc))

        // Staying within the same token must NOT reset the timer — otherwise slow
        // motion over a symbol keeps rescheduling and hover never fires. Only act
        // when the hovered character actually changes.
        if charIndex == hoverPendingCharIndex { return }
        hoverPendingCharIndex = charIndex

        hoverWorkItem?.cancel()
        // Already showing this symbol's popover: nothing to do.
        if charIndex == lastHoverCharIndex, HoverPanel.shared.isVisible { return }

        let work = DispatchWorkItem { [weak self] in self?.fireHover(at: point) }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverWorkItem?.cancel()
        lastHoverCharIndex = NSNotFound
        hoverPendingCharIndex = NSNotFound
        HoverPanel.shared.dismiss()
    }

    private func fireHover(at point: NSPoint) {
        guard let lm = layoutManager, let tc = textContainer else { return }

        let containerPoint = NSPoint(x: point.x - textContainerInset.width,
                                     y: point.y - textContainerInset.height)
        let glyphIndex = lm.glyphIndex(for: containerPoint, in: tc)
        guard lm.numberOfGlyphs > 0 else { return }
        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)

        // Don't re-request for the same symbol position.
        if charIndex == lastHoverCharIndex, HoverPanel.shared.isVisible { return }
        lastHoverCharIndex = charIndex

        let glyphRange = lm.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1),
                                       actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        rect.origin.x += textContainerInset.width
        rect.origin.y += textContainerInset.height
        let screenRect = window?.convertToScreen(convert(rect, to: nil)) ?? .zero

        let diagBlock = diagnosticsCovering(bufferLocation: charIndex)
            .map { ($0.severity == .warning ? "Warning: " : "Error: ") + $0.message }
            .joined(separator: "\n")

        // Prefer the language server when running; otherwise static love_api docs.
        if let url = lspDocumentURL, let client = lspClient, client.status == .active {
            client.requestHover(url, line: hoverPosition(forBufferLocation: charIndex).line,
                                character: hoverPosition(forBufferLocation: charIndex).character) { [weak self] markdown in
                let docs = (markdown?.isEmpty == false) ? markdown : self?.staticDocMarkdown(charIndex: charIndex)
                self?.presentCombinedHover(diagnostics: diagBlock, docs: docs, screenRect: screenRect)
            }
        } else {
            presentCombinedHover(diagnostics: diagBlock, docs: staticDocMarkdown(charIndex: charIndex), screenRect: screenRect)
        }
    }

    // Compose the single hover box: diagnostics on top, an HR, then docs below.
    // HR only when both are present; dismiss if neither.
    private func presentCombinedHover(diagnostics diagBlock: String, docs: String?, screenRect: NSRect) {
        let hasDiag = !diagBlock.isEmpty
        let hasDocs = (docs?.isEmpty == false)
        guard hasDiag || hasDocs else { HoverPanel.shared.dismiss(); return }

        var md = ""
        if hasDiag { md += diagBlock }
        if hasDiag && hasDocs { md += "\n\n---\n\n" }
        if hasDocs { md += docs! }
        HoverPanel.shared.show(markdown: md, anchorScreenRect: screenRect)
    }

    // Static docs markdown for the dotted symbol under the cursor, or nil.
    private func staticDocMarkdown(charIndex: Int) -> String? {
        let ns = string as NSString
        guard charIndex < ns.length else { return nil }
        func isSym(_ c: unichar) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 46
        }
        var start = charIndex, end = charIndex
        while start > 0, isSym(ns.character(at: start - 1)) { start -= 1 }
        while end < ns.length, isSym(ns.character(at: end)) { end += 1 }
        guard end > start else { return nil }
        let symbol = ns.substring(with: NSRange(location: start, length: end - start))
        return LoveAPILoader.hoverMarkdown(for: symbol)
    }

    // Buffer char location -> 0-based (line, char) in realText (LSP positions).
    // Counts newlines strictly before `loc`; the line containing the cursor is
    // not yet "passed", so this yields the correct 0-based line.
    private func hoverPosition(forBufferLocation bufLoc: Int) -> (line: Int, character: Int) {
        let real = realLocation(forBufferLocation: bufLoc)
        let ns = realText as NSString
        let loc = min(real, ns.length)
        var line = 0
        var lineStart = 0
        var i = 0
        while i < loc {
            if ns.character(at: i) == 10 {  // \n
                line += 1
                lineStart = i + 1
            }
            i += 1
        }
        return (line, loc - lineStart)
    }

    // MARK: Quick Fix

    private var quickFixActions: [LSPClientService.CodeAction] = []

    override func rightMouseDown(with event: NSEvent) {
        // A right-click opens a menu; the hover box must not linger over it.
        hoverWorkItem?.cancel()
        lastHoverCharIndex = NSNotFound
        hoverPendingCharIndex = NSNotFound
        HoverPanel.shared.dismiss()

        guard let lm = layoutManager, let tc = textContainer,
              let url = lspDocumentURL, let client = lspClient,
              client.status == .active, lm.numberOfGlyphs > 0 else {
            super.rightMouseDown(with: event); return
        }
        // Resolve the clicked character and the diagnostics covering its line.
        let p = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: p.x - textContainerInset.width, y: p.y - textContainerInset.height)
        let charIndex = lm.characterIndexForGlyph(at: lm.glyphIndex(for: containerPoint, in: tc))
        let pos = hoverPosition(forBufferLocation: charIndex)

        let lineDiags = diagnostics.filter { $0.startLine <= pos.line && pos.line <= $0.endLine }
        guard !lineDiags.isEmpty else { super.rightMouseDown(with: event); return }

        // Move the caret to the click so an applied edit lands sensibly, then ask
        // the server for fixes covering this line's diagnostics.
        setSelectedRange(NSRange(location: charIndex, length: 0))
        let startL = lineDiags.map(\.startLine).min() ?? pos.line
        let endL = lineDiags.map(\.endLine).max() ?? pos.line
        // Capture the click point now; the event is stale once the async reply
        // arrives, so we pop the menu by position rather than with the event.
        let menuPoint = p
        client.requestCodeActions(url, startLine: startL, startCharacter: 0,
                                  endLine: endL, endCharacter: 0, diagnostics: lineDiags) { [weak self] actions in
            guard let self, !actions.isEmpty else { return }
            self.presentQuickFixMenu(actions, at: menuPoint)
        }
    }

    private func presentQuickFixMenu(_ actions: [LSPClientService.CodeAction], at point: NSPoint) {
        quickFixActions = actions
        let menu = NSMenu(title: "Quick Fix")
        for (i, action) in actions.enumerated() {
            let item = NSMenuItem(title: action.title, action: #selector(applyQuickFix(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func applyQuickFix(_ sender: NSMenuItem) {
        guard sender.tag < quickFixActions.count, let client = lspClient else { return }
        let action = quickFixActions[sender.tag]
        client.apply(action) { [weak self] _, edits in
            self?.applyLSPEdits(edits)
        }
    }

    // Apply LSP TextEdits (realText positions) to this buffer, mapping through
    // folding. Applied last-first so earlier offsets stay valid.
    private func applyLSPEdits(_ edits: [[String: Any]]) {
        struct Resolved { let range: NSRange; let text: String }
        var resolved: [Resolved] = []
        for e in edits {
            guard let newText = e["newText"] as? String,
                  let range = e["range"] as? [String: Any],
                  let start = range["start"] as? [String: Any],
                  let end = range["end"] as? [String: Any],
                  let sl = start["line"] as? Int, let sc = start["character"] as? Int,
                  let el = end["line"] as? Int, let ec = end["character"] as? Int,
                  let startLoc = bufferLocation(realLine: sl, realCharacter: sc),
                  let endLoc = bufferLocation(realLine: el, realCharacter: ec) else { continue }
            resolved.append(Resolved(range: NSRange(location: startLoc, length: max(0, endLoc - startLoc)),
                                     text: newText))
        }
        // Apply bottom-up so earlier edits don't shift later ranges.
        for r in resolved.sorted(by: { $0.range.location > $1.range.location }) {
            if shouldChangeText(in: r.range, replacementString: r.text) {
                insertText(r.text, replacementRange: r.range)
            }
        }
    }

    /// Returns the real (unfolded) text corresponding to the current selection.
    private func selectedRealText() -> String {
        let sel = selectedRange()
        guard sel.length > 0 else { return "" }
        let bufStr = string as NSString

        // Build a list of (bufferLocation, realLocation) offsets for each fold region
        // sorted by buffer location so we can walk through them in order.
        let sorted = foldRegions.sorted { $0.placeholderRange.location < $1.placeholderRange.location }

        let result = NSMutableString()
        let bufEnd = sel.location + sel.length

        // Walk the selected buffer range, substituting placeholders with real text
        var cursor = sel.location
        while cursor < bufEnd {
            // Find next fold placeholder that starts at or after cursor and within selection
            let nextFold = sorted.first { $0.placeholderRange.location >= cursor &&
                                          $0.placeholderRange.location < bufEnd }
            if let fold = nextFold {
                let foldStart = fold.placeholderRange.location
                let foldEnd   = NSMaxRange(fold.placeholderRange)
                // Append buffer text before this fold
                if foldStart > cursor {
                    let before = NSRange(location: cursor, length: foldStart - cursor)
                    result.append(bufStr.substring(with: before))
                }
                // Append real (original) text of this fold
                result.append(fold.originalText)
                cursor = foldEnd
            } else {
                // No more folds - append remainder
                let remaining = NSRange(location: cursor, length: bufEnd - cursor)
                result.append(bufStr.substring(with: remaining))
                break
            }
        }
        return result as String
    }

    // MARK: Line comment toggle (Cmd+/)

    private func toggleLineComment() {
        guard let ts = textStorage else { return }
        let str = ts.string as NSString
        let sel = selectedRange()

        // Find the range of all lines covered by the selection
        let selLineRange = str.lineRange(for: sel)
        let selStr = str.substring(with: selLineRange)
        let lines = selStr.components(separatedBy: "\n")

        // Determine whether ALL non-empty lines already have --
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allCommented = !nonEmpty.isEmpty && nonEmpty.allSatisfy { line in
            let t = line.drop(while: { $0 == " " || $0 == "\t" })
            return t.hasPrefix("--")
        }

        // Build new block
        var newLines = lines
        for i in newLines.indices {
            let line = newLines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if allCommented {
                // Remove first occurrence of "--" after leading whitespace
                if let dashRange = line.range(of: "--") {
                    newLines[i] = line.replacingCharacters(in: dashRange, with: "")
                }
            } else {
                // Add "--" after leading whitespace
                var wsEnd = line.startIndex
                while wsEnd < line.endIndex && (line[wsEnd] == " " || line[wsEnd] == "\t") {
                    wsEnd = line.index(after: wsEnd)
                }
                newLines[i] = String(line[..<wsEnd]) + "--" + String(line[wsEnd...])
            }
        }

        let newBlock = newLines.joined(separator: "\n")
        insertText(newBlock, replacementRange: selLineRange)
        // Re-select the entire modified region
        setSelectedRange(NSRange(location: selLineRange.location, length: (newBlock as NSString).length))
    }

    private func triggerFinder(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    func rangeForLine(_ lineNumber: Int, in text: String) -> NSRange {
        let ns = text as NSString
        var current = 1
        var index = 0
        while index < ns.length && current < lineNumber {
            if ns.character(at: index) == unichar(("\n" as UnicodeScalar).value) { current += 1 }
            index += 1
        }
        guard current == lineNumber else { return NSRange(location: NSNotFound, length: 0) }
        return ns.lineRange(for: NSRange(location: index, length: 0))
    }
}

// MARK: - LineNumberRulerView

final class LineNumberRulerView: NSRulerView {
    var theme: LuaTheme = .dark { didSet { needsDisplay = true } }
    var breakpoints: BreakpointManager? { didSet { needsDisplay = true } }
    // 1-based line number -> highest severity on that line (for the gutter dot).
    var diagnosticLines: [Int: LSPClientService.DiagnosticSeverity] = [:] { didSet { needsDisplay = true } }
    var currentFile: String = "" { didSet { needsDisplay = true } }
    var fontName: String = "" { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 11 {
        didSet {
            ruleThickness = max(44, fontSize * 3.2)
            needsDisplay = true
            // Force scroll view to re-tile and ruler to redraw immediately
            // so triangles track line positions after font size changes.
            scrollView?.tile()
            display()
        }
    }

    private let rightPad: CGFloat = 10
    private let newline = unichar(("\n" as UnicodeScalar).value)
    private let dotSize: CGFloat = 7

    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 44
        observeScroll(in: scrollView)
    }

    required init(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func observeScroll(in scrollView: NSScrollView) {
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
            name: NSText.didChangeNotification, object: nil)
    }

    @objc private func refresh() { needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        guard let scrollView,
              let textView = scrollView.documentView as? LuaTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let localX = convert(event.locationInWindow, from: nil).x
        let localY = convert(event.locationInWindow, from: nil).y
        let visibleRect = scrollView.documentVisibleRect
        let insetY = textView.textContainerInset.height
        let documentY = localY + visibleRect.minY - insetY
        let glyphIndex = layoutManager.glyphIndex(for: CGPoint(x: 0, y: max(documentY, 0)), in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let text = textView.string as NSString
        let lineRange = text.lineRange(for: NSRange(location: characterIndex, length: 0))
        var lineNumber = 1, index = 0
        while index < lineRange.location && index < text.length {
            if text.character(at: index) == newline { lineNumber += 1 }
            index += 1
        }
        if localX < bounds.maxX - rightPad - 12 {
            if textView.isFoldable(lineNum: lineNumber, in: textView.string) {
                textView.toggleFold(atLine: lineNumber)
            }
        } else {
            // Right side of gutter → toggle breakpoint
            if let bp = breakpoints, !currentFile.isEmpty {
                bp.toggle(file: currentFile, line: lineNumber)
            }
        }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let scrollView,
              let textView = scrollView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager else { return }

        let luaTextView = textView as? LuaTextView
        theme.lineNumberBg.setFill()
        bounds.fill()
        theme.text.withAlphaComponent(0.08).setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: (!fontName.isEmpty ? NSFont(name: fontName, size: fontSize) : nil)
                   ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: theme.lineNumber
        ]
        let text = textView.string as NSString
        let insetY = textView.textContainerInset.height
        let visibleRect = scrollView.documentVisibleRect
        let totalGlyphs = layoutManager.numberOfGlyphs
        let foldPlaceholders: [(location: Int, hiddenCount: Int)] = luaTextView?.foldRegions.map {
            ($0.placeholderRange.location, $0.hiddenLineCount)
        } ?? []

        guard totalGlyphs > 0 else {
            let font = attributes[.font] as? NSFont
                       ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let lineH = ceil(layoutManager.defaultLineHeight(for: font))
            // y = lineRect.minY + insetY - visibleRect.minY → insetY when minY = visibleRect.minY
            drawLabel("1", attributes: attributes,
                lineRect: .init(x: 0, y: visibleRect.minY, width: 0, height: lineH),
                insetY: insetY, visibleRect: visibleRect, lineNumber: 1, luaTextView: luaTextView)
            return
        }

        var lineNumber = 1
        var lineOffset  = 0
        var glyphIndex  = 0
        var lastLineRect = CGRect.zero

        while glyphIndex < totalGlyphs {
            var glyphRange = NSRange()
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &glyphRange)
            lastLineRect = lineRect
            let lineYInRuler = lineRect.minY + insetY - visibleRect.minY
            if lineYInRuler > bounds.height { break }
            let lineBottomInRuler = lineRect.maxY + insetY - visibleRect.minY
            if lineBottomInRuler < 0 {
                glyphIndex = NSMaxRange(glyphRange)
                countNewline(glyphRange: glyphRange, layoutManager: layoutManager, text: text, lineNumber: &lineNumber)
                continue
            }
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let isLogicalStart = characterIndex == 0 || text.character(at: characterIndex - 1) == newline
            if isLogicalStart {
                let matchedFold = foldPlaceholders.first {
                    NSLocationInRange(characterIndex, NSRange(location: $0.location, length: 1)) || $0.location == characterIndex
                }
                if let fold = matchedFold {
                    drawLabel("⋯", attributes: attributes, lineRect: lineRect,
                        insetY: insetY, visibleRect: visibleRect,
                        lineNumber: lineNumber + lineOffset, luaTextView: luaTextView)
                    lineOffset += max(0, fold.hiddenCount - 1)
                } else {
                    drawLabel("\(lineNumber + lineOffset)", attributes: attributes, lineRect: lineRect,
                        insetY: insetY, visibleRect: visibleRect,
                        lineNumber: lineNumber + lineOffset, luaTextView: luaTextView)
                }
            }
            glyphIndex = NSMaxRange(glyphRange)
            countNewline(glyphRange: glyphRange, layoutManager: layoutManager, text: text, lineNumber: &lineNumber)
        }

        // Draw line number for trailing empty line (text ends with newline)
        if text.length > 0 && text.character(at: text.length - 1) == newline {
            let emptyLineRect = CGRect(x: lastLineRect.minX,
                                       y: lastLineRect.maxY,
                                       width: lastLineRect.width,
                                       height: lastLineRect.height > 0 ? lastLineRect.height : 16)
            let emptyLineY = emptyLineRect.minY + insetY - visibleRect.minY
            if emptyLineY <= bounds.height {
                drawLabel("\(lineNumber + lineOffset)", attributes: attributes,
                    lineRect: emptyLineRect,
                    insetY: insetY, visibleRect: visibleRect,
                    lineNumber: lineNumber + lineOffset, luaTextView: luaTextView)
            }
        }
    }

    private func countNewline(glyphRange: NSRange, layoutManager: NSLayoutManager,
                               text: NSString, lineNumber: inout Int) {
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let lastIndex = NSMaxRange(characterRange) - 1
        if lastIndex >= 0 && lastIndex < text.length && text.character(at: lastIndex) == newline {
            lineNumber += 1
        }
    }

    private func drawLabel(_ label: String, attributes: [NSAttributedString.Key: Any],
                            lineRect: CGRect, insetY: CGFloat, visibleRect: CGRect,
                            lineNumber: Int, luaTextView: LuaTextView? = nil) {
        let y = lineRect.minY + insetY - visibleRect.minY
        let midY = y + lineRect.height / 2

        // Fold triangle - fixed on the left so it never overlaps line numbers
        if let tv = luaTextView, tv.isFoldable(lineNum: lineNumber, in: tv.string) {
            let isFolded = tv.foldedLines.contains(lineNumber)
            let triSize: CGFloat = 6
            let triX: CGFloat = 5
            theme.lineNumber.withAlphaComponent(0.60).setFill()
            let path = NSBezierPath()
            if isFolded {
                path.move(to: NSPoint(x: triX, y: midY - triSize / 2))
                path.line(to: NSPoint(x: triX, y: midY + triSize / 2))
                path.line(to: NSPoint(x: triX + triSize, y: midY))
            } else {
                path.move(to: NSPoint(x: triX, y: midY + triSize / 2))
                path.line(to: NSPoint(x: triX + triSize, y: midY + triSize / 2))
                path.line(to: NSPoint(x: triX + triSize / 2, y: midY - triSize / 2))
            }
            path.close()
            path.fill()
        }

        // Breakpoint dot (takes priority over the diagnostic marker on a line)
        if let bp = breakpoints, bp.has(file: currentFile, line: lineNumber) {
            NSColor.systemRed.setFill()
            let dotSize: CGFloat = 7
            let dotX = bounds.minX + 4
            let dotY = midY - dotSize / 2
            NSBezierPath(ovalIn: CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize)).fill()
        } else if let severity = diagnosticLines[lineNumber] {
            // Diagnostic marker: a small diamond, red for errors, yellow for warnings.
            (severity == .warning ? NSColor.systemYellow : NSColor.systemRed).setFill()
            let s: CGFloat = 6
            let cx = bounds.minX + 4 + 3.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: cx, y: midY - s / 2))
            path.line(to: NSPoint(x: cx + s / 2, y: midY))
            path.line(to: NSPoint(x: cx, y: midY + s / 2))
            path.line(to: NSPoint(x: cx - s / 2, y: midY))
            path.close()
            path.fill()
        }

        let nsLabel = label as NSString
        let size = nsLabel.size(withAttributes: attributes)
        let labelRect = CGRect(x: bounds.maxX - size.width - rightPad,
                               y: y + (lineRect.height - size.height) / 2,
                               width: size.width, height: size.height)
        nsLabel.draw(in: labelRect, withAttributes: attributes)
    }
}
