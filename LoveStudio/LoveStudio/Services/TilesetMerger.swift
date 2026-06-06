import AppKit

// MARK: - Result types

struct MergedSheetInfo {
    let entry: SpriteEntry
    let nsImage: NSImage
    /// Top-left pixel origin in the merged atlas
    let originX: Int
    let originY: Int
    /// How many tile columns this sheet has
    let cols: Int
    /// How many tile rows this sheet has
    let rows: Int
    /// Pixel width  (cols * tileSize)
    let pxW: Int
    /// Pixel height (rows * tileSize)
    let pxH: Int
    /// First GID in the merged atlas: (originY/tileSize) * mergedCols + (originX/tileSize)
    let firstGID: Int
}

struct TilesetMergeResult {
    let sheets: [MergedSheetInfo]
    let atlasSize: CGSize
    let atlasImage: NSImage?
    let mergedCols: Int
    let mergedRows: Int
    let failed: [SpriteEntry]
}

// MARK: - Merger

struct TilesetMerger {

    /// Merge multiple sprite sheets into one atlas, preserving tile grid alignment.
    ///
    /// Sheets are arranged in a grid: left-to-right until the row would exceed
    /// `maxAtlasWidth` pixels, then a new row is started.  Every sheet is placed
    /// at a tile-aligned position (multiples of tileSize).
    ///
    /// Because sheets in the same row can have different heights, each row's
    /// height equals the tallest sheet in that row.  `mergedCols` is the total
    /// number of tile columns the widest row occupies, so GID ranges are computed
    /// as `(originY/tileSize) * mergedCols + (originX/tileSize)`.
    ///
    /// - Parameters:
    ///   - sprites:       List of sprite entries to merge (order preserved).
    ///   - tileSize:      Side length of one tile in pixels.
    ///   - maxAtlasWidth: Maximum pixel width before wrapping to next row.
    ///   - powerOfTwo:    Round atlas dimensions up to next power of two.
    ///   - projectURL:    Base URL used to resolve relative file paths.
    static func merge(sprites: [SpriteEntry],
                      tileSize: Int,
                      maxAtlasWidth: Int = 2048,
                      powerOfTwo: Bool,
                      projectURL: URL) -> TilesetMergeResult {

        guard tileSize > 0 else {
            return TilesetMergeResult(sheets: [], atlasSize: .zero,
                                      atlasImage: nil, mergedCols: 0,
                                      mergedRows: 0, failed: sprites)
        }

        // ── 1. Load images ────────────────────────────────────────────────────
        var loaded: [(entry: SpriteEntry, image: NSImage)] = []
        var failed: [SpriteEntry] = []

        for sprite in sprites {
            let url = resolveURL(sprite.filePath, projectURL: projectURL)
            if let img = NSImage(contentsOf: url) {
                loaded.append((sprite, img))
            } else {
                failed.append(sprite)
            }
        }

        guard !loaded.isEmpty else {
            return TilesetMergeResult(sheets: [], atlasSize: .zero,
                                      atlasImage: nil, mergedCols: 0,
                                      mergedRows: 0, failed: failed)
        }

        // ── 2. Compute per-sheet tile grids ───────────────────────────────────
        struct SheetGrid {
            let entry: SpriteEntry
            let image: NSImage
            let cols: Int   // tile columns
            let rows: Int   // tile rows
            let pxW: Int    // pixel width  = cols * tileSize
            let pxH: Int    // pixel height = rows * tileSize
        }

        let grids: [SheetGrid] = loaded.map { item in
            // Use pixel dimensions from bitmap rep to avoid DPI scaling issues.
            let pxW: Int
            let pxH: Int
            if let rep = item.image.representations.first as? NSBitmapImageRep {
                pxW = rep.pixelsWide
                pxH = rep.pixelsHigh
            } else {
                pxW = Int(item.image.size.width)
                pxH = Int(item.image.size.height)
            }
            let cols = max(1, pxW / tileSize)
            let rows = max(1, pxH / tileSize)
            return SheetGrid(entry: item.entry, image: item.image,
                             cols: cols, rows: rows,
                             pxW: cols * tileSize, pxH: rows * tileSize)
        }

        // ── 3. Grid layout: pack sheets left-to-right, wrap when too wide ─────
        // Each row tracks: current X cursor, max row height, sheets placed
        struct RowLayout {
            var sheets: [(grid: SheetGrid, originX: Int)] = []
            var currentX: Int = 0
            var maxRows: Int = 0   // tallest sheet in this row (in tiles)
        }

        var rows: [RowLayout] = [RowLayout()]

        for grid in grids {
            var currentRow = rows.count - 1
            // If this sheet won't fit, start a new row
            if rows[currentRow].currentX + grid.pxW > maxAtlasWidth
                && rows[currentRow].currentX > 0 {
                rows.append(RowLayout())
                currentRow = rows.count - 1
            }
            rows[currentRow].sheets.append((grid, rows[currentRow].currentX))
            rows[currentRow].currentX += grid.pxW
            rows[currentRow].maxRows = max(rows[currentRow].maxRows, grid.rows)
        }

        // ── 4. Compute total canvas size ──────────────────────────────────────
        let mergedColsPx = rows.map(\.currentX).max() ?? 0
        let mergedCols   = mergedColsPx / tileSize

        // ── 5. Assign pixel origins and GIDs ─────────────────────────────────
        var infos: [MergedSheetInfo] = []
        var currentRowY = 0   // current Y in tiles

        for row in rows {
            for (grid, originXpx) in row.sheets {
                let originXtile = originXpx / tileSize
                let firstGID    = currentRowY * mergedCols + originXtile

                infos.append(MergedSheetInfo(
                    entry:    grid.entry,
                    nsImage:  grid.image,
                    originX:  originXpx,
                    originY:  currentRowY * tileSize,
                    cols:     grid.cols,
                    rows:     grid.rows,
                    pxW:      grid.pxW,
                    pxH:      grid.pxH,
                    firstGID: firstGID
                ))
            }
            currentRowY += row.maxRows
        }

        let mergedRows = currentRowY

        // ── 6. Power-of-two rounding ──────────────────────────────────────────
        var atlasW = CGFloat(mergedColsPx)
        var atlasH = CGFloat(mergedRows * tileSize)
        if powerOfTwo {
            atlasW = nextPow2(atlasW)
            atlasH = nextPow2(atlasH)
        }

        let atlasSize = CGSize(width: max(atlasW, 1), height: max(atlasH, 1))

        // ── 7. Render ─────────────────────────────────────────────────────────
        let atlasImage = renderAtlas(infos: infos, size: atlasSize)

        return TilesetMergeResult(
            sheets:     infos,
            atlasSize:  atlasSize,
            atlasImage: atlasImage,
            mergedCols: mergedCols,
            mergedRows: mergedRows,
            failed:     failed
        )
    }

    // MARK: - PNG data

    static func pngData(from result: TilesetMergeResult) -> Data? {
        guard let img = result.atlasImage,
              let cg  = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Private helpers

    private static func renderAtlas(infos: [MergedSheetInfo], size: CGSize) -> NSImage? {
        guard let ctx = CGContext(
            data: nil,
            width:  Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // NSGraphicsContext(flipped: true) gives top-left origin so NSImage.draw(in:)
        // places images correctly without any manual axis flipping artifacts.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

        for info in infos {
            let drawRect = NSRect(
                x:      CGFloat(info.originX),
                y:      CGFloat(info.originY),
                width:  CGFloat(info.pxW),
                height: CGFloat(info.pxH)
            )
            info.nsImage.draw(in: drawRect,
                              from: NSRect(origin: .zero, size: NSSize(width: info.pxW, height: info.pxH)),
                              operation: .copy,
                              fraction: 1.0)
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let cgResult = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgResult, size: size)
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
