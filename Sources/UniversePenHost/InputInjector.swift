import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox
import TafelKit

/// Posts Pencil samples as macOS tablet events using only public CoreGraphics API
/// (`CGEventTypes.h`: tablet proximity events + mouse events with the tablet-point subtype and
/// pressure / tilt / rotation fields). Requires the Accessibility permission.
///
/// Whether a given app reads these fields is app-specific; Cocoa apps receive them as
/// `NSEvent.pressure`, `.tilt`, `.rotation`, `.subtype == .tabletPoint`.
final class InputInjector {
    private let lock = NSLock()
    private var _region = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var _penDown = false
    private var penDown: Bool {
        get { lock.withLock { _penDown } }
        set { lock.withLock { _penDown = newValue } }
    }
    /// Pen tip is down (readable from any thread).
    var isPenDown: Bool { penDown }
    /// Last hover sample of the main iPad, to move the pointer when the section moves under a still pen.
    private var hoverSample: PenSample?
    private var inProximity = false
    private var lastPoint = CGPoint.zero
    /// Where the last pointer event we posted put the cursor (for delta fields and jump moves).
    private var lastPosted: CGPoint?
    private var scrollX = DeltaAccumulator()
    private var scrollY = DeltaAccumulator()
    private let source = CGEventSource(stateID: .hidSystemState)

    /// Arbitrary but stable IDs so apps can associate proximity and point events.
    private let deviceID: Int64 = 0x7AFE1
    private let vendorID: Int64 = 0x7AFE   // deliberately not a real tablet vendor ID
    private let capabilities: Int64 = 0x0001 | 0x0002 | 0x0004 | 0x0040 | 0x0080 | 0x0100 | 0x0400 | 0x2000

    /// Global display coordinates (points, top-left origin) of the captured area.
    var region: CGRect {
        get { lock.withLock { _region } }
        set { lock.withLock { _region = newValue } }
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Global Mac screen point (points, top-left origin) for a normalised image coordinate.
    func screenPoint(x: Float, y: Float) -> CGPoint {
        Geometry.denormalized(CGPoint(x: CGFloat(x), y: CGFloat(y)), in: region)
    }

    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: Pen

    /// `area`: global display rect the sample maps onto (extra tablet iPads: a whole display);
    /// nil = the streamed region.
    func handle(_ s: PenSample, area: CGRect? = nil) {
        // "Out of range" carries no meaningful position (the iPad may send 0,0): keep the
        // pointer where the pen was last seen instead of jumping to the corner.
        let p = s.phase == .exit ? lastPoint
            : Geometry.denormalized(CGPoint(x: CGFloat(s.x), y: CGFloat(s.y)), in: area ?? region)
        lastPoint = p
        if area == nil { hoverSample = s.phase == .hover ? s : (s.phase == .up ? hoverSample : nil) }
        switch s.phase {
        case .enter:
            proximity(true, at: p)
        case .exit:
            if penDown { mouse(.leftMouseUp, s, p, buttons: 0) ; penDown = false }
            proximity(false, at: p)
        case .hover:
            if !inProximity { proximity(true, at: p) }
            mouse(.mouseMoved, s, p, buttons: 0)
        case .down:
            if !inProximity { proximity(true, at: p) }
            moveFirst(s, p)
            penDown = true
            mouse(.leftMouseDown, s, p, buttons: 1)
        case .move:
            if !penDown {
                moveFirst(s, p)
                penDown = true
                mouse(.leftMouseDown, s, p, buttons: 1)
            } else {
                mouse(.leftMouseDragged, s, p, buttons: 1)
            }
        case .up, .cancel:
            if penDown { mouse(.leftMouseUp, s, p, buttons: 0) }
            penDown = false
        }
    }

    /// Re-posts the last hover position after the streamed section moved (network queue).
    func rehover() {
        guard !penDown, inProximity, let s = hoverSample else { return }
        handle(s)
    }

    /// Never leave the button stuck down when the iPad disconnects mid-stroke.
    // MARK: Trackpad / mouse (network queue)

    private var mouseButton: MouseEvent.Button?
    private var clickCount: Int64 = 0
    private var lastClick = (time: Date.distantPast, point: CGPoint.zero, button: MouseEvent.Button.left)

    /// `area`: global rect the normalised x/y refer to (the palette window); default the stream.
    func pointer(_ m: MouseEvent, area: CGRect? = nil) {
        let p = Geometry.denormalized(CGPoint(x: CGFloat(m.x), y: CGFloat(m.y)), in: area ?? region)
        let type: CGEventType
        let button: CGMouseButton
        switch m.phase {
        case .move:
            switch mouseButton {
            case .left?: type = .leftMouseDragged; button = .left
            case .right?: type = .rightMouseDragged; button = .right
            case nil: type = .mouseMoved; button = .left
            }
        case .down:
            if let held = mouseButton { postMouse(held == .left ? .leftMouseUp : .rightMouseUp, held == .left ? .left : .right, at: p) }
            mouseButton = m.button
            // Double/triple clicks: same button, close in time and space (system settings).
            let now = Date()
            if lastClick.button == m.button, now.timeIntervalSince(lastClick.time) < NSEvent.doubleClickInterval,
               hypot(p.x - lastClick.point.x, p.y - lastClick.point.y) < 8 {  // fingers are less precise than a mouse
                clickCount += 1
            } else {
                clickCount = 1
            }
            lastClick = (now, p, m.button)
            // Finger tap at a new spot: move there first (games track the cursor via moves).
            if let last = lastPosted, hypot(p.x - last.x, p.y - last.y) >= 0.5 { postMouse(.mouseMoved, .left, at: p) }
            type = m.button == .left ? .leftMouseDown : .rightMouseDown
            button = m.button == .left ? .left : .right
        case .up:
            guard let held = mouseButton else { return }
            mouseButton = nil
            type = held == .left ? .leftMouseUp : .rightMouseUp
            button = held == .left ? .left : .right
        case .exit:
            releaseMouse(at: p)
            return
        }
        postMouse(type, button, at: p)
    }

    private func postMouse(_ type: CGEventType, _ button: CGMouseButton, at p: CGPoint) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        if type != .mouseMoved { e.setIntegerValueField(.mouseEventClickState, value: max(clickCount, 1)) }
        setDelta(e, to: p)
        e.flags = currentKeyFlags
        e.post(tap: .cghidEventTap)
        lastPoint = p
    }

