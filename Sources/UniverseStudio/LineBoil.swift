import Foundation

/// Animate → right-click a frame → Line boil (0.92): adds copies of the frame whose active layer
/// wobbles slightly – brush strokes bend a little, pixel layers shift a hair – the hand-drawn
/// "living line". Deterministic (same seed, same wobble), one undo step.
enum LineBoil {
    struct RNG { var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53) * 2 - 1   // −1…1
        }
    }

    /// Smooth wobble: random offsets every few points, eased in between, at most `amount` px.
    static func wobble(_ s: InkStroke, amount: Double, rng: inout RNG) -> InkStroke {
        var out = s
        let n = s.points.count
        guard n > 0, amount > 0 else { return s }
        let step = max(1, min(8, n / 3 + 1)), keys = n / step + 2
        let kx = (0..<keys).map { _ in rng.next() * amount }, ky = (0..<keys).map { _ in rng.next() * amount }
        out.points = s.points.enumerated().map { i, p in
            let f = Double(i) / Double(step), k = Int(f), t = f - Double(k), e = t * t * (3 - 2 * t)
            var q = p
            q.x += kx[k] + (kx[k + 1] - kx[k]) * e; q.y += ky[k] + (ky[k + 1] - ky[k]) * e
            return q
        }
        return out
    }

    static func boiled(_ layer: ArtLayer, amount: Double, seed: UInt64) -> ArtLayer {
        var rng = RNG(state: seed), l = layer
        let canBend: Set<String?> = [nil, "line", "arrow"]
        l.strokes = layer.strokes.map { canBend.contains($0.kind) && $0.imageData == nil ? wobble($0, amount: amount, rng: &rng) : $0 }
        if layer.imageData != nil || layer.strokes.contains(where: { $0.imageData != nil }) {
            l.transform.x += rng.next() * amount * 0.5; l.transform.y += rng.next() * amount * 0.5
            l.transform.rotation += rng.next() * amount * 0.15
        }
        return l
    }
}

extension Studio {
    static let boilChoices = [2, 3, 4]

    /// Inserts `copies` wobbled copies after frame `index` (active layer only). Returns how many.
    @discardableResult func lineBoil(after index: Int, copies: Int, amount: Double = 1.5) -> Int {
        guard frames.indices.contains(index) || (frames.isEmpty && index == 0), copies > 0, let id = activeLayer?.id else { return 0 }
        stopPlayback(); checkpoint("Line boil")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        let source = frames[index]
        let made = (1...copies).map { k in source.map { $0.id == id ? LineBoil.boiled($0, amount: amount, seed: UInt64(k) &* 7919 &+ UInt64(index)) : $0 } }
        metaInsert(at: index + 1, holds: Array(repeating: hold(index), count: copies))
        frames.insert(contentsOf: made, at: index + 1)
        if frameIndex > index { frameIndex += copies }
        layers = frames[frameIndex]
        changed()
        return copies
    }
}
