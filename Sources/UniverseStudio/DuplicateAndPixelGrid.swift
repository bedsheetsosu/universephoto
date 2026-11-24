import AppKit

/// Image → Duplicate: the whole document (layers, frames, groups, guides, comps) as a new,
/// unsaved tab. View → Pixel grid: thin lines between pixels from 800 % zoom on.
extension Studio {
    func duplicateImage() {
        var d = document()
        d.title = LF("%@ copy", documentName)
        let layer = selectedLayer
        newDocument(width: d.width, height: d.height)
        apply(d)
        selectedLayer = min(layer, max(0, layers.count - 1))
        dirty = true; syncTab()
    }

    /// Shown from this zoom factor (screen pixels per image pixel) on.
    static let pixelGridScale = 8.0
    static var pixelGridOn: Bool { UserDefaults.standard.object(forKey: "pixelGrid") as? Bool ?? true }

    /// Pixel-grid lines (document pixels) inside `visible`, nil when zoomed out or too many.
    static func pixelGridLines(visible: CGRect, width w: Int, height h: Int, scale: Double) -> (xs: [Int], ys: [Int])? {
        guard scale >= pixelGridScale else { return nil }
        let r = visible.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !r.isNull, r.width > 0 else { return nil }
        let xs = Array(max(0, Int(r.minX.rounded(.down)))...min(w, Int(r.maxX.rounded(.up))))
        let ys = Array(max(0, Int(r.minY.rounded(.down)))...min(h, Int(r.maxY.rounded(.up))))
        guard xs.count + ys.count < 4000 else { return nil }
        return (xs, ys)
    }
}
