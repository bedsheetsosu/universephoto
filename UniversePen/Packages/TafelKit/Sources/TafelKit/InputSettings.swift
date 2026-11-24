import Foundation
import CoreGraphics

/// What a Pencil gesture (double tap, squeeze) or a finger tap triggers.
/// Things that happen on the iPad itself (no Mac shortcut): drawing aids and tools.
public enum IPadTool: String, Codable, CaseIterable, Sendable {
    case ruler, perspective1, perspective2, perspective3, ellipse, shapeRecognition, laser, screenshot, palette, mirror, grayscale, grid
    case rope, fixedPressure, speedPressure

    public var title: String {
        switch self {
        case .ruler: return L("Lineal")
        case .perspective1: return L("Perspektive: 1 Fluchtpunkt")
        case .perspective2: return L("Perspektive: %d Fluchtpunkte", 2)
        case .perspective3: return L("Perspektive: %d Fluchtpunkte", 3)
        case .ellipse: return L("Ellipsen-Schablone")
        case .shapeRecognition: return L("Formerkennung")
        case .laser: return L("Laserpointer am Mac")
        case .screenshot: return L("Bildschirmfoto")
        case .palette: return L("Palette vom Mac")
        case .mirror: return L("Ansicht spiegeln")
        case .grayscale: return L("Graustufen-Vorschau")
        case .grid: return L("Raster")
        case .rope: return L("Seil-Stabilisator")
        case .fixedPressure: return L("Fester Druck")
        case .speedPressure: return L("Tempo-Druck")
        }
    }

    /// Short label for radial menu buttons.
    public var shortTitle: String {
        switch self {
        case .ruler: return L("Lineal")
        case .perspective1: return "1P"
        case .perspective2: return "2P"
        case .perspective3: return "3P"
        case .ellipse: return L("Ellipse")
        case .shapeRecognition: return L("Formen")
        case .laser: return L("Laser")
        case .screenshot: return L("Foto")
        case .palette: return L("Palette")
        case .mirror: return L("Spiegeln")
        case .grayscale: return L("Grau")
        case .grid: return L("Raster")
        case .rope: return L("Seil")
        case .fixedPressure: return L("Druck fest")
        case .speedPressure: return L("Tempo")
        }
    }
}

public enum PencilAction: Codable, Hashable, Sendable {
    case none
    /// An iPad tool (ruler, perspective, laser …), toggled on the iPad.
    case tool(IPadTool)
    case shortcut(Shortcut)
    /// Opens the radial menu at the Pencil tip (Pencil Pro squeeze / double tap).
    case radialMenu
    /// Runs an action of a Mac plugin ("pluginID/actionID").
    case plugin(String)

    public static let undo = PencilAction.shortcut(Shortcut("z", .command))
    public static let redo = PencilAction.shortcut(Shortcut("z", [.command, .shift]))
    /// Affinity default tool keys.
    public static let eraser = PencilAction.shortcut(Shortcut("e"))
    public static let brush = PencilAction.shortcut(Shortcut("b"))
    public static let hand = PencilAction.shortcut(Shortcut("h"))
    /// macOS system shortcuts (System Settings → Keyboard → Shortcuts → Mission Control, on by default).
    public static let desktopLeft = PencilAction.shortcut(Shortcut("left", .control))
    public static let desktopRight = PencilAction.shortcut(Shortcut("right", .control))
    public static let missionControl = PencilAction.shortcut(Shortcut("up", .control))
    public static let appWindows = PencilAction.shortcut(Shortcut("down", .control))

    public var shortcut: Shortcut? {
        if case .shortcut(let s) = self { return s }
        return nil
    }

    public var display: String {
        switch self {
        case .none: return L("Keine")
        case .shortcut(let s): return s.display
        case .radialMenu: return L("Radialmenü")
        case .plugin(let id): return "⚙︎ " + (id.split(separator: "/").last.map(String.init) ?? id)
        case .tool(let t): return t.title
        }
    }
}

public enum ZoomMethod: String, Codable, CaseIterable, Sendable {
    /// Scroll events with a held modifier. Many Mac drawing apps zoom with ⌘ or ⌥ + scroll;
    /// which one Affinity uses depends on its preferences, so it is selectable.
    case commandScroll, optionScroll, controlScroll
    /// Discrete ⌘+ / ⌘- shortcuts, one per zoom step.
    case keyboardSteps
    /// Zooms only the picture on the iPad (the Mac app is untouched); two fingers then pan it.
    case localView
    case off

    public var modifiers: ModifierSet {
        switch self {
        case .commandScroll: return .command
        case .optionScroll: return .option
        case .controlScroll: return .control
        default: return []
        }
    }

