import Foundation
import CoreGraphics

/// Animation → Effects → Speed lines (0.189): comic-style motion streaks behind the active layer,
/// worked out from how it actually moves – long lines when it's fast, none when it stands still,
/// always pointing back along its path. Drawn on a new layer just below it, so they stay editable.
/// Works on the play range if set. One undo step. Returns how many frames got lines.
extension Studio {
    /// Lines behind a box moving by `v` (pixels per frame) – `count` streaks spread across the box.
    static func speedLineStrokes(box: CGRect, velocity v: CGVector, count: Int = 5, color: CodableColor) -> [InkStroke] {
        let speed = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        guard speed > 2 else { return [] }
        let ux = v.dx / speed, uy = v.dy / speed, px = -uy, py = ux
        let half = (abs(px) * box.width + abs(py) * box.height) / 2 * 0.8
        let back = (abs(ux) * box.width + abs(uy) * box.height) / 2       // from the centre to the trailing edge
        let len = min(speed * 3, 400)
        return (0..<count).map { k in
            let s = count == 1 ? 0 : (Double(k) / Double(count - 1) * 2 - 1) * half
            let l = len * (0.6 + 0.4 * abs(sin(Double(k) * 2.4)))       // a little uneven
            let sx = box.midX + px * s - ux * (back + 6), sy = box.midY + py * s - uy * (back + 6)
            return InkStroke(points: [InkPoint(x: sx, y: sy, pressure: 1), InkPoint(x: sx - ux * l, y: sy - uy * l, pressure: 0.2)],
                             color: color, width: 2.5)
        }
    }

    @discardableResult func addSpeedLines() -> Int {
        guard frames.count >= 2, let src = activeLayer else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard let local = contentBounds(src) else { return 0 }
        // Screen box of the layer in each frame of the range.
        let boxes: [CGRect?] = r.map { i in frames[i].first { $0.id == src.id }.map { local.applying(matrix($0.transform)) } }
        let colour = CodableColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.55)
        var perFrame: [Int: [InkStroke]] = [:]
        for (k, i) in r.enumerated() where k > 0 {
            guard let a = boxes[k - 1], let b = boxes[k] else { continue }
            let lines = Studio.speedLineStrokes(box: b, velocity: CGVector(dx: b.midX - a.midX, dy: b.midY - a.midY), color: colour)
            if !lines.isEmpty { perFrame[i] = lines }
        }
        guard !perFrame.isEmpty else { return 0 }
        checkpoint("Speed lines")
        let layer = ArtLayer(name: L("Speed lines"))
        for i in frames.indices {
            var l = layer; l.strokes = perFrame[i] ?? []
            let at = frames[i].firstIndex { $0.id == src.id } ?? frames[i].count
            frames[i].insert(l, at: at)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return perFrame.count
    }
}
