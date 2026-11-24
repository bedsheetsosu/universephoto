import UIKit
import SwiftUI
import AVFoundation
import GameController
import TafelKit

/// Full-screen surface: shows the video layer and turns Pencil + finger input into wire messages.
///
/// - Pencil touches (`UITouch.TouchType.pencil`) -> pen samples, all coalesced samples (up to 240 Hz).
///   Predicted touches are *not* sent: they would draw strokes the user never made.
/// - Pencil hover (`UIHoverGestureRecognizer`, iPad with hover support) -> proximity + move.
/// - Pencil Pro squeeze / double tap (`UIPencilInteraction`) -> configured shortcut.
/// - Fingers (direct touches only) -> pan / pinch / rotate / multi-finger taps. Finger touches
///   never draw; this doubles as palm rejection. Gestures are suppressed while the Pencil is active.
final class CanvasView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate, UIPointerInteractionDelegate {
    var session: Session?
    var settings = InputSettings()
    var onAction: ((PencilAction) -> Void)?
    /// Gesture report for the developer API (in addition to the action).
    var onGesture: ((GestureEvent) -> Void)?
    var onPixelSize: ((Int, Int) -> Void)?
    /// Radial menu: open at a point, or (already open) pick what the Pencil hovers over.
    var onRadialOpen: ((CGPoint) -> Void)?
    var onRadialPick: (() -> Void)?
    var radialOpen = false { didSet { if radialOpen { ink.clear() } } }
    /// The control centre is open: the next touch on the canvas closes it. A Pencil stroke goes
    /// on as usual; fingers only close it (a dismissing tap must not click on the Mac).
    var chromeOpen = false
    var onChromeDismiss: (() -> Void)?
    private var dismissingTouches: Set<UITouch> = []
    /// Local instant ink and hover dot above the picture.
    let ink = InkOverlayView()
    /// Undo scrub progress (steps, negative = undo), nil when it ends.
    var onScrub: ((Int?) -> Void)?
    private var undoScrub: UILongPressGestureRecognizer?
    private var scrubbing = false
    private var scrubOriginX: CGFloat = 0
    private var scrubDone = 0
    private var lastHoverPoint: CGPoint?
    private var squeezing = false
    private var touchedWhileSqueezing = false
    var videoSize: CGSize = .zero { didSet { setNeedsLayout() } }
    /// Hidden text field for the on-screen keyboard.
    let keyboardProxy = KeyboardProxy()
    /// Hardware keys currently held (HID usages as sent), released on focus loss.
    private var heldKeys: Set<UInt16> = []

    private let videoLayer: AVSampleBufferDisplayLayer
    private var pencilTouch: UITouch?
    /// Trackpad/mouse click in progress (indirect pointer touch).
    private var pointerTouch: UITouch?
    /// Finger touches currently down that are not palms.
    private var fingerTouches = Set<UITouch>()
    private var oneFinger = OneFingerGesture()
    private var trackedFinger: UITouch?
    private var fingerTimer: Timer?
    private var lastScroll: CGPoint = .zero
    private var hovering = false
    private var lastPencilActivity = Date.distantPast
    /// Last time the Pencil actually touched the glass (hover does not count).
    private var lastPencilContact = Date.distantPast
    private var smoothX = SampleSmoother(amount: 0)
    private var smoothY = SampleSmoother(amount: 0)
    private var smoothP = SampleSmoother(amount: 0)

    private var lastPan: CGPoint = .zero
    private var lastPinchScale: CGFloat = 1
    /// Scroll or zoom, decided once per two-finger touch (see `TwoFingerLock`).
    private var twoFingerLock = TwoFingerLock()
    private var panActive = false
    private var pinchActive = false
    private var zoomSteps = StepAccumulator(stepSize: 0.35)
    private var lastRotation: CGFloat = 0
    // Local zoom ("only on the iPad"): screen = centre + (content − centre)·scale + offset.
    private(set) var zoomScale: CGFloat = 1
    private var zoomOffset: CGPoint = .zero
    /// Local view rotation (radians), like turning a sheet of paper; iPad only.
    private(set) var viewAngle: CGFloat = 0
    private var localTurn: (angle: CGFloat, content: CGPoint)?
    var onLocalAngle: ((CGFloat) -> Void)?
    private var localPinch: (scale: CGFloat, content: CGPoint)?
    var onLocalZoom: ((CGFloat) -> Void)?
    // Ruler: fingers on it move/turn it, Pencil strokes near its edges stay straight.
    let rulerView = RulerView()
    private var rulerTouches: [UITouch] = []
    private var rulerGrab: (ruler: Ruler, points: [CGPoint])?
    private var rulerLine: SnapLine?
    private var rulerStart: CGPoint?
    private var squeezeHoldWork: DispatchWorkItem?
    private var heldSqueezeKey: HoldKey?
    /// Hold / release a key on the Mac (spring-loaded squeeze).
    var onHoldKey: ((HoldKey, Bool) -> Void)?
    /// Live pressure meter (bottom left): a bar filled to the pressure sent to the Mac.
    private let meterTrack = CALayer()
    private let meterFill = CALayer()
    private var measureClear: DispatchWorkItem?
    // Shape recognition: the stroke so far (view points), its pressures, and the hold timer.
    private var shapePoints: [CGPoint] = []
    private var shapePressures: [Double] = []
    private var shapeTilt = CGPoint.zero
    private var shapeAnchor = CGPoint.zero
    private var shapeHold: DispatchWorkItem?
    /// The stroke was replaced by a clean shape; ignore the rest of it until the Pencil lifts.
    private var shapeSnapped = false
    private var rope = Rope(length: 0)
    private var lastSpeedSample: (point: CGPoint, time: TimeInterval)?
    private var smoothSpeed: Double = 0
    private var rulerPlaced = false
    var rulerVisible = false {
        didSet {
            guard rulerVisible != oldValue else { return }
            rulerView.isHidden = !rulerVisible
            if rulerVisible && !rulerPlaced, bounds.width > 0 {
                rulerView.ruler = Ruler(center: CGPoint(x: bounds.midX, y: bounds.midY), angle: 0, length: 2.5 * max(bounds.width, bounds.height))
                rulerPlaced = true
            }
            if !rulerVisible { rulerTouches = []; rulerGrab = nil; rulerLine = nil }
        }
    }
    // Perspective / ellipse aids (fingers move their knobs, the Pencil follows them).
    let guideView = GuideView()
    var guideKind: DrawingGuide = .none {
        didSet { if guideKind != oldValue { applyGuideKind() } }
    }
    private var perspective: PerspectiveGuide?
    private var ellipseGuide: EllipseGuide?
    private enum GuideGrab {
        case vanishingPoint(Int)
        case axis(Int)
        case body(EllipseGuide, [CGPoint])
    }
    private var guideTouches: [UITouch] = []
    private var guideGrab: GuideGrab?
    /// Perspective stroke waiting for its direction (start point).
    private var perspectiveStart: CGPoint?
    private var guideLine: SnapLine?
    private var ellipseSnap = false

    private func applyGuideKind() {
        guideTouches = []; guideGrab = nil
        switch guideKind {
        case .perspective(let n):
            if perspective?.points.count != n, bounds.width > 0 {
                perspective = .defaultLayout(count: n, in: bounds.size)
            }
            guideView.content = perspective.map { .perspective($0) } ?? .none
        case .ellipse:
            if ellipseGuide == nil, bounds.width > 0 {
                ellipseGuide = EllipseGuide(center: CGPoint(x: bounds.midX, y: bounds.midY),
                                            rx: bounds.width * 0.22, ry: bounds.height * 0.16)
            }
            guideView.content = ellipseGuide.map { .ellipse($0) } ?? .none
        default:
            guideView.content = .none
        }
        guideView.isHidden = guideView.content == .none
    }

    /// Fingers on a vanishing point, an ellipse knob or inside the ellipse belong to the aid.
    private func guideHit(_ p: CGPoint) -> Bool {
        switch guideKind {
        case .perspective: return !guidesLocked && perspective?.handle(at: p) != nil
        case .ellipse: return !guidesLocked && (ellipseGuide.map { $0.handle(at: p) != nil || $0.containsBody(p) } ?? false)
        default: return false
        }
    }

