import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// System-wide shortcuts of the Mac app (Carbon hot keys: public, no Accessibility needed).
/// ⌃⌥⌘T tablet mode on the iPad, ⌃⌥⌘P choose the palette area, ⌃⌥⌘I move the front window
/// onto what the iPad shows.
@MainActor
final class Hotkeys {
    enum Action: UInt32 { case tabletMode = 1, palette = 2, windowToIPad = 3 }

    static let shortcuts: [(Action, UInt32, String)] = [
        (.tabletMode, UInt32(kVK_ANSI_T), "⌃⌥⌘T"),
        (.palette, UInt32(kVK_ANSI_P), "⌃⌥⌘P"),
        (.windowToIPad, UInt32(kVK_ANSI_I), "⌃⌥⌘I"),
    ]

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static var onAction: ((Action) -> Void)?

    func register(_ onAction: @escaping (Action) -> Void) {
        Self.onAction = onAction
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let a = Hotkeys.Action(rawValue: id.id) {
                DispatchQueue.main.async { Hotkeys.onAction?(a) }
            }
            return noErr
        }, 1, &spec, nil, &handler)
        let mods = UInt32(controlKey | optionKey | cmdKey)
        for (action, key, _) in Self.shortcuts {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5550_454E), id: action.rawValue)   // "UPEN"
            if RegisterEventHotKey(key, mods, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            } else {
                NSLog("Tafel: hot key %d is taken by another app", key)
            }
        }
    }

    /// Moves the focused window of the front app (not ours) into `area` (global points, top-left),
    /// centred, and shrinks it to fit if it is larger and resizable. Needs Accessibility.
    static func moveFrontWindow(of pid: pid_t, into area: CGRect) -> Bool {
        guard pid != getpid() else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let win = value, CFGetTypeID(win) == AXUIElementGetTypeID() else { return false }
        let window = win as! AXUIElement
        var size = CGSize(width: 800, height: 600)
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success, let sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }
        let fit = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
        if fit != size, var s = Optional(fit), let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
        }
        var origin = CGPoint(x: area.midX - fit.width / 2, y: area.midY - fit.height / 2)
        guard let p = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p) == .success
    }
}
