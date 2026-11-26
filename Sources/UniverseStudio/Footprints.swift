import Foundation
import CoreGraphics

/// Animation → Effects → Footprints (0.242): where the active layer walks, prints stay behind on
/// the ground at its feet – left, right, left – one every few frames while it moves, slowly fading.
/// Snow, sand, mud, a detective story. On a new layer below the active one. Works on the play range
/// if set. One undo step. Returns how many prints there are.
extension Studio {
    @discardableResult func addFootprints(every: Int, colour: CodableColor = CodableColor(red: 0.35, green: 0.28, blue: 0.22, alpha: 0.55)) -> Int {
        guard frames.count >= 2, every >= 1, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let foot = CGPoint(x: local.midX, y: local.maxY)
        let pts: [CGPoint?] = frames.indices.map { i in frames[i].first { $0.id == src.id }.map { foot.applying(matrix($0.transform)) } }
        let size = max(4, local.width * 0.12)
        // Prints: (frame made, position, angle of travel, left/right).
        var prints: [(Int, CGPoint, Double, Bool)] = []
        var left = true
        for i in stride(from: r.lowerBound + 1, through: r.upperBound, by: every) {
            guard let p = pts[i], let q = pts[i - 1] else { continue }
            let dx = p.x - q.x, dy = p.y - q.y, d = hypot(dx, dy)
            guard d > 0.5 else { continue }
            let side = (left ? -1.0 : 1.0) * size * 0.7
            prints.append((i, CGPoint(x: p.x - dy / d * side, y: p.y + dx / d * side), atan2(dy, dx), left))
            left.toggle()
        }
        guard !prints.isEmpty else { return 0 }
        checkpoint("Footprints")
        let layer = ArtLayer(name: L("Footprints"))
        for i in frames.indices {
            var l = layer
            if r.contains(i) {
                l.strokes = prints.filter { $0.0 <= i }.map { made, c, angle, _ in
                    let age = Double(i - made) / Double(max(1, r.count))
                    var col = colour; col.alpha = colour.alpha * max(0.3, 1 - age)
                    // An oval along the direction of travel (approximated axis-aligned for steep paths).
                    let along = abs(cos(angle)) > abs(sin(angle))
                    let w = along ? size * 1.4 : size * 0.8, h = along ? size * 0.8 : size * 1.4
                    var s = InkStroke(points: [InkPoint(x: c.x - w / 2, y: c.y - h / 2, pressure: 1), InkPoint(x: c.x + w / 2, y: c.y + h / 2, pressure: 1)], color: col, width: 1)
                    s.kind = "ellipse"; s.filled = true
                    return s
                }
            }
            frames[i].insert(l, at: frames[i].firstIndex { $0.id == src.id } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return prints.count
    }
}
