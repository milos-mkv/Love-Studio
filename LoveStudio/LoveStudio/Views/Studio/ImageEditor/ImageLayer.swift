import AppKit

// MARK: - Blend Mode

enum LayerBlendMode: String, Codable, CaseIterable, Identifiable {
    case normal   = "Normal"
    case multiply = "Multiply"
    case screen   = "Screen"
    case overlay  = "Overlay"
    case add      = "Add"
    case subtract = "Subtract"
    case darken   = "Darken"
    case lighten  = "Lighten"

    var id: String { rawValue }
}

// MARK: - Layer Metadata (Codable, no pixel data)

struct ImageLayerMeta: Codable {
    var id: String
    var name: String
    var visible: Bool
    var opacity: Double
    var blendMode: LayerBlendMode
    var isReference: Bool
    var isLocked: Bool
    var order: Int
}

// MARK: - Layer (runtime, includes pixel data)

final class ImageLayer: Identifiable {
    var id: UUID
    var name: String
    var visible: Bool
    var opacity: Double        // 0.0 - 1.0
    var blendMode: LayerBlendMode
    var isReference: Bool      // shown at 50% opacity, not exported
    var isLocked: Bool
    var pixelData: [UInt8]     // RGBA, width*height*4

    init(id: UUID = UUID(), name: String, width: Int, height: Int,
         visible: Bool = true, opacity: Double = 1.0,
         blendMode: LayerBlendMode = .normal,
         isReference: Bool = false, isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.visible = visible
        self.opacity = opacity
        self.blendMode = blendMode
        self.isReference = isReference
        self.isLocked = isLocked
        self.pixelData = Array(repeating: 0, count: max(1, width * height * 4))
    }

    func meta(order: Int) -> ImageLayerMeta {
        ImageLayerMeta(id: id.uuidString, name: name, visible: visible,
                       opacity: opacity, blendMode: blendMode,
                       isReference: isReference, isLocked: isLocked, order: order)
    }

    func duplicate() -> ImageLayer {
        let l = ImageLayer(name: name + " copy", width: 0, height: 0,
                           visible: visible, opacity: opacity, blendMode: blendMode,
                           isReference: isReference, isLocked: isLocked)
        l.pixelData = pixelData
        return l
    }
}

// MARK: - Compositing

struct LayerCompositor {

    /// Composite `layers` (index 0 = bottom) into a single RGBA buffer of size width×height.
    static func composite(layers: [ImageLayer], width: Int, height: Int) -> [UInt8] {
        let count = width * height * 4
        guard count > 0 else { return [] }
        var result = Array(repeating: UInt8(0), count: count)

        for layer in layers {
            guard layer.visible, layer.pixelData.count == count else { continue }
            let opacity = max(0, min(1, layer.opacity))
            let refOpacity = layer.isReference ? 0.5 * opacity : opacity

            for i in stride(from: 0, to: count, by: 4) {
                let sr = Double(layer.pixelData[i])   / 255
                let sg = Double(layer.pixelData[i+1]) / 255
                let sb = Double(layer.pixelData[i+2]) / 255
                let sa = Double(layer.pixelData[i+3]) / 255 * refOpacity

                let dr = Double(result[i])   / 255
                let dg = Double(result[i+1]) / 255
                let db = Double(result[i+2]) / 255
                let da = Double(result[i+3]) / 255

                var or_, og, ob, oa: Double

                switch layer.blendMode {
                case .normal:
                    or_ = sr * sa + dr * da * (1 - sa)
                    og  = sg * sa + dg * da * (1 - sa)
                    ob  = sb * sa + db * da * (1 - sa)
                    oa  = sa + da * (1 - sa)
                case .multiply:
                    let blr = sr * dr
                    let blg = sg * dg
                    let blb = sb * db
                    or_ = blr * sa + dr * (1 - sa)
                    og  = blg * sa + dg * (1 - sa)
                    ob  = blb * sa + db * (1 - sa)
                    oa  = sa + da * (1 - sa)
                case .screen:
                    let blr = 1 - (1 - sr) * (1 - dr)
                    let blg = 1 - (1 - sg) * (1 - dg)
                    let blb = 1 - (1 - sb) * (1 - db)
                    or_ = blr * sa + dr * (1 - sa)
                    og  = blg * sa + dg * (1 - sa)
                    ob  = blb * sa + db * (1 - sa)
                    oa  = sa + da * (1 - sa)
                case .overlay:
                    let blr = dr < 0.5 ? 2*sr*dr : 1 - 2*(1-sr)*(1-dr)
                    let blg = dg < 0.5 ? 2*sg*dg : 1 - 2*(1-sg)*(1-dg)
                    let blb = db < 0.5 ? 2*sb*db : 1 - 2*(1-sb)*(1-db)
                    or_ = blr * sa + dr * (1 - sa)
                    og  = blg * sa + dg * (1 - sa)
                    ob  = blb * sa + db * (1 - sa)
                    oa  = sa + da * (1 - sa)
                case .add:
                    or_ = min(1, sr + dr)
                    og  = min(1, sg + dg)
                    ob  = min(1, sb + db)
                    oa  = sa + da * (1 - sa)
                case .subtract:
                    or_ = max(0, dr - sr)
                    og  = max(0, dg - sg)
                    ob  = max(0, db - sb)
                    oa  = sa + da * (1 - sa)
                case .darken:
                    or_ = min(sr, dr) * sa + dr * (1 - sa)
                    og  = min(sg, dg) * sa + dg * (1 - sa)
                    ob  = min(sb, db) * sa + db * (1 - sa)
                    oa  = sa + da * (1 - sa)
                case .lighten:
                    or_ = max(sr, dr) * sa + dr * (1 - sa)
                    og  = max(sg, dg) * sa + dg * (1 - sa)
                    ob  = max(sb, db) * sa + db * (1 - sa)
                    oa  = sa + da * (1 - sa)
                }

                result[i]   = UInt8(min(255, max(0, or_ * 255)))
                result[i+1] = UInt8(min(255, max(0, og  * 255)))
                result[i+2] = UInt8(min(255, max(0, ob  * 255)))
                result[i+3] = UInt8(min(255, max(0, oa  * 255)))
            }
        }
        return result
    }
}

