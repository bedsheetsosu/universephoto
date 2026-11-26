import Foundation
import CoreGraphics

/// Animation → Effects → Smoke trail (0.213): while the active layer moves, it leaves little puffs
/// behind it every few frames – they stay where they were born, grow, drift up and fade. A rocket,
/// a steam train, a car, a running cartoon. On a new layer below the active one. Works on the play
/// range if set. One undo step. Returns how many puffs were made.
extension Studio {
    static let puffLife = 6

    /// One puff `age` frames old (0 ..< puffLife), born at `p`; `size` is the base radius.
    static func puffStroke(born p: CGPoint, age: Int, size: Double, colour: CodableColor) -> InkStroke? {
        let t = Double(age) / Double(puffLife)
        var c = colour; c.alpha = colour.alpha * (1 - t)
        guard c.alpha > 0.02 else { return nil }
        let r = size * (0.5 + 1.1 * t), cy = p.y - size * 1.2 * t
        var s = InkStroke(points: [InkPoint(x: p.x - r, y: cy - r, pressure: 1), InkPoint(x: p.x + r, y: cy + r, pressure: 1)], color: c, width: 1)
        s.kind = "ellipse"; s.filled = true
        return s
    }

    @discardableResult func addSmokeTrail(every: Int = 2, colour: CodableColor = CodableColor(red: 0.72, green: 0.72, blue: 0.74, alpha: 0.6)) -> Int {
        guard frames.count >= 2, every >= 1, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let idx = Array(r)
        let centre = CGPoint(x: local.midX, y: local.midY)
        let pts: [CGPoint?] = idx.map { i in frames[i].first { $0.id == src.id }.map { centre.applying(matrix($0.transform)) } }
        let size = max(4, min(local.width, local.height) * 0.28)
        var perFrame: [Int: [InkStroke]] = [:], puffs = 0
        for k in stride(from: 1, to: idx.count, by: every) {
            guard let p = pts[k], let q = pts[k - 1] else { continue }
            let dx = p.x - q.x, dy = p.y - q.y, d = hypot(dx, dy)
            guard d > 1 else { continue }                          // standing still: no smoke
            // Born at the back edge of the drawing, opposite the way it moves.
            let back = CGPoint(x: p.x - dx / d * local.width * 0.5, y: p.y - dy / d * local.height * 0.5)
            puffs += 1
            for age in 0..<Studio.puffLife where k + age < idx.count {
                if let s = Studio.puffStroke(born: back, age: age, size: size, colour: colour) { perFrame[idx[k + age], default: []].append(s) }
            }
        }
        guard puffs > 0 else { return 0 }
        checkpoint("Smoke trail")
        let layer = ArtLayer(name: L("Smoke trail"))
        for i in frames.indices {
            var l = layer; l.strokes = perFrame[i] ?? []
            frames[i].insert(l, at: frames[i].firstIndex { $0.id == src.id } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return puffs
    }
}