    public var title: String {
        switch self {
        case .commandScroll: return L("⌘ + Scrollen")
        case .optionScroll: return L("⌥ + Scrollen")
        case .controlScroll: return L("⌃ + Scrollen")
        case .keyboardSteps: return L("⌘+ / ⌘− Tasten")
        case .localView: return L("Nur auf dem iPad (Bild vergrößern)")
        case .off: return L("Aus")
        }
    }
}

/// What a single finger does on the canvas (like the touch ring of a pen display).
public enum FingerMode: String, Codable, CaseIterable, Sendable {
    /// Fingers only do multi-finger gestures (strict palm rejection).
    case off
    /// Tap = click, drag = click-and-drag, hold = right click. Draws without pressure in drawing apps.
    case mouse
    /// Like the Pencil with a fixed pressure (tablet events), hold = right click.
    case pen
    /// Finger only moves the pointer (no click while dragging); tap = click, hold = right click.
    /// For Pencils without hover: aim with the finger, draw with the Pencil.
    case pointer

    public var title: String {
        switch self {
        case .off: return L("Aus")
        case .mouse: return L("Maus")
        case .pen: return L("Stift (fester Druck)")
        case .pointer: return L("Zeiger (Tippen = Klick)")
        }
    }
}

/// Keys a bar button can hold down while the finger rests on it (USB HID usages).
public enum HoldKey: UInt16, CaseIterable, Codable, Sendable {
    case shift = 0xE1, option = 0xE2, command = 0xE3, control = 0xE0, space = 0x2C

    public var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        case .space: return "␣"
        }
    }
}

public struct ShortcutButton: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var shortcut: Shortcut
    /// If set, the button holds this key down while touched (e.g. ⇧ or Space while drawing)
    /// instead of sending `shortcut` once.
    public var hold: HoldKey?
    /// If set, the button runs this Mac plugin action ("pluginID/actionID") instead of the shortcut.
    public var pluginAction: String?
    /// If set, the button toggles this iPad tool instead.
    public var tool: IPadTool?
    public init(id: UUID = UUID(), title: String, shortcut: Shortcut, hold: HoldKey? = nil, pluginAction: String? = nil, tool: IPadTool? = nil) {
        self.id = id; self.title = title; self.shortcut = shortcut; self.hold = hold; self.pluginAction = pluginAction; self.tool = tool
    }

    /// What the button does, for lists.
    public var actionDisplay: String {
        if let tool { return tool.title }
        if let hold { return L("Halten: %@", hold.symbol) }
        return shortcut.display
    }
}

/// All iPad-side input settings. Stored in UserDefaults on the iPad (not secret).
public struct InputSettings: Codable, Equatable, Sendable {
    public var pressure = PressureCurve()
    public var tilt = TiltConverter()
    public var sendHover = true
    public var sendRoll = true

    public var doubleTap: PencilAction = .eraser
    public var squeeze: PencilAction = .radialMenu
    public var twoFingerTap: PencilAction = .undo
    public var threeFingerTap: PencilAction = .redo

    public var panEnabled = true
    public var invertPan = false
    public var zoomMethod: ZoomMethod = .commandScroll
    /// Scroll units (fraction of capture height) per doubling of pinch scale.
    public var zoomSensitivity: Double = 0.25
    public var rotateLeft: PencilAction = .none
    public var rotateRight: PencilAction = .none
    public var rotateStepDegrees: Double = 15

    /// Smoothing of the Pencil path and of the pressure (0 = off … 1 = strong, adds lag).
    public var positionSmoothing: Double = 0
    public var pressureSmoothing: Double = 0.15

    public var fingerMode: FingerMode = .mouse
    /// Pressure used in `.pen` finger mode.
    public var fingerPressure: Double = 0.5
    public var longPressRightClick = true
    /// Touches with a larger contact radius (points) count as palm and are ignored.
    public var palmRadius: Double = 32
    /// Like a Mac trackpad: fingers move left → the desktop on the right slides in.
    public var threeFingerSwipeLeft: PencilAction = .desktopRight
    public var threeFingerSwipeRight: PencilAction = .desktopLeft
    public var threeFingerSwipeUp: PencilAction = .missionControl
    public var threeFingerSwipeDown: PencilAction = .appWindows
    public var fourFingerTap: PencilAction = .none

    /// Swap the ISO keys "^" and "<" (some keyboards report them the other way round).
    public var swapISOKeys = false
    /// Trackpad/mouse on the iPad controls the Mac's pointer.
    public var trackpadAsMouse = true
    /// Hide the iPad's own pointer over the picture (the Mac cursor in the video is shown instead).
    public var hideIPadPointer = true

