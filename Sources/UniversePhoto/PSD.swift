import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Photoshop documents (PSD, 8-bit RGB) with layers.
///
/// Export: every layer as it looks (transform, adjustments, mask and effects baked in) with its
/// name, opacity, blend mode, visibility and clipping; plus the flattened picture.
/// Import: layers with raw or PackBits (RLE) data, names, opacity, blend mode, visibility and
/// clipping. Smart objects, adjustment layers, text, vector masks and layer effects come in as
/// their pixels only (or not at all when a layer has none); 16/32-bit and CMYK files are refused.
enum PSD {
    static let type = UTType(filenameExtension: "psd") ?? UTType(importedAs: "com.adobe.photoshop-image")

    enum PSDError: LocalizedError {
        case unsupported(String), damaged
        var errorDescription: String? {
            switch self {
            case .unsupported(let what): return LocalizedText.string("This Photoshop file is not supported:") + " " + LocalizedText.string(what)
            case .damaged: return LocalizedText.string("The Photoshop file is damaged or incomplete.")
            }
        }
    }

    private static let blendKeys: [LayerBlend: String] = [
        .normal: "norm", .multiply: "mul ", .screen: "scrn", .overlay: "over", .darken: "dark", .lighten: "lite",
        .colorBurn: "idiv", .linearBurn: "lbrn", .colorDodge: "div ", .linearDodge: "lddg", .softLight: "sLit", .hardLight: "hLit",
        .difference: "diff", .exclusion: "smud", .hue: "hue ", .saturation: "sat ", .color: "colr", .luminosity: "lum ",
    ]

    // MARK: Export

    /// `layers` are composited the way the canvas shows them (groups already applied).
    static func write(layers: [ArtLayer], width: Int, height: Int) throws -> Data {
        var out = Writer()
        out.text("8BPS"); out.u16(1); out.zeros(6); out.u16(4); out.u32(UInt32(height)); out.u32(UInt32(width)); out.u16(8); out.u16(3)
        out.u32(0)                                   // colour mode data
        out.u32(0)                                   // image resources

        struct Prepared { var layer: ArtLayer; var rect: (top: Int, left: Int, bottom: Int, right: Int); var planes: [[UInt8]] }
        var prepared: [Prepared] = []
        for layer in layers {
            var solo = layer
            solo.opacity = 1; solo.blend = .normal; solo.visible = true; solo.clipped = false
            guard let image = Renderer.render(layers: [solo], width: width, height: height), let b = PixelOps.bitmap(image) else { throw PSDError.damaged }
            var alpha = [UInt8](repeating: 0, count: width * height)
            for i in 0..<(width * height) { alpha[i] = b.bytes[i * 4 + 3] }
            let box = PixelOps.bounds(alpha, width: width, height: height) ?? .zero
            let l = Int(box.minX), t = Int(box.minY), w = Int(box.width), h = Int(box.height)
            var planes = [[UInt8]](repeating: [UInt8](repeating: 0, count: w * h), count: 4)   // A, R, G, B
            for y in 0..<h { for x in 0..<w {
                let p = b.index(l + x, t + y), a = Int(b.bytes[p + 3]), o = y * w + x
                planes[0][o] = UInt8(a)
                if a > 0 { for c in 0..<3 { planes[c + 1][o] = UInt8(min(255, (Int(b.bytes[p + c]) * 255 + a / 2) / a)) } }   // unpremultiply
            } }
            prepared.append(Prepared(layer: layer, rect: (t, l, t + h, l + w), planes: planes))
        }

        var info = Writer()
        info.i16(-Int16(prepared.count))             // negative: the merged image's first alpha is transparency
        for p in prepared {
            info.i32(Int32(p.rect.top)); info.i32(Int32(p.rect.left)); info.i32(Int32(p.rect.bottom)); info.i32(Int32(p.rect.right))
            info.u16(4)
            for id in [-1, 0, 1, 2] as [Int16] { info.i16(id); info.u32(UInt32(2 + p.planes[0].count)) }
            info.text("8BIM"); info.text(blendKeys[p.layer.blend] ?? "norm")
            info.u8(UInt8(max(0, min(255, (p.layer.opacity * 255).rounded()))))
            info.u8(p.layer.clipped ? 1 : 0)
            info.u8(p.layer.visible ? 0 : 2)          // bit 1: hidden
            info.u8(0)
            var extra = Writer()
            extra.u32(0); extra.u32(0)                 // no layer mask, no blending ranges
            let name = Array(p.layer.name.data(using: .macOSRoman, allowLossyConversion: true) ?? Data()).prefix(255)
            extra.u8(UInt8(name.count)); extra.bytes(Array(name))
            extra.zeros((4 - (1 + name.count) % 4) % 4)   // Pascal string padded to a multiple of 4
            info.u32(UInt32(extra.data.count)); info.bytes(Array(extra.data))
        }
        for p in prepared { for plane in p.planes { info.u16(0); info.bytes(plane) } }
        if info.data.count % 2 == 1 { info.u8(0) }

        var section = Writer()
        section.u32(UInt32(info.data.count)); section.bytes(Array(info.data))
        section.u32(0)                               // global layer mask info
        out.u32(UInt32(section.data.count)); out.bytes(Array(section.data))

        // Flattened picture: raw planes R, G, B, A.
        guard let merged = Renderer.render(layers: layers, width: width, height: height), let mb = PixelOps.bitmap(merged) else { throw PSDError.damaged }
        out.u16(0)
        for c in [0, 1, 2, 3] {
            var plane = [UInt8](repeating: 0, count: width * height)
            for i in 0..<(width * height) {
                let p = i * 4, a = Int(mb.bytes[p + 3])
                plane[i] = c == 3 ? UInt8(a) : (a > 0 ? UInt8(min(255, (Int(mb.bytes[p + c]) * 255 + a / 2) / a)) : 0)
            }
            out.bytes(plane)
        }
        return out.data
    }

