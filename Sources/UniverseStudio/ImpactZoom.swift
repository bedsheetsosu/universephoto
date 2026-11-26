import Foundation
import CoreGraphics

/// Animation → Effects → Impact zoom (0.224): wherever the active layer lands (see Landing dust),
/// the whole picture punches in a little and eases back out over a few frames – like a camera
/// reacting to the hit. Every layer is scaled around the middle of the canvas by the same amount.
/// Pairs with Impact shake and Hit stop. Works on the play range if set. One undo step. Returns
/// how many landings were found.
extension Studio {
    /// Extra zoom for `age` frames after a hit (0 = the hit frame).
    static func impactZoom(age: Int, amount: Double) -> Double {
        guard age >= 0, age < 5 else { return 0 }
        return amount * [1, 0.6, 0.3, 0.12, 0.04][age]
    }

    @discardableResult func impactZoom(amount: Double) -> Int {
        guard frames.count >= 3, amount > 0, let src = activeLayer, let local = contentBounds(src) else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        let idx = Array(r)
        let feet: [Double?] = idx.map { i in frames[i].first { $0.id == src.id }.map { local.applying(matrix($0.transform)).maxY } }
        guard feet.allSatisfy({ $0 != nil }) else { return 0 }
        let hits = Studio.landings(feet.map { $0! })
        guard !hits.isEmpty else { return 0 }
        var zoom: [Int: Double] = [:]
        for h in hits { for age in 0..<5 where h + age < idx.count { zoom[idx[h + age], default: 0] += Studio.impactZoom(age: age, amount: amount) } }
        checkpoint("Impact zoom")
        for (i, z) in zoom where z > 1e-9 {
            let f = 1 + z
            for j in frames[i].indices where !frames[i][j].locked && frames[i][j].allFrames != true {
                // Scaling around the canvas middle: the offset from the middle grows by the same factor.
                frames[i][j].transform.scale *= f
                frames[i][j].transform.x *= f; frames[i][j].transform.y *= f
            }
        }
        layers = frames[frameIndex]; changed()
        return hits.count
    }
}
