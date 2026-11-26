import Foundation
import CoreGraphics

/// Animation → Effects → Ground shadow (0.203): a soft oval shadow on the ground under the active
/// layer in every frame. The ground is the lowest point the layer reaches; the higher the layer is
/// above it, the smaller and paler the shadow – so a bouncing ball feels like it leaves the floor.
/// On a new layer just below the active one. Works on the play range if set. One undo step.
/// Returns how many frames got a shadow.
extension Studio {
    /// The shadow oval for a drawing `box` (y down) over the ground line `groundY`; `lift` 0…1 is how
    /// high the drawing is compared to its highest point.
    static func shadowStroke(box b: CGRect, groundY: Double, lift: Double) -> InkStroke {
        let k = min(1, max(0, lift))
        let w = max(4, b.width * (1 - 0.55 * k)), h = max(2, w * 0.18)
        let colour = CodableColor(red: 0, green: 0, blue: 0, alpha: 0.32 * (1 - 0.65 * k))
        var s = InkStroke(points: [InkPoint(x: b.midX - w / 2, y: groundY - h / 2, pressure: 1),
                                   InkPoint(x: b.midX + w / 2, y: groundY + h / 2, pressure: 1)], color: colour, width: 1)
        s.kind = "ellipse"; s.filled = true
        return s
    }

    @discardableResult func addGroundShadow() -> Int {
        guard !frames.isEmpty || !layers.isEmpty, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.isEmpty { frames = [layers] }
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let idx = Array(r)
        let boxes: [CGRect?] = idx.map { i in frames[i].first { $0.id == src.id }.map { local.applying(matrix($0.transform)) } }
        let found = boxes.compactMap { $0 }
        guard !found.isEmpty else { return 0 }
        let ground = found.map(\.maxY).max()!
        let top = found.map { ground - $0.maxY }.max()!
        var perFrame: [Int: InkStroke] = [:]
        for (k, i) in idx.enumerated() {
            guard let b = boxes[k] else { continue }
            perFrame[i] = Studio.shadowStroke(box: b, groundY: ground, lift: top > 0.5 ? (ground - b.maxY) / top : 0)
        }
        checkpoint("Ground shadow")
        let layer = ArtLayer(name: L("Ground shadow"))
        for i in frames.indices {
            var l = layer; l.strokes = perFrame[i].map { [$0] } ?? []
            frames[i].insert(l, at: frames[i].firstIndex { $0.id == src.id } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return perFrame.count
    }
}