    private func releaseMouse(at p: CGPoint) {
        guard let held = mouseButton else { return }
        mouseButton = nil
        postMouse(held == .left ? .leftMouseUp : .rightMouseUp, held == .left ? .left : .right, at: p)
    }

    // MARK: Keyboard (network queue)

    /// Physical keys currently held (macOS key codes) and the modifier flags they produce.
    private var heldKeys: Set<UInt16> = []
    private var heldModifiers: [UInt16: CGEventFlags] = [:]
    private var capsLock = false

    func key(_ k: KeyEvent) {
        guard let code = HIDKeyMap.macKeyCode(k.hidUsage) else { return }
        if k.down { heldKeys.insert(code) } else { heldKeys.remove(code) }
        if let m = HIDKeyMap.modifier(macKeyCode: code) {
            let flag: CGEventFlags
            switch m {
            case .command: flag = .maskCommand
            case .shift: flag = .maskShift
            case .option: flag = .maskAlternate
            case .control: flag = .maskControl
            case .capsLock: flag = .maskAlphaShift
            }
            if m == .capsLock {
                if k.down { capsLock.toggle() }
            } else if k.down {
                heldModifiers[code] = flag
            } else {
                heldModifiers[code] = nil
            }
        }
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: k.down) else { return }
        var flags = currentKeyFlags
        if HIDKeyMap.needsFunctionFlag(macKeyCode: code) { flags.insert(.maskSecondaryFn) }
        if HIDKeyMap.isArrow(macKeyCode: code) { flags.insert(.maskNumericPad) }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    private var currentKeyFlags: CGEventFlags {
        var f = heldModifiers.values.reduce(into: CGEventFlags()) { $0.formUnion($1) }
        if capsLock { f.insert(.maskAlphaShift) }
        return f
    }

