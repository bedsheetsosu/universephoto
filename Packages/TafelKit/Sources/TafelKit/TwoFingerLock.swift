import Foundation

/// Decides once per two-finger touch whether the fingers scroll or zoom, and keeps that until
/// they lift. Pinching always moves the fingers' centre a little and panning always changes their
/// distance a little; sending both made the Mac jump up/down/up while zooming.
public struct TwoFingerLock: Sendable, Equatable {
    public enum Mode: Sendable, Equatable { case undecided, scroll, zoom }
    public private(set) var mode: Mode = .undecided
    /// Movement of the fingers' centre (points) that means scrolling…
    public var panThreshold: Double
    /// …and change of their distance (fraction, 0.06 = 6 %) that means zooming.
    public var zoomThreshold: Double
    private var pan = 0.0
    private var scale = 1.0

    public init(panThreshold: Double = 14, zoomThreshold: Double = 0.06) {
        self.panThreshold = panThreshold; self.zoomThreshold = zoomThreshold
    }

    /// New touch: decide again.
    public mutating func reset() { mode = .undecided; pan = 0; scale = 1 }

    /// The pan gesture's total translation since the fingers went down.
    @discardableResult public mutating func pan(translation: Double) -> Mode {
        pan = translation; return decide()
    }

    /// The pinch gesture's total scale since the fingers went down.
    @discardableResult public mutating func pinch(scale: Double) -> Mode {
        self.scale = scale; return decide()
    }

    private mutating func decide() -> Mode {
        guard mode == .undecided else { return mode }
        // Compare both against their thresholds; whichever is further past its own wins.
        let zoom = abs(log(max(scale, 0.0001))) / log(1 + zoomThreshold), scroll = pan / panThreshold
        if zoom >= 1 || scroll >= 1 { mode = zoom >= scroll ? .zoom : .scroll }
        return mode
    }
}
