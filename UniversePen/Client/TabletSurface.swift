import SwiftUI
import TafelKit

/// Tablet mode background: black like a screenless pen tablet, a fine dot grid and corner marks
/// for the active area (everything outside it is clamped to the area's edge).
///
/// When the area changes (another preset, an app-bound preset, tablet mode coming on) the marks
/// and the lit dots spring to the new shape, the area flashes once and its size in millimetres
/// shows for a moment. While you drag it in the editor nothing animates: it follows the finger.
struct TabletSurfaceView: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject var theme = Theme.shared
    /// 1 right after a change, fading to 0.
    @State private var flash = 0.0
    @State private var labelShown = false
    @State private var labelHide: DispatchWorkItem?

    /// Points → millimetres on an 11" iPad Air (264 ppi, 2 px per point).
    private static let mmPerPoint = 2.0 / 264.0 * 25.4

    var body: some View {
        GeometryReader { g in
            let area = model.tabletArea
            let corners = area.corners(in: g.size)
            ZStack {
                Color.black
                SurfaceDots(quad: Quad(corners))
                AreaOutline(corners: corners)
                    .fill(Brand.mint.opacity(0.13 * flash))
                AreaOutline(corners: corners)
                    .stroke(Brand.mint.opacity(0.9 * flash), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                AreaCorners(corners: corners)
                    .stroke(Brand.mint.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: Brand.mint.opacity(0.7 * flash), radius: 10)
                Text(Self.sizeText(corners))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .ultraPanel(Capsule(), shadow: false)
                    .scaleEffect(labelShown ? 1 : 0.85)
                    .opacity(labelShown ? 1 : 0)
                    .position(Self.center(corners))
                    .accessibilityHidden(!labelShown)
            }
            // Dragging in the editor must not lag behind the finger.
            .animation(model.tabletEditing ? nil : Ultra.bouncy, value: area)
            .animation(Ultra.smooth, value: labelShown)
            .onAppear { lockAspect(g.size); announce() }
            .onChange(of: area) { announce() }
            .onChange(of: model.tabletAspect) { lockAspect(g.size) }
            .onChange(of: g.size) { lockAspect(g.size) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Flash the area and show its size for a moment.
    private func announce() {
        guard !model.tabletEditing else { return }
        flash = 1
        labelShown = true
        // Next run loop, so the jump to 1 is committed before it fades.
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.9)) { flash = 0 } }
        labelHide?.cancel()
        let hide = DispatchWorkItem { labelShown = false }
        labelHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: hide)
    }

    private static func center(_ c: [CGPoint]) -> CGPoint {
        guard c.count == 4 else { return .zero }
        return CGPoint(x: c.map(\.x).reduce(0, +) / 4, y: c.map(\.y).reduce(0, +) / 4)
    }

    private static func sizeText(_ c: [CGPoint]) -> String {
        guard c.count == 4 else { return "" }
        let w = hypot(c[1].x - c[0].x, c[1].y - c[0].y) * mmPerPoint
        let h = hypot(c[2].x - c[1].x, c[2].y - c[1].y) * mmPerPoint
        return String(format: "%.0f × %.0f mm", w, h)
    }

    /// Keeps the area in the Mac display's shape (when that option is on).
    private func lockAspect(_ size: CGSize) {
        guard model.tabletLock else { return }
        let locked = model.tabletArea.locked(to: model.tabletAspect, in: size)
        let a = model.tabletArea
        if abs(locked.width - a.width) > 0.002 || abs(locked.height - a.height) > 0.002 { model.setTabletArea(locked) }
    }
}

/// Four corner points as one animatable value (top-left, top-right, bottom-right, bottom-left).
struct Quad: VectorArithmetic {
    var v: [Double]

    init(_ points: [CGPoint]) {
        var out = points.prefix(4).flatMap { [Double($0.x), Double($0.y)] }
        while out.count < 8 { out.append(0) }
        v = out
    }

    private init(values: [Double]) { v = values }

    var points: [CGPoint] { (0..<4).map { CGPoint(x: v[$0 * 2], y: v[$0 * 2 + 1]) } }

