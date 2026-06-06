import AppKit

// MARK: - Suggestion model

struct CompletionSuggestion: Equatable {
    let label: String   // displayed text
    let insert: String  // text inserted into editor

    enum Kind { case keyword, function, loveAPI, stdlib, other }

    var kind: Kind {
        if label.hasPrefix("love.")  { return .loveAPI }
        let kws: Set<String> = ["and","break","do","else","elseif","end","false","for",
            "function","goto","if","in","local","nil","not","or","repeat","return",
            "then","true","until","while"]
        if kws.contains(label)       { return .keyword }
        if insert.contains("()")     { return .function }
        if label.contains(".")       { return .stdlib }
        return .other
    }

    var kindLetter: String {
        switch kind {
        case .keyword:  return "K"
        case .function: return "f"
        case .loveAPI:  return "L"
        case .stdlib:   return "S"
        case .other:    return "v"
        }
    }

    var kindColor: NSColor {
        switch kind {
        case .keyword:  return NSColor(calibratedRed: 0.45, green: 0.68, blue: 0.90, alpha: 1)
        case .function: return NSColor(calibratedRed: 0.85, green: 0.75, blue: 0.40, alpha: 1)
        case .loveAPI:  return NSColor(calibratedRed: 0.95, green: 0.40, blue: 0.55, alpha: 1)
        case .stdlib:   return NSColor(calibratedRed: 0.45, green: 0.85, blue: 0.72, alpha: 1)
        case .other:    return NSColor(calibratedRed: 0.70, green: 0.60, blue: 0.90, alpha: 1)
        }
    }
}

// MARK: - CompletionPanel

final class CompletionPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    static let shared = CompletionPanel()

    // Callbacks
    var onAccept: ((CompletionSuggestion) -> Void)?
    var onDismiss: (() -> Void)?

    // State
    private(set) var isVisible = false
    private var completions: [CompletionSuggestion] = []
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var appMonitorTokens: [NSObjectProtocol] = []

    // Views
    private var panel: NSPanel?
    private var tableView: NSTableView?
    private var scrollView: NSScrollView?

    // Sizing
    private let rowH: CGFloat   = 24
    private let panelW: CGFloat = 315
    private let maxRows         = 10

    // Anchor — keeps the correct edge fixed when list resizes
    private var anchorIsBottom = false  // true → popup is above cursor, anchor = bottom edge
    private var anchorX: CGFloat = 0
    private var anchorY: CGFloat = 0

    // MARK: Public API

    func show(completions: [CompletionSuggestion],
              cursorScreenRect: NSRect) {
        guard !completions.isEmpty else { dismiss(); return }
        self.completions = completions

        if panel == nil { buildPanel() }

        let h = panelHeight()

        // Decide position: prefer below cursor, fall back to above
        let belowOrigin = NSPoint(x: cursorScreenRect.minX,
                                  y: cursorScreenRect.minY - h - 2)
        if let screen = NSScreen.main, belowOrigin.y < screen.visibleFrame.minY {
            // Show above cursor — anchor = bottom of panel
            anchorIsBottom = true
            anchorX = cursorScreenRect.minX
            anchorY = cursorScreenRect.maxY + 2        // bottom edge of panel
        } else {
            // Show below cursor — anchor = top of panel
            anchorIsBottom = false
            anchorX = cursorScreenRect.minX
            anchorY = cursorScreenRect.minY - 2        // top edge of panel
        }

        applyFrame(height: h)
        tableView?.reloadData()
        tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        panel?.orderFront(nil)
        isVisible = true
        startMouseMonitor()
        startAppMonitor()
    }

    func update(completions: [CompletionSuggestion]) {
        guard isVisible else { return }
        if completions.isEmpty { dismiss(); return }
        self.completions = completions
        applyFrame(height: panelHeight())
        tableView?.reloadData()
        tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    func dismiss() {
        panel?.orderOut(nil)
        isVisible = false
        completions = []
        stopMouseMonitor()
        stopAppMonitor()
        onDismiss?()
    }

    func moveSelection(by delta: Int) {
        guard let tv = tableView, !completions.isEmpty else { return }
        let next = max(0, min(completions.count - 1, tv.selectedRow + delta))
        tv.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tv.scrollRowToVisible(next)
    }

    func acceptCurrentSelection() {
        guard let tv = tableView,
              tv.selectedRow >= 0,
              tv.selectedRow < completions.count else { dismiss(); return }
        let suggestion = completions[tv.selectedRow]
        let handler = onAccept
        dismiss()
        handler?(suggestion)
    }

    // MARK: Layout

    private func panelHeight() -> CGFloat {
        CGFloat(min(completions.count, maxRows)) * rowH + 20
    }

    private func applyFrame(height: CGFloat) {
        let originY: CGFloat
        if anchorIsBottom {
            originY = anchorY                   // panel's bottom = anchorY (above cursor)
        } else {
            originY = anchorY - height          // panel's top = anchorY (below cursor)
        }
        let frame = NSRect(x: anchorX, y: originY, width: panelW, height: height)
        panel?.setFrame(frame, display: false)
        scrollView?.frame = panel?.contentView?.bounds ?? .zero
    }

    // MARK: Build

    private func buildPanel() {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: true)
        p.isOpaque        = false
        p.hasShadow       = true
        p.level           = .popUpMenu
        p.isMovable       = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false

        // Blur background
        let blur = NSVisualEffectView()
        blur.material     = .menu
        blur.blendingMode = .behindWindow
        blur.state        = .active
        blur.wantsLayer   = true
        blur.layer?.cornerRadius   = 8
        blur.layer?.masksToBounds  = true
        p.contentView = blur

        // Border
        let border = CALayer()
        border.borderColor  = NSColor.white.withAlphaComponent(0.10).cgColor
        border.borderWidth  = 0.5
        border.cornerRadius = 8
        blur.layer?.addSublayer(border)
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: blur, queue: .main) { _ in
            border.frame = blur.bounds
        }
        blur.postsFrameChangedNotifications = true

        // ScrollView
        let sv = NSScrollView()
        sv.hasVerticalScroller   = true
        sv.autohidesScrollers    = true
        sv.borderType            = .noBorder
        sv.backgroundColor       = .clear
        sv.drawsBackground       = false
        blur.addSubview(sv)

        // TableView
        let tv = NSTableView()
        tv.backgroundColor          = .clear
        tv.intercellSpacing         = .zero
        tv.selectionHighlightStyle  = .regular
        tv.headerView               = nil
        tv.rowHeight                = rowH
        tv.dataSource               = self
        tv.delegate                 = self
        tv.target                   = self
        tv.doubleAction             = #selector(doubleClicked)
        tv.columnAutoresizingStyle  = .uniformColumnAutoresizingStyle
        tv.usesAutomaticRowHeights  = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.isEditable = false
        tv.addTableColumn(col)
        sv.documentView = tv

        panel     = p
        scrollView = sv
        tableView  = tv
    }

    @objc private func doubleClicked() { acceptCurrentSelection() }

    // MARK: Mouse monitor

    private func startMouseMonitor() {
        guard mouseMonitor == nil else { return }
        // Global: clicks outside the app
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.dismiss()
        }
        // Local: clicks inside the app (e.g. text editor, sidebar)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if let panel = self.panel, !panel.frame.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
            return event
        }
    }

    private func stopMouseMonitor() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
    }

    private func startAppMonitor() {
        guard appMonitorTokens.isEmpty else { return }
        let nc = NotificationCenter.default
        // App resigned active (Alt+Tab, Cmd+Tab, clicking another app)
        let t1 = nc.addObserver(forName: NSApplication.didResignActiveNotification,
                                object: nil, queue: .main) { [weak self] _ in
            self?.dismiss()
        }
        // Key window changed (e.g. a sheet or another window took focus)
        let t2 = nc.addObserver(forName: NSWindow.didResignKeyNotification,
                                object: nil, queue: .main) { [weak self] _ in
            self?.dismiss()
        }
        appMonitorTokens = [t1, t2]
    }

    private func stopAppMonitor() {
        appMonitorTokens.forEach { NotificationCenter.default.removeObserver($0) }
        appMonitorTokens = []
    }

    // MARK: NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { completions.count }

    // MARK: NSTableViewDelegate

    func tableView(_ tableView: NSTableView,
                   viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard row < completions.count else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? CompletionCell)
                   ?? CompletionCell(identifier: id)
        cell.configure(with: completions[row])
        return cell
    }

    func tableView(_ tableView: NSTableView,
                   rowViewForRow row: Int) -> NSTableRowView? {
        CompletionRowView()
    }
}

