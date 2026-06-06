import SwiftUI

// MARK: - Pixel Background (stars + shooting stars + blocks + pixel rain)

private let pico8Colors: [NSColor] = [
    NSColor(red: 0.16, green: 0.68, blue: 1.00, alpha: 1), // cyan
    NSColor(red: 1.00, green: 0.93, blue: 0.15, alpha: 1), // yellow
    NSColor(red: 0.00, green: 0.89, blue: 0.21, alpha: 1), // green
    NSColor(red: 1.00, green: 0.47, blue: 0.66, alpha: 1), // pink
    NSColor(red: 0.51, green: 0.46, blue: 0.61, alpha: 1), // purple
    NSColor(red: 1.00, green: 0.00, blue: 0.30, alpha: 1), // red
    NSColor(red: 1.00, green: 0.64, blue: 0.00, alpha: 1), // orange
]

private let blockShapes: [[[Int]]] = [
    [[1,1,1,1]],
    [[1,1],[1,1]],
    [[1,0],[1,0],[1,1]],
    [[1,1,1],[0,1,0]],
    [[0,1,1],[1,1,0]],
    [[1]],
    [[1],[1]],
]

private struct BgStar {
    var x, y: CGFloat
    var size: CGFloat
    var alpha: CGFloat
    var twinkleSpeed: CGFloat
    var twinkleDir: CGFloat
}

private struct BgShooter {
    var x, y: CGFloat
    var len: Int
    var speed: CGFloat
    var alpha: CGFloat
    var dead: Bool
}

private struct BgBlock {
    var x, y: CGFloat
    var shape: [[Int]]
    var color: NSColor
    var alpha: CGFloat
    var vy, vx: CGFloat
    var rot, rotSpeed: CGFloat
}

private struct BgRainCol {
    var x, y: CGFloat
    var speed: CGFloat
    var len: Int
    var chars: [Character]
    var alpha: CGFloat
    var color: NSColor
    var timer: Int
    var updateEvery: Int
}

private let rainChars = Array("01アイウエオカキクケコサシスセソタチツテト")

private struct PixelBgView: NSViewRepresentable {
    func makeNSView(context: Context) -> PixelBgNSView { PixelBgNSView() }
    func updateNSView(_ v: PixelBgNSView, context: Context) {}
}