    public var showShortcutBar = true
    /// Shortcut bar on the right edge (for left-handed use, so the drawing hand doesn't cover it).
    public var shortcutBarOnRight = false
    /// Own bars per Mac app (bundle ID); the bar switches automatically with the front app.
    public var appShortcutBars: [String: [ShortcutButton]] = [:]
    /// Display names of apps with an own bar (for the settings list).
    public var appNames: [String: String] = [:]
    public var shortcutBar: [ShortcutButton] = [
        ShortcutButton(title: "Undo", shortcut: Shortcut("z", .command)),
        ShortcutButton(title: "Redo", shortcut: Shortcut("z", [.command, .shift])),
        ShortcutButton(title: L("Pinsel"), shortcut: Shortcut("b")),
        ShortcutButton(title: L("Radierer"), shortcut: Shortcut("e")),
        ShortcutButton(title: L("Hand"), shortcut: Shortcut("h")),
        ShortcutButton(title: "⇧", shortcut: Shortcut("a"), hold: .shift),
        ShortcutButton(title: "⌥", shortcut: Shortcut("a"), hold: .option),
    ]

    /// Items of the Pencil palette (Pencil Pro squeeze), left to right, row by row. 2…12 items.
    public var radialMenu: [ShortcutButton] = InputSettings.defaultRadialMenu
    public static let maxRadialItems = 12
    public static var defaultRadialMenu: [ShortcutButton] {
        [
            ShortcutButton(title: "Undo", shortcut: Shortcut("z", .command)),
            ShortcutButton(title: L("Pinsel"), shortcut: Shortcut("b")),
            ShortcutButton(title: L("Radierer"), shortcut: Shortcut("e")),
            ShortcutButton(title: L("Pipette"), shortcut: Shortcut("i")),
            ShortcutButton(title: L("Hand"), shortcut: Shortcut("h")),
            ShortcutButton(title: "Redo", shortcut: Shortcut("z", [.command, .shift])),
        ]
    }

    /// Own Pencil settings per Mac app (bundle ID); they replace the standard ones while that app
    /// is in front on the Mac.
    public var appPenProfiles: [String: PenProfile] = [:]

    /// Mac apps (bundle ID → name) that get game mode: maximum picture quality and no smoothing
    /// while they are in front (e.g. osu!).
    public var gameApps: [String: String] = [:]
    /// Mac apps (bundle ID → name) that switch the iPad into tablet mode while they are in front.
    public var tabletApps: [String: String] = [:]

    /// Draw the stroke on the iPad right away (fades when the Mac's picture catches up).
    public var instantInk = true
    /// Hold the Pencil still at the end of a stroke → it is redrawn as a clean line, polygon or ellipse.
    public var shapeRecognition = false
    /// Rope stabilizer ("lazy brush"): the stroke follows the Pencil on a string of this length
    /// in points; 0 = off. Steadies lines without the lag of averaging.
    public var ropeLength: Double = 0
    /// Fixed pressure for every stroke (inking with an even line); 0 = off (real pressure).
    public var constantPressure: Double = 0
    /// Faster strokes get lighter, like an ink nib (0 = off, 1 = strong).
    public var speedPressure: Double = 0
    /// Instant-ink colour as hex; empty = the accent colour.
    public var inkColor = ""
    /// Diameter of the hover ring in points.
    public var hoverDotSize: Double = 10
    /// Small live meter of the pressure sent to the Mac (bottom left).
    public var pressureMeter = false
    /// Two round undo/redo buttons at the bottom edge.
    public var undoButtons = false
    /// Squeeze and hold (> 0.35 s): this key is held on the Mac until the squeeze ends (spring-loaded tool).
    public var squeezeHoldKey: HoldKey?
    /// Saved texts typed on the Mac with one tap (… menu).
    public var snippets: [String] = []
    /// Hover dot also shows the Pencil's tilt as a short line.
    public var hoverTilt = false
    /// Small ring under the hovering Pencil tip, drawn on the iPad.
    public var hoverDot = true

    /// Tablet mode: black dotted surface, no picture; the active area maps onto a Mac display.
    public var tabletMode = false
    /// Active area in the iPad's view, normalised (0…1). Default: the whole iPad.
    public var tabletArea = TabletArea.full
    /// Keep the area in the Mac display's aspect ratio (no stretching, like Wacom's "force proportions").
    public var tabletLockAspect = false
    /// Dim the iPad after this many minutes without input (0 = never). Brightness comes back at once.
    public var dimAfterMinutes: Double = 0
    /// Remind to take a break after this many minutes of drawing (0 = never).
    public var breakReminderMinutes: Double = 0
    /// Don't dim while the picture keeps changing (e.g. a video in monitor mode).
    public var dimOnlyWhenStill = true

