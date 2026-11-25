import Foundation

/// Animate → Layer across frames → Copy motion to selected layers (0.154): the other selected
/// layers move like the active one – relative to where each of them starts, so they don't jump onto
/// it. Offsets in position and turn are added, size is multiplied. Opacity stays. Works on the play
/// range if one is set, otherwise all frames. One undo step. Returns how many layer-frames changed.
extension Studio {
    @discardableResult func copyMotionToSelected() -> Int {
        guard frames.count >= 2, let sid = activeLayer?.id else { return 0 }
        let targets = selectedIDs.subtracting([sid])
        guard !targets.isEmpty else { return 0 }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard let s0 = frames[r.lowerBound].first(where: { $0.id == sid })?.transform else { return 0 }
        var base: [UUID: LayerTransform] = [:]
        for l in frames[r.lowerBound] where targets.contains(l.id) { base[l.id] = l.transform }
        var nf = frames, touched = 0
        for i in r {
            guard let s = frames[i].first(where: { $0.id == sid })?.transform else { continue }
            for j in nf[i].indices {
                guard let b = base[nf[i][j].id], !nf[i][j].locked else { continue }
                let n = LayerTransform(x: b.x + s.x - s0.x, y: b.y + s.y - s0.y,
                                       scale: b.scale * (s0.scale == 0 ? 1 : s.scale / s0.scale),
                                       rotation: b.rotation + s.rotation - s0.rotation)
                if nf[i][j].transform != n { nf[i][j].transform = n; touched += 1 }
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Copy motion")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
