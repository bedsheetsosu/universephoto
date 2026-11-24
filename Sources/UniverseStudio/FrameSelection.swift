import AppKit

/// Animate (0.86): several frames at once – ⌘-click adds or removes a frame, ⇧-click selects the
/// run from the current frame; delete, hold and copy then act on all of them.
extension Studio {
    /// The frames an action applies to: the selection plus the current frame, or just `index`
    /// when it is outside the selection.
    func framesForAction(at index: Int) -> [Int] {
        let picked = selectedFrames.union([frameIndex]).filter { frames.indices.contains($0) }
        return picked.contains(index) && picked.count > 1 ? picked.sorted() : [index]
    }

    func clickFrame(_ index: Int, command: Bool, shift: Bool) {
        guard frames.indices.contains(index) else { return }
        if shift {
            let lo = min(frameIndex, index), hi = max(frameIndex, index)
            selectedFrames = Set(lo...hi)
        } else if command {
            if index == frameIndex { return }
            if selectedFrames.contains(index) { selectedFrames.remove(index) } else { selectedFrames.insert(index) }
        } else {
            selectedFrames = []
            stepToFrame(index)
        }
    }

    func removeFrames(_ indices: [Int]) {
        let picked = Array(Set(indices.filter { frames.indices.contains($0) })).sorted(by: >)
        guard !picked.isEmpty, picked.count < frames.count else { return }
        stopPlayback(); checkpoint(picked.count > 1 ? "Delete frames" : "Delete frame")
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }
        let keep = frameIndex
        for i in picked { metaRemove(at: i); frames.remove(at: i) }
        let before = picked.filter { $0 < keep }.count
        frameIndex = min(max(0, picked.contains(keep) ? keep - before : keep - before), frames.count - 1)
        layers = frames[frameIndex]; selectedFrames = []
        changed()
    }

    func setHold(_ n: Int, for indices: [Int]) {
        let picked = indices.filter { frames.indices.contains($0) }
        guard !picked.isEmpty, picked.contains(where: { hold($0) != n }) else { return }
        checkpoint("Frame hold")
        var h = (0..<frames.count).map { hold($0) }
        for i in picked { h[i] = max(1, min(99, n)) }
        frameHolds = h; normalizeHolds(); changed()
    }
}