    /// Monitor only: the iPad just shows the picture, nothing is sent to the Mac.
    public var viewOnly = false

    /// For Pencils without hover: touching only moves the pointer; touch again right away at the
    /// same spot (and hold) to click / draw – like double-tap-and-drag on a trackpad.
    public var doubleTapToClick = false

    /// Click only above this pressure (0 = off); lighter touches stay hover. Like OpenTabletDriver's tip threshold.
    public var tipThreshold: Double = 0
    /// Touch keys next to the active area in tablet mode (like a pen tablet's ExpressKeys).
    public var tabletKeys = TabletKeys()

    /// Saved active areas (e.g. "osu! small", "drawing").
    public var tabletPresets: [TabletPreset] = []

    /// Two fingers rest, then drag left/right = undo/redo step by step.
    public var undoScrub = true
    /// Finger travel (points) per undo/redo step.
    public var undoScrubStep: Double = 40

    public init() {}

    public func isGame(_ bundleID: String?) -> Bool { bundleID.map { gameApps[$0] != nil } ?? false }

    /// Tablet preset bound to this Mac app, if any.
    public func tabletPreset(for bundleID: String?) -> TabletPreset? {
        guard let bundleID else { return nil }
        return tabletPresets.first { $0.appBundleID == bundleID }
    }

    /// The Pencil part of these settings (what a per-app profile can override).
    public var penProfile: PenProfile {
        get { PenProfile(pressure: pressure, positionSmoothing: positionSmoothing, pressureSmoothing: pressureSmoothing,
                         doubleTap: doubleTap, squeeze: squeeze) }
        set {
            pressure = newValue.pressure
            positionSmoothing = newValue.positionSmoothing
            pressureSmoothing = newValue.pressureSmoothing
            doubleTap = newValue.doubleTap
            squeeze = newValue.squeeze
        }
    }

    /// Settings in effect while the app with `bundleID` is in front on the Mac.
    public func effective(for bundleID: String?) -> InputSettings {
        var s = self
        if let bundleID, let p = appPenProfiles[bundleID] { s.penProfile = p }
        if let p = tabletPreset(for: bundleID) {
            s.tabletArea = p.area
            s.tabletLockAspect = p.lockAspect
        }
        if isGame(bundleID) {
            // Smoothing adds lag; a game wants the raw Pencil.
            s.positionSmoothing = 0
            s.pressureSmoothing = 0
        }
        return s
    }

    private enum CodingKeys: String, CodingKey {
        case pressure, tilt, sendHover, sendRoll, doubleTap, squeeze, twoFingerTap, threeFingerTap
        case panEnabled, invertPan, zoomMethod, zoomSensitivity, rotateLeft, rotateRight, rotateStepDegrees
        case positionSmoothing, pressureSmoothing
        case fingerMode, fingerPressure, longPressRightClick, palmRadius
        case threeFingerSwipeLeft, threeFingerSwipeRight, threeFingerSwipeUp, threeFingerSwipeDown, fourFingerTap
        case swapISOKeys, trackpadAsMouse, hideIPadPointer, showShortcutBar, shortcutBarOnRight, shortcutBar
        case appShortcutBars, appNames, radialMenu, appPenProfiles, gameApps, tabletApps, undoScrub, undoScrubStep, instantInk, shapeRecognition, ropeLength, constantPressure, speedPressure, inkColor, hoverDotSize, pressureMeter, undoButtons, squeezeHoldKey, snippets, hoverTilt, hoverDot, tabletMode, tabletArea, tabletLockAspect, tabletPresets, tipThreshold, tabletKeys, doubleTapToClick, viewOnly, dimAfterMinutes, dimOnlyWhenStill, breakReminderMinutes
    }

