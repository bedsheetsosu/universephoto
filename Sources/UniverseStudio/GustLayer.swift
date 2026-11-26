import Foundation

/// Animation → Layer effects → Gust of wind (0.241): a gust hits the active layer – it bends over on
/// its foot, holds against the wind for a moment, then springs back and wobbles out. A tree, a
/// blade of grass, a sign on a post, someone leaning into a storm. Several selected layers bend
/// together. Over the play range (or all frames). One undo step.
extension Studio {
    /// Lean in degrees for frame `k` of `n`, `degrees` at the strongest (positive = to the right).
    static func gustLean(_ k: Int, of n: Int, degrees: Double) -> Double {
        guard n >= 2 else { return 0 }
        let t = Double(k) / Double(n - 1)
        switch t {
        case ..<0.25: let u = t / 0.25; return degrees * u * u * (3 - 2 * u)        // bends over
        case ..<0.5: return degrees * (1 + 0.05 * sin(.pi * 6 * (t - 0.25) / 0.25))  // holds, trembling
        default:
            let u = (t - 0.5) / 0.5                                                   // springs back and wobbles out
            return degrees * cos(.pi * 2.5 * u) * exp(-4 * u) * (u >= 1 ? 0 : 1)
        }
    }

    @discardableResult func gustLayer(degrees: Double) -> Int {
        guard frames.count >= 4, degrees != 0, let id = activeLayer?.id, activeLayer?.allFrames != true else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        var nf = frames, touched = 0
        for (k, i) in r.enumerated() {
            let lean = Studio.gustLean(k, of: r.count, degrees: degrees)
            guard abs(lean) > 1e-6 else { continue }
            for j in nf[i].indices where nf[i][j].id == id && !nf[i][j].locked {
                pivotEdit(&nf[i][j], .bottom) { $0.rotation += lean }
                touched += 1
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Gust of wind")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
