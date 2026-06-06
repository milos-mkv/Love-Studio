import AppKit

// MARK: - Pack result types

struct PackedSprite {
    let entry:   SpriteEntry
    let rect:    CGRect   // position & size inside atlas
    let nsImage: NSImage
}

struct PackResult {
    let packed:     [PackedSprite]
    let atlasSize:  CGSize
    let atlasImage: NSImage?
    /// Sprites that could not be loaded (missing file, etc.)
    let failed:     [SpriteEntry]
}

// MARK: - Packer

struct SpritesheetPacker {

    /// Pack all sprites in `config` into a single atlas.
    /// `projectURL` is used to resolve relative file paths.
    static func pack(config: SpritesheetConfig, projectURL: URL) -> PackResult {
        // ── 1. Load images ──────────────────────────────────────────────────
        var loaded:  [(entry: SpriteEntry, image: NSImage)] = []
        var failed:  [SpriteEntry] = []

        for sprite in config.sprites {
            let url = resolveURL(sprite.filePath, projectURL: projectURL)
            if var img = NSImage(contentsOf: url) {
                if config.trimTransparent { img = trimmed(img) }
                loaded.append((sprite, img))
            } else {
                failed.append(sprite)
            }
        }

        guard !loaded.isEmpty else {
            return PackResult(packed: [], atlasSize: .zero, atlasImage: nil, failed: failed)
        }

        // ── 2. Sort by height descending (shelf-packing heuristic) ──────────
        let pad = CGFloat(config.padding)
        let sorted = loaded.sorted {
            $0.image.size.height > $1.image.size.height
        }

        // ── 3. Shelf-based bin packing ──────────────────────────────────────
        let maxDim = CGFloat(config.maxSize)

        // Compute minimum required atlas width (widest single sprite)
        let minW = sorted.map { $0.image.size.width }.max() ?? 1
        // Start with a width that fits all sprites in roughly a square
        let totalArea = sorted.reduce(0.0) { $0 + $1.image.size.width * $1.image.size.height }
        var atlasW = max(minW, ceil(sqrt(totalArea) * 1.2))
        atlasW = min(atlasW, maxDim)

        var packed: [PackedSprite] = []

        // Try packing; if a sprite doesn't fit horizontally, we fail gracefully.
        var curX: CGFloat = pad
        var curY: CGFloat = pad
        var rowH: CGFloat = 0

        for item in sorted {
            let imgW = item.image.size.width
            let imgH = item.image.size.height

            if curX + imgW + pad > atlasW {
                // New shelf
                curX  = pad
                curY += rowH + pad
                rowH  = 0
            }

            packed.append(PackedSprite(
                entry:   item.entry,
                rect:    CGRect(x: curX, y: curY, width: imgW, height: imgH),
                nsImage: item.image
            ))

            curX += imgW + pad
            rowH  = max(rowH, imgH)
        }

        var atlasH = curY + rowH + pad

        // ── 4. Round up to power of two if requested ─────────────────────────
        if config.powerOfTwo {
            atlasW = nextPow2(atlasW)
            atlasH = nextPow2(atlasH)
        }
        atlasW = min(atlasW, maxDim)
        atlasH = min(atlasH, maxDim)

        let atlasSize = CGSize(width: atlasW, height: atlasH)

        // ── 5. Render atlas using CoreGraphics ───────────────────────────────
        let atlasImage = renderAtlas(packed: packed, size: atlasSize)

        return PackResult(packed: packed, atlasSize: atlasSize, atlasImage: atlasImage, failed: failed)
    }

    // MARK: - Atlas PNG data

    static func pngData(from result: PackResult) -> Data? {
        guard let img = result.atlasImage,
              let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImg)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Private helpers

    private static func renderAtlas(packed: [PackedSprite], size: CGSize) -> NSImage? {
        guard let ctx = CGContext(
            data: nil,
            width:  Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CoreGraphics origin is bottom-left; flip so we draw top-left.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)

        for p in packed {
            guard let cg = p.nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { continue }
            ctx.draw(cg, in: p.rect)
        }

        guard let cgResult = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgResult, size: size)
    }

    // MARK: - Trim transparent edges

    private static func trimmed(_ nsImage: NSImage) -> NSImage {
        guard let cgSrc = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nsImage }
        let w = cgSrc.width, h = cgSrc.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nsImage }
        ctx.draw(cgSrc, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let rawData = ctx.data else { return nsImage }
        let pixels = rawData.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                if pixels[(y * w + x) * 4 + 3] > 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nsImage }
        let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cgSrc.cropping(to: crop) else { return nsImage }
        return NSImage(cgImage: cropped, size: CGSize(width: crop.width, height: crop.height))
    }

    private static func resolveURL(_ path: String, projectURL: URL) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return projectURL.appendingPathComponent(path)
    }

    private static func nextPow2(_ v: CGFloat) -> CGFloat {
        var n: CGFloat = 1
        while n < v { n *= 2 }
        return n
    }
}