    static var zero: Quad { Quad(values: Array(repeating: 0, count: 8)) }
    static func + (a: Quad, b: Quad) -> Quad { Quad(values: zip(a.v, b.v).map(+)) }
    static func - (a: Quad, b: Quad) -> Quad { Quad(values: zip(a.v, b.v).map(-)) }
    mutating func scale(by rhs: Double) { v = v.map { $0 * rhs } }
    var magnitudeSquared: Double { v.reduce(0) { $0 + $1 * $1 } }
}

/// The dot grid; dots inside the active area are brighter. Animatable, so the lit dots follow
/// the corners while they spring to a new shape.
private struct SurfaceDots: View, Animatable {
    var quad: Quad
    var animatableData: Quad {
        get { quad }
        set { quad = newValue }
    }

    var body: some View {
        let pts = quad.points
        let poly = Path { p in p.addLines(pts); p.closeSubpath() }
        Canvas { ctx, size in
            let step: CGFloat = 22
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    let inside = poly.contains(CGPoint(x: x, y: y))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)),
                             with: .color(.white.opacity(inside ? 0.22 : 0.09)))
                    x += step
                }
                y += step
            }
        }
    }
}

/// The active area as a closed shape (for the flash).
struct AreaOutline: Shape {
    var corners: [CGPoint]
    var animatableData: Quad {
        get { Quad(corners) }
        set { corners = newValue.points }
    }

    func path(in _: CGRect) -> Path {
        var p = Path()
        guard corners.count == 4 else { return p }
        p.addLines(corners)
        p.closeSubpath()
        return p
    }
}

/// L-shaped corner marks of the active area (like the marks printed on pen tablets); follows rotation.
struct AreaCorners: Shape {
    /// top-left, top-right, bottom-right, bottom-left
    var corners: [CGPoint]
    var animatableData: Quad {
        get { Quad(corners) }
        set { corners = newValue.points }
    }

    func path(in _: CGRect) -> Path {
        var p = Path()
        guard corners.count == 4 else { return p }
        for i in 0..<4 {
            let c = corners[i], next = corners[(i + 1) % 4], prev = corners[(i + 3) % 4]
            func toward(_ o: CGPoint) -> CGPoint {
                let dx = o.x - c.x, dy = o.y - c.y
                let len = max(hypot(dx, dy), 1)
                let l = min(26, len / 4)
                return CGPoint(x: c.x + dx / len * l, y: c.y + dy / len * l)
            }
            p.move(to: toward(prev))
            p.addLine(to: c)
            p.addLine(to: toward(next))
        }
        return p
    }
}

