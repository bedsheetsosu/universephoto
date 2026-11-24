import CoreGraphics
import Foundation

/// Turns one finger into mouse-like actions, the way a pen display's touch works:
/// - lift without moving        → click (at the touch-down point, so taps are precise)
/// - move past `moveThreshold`  → press at the start point, then drag, release on lift
/// - hold still for `longPress` → right click (if enabled)
/// - another finger lands       → whatever started is ended cleanly (gesture takes over)
///
/// Pure state machine (no UIKit) so it can be unit-tested; the canvas feeds touch events and
/// a periodic `tick` for the long-press timeout.
public struct OneFingerGesture: Sendable {
    public enum Output: Equatable, Sendable {
        case press(CGPoint)
        case drag(CGPoint)
        case release(CGPoint)
        case click(CGPoint)
        case rightClick(CGPoint)
    }

    private enum State: Sendable {
        case idle
        case pending(start: CGPoint, time: TimeInterval)
        case dragging
        /// Right click fired or gesture cancelled: ignore this finger until it lifts.
        case consumed
    }

    public var moveThreshold: CGFloat = 8
    public var longPress: TimeInterval = 0.55
    public var longPressEnabled = true

    private var state: State = .idle
    private var last: CGPoint = .zero

    public init() {}

    public var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

    public var isPending: Bool {
        if case .pending = state { return true }
        return false
    }

    public mutating func begin(_ p: CGPoint, at t: TimeInterval) -> [Output] {
        state = .pending(start: p, time: t)
        last = p
        return []
    }

    public mutating func move(_ p: CGPoint, at t: TimeInterval) -> [Output] {
        last = p
        switch state {
        case .pending(let start, _):
            guard hypot(p.x - start.x, p.y - start.y) > moveThreshold else { return [] }
            state = .dragging
            return [.press(start), .drag(p)]
        case .dragging:
            return [.drag(p)]
        case .idle, .consumed:
            return []
        }
    }

    public mutating func tick(at t: TimeInterval) -> [Output] {
        guard longPressEnabled, case .pending(let start, let t0) = state, t - t0 >= longPress else { return [] }
        state = .consumed
        return [.rightClick(start)]
    }

    public mutating func end(_ p: CGPoint) -> [Output] {
        defer { state = .idle }
        switch state {
        case .pending(let start, _): return [.click(start)]
        case .dragging: return [.release(p)]
        case .idle, .consumed: return []
        }
    }

    /// A second finger (or the Pencil) took over.
    public mutating func cancel() -> [Output] {
        switch state {
        case .dragging:
            state = .consumed
            return [.release(last)]
        case .pending:
            state = .consumed
            return []
        case .idle, .consumed:
            return []
        }
    }

    /// Finger lifted after a cancel / right click.
    public mutating func reset() { state = .idle }
}