// MARK: - Row highlight

private final class CompletionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1),
                                xRadius: 5, yRadius: 5)
        NSColor.controlAccentColor.withAlphaComponent(0.30).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.60).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

// MARK: - Cell

final class CompletionCell: NSView {

    private let badge = NSView()
    private let badgeLetter = NSTextField(labelWithString: "")
    private let nameLabel   = NSTextField(labelWithString: "")
    private let typeLabel   = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        badge.wantsLayer       = true
        badge.layer?.cornerRadius = 4

        badgeLetter.font      = .systemFont(ofSize: 9, weight: .bold)
        badgeLetter.alignment = .center

        nameLabel.font          = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.truncatesLastVisibleLine = true

        typeLabel.font      = .systemFont(ofSize: 10.5)
        typeLabel.alignment = .right
        typeLabel.lineBreakMode = .byTruncatingTail

        addSubview(badge)
        badge.addSubview(badgeLetter)
        addSubview(nameLabel)
        addSubview(typeLabel)
    }

    func configure(with s: CompletionSuggestion) {
        let c = s.kindColor
        badge.layer?.backgroundColor = c.withAlphaComponent(0.18).cgColor
        badgeLetter.stringValue = s.kindLetter
        badgeLetter.textColor   = c
        nameLabel.stringValue   = s.label
        nameLabel.textColor     = .labelColor

        // Right-side type hint
        let hint: String
        switch s.kind {
        case .keyword:  hint = "keyword"
        case .function: hint = "func"
        case .loveAPI:  hint = "LÖVE"
        case .stdlib:   hint = "stdlib"
        case .other:    hint = "var"
        }
        typeLabel.stringValue = hint
        typeLabel.textColor   = NSColor.secondaryLabelColor
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let badgeSize: CGFloat = 16
        let leftPad: CGFloat   = 6
        let gap: CGFloat       = 6
        let rightPad: CGFloat  = 6
        let typeW: CGFloat     = 48

        badge.frame       = CGRect(x: leftPad, y: (h - badgeSize) / 2,
                                   width: badgeSize, height: badgeSize)
        badgeLetter.frame = badge.bounds

        let nameX = leftPad + badgeSize + gap
        let nameW = bounds.width - nameX - typeW - rightPad
        nameLabel.frame = CGRect(x: nameX, y: (h - 16) / 2,
                                 width: nameW, height: 16)
        typeLabel.frame = CGRect(x: bounds.width - typeW - rightPad,
                                 y: (h - 13) / 2,
                                 width: typeW, height: 13)
    }
}