    private func captureGuideTouches(_ touches: inout Set<UITouch>) {
        for t in touches where t.type == .direct {
            let p = t.location(in: self)
            switch guideKind {
            case .perspective:
                if !guidesLocked, guideTouches.isEmpty, let i = perspective?.handle(at: p) {
                    guideTouches = [t]; guideGrab = .vanishingPoint(i); touches.remove(t)
                }
            case .ellipse:
                guard !guidesLocked, let e = ellipseGuide else { continue }
                if guideTouches.isEmpty, let i = e.handle(at: p) {
                    guideTouches = [t]; guideGrab = .axis(i); touches.remove(t)
                } else if guideTouches.count < 2, e.containsBody(p) || !guideTouches.isEmpty && e.handle(at: p) == nil {
                    if case .axis = guideGrab { continue }
                    guideTouches.append(t); touches.remove(t)
                    guideGrab = .body(e, guideTouches.map { $0.location(in: self) })
                }
            default:
                break
            }
        }
    }

    private func moveGuide() {
        guard let grab = guideGrab, !guideTouches.isEmpty else { return }
        let now = guideTouches.map { $0.location(in: self) }
        switch grab {
        case .vanishingPoint(let i):
            perspective?.points[i] = now[0]
        case .axis(let i):
            ellipseGuide?.drag(handle: i, to: now[0])
        case .body(let start, let points):
            var e = start
            if now.count >= 2, points.count >= 2 {
                let d0 = max(hypot(points[1].x - points[0].x, points[1].y - points[0].y), 1)
                let d1 = hypot(now[1].x - now[0].x, now[1].y - now[0].y)
                let s = d1 / d0
                e.rx = max(start.rx * s, 20); e.ry = max(start.ry * s, 20)
                let a0 = atan2(points[1].y - points[0].y, points[1].x - points[0].x)
                let a1 = atan2(now[1].y - now[0].y, now[1].x - now[0].x)
                e.angle = Ruler.snapped(start.angle + Double(a1 - a0))
                let m0 = CGPoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2)
                let m1 = CGPoint(x: (now[0].x + now[1].x) / 2, y: (now[0].y + now[1].y) / 2)
                e.center = CGPoint(x: start.center.x + m1.x - m0.x, y: start.center.y + m1.y - m0.y)
            } else {
                e.center = CGPoint(x: start.center.x + now[0].x - points[0].x, y: start.center.y + now[0].y - points[0].y)
            }
            ellipseGuide = e
        }
        guideView.content = guideKind == .ellipse ? ellipseGuide.map { .ellipse($0) } ?? .none
                                                  : perspective.map { .perspective($0) } ?? .none
    }

    private func releaseGuide(_ touches: Set<UITouch>) {
        let before = guideTouches.count
        guideTouches.removeAll { touches.contains($0) }
        guard guideTouches.count != before else { return }
        if guideTouches.isEmpty {
            guideGrab = nil
        } else if case .body = guideGrab, let e = ellipseGuide {
            guideGrab = .body(e, guideTouches.map { $0.location(in: self) })
        }
    }

    private var rotateSteps = StepAccumulator(stepSize: 15)

    init(renderer: VideoRenderer) {
        videoLayer = renderer.layer
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        // VoiceOver: one element for the Mac picture that passes touches straight through,
        // so Pencil and fingers keep working with VoiceOver on.
        isAccessibilityElement = true
        accessibilityLabel = L("Mac-Bildschirm")
        accessibilityHint = L("Direkt bedienen: Pencil und Finger gehen an den Mac.")
        accessibilityTraits = .allowsDirectInteraction
        layer.addSublayer(videoLayer)
        addSubview(rulerView)
        rulerView.isHidden = true
        addSubview(guideView)
        guideView.isHidden = true
        meterTrack.backgroundColor = UIColor.black.withAlphaComponent(0.45).cgColor
        meterTrack.cornerRadius = 4
        meterTrack.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        meterTrack.borderWidth = 1
        meterFill.cornerRadius = 3
        meterTrack.addSublayer(meterFill)
        meterTrack.isHidden = true
        layer.addSublayer(meterTrack)
        addSubview(ink)
        addSubview(keys)
        keys.isHidden = true
        keys.onKey = { [weak self] k, down in
            if down { self?.onInput?() }
            self?.session?.send(charKey: CharKeyEvent(key: k, down: down))
        }
        setupGestures()
        let pencil = UIPencilInteraction(delegate: self)
        addInteraction(pencil)
        addInteraction(UIPointerInteraction(delegate: self))
        keyboardProxy.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        keyboardProxy.onText = { [weak self] t in self?.session?.send(text: t) }
        keyboardProxy.onKey = { [weak self] usage in
            self?.session?.send(KeyEvent(hidUsage: usage, down: true))
            self?.session?.send(KeyEvent(hidUsage: usage, down: false))
        }
        addSubview(keyboardProxy)
    }

    // MARK: Hardware keyboard

    override var canBecomeFirstResponder: Bool { true }

    /// iPadOS reserves three-finger swipes/taps for text editing (undo, redo, edit menu) on the
    /// first responder – which is this canvas (it takes the keyboard). Opt out so Tafel's own
    /// three-finger gestures receive them.
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    override func resignFirstResponder() -> Bool {
        releaseKeys()
        return super.resignFirstResponder()
    }

    /// Every key goes to the Mac as a physical key position (incl. modifiers). iPadOS keeps a few
    /// system shortcuts for itself (e.g. ⌘-Tab, ⌘-Space, Globe), those never arrive here.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        onInput?()
        var unhandled = Set<UIPress>()
        for p in presses {
            guard let usage = hidUsage(p) else { unhandled.insert(p); continue }
            heldKeys.insert(usage)
            session?.send(KeyEvent(hidUsage: usage, down: true))
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        keyUp(presses, event, cancelled: false)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        keyUp(presses, event, cancelled: true)
    }

    private func keyUp(_ presses: Set<UIPress>, _ event: UIPressesEvent?, cancelled: Bool) {
        var unhandled = Set<UIPress>()
        for p in presses {
            guard let usage = hidUsage(p) else { unhandled.insert(p); continue }
            heldKeys.remove(usage)
            session?.send(KeyEvent(hidUsage: usage, down: false))
        }
        if !unhandled.isEmpty {
            if cancelled { super.pressesCancelled(unhandled, with: event) } else { super.pressesEnded(unhandled, with: event) }
        }
    }

    private func hidUsage(_ p: UIPress) -> UInt16? {
        guard let key = p.key else { return nil }
        let raw = UInt16(truncatingIfNeeded: key.keyCode.rawValue)
        let usage = settings.swapISOKeys ? HIDKeyMap.swapISO(raw) : raw
        return HIDKeyMap.macKeyCode(usage) != nil ? usage : nil
    }

    /// Monitor only: no input reaches the Mac. Entering it ends whatever is in progress cleanly.
    private(set) var viewOnly = false

    func setViewOnly(_ on: Bool, session s: Session?) {
        if on && !viewOnly {
            if let p = pencilTouch {
                let n = normalizeInput(p.preciseLocation(in: self))
                session?.send(PenSample(phase: .cancel, x: Float(n.x), y: Float(n.y), timestamp: p.timestamp))
                pencilTouch = nil
            }
            emitFinger(oneFinger.cancel())
            trackedFinger = nil
            fingerTimer?.invalidate(); fingerTimer = nil
            if let t = pointerTouch { sendMouse(.up, t.location(in: self)); pointerTouch = nil }
            releaseKeys()
            keys.releaseAll()
            ink.clear()
        }
        viewOnly = on
        // Without a session nothing can be sent: every input path ends in `session?.send`.
        session = on ? nil : s
    }

    func releaseKeys() {
        for usage in heldKeys { session?.send(KeyEvent(hidUsage: usage, down: false)) }
        heldKeys.removeAll()
    }

    /// Shows or hides the on-screen keyboard (does nothing visible with a hardware keyboard).
    private var keyboardShown: Bool?

    /// Called on every SwiftUI update (several times a second). Only act when the on-screen
    /// keyboard setting actually changes: grabbing first responder on every update would steal
    /// it from an open menu, which then blinks and loses the item you are holding.
    func setOnScreenKeyboard(_ visible: Bool) {
        guard visible != keyboardShown else { return }
        keyboardShown = visible
        if visible {
            if !keyboardProxy.isFirstResponder { keyboardProxy.becomeFirstResponder() }
        } else if keyboardProxy.isFirstResponder {
            keyboardProxy.resignFirstResponder()
            becomeFirstResponder()
        } else if window != nil, !isFirstResponder {
            becomeFirstResponder()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // bounds + position (not frame): the layer may carry the local zoom transform.
        videoLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        videoLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        updateGrid()
        clampZoom()
        applyZoom()
        CATransaction.commit()
        ink.frame = bounds
        rulerView.frame = bounds
        guideView.frame = bounds
        meterTrack.frame = CGRect(x: 16, y: bounds.height - 156, width: 10, height: 120)
        if guideKind != .none, guideView.content == .none { applyGuideKind() }
        keys.frame = bounds
        let scale = traitCollection.displayScale
        onPixelSize?(Int((bounds.width * scale).rounded()), Int((bounds.height * scale).rounded()))
    }

    /// Tablet mode: no picture (the surface below shows through), Pencil maps onto the active area.
    var tabletMode = false {
        didSet {
            guard tabletMode != oldValue else { return }
            videoLayer.isHidden = tabletMode
            if tabletMode { resetLocalZoom() }
            backgroundColor = tabletMode ? .clear : .black
            if tabletMode { emitFinger(oneFinger.cancel()) } else { keys.releaseAll() }
            keys.isHidden = !tabletMode || !settings.tabletKeys.enabled
        }
    }

    /// Area the input coordinates refer to: the picture, or the active area in tablet mode.
    var inputRect: CGRect { tabletMode ? settings.tabletArea.rect(in: bounds.size) : videoRect }

    /// View point → normalised input position (picture, or the possibly rotated tablet area).
    func normalizeInput(_ p: CGPoint) -> CGPoint {
        tabletMode ? settings.tabletArea.normalized(p, in: bounds.size) : Geometry.normalized(contentPoint(p), in: videoRect)
    }

    // MARK: Local zoom

    /// Screen point → point in the unzoomed picture.
    private func contentPoint(_ p: CGPoint) -> CGPoint {
        guard zoomScale != 1 || zoomOffset != .zero || mirrored || viewAngle != 0 else { return p }
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let m: CGFloat = mirrored ? -1 : 1
        let dx = p.x - c.x - zoomOffset.x, dy = p.y - c.y - zoomOffset.y
        let ca = cos(-viewAngle), sa = sin(-viewAngle)
        let rx = dx * ca - dy * sa, ry = dx * sa + dy * ca
        return CGPoint(x: c.x + m * rx / zoomScale, y: c.y + ry / zoomScale)
    }

    /// Offset that puts picture point `content` under screen point `screen` at this scale and angle.
    private func offsetKeeping(_ content: CGPoint, at screen: CGPoint, scale s: CGFloat, angle: CGFloat) -> CGPoint {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let m: CGFloat = mirrored ? -1 : 1
        let vx = (content.x - c.x) * s * m, vy = (content.y - c.y) * s
        let ca = cos(angle), sa = sin(angle)
        return CGPoint(x: screen.x - c.x - (vx * ca - vy * sa), y: screen.y - c.y - (vx * sa + vy * ca))
    }

    /// Snaps to 0/90/180/270° within 6°.
    private static func snapAngle(_ a: CGFloat) -> CGFloat {
        let q = CGFloat.pi / 2
        let n = (a / q).rounded() * q
        return abs(a - n) < 6 * .pi / 180 ? n : a
    }

    /// Screen tilt → picture tilt (undo the view's rotation and mirroring).
    func contentTilt(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        let ca = cos(-Double(viewAngle)), sa = sin(-Double(viewAngle))
        let rx = x * ca - y * sa, ry = x * sa + y * ca
        return (mirrored ? -rx : rx, ry)
    }

    /// The picture is shown mirrored on the iPad only (checking proportions); input is mirrored back.
    var mirrored = false {
        didSet {
            guard mirrored != oldValue else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            applyZoom()
            CATransaction.commit()
        }
    }

    private var localZoomActive: Bool { settings.zoomMethod == .localView && !tabletMode }

    /// Keeps the zoomed picture covering the screen.
    private func clampZoom() {
        if viewAngle != 0 {
            // Turned: the picture cannot cover the screen anyway; keep it reachable.
            zoomScale = min(max(zoomScale, 0.5), 8)
            let mx = bounds.width / 2 * zoomScale, my = bounds.height / 2 * zoomScale
            zoomOffset = CGPoint(x: min(max(zoomOffset.x, -mx), mx), y: min(max(zoomOffset.y, -my), my))
            return
        }
        zoomScale = min(max(zoomScale, 1), 8)
        let mx = bounds.width / 2 * (zoomScale - 1), my = bounds.height / 2 * (zoomScale - 1)
        zoomOffset = CGPoint(x: min(max(zoomOffset.x, -mx), mx), y: min(max(zoomOffset.y, -my), my))
    }

    private func applyZoom() {
        videoLayer.setAffineTransform(CGAffineTransform(translationX: zoomOffset.x, y: zoomOffset.y)
            .rotated(by: viewAngle)
            .scaledBy(x: zoomScale * (mirrored ? -1 : 1), y: zoomScale))
    }

    private func setZoom(_ scale: CGFloat, _ offset: CGPoint) {
        let before = zoomScale
        zoomScale = scale
        zoomOffset = offset
        clampZoom()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyZoom()
        CATransaction.commit()
        if abs(before - zoomScale) > 0.001 || zoomScale == 1 { onLocalZoom?(zoomScale) }
    }

    func resetLocalZoom() {
        guard zoomScale != 1 || zoomOffset != .zero || viewAngle != 0 else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        zoomScale = 1
        zoomOffset = .zero
        viewAngle = 0
        applyZoom()
        CATransaction.commit()
        onLocalZoom?(1)
        onLocalAngle?(0)
    }

    // MARK: Ruler touches

    private func snapshotRuler() {
        rulerGrab = rulerTouches.isEmpty ? nil : (rulerView.ruler, rulerTouches.map { $0.location(in: self) })
    }

    private func moveRuler() {
        guard let g = rulerGrab, !rulerTouches.isEmpty else { return }
        let now = rulerTouches.map { $0.location(in: self) }
        var r = g.ruler
        if now.count >= 2, g.points.count >= 2 {
            let m0 = CGPoint(x: (g.points[0].x + g.points[1].x) / 2, y: (g.points[0].y + g.points[1].y) / 2)
            let m1 = CGPoint(x: (now[0].x + now[1].x) / 2, y: (now[0].y + now[1].y) / 2)
            let a0 = atan2(g.points[1].y - g.points[0].y, g.points[1].x - g.points[0].x)
            let a1 = atan2(now[1].y - now[0].y, now[1].x - now[0].x)
            r.angle = Ruler.snapped(g.ruler.angle + Double(a1 - a0))
            // Turn around the fingers' midpoint, then follow it.
            let v = CGPoint(x: g.ruler.center.x - m0.x, y: g.ruler.center.y - m0.y)
            let da = r.angle - g.ruler.angle
            r.center = CGPoint(x: m1.x + v.x * cos(da) - v.y * sin(da), y: m1.y + v.x * sin(da) + v.y * cos(da))
        } else {
            r.center = CGPoint(x: g.ruler.center.x + now[0].x - g.points[0].x, y: g.ruler.center.y + now[0].y - g.points[0].y)
        }
        rulerView.ruler = r
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard touch.type == .direct else { return true }
        if chromeOpen { return false }
        let p = touch.location(in: self)
        return !(rulerVisible && rulerView.ruler.contains(p)) && !guideHit(p)
    }

    /// Tablet keys ("ExpressKeys") above the surface in tablet mode.
    let keys = TabletKeysView()
    private var tipGate = TipGate()
    private var tapGate = DoubleTapClickGate()

    /// Where the video is drawn inside the view (aspect fit, same as the layer's gravity).
    // MARK: Grid

    /// Composition grid, a sublayer of the picture so it zooms, turns and mirrors with it.
    private let gridLayer: CAShapeLayer = {
        let l = CAShapeLayer()
        l.fillColor = nil
        l.lineWidth = 1
        l.strokeColor = UIColor.white.withAlphaComponent(0.45).cgColor
        l.shadowColor = UIColor.black.cgColor
        l.shadowOpacity = 0.6
        l.shadowRadius = 1
        l.shadowOffset = .zero
        return l
    }()

    var grid: GridStyle = .off { didSet { if grid != oldValue { updateGrid() } } }
    var gridCells = 8 { didSet { if gridCells != oldValue { updateGrid() } } }
    /// Strokes that start near a grid line follow it.
    var gridSnap = false
    /// Vanishing points and the ellipse cannot be moved (no accidental drags while drawing).
    var guidesLocked = false
    var gridOpacity: CGFloat = 0.45 { didSet { if gridOpacity != oldValue { gridLayer.strokeColor = UIColor.white.withAlphaComponent(gridOpacity).cgColor } } }
    /// The grid line (picture coordinates) the current stroke follows.
    private var gridLine: SnapLine?

    /// Picture point → screen point (inverse of contentPoint).
    private func screenPoint(_ p: CGPoint) -> CGPoint {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let m: CGFloat = mirrored ? -1 : 1
        let vx = (p.x - c.x) * zoomScale * m, vy = (p.y - c.y) * zoomScale
        let ca = cos(viewAngle), sa = sin(viewAngle)
        return CGPoint(x: c.x + zoomOffset.x + vx * ca - vy * sa, y: c.y + zoomOffset.y + vx * sa + vy * ca)
    }

    private func nearestGridLine(to screen: CGPoint) -> SnapLine? {
        guard gridSnap, grid != .off else { return nil }
        let p = contentPoint(screen)
        var best: (SnapLine, CGFloat)?
        for (a, b) in grid.lines(in: videoRect, cells: gridCells) {
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            guard len > 0 else { continue }
            let line = SnapLine(origin: a, direction: CGPoint(x: dx / len, y: dy / len))
            let q = line.project(p)
            let d = hypot(q.x - p.x, q.y - p.y) * zoomScale
            if d < 24, d < (best?.1 ?? .infinity) { best = (line, d) }
        }
        return best?.0
    }

    private func updateGrid() {
        if gridLayer.superlayer == nil { videoLayer.addSublayer(gridLayer) }
        let path = UIBezierPath()
        for (a, b) in grid.lines(in: videoRect, cells: gridCells) { path.move(to: a); path.addLine(to: b) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gridLayer.frame = videoLayer.bounds
        gridLayer.path = path.cgPath
        gridLayer.isHidden = grid == .off
        CATransaction.commit()
    }

    var videoRect: CGRect {
        videoSize == .zero ? bounds : Geometry.aspectFit(content: videoSize, in: bounds)
    }

    // MARK: Pencil touches

    /// Any input (touch, hover, key) – wakes a dimmed screen.
    var onInput: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onInput?()
        // Back to the canvas after a menu or sheet took the keyboard focus (hardware keyboard).
        if keyboardShown != true, !isFirstResponder { becomeFirstResponder() }
        var touches = touches
        if chromeOpen {
            onChromeDismiss?()
            let fingers = touches.filter { $0.type == .direct }
            dismissingTouches.formUnion(fingers)
            touches.subtract(fingers)
        }
        if rulerVisible {
            for t in touches where t.type == .direct && rulerTouches.count < 2 && rulerView.ruler.contains(t.location(in: self)) {
                if rulerTouches.isEmpty { rulerTapStart = t.timestamp }
                rulerTouches.append(t)
                touches.remove(t)
            }
            snapshotRuler()
        }
        if guideKind != .none, guideKind != .ruler { captureGuideTouches(&touches) }
        fingersBegan(touches)
        if settings.trackpadAsMouse, pointerTouch == nil, let t = touches.first(where: { $0.type == .indirectPointer }) {
            pointerTouch = t
            let right = event?.buttonMask.contains(.secondary) == true
            sendMouse(.down, t.location(in: self), button: right ? .right : .left)
        }
        for t in touches where t.type == .pencil && pencilTouch == nil {
            if squeezing { touchedWhileSqueezing = true }
            // The Pencil always wins over a finger in progress.
            emitFinger(oneFinger.cancel())
            pencilTouch = t
            lastPencilActivity = Date()
            lastPencilContact = Date()
            send(t, .down)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if rulerTouches.contains(where: { touches.contains($0) }) { moveRuler() }
        if guideTouches.contains(where: { touches.contains($0) }) { moveGuide() }
        if let f = trackedFinger, touches.contains(f) {
            for c in event?.coalescedTouches(for: f) ?? [f] {
                emitFinger(oneFinger.move(c.location(in: self), at: c.timestamp))
            }
        }
        if let t = pointerTouch, touches.contains(t) {
            for c in event?.coalescedTouches(for: t) ?? [t] { sendMouse(.move, c.location(in: self)) }
        }
        guard let p = pencilTouch, touches.contains(p) else { return }
        lastPencilActivity = Date()
        lastPencilContact = Date()
        let samples = event?.coalescedTouches(for: p) ?? [p]
        for c in samples { send(c, .move) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        dismissingTouches.subtract(touches)
        releaseRuler(touches)
        releaseGuide(touches)
        fingersEnded(touches)
        endPointer(touches)
        endPencil(touches, phase: .up)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dismissingTouches.subtract(touches)
        releaseRuler(touches)
        releaseGuide(touches)
        for t in touches where t === trackedFinger { emitFinger(oneFinger.cancel()) }
        fingersEnded(touches)
        endPointer(touches)
        endPencil(touches, phase: .cancel)
    }

    /// Double-tap on the ruler: back to 0°, or to 90° when it is already level.
    private var lastRulerTap: TimeInterval = 0

    private func checkRulerDoubleTap(_ touches: Set<UITouch>) {
        for t in touches where rulerTouches.contains(t) && rulerTouches.count == 1 {
            let quick = t.timestamp - (rulerTapStart ?? t.timestamp) < 0.25
            let still = rulerGrab.map { hypot(t.location(in: self).x - $0.points[0].x, t.location(in: self).y - $0.points[0].y) < 8 } ?? false
            guard quick, still else { lastRulerTap = 0; continue }
            if t.timestamp - lastRulerTap < 0.4 {
                var r = rulerView.ruler
                r.angle = abs(r.angle.truncatingRemainder(dividingBy: .pi)) < 0.001 ? .pi / 2 : 0
                rulerView.ruler = r
                lastRulerTap = 0
            } else {
                lastRulerTap = t.timestamp
            }
        }
    }
    private var rulerTapStart: TimeInterval?

    private func releaseRuler(_ touches: Set<UITouch>) {
        checkRulerDoubleTap(touches)
        let before = rulerTouches.count
        rulerTouches.removeAll { touches.contains($0) }
        if rulerTouches.count != before { snapshotRuler() }
    }

    // MARK: One finger (pen-display style touch)

    /// Single-finger input is allowed only when it cannot be a resting hand: no Pencil in range
    /// or in use (and not for 0.6 s after it), and not a large contact area.
    private var fingerAllowed: Bool {
        !tabletMode && settings.fingerMode != .off && session != nil && !hovering && pencilTouch == nil
            && Date().timeIntervalSince(lastPencilActivity) > 0.6
    }

    private func isPalm(_ t: UITouch) -> Bool { t.majorRadius > CGFloat(settings.palmRadius) }

    private func fingersBegan(_ touches: Set<UITouch>) {
        for t in touches where t.type == .direct && !isPalm(t) { fingerTouches.insert(t) }
        if fingerTouches.count == 1, trackedFinger == nil, let t = fingerTouches.first, touches.contains(t), fingerAllowed {
            trackedFinger = t
            oneFinger.longPressEnabled = settings.longPressRightClick
            emitFinger(oneFinger.begin(t.location(in: self), at: t.timestamp))
            fingerTimer?.invalidate()
            fingerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.emitFinger(self.oneFinger.tick(at: ProcessInfo.processInfo.systemUptime))
            }
        } else if fingerTouches.count > 1 {
            // A multi-finger gesture is starting: end the single-finger action cleanly.
            emitFinger(oneFinger.cancel())
        }
    }

    private func fingersEnded(_ touches: Set<UITouch>) {
        for t in touches { fingerTouches.remove(t) }
        if let f = trackedFinger, touches.contains(f) {
            emitFinger(oneFinger.end(f.location(in: self)))
            trackedFinger = nil
            fingerTimer?.invalidate()
            fingerTimer = nil
        }
    }

    private func emitFinger(_ outputs: [OneFingerGesture.Output]) {
        for o in outputs {
            switch (settings.fingerMode, o) {
            case (_, .rightClick(let p)):
                sendMouse(.down, p, button: .right)
                sendMouse(.up, p)
            case (.pen, .press(let p)): sendFingerPen(.down, p)
            case (.pen, .drag(let p)): sendFingerPen(.move, p)
            case (.pen, .release(let p)): sendFingerPen(.up, p); sendFingerPen(.exit, p)
            case (.pen, .click(let p)): sendFingerPen(.down, p); sendFingerPen(.up, p); sendFingerPen(.exit, p)
            // Pointer: moving the finger only moves the pointer; a tap clicks.
            case (.pointer, .press(let p)), (.pointer, .drag(let p)): sendMouse(.move, p)
            case (.pointer, .release): break
            case (_, .press(let p)): sendMouse(.down, p)
            case (_, .drag(let p)): sendMouse(.move, p)
            case (_, .release(let p)): sendMouse(.up, p)
            case (_, .click(let p)): sendMouse(.down, p); sendMouse(.up, p)
            }
        }
    }

    private func sendFingerPen(_ phase: PenPhase, _ location: CGPoint) {
        guard let session else { return }
        let n = normalizeInput(location)
        let touching = phase == .down || phase == .move
        session.send(PenSample(phase: phase, x: Float(n.x), y: Float(n.y),
                               pressure: touching ? Float(settings.fingerPressure) : 0,
                               tiltX: 0, tiltY: 0, rotation: 0, timestamp: ProcessInfo.processInfo.systemUptime))
    }

    // MARK: Trackpad / mouse

    private func endPointer(_ touches: Set<UITouch>) {
        guard let t = pointerTouch, touches.contains(t) else { return }
        pointerTouch = nil
        sendMouse(.up, t.location(in: self))
    }

    private func sendMouse(_ phase: MouseEvent.Phase, _ location: CGPoint, button: MouseEvent.Button = .left) {
        guard let session else { return }
        let n = normalizeInput(location)
        session.send(MouseEvent(phase: phase, button: button, x: Float(n.x), y: Float(n.y)))
    }

    /// Pointer moving without a click.
    @objc private func handlePointerHover(_ g: UIHoverGestureRecognizer) {
        guard settings.trackpadAsMouse, pointerTouch == nil else { return }
        switch g.state {
        case .began, .changed: sendMouse(.move, g.location(in: self))
        default: break
        }
    }

    /// Two-finger scrolling on the trackpad (or a mouse wheel) – arrives as scroll events, not touches.
    @objc private func handleTrackpadScroll(_ g: UIPanGestureRecognizer) {
        guard settings.trackpadAsMouse, let session else { return }
        let t = g.translation(in: self)
        switch g.state {
        case .began:
            lastScroll = t
        case .changed:
            let r = videoRect
            guard r.width > 0, r.height > 0 else { return }
            let dx = (t.x - lastScroll.x) / r.width
            let dy = (t.y - lastScroll.y) / r.height
            lastScroll = t
            let a = anchor(g)
            session.send(ScrollEvent(x: Float(a.x), y: Float(a.y), dx: Float(dx), dy: Float(dy)))
        default:
            break
        }
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        // The Mac cursor is part of the video; a second iPad pointer on top would only confuse.
        settings.hideIPadPointer && session != nil ? .hidden() : nil
    }

    private func endPencil(_ touches: Set<UITouch>, phase: PenPhase) {
        guard let p = pencilTouch, touches.contains(p) else { return }
        send(p, phase)
        pencilTouch = nil
        lastPencilActivity = Date()
        lastPencilContact = Date()
        // Without hover support there is no "out of range" signal: leave proximity shortly after lift.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.pencilTouch == nil, !self.hovering else { return }
            self.session?.send(PenSample(phase: .exit, x: 0, y: 0))
        }
    }

    private func send(_ t: UITouch, _ rawPhase: PenPhase) {
        guard let session else { return }
        // Ruler: a stroke that starts near an edge stays on that edge's line.
        var loc = t.preciseLocation(in: self)
        if rawPhase == .down { rulerLine = rulerVisible ? rulerView.ruler.snapLine(for: loc) : nil }
        if let line = rulerLine {
            loc = line.project(loc)
            // Measure the stroke along the ruler (shown in its label, kept a moment after lifting).
            if rawPhase == .down { rulerStart = loc; measureClear?.cancel() }
            if let s = rulerStart { rulerView.measuredMM = hypot(loc.x - s.x, loc.y - s.y) * RulerView.mmPerPoint }
            if rawPhase == .up || rawPhase == .cancel {
                rulerStart = nil
                let w = DispatchWorkItem { [weak self] in self?.rulerView.measuredMM = nil }
                measureClear = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
            }
        }
        // Perspective: the stroke picks its vanishing line after 10 pt; ellipse: strokes that
        // start on the outline band stay on it.
        if rawPhase == .down {
            guideLine = nil
            perspectiveStart = nil
            ellipseSnap = false
            if rulerLine == nil, case .perspective = guideKind, perspective != nil { perspectiveStart = loc }
            if rulerLine == nil, guideKind == .ellipse, let e = ellipseGuide, e.snaps(loc) { ellipseSnap = true }
        }
        if let start = perspectiveStart, guideLine == nil, rawPhase == .move {
            if hypot(loc.x - start.x, loc.y - start.y) < PerspectiveGuide.decideDistance { return }
            guideLine = perspective?.snapLine(start: start, toward: loc)
            guideView.activeLine = guideLine
            if guideLine != nil { snapFeedback(at: loc) }
        }
        if let line = guideLine { loc = line.project(loc) }
        if rawPhase == .down { gridLine = rulerLine == nil && perspectiveStart == nil && !ellipseSnap ? nearestGridLine(to: loc) : nil }
        // Pencil Pro tick when a stroke locks onto an aid.
        if rawPhase == .down, rulerLine != nil || ellipseSnap || gridLine != nil { snapFeedback(at: loc) }
        if let g = gridLine { loc = screenPoint(g.project(contentPoint(loc))) }
        if ellipseSnap, let e = ellipseGuide { loc = e.project(loc) }
        defer {
            if rawPhase == .up || rawPhase == .cancel {
                rulerLine = nil; guideLine = nil; perspectiveStart = nil; ellipseSnap = false; gridLine = nil
                guideView.activeLine = nil
            }
        }
        // Pencil without hover: a touch only moves the pointer; touch again at once to click.
        if settings.doubleTapToClick {
            let at = loc
            if rawPhase == .down { _ = tapGate.begin(at: at, time: t.timestamp) }
            if !tapGate.armed {
                if rawPhase == .up || rawPhase == .cancel { tapGate.end(at: at, time: t.timestamp); return }
                let n = normalizeInput(at)
                session.send(PenSample(phase: .hover, x: Float(n.x), y: Float(n.y), timestamp: t.timestamp))
                return
            }
            if rawPhase == .up || rawPhase == .cancel { tapGate.end(at: at, time: t.timestamp) }
        }
        let touchingRaw = rawPhase == .down || rawPhase == .move
        // Tip threshold: below it a touching Pencil stays hover (no click).
        let curved = touchingRaw ? settings.pressure.apply(force: Double(t.force), maximumForce: Double(t.maximumPossibleForce)) : 0
        guard let phase = tipGate.phase(for: rawPhase, pressure: curved, threshold: settings.tipThreshold) else { return }
        if shapeSnapped {
            if phase == .up || phase == .cancel { shapeSnapped = false }
            return
        }
        // Rope stabilizer (not with straight-line aids, which are steadier already).
        if settings.ropeLength > 0, !tabletMode, rulerLine == nil, guideLine == nil, !ellipseSnap, gridLine == nil {
            switch phase {
            case .down: rope = Rope(length: settings.ropeLength); loc = rope.start(at: loc)
            case .move: loc = rope.pull(to: loc)
            case .up, .cancel: if let p = rope.point { loc = p }; rope.end()
            default: break
            }
        }
        if settings.instantInk, phase == .down || phase == .move {
            let raw = t.maximumPossibleForce > 0 ? Double(t.force / t.maximumPossibleForce) : 0.5
            ink.add(loc, pressure: settings.pressure.map(raw), newStroke: phase == .down)
        }
        if phase == .down { ink.setHover(nil) }
        var n = normalizeInput(loc)
        let touching = phase == .down || phase == .move
        var pressure = touching ? settings.pressure.apply(force: Double(t.force), maximumForce: Double(t.maximumPossibleForce)) : 0
        if phase == .down {
            smoothX = SampleSmoother(amount: settings.positionSmoothing)
            smoothY = SampleSmoother(amount: settings.positionSmoothing)
            smoothP = SampleSmoother(amount: settings.pressureSmoothing)
        }
        if touching {
            n = CGPoint(x: smoothX.add(Double(n.x)), y: smoothY.add(Double(n.y)))
            pressure = smoothP.add(pressure)
            if settings.constantPressure > 0 { pressure = settings.constantPressure }
            if settings.speedPressure > 0 {
                if phase == .down { lastSpeedSample = nil; smoothSpeed = 0 }
                if let last = lastSpeedSample, t.timestamp > last.time {
                    let v = hypot(loc.x - last.point.x, loc.y - last.point.y) / (t.timestamp - last.time)
                    smoothSpeed += (Double(v) - smoothSpeed) * 0.25
                }
                lastSpeedSample = (loc, t.timestamp)
                pressure = SpeedPressure.apply(pressure, speed: smoothSpeed, amount: settings.speedPressure)
            }
        }
        var tilt = settings.tilt.tilt(altitude: Double(t.altitudeAngle), azimuth: Double(t.azimuthAngle(in: self)))
        let tiltIn = contentTilt(Double(tilt.x), Double(tilt.y))
        tilt.x = .init(tiltIn.x); tilt.y = .init(tiltIn.y)
        let roll = settings.sendRoll ? Double(t.rollAngle) * 180 / .pi : 0
        session.send(PenSample(phase: phase, x: Float(n.x), y: Float(n.y), pressure: Float(pressure),
                               tiltX: Float(tilt.x), tiltY: Float(tilt.y), rotation: Float(roll), timestamp: t.timestamp))
        trackShape(loc, phase: phase, pressure: pressure, tilt: CGPoint(x: tilt.x, y: tilt.y))
        if settings.pressureMeter { showPressure(touching ? pressure : 0) }
    }

    func hidePressureMeter() { meterTrack.isHidden = true }

    private func snapFeedback(at p: CGPoint) {
        if #available(iOS 17.5, *) { UICanvasFeedbackGenerator(view: self).alignmentOccurred(at: p) }
    }

    private func showPressure(_ p: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        meterTrack.isHidden = false
        let h = (meterTrack.bounds.height - 4) * CGFloat(min(max(p, 0), 1))
        meterFill.frame = CGRect(x: 2, y: meterTrack.bounds.height - 2 - h, width: meterTrack.bounds.width - 4, height: h)
        meterFill.backgroundColor = ink.color.cgColor
        CATransaction.commit()
    }

    // MARK: Shape recognition

    private func trackShape(_ loc: CGPoint, phase: PenPhase, pressure: Double, tilt: CGPoint) {
        guard settings.shapeRecognition, !tabletMode, rulerLine == nil, perspectiveStart == nil, !ellipseSnap, gridLine == nil else { return }
        switch phase {
        case .down:
            shapePoints = [loc]; shapePressures = [pressure]; shapeTilt = tilt
            shapeAnchor = loc
            scheduleShapeHold()
        case .move:
            shapePoints.append(loc); shapePressures.append(pressure); shapeTilt = tilt
            // Only real movement restarts the hold timer (pressure changes alone don't).
            if hypot(loc.x - shapeAnchor.x, loc.y - shapeAnchor.y) > 3 {
                shapeAnchor = loc
                scheduleShapeHold()
            }
        default:
            shapeHold?.cancel(); shapeHold = nil
            shapePoints = []; shapePressures = []
        }
    }

    private func scheduleShapeHold() {
        shapeHold?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snapShape() }
        shapeHold = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// The Pencil rested 0.5 s: if the stroke looks like a shape, lift the pen on the Mac, undo
    /// the hand-drawn stroke and draw the clean shape as a new one with the stroke's average pressure.
    private func snapShape() {
        guard pencilTouch != nil, !shapeSnapped, let session, shapePoints.count >= 6,
              let shape = ShapeRecognizer.recognize(shapePoints), let end = shapePoints.last else { return }
        shapeSnapped = true
        let pressure = shapePressures.reduce(0, +) / Double(max(shapePressures.count, 1))
        let tilt = shapeTilt
        var time = ProcessInfo.processInfo.systemUptime
        let e = normalizeInput(end)
        session.send(PenSample(phase: .up, x: Float(e.x), y: Float(e.y), timestamp: time))
        onAction?(.undo)
        ink.clear()
        if #available(iOS 17.5, *) { UICanvasFeedbackGenerator(view: self).alignmentOccurred(at: end) }
        let outline = shape.sampled(spacing: 3)
        // Give the Mac app a moment to undo before the new stroke starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, let session = self.session, let last = outline.last else { return }
            for (i, q) in outline.enumerated() {
                let n = self.normalizeInput(q)
                time += 0.002
                session.send(PenSample(phase: i == 0 ? .down : .move, x: Float(n.x), y: Float(n.y), pressure: Float(pressure),
                                       tiltX: Float(tilt.x), tiltY: Float(tilt.y), timestamp: time))
                if self.settings.instantInk { self.ink.add(q, pressure: pressure, newStroke: i == 0) }
            }
            let n = self.normalizeInput(last)
            session.send(PenSample(phase: .up, x: Float(n.x), y: Float(n.y), timestamp: time + 0.002))
        }
        shapePoints = []; shapePressures = []
    }

    // MARK: Hover

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        let gone = g.state == .ended || g.state == .cancelled || g.state == .failed
        if g.state == .began { onInput?() }
        lastHoverPoint = gone ? nil : g.location(in: self)
        // Show which edge a stroke would snap to before the Pencil touches.
        let hp = lastHoverPoint
        rulerView.highlightSide = rulerVisible ? hp.flatMap { rulerView.ruler.snapSide(for: $0) } : nil
        guideView.highlight = guideKind == .ellipse && hp.map { ellipseGuide?.snaps($0) ?? false } == true
        // While the radial menu is open nothing goes to the Mac, but the hover state must still
        // end – otherwise single-finger input stays blocked ("Pencil is hovering").
        if radialOpen { if gone { hovering = false }; return }
        if viewOnly { hovering = false; ink.setHover(nil); return }
        ink.hoverTilt = settings.hoverTilt && !gone
            ? CGVector(dx: cos(g.azimuthAngle(in: self)) * (1 - g.altitudeAngle / (.pi / 2)),
                       dy: sin(g.azimuthAngle(in: self)) * (1 - g.altitudeAngle / (.pi / 2)))
            : nil
        ink.setHover(settings.hoverDot && !gone && pencilTouch == nil ? g.location(in: self) : nil)
        guard settings.sendHover, let session else { return }
        let n = normalizeInput(g.location(in: self))
        let tilt = settings.tilt.tilt(altitude: Double(g.altitudeAngle), azimuth: Double(g.azimuthAngle(in: self)))
        let roll = settings.sendRoll ? Double(g.rollAngle) * 180 / .pi : 0
        func sample(_ phase: PenPhase) -> PenSample {
            PenSample(phase: phase, x: Float(n.x), y: Float(n.y), pressure: 0, tiltX: Float(tilt.x), tiltY: Float(tilt.y),
                      rotation: Float(roll), timestamp: ProcessInfo.processInfo.systemUptime)
        }
        switch g.state {
        case .began:
            hovering = true
            lastPencilActivity = Date()
            session.send(sample(.enter))
            session.send(sample(.hover))
        case .changed:
            lastPencilActivity = Date()
            if pencilTouch == nil { session.send(sample(.hover)) }
        case .ended, .cancelled, .failed:
            hovering = false
            if pencilTouch == nil { session.send(sample(.exit)) }
        default:
            break
        }
    }

    // MARK: Pencil Pro gestures

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        guard !viewOnly else { return }
        onGesture?(GestureEvent(name: "pencil.doubleTap"))
        perform(settings.doubleTap, at: tap.hoverPose?.location)
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard !viewOnly else { return }
        // Begin/end for plugins (e.g. "hold squeeze and drag the Pencil to scroll").
        if squeeze.phase == .began {
            squeezing = true
            touchedWhileSqueezing = false
            onGesture?(GestureEvent(name: "pencil.squeezeBegan"))
            // Spring-loaded key: after 0.35 s of squeezing the key goes down until release.
            if let key = settings.squeezeHoldKey {
                let w = DispatchWorkItem { [weak self] in
                    guard let self, self.squeezing else { return }
                    self.heldSqueezeKey = key
                    self.onHoldKey?(key, true)
                }
                squeezeHoldWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
            }
        }
        if squeeze.phase == .ended || squeeze.phase == .cancelled {
            onGesture?(GestureEvent(name: "pencil.squeezeEnded", value: touchedWhileSqueezing ? 1 : 0))
            squeezing = false
            squeezeHoldWork?.cancel(); squeezeHoldWork = nil
            if let key = heldSqueezeKey {
                heldSqueezeKey = nil
                onHoldKey?(key, false)
                return   // it was a hold, not a squeeze tap
            }
        }
        guard squeeze.phase == .ended else { return }
        // The Pencil touched the glass while squeezed: the squeeze was used as a modifier
        // (e.g. squeeze-scroll), so its own action (radial menu, undo, …) does not run.
        if touchedWhileSqueezing { touchedWhileSqueezing = false; return }
        onGesture?(GestureEvent(name: "pencil.squeeze"))
        perform(settings.squeeze, at: squeeze.hoverPose?.location)
    }

    private func perform(_ action: PencilAction, at hover: CGPoint?) {
        guard action == .radialMenu else { onAction?(action); return }
        if radialOpen { onRadialPick?(); return }
        // The Mac should not keep a hovering pen while the menu is up.
        if hovering, pencilTouch == nil, let session, let p = lastHoverPoint {
            let n = normalizeInput(p)
            session.send(PenSample(phase: .exit, x: Float(n.x), y: Float(n.y), timestamp: ProcessInfo.processInfo.systemUptime))
        }
        let at = hover ?? lastHoverPoint ?? CGPoint(x: bounds.midX, y: bounds.midY)
        hovering = false   // the Mac got its exit above; hover resumes after the menu closes
        onRadialOpen?(at)
    }

    // MARK: Finger gestures

    private func setupGestures() {
        let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        // Pencil hover and trackpad pointer both produce hover events; keep them apart.
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        addGestureRecognizer(hover)
        let pointerHover = UIHoverGestureRecognizer(target: self, action: #selector(handlePointerHover(_:)))
        pointerHover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        addGestureRecognizer(pointerHover)

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleTrackpadScroll(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = []   // only scroll events, never touches
        scroll.delegate = self
        addGestureRecognizer(scroll)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        let tap2 = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        tap2.numberOfTouchesRequired = 2
        let tap3 = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap))
        tap3.numberOfTouchesRequired = 3
        let tap4 = UITapGestureRecognizer(target: self, action: #selector(handleFourFingerTap))
        tap4.numberOfTouchesRequired = 4
        var swipes: [UIGestureRecognizer] = []
        for dir in [UISwipeGestureRecognizer.Direction.left, .right, .up, .down] {
            let g = UISwipeGestureRecognizer(target: self, action: #selector(handleThreeFingerSwipe(_:)))
            g.direction = dir
            g.numberOfTouchesRequired = 3
            swipes.append(g)
        }
        for g in [pan, pinch, rotate, tap2, tap3, tap4] + swipes as [UIGestureRecognizer] {
            g.allowedTouchTypes = direct
            g.cancelsTouchesInView = false
            g.delegate = self
            addGestureRecognizer(g)
        }
        // Undo scrub: two fingers rest briefly, then drag left (undo) / right (redo).
        let scrub = UILongPressGestureRecognizer(target: self, action: #selector(handleUndoScrub(_:)))
        scrub.numberOfTouchesRequired = 2
        scrub.minimumPressDuration = 0.35
        scrub.allowableMovement = 12
        scrub.allowedTouchTypes = direct
        scrub.cancelsTouchesInView = false
        scrub.delegate = self
        addGestureRecognizer(scrub)
        undoScrub = scrub
        // Trackpad pinch / rotate use the same zoom and rotate settings as fingers.
        let indirect = NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        pinch.allowedTouchTypes = direct + [indirect]
        rotate.allowedTouchTypes = direct + [indirect]
    }

    /// Multi-finger gestures are blocked only while the Pencil draws (or just did) – not while it
    /// merely hovers: holding the Pencil above the screen while zooming with the other hand is
    /// normal. Single-finger input stays stricter (see `fingerAllowed`).
    private var pencilBusy: Bool {
        pencilTouch != nil || Date().timeIntervalSince(lastPencilContact) < 0.3
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g is UIHoverGestureRecognizer { return true }
        // Tablet mode: only the Pencil (like a pen tablet; the hand rests on the glass).
        if tabletMode && !(g is UIPanGestureRecognizer && g.allowedTouchTypes.isEmpty) { return false }
        if g === undoScrub { return settings.undoScrub && !pencilBusy }
        // While scrubbing, the fingers only scrub (no scroll, zoom or rotate).
        if scrubbing { return false }
        return !pencilBusy
    }

    @objc private func handleUndoScrub(_ g: UILongPressGestureRecognizer) {
        let x = g.location(in: self).x
        switch g.state {
        case .began:
            scrubbing = true
            scrubOriginX = x
            scrubDone = 0
            onScrub?(0)
        case .changed:
            let target = Int(((x - scrubOriginX) / max(settings.undoScrubStep, 10)).rounded(.towardZero))
            guard target != scrubDone, let session else { return }
            while scrubDone > target { session.send(Shortcut("z", .command)); scrubDone -= 1 }
            while scrubDone < target { session.send(Shortcut("z", [.command, .shift])); scrubDone += 1 }
            onScrub?(scrubDone)
        default:
            if scrubbing { onGesture?(GestureEvent(name: "undoScrub", value: Double(scrubDone))) }
            scrubbing = false
            onScrub?(nil)
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let continuous: (UIGestureRecognizer) -> Bool = { $0 is UIPanGestureRecognizer || $0 is UIPinchGestureRecognizer || $0 is UIRotationGestureRecognizer }
        return (continuous(g) && continuous(other)) || g is UIHoverGestureRecognizer || other is UIHoverGestureRecognizer
    }

    private func anchor(_ g: UIGestureRecognizer) -> CGPoint {
        normalizeInput(g.location(in: self))
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        // Zoomed in locally: two fingers move the picture instead of scrolling the Mac.
        if localZoomActive && (zoomScale > 1.001 || viewAngle != 0) {
            let t = g.translation(in: self)
            if g.state == .began { lastPan = t }
            if g.state == .changed, localPinch == nil {
                setZoom(zoomScale, CGPoint(x: zoomOffset.x + t.x - lastPan.x, y: zoomOffset.y + t.y - lastPan.y))
            }
            lastPan = t
            return
        }
        let t = g.translation(in: self)
        switch g.state {
        case .began:
            if !pinchActive { twoFingerLock.reset() }
            panActive = true
        case .changed: break
        default: panActive = false
        }
        guard settings.panEnabled, let session else { return }
        switch g.state {
        case .began:
            lastPan = t
        case .changed:
            // Only scroll once the touch is a scroll; while undecided the movement adds up.
            let mode = twoFingerLock.pan(translation: Double(hypot(t.x, t.y)))
            guard mode == .scroll || settings.zoomMethod == .off else { if mode == .zoom { lastPan = t }; return }
            let r = videoRect
            guard r.width > 0, r.height > 0 else { return }
            let sign: CGFloat = settings.invertPan ? -1 : 1
            let dx = (t.x - lastPan.x) / r.width * sign
            let dy = (t.y - lastPan.y) / r.height * sign
            lastPan = t
            let a = anchor(g)
            session.send(ScrollEvent(x: Float(a.x), y: Float(a.y), dx: Float(dx), dy: Float(dy)))
        default:
            break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        if localZoomActive {
            let a = g.location(in: self)
            switch g.state {
            case .began:
                localPinch = (zoomScale / max(g.scale, 0.01), contentPoint(a))
            case .changed:
                guard let lp = localPinch else { return }
                // Keep the picture point under the fingers there while scaling.
                let s = min(max(lp.scale * g.scale, viewAngle != 0 ? 0.5 : 1), 8)
                setZoom(s, offsetKeeping(lp.content, at: a, scale: s, angle: viewAngle))
            default:
                localPinch = nil
                if zoomScale < 1.06, viewAngle == 0 { resetLocalZoom() }
            }
            return
        }
        switch g.state {
        case .began:
            if !panActive { twoFingerLock.reset() }
            pinchActive = true
        case .changed: break
        default: pinchActive = false
        }
        guard let session, settings.zoomMethod != .off else { return }
        switch g.state {
        case .began:
            lastPinchScale = g.scale
            pinchReport = 1
            zoomSteps.reset()
        case .changed:
            guard lastPinchScale > 0, g.scale > 0 else { return }
            // Only zoom once the touch is a pinch (fingers drifting while zooming never scroll).
            let mode = twoFingerLock.pinch(scale: Double(g.scale))
            guard mode == .zoom || !settings.panEnabled else { if mode == .scroll { lastPinchScale = g.scale }; return }
            let factor = Double(g.scale / lastPinchScale)
            let delta = log2(factor)
            lastPinchScale = g.scale
            // Same for pinch: report once the accumulated scale changed by at least 0.5 %.
            pinchReport *= factor
            if abs(pinchReport - 1) >= 0.005 {
                onGesture?(GestureEvent(name: "pinch", value: pinchReport))
                pinchReport = 1
            }
            let a = anchor(g)
            switch settings.zoomMethod {
            case .keyboardSteps:
                let steps = zoomSteps.add(delta)
                for _ in 0..<abs(steps) { session.send(Shortcut(steps > 0 ? "+" : "-", .command)) }
            case .off:
                break
            default:
                session.send(ScrollEvent(x: Float(a.x), y: Float(a.y), dx: 0,
                                         dy: Float(delta * settings.zoomSensitivity), modifiers: settings.zoomMethod.modifiers))
            }
        default:
            break
        }
    }

    private var rotateReport = 0.0
    private var pinchReport = 1.0

    @objc private func handleRotate(_ g: UIRotationGestureRecognizer) {
        // Local zoom mode: two fingers turn the picture on the iPad like a sheet of paper.
        if localZoomActive {
            let a = g.location(in: self)
            switch g.state {
            case .began:
                localTurn = (viewAngle - g.rotation, contentPoint(a))
            case .changed:
                guard let lt = localTurn else { return }
                var angle = Self.snapAngle(lt.angle + g.rotation)
                if abs(angle) < 0.0001 { angle = 0 }
                viewAngle = angle
                setZoom(zoomScale, offsetKeeping(lt.content, at: a, scale: zoomScale, angle: angle))
                onLocalAngle?(angle)
            default:
                localTurn = nil
            }
            return
        }
        switch g.state {
        case .began:
            lastRotation = g.rotation
            rotateReport = 0
            rotateSteps = StepAccumulator(stepSize: max(settings.rotateStepDegrees, 5))
        case .changed:
            let deg = Double(g.rotation - lastRotation) * 180 / .pi
            lastRotation = g.rotation
            // Two resting fingers still fire .changed with ~0 / 1e-16 rotation: only report real
            // turns, accumulated until they reach 0.1°, so API clients don't get floods of zeros.
            rotateReport += deg
            if abs(rotateReport) >= 0.1 {
                onGesture?(GestureEvent(name: "rotate", value: rotateReport))
                rotateReport = 0
            }
            let steps = rotateSteps.add(deg)
            for _ in 0..<abs(steps) { onAction?(steps > 0 ? settings.rotateRight : settings.rotateLeft) }
        default:
            break
        }
    }

    @objc private func handleTwoFingerTap() { onGesture?(GestureEvent(name: "tap2")); onAction?(settings.twoFingerTap) }
    @objc private func handleThreeFingerTap() { onGesture?(GestureEvent(name: "tap3")); onAction?(settings.threeFingerTap) }
    @objc private func handleFourFingerTap() { onGesture?(GestureEvent(name: "tap4")); onAction?(settings.fourFingerTap) }

    @objc private func handleThreeFingerSwipe(_ g: UISwipeGestureRecognizer) {
        let dir = g.direction == .left ? "left" : g.direction == .right ? "right" : g.direction == .up ? "up" : "down"
        onGesture?(GestureEvent(name: "swipe3.\(dir)"))
        switch g.direction {
        case .left: onAction?(settings.threeFingerSwipeLeft)
        case .right: onAction?(settings.threeFingerSwipeRight)
        case .up: onAction?(settings.threeFingerSwipeUp)
        case .down: onAction?(settings.threeFingerSwipeDown)
        default: break
        }
    }
}

struct CanvasRepresentable: UIViewRepresentable {
    @ObservedObject var model: ClientModel

    final class Coordinator { var zoomResets = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> CanvasView {
        let v = CanvasView(renderer: model.renderer)
        let model = self.model
        v.onAction = { [weak model] a in model?.trigger(a) }
        v.onHoldKey = { [weak model] k, down in model?.hold(k, down: down) }
        v.onChromeDismiss = { [weak model] in withAnimation(Ultra.smooth) { model?.commandOpen = false } }
        v.onGesture = { [weak model] g in model?.report(g) }
        v.onPixelSize = { [weak model] w, h in model?.updateViewPixelSize(width: w, height: h) }
        v.onRadialOpen = { [weak model] p in model?.openRadial(at: p) }
        v.onRadialPick = { [weak model] in model?.pickRadial(model?.radialHighlight) }
        v.onScrub = { [weak model] n in model?.scrubSteps = n }
        v.onInput = { [weak model] in model?.noteInput() }
        v.onLocalZoom = { [weak model] s in DispatchQueue.main.async { model?.localZoom = s } }
        v.onLocalAngle = { [weak model] a in
            let deg = Int((a * 180 / .pi).rounded())
            DispatchQueue.main.async { if model?.localAngle != deg { model?.localAngle = deg } }
        }
        return v
    }

    func updateUIView(_ v: CanvasView, context: Context) {
        v.setViewOnly(model.settings.viewOnly, session: model.session)
        v.settings = model.effectiveSettings
        v.tabletMode = model.tabletModeActive
        v.keys.config = model.settings.tabletKeys
        v.keys.accent = UIColor(Brand.mint)
        v.keys.isHidden = !model.tabletModeActive || !model.settings.tabletKeys.enabled || model.settings.viewOnly
        v.ink.color = model.settings.inkColor.isEmpty ? UIColor(Brand.mint) : UIColor(Theme.color(model.settings.inkColor))
        v.ink.hoverSize = CGFloat(model.settings.hoverDotSize)
        if !model.settings.pressureMeter { v.hidePressureMeter() }
        // Visible for about as long as the Mac's own stroke takes to appear in the picture:
        // pen event to the Mac (½ RTT) + drawing + capture/encode/network (frame age) + decode/display.
        if let t = model.timing {
            v.ink.lifetime = min(max((t.rttMs / 2 + (t.frameAgeMs ?? 40) + 45) / 1000, 0.06), 0.4)
        }
        v.radialOpen = model.radialCenter != nil
        v.chromeOpen = model.commandOpen
        let guidesAllowed = !model.tabletModeActive && !model.settings.viewOnly
        v.rulerVisible = model.rulerVisible && guidesAllowed
        v.rulerView.accent = UIColor(Brand.mint)
        v.guideView.accent = UIColor(Brand.mint)
        v.guideKind = guidesAllowed ? model.guide : .none
        v.mirrored = model.mirrored && !model.tabletModeActive
        v.grid = model.tabletModeActive ? .off : model.grid
        v.gridCells = model.gridCells
        v.gridSnap = model.gridSnap
        v.guidesLocked = model.guidesLocked
        v.gridOpacity = CGFloat(model.gridOpacity)
        if model.settings.zoomMethod != .localView || model.localZoomResets != context.coordinator.zoomResets {
            context.coordinator.zoomResets = model.localZoomResets
            v.resetLocalZoom()
        }
        v.videoSize = model.videoSize
        v.keyboardProxy.onDismiss = { [weak model] in model?.showKeyboard = false }
        v.setOnScreenKeyboard(model.showKeyboard)
    }
}

/// Invisible text input that brings up the on-screen keyboard. Typed text goes to the Mac as
/// text (layout-independent); Return and Backspace go as keys. Autocorrection is off so the
/// Mac receives exactly what was typed.
final class KeyboardProxy: UIView, UIKeyInput {
    var onText: ((String) -> Void)?
    var onKey: ((UInt16) -> Void)?
    var onDismiss: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }

    override func resignFirstResponder() -> Bool {
        let r = super.resignFirstResponder()
        if r { DispatchQueue.main.async { self.onDismiss?() } }
        return r
    }

    var hasText: Bool { true }

    func insertText(_ text: String) {
        // With a hardware keyboard the canvas already sent the key itself.
        guard GCKeyboard.coalesced == nil else { return }
        if text == "\n" { onKey?(HIDKeyMap.returnKey) } else { onText?(text) }
    }

    func deleteBackward() {
        guard GCKeyboard.coalesced == nil else { return }
        onKey?(HIDKeyMap.backspace)
    }

    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var inlinePredictionType: UITextInlinePredictionType = .no
    var keyboardType: UIKeyboardType = .default
}