    /// Tolerates settings saved by older versions: missing keys keep their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ into: inout T) throws {
            if let v = try c.decodeIfPresent(T.self, forKey: k) { into = v }
        }
        try get(.pressure, &pressure); try get(.tilt, &tilt)
        try get(.sendHover, &sendHover); try get(.sendRoll, &sendRoll)
        try get(.doubleTap, &doubleTap); try get(.squeeze, &squeeze)
        try get(.twoFingerTap, &twoFingerTap); try get(.threeFingerTap, &threeFingerTap)
        try get(.panEnabled, &panEnabled); try get(.invertPan, &invertPan)
        try get(.zoomMethod, &zoomMethod); try get(.zoomSensitivity, &zoomSensitivity)
        try get(.rotateLeft, &rotateLeft); try get(.rotateRight, &rotateRight)
        try get(.rotateStepDegrees, &rotateStepDegrees)
        try get(.positionSmoothing, &positionSmoothing); try get(.pressureSmoothing, &pressureSmoothing)
        try get(.fingerMode, &fingerMode); try get(.fingerPressure, &fingerPressure)
        try get(.longPressRightClick, &longPressRightClick); try get(.palmRadius, &palmRadius)
        try get(.threeFingerSwipeLeft, &threeFingerSwipeLeft); try get(.threeFingerSwipeRight, &threeFingerSwipeRight)
        try get(.threeFingerSwipeUp, &threeFingerSwipeUp); try get(.threeFingerSwipeDown, &threeFingerSwipeDown)
        try get(.fourFingerTap, &fourFingerTap)
        try get(.swapISOKeys, &swapISOKeys)
        try get(.trackpadAsMouse, &trackpadAsMouse); try get(.hideIPadPointer, &hideIPadPointer)
        try get(.shortcutBarOnRight, &shortcutBarOnRight)
        try get(.showShortcutBar, &showShortcutBar); try get(.shortcutBar, &shortcutBar)
        try get(.appShortcutBars, &appShortcutBars); try get(.appNames, &appNames)
        try get(.radialMenu, &radialMenu); try get(.appPenProfiles, &appPenProfiles)
        try get(.gameApps, &gameApps); try get(.tabletApps, &tabletApps); try get(.undoScrub, &undoScrub); try get(.undoScrubStep, &undoScrubStep)
        try get(.instantInk, &instantInk); try get(.hoverDot, &hoverDot)
        try get(.shapeRecognition, &shapeRecognition)
        try get(.ropeLength, &ropeLength); try get(.constantPressure, &constantPressure)
        try get(.speedPressure, &speedPressure); try get(.inkColor, &inkColor); try get(.hoverDotSize, &hoverDotSize); try get(.pressureMeter, &pressureMeter); try get(.undoButtons, &undoButtons); try get(.squeezeHoldKey, &squeezeHoldKey); try get(.snippets, &snippets); try get(.hoverTilt, &hoverTilt)
        try get(.tabletMode, &tabletMode); try get(.tabletArea, &tabletArea); try get(.tabletLockAspect, &tabletLockAspect)
        try get(.tabletPresets, &tabletPresets)
        try get(.tipThreshold, &tipThreshold); try get(.tabletKeys, &tabletKeys)
        try get(.doubleTapToClick, &doubleTapToClick); try get(.viewOnly, &viewOnly)
        try get(.dimAfterMinutes, &dimAfterMinutes); try get(.dimOnlyWhenStill, &dimOnlyWhenStill)
        try get(.breakReminderMinutes, &breakReminderMinutes)
    }
}

/// Pencil settings that can differ per Mac app.
public struct PenProfile: Codable, Equatable, Sendable {
    public var pressure: PressureCurve
    public var positionSmoothing: Double
    public var pressureSmoothing: Double
    public var doubleTap: PencilAction
    public var squeeze: PencilAction

    public init(pressure: PressureCurve, positionSmoothing: Double, pressureSmoothing: Double,
                doubleTap: PencilAction, squeeze: PencilAction) {
        self.pressure = pressure
        self.positionSmoothing = positionSmoothing
        self.pressureSmoothing = pressureSmoothing
        self.doubleTap = doubleTap
        self.squeeze = squeeze
    }
}

/// Geometry of the radial menu: which item lies under a point.
public enum RadialMenuLayout {
    /// Room for one icon on the band (1.1: icons sit right on a dark band, like the squeeze
    /// palettes of note apps, instead of separate round buttons).
    public static let buttonSize: Double = 46
    /// Thickness of the band.
    public static let bandWidth: Double = 62
    /// Inside this distance from the Pencil tip nothing is selected (lets you back out).
    public static let deadZone: Double = 60
    public static let outerLimit: Double = 220
    /// Items sit on an arc (not a full ring): this far apart, the whole arc never wider than `maxSpan`.
    static let preferredStep = 25.0 * Double.pi / 180
    static let maxSpan = 260.0 * Double.pi / 180
    /// Arc direction pointing up (screen coordinates: y grows downwards).
    public static let up = -Double.pi / 2
    /// Where the arc opens when there is room: up, leaning left, so a right hand doesn't cover it.
    public static let preferred = up - 0.4

    /// Angle between neighbouring items.
    public static func step(count: Int) -> Double {
        count <= 1 ? 0 : min(preferredStep, maxSpan / Double(count - 1))
    }

    /// Arc radius: big enough that neighbouring buttons don't touch.
    public static func radius(count: Int) -> Double {
        let s = step(count: count)
        guard s > 0 else { return 120 }
        return max(120, (buttonSize / 2 + 4) / sin(s / 2))
    }

