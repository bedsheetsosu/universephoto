import Foundation

/// Per-frame data next to `frames` – hold, marker name and the pinned reference – kept in step
/// by four operations. Each is called with the frames as they are *before* the change.
extension Studio {
    private var fullHolds: [Int] { (0..<frames.count).map { hold($0) } }
    private var fullLabels: [String] { (0..<frames.count).map { label($0) } }

    func label(_ i: Int) -> String { frameLabels.indices.contains(i) ? frameLabels[i] : "" }

    private func setMeta(_ h: [Int], _ l: [String]) {
        selectedFrames = []   // indices shift: a frame selection would point at other drawings
        frameHolds = h.allSatisfy { $0 == 1 } ? [] : h
        frameLabels = l.allSatisfy(\.isEmpty) ? [] : l
    }

    func metaInsert(at i: Int, holds: [Int]) {
        var h = fullHolds, l = fullLabels
        let at = min(max(0, i), h.count)
        h.insert(contentsOf: holds.map { max(1, $0) }, at: at)
        l.insert(contentsOf: Array(repeating: "", count: holds.count), at: at)
        setMeta(h, l)
        if let r = referenceFrame, r >= at { referenceFrame = r + holds.count }
    }

    func metaRemove(at i: Int) {
        var h = fullHolds, l = fullLabels
        guard h.indices.contains(i) else { return }
        h.remove(at: i); l.remove(at: i)
        setMeta(h, l)
        if let r = referenceFrame { referenceFrame = r == i ? nil : r > i ? r - 1 : r }
    }

    func metaMove(from: Int, to: Int) {
        var h = fullHolds, l = fullLabels
        guard h.indices.contains(from), h.indices.contains(to) else { return }
        h.insert(h.remove(at: from), at: to); l.insert(l.remove(at: from), at: to)
        setMeta(h, l)
        if let r = referenceFrame {
            if r == from { referenceFrame = to } else if from < r && to >= r { referenceFrame = r - 1 } else if from > r && to <= r { referenceFrame = r + 1 }
        }
    }

    func metaReverse(_ range: ClosedRange<Int>) {
        var h = fullHolds, l = fullLabels
        guard range.lowerBound >= 0, range.upperBound < h.count else { return }
        h.replaceSubrange(range, with: h[range].reversed()); l.replaceSubrange(range, with: l[range].reversed())
        setMeta(h, l)
        if let r = referenceFrame, range.contains(r) { referenceFrame = range.lowerBound + range.upperBound - r }
    }

    // MARK: Markers (0.82)

    func setLabel(_ name: String, for index: Int) {
        guard frames.indices.contains(index) || (frames.isEmpty && index == 0) else { return }
        if frames.isEmpty { frames = [layers] }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != label(index) else { return }
        checkpoint("Frame marker")
        var l = fullLabels; l[index] = String(clean.prefix(40))
        setMeta(fullHolds, l); changed()
    }

    /// Named sections: each marker runs until the next one (or the end).
    var markerSections: [(name: String, range: ClosedRange<Int>)] { Self.sections(labels: frameLabels, count: frames.count) }

    nonisolated static func sections(labels: [String], count: Int) -> [(name: String, range: ClosedRange<Int>)] {
        let starts = (0..<count).filter { labels.indices.contains($0) && !labels[$0].isEmpty }
        return starts.enumerated().map { k, start in
            let end = k + 1 < starts.count ? starts[k + 1] - 1 : count - 1
            return (labels[start], start...end)
        }
    }

    /// Plays just this marker's section.
    func playSection(_ name: String) {
        guard let section = markerSections.first(where: { $0.name == name }) else { return }
        playRange = Playback.clamp(section.range, count: frames.count)
        selectFrame(section.range.lowerBound)
    }
}
