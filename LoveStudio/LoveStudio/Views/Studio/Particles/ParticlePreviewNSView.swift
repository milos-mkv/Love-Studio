import AppKit

// MARK: - Preview background

enum ParticlePreviewBackground: String, CaseIterable {
    case dark, light, checkerboard

    var icon: String {
        switch self {
        case .dark:         return "moon.fill"
        case .light:        return "sun.max.fill"
        case .checkerboard: return "checkerboard.rectangle"
        }
    }
}

// MARK: - Particle instance

private struct Particle {
    var x, y: Float
    var vx, vy: Float
    var age: Float
    var lifetime: Float
    var startSize: Float
    var endSize: Float
    var rotation: Float
    var rotSpeed: Float
    var sr, sg, sb, sa: Float
    var er, eg, eb, ea: Float
    var sizeCurve: Float
    var alphaCurve: Float

    var t: Float { min(age / max(lifetime, 0.001), 1) }

    private func applyCurve(_ t: Float, curve: Float) -> Float {
        let ct = 1 - t
        return ct * ct * 0 + 2 * ct * t * curve + t * t * 1
    }

    var currentSize: CGFloat {
        let ct = applyCurve(t, curve: sizeCurve)
        return CGFloat(startSize + (endSize - startSize) * ct)
    }

    var currentColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let ct = applyCurve(t, curve: t)
        let at = applyCurve(t, curve: alphaCurve)
        return (CGFloat(sr+(er-sr)*ct), CGFloat(sg+(eg-sg)*ct), CGFloat(sb+(eb-sb)*ct), CGFloat(sa+(ea-sa)*at))
    }
}

// MARK: - Preview view

final class ParticlePreviewNSView: NSView {

    var config: ParticleSystemConfig = ParticleSystemConfig() {
        didSet { reset() }
    }

    var textureImage: NSImage? = nil {
        didSet {
            cachedCGImage = textureImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            needsDisplay = true
        }
    }

    var background: ParticlePreviewBackground = .dark {
        didSet { needsDisplay = true }
    }

    private var cachedCGImage: CGImage?
    private var particles: [Particle] = []
    private var emitAccum: Double = 0
    private var hasBurst: Bool = false
    private var lastFireDate: TimeInterval = 0
    private var timer: Timer?

    // Emitter position; negative = use view center
    private var emitterX: Float = -1
    private var emitterY: Float = -1

