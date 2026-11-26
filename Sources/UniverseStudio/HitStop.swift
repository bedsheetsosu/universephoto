import Foundation
import CoreGraphics

/// Animation → Effects → Hit stop (0.205): wherever the active layer lands (see Landing dust), the
/// landing frame is held a little longer – the picture freezes for a beat at the impact, like in games
/// and cartoons. Only holds change, no drawing. Works on the play range if set. One undo step.
/// Returns how many landings were held.
extension Studio {
    @discardableResult func hitStop(extra: Int) -> Int {
        guard frames.count >= 3, extra > 0, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let idx = Array(r)
        let feet: [Double?] = idx.map { i in frames[i].first { $0.id == src.id }.map { local.applying(matrix($0.transform)).maxY } }
        guard feet.allSatisfy({ $0 != nil }) else { return 0 }
        let hits = Studio.landings(feet.map { $0! }).map { idx[$0] }.filter { hold($0) < 99 }
        guard !hits.isEmpty else { return 0 }
        checkpoint("Hit stop")
        var h = (0..<frames.count).map { hold($0) }
        for i in hits { h[i] = min(99, h[i] + extra) }
        frameHolds = h; normalizeHolds(); changed()
        return hits.count
    }
}