final class PixelBgNSView: NSView {
    private let px: CGFloat = 4
    private var stars:    [BgStar]     = []
    private var shooters: [BgShooter]  = []
    private var blocks:   [BgBlock]    = []
    private var rain:     [BgRainCol]  = []
    private var displayLink: CVDisplayLink?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { setup(); startLink() }
        else { stopLink() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func setup() {
        let W = bounds.width, H = bounds.height
        guard W > 0, H > 0 else { return }

        stars = (0..<60).map { _ in
            BgStar(x: CGFloat.random(in: 0...W), y: CGFloat.random(in: 0...H),
                   size: Bool.random() ? px : px*2,
                   alpha: CGFloat.random(in: 0.2...0.8),
                   twinkleSpeed: CGFloat.random(in: 0.005...0.02),
                   twinkleDir: 1)
        }
        blocks = (0..<22).map { _ in makeBlock(W: W, H: H) }
        rain   = (0..<10).map { _ in makeRain(W: W, H: H) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8)  { [weak self] in self?.addShooter() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2)  { [weak self] in self?.addShooter() }
    }

    private func makeBlock(W: CGFloat, H: CGFloat) -> BgBlock {
        BgBlock(x: CGFloat.random(in: 0...W),
                y: CGFloat.random(in: -200...H+200),
                shape: blockShapes.randomElement()!,
                color: pico8Colors.randomElement()!,
                alpha: CGFloat.random(in: 0.18...0.45),
                vy: CGFloat.random(in: 0.5...1.4),
                vx: CGFloat.random(in: -0.2...0.2),
                rot: CGFloat.random(in: 0...CGFloat.pi*2),
                rotSpeed: CGFloat.random(in: -0.008...0.008))
    }

    private func makeRain(W: CGFloat, H: CGFloat) -> BgRainCol {
        let col = pico8Colors.randomElement()!
        return BgRainCol(
            x: (CGFloat.random(in: 0...W) / px).rounded() * px,
            y: CGFloat.random(in: -300...0),
            speed: CGFloat.random(in: 0.4...1.2),
            len: Int.random(in: 5...18),
            chars: (0..<20).map { _ in rainChars.randomElement()! },
            alpha: CGFloat.random(in: 0.06...0.14),
            color: col,
            timer: 0,
            updateEvery: Int.random(in: 8...20))
    }

    private func addShooter() {
        let W = bounds.width, H = bounds.height
        guard W > 0 else { return }
        shooters.append(BgShooter(
            x: (CGFloat.random(in: 0...W) / px).rounded() * px,
            y: (CGFloat.random(in: 0...H*0.6) / px).rounded() * px,
            len: Int.random(in: 4...10),
            speed: CGFloat.random(in: 3...7),
            alpha: CGFloat.random(in: 0.5...0.9),
            dead: false))
    }

    private func startLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let dl = displayLink else { return }
        CVDisplayLinkSetOutputCallback(dl, { _, _, _, _, _, ctx in
            let v = Unmanaged<PixelBgNSView>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { v.tick(); v.needsDisplay = true }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(dl)
    }

    private func stopLink() {
        if let dl = displayLink { CVDisplayLinkStop(dl) }
    }

    private func tick() {
        let W = bounds.width, H = bounds.height
        // Stars twinkle
        for i in stars.indices {
            stars[i].alpha += stars[i].twinkleSpeed * stars[i].twinkleDir
            if stars[i].alpha >= 0.85 || stars[i].alpha <= 0.08 { stars[i].twinkleDir *= -1 }
        }
        // Shooters
        for i in (0..<shooters.count).reversed() {
            shooters[i].x += shooters[i].speed
            shooters[i].y += shooters[i].speed * 0.5
            if shooters[i].x > W+100 || shooters[i].y > H+100 {
                shooters.remove(at: i)
                let delay = Double.random(in: 1.5...5.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.addShooter() }
            }
        }
        // Blocks
        for i in blocks.indices {
            blocks[i].y += blocks[i].vy
            blocks[i].x += blocks[i].vx
            blocks[i].rot += blocks[i].rotSpeed
            if blocks[i].y > H+200 { blocks[i].y = -120 }
            if blocks[i].x < -100  { blocks[i].x = W+100 }
            if blocks[i].x > W+100 { blocks[i].x = -100  }
        }
        // Rain
        for i in rain.indices {
            rain[i].timer += 1
            if rain[i].timer >= rain[i].updateEvery {
                rain[i].timer = 0
                let idx = Int.random(in: 0..<rain[i].chars.count)
                rain[i].chars[idx] = rainChars.randomElement()!
            }
            rain[i].y += rain[i].speed
            let colH = CGFloat(rain[i].len) * px * 3
            if rain[i].y > H + colH {
                rain[i].y = -colH
                rain[i].x = (CGFloat.random(in: 0...W) / px).rounded() * px
                rain[i].speed = CGFloat.random(in: 0.4...1.2)
                rain[i].color = pico8Colors.randomElement()!
            }
        }
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let W = bounds.width, H = bounds.height
        let dark = isDark

        // In light mode boost alpha so elements are visible on light background
        let alphaScale: CGFloat = dark ? 1.0 : 2.2

        // Flip to top-left origin so everything falls downward
        ctx.saveGState()
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)

        // Stars - dark in light mode, light in dark mode
        let starWhite: CGFloat = dark ? 0.97 : 0.1
        for s in stars {
            ctx.setFillColor(NSColor(white: starWhite, alpha: min(1, s.alpha * alphaScale)).cgColor)
            ctx.fill(CGRect(x: (s.x/px).rounded()*px, y: (s.y/px).rounded()*px,
                            width: s.size, height: s.size))
        }

        // Shooting stars
        let shooterWhite: CGFloat = dark ? 0.95 : 0.05
        for s in shooters {
            for t in 0..<s.len {
                let fade = pow(CGFloat(s.len - t) / CGFloat(s.len), 2)
                ctx.setFillColor(NSColor(white: shooterWhite, alpha: min(1, s.alpha * fade * alphaScale)).cgColor)
                ctx.fill(CGRect(x: ((s.x - CGFloat(t)*px)/px).rounded()*px,
                                y: ((s.y - CGFloat(t)*px*0.5)/px).rounded()*px,
                                width: px, height: px))
            }
        }

        // Blocks
        let bpx: CGFloat = 10
        for b in blocks {
            ctx.saveGState()
            ctx.translateBy(x: b.x, y: b.y)
            ctx.rotate(by: b.rot)
            let blockAlpha = min(1.0, b.alpha * alphaScale)
            for (row, rowArr) in b.shape.enumerated() {
                for (col, filled) in rowArr.enumerated() {
                    guard filled == 1 else { continue }
                    let bx = CGFloat(col) * bpx
                    let by = CGFloat(row) * bpx
                    ctx.setFillColor(b.color.withAlphaComponent(blockAlpha).cgColor)
                    ctx.fill(CGRect(x: bx, y: by, width: bpx-1, height: bpx-1))
                    // highlight / shadow adjust per theme
                    let hlColor = dark ? NSColor.white : NSColor.white
                    let shColor = dark ? NSColor.black : NSColor.black
                    ctx.setFillColor(hlColor.withAlphaComponent(0.35 * blockAlpha).cgColor)
                    ctx.fill(CGRect(x: bx, y: by, width: bpx-1, height: 2))
                    ctx.fill(CGRect(x: bx, y: by, width: 2, height: bpx-1))
                    ctx.setFillColor(shColor.withAlphaComponent(0.5 * blockAlpha).cgColor)
                    ctx.fill(CGRect(x: bx, y: by+bpx-3, width: bpx-1, height: 2))
                    ctx.fill(CGRect(x: bx+bpx-3, y: by, width: 2, height: bpx-1))
                }
            }
            ctx.restoreGState()
        }

        // Pixel rain - darker tones in light mode
        let font = NSFont.monospacedSystemFont(ofSize: px*2.5, weight: .bold)
        for col in rain {
            for i in 0..<col.len {
                let charAlpha = min(1, col.alpha * alphaScale * (CGFloat(col.len - i) / CGFloat(col.len)))
                let rainColor = dark ? col.color : col.color.blended(withFraction: 0.4, of: .black) ?? col.color
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: rainColor.withAlphaComponent(charAlpha)
                ]
                let ch = String(col.chars[i % col.chars.count])
                let x = (col.x/px).rounded()*px
                let y = (col.y + CGFloat(i) * px * 3)
                ch.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            }
        }

        ctx.restoreGState()
    }
}

