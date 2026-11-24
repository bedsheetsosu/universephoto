import AppKit
import TafelKit

/// Laser pointer: glowing marks drawn by the Pencil over the Mac screen that fade after a moment.
/// A borderless, click-through window per display; nothing reaches the apps underneath. The marks
/// are part of the screen, so they also show in the stream and in screen sharing.
@MainActor
final class LaserOverlay {
    enum Colour: String, CaseIterable, Identifiable {
        case red, green, yellow, blue, magenta
        var id: String { rawValue }
        var color: NSColor {
            switch self {
            case .red: return NSColor(calibratedRed: 1, green: 0.18, blue: 0.25, alpha: 1)
            case .green: return NSColor(calibratedRed: 0.2, green: 1, blue: 0.45, alpha: 1)
            case .yellow: return NSColor(calibratedRed: 1, green: 0.85, blue: 0.1, alpha: 1)
            case .blue: return NSColor(calibratedRed: 0.25, green: 0.6, blue: 1, alpha: 1)
            case .magenta: return NSColor(calibratedRed: 1, green: 0.25, blue: 0.9, alpha: 1)
            }
        }
        var title: String {
            switch self {
            case .red: return L("Rot")
            case .green: return L("Grün")
            case .yellow: return L("Gelb")
            case .blue: return L("Blau")
            case .magenta: return L("Magenta")
            }
        }
    }

    /// Glow colour of the marks.
    var colour: Colour = Colour(rawValue: UserDefaults.standard.string(forKey: "laserColour") ?? "") ?? .red {
        didSet {
            UserDefaults.standard.set(colour.rawValue, forKey: "laserColour")
            for (_, v) in windows.values { v.colour = colour.color }
        }
    }
    private struct Stroke { var points: [CGPoint]; var last: TimeInterval; var active: Bool }
    private var windows: [CGDirectDisplayID: (window: NSWindow, view: LaserView)] = [:]
    private var strokes: [Stroke] = []
    private var dot: (point: CGPoint, time: TimeInterval)?
    private var drawing = false
    private var timer: Timer?
    static let hold: TimeInterval = 1.2
    static let fade: TimeInterval = 0.8

    /// One pen sample at a global screen point (points, top-left origin).
    func handle(_ phase: PenPhase, at p: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        switch phase {
        case .down:
            endStroke(now)
            strokes.append(Stroke(points: [p], last: now, active: true)); drawing = true
        case .move:
            if drawing, !strokes.isEmpty { strokes[strokes.count - 1].points.append(p); strokes[strokes.count - 1].last = now }
            else { strokes.append(Stroke(points: [p], last: now, active: true)); drawing = true }
        case .up, .cancel:
            endStroke(now)
        case .hover, .enter:
            break
        case .exit:
            endStroke(now); dot = nil
        }
        if phase != .exit { dot = (p, now) }
        ensureWindow(for: p)
        startTimer()
        redraw()
    }

    private func endStroke(_ now: TimeInterval) {
        if drawing, !strokes.isEmpty { strokes[strokes.count - 1].active = false; strokes[strokes.count - 1].last = now }
        drawing = false
    }

    /// Laser switched off: clear everything right away.
    func clear() {
        strokes = []; dot = nil; drawing = false
        timer?.invalidate(); timer = nil
        for w in windows.values { w.window.orderOut(nil) }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        strokes.removeAll { !$0.active && now - $0.last > Self.hold + Self.fade }
        if let d = dot, now - d.time > 3 { dot = nil }
        if strokes.isEmpty && dot == nil {
            timer?.invalidate(); timer = nil
            for w in windows.values { w.window.orderOut(nil) }
            return
        }
        redraw()
    }

    private func redraw() {
        let now = ProcessInfo.processInfo.systemUptime
        let items = strokes.map { s -> ([CGPoint], CGFloat) in
            let age = s.active ? 0 : now - s.last
            let a = age < Self.hold ? 1 : max(0, 1 - (age - Self.hold) / Self.fade)
            return (s.points, CGFloat(a))
        }
        for (id, w) in windows {
            let origin = CGDisplayBounds(id).origin
            w.view.strokes = items.map { ($0.0.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }, $0.1) }
            w.view.dot = dot.map { CGPoint(x: $0.point.x - origin.x, y: $0.point.y - origin.y) }
            w.view.needsDisplay = true
            if !w.window.isVisible { w.window.orderFrontRegardless() }
        }
    }

    private func ensureWindow(for p: CGPoint) {
        var count: UInt32 = 0
        var id: CGDirectDisplayID = 0
        guard CGGetDisplaysWithPoint(p, 1, &id, &count) == .success, count > 0, windows[id] == nil,
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id })
        else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        let v = LaserView(frame: CGRect(origin: .zero, size: screen.frame.size))
        v.colour = colour.color
        w.contentView = v
        w.setFrame(screen.frame, display: false)
        windows[id] = (w, v)
    }
}

private final class LaserView: NSView {
    var strokes: [([CGPoint], CGFloat)] = []
    var dot: CGPoint?
    var colour = NSColor(calibratedRed: 1, green: 0.18, blue: 0.25, alpha: 1)
    override var isFlipped: Bool { true }   // top-left origin, like the pen points

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let red = colour
        for (pts, a) in strokes where a > 0 && !pts.isEmpty {
            let path = CGMutablePath()
            path.addLines(between: pts.count == 1 ? [pts[0], CGPoint(x: pts[0].x + 0.1, y: pts[0].y)] : pts)
            // Glow, colour, white core.
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 14, color: red.withAlphaComponent(0.9 * a).cgColor)
            ctx.addPath(path); ctx.setStrokeColor(red.withAlphaComponent(0.85 * a).cgColor); ctx.setLineWidth(7); ctx.strokePath()
            ctx.restoreGState()
            ctx.addPath(path); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9 * a).cgColor); ctx.setLineWidth(2.2); ctx.strokePath()
        }
        if let d = dot {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 12, color: red.cgColor)
            ctx.setFillColor(red.cgColor)
            ctx.fillEllipse(in: CGRect(x: d.x - 6, y: d.y - 6, width: 12, height: 12))
            ctx.restoreGState()
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: d.x - 2.5, y: d.y - 2.5, width: 5, height: 5))
        }
    }
}
