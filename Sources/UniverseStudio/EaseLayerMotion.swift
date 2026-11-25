import Foundation

/// Animate → Layer motion → Ease the motion (0.169): re-times the movement the active layer already
/// has – slow in, slow out or both – by sampling its position, turn and size along an eased clock.
/// A stiff, even glide gets weight without adding frames; first and last frame stay. Opacity and
/// drawings stay. Works on the play range if set. One undo step. Returns frames changed.
extension Studio {
    enum EaseMode: String, CaseIterable, Identifiable {
        case inOut, slowIn, slowOut, anticipate, overshoot, both
        var id: String { rawValue }
        var title: String { switch self { case .inOut: "Slow in and out"; case .slowIn: "Slow start"; case .slowOut: "Slow end"
            case .anticipate: "Wind up first (anticipation)"; case .overshoot: "Overshoot and settle"; case .both: "Wind up and overshoot" } }
        func apply(_ t: Double) -> Double {
            switch self {
            case .inOut: return t * t * (3 - 2 * t)
            case .slowIn: return t * t
            case .slowOut: return 1 - (1 - t) * (1 - t)
            // Back easings (0.186): dip below 0 at the start / rise past 1 at the end.
            case .anticipate: let c = 1.70158; return (c + 1) * t * t * t - c * t * t
            case .overshoot: let c = 1.70158, u = t - 1; return 1 + (c + 1) * u * u * u + c * u * u
            case .both:
                let c = 1.70158 * 1.525
                return t < 0.5 ? (pow(2 * t, 2) * ((c + 1) * 2 * t - c)) / 2
                               : (pow(2 * t - 2, 2) * ((c + 1) * (t * 2 - 2) + c) + 2) / 2
            }
        }
    }

    static func sampled(_ v: [Double], at p: Double) -> Double {
        guard let last = v.indices.last else { return 0 }
        guard last > 0 else { return v[0] }
        // Outside the frames (back easings): continue the first / last step in a straight line.
        if p < 0 { return v[0] + (v[1] - v[0]) * p }
        if p > Double(last) { return v[last] + (v[last] - v[last - 1]) * (p - Double(last)) }
        let a = min(Int(p.rounded(.down)), last - 1), f = p - Double(a)
        return v[a] + (v[a + 1] - v[a]) * f
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
