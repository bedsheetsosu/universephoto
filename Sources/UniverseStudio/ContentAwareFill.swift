import CoreGraphics
import Foundation

/// Content-aware fill: the selected hole is filled from the surroundings, peeling in from the
/// edge one ring at a time. Each hole pixel takes the colour of the source pixel whose 7 × 7
/// neighbourhood best matches what is already known or filled around it. Candidates are the
/// continuation of the neighbours' sources (keeps texture and lines coherent) plus random
/// samples from a band around the hole.
enum ContentAwareFill {
    /// `bitmap` RGBA premultiplied (row 0 = top), `hole` one byte per pixel (≥ 128 = fill).
    /// Returns new RGBA bytes with the hole filled (unchanged where nothing could be found).
    static func fill(_ bitmap: PixelOps.Bitmap, hole: [UInt8], candidates: Int = 40, seed: UInt64 = 7) -> [UInt8] {
        let w = bitmap.width, h = bitmap.height
        var out = bitmap.bytes
        guard hole.count == w * h, let box = PixelOps.bounds(hole.map { $0 >= 128 ? 255 : 0 }, width: w, height: h) else { return out }
        // state: 0 = original (usable as source), 1 = hole, 2 = filled
        var state = hole.map { $0 >= 128 ? UInt8(1) : 0 }
        // Source band: known pixels around the hole.
        let margin = Int(max(24, 1.2 * max(box.width, box.height)))
        let x0 = max(0, Int(box.minX) - margin), x1 = min(w - 1, Int(box.maxX) + margin)
        let y0 = max(0, Int(box.minY) - margin), y1 = min(h - 1, Int(box.maxY) + margin)
        var sources: [Int] = []
        for y in y0...y1 { for x in x0...x1 where state[y * w + x] == 0 { sources.append(y * w + x) } }
        guard !sources.isEmpty else { return out }
        var src = [Int32](repeating: -1, count: w * h)
        var rng = SplitMix(state: seed)
        let r = 3
        let neighbours = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

        /// Distance of the neighbourhoods around target t and source s (known/filled pixels only).
        func cost(_ tx: Int, _ ty: Int, _ sx: Int, _ sy: Int) -> Int {
            var sum = 0, n = 0
            for dy in -r...r {
                let ty2 = ty + dy, sy2 = sy + dy
                guard ty2 >= 0, ty2 < h, sy2 >= 0, sy2 < h else { continue }
                for dx in -r...r {
                    let tx2 = tx + dx, sx2 = sx + dx
                    guard tx2 >= 0, tx2 < w, sx2 >= 0, sx2 < w else { continue }
                    let ti = ty2 * w + tx2, si = sy2 * w + sx2
                    guard state[ti] != 1, state[si] == 0 else { continue }
                    let a = ti * 4, b = si * 4
                    for k in 0..<4 { let d = Int(out[a + k]) - Int(out[b + k]); sum += d * d }
                    n += 1
                }
            }
            return n == 0 ? Int.max : sum * 49 / n
        }

        // Onion peel: each pass fills the hole pixels touching known or filled ones.
        var front: [Int] = []
        for y in Int(box.minY)..<Int(box.maxY) { for x in Int(box.minX)..<Int(box.maxX) where state[y * w + x] == 1 {
            if neighbours.contains(where: { let nx = x + $0.0, ny = y + $0.1; return nx >= 0 && ny >= 0 && nx < w && ny < h && state[ny * w + nx] != 1 }) { front.append(y * w + x) }
        } }
        var queued = Set(front)
        while !front.isEmpty {
            var next: [Int] = []
            for i in front {
                let x = i % w, y = i / w
                var bestCost = Int.max, best = -1
                func consider(_ s: Int) {
                    guard s >= 0, s < w * h, state[s] == 0 else { return }
                    let c = cost(x, y, s % w, s / w)
                    if c < bestCost { bestCost = c; best = s }
                }
                for (dx, dy) in neighbours {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let s = Int(src[ny * w + nx])
                    if s >= 0 { let sx = s % w - dx, sy = s / w - dy; if sx >= 0, sy >= 0, sx < w, sy < h { consider(sy * w + sx) } }
                }
                for _ in 0..<candidates { consider(sources[Int(rng.next() % UInt64(sources.count))]) }
                if best >= 0 {
                    for k in 0..<4 { out[i * 4 + k] = out[best * 4 + k] }
                    src[i] = Int32(best)
                }
                state[i] = 2
                for (dx, dy) in neighbours {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let j = ny * w + nx
                    if state[j] == 1, !queued.contains(j) { queued.insert(j); next.append(j) }
                }
            }
            front = next
        }
        return out
    }

    struct SplitMix { var state: UInt64; mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }

    /// RGBA premultiplied bytes as an image.
    static func image(_ bytes: [UInt8], width w: Int, height h: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

extension Studio {
    /// Edit → Content-aware fill: fills the selection from everything visible around it and puts
    /// the result on the active layer as a picture stroke (one undo step).
    func contentAwareFill() {
        guard let mask = selectionMask(), canEdit, let layer = activeLayer, !layer.isAdjustmentLayer,
              let image = Renderer.render(layers: composite(layers), width: width, height: height), let bitmap = PixelOps.bitmap(image) else { return }
        // One pixel more than the selection, so no old edge survives.
        let hole = PixelOps.grow(mask.map { $0 >= 128 ? 255 : 0 }, width: width, height: height)
        // Fewer random candidates for big holes keeps it to a few seconds at most.
        let count = hole.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
        let filled = ContentAwareFill.fill(bitmap, hole: hole, candidates: max(8, min(40, 3_000_000 / max(1, count))))
        var patch = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) where hole[i] != 0 { for k in 0..<4 { patch[i * 4 + k] = filled[i * 4 + k] } }
        guard let picture = ContentAwareFill.image(patch, width: width, height: height) else { return }
        // Document pixels → the layer's own pixels.
        let local = Self.remap(picture, width: width, height: height, matrix(layer.transform).inverted()) ?? picture
        guard let data = PixelOps.png(local) else { return }
        var stroke = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: .white, width: 1)
        stroke.kind = "bitmap"; stroke.imageData = data
        mutateLayer("Content-aware fill") { $0.strokes.append(stroke) }
    }
}
