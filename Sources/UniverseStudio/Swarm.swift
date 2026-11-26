import Foundation
import CoreGraphics

/// Animation → Effects → Swarm (0.206): smaller copies of the active layer buzz around it on their
/// own loops – bees, birds, fireflies, a cloud of hearts. Each copy is a new layer behind the
/// original that follows it (and its drawing, if that changes) on a seamless wobbly path of its own.
/// Works on the play range if set (copies are empty outside it). One undo step. Returns the copies.
extension Studio {
    /// Offset of swarm member `c` in frame `k` of `n`, within `radius`: integer frequencies keep it a loop.
    static func swarmOffset(member c: Int, frame k: Int, of n: Int, radius: Double, seed: UInt64 = 0x5A4A) -> CGPoint {
        let r = shakeOffsets(count: c + 1, seed: seed &+ UInt64(c) &* 0x9E37)[c]
        let t = 2 * Double.pi * Double(k) / Double(max(1, n))
        let fx = 1 + Double(c % 2), fy = 1 + Double((c / 2) % 2) + 1
        let px = (r.0 + 1) * .pi, py = (r.1 + 1) * .pi
        return CGPoint(x: radius * (0.55 + 0.45 * abs(r.2)) * sin(fx * t + px),
                       y: radius * 0.6 * sin(fy * t + py))
    }

    @discardableResult func addSwarm(count: Int) -> Int {
        guard count > 0, frames.count >= 2, let src = activeLayer, src.allFrames != true, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let radius = max(40, max(local.width, local.height) * 2.4)
        checkpoint("Swarm")
        for c in 0..<count {
            let id = UUID(), size = 0.45 + 0.3 * abs(Studio.shakeOffsets(count: c + 1, seed: 0x51E)[c].0)
            for i in frames.indices {
                let at = frames[i].firstIndex { $0.id == src.id } ?? frames[i].count
                var copy = (r.contains(i) ? frames[i].first { $0.id == src.id } : nil) ?? ArtLayer(name: "")
                copy.id = id; copy.name = L("Swarm") + " \(c + 1)"; copy.locked = false
                if r.contains(i) {
                    pivotEdit(&copy, .centre) { $0.scale *= size }
                    let o = Studio.swarmOffset(member: c, frame: i - r.lowerBound, of: r.count, radius: radius)
                    copy.transform.x += o.x; copy.transform.y += o.y
                } else { copy.strokes = []; copy.imageData = nil; copy.mask = nil }
                frames[i].insert(copy, at: at)
            }
        }
        layers = frames[frameIndex]
        selectedLayer = layers.firstIndex { $0.id == src.id } ?? selectedLayer
        changed()
        return count
    }
}