    // MARK: Import

    static func read(_ data: Data, title: String) throws -> ArtDocument {
        var r = Reader(bytes: [UInt8](data))
        guard try r.text(4) == "8BPS", try r.u16() == 1 else { throw PSDError.unsupported("Not a PSD (PSB is not supported).") }
        try r.skip(6)
        let channels = Int(try r.u16()), height = Int(try r.u32()), width = Int(try r.u32()), depth = try r.u16(), mode = try r.u16()
        guard depth == 8 else { throw PSDError.unsupported("Only 8-bit files.") }
        guard mode == 3 || mode == 1 else { throw PSDError.unsupported("Only RGB or grayscale files.") }
        try ImageFiles.validate(width: width, height: height)
        try r.skip(Int(try r.u32()))                 // colour mode data
        try r.skip(Int(try r.u32()))                 // image resources
        let sectionLength = Int(try r.u32()), sectionEnd = r.pos + sectionLength
        var layers: [ArtLayer] = []
        if sectionLength > 0 {
            let infoLength = Int(try r.u32()), infoEnd = r.pos + infoLength
            if infoLength > 0 {
                let count = abs(Int(try r.i16()))
                struct Record { var top, left, bottom, right: Int; var channels: [(id: Int, length: Int)]; var blend: String; var opacity: UInt8; var clipping: UInt8; var flags: UInt8; var name: String }
                var records: [Record] = []
                for _ in 0..<count {
                    let top = Int(try r.i32()), left = Int(try r.i32()), bottom = Int(try r.i32()), right = Int(try r.i32())
                    let n = Int(try r.u16())
                    var chans: [(Int, Int)] = []
                    for _ in 0..<n { chans.append((Int(try r.i16()), Int(try r.u32()))) }
                    guard try r.text(4) == "8BIM" else { throw PSDError.damaged }
                    let blend = try r.text(4), opacity = try r.u8(), clipping = try r.u8(), flags = try r.u8(); try r.skip(1)
                    let extraLength = Int(try r.u32()), extraEnd = r.pos + extraLength
                    try r.skip(Int(try r.u32())); try r.skip(Int(try r.u32()))   // mask, blending ranges
                    let nameLength = Int(try r.u8())
                    let name = String(bytes: try r.take(nameLength), encoding: .macOSRoman) ?? ""
                    r.pos = extraEnd
                    records.append(Record(top: top, left: left, bottom: bottom, right: right, channels: chans.map { (id: $0.0, length: $0.1) }, blend: blend, opacity: opacity, clipping: clipping, flags: flags, name: name))
                }
                for rec in records {
                    let w = rec.right - rec.left, h = rec.bottom - rec.top
                    var planes: [Int: [UInt8]] = [:]
                    for ch in rec.channels {
                        let end = r.pos + ch.length
                        if w > 0 && h > 0 { planes[ch.id] = try channel(&r, width: w, height: h, end: end) }
                        r.pos = end
                    }
                    // Group dividers and empty layers carry no pixels.
                    guard w > 0, h > 0, rec.name != "</Layer group>" else { continue }
                    var layer = ArtLayer(name: rec.name.isEmpty ? L("Layer") : rec.name)
                    layer.opacity = Double(rec.opacity) / 255
                    layer.blend = blendKeys.first { $0.value == rec.blend }?.key ?? .normal
                    layer.visible = rec.flags & 2 == 0
                    layer.clipped = rec.clipping == 1 && !layers.isEmpty
                    layer.imageData = try png(planes: planes, grayscale: mode == 1, width: w, height: h, left: rec.left, top: rec.top, canvasWidth: width, canvasHeight: height)
                    layers.append(layer)
                }
            }
            r.pos = max(r.pos, min(infoEnd, sectionEnd))
        }
        r.pos = sectionEnd
        if layers.isEmpty {
            // No layers (e.g. a flattened file): use the merged picture.
            let compression = try r.u16()
            var planes: [Int: [UInt8]] = [:]
            if compression == 1 {
                var counts: [Int] = []
                for _ in 0..<(channels * height) { counts.append(Int(try r.u16())) }
                for c in 0..<channels {
                    var plane: [UInt8] = []
                    plane.reserveCapacity(width * height)
                    for row in 0..<height { plane += try packBits(r.take(counts[c * height + row]), expected: width) }
                    planes[c] = plane
                }
            } else {
                for c in 0..<channels { planes[c] = try r.take(width * height) }
            }
            var mapped: [Int: [UInt8]] = [:]
            if mode == 1 { mapped[0] = planes[0]; if channels > 1 { mapped[-1] = planes[1] } }
            else { mapped[0] = planes[0]; mapped[1] = planes[1]; mapped[2] = planes[2]; if channels > 3 { mapped[-1] = planes[3] } }
            var layer = ArtLayer(name: title)
            layer.imageData = try png(planes: mapped, grayscale: mode == 1, width: width, height: height, left: 0, top: 0, canvasWidth: width, canvasHeight: height)
            layers = [layer]
        }
        return ArtDocument(title: title, width: width, height: height, layers: layers)
    }