// MARK: - Layer Document (save/load)

struct ImageLayerDocument {

    /// Save layers to .love-studio/images/{name}/ folder
    static func save(layers: [ImageLayer], name: String, width: Int, height: Int, to projectRoot: URL) throws {
        let dir = layerDir(name: name, projectRoot: projectRoot)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Save meta.json
        let metas = layers.enumerated().map { $0.element.meta(order: $0.offset) }
        let metaData = try JSONEncoder().encode(metas)
        try metaData.write(to: dir.appendingPathComponent("meta.json"))

        // Save each layer as PNG
        for layer in layers {
            let pngURL = dir.appendingPathComponent("layer_\(layer.id.uuidString).png")
            if let png = pngData(from: layer.pixelData, width: width, height: height) {
                try png.write(to: pngURL)
            }
        }

        // Remove old layer PNGs not in current layer set
        let currentIDs = Set(layers.map { "layer_\($0.id.uuidString).png" })
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for file in existing where file.hasPrefix("layer_") && file.hasSuffix(".png") {
            if !currentIDs.contains(file) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }

    /// Load layers from .love-studio/images/{name}/ folder
    static func load(name: String, projectRoot: URL) -> (layers: [ImageLayer], width: Int, height: Int)? {
        let dir = layerDir(name: name, projectRoot: projectRoot)
        guard let metaData = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
              let metas = try? JSONDecoder().decode([ImageLayerMeta].self, from: metaData)
        else { return nil }

        let sorted = metas.sorted { $0.order < $1.order }
        var width = 0, height = 0
        var layers: [ImageLayer] = []

        for meta in sorted {
            guard let uid = UUID(uuidString: meta.id) else { continue }
            let pngURL = dir.appendingPathComponent("layer_\(meta.id).png")
            var pixels: [UInt8] = []
            var w = 0, h = 0
            if let nsImg = NSImage(contentsOf: pngURL),
               let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                w = cg.width; h = cg.height
                if width == 0 { width = w; height = h }
                pixels = Array(repeating: 0, count: w * h * 4)
                pixels.withUnsafeMutableBytes { ptr in
                    guard let base = ptr.baseAddress else { return }
                    let cs = CGColorSpaceCreateDeviceRGB()
                    guard let ctx = CGContext(data: base, width: w, height: h,
                                              bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    else { return }
                    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
            }
            let layer = ImageLayer(id: uid, name: meta.name, width: w, height: h,
                                   visible: meta.visible, opacity: meta.opacity,
                                   blendMode: meta.blendMode, isReference: meta.isReference,
                                   isLocked: meta.isLocked)
            if !pixels.isEmpty { layer.pixelData = pixels }
            layers.append(layer)
        }

        return layers.isEmpty ? nil : (layers, width, height)
    }

    static func layerDir(name: String, projectRoot: URL) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "_")
                       .replacingOccurrences(of: "\\", with: "_")
        return projectRoot
            .appendingPathComponent(".love-studio")
            .appendingPathComponent("images")
            .appendingPathComponent(safe)
    }

    private static func pngData(from pixels: [UInt8], width: Int, height: Int) -> Data? {
        guard !pixels.isEmpty, width > 0, height > 0 else { return nil }
        var copy = pixels
        return copy.withUnsafeMutableBytes { ptr -> Data? in
            guard let base = ptr.baseAddress else { return nil }
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = ctx.makeImage()
            else { return nil }
            let ns = NSImage(cgImage: cg, size: NSSize(width: width, height: height))
            guard let tiff = ns.tiffRepresentation,
                  let rep  = NSBitmapImageRep(data: tiff)
            else { return nil }
            return rep.representation(using: .png, properties: [:])
        }
    }
}