/// Move (drag inside) and resize (drag the corner knob) the active area.
struct TabletAreaEditor: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject var theme = Theme.shared
    @State private var area: TabletArea?
    @State private var dragStart: TabletArea?
    // Millimetre fields: plain text (comma or point both work), one focus per field, refreshed
    // from the area only while you are not typing in them.
    private enum Field: Hashable, CaseIterable { case w, h, x, y, r }
    @FocusState private var focus: Field?
    @State private var text: [Field: String] = [:]
    /// The value a field showed before you tapped it (shown greyed while it is empty).
    @State private var before: [Field: String] = [:]
    @State private var viewSize: CGSize = .zero
    /// Key being dragged and where it is right now (view points).
    @State private var keyDrag: (id: UUID, at: CGPoint)?
    @State private var presetName = ""
    @State private var naming = false
    @FocusState private var nameFocus: Bool

    /// Points → millimetres on an 11" iPad Air (264 ppi, 2 px per point).
    private static let mmPerPoint = 2.0 / 264.0 * 25.4

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let a = area ?? model.tabletArea
            let r = a.rect(in: size)
            ZStack {
                Color.black.opacity(0.45)
                    .mask {
                        Rectangle().overlay(Rectangle().frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                            .blendMode(.destinationOut))
                            .compositingGroup()
                    }
                RoundedRectangle(cornerRadius: 4)
                    .fill(Brand.mint.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brand.mint, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
                    .frame(width: r.width, height: r.height)
                    .rotationEffect(.degrees(a.rotation))
                    .position(x: r.midX, y: r.midY)
                    .gesture(DragGesture()
                        .onChanged { v in
                            let start = dragStart ?? a
                            dragStart = start
                            let sr = start.rect(in: size)
                            area = start.moved(toCenter: CGPoint(x: sr.midX + v.translation.width, y: sr.midY + v.translation.height), in: size)
                        }
                        .onEnded { _ in commit() })
                Circle()
                    .fill(Brand.mint)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.bold()).foregroundStyle(Brand.slateDeep))
                    .contentShape(Circle().inset(by: -14))
                    .position(a.corners(in: size)[2])
                    .gesture(DragGesture()
                        .onChanged { v in
                            let start = dragStart ?? a
                            dragStart = start
                            area = resized(start, to: v.location, in: size)
                        }
                        .onEnded { _ in commit() })
                if model.settings.tabletKeys.enabled { keyHandles(size) }
                Text(String(format: "%.0f × %.0f mm", r.width * Self.mmPerPoint, r.height * Self.mmPerPoint))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .tafelOverlayGlass(Capsule())
                    .position(x: r.midX, y: r.midY)
                    .allowsHitTesting(false)
                VStack(spacing: 10) {
                    toolbar
                    numbers(size)
                    presets(size)
                    Spacer()
                }
                .padding(.top, 14)
                .onAppear { viewSize = size; fill(a, size) }
                .onChange(of: size) { viewSize = size; fill(area ?? model.tabletArea, size) }
                .onChange(of: area) { fill(area ?? model.tabletArea, size) }
                .onChange(of: model.tabletArea) { fill(area ?? model.tabletArea, size) }
                .onChange(of: model.tabletLock) { fill(area ?? model.tabletArea, size) }
                .onChange(of: focus) { old, new in
                    // Tapping a field empties it, so typing replaces the value instead of adding digits to it.
                    if let new { before[new] = text[new]; text[new] = "" }
                    // Left without typing: show the value again.
                    if let old, old != new, (text[old] ?? "").isEmpty { text[old] = before[old] }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L("Aktiver Bereich")).font(.headline)
                if let p = model.activeAppPreset {
                    Text(L("Gilt jetzt für %@ (Preset „%@“)", p.appName ?? "", p.name)).font(.caption).foregroundStyle(Brand.mint)
                } else {
                    Text(L("Normaler Bereich (alle anderen Apps)")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(L("Seitenverhältnis wie Mac-Bildschirm"), isOn: Binding(get: { model.tabletLock }, set: { model.setTabletLock($0) }))
                .toggleStyle(.switch).tint(Brand.mint).fixedSize()
            if model.settings.tabletKeys.enabled && model.settings.tabletKeys.anyMoved {
                Button(L("Tasten zurücksetzen")) {
                    withAnimation(Brand.spring) {
                        for i in model.settings.tabletKeys.keys.indices {
                            model.settings.tabletKeys.keys[i].x = nil
                            model.settings.tabletKeys.keys[i].y = nil
                        }
                    }
                }
                .buttonStyle(UltraQuiet(compact: true))
            }
            Button(L("Zurücksetzen")) {
                area = nil
                model.setTabletArea(TabletArea())
            }
            .buttonStyle(UltraQuiet(compact: true))
            Button(L("Fertig")) {
                withAnimation(Brand.spring) { model.tabletEditing = false }
            }
            .buttonStyle(UltraProminent(compact: true))
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .tafelOverlayGlass(Capsule())
    }

    /// The tablet keys, each draggable to any place (W left, E right, …).
    private func keyHandles(_ size: CGSize) -> some View {
        let cfg = model.settings.tabletKeys
        let frames = cfg.frames(in: size)
        return ForEach(Array(cfg.keys.enumerated()), id: \.element.id) { i, k in
            let f = frames[i]
            let center = keyDrag?.id == k.id ? keyDrag!.at : CGPoint(x: f.midX, y: f.midY)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Brand.mint.opacity(keyDrag?.id == k.id ? 0.35 : 0.15))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Brand.mint, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                .overlay(VStack(spacing: 2) {
                    Text(k.title).font(.system(size: 26, weight: .bold))
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.caption2).opacity(0.7)
                })
                .frame(width: f.width, height: f.height)
                .position(center)
                .gesture(DragGesture()
                    .onChanged { v in
                        let half = f.width / 2
                        let p = CGPoint(x: min(max(f.midX + v.translation.width, half), size.width - half),
                                        y: min(max(f.midY + v.translation.height, half), size.height - half))
                        keyDrag = (k.id, p)
                    }
                    .onEnded { _ in
                        if let d = keyDrag, let j = model.settings.tabletKeys.keys.firstIndex(where: { $0.id == d.id }) {
                            model.settings.tabletKeys.keys[j].x = Double(d.at.x / size.width)
                            model.settings.tabletKeys.keys[j].y = Double(d.at.y / size.height)
                        }
                        keyDrag = nil
                    })
        }
    }

    /// Width, height and offset (from the top-left of the iPad) typed in millimetres.
    private func numbers(_ size: CGSize) -> some View {
        HStack(spacing: 12) {
            field(L("Breite"), .w)
            Text("×").foregroundStyle(.secondary)
            field(L("Höhe"), .h)
                .disabled(model.tabletLock)
                .opacity(model.tabletLock ? 0.5 : 1)
            Divider().frame(height: 22)
            field("X", .x)
            field("Y", .y)
            Divider().frame(height: 22)
            field(L("Drehung"), .r, unit: "°")
            Button(L("Zentrieren")) { apply(size, center: true) }
                .buttonStyle(UltraQuiet(compact: true))
            Button(L("Übernehmen")) { apply(size, center: false) }
                .buttonStyle(UltraProminent(compact: true))
        }
        .font(.callout)
        .padding(.horizontal, 18).padding(.vertical, 8)
        .tafelOverlayGlass(Capsule())
    }

    private func field(_ label: String, _ f: Field, unit: String = "mm") -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            TextField(before[f] ?? label, text: Binding(get: { text[f] ?? "" }, set: { new in
                text[f] = new
                // Aspect locked: the height follows the typed width right away.
                if f == .w, model.tabletLock, let w = Self.number(new) {
                    text[.h] = Self.format(w / model.tabletAspect)
                }
            }))
            .keyboardType(.decimalPad)
            .focused($focus, equals: f)
            .submitLabel(.done)
            .onSubmit { apply(viewSize, center: false) }
            .multilineTextAlignment(.trailing)
            .frame(width: 58)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(.white.opacity(focus == f ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(unit).foregroundStyle(.secondary)
        }
    }

    /// Saved areas: tap to use, ✕ to delete; save the current area under a name.
    private func presets(_ size: CGSize) -> some View {
        let current = area ?? model.tabletArea
        return HStack(spacing: 8) {
            Text(L("Presets")).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.allTabletPresets) { p in
                        let on = p.matches(current)
                        let r = p.area.rect(in: size)
                        HStack(spacing: 6) {
                            Button {
                                withAnimation(Brand.spring) { area = nil; model.applyTabletPreset(p) }
                            } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(p.title).font(.callout.weight(.semibold)).lineLimit(1)
                                    Text(String(format: "%.0f × %.0f mm", r.width * Self.mmPerPoint, r.height * Self.mmPerPoint)
                                         + (p.appName.map { " · " + $0 } ?? ""))
                                        .font(.caption2.monospacedDigit()).opacity(0.75)
                                }
                            }
                            .buttonStyle(.plain)
                            // Bind to the app in front on the Mac (used automatically while it is in front).
                            if !p.isBuiltIn, p.appBundleID != nil || model.frontApp != nil {
                                Button {
                                    withAnimation(Brand.spring) { model.bindTabletPreset(p, toFrontApp: p.appBundleID == nil) }
                                } label: {
                                    Image(systemName: p.appBundleID != nil ? "link.circle.fill" : "link").font(.caption.bold())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(p.appBundleID != nil ? L("Von der App lösen") : L("An %@ binden", model.frontApp?.name ?? ""))
                            }
                            if !p.isBuiltIn {
                                Button {
                                    withAnimation(Brand.spring) { model.settings.tabletPresets.removeAll { $0.id == p.id } }
                                } label: {
                                    Image(systemName: "xmark").font(.caption2.bold()).opacity(0.7)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Löschen"))
                            }
                        }
                        .foregroundStyle(on ? Brand.slateDeep : .primary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(on ? AnyShapeStyle(Ultra.accentFill) : AnyShapeStyle(Color.white.opacity(0.1)), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(on ? 0.35 : 0.06), lineWidth: 1))
                        .animation(Ultra.snappy, value: on)
                    }
                }
            }
            .frame(maxWidth: 520)
            if naming {
                TextField(L("Name"), text: $presetName)
                    .focused($nameFocus)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .frame(width: 150)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button(L("Speichern"), action: save)
                    .buttonStyle(UltraProminent(compact: true))
                Button(L("Abbrechen")) { naming = false; presetName = "" }
                    .buttonStyle(UltraQuiet(compact: true))
            } else {
                Button {
                    commit()
                    naming = true
                    nameFocus = true
                } label: {
                    Label(L("Als Preset speichern"), systemImage: "plus")
                }
                .buttonStyle(UltraQuiet(compact: true))
            }
        }
        .font(.callout)
        .padding(.horizontal, 18).padding(.vertical, 8)
        .tafelOverlayGlass(Capsule())
    }

    private func save() {
        commit()
        withAnimation(Brand.spring) { model.saveTabletPreset(named: presetName) }
        presetName = ""
        naming = false
        nameFocus = false
    }

    static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func format(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    /// Shows the area in the fields – except in the field you are typing in.
    private func fill(_ a: TabletArea, _ size: CGSize) {
        guard size.width > 0 else { return }
        let r = a.rect(in: size)
        let values: [Field: CGFloat] = [.w: r.width, .h: r.height, .x: r.minX, .y: r.minY]
        for (f, v) in values where focus != f {
            text[f] = Self.format(Double(v) * Self.mmPerPoint)
        }
        if focus != .r { text[.r] = Self.format(a.rotation) }
    }

    /// Applies the typed millimetres (clamped to the iPad), keeping the aspect lock.
    private func apply(_ size: CGSize, center: Bool) {
        focus = nil
        guard size.width > 0 else { return }
        let cur = (area ?? model.tabletArea).rect(in: size)
        func pt(_ f: Field, _ fallback: CGFloat) -> CGFloat {
            let typed = (text[f] ?? "").isEmpty ? before[f] ?? "" : text[f] ?? ""
            return Self.number(typed).map { CGFloat($0 / Self.mmPerPoint) } ?? fallback
        }
        var w = pt(.w, cur.width)
        var h = model.tabletLock ? w / model.tabletAspect : pt(.h, cur.height)
        w = min(max(w, 40), size.width); h = min(max(h, 30), size.height)
        if model.tabletLock { let asp = model.tabletAspect; if w / h > asp { w = h * asp } else { h = w / asp } }
        var x = center ? (size.width - w) / 2 : pt(.x, cur.minX)
        var y = center ? (size.height - h) / 2 : pt(.y, cur.minY)
        x = min(max(x, 0), size.width - w); y = min(max(y, 0), size.height - h)
        area = nil
        var new = TabletArea(x: Double(x / size.width), y: Double(y / size.height),
                             width: Double(w / size.width), height: Double(h / size.height))
        let typedRot = (text[.r] ?? "").isEmpty ? before[.r] ?? "" : text[.r] ?? ""
        new.rotation = Self.number(typedRot).map { ($0.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
            ?? (area ?? model.tabletArea).rotation
        model.setTabletArea(new)
        before = [:]
        fill(new, size)   // show what was actually applied (after clamping)
    }

    /// New area with its bottom-right corner at `p` (top-left stays), aspect-locked if wanted.
    private func resized(_ a: TabletArea, to drag: CGPoint, in size: CGSize) -> TabletArea {
        let r = a.rect(in: size)
        // Drag point in the area's own (unrotated) frame.
        let ang = -a.rotation * .pi / 180
        let dx = Double(drag.x - r.midX), dy = Double(drag.y - r.midY)
        let p = CGPoint(x: Double(r.midX) + dx * cos(ang) - dy * sin(ang), y: Double(r.midY) + dx * sin(ang) + dy * cos(ang))
        var w = min(max(p.x - r.minX, 80), size.width - r.minX)
        var h = min(max(p.y - r.minY, 60), size.height - r.minY)
        if model.tabletLock {
            let asp = model.tabletAspect
            if w / h > asp { w = h * asp } else { h = w / asp }
        }
        var out = TabletArea(x: Double(r.minX / size.width), y: Double(r.minY / size.height),
                             width: Double(w / size.width), height: Double(h / size.height))
        out.rotation = a.rotation
        return out
    }

    private func commit() {
        if let area { model.setTabletArea(area) }
        area = nil
        dragStart = nil
    }
}