    /// Angle (radians, 0 = right, clockwise on screen) of item `i`; item 0 is the left end of the arc.
    public static func angle(of i: Int, count: Int, facing: Double = up) -> Double {
        facing + (Double(i) - Double(count - 1) / 2) * step(count: count)
    }

    /// Centre of item `i` of `count`, relative to the Pencil tip.
    public static func offset(of i: Int, count: Int, facing: Double = up) -> (x: Double, y: Double) {
        let a = angle(of: i, count: count, facing: facing)
        let r = radius(count: count)
        return (r * cos(a), r * sin(a))
    }

    /// Item in the direction (dx, dy) from the tip, or nil in the dead zone, far outside or
    /// clearly beyond the ends of the arc.
    public static func item(dx: Double, dy: Double, count: Int, facing: Double = up) -> Int? {
        guard count > 0 else { return nil }
        let d = (dx * dx + dy * dy).squareRoot()
        guard d >= deadZone, d <= outerLimit else { return nil }
        let rel = remainder(atan2(dy, dx) - facing, 2 * Double.pi)   // −π…π from the arc's middle
        if count == 1 { return abs(rel) <= preferredStep ? 0 : nil }
        let pos = rel / step(count: count) + Double(count - 1) / 2
        guard pos >= -0.75, pos <= Double(count - 1) + 0.75 else { return nil }
        return min(max(Int(pos.rounded()), 0), count - 1)
    }

    // MARK: Scrolling arc (1.1)
    /// At most this many items show at once; with more, the arc scrolls (drag along it) and its
    /// ends fade out where more items wait.
    public static let maxVisible = 7
    public static func visible(count: Int) -> Int { min(max(count, 0), maxVisible) }
    public static func maxScroll(count: Int) -> Double { Double(max(0, count - maxVisible)) }

    /// Angle of item `i` when the arc is scrolled by `scroll` items (0 = first item at the left end).
    public static func angle(of i: Int, count: Int, facing: Double, scroll: Double) -> Double {
        let v = visible(count: count)
        return facing + (Double(i) - scroll - Double(v - 1) / 2) * step(count: v)
    }

    /// How visible item `i` is (1 inside the window, fading to 0 just beyond its ends).
    public static func opacity(of i: Int, count: Int, scroll: Double) -> Double {
        let p = Double(i) - scroll, v = Double(visible(count: count))
        let out = p < 0 ? -p : p > v - 1 ? p - (v - 1) : 0
        return max(0, 1 - out / 0.7)
    }

    /// Item in direction (dx, dy) on the scrolled arc, or nil (dead zone, outside, beyond the ends).
    public static func item(dx: Double, dy: Double, count: Int, facing: Double, scroll: Double) -> Int? {
        guard count > 0 else { return nil }
        let d = (dx * dx + dy * dy).squareRoot()
        guard d >= deadZone, d <= outerLimit else { return nil }
        let v = visible(count: count)
        let rel = remainder(atan2(dy, dx) - facing, 2 * Double.pi)
        let st = step(count: v)
        let pos = v == 1 ? 0 : rel / st + Double(v - 1) / 2
        guard pos >= -0.5, pos <= Double(v - 1) + 0.5 else { return nil }
        let i = Int((pos + scroll).rounded())
        return (0..<count).contains(i) ? i : nil
    }

    /// Scroll change (in items) for the finger moving from angle `a` to angle `b` along the arc.
    public static func scrollDelta(from a: Double, to b: Double, count: Int) -> Double {
        let st = step(count: visible(count: count))
        guard st > 0 else { return 0 }
        return -remainder(b - a, 2 * Double.pi) / st
    }

    /// Direction that keeps the arc on screen: up, down near the top edge, sideways near the
    /// left/right edges (diagonal in the corners).
    public static func facing(x: Double, y: Double, width: Double, height: Double, count: Int) -> Double {
        let reach = radius(count: visible(count: count)) + bandWidth / 2 + 12
        var fx = 0.0, fy = -1.0
        if y < reach { fy = 1 }
        if x < reach { fx = 1 } else if x > width - reach { fx = -1 }
        if fx == 0 && fy < 0 { return preferred }
        if fx != 0 && y >= reach && y <= height - reach { fy = 0 }
        return atan2(fy, fx)
    }
}

/// Active area of tablet mode, normalised to the iPad's view (0…1, origin top-left).
public struct TabletArea: Codable, Equatable, Sendable {
    public var x: Double = 0.2
    public var y: Double = 0.2
    public var width: Double = 0.6
    public var height: Double = 0.6
    /// Rotation of the area around its centre, degrees clockwise (like OpenTabletDriver's rotation).
    public var rotation: Double = 0
    public init() {}

