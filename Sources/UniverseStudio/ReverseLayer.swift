import Foundation

/// Animate → Layer across frames → Reverse this layer only (0.155): the active layer plays its
/// frames backwards while everything else runs forward – e.g. a door that closes instead of opens,
/// without redrawing. Works on the play range if one is set, otherwise all frames. One undo step.
extension Studio {
    @discardableResult func reverseLayerOnly() -> Int {
        guard frames.count >= 2, let id = activeLayer?.id else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.allSatisfy({ i in frames[i].contains { $0.id == id } }) else { return 0 }
        var nf = frames, touched = 0
        for i in r {
            let src = r.upperBound - (i - r.lowerBound)
            guard let layer = frames[src].first(where: { $0.id == id }), let j = nf[i].firstIndex(where: { $0.id == id }) else { continue }
            if nf[i][j] != layer { nf[i][j] = layer; touched += 1 }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Reverse layer")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
