import Foundation

/// Animate → Layer motion → Path → Arc the path (0.185): bends the active layer's movement into an
/// arc – natural motion rarely runs straight. The bulge is sideways to the line from the first to
/// the last frame, highest in the middle, `amount` × the length of that line (signed: one side or
/// the other). Added on top, so wiggles stay. Needs the layer to travel. Play range if set. One undo step.
extension Studio {
    @discardableResult func arcLayerPath(amount: Double) -> Int {
        guard frames.count >= 3, amount != 0, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let slots = r.compactMap { i in frames[i].firstIndex { $0.id == id }.map { (i, $0) } }
        guard slots.count >= 3, let a = slots.first.map({ frames[$0.0][$0.1].transform }), let b = slots.last.map({ frames[$0.0][$0.1].transform }) else { return 0 }
        let dx = b.x - a.x, dy = b.y - a.y, len = (dx * dx + dy * dy).squareRoot()
        guard len > 1 else { return 0 }
        let nx = -dy / len, ny = dx / len                // left of the direction of travel (y down: "up" for a move to the right)
        var nf = frames, touched = 0
        for (k, (i, j)) in slots.enumerated() where !nf[i][j].locked {
            let bulge = amount * len * sin(.pi * Double(k) / Double(slots.count - 1))
            guard abs(bulge) > 1e-9 else { continue }
            nf[i][j].transform.x += nx * bulge; nf[i][j].transform.y += ny * bulge; touched += 1
        }
        guard touched > 0 else { return 0 }
        checkpoint("Arc the path")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
