import Foundation

/// Animate: ping-pong playback (forth and back) and a play range (start/end markers on frames).
enum Playback {
    /// Next frame and direction after `current`, or nil when playback should stop (no loop).
    static func step(current: Int, count: Int, range: ClosedRange<Int>?, loop: Bool, pingPong: Bool, forward: Bool) -> (index: Int, forward: Bool)? {
        guard count > 0 else { return nil }
        let r = clamp(range, count: count) ?? 0...(count - 1)
        guard r.count > 1 else { return loop ? (r.lowerBound, forward) : nil }
        if !r.contains(current) { return (r.lowerBound, true) }
        if pingPong {
            if forward {
                if current < r.upperBound { return (current + 1, true) }
                return (current - 1, false)
            }
            if current > r.lowerBound { return (current - 1, false) }
            return loop ? (current + 1, true) : nil
        }
        if current < r.upperBound { return (current + 1, true) }
        return loop ? (r.lowerBound, true) : nil
    }

    /// The range limited to existing frames; nil when it covers everything or is unset.
    static func clamp(_ range: ClosedRange<Int>?, count: Int) -> ClosedRange<Int>? {
        guard let range, count > 0 else { return nil }
        let lo = max(0, min(range.lowerBound, count - 1)), hi = max(lo, min(range.upperBound, count - 1))
        return lo == 0 && hi == count - 1 ? nil : lo...hi
    }
}

extension Studio {
    func setPlayStart(_ i: Int) {
        let hi = playRange.map { max($0.upperBound, i) } ?? frames.count - 1
        playRange = Playback.clamp(i...max(i, hi), count: frames.count)
    }
    func setPlayEnd(_ i: Int) {
        let lo = playRange.map { min($0.lowerBound, i) } ?? 0
        playRange = Playback.clamp(min(lo, i)...i, count: frames.count)
    }
    func inPlayRange(_ i: Int) -> Bool { Playback.clamp(playRange, count: frames.count)?.contains(i) ?? true }
}