    private enum CodingKeys: String, CodingKey { case x, y, width, height, rotation }
    /// Areas saved before rotation existed have no "rotation" key.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
    }

    /// Normalised position (0…1, clamped) of view point `p` inside this area, rotation undone.
    public func normalized(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let r = rect(in: size)
        guard rotation != 0 else { return Geometry.normalized(p, in: r) }
        let a = -rotation * .pi / 180
        let dx = Double(p.x - r.midX), dy = Double(p.y - r.midY)
        let q = CGPoint(x: Double(r.midX) + dx * cos(a) - dy * sin(a), y: Double(r.midY) + dx * sin(a) + dy * cos(a))
        return Geometry.normalized(q, in: r)
    }

    /// The four corners in view points, rotation applied (top-left, top-right, bottom-right, bottom-left).
    public func corners(in size: CGSize) -> [CGPoint] {
        let r = rect(in: size)
        let a = rotation * .pi / 180
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)].map { p in
            let dx = Double(p.x - r.midX), dy = Double(p.y - r.midY)
            return CGPoint(x: Double(r.midX) + dx * cos(a) - dy * sin(a), y: Double(r.midY) + dx * sin(a) + dy * cos(a))
        }
    }
    /// The whole iPad.
    public static let full = TabletArea(x: 0, y: 0, width: 1, height: 1)
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }

    /// Same area with the given aspect (w/h, in points of a view of `size`), keeping its centre
    /// and width where possible, and fully inside the view.
    public func locked(to aspect: Double, in size: CGSize) -> TabletArea {
        guard aspect > 0, size.width > 0, size.height > 0 else { return self }
        var w = width * size.width
        var h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        if w > size.width { w = size.width; h = w / aspect }
        let cx = (x + width / 2) * size.width, cy = (y + height / 2) * size.height
        var out = TabletArea(x: 0, y: 0, width: w / size.width, height: h / size.height)
        out.rotation = rotation
        return out.moved(toCenter: CGPoint(x: cx, y: cy), in: size)
    }

    /// Moved so its centre is at `c` (points), clamped inside the view.
    public func moved(toCenter c: CGPoint, in size: CGSize) -> TabletArea {
        var a = self
        a.x = min(max(Double(c.x / size.width) - width / 2, 0), max(1 - width, 0))
        a.y = min(max(Double(c.y / size.height) - height / 2, 0), max(1 - height, 0))
        return a
    }
}

/// A saved tablet-mode active area.
public struct TabletPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var area: TabletArea
    public var lockAspect: Bool
    /// If set, this area is used automatically while that Mac app is in front (e.g. osu!).
    public var appBundleID: String?
    public var appName: String?
    public init(id: UUID = UUID(), name: String, area: TabletArea, lockAspect: Bool, appBundleID: String? = nil, appName: String? = nil) {
        self.id = id; self.name = name; self.area = area; self.lockAspect = lockAspect
        self.appBundleID = appBundleID; self.appName = appName
    }

    /// Built-in "Full area" preset (whole iPad, not stretched to the display's shape). Always listed
    /// first, cannot be deleted or bound to an app.
    public static let fullArea = TabletPreset(id: UUID(uuidString: "00000000-0000-0000-0000-00000000F011")!,
                                              name: "Full area", area: .full, lockAspect: false)
    public var isBuiltIn: Bool { id == Self.fullArea.id }
    /// Name to show (the built-in preset in the app language).
    public var title: String { isBuiltIn ? L("Ganze Fläche") : name }

    /// Whether `a` is (practically) this preset's area.
    public func matches(_ a: TabletArea) -> Bool {
        abs(a.x - area.x) < 0.001 && abs(a.y - area.y) < 0.001 && abs(a.width - area.width) < 0.001 && abs(a.height - area.height) < 0.001
    }
}

/// Touch keys in tablet mode ("ExpressKeys"): held as long as a finger rests on them.
public struct TabletKeys: Codable, Equatable, Sendable {
    public enum Side: String, Codable, CaseIterable, Sendable {
        case left, right, top, bottom
        /// Keys side by side (top / bottom edge) instead of in a column.
        public var horizontal: Bool { self == .top || self == .bottom }
    }
    public var enabled = false
    public var side: Side = .left
    /// Edge length of a key in points.
    public var size: Double = 120
    /// Where the keys sit along their edge: 0 = top/left, 0.5 = centred, 1 = bottom/right.
    public var vertical: Double = 0.5
    public var keys: [TabletKey] = [TabletKey(title: "Z", key: "z"), TabletKey(title: "X", key: "x")]
    public init() {}

