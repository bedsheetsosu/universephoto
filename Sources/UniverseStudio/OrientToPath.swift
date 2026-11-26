import Foundation
import CoreGraphics

/// Animation → Layer motion → Turn with the path (0.210): the active layer turns to face where it
/// is going – a paper plane, a fish, a car on a hilly road. The direction of the first move counts as
/// "straight ahead" (as drawn); later frames turn by how much the path bends from there. Where the
/// layer stands still, it keeps its last heading. Turns around the drawing. Works on the play range
/// if set. One undo step. Returns how many frames turned.
extension Studio {
    /// Heading in degrees (y down, clockwise) per point, from its neighbours; unwrapped so it never
    /// jumps by 360; `nil` until the path has moved at all, then held while standing still.
    static func headings(_ pts: [CGPoint], minStep: Double = 0.5) -> [Double?] {
        var out: [Double?] = [], last: Double? = nil
        for i in pts.indices {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            if hypot(dx, dy) > minStep {
                var h = atan2(dy, dx) * 180 / .pi
                if let l = last { while h - l > 180 { h -= 360 }; while h - l < -180 { h += 360 } }
                last = h
            }
            out.append(last)
        }
        // Frames before the first move take the first heading.
        if let first = out.first(where: { $0 != nil }) ?? nil { out = out.map { $0 ?? first } }
        return out
    }

    @discardableResult func orientToPath() -> Int {
        guard frames.count >= 2, let src = activeLayer, src.allFrames != true, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let idx = Array(r)
        let centre = CGPoint(x: local.midX, y: local.midY)
        let pts: [CGPoint?] = idx.map { i in frames[i].first { $0.id == src.id }.map { centre.applying(matrix($0.transform)) } }
        guard pts.allSatisfy({ $0 != nil }) else { return 0 }
        let hs = Studio.headings(pts.map { $0! })
        guard let base = hs.first ?? nil else { return 0 }
        var nf = frames, turned = 0
        for (k, i) in idx.enumerated() {
            guard let h = hs[k], abs(h - base) > 1e-6 else { continue }
            for j in nf[i].indices where nf[i][j].id == src.id {
                pivotEdit(&nf[i][j], .centre) { $0.rotation += h - base }
                turned += 1
            }
        }
        guard turned > 0 else { return 0 }
        checkpoint("Turn with the path")
        frames = nf; layers = frames[frameIndex]; changed()
        return turned
    }
}