    /// Text from the on-screen keyboard, typed as Unicode independent of the Mac's layout.
    func text(_ text: String) {
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            // CGEvent carries at most 20 UTF-16 units per event.
            let chunk = Array(units[i..<min(i + 20, units.count)])
            i += chunk.count
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                chunk.withUnsafeBufferPointer { e.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress) }
                e.post(tap: .cghidEventTap)
            }
        }
    }

    private func releaseKeys() {
        for code in heldKeys {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: false) else { continue }
            e.flags = []
            e.post(tap: .cghidEventTap)
        }
        heldKeys.removeAll()
        heldModifiers.removeAll()
    }

    func releaseAll() {
        releaseKeys()
        releaseMouse(at: lastPoint)
        if penDown {
            mouse(.leftMouseUp, PenSample(phase: .up, x: 0, y: 0), lastPoint, buttons: 0)
            penDown = false
        }
        if inProximity { proximity(false, at: lastPoint) }
    }

    /// A tap at a new spot without hovering there first: move the pointer there before the click.
    /// Games (osu!, …) often track the cursor only through move events and ignore a click's
    /// own position, so the cursor would stay where it was.
    private func moveFirst(_ s: PenSample, _ p: CGPoint) {
        guard let last = lastPosted, hypot(p.x - last.x, p.y - last.y) >= 0.5 else { return }
        mouse(.mouseMoved, s, p, buttons: 0)
    }

    /// Relative movement since the last event we posted. Apps with "raw"/relative mouse input
    /// read only these fields; without them the cursor would not move at all.
    private func setDelta(_ e: CGEvent, to p: CGPoint) {
        if let last = lastPosted {
            e.setIntegerValueField(.mouseEventDeltaX, value: Int64((p.x - last.x).rounded()))
            e.setIntegerValueField(.mouseEventDeltaY, value: Int64((p.y - last.y).rounded()))
        }
        lastPosted = p
    }

    private func mouse(_ type: CGEventType, _ s: PenSample, _ p: CGPoint, buttons: Int64) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
        setDelta(e, to: p)
        let pressure = type == .leftMouseDown || type == .leftMouseDragged ? Double(s.pressure) : 0
        e.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
        e.setDoubleValueField(.mouseEventPressure, value: pressure)
        e.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        e.setDoubleValueField(.tabletEventTiltX, value: Double(s.tiltX))
        e.setDoubleValueField(.tabletEventTiltY, value: Double(s.tiltY))
        e.setDoubleValueField(.tabletEventRotation, value: Double(s.rotation))
        // Absolute tablet coordinates in an arbitrary 0...65535 space.
        e.setIntegerValueField(.tabletEventPointX, value: Int64(Double(s.x) * 65535))
        e.setIntegerValueField(.tabletEventPointY, value: Int64(Double(s.y) * 65535))
        e.setIntegerValueField(.tabletEventPointButtons, value: buttons)
        e.setIntegerValueField(.tabletEventDeviceID, value: deviceID)
        // Keys held on the iPad (keyboard or hold buttons, e.g. ⇧ for straight lines) apply to the pen.
        e.flags = currentKeyFlags
        if type == .leftMouseDown || type == .leftMouseUp || type == .leftMouseDragged {
            e.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        e.post(tap: .cghidEventTap)
    }

    private func proximity(_ enter: Bool, at p: CGPoint) {
        inProximity = enter
        guard let e = CGEvent(source: source) else { return }
        e.type = .tabletProximity
        e.location = p
        e.setIntegerValueField(.tabletProximityEventVendorID, value: vendorID)
        e.setIntegerValueField(.tabletProximityEventTabletID, value: 1)
        e.setIntegerValueField(.tabletProximityEventPointerID, value: 1)
        e.setIntegerValueField(.tabletProximityEventDeviceID, value: deviceID)
        e.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 1)
        e.setIntegerValueField(.tabletProximityEventVendorPointerType, value: 0)
        e.setIntegerValueField(.tabletProximityEventVendorPointerSerialNumber, value: 1)
        e.setIntegerValueField(.tabletProximityEventVendorUniqueID, value: 1)
        e.setIntegerValueField(.tabletProximityEventCapabilityMask, value: capabilities)
        e.setIntegerValueField(.tabletProximityEventPointerType, value: 1) // NX_TABLET_POINTER_PEN
        e.setIntegerValueField(.tabletProximityEventEnterProximity, value: enter ? 1 : 0)
        e.post(tap: .cghidEventTap)
    }

    // MARK: Gestures

    func scroll(_ s: ScrollEvent) {
        let r = region
        let anchor = Geometry.denormalized(CGPoint(x: CGFloat(s.x), y: CGFloat(s.y)), in: r)
        // Move the pointer to the gesture anchor first, so zoom-by-scroll zooms around the fingers.
        if !penDown, let m = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: anchor, mouseButton: .left) {
            setDelta(m, to: anchor)
            m.post(tap: .cghidEventTap)
            lastPoint = anchor
        }
        let dx = scrollX.take(Double(s.dx) * r.width)
        let dy = scrollY.take(Double(s.dy) * r.height)
        guard dx != 0 || dy != 0 else { return }
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                              wheel1: Int32(clamping: dy), wheel2: Int32(clamping: dx), wheel3: 0) else { return }
        e.flags = Self.flags(s.modifiers).union(currentKeyFlags)
        e.location = anchor
        e.post(tap: .cghidEventTap)
    }

    // MARK: Held keys by character (tablet keys; main thread – layout lookup)

    private var heldCharCodes: [String: CGKeyCode] = [:]

    /// Holds / releases a key given as character (or special key name), resolved with the Mac's
    /// keyboard layout. Main thread.
    func charKey(_ key: String, down: Bool) {
        let code: CGKeyCode
        if down {
            guard heldCharCodes[key] == nil, let r = KeyboardLayout.keyCode(for: key) else { return }
            code = r.code
            heldCharCodes[key] = code
        } else {
            guard let c = heldCharCodes.removeValue(forKey: key) else { return }
            code = c
        }
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = currentKeyFlags
        e.post(tap: .cghidEventTap)
    }

    /// Lets go of all keys held by character (disconnect). Main thread.
    func releaseCharKeys() {
        for key in Array(heldCharCodes.keys) { charKey(key, down: false) }
    }

    /// Scroll by pixels at the current pointer position (plugins).
    func scrollPixels(dx: Double, dy: Double) {
        let ix = scrollX.take(dx), iy = scrollY.take(dy)
        guard ix != 0 || iy != 0,
              let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                              wheel1: Int32(clamping: iy), wheel2: Int32(clamping: ix), wheel3: 0) else { return }
        e.flags = currentKeyFlags
        e.post(tap: .cghidEventTap)
    }

    /// Must be called on the main thread (Text Input Sources API).
    func shortcut(_ s: Shortcut) {
        guard let resolved = KeyboardLayout.keyCode(for: s.key) else {
            NSLog("Tafel: no key code for shortcut key %@ in current layout", s.key)
            return
        }
        var flags = Self.flags(s.modifiers)
        if resolved.needsShift { flags.insert(.maskShift) }
        // A real keyboard sends arrow keys with the fn + numeric-pad flags; the Mission Control
        // shortcuts (⌃ + arrow) only trigger with them.
        if HIDKeyMap.isArrow(macKeyCode: UInt16(resolved.code)) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: resolved.code, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    static func flags(_ m: ModifierSet) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.shift) { f.insert(.maskShift) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        return f
    }
}

/// Resolves a character to the virtual key code of the *current* keyboard layout, so "z" means
/// the key labelled Z on a German QWERTZ keyboard too (key codes are positional).
enum KeyboardLayout {
    static func keyCode(for key: String) -> (code: CGKeyCode, needsShift: Bool)? {
        if let special = Shortcut.specialKeys[key] { return (CGKeyCode(special), false) }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let target = key.lowercased()
        for shift in [false, true] {
            let modState: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
            for code in 0..<128 {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), modState,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &dead, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                if String(utf16CodeUnits: chars, count: length).lowercased() == target {
                    return (CGKeyCode(code), shift)
                }
            }
        }
        return nil
    }
}
