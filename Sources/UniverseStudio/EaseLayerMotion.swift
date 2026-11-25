import Foundation

/// Animate → Layer motion → Ease the motion (0.169): re-times the movement the active layer already
/// has – slow in, slow out or both – by sampling its position, turn and size along an eased clock.
/// A stiff, even glide gets weight without adding frames; first and last frame stay. Opacity and
/// drawings stay. Works on the play range if set. One undo step. Returns frames changed.
extension Studio {
    enum EaseMode: String, CaseIterable, Identifiable {
        case inOut, slowIn, slowOut
        var id: String { rawValue }
        var title: String { switch self { case .inOut: "Slow in and out"; case .slowIn: "Slow start"; case .slowOut: "Slow end" } }
        func apply(_ t: Double) -> Double {
            switch self {
            case .inOut: t * t * (3 - 2 * t)
            case .slowIn: t * t
            case .slowOut: 1 - (1 - t) * (1 - t)
            }
        }
    }

    static func sampled(_ v: [Double], at p: Double) -> Double {
        guard let last = v.indices.last else { return 0 }
        let q = min(max(p, 0), Double(last)), a = Int(q.rounded(.down)), b = min(a + 1, last), f = q - Double(a)
        return v[a] + (v[b] - v[a]) * f
    }

    @discardableResult func easeLayerMotion(_ mode: EaseMode) -> Int {
        guard frames.count >= 3, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let slots = r.compactMap { i in frames[i].firstIndex { $0.id == id }.map { (i, $0) } }
        guard slots.count >= 3 else { return 0 }
        let t = slots.map { frames[$0.0][$0.1].transform }, n = Double(slots.count - 1)
        let xs = t.map(\.x), ys = t.map(\.y), rs = t.map(\.rotation), ss = t.map(\.scale)
        var nf = frames, touched = 0
        for (k, (i, j)) in slots.enumerated() {
            let p = mode.apply(Double(k) / n) * n
            var v = LayerTransform(x: Studio.sampled(xs, at: p), y: Studio.sampled(ys, at: p),
                                   scale: Studio.sampled(ss, at: p), rotation: Studio.sampled(rs, at: p))
            v.stretch = nf[i][j].transform.stretch
            if nf[i][j].transform != v { nf[i][j].transform = v; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Ease motion")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
