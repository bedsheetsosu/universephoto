import CoreGraphics
import Foundation

/// Liquify in progress: the untouched pixels, a displacement per pixel (where each output
/// pixel takes its colour from), and the current result.
struct LiquifyState {
    var source: PixelOps.Bitmap
    var output: PixelOps.Bitmap
    var dx: [Float]
    var dy: [Float]
    var last: CGPoint
}

/// What the liquify brush does: push drags pixels along; the others work while the brush rests
/// or moves (about 30 times a second) and grow with the time spent there.
enum LiquifyMode: String, CaseIterable, Sendable {
    case push, twirl, bloat, pinch, reconstruct
    var title: String { switch self { case .push: "Push"; case .twirl: "Twirl"; case .bloat: "Bloat"; case .pinch: "Pucker"; case .reconstruct: "Reconstruct" } }
    var symbol: String { switch self { case .push: "hand.point.right"; case .twirl: "tornado"; case .bloat: "arrow.up.left.and.arrow.down.right"; case .pinch: "arrow.down.right.and.arrow.up.left"; case .reconstruct: "arrow.uturn.backward" } }
}

/// Liquify: drag to push pixels along, like a finger in wet paint, without smearing colours;
/// or twirl, bloat, pucker and reconstruct under the brush.
extension Studio {
    func beginLiquify(id: UUID, at point: CGPoint) {
        guard activeLayer?.isAdjustmentLayer != true, let image = rawLayerPixels(), let bitmap = PixelOps.bitmap(image) else { return }
        let n = width * height
        liquifyState = LiquifyState(source: bitmap, output: bitmap, dx: [Float](repeating: 0, count: n), dy: [Float](repeating: 0, count: n), last: point)
        Renderer.transient[id] = image
        liquifyTimer?.invalidate(); liquifyTimer = nil
        if liquifyMode != .push {
            // Effects that build up while the brush rests: tick about 30 times a second.
            liquifyTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.liquifyTick(id: id) }
            }
        }
    }

    /// One tick of twirl, bloat, pucker or reconstruct at the brush's current position.
    func liquifyTick(id: UUID) {
        guard var st = liquifyState, liquifyMode != .push else { return }
        let c = st.last, r = max(2, brushSize / 2), k = 0.06 * max(0.05, min(1, toolStrength))
        let x0 = max(0, Int(c.x - r)), x1 = min(width - 1, Int(c.x + r)), y0 = max(0, Int(c.y - r)), y1 = min(height - 1, Int(c.y + r))
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0...y1 { for x in x0...x1 {
            let rx = Double(x) - c.x, ry = Double(y) - c.y, d2 = (rx * rx + ry * ry) / (r * r)
            guard d2 < 1 else { continue }
            let w = (1 - d2) * (1 - d2), i = y * width + x
            // Where this pixel samples the source now, relative to the brush centre; each tick moves
            // that sample point (so repeated ticks compose into a real turn or scale).
            let sx = rx + Double(st.dx[i]), sy = ry + Double(st.dy[i])
            var nx = sx, ny = sy
            switch liquifyMode {
            case .bloat: nx = sx * (1 - k * w); ny = sy * (1 - k * w)         // sample nearer the centre: grows
            case .pinch: nx = sx * (1 + k * w); ny = sy * (1 + k * w)         // sample further out: shrinks
            case .twirl:
                let a = -k * 1.5 * w, ca = cos(a), sa = sin(a)                 // clockwise
                nx = sx * ca - sy * sa; ny = sx * sa + sy * ca
            case .reconstruct:
                let f = 1 - min(1, k * 3 * w); nx = rx + (sx - rx) * f; ny = ry + (sy - ry) * f
            case .push: break
            }
            st.dx[i] = Float(nx - rx); st.dy[i] = Float(ny - ry)
        } }
        Self.resample(&st, in: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1), width: width, height: height)
        liquifyState = st
        Renderer.transient[id] = Self.cgImage(st.output)
        liquifyChanged?()
    }

    /// Pushes from the last point to `point` in steps of a quarter radius.
    func liquify(id: UUID, to point: CGPoint) {
        guard var st = liquifyState else { return }
        if liquifyMode != .push { st.last = point; liquifyState = st; liquifyTick(id: id); return }
        let r = max(2, brushSize / 2), strength = max(0.05, min(1, toolStrength))
        let dist = hypot(point.x - st.last.x, point.y - st.last.y)
        guard dist > 0.01 else { return }
        let n = max(1, Int(dist / max(1, r / 4)))
        var box = CGRect.null
        for k in 1...n {
            let a = CGPoint(x: st.last.x + (point.x - st.last.x) * Double(k - 1) / Double(n), y: st.last.y + (point.y - st.last.y) * Double(k - 1) / Double(n))
            let mx = (point.x - st.last.x) / Double(n), my = (point.y - st.last.y) / Double(n)
            let x0 = max(0, Int(a.x - r)), x1 = min(width - 1, Int(a.x + r)), y0 = max(0, Int(a.y - r)), y1 = min(height - 1, Int(a.y + r))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 {
                let d2 = ((Double(x) - a.x) * (Double(x) - a.x) + (Double(y) - a.y) * (Double(y) - a.y)) / (r * r)
                guard d2 < 1 else { continue }
                let w = strength * (1 - d2) * (1 - d2)            // smooth falloff
                // Output pixel now shows what was `w × step` behind it (pixels move with the brush).
                let i = y * width + x
                st.dx[i] -= Float(mx * w); st.dy[i] -= Float(my * w)
            } }
            box = box.union(CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1))
        }
        if !box.isNull { Self.resample(&st, in: box, width: width, height: height) }
        st.last = point
        liquifyState = st
        Renderer.transient[id] = Self.cgImage(st.output)
    }

    /// Bilinear lookup of the source through the displacement, inside `box`.
    static func resample(_ st: inout LiquifyState, in box: CGRect, width: Int, height: Int) {
        let src = st.source
        for y in Int(box.minY)..<Int(box.maxY) { for x in Int(box.minX)..<Int(box.maxX) {
            let i = y * width + x
            let sx = min(Double(width - 1), max(0, Double(x) + Double(st.dx[i]))), sy = min(Double(height - 1), max(0, Double(y) + Double(st.dy[i])))
            let x0 = Int(sx), y0 = Int(sy), x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1), fx = sx - Double(x0), fy = sy - Double(y0)
            let p00 = src.index(x0, y0), p10 = src.index(x1, y0), p01 = src.index(x0, y1), p11 = src.index(x1, y1), o = i * 4
            for ch in 0..<4 {
                let top = Double(src.bytes[p00 + ch]) * (1 - fx) + Double(src.bytes[p10 + ch]) * fx
                let bottom = Double(src.bytes[p01 + ch]) * (1 - fx) + Double(src.bytes[p11 + ch]) * fx
                st.output.bytes[o + ch] = UInt8(max(0, min(255, (top * (1 - fy) + bottom * fy).rounded())))
            }
        } }
    }

    static func cgImage(_ b: PixelOps.Bitmap) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(b.bytes) as CFData) else { return nil }
        return CGImage(width: b.width, height: b.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: b.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Ends a liquify stroke: the layer becomes the pushed picture (its strokes are rasterized).
    func finishLiquify(_ stroke: InkStroke) {
        liquifyTimer?.invalidate(); liquifyTimer = nil
        defer { Renderer.transient[stroke.id] = nil; liquifyState = nil }
        guard canEdit, let st = liquifyState, let image = Self.cgImage(st.output), let data = try? Renderer.png(image) else { return }
        mutateLayer("Liquify") { $0.imageData = data; $0.strokes = [] }
        boundsCache.removeAll()
    }
}
