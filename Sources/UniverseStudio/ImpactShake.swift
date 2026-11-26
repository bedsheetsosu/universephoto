import Foundation
import CoreGraphics

/// Animation → Effects → Impact shake (0.197): wherever the active layer lands (see Landing dust),
/// the whole picture jolts for a few frames and settles – a heavy landing, a stomp. It moves every
/// layer by the same fading offset, like a camera knock. Works on the play range if set. One undo
/// step. Returns how many landings were found.
extension Studio {
    @discardableResult func impactShake(strength: Double) -> Int {
        guard frames.count >= 3, strength > 0, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let idx = Array(r)
        let feet: [Double?] = idx.map { i in frames[i].first { $0.id == src.id }.map { local.applying(matrix($0.transform)).maxY } }
        guard feet.allSatisfy({ $0 != nil }) else { return 0 }
        let hits = Studio.landings(feet.map { $0! })
        guard !hits.isEmpty else { return 0 }
        let jolts = Studio.shakeOffsets(count: 4, seed: 0xB00F)
        var offset: [Int: (Double, Double)] = [:]
        for h in hits {
            for age in 0..<4 where h + age < idx.count {
                let fade = strength * (1 - Double(age) / 4)
                let o = offset[idx[h + age]] ?? (0, 0)
                offset[idx[h + age]] = (o.0 + jolts[age].0 * fade, o.1 + abs(jolts[age].1) * fade * (age == 0 ? 1 : -1))
            }
        }
        checkpoint("Impact shake")
        frames = Studio.unsharedForCamera(frames)          // a jolt moves backgrounds too (0.246)
        for (i, o) in offset {
            for j in frames[i].indices where !frames[i][j].locked {
                frames[i][j].transform.x += o.0; frames[i][j].transform.y += o.1
            }
        }
        layers = frames[frameIndex]; changed()
        return hits.count
    }
}
