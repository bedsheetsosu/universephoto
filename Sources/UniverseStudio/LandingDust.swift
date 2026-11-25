import Foundation
import CoreGraphics

/// Animation → Effects → Landing dust (0.190): finds the frames where the active layer touches down
/// (moving down, then up again) and puffs a little dust cloud at its bottom edge for a few frames –
/// growing, drifting sideways and fading. Pairs with Bounce. On a new layer just below the active
/// one. Works on the play range if set. One undo step. Returns how many landings were found.
extension Studio {
    /// Indices (into `ys`, y down) where a fall turns into a rise.
    static func landings(_ ys: [Double], minDrop: Double = 4) -> [Int] {
        guard ys.count >= 3 else { return [] }
        return (1..<(ys.count - 1)).filter { i in
            ys[i] - ys[i - 1] > minDrop / 2 && ys[i] >= ys[i + 1] && ys[i] > ys[i + 1] - 1e-9 && (ys[i] - ys[i + 1]) + (ys[i] - ys[i - 1]) > minDrop
        }
    }

    /// Dust puffs `age` frames (0…3) after a landing at `foot` (the bottom middle), `width` wide.
    static func dustStrokes(age: Int, foot: CGPoint, width w: Double) -> [InkStroke] {
        let t = Double(age + 1) / 4, alpha = 0.55 * (1 - t * 0.85)
        let colour = CodableColor(red: 0.72, green: 0.68, blue: 0.62, alpha: alpha)
        return [-1.0, -0.45, 0.45, 1.0].map { side in
            let r = (4 + 10 * t) * (abs(side) > 0.5 ? 0.8 : 1)
            let cx = foot.x + side * w * (0.3 + 0.5 * t), cy = foot.y - r * 0.6 - 3 * t
            var puff = InkStroke(points: [InkPoint(x: cx - r, y: cy - r * 0.75, pressure: 1), InkPoint(x: cx + r, y: cy + r * 0.75, pressure: 1)], color: colour, width: 1)
            puff.kind = "ellipse"; puff.filled = true
            return puff
        }
    }

    @discardableResult func addLandingDust() -> Int {
        guard frames.count >= 3, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let idx = Array(r)
        let boxes: [CGRect?] = idx.map { i in frames[i].first { $0.id == src.id }.map { local.applying(matrix($0.transform)) } }
        guard boxes.allSatisfy({ $0 != nil }) else { return 0 }
        let hits = Studio.landings(boxes.map { $0!.maxY })
        guard !hits.isEmpty else { return 0 }
        var perFrame: [Int: [InkStroke]] = [:]
        for h in hits {
            let b = boxes[h]!, foot = CGPoint(x: b.midX, y: b.maxY)
            for age in 0..<4 where h + age < idx.count {
                perFrame[idx[h + age], default: []] += Studio.dustStrokes(age: age, foot: foot, width: b.width)
            }
        }
        checkpoint("Landing dust")
        let layer = ArtLayer(name: L("Landing dust"))
        for i in frames.indices {
            var l = layer; l.strokes = perFrame[i] ?? []
            frames[i].insert(l, at: frames[i].firstIndex { $0.id == src.id } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return hits.count
    }
}