    private enum CodingKeys: String, CodingKey { case enabled, side, size, vertical, keys }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TabletKeys()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        side = try c.decodeIfPresent(Side.self, forKey: .side) ?? d.side
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        vertical = try c.decodeIfPresent(Double.self, forKey: .vertical) ?? d.vertical
        keys = try c.decodeIfPresent([TabletKey].self, forKey: .keys) ?? d.keys
    }

    /// Key frames in a view of `size`: keys moved in the area editor sit where they were put,
    /// the others in a column (left/right edge) or row (top/bottom edge).
    public func frames(in view: CGSize) -> [CGRect] {
        let auto = autoFrames(in: view)
        let s = CGFloat(size)
        return keys.enumerated().map { i, k in
            guard let x = k.x, let y = k.y else { return auto[i] }
            let cx = min(max(CGFloat(x) * view.width, s / 2), max(view.width - s / 2, s / 2))
            let cy = min(max(CGFloat(y) * view.height, s / 2), max(view.height - s / 2, s / 2))
            return CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)
        }
    }

    public var anyMoved: Bool { keys.contains { $0.x != nil } }

    private func autoFrames(in view: CGSize) -> [CGRect] {
        let s = CGFloat(size), gap: CGFloat = 16, margin: CGFloat = 22
        let total = CGFloat(keys.count) * s + CGFloat(max(keys.count - 1, 0)) * gap
        let pos = CGFloat(min(max(vertical, 0), 1))
        if side.horizontal {
            let y = side == .top ? margin : view.height - margin - s
            var x = margin + max(view.width - total - 2 * margin, 0) * pos
            return keys.map { _ in defer { x += s + gap }; return CGRect(x: x, y: y, width: s, height: s) }
        }
        let x = side == .left ? margin : view.width - margin - s
        var y = margin + max(view.height - total - 2 * margin, 0) * pos
        return keys.map { _ in defer { y += s + gap }; return CGRect(x: x, y: y, width: s, height: s) }
    }
}

public struct TabletKey: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// Character (resolved with the Mac's keyboard layout) or a special key name (space, return, …).
    public var key: String
    /// Centre placed freely in the area editor (normalised to the iPad view); nil = automatic.
    public var x: Double?
    public var y: Double?
    public init(id: UUID = UUID(), title: String, key: String, x: Double? = nil, y: Double? = nil) {
        self.id = id; self.title = title; self.key = key; self.x = x; self.y = y
    }
}

/// Hold / release a key by character (resolved on the Mac with its layout).
public struct CharKeyEvent: Codable, Equatable, Sendable {
    public var key: String
    public var down: Bool
    public init(key: String, down: Bool) { self.key = key; self.down = down }
}

/// Tip threshold logic: decides whether a touching sample is sent as a click (down/move/up) or as hover.
public struct TipGate: Sendable {
    public private(set) var tipDown = false
    public init() {}

    /// Returns the phase to send (nil = send nothing). Release happens at 75 % of the threshold.
    public mutating func phase(for phase: PenPhase, pressure: Double, threshold: Double) -> PenPhase? {
        guard threshold > 0 else { return phase }
        switch phase {
        case .down, .move:
            if !tipDown {
                if pressure >= threshold { tipDown = true; return .down }
                return .hover
            }
            if pressure < threshold * 0.75 { tipDown = false; return .up }
            return .move
        case .up, .cancel:
            if tipDown { tipDown = false; return phase }
            return nil
        default:
            return phase
        }
    }
}

/// A named set of all iPad settings (pressure, gestures, bars, tablet mode, …) plus picture quality.
public struct SettingsProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var settings: InputSettings
    public var quality: StreamQuality
    public init(id: UUID = UUID(), name: String, settings: InputSettings, quality: StreamQuality) {
        self.id = id; self.name = name; self.settings = settings; self.quality = quality
    }
}

/// "Double-tap to click" for Pencils without hover: a touch only moves the pointer; a second touch
/// soon after, near where the first one lifted, is a real click / stroke.
public struct DoubleTapClickGate: Sendable {
    public var window: TimeInterval = 0.35
    public var radius: CGFloat = 40
    private var lastLift: (time: TimeInterval, point: CGPoint)?
    public private(set) var armed = false
    public init() {}

    /// Pencil touched down. Returns whether this touch clicks.
    public mutating func begin(at p: CGPoint, time: TimeInterval) -> Bool {
        if let l = lastLift, time - l.time <= window, hypot(p.x - l.point.x, p.y - l.point.y) <= radius {
            armed = true
        } else {
            armed = false
        }
        lastLift = nil
        return armed
    }

    /// Pencil lifted. A pointer-only touch arms the next one; a click touch does not.
    public mutating func end(at p: CGPoint, time: TimeInterval) {
        lastLift = armed ? nil : (time, p)
        armed = false
    }
}
