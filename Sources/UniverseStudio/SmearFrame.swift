import Foundation

/// Animate → right-click a frame → Smear to next (0.128): drops in a single frame that shows the
/// active layer several times at once, spread from its pose here to its pose in the next frame –
/// the stretched multi-exposure "smear" hand animators use for one fast frame. The copies are
/// faint in the middle and firm at the ends. They are locked layers named "Smear"; hold 1, one undo.
extension Studio {
    static let smearName = "Smear"

    /// `copies` ghosts of `a`'s drawing, their transforms spread from `a` to `b`. The two ends stay
    /// firm, the middle ones fade, so the stack reads as a motion blur.
    static func smearLayers(_ a: ArtLayer, _ b: ArtLayer, copies: Int) -> [ArtLayer] {
        let n = max(2, copies)
        return (0..<n).map { k in
            let t = Double(k) / Double(n - 1)
            var g = a
            g.id = UUID(); g.name = smearName; g.locked = true; g.visible = true
            g.transform = Tween.blend(a.transform, b.transform, t)
            let end = (k == 0 || k == n - 1)
            g.opacity = max(0, min(1, a.opacity * (end ? 0.9 : 0.4)))
            return g
        }
    }

    func insertSmear(after index: Int, copies: Int) {
        guard frames.indices.contains(index), frames.indices.contains(index + 1),
              let activeID = activeLayer?.id,
              let a = frames[index].first(where: { $0.id == activeID }),
              let b = frames[index + 1].first(where: { $0.id == activeID }),
              let at = frames[index].firstIndex(where: { $0.id == activeID }) else { return }
        stopPlayback(); checkpoint("Smear frame")
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        var smear = frames[index]
        smear.replaceSubrange(at...at, with: Self.smearLayers(a, b, copies: copies))
        metaInsert(at: index + 1, holds: [1])
        frames.insert(smear, at: index + 1)
        if frameIndex > index { frameIndex += 1 }
        selectFrame(index + 1)
        changed()
    }
}