struct WelcomeView: View {

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var showNewProjectSheet = false

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            Divider()
            rightPanel
        }
        .background(.windowBackground)
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectView { url in
                openProject(url: url)
            }
        }
    }

    // MARK: Left Panel - Branding

    private var leftPanel: some View {
        ZStack {
            // Animated pixel background
            PixelBgView()
                .frame(width: 260)
                .frame(maxHeight: .infinity)
                .clipped()

            // Subtle dark overlay so text stays readable
            LinearGradient(
                colors: [
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.15),
                    Color.black.opacity(0.35),
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Content
            VStack(alignment: .center, spacing: 8) {
                Spacer()

                Image(systemName: "heart.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.pink)
                    .shadow(color: .pink.opacity(0.6), radius: 12)

                Text("LÖVE Studio")
                    .font(.largeTitle.bold())
                    .shadow(color: .black.opacity(0.4), radius: 4)

                Text("Make games, not engines.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()

                Text("Version 1.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(36)
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: Right Panel - Actions + Recents

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionButtons
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 20)

            Divider()

            recentProjectsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            WelcomeActionButton(
                icon: "plus.square.fill",
                title: "New Project",
                subtitle: "Create a new LÖVE game project"
            ) {
                createNewProject()
            }

            WelcomeActionButton(
                icon: "folder.fill",
                title: "Open Project",
                subtitle: "Open an existing project folder"
            ) {
                openExistingProject()
            }
        }
    }

    private var recentProjectsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Projects")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if RecentProjectsStore.shared.projects.isEmpty {
                Text("No recent projects")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(RecentProjectsStore.shared.projects) { entry in
                            RecentProjectRow(entry: entry) {
                                if let url = entry.accessURL() {
                                    openProject(url: url)
                                }
                            }
                            .contextMenu {
                                Button("Remove from Recents") {
                                    RecentProjectsStore.shared.remove(id: entry.id)
                                }
                                Button("Show in Finder") {
                                    if let url = entry.resolveBookmark() {
                                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: Actions

    private func createNewProject() {
        showNewProjectSheet = true
    }

    private func openExistingProject() {
        let panel = NSOpenPanel()
        panel.title = "Open LÖVE Project"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url: url)
    }

    private func openProject(url: URL) {
        // Sacuvaj bookmark dok imamo security scope (pre WindowGroup serijalizacije)
        let tempProject = Project(rootURL: url)
        tempProject.saveBookmark()

        RecentProjectsStore.shared.add(url: url)
        openWindow(id: "studio", value: url)
        dismissWindow(id: "welcome")
    }
}

// MARK: - WelcomeActionButton

private struct WelcomeActionButton: View {

    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.pink)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - RecentProjectRow

private struct RecentProjectRow: View {

    let entry: RecentProjectEntry
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.pink.opacity(0.8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)
                        .lineLimit(1)
                    Text(entry.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview {
    WelcomeView()
        .frame(width: 760, height: 460)
}
