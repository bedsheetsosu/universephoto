import Foundation

/// Layout of the Pencil palette (UniversePen 1.1, replaces the arc of the radial menu): a small
/// floating grid of buttons near the Pencil tip, like the squeeze palettes of note apps. It stays
/// open while you use it; pure geometry here so it can be tested without UIKit.
public enum PaletteGridLayout {
    public static let button: Double = 58
    public static let gap: Double = 8
    public static let padding: Double = 12
    /// Strip on top with the grab handle and the close button.
    public static let header: Double = 30
    /// Distance between the Pencil tip and the panel, and from the screen edges.
    public static let tipGap: Double = 26
    public static let margin: Double = 12

    /// 2 → 2 columns, 3–4 → one row, 5–6 → 3, 7–9 → 3, 10–12 → 4.
    public static func columns(count: Int) -> Int {
        switch count { case ...4: return max(1, count); case 5...9: return 3; default: return 4 }
    }
    public static func rows(count: Int) -> Int { max(1, Int((Double(count) / Double(columns(count: count))).rounded(.up))) }

    public static func size(count: Int) -> (width: Double, height: Double) {
        let c = Double(columns(count: count)), r = Double(rows(count: count))
        return (padding * 2 + c * button + (c - 1) * gap, header + padding + r * button + (r - 1) * gap)
    }

    /// Top-left corner of the panel for a tip at (x, y) on a `width` × `height` screen: centred
    /// above the tip, below it when there is no room, always fully on screen.
    public static func origin(tipX x: Double, tipY y: Double, width: Double, height: Double, count: Int) -> (x: Double, y: Double) {
        let s = size(count: count)
        var oy = y - tipGap - s.height
        if oy < margin { oy = y + tipGap }
        oy = min(max(margin, oy), max(margin, height - margin - s.height))
        let ox = min(max(margin, x - s.width / 2), max(margin, width - margin - s.width))
        return (ox, oy)
    }

    /// Centre of item `i`, relative to the panel's top-left corner.
    public static func center(of i: Int, count: Int) -> (x: Double, y: Double) {
        let c = columns(count: count), col = i % c, row = i / c
        return (padding + Double(col) * (button + gap) + button / 2, header + Double(row) * (button + gap) + button / 2)
    }

    /// Item under point (x, y) relative to the panel's top-left corner, or nil between or outside
    /// the buttons.
    public static func item(x: Double, y: Double, count: Int) -> Int? {
        let c = columns(count: count)
        let gx = x - padding, gy = y - header
        guard gx >= 0, gy >= 0 else { return nil }
        let col = Int(gx / (button + gap)), row = Int(gy / (button + gap))
        guard col < c, gx - Double(col) * (button + gap) <= button, gy - Double(row) * (button + gap) <= button else { return nil }
        let i = row * c + col
        return i < count ? i : nil
    }
}
