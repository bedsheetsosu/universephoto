import Foundation

/// Play range from the menu bar (0.196): set its start and end at the current frame (⌥[ / ⌥]),
/// make it span the selected frames, or play everything again (⌥\). The layer effects all work on
/// the play range, so this is how to aim them at one part of an animation.
extension Studio {
    /// Play range over the selected frames (with the current one); returns false with fewer than two.
    @discardableResult func playRangeFromSelection() -> Bool {
        let picked = selectedFrames.union([frameIndex]).filter { frames.indices.contains($0) }
        guard let lo = picked.min(), let hi = picked.max(), hi > lo else { return false }
        playRange = lo...hi
        return true
    }
}