    private static func channel(_ r: inout Reader, width: Int, height: Int, end: Int) throws -> [UInt8] {
        let compression = try r.u16()
        switch compression {
        case 0: return try r.take(width * height)
        case 1:
            var counts: [Int] = []
            for _ in 0..<height { counts.append(Int(try r.u16())) }
            var out: [UInt8] = []
            out.reserveCapacity(width * height)
            for c in counts { out += try packBits(r.take(c), expected: width) }
            return out
        default: throw PSDError.unsupported("ZIP-compressed layers.")
        }
    }

    /// PackBits (Apple RLE) as used per row in PSD files.
    static func packBits(_ input: [UInt8], expected: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(expected)
        var i = 0
        while i < input.count && out.count < expected {
            let n = Int(Int8(bitPattern: input[i])); i += 1
            if n >= 0 {
                guard i + n + 1 <= input.count else { throw PSDError.damaged }
                out += input[i..<(i + n + 1)]; i += n + 1
            } else if n != -128 {
                guard i < input.count else { throw PSDError.damaged }
                out += [UInt8](repeating: input[i], count: 1 - n); i += 1
            }
        }
        if out.count < expected { out += [UInt8](repeating: 0, count: expected - out.count) }
        return Array(out.prefix(expected))
    }

    /// Planes of one layer placed on a transparent canvas-sized picture (PNG).
    private static func png(planes: [Int: [UInt8]], grayscale: Bool, width w: Int, height h: Int, left: Int, top: Int, canvasWidth: Int, canvasHeight: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: canvasWidth * canvasHeight * 4)
        let red = planes[0], green = grayscale ? planes[0] : planes[1], blue = grayscale ? planes[0] : planes[2], alpha = planes[-1]
        for y in 0..<h {
            let cy = top + y; guard cy >= 0, cy < canvasHeight else { continue }
            for x in 0..<w {
                let cx = left + x; guard cx >= 0, cx < canvasWidth else { continue }
                let i = y * w + x, o = (cy * canvasWidth + cx) * 4
                let a = Int(alpha?[i] ?? 255)
                bytes[o] = UInt8((Int(red?[i] ?? 0) * a + 127) / 255)
                bytes[o + 1] = UInt8((Int(green?[i] ?? 0) * a + 127) / 255)
                bytes[o + 2] = UInt8((Int(blue?[i] ?? 0) * a + 127) / 255)
                bytes[o + 3] = UInt8(a)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: canvasWidth, height: canvasHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: canvasWidth * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let data = PixelOps.png(image) else { throw PSDError.damaged }
        return data
    }

    // MARK: Big-endian helpers

    private struct Writer {
        var data = Data()
        mutating func u8(_ v: UInt8) { data.append(v) }
        mutating func u16(_ v: UInt16) { data.append(UInt8(v >> 8)); data.append(UInt8(v & 0xFF)) }
        mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
        mutating func u32(_ v: UInt32) { for s in [24, 16, 8, 0] { data.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
        mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
        mutating func zeros(_ n: Int) { data.append(contentsOf: [UInt8](repeating: 0, count: n)) }
        mutating func text(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        mutating func bytes(_ b: [UInt8]) { data.append(contentsOf: b) }
    }

    private struct Reader {
        var bytes: [UInt8]; var pos = 0
        mutating func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, pos + n <= bytes.count else { throw PSDError.damaged }
            defer { pos += n }
            return Array(bytes[pos..<(pos + n)])
        }
        mutating func skip(_ n: Int) throws { guard n >= 0, pos + n <= bytes.count else { throw PSDError.damaged }; pos += n }
        mutating func u8() throws -> UInt8 { try take(1)[0] }
        mutating func u16() throws -> UInt16 { let b = try take(2); return UInt16(b[0]) << 8 | UInt16(b[1]) }
        mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
        mutating func u32() throws -> UInt32 { let b = try take(4); return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]) }
        mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
        mutating func text(_ n: Int) throws -> String { String(bytes: try take(n), encoding: .ascii) ?? "" }
    }
}
