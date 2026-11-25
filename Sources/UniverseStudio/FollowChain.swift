import Foundation

/// Animate → Layer motion → Follow in a chain (0.174): the other selected layers take on the active
/// layer's movement, each `step` frames later than the one before (in stack order, nearest first)
/// – a wave running through a tail, a chain, a scarf or a row of letters. Like Copy motion, each
/// moves relative to its own start; the delay loops round. Works on the play range if set.
/// One undo step. Returns how many layer-frames changed.
extension Studio {
    @discardableResult func followInChain(step: Int) -> Int {
        guard frames.count >= 2, step >= 1, let sid = activeLayer?.id else { return 0 }
        let order = layers.map(\.id).filter { selectedIDs.contains($0) && $0 != sid }
        guard !order.isEmpty else { return 0 }
        let active = layers.firstIndex { $0.id == sid } ?? 0
        let pos = Dictionary(uniqueKeysWithValues: layers.enumerated().map { ($0.element.id, $0.offset) })
        let ranked = order.sorted { abs((pos[$0] ?? 0) - active) < abs((pos[$1] ?? 0) - active) }
        stopPlayback()
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let r = Playback.clamp(playRange, count: frames.count) ?? 0...(frames.count - 1)
        guard r.allSatisfy({ i in frames[i].contains { $0.id == sid } }),
              let s0 = frames[r.lowerBound].first(where: { $0.id == sid })?.transform else { return 0 }
        var base: [UUID: LayerTransform] = [:]
        for l in frames[r.lowerBound] where order.contains(l.id) { base[l.id] = l.transform }
        var nf = frames, touched = 0
        for (m, tid) in ranked.enumerated() {
            guard let b = base[tid] else { continue }
            for i in r {
                let src = Studio.delaySource(i, offset: (m + 1) * step, in: r, wrap: true)
                guard let s = frames[src].first(where: { $0.id == sid })?.transform,
                      let j = nf[i].firstIndex(where: { $0.id == tid }), !nf[i][j].locked else { continue }
                var n = LayerTransform(x: b.x + s.x - s0.x, y: b.y + s.y - s0.y,
                                       scale: b.scale * (s0.scale == 0 ? 1 : s.scale / s0.scale),
                                       rotation: b.rotation + s.rotation - s0.rotation)
                n.stretch = s.stretch
                if nf[i][j].transform != n { nf[i][j].transform = n; touched += 1 }
            }
        }
        guard touched > 0 else { return 0 }
        checkpoint("Follow in a chain")
        frames = nf; layers = frames[frameIndex]; changed()
        return touched
    }
}