    private lazy var labelAttrs: [NSAttributedString.Key: Any] = {
        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            as NSFont? ?? NSFont.systemFont(ofSize: 10)
        return [
            .font:            font,
            .foregroundColor: NSColor(white: 1, alpha: 0.35)
        ]
    }()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { stop() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        start()
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Visibility / window lifecycle

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stop() }
    }

    override func viewDidMoveToWindow() {
        if window != nil { start() }
    }

    // MARK: - Mouse (drag emitter)

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            emitterX = -1; emitterY = -1   // double-click → reset to center
        } else {
            updateEmitter(event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        updateEmitter(event)
    }

    private func updateEmitter(_ event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        emitterX = Float(min(max(loc.x, 0), bounds.width))
        emitterY = Float(min(max(loc.y, 0), bounds.height))
    }

    // MARK: - Control

    func start() {
        guard timer == nil else { return }
        timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            self?.tick(fireDate: t.fireDate.timeIntervalSinceReferenceDate)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }

    func reset() {
        particles.removeAll()
        emitAccum    = 0
        hasBurst     = false
        lastFireDate = 0
    }

    // MARK: - Simulation

    private func tick(fireDate: TimeInterval) {
        let dt = lastFireDate == 0 ? 0.016 : Float(fireDate - lastFireDate)
        lastFireDate = fireDate
        guard dt > 0 && dt < 0.1 else { return }

        let dampFactor: Float = config.damping > 0
            ? max(0, 1.0 - Float(config.damping) * dt)
            : 1.0

        let cx = emitterX >= 0 ? emitterX : Float(bounds.midX)
        let cy = emitterY >= 0 ? emitterY : Float(bounds.midY)

        particles = particles.compactMap { p in
            var p = p
            p.age += dt
            guard p.age < p.lifetime else { return nil }
            p.vx += Float(config.gravityX) * dt
            p.vy -= Float(config.gravityY) * dt
            if config.attractRepelStrength != 0 {
                let dx = cx - p.x
                let dy = cy - p.y
                let dist = max(1, sqrt(dx*dx + dy*dy))
                let force = Float(config.attractRepelStrength) / dist
                p.vx += (dx / dist) * force * dt
                p.vy += (dy / dist) * force * dt
            }
            if dampFactor < 1 { p.vx *= dampFactor; p.vy *= dampFactor }
            p.x  += p.vx * dt
            p.y  += p.vy * dt
            p.rotation += p.rotSpeed * dt
            return p
        }

        if config.isBurst {
            if !hasBurst {
                for _ in 0 ..< config.burstCount {
                    particles.append(spawnParticle(cx: cx, cy: cy))
                }
                hasBurst = true
            }
        } else if particles.count < config.maxParticles {
            emitAccum += Double(config.emissionRate) * Double(dt)
            let toEmit = min(Int(emitAccum), config.maxParticles - particles.count)
            emitAccum -= Double(toEmit)
            for _ in 0 ..< toEmit { particles.append(spawnParticle(cx: cx, cy: cy)) }
        }

        needsDisplay = true
    }

    private func spawnParticle(cx: Float, cy: Float) -> Particle {
        let dirRad     = Float(config.directionDeg * .pi / 180.0)
        let halfSpread = Float(config.spreadDeg    * .pi / 180.0)
        let angle      = dirRad + Float.random(in: -halfSpread ... halfSpread)
        let speed      = Float.random(in: Float(config.speedMin) ... max(Float(config.speedMin), Float(config.speedMax)))
        let life       = Float.random(in: Float(config.lifetimeMin) ... max(Float(config.lifetimeMin), Float(config.lifetimeMax)))

        let varFactor: Float = config.sizeVariation > 0
            ? 1.0 + Float.random(in: -Float(config.sizeVariation) ... Float(config.sizeVariation))
            : 1.0

        var spawnX = cx, spawnY = cy
        switch config.emitterShape {
        case .point:
            break
        case .circle:
            let r = Float(config.emitterRadius)
            let ea2 = Float.random(in: 0 ..< .pi * 2)
            spawnX = cx + cos(ea2) * r
            spawnY = cy + sin(ea2) * r
        case .line:
            let half = Float(config.emitterLineLength / 2)
            spawnX = cx + Float.random(in: -half...half)
        case .rect:
            let hw = Float(config.emitterRectW / 2)
            let hh = Float(config.emitterRectH / 2)
            spawnX = cx + Float.random(in: -hw...hw)
            spawnY = cy + Float.random(in: -hh...hh)
        }

        return Particle(
            x: spawnX, y: spawnY,
            vx: cos(angle) * speed,
            vy: sin(angle) * speed,
            age: 0, lifetime: life,
            startSize: max(0.5, Float(config.sizeStart) * varFactor),
            endSize:   max(0,   Float(config.sizeEnd)   * varFactor),
            rotation: Float.random(in: 0 ..< .pi * 2),
            rotSpeed: Float.random(
                in: Float(config.rotSpeedMinDeg * .pi / 180.0) ...
                    max(Float(config.rotSpeedMinDeg * .pi / 180.0), Float(config.rotSpeedMaxDeg * .pi / 180.0))
            ),
            sr: Float(config.colorStartR), sg: Float(config.colorStartG),
            sb: Float(config.colorStartB), sa: Float(config.colorStartA),
            er: Float(config.colorEndR),   eg: Float(config.colorEndG),
            eb: Float(config.colorEndB),   ea: Float(config.colorEndA),
            sizeCurve:  Float(config.sizeCurve),
            alphaCurve: Float(config.alphaCurve)
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background
        drawBackground(ctx)

        // Particles - apply blend mode
        ctx.saveGState()
        ctx.setBlendMode(config.blendMode.cgBlendMode)

        for p in particles {
            let c  = p.currentColor
            guard c.a > 0.01 else { continue }
            let sz = max(p.currentSize, 0.5)

            ctx.saveGState()
            ctx.translateBy(x: CGFloat(p.x), y: CGFloat(p.y))
            ctx.rotate(by: CGFloat(p.rotation))

            if let cg = cachedCGImage {
                let r = CGRect(x: -sz/2, y: -sz/2, width: sz, height: sz)
                let hasCustomTexture = !(config.textureName ?? "").isEmpty
                if hasCustomTexture {
                    // Custom image: draw as-is with particle alpha fade only.
                    ctx.saveGState()
                    ctx.setAlpha(c.a)
                    ctx.draw(cg, in: r)
                    ctx.restoreGState()
                } else {
                    // Procedural shape (white canvas): use image as alpha mask
                    // and fill with the particle color - matches LÖVE setColors tinting.
                    ctx.saveGState()
                    ctx.setAlpha(c.a)
                    ctx.clip(to: r, mask: cg)
                    ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: 1.0)
                    ctx.fill(r)
                    ctx.restoreGState()
                }
            } else {
                drawShape(ctx, size: sz, color: c, shape: config.shape)
            }
            ctx.restoreGState()
        }

        ctx.restoreGState()  // restore blend mode

        // Crosshair at emitter position
        let ex = emitterX >= 0 ? CGFloat(emitterX) : bounds.midX
        let ey = emitterY >= 0 ? CGFloat(emitterY) : bounds.midY
        let crossColor: CGFloat = background == .light ? 0.0 : 1.0
        ctx.setStrokeColor(NSColor(white: crossColor, alpha: 0.30).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: ex-10, y: ey)); ctx.addLine(to: CGPoint(x: ex+10, y: ey))
        ctx.move(to: CGPoint(x: ex, y: ey-10)); ctx.addLine(to: CGPoint(x: ex, y: ey+10))
        ctx.strokePath()

        // Particle count label
        let burstDone  = config.isBurst && hasBurst
        let countLabel = "\(particles.count) particles\(burstDone ? "  (burst done)" : "")"
        let hintLabel  = emitterX >= 0 ? "dbl-click to reset emitter" : "click to move emitter"

        var labelColor: NSColor
        switch background {
        case .dark:         labelColor = NSColor(white: 1, alpha: 0.35)
        case .light:        labelColor = NSColor(white: 0, alpha: 0.40)
        case .checkerboard: labelColor = NSColor(white: 1, alpha: 0.60)
        }

        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular) as NSFont?
            ?? NSFont.systemFont(ofSize: 10)
        let darkBg = NSColor(white: 0, alpha: 0.35)

        let countAttr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: labelColor]
        let hintAttr:  [NSAttributedString.Key: Any] = [.font: font,
                         .foregroundColor: NSColor(white: 0.7, alpha: 0.45)]

        // Small dark pill behind count
        let countSize = (countLabel as NSString).size(withAttributes: countAttr)
        let pill = CGRect(x: 6, y: 4, width: countSize.width + 8, height: countSize.height + 4)
        ctx.setFillColor(darkBg.cgColor)
        let path = CGPath(roundedRect: pill, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path); ctx.fillPath()

        (countLabel as NSString).draw(at: CGPoint(x: 10, y: 6), withAttributes: countAttr)
        (hintLabel  as NSString).draw(at: CGPoint(x: 10, y: pill.maxY + 3), withAttributes: hintAttr)
    }

    // MARK: - Shape drawing

    private func drawShape(_ ctx: CGContext, size: CGFloat,
                            color c: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
                            shape: ParticleShape) {
        let half = size / 2
        switch shape {

        case .circle:
            ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
            ctx.fillEllipse(in: CGRect(x: -half, y: -half, width: size, height: size))

        case .square:
            ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
            ctx.fill(CGRect(x: -half, y: -half, width: size, height: size))

        case .triangle:
            ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
            let p = CGMutablePath()
            p.move(to: .init(x: 0, y: half))
            p.addLine(to: .init(x: -half, y: -half))
            p.addLine(to: .init(x:  half, y: -half))
            p.closeSubpath()
            ctx.addPath(p); ctx.fillPath()

        case .star:
            ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
            ctx.addPath(makeStarPath(size: size)); ctx.fillPath()

        case .ring:
            let lw = max(size * 0.22, 1.5)
            ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
            ctx.setLineWidth(lw)
            let inset = lw / 2
            ctx.strokeEllipse(in: CGRect(x: -half + inset, y: -half + inset,
                                          width: size - lw, height: size - lw))

        case .diamond:
            ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
            let p = CGMutablePath()
            p.move(to: .init(x: 0,    y:  half))
            p.addLine(to: .init(x:  half, y:  0))
            p.addLine(to: .init(x: 0,    y: -half))
            p.addLine(to: .init(x: -half, y:  0))
            p.closeSubpath()
            ctx.addPath(p); ctx.fillPath()
        }
    }

    private func makeStarPath(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let outer = size / 2
        let inner = outer * 0.42
        let n = 5
        for i in 0 ..< n * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(n) - .pi / 2
            let r = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    private func drawBackground(_ ctx: CGContext) {
        switch background {
        case .dark:
            ctx.setFillColor(NSColor(white: 0.06, alpha: 1).cgColor)
            ctx.fill(bounds)
            ctx.setFillColor(NSColor(white: 1, alpha: 0.04).cgColor)
            stride(from: CGFloat(24), to: bounds.width, by: 24).forEach { gx in
                stride(from: CGFloat(24), to: bounds.height, by: 24).forEach { gy in
                    ctx.fillEllipse(in: CGRect(x: gx-1, y: gy-1, width: 2, height: 2))
                }
            }

        case .light:
            ctx.setFillColor(NSColor(white: 0.88, alpha: 1).cgColor)
            ctx.fill(bounds)
            ctx.setFillColor(NSColor(white: 0, alpha: 0.04).cgColor)
            stride(from: CGFloat(24), to: bounds.width, by: 24).forEach { gx in
                stride(from: CGFloat(24), to: bounds.height, by: 24).forEach { gy in
                    ctx.fillEllipse(in: CGRect(x: gx-1, y: gy-1, width: 2, height: 2))
                }
            }

        case .checkerboard:
            let sz: CGFloat = 18
            var flipRow = false
            var y: CGFloat = 0
            while y < bounds.height {
                var x: CGFloat = 0
                var flipCell = flipRow
                while x < bounds.width {
                    ctx.setFillColor(flipCell
                        ? NSColor(white: 0.22, alpha: 1).cgColor
                        : NSColor(white: 0.14, alpha: 1).cgColor)
                    ctx.fill(CGRect(x: x, y: y, width: sz, height: sz))
                    x += sz; flipCell.toggle()
                }
                y += sz; flipRow.toggle()
            }
        }
    }
}
