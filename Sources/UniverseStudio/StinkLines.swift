import Foundation
import CoreGraphics

/// Animation → Effects → Stink lines (0.272): the comic sign for a bad smell (or steam, in white) –
/// three wavy lines rise above the active layer, wobbling as they go, thin and pale at the top. The
/// wave travels upwards; a seamless loop over the play range (or all frames). Follows the layer. On a
/// new layer above it. One undo step.
enum StinkStyle: String, CaseIterable, Identifiable {
    case stink, steam
    var id: String { rawValue }
    var title: String { switch self { case .stink: "Stink"; case .steam: "Steam" } }
    var colour: CodableColor {
        switch self {
        case .stink: CodableColor(red: 0.45, green: 0.6, blue: 0.2, alpha: 0.85)
        case .steam: CodableColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 0.85)
        }
    }
}

extension Studio {
    /// One wavy line from `base` up by `height`, its wave shifted by `phase` (0…1 = one wave).
    static func wavyLine(base: CGPoint, height: Double, amplitude: Double, phase: Double, colour: CodableColor, width: Double) -> InkStroke {
        let steps = 16
        let pts = (0...steps).map { k -> InkPoint in
            let f = Double(k) / Double(steps)
            let x = base.x + sin(2 * .pi * (f * 1.5 - phase)) * amplitude * (0.4 + 0.6 * f)   // wider towards the top
            return InkPoint(x: x, y: base.y - f * height, pressure: 1 - 0.7 * f)              // thinner towards the top
        }
        return InkStroke(points: pts, color: colour, width: width)
    }

    @discardableResult func addStinkLines(_ style: StinkStyle = .stink) -> Int {
        guard frames.count >= 2, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let height = max(24, local.height * 0.6, local.width * 0.6), amp = max(3, local.width * 0.06), w = max(2, local.width * 0.03)
        checkpoint(style == .stink ? "Stink lines" : "Steam")
        let layer = ArtLayer(name: L(style.title))
        for i in frames.indices {
            var l = layer
            if r.contains(i), let s = frames[i].first(where: { $0.id == src.id }) {
                let m = matrix(s.transform), t = Double(i - r.lowerBound) / Double(r.count)
                l.strokes = [-1.0, 0, 1].enumerated().map { n, side in
                    let base = CGPoint(x: local.midX + side * local.width * 0.25, y: local.minY - (n == 1 ? height * 0.12 : 0)).applying(m)
                    return Studio.wavyLine(base: base, height: height * (n == 1 ? 1.1 : 0.85) * s.transform.scale, amplitude: amp * s.transform.scale,
                                           phase: t + Double(n) * 0.3, colour: style.colour, width: w * s.transform.scale)
                }
            }
            frames[i].insert(l, at: (frames[i].firstIndex { $0.id == src.id }).map { $0 + 1 } ?? frames[i].count)
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return r.count
    }
}
