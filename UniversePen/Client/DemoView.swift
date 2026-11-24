import SwiftUI
import UIKit
import TafelKit

/// Demo mode: runs entirely on the iPad, without a Mac – to show what UniversePen does.
/// Clearly labelled as a demo. "Display" simulates a desktop with a drawing window (real Pencil
/// pressure through your pressure curve, tilt, a pointer that follows the hovering Pencil, clicks);
/// "Tablet" shows tablet mode with a small monitor and targets to hit.
struct DemoView: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject var theme = Theme.shared
    enum Mode: Hashable { case display, tablet }
    @State private var mode: Mode = .display

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch mode {
                case .display: DemoDesktop()
                case .tablet: DemoTablet()
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .animation(Ultra.smooth, value: mode)
            // Always visible: this is a demo, not a Mac connection.
            HStack(spacing: 12) {
                Label(L("Demo – kein Mac verbunden"), systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
                    .padding(.leading, 8)
                UltraSegmented([(Mode.display, L("Display"), "display"), (Mode.tablet, L("Tablett"), "rectangle.dashed")],
                               selection: $mode)
                    .frame(width: 260)
                Button {
                    withAnimation(Ultra.smooth) { model.demoMode = false }
                } label: {
                    Label(L("Demo beenden"), systemImage: "xmark")
                }
                .buttonStyle(UltraProminent(compact: true))
            }
            .padding(6)
            .ultraPanel(Capsule())
            .padding(.top, 10)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Display demo

private struct DemoDesktop: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject var theme = Theme.shared
    @State private var color = Color.white
    @State private var size: CGFloat = 1
    @State private var pointer: CGPoint?
    @State private var ripples: [Ripple] = []
    @State private var clearToken = 0
    @State private var undoToken = 0

    private let colors: [Color] = [.white, Color(red: 0.5, green: 0.89, blue: 0.83), Color(red: 1, green: 0.54, blue: 0.48),
                                   Color(red: 1, green: 0.77, blue: 0.42), Color(red: 0.49, green: 0.77, blue: 1), Color(red: 0.75, green: 0.55, blue: 1)]

    struct Ripple: Identifiable { let id = UUID(); let at: CGPoint }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                ThemeBackground()
                // Menu bar
                HStack(spacing: 18) {
                    Image(systemName: "paintpalette.fill")
                    Text("UniversePen Paint").fontWeight(.semibold)
                    Text(L("Ablage")); Text(L("Bearbeiten")); Text(L("Ansicht"))
                    Spacer()
                    Text(Date.now, style: .time)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(.black.opacity(0.35))

                window(in: g.size)

                // Click ripples
                ForEach(ripples) { r in
                    RippleView().position(r.at).allowsHitTesting(false)
                }
                // Pointer
                if let p = pointer {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .position(x: p.x + 6, y: p.y + 10)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                if case .active(let p) = phase { pointer = p } else { pointer = nil }
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { v in click(at: v.location) })
        }
    }

    private func window(in size: CGSize) -> some View {
        let w = min(size.width - 80, 1100)
        let h = min(size.height - 130, 760)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 0) {
            titleBar
            toolbar
            paper
        }
        .frame(width: w, height: h)
        .background(Color(white: 0.11), in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: Color.black.opacity(0.5), radius: 30, y: 12)
        .position(x: size.width / 2, y: 30 + (size.height - 30) / 2)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red.opacity(0.85)).frame(width: 12, height: 12)
            Circle().fill(Color.yellow.opacity(0.85)).frame(width: 12, height: 12)
            Circle().fill(Color.green.opacity(0.85)).frame(width: 12, height: 12)
            Spacer()
            Text(L("Unbenannt – Demo")).font(.callout.weight(.medium)).opacity(0.8)
            Spacer()
            Color.clear.frame(width: 52)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color.white.opacity(0.08))
    }

    private var paper: some View {
        DemoPaper(color: UIColor(color), size: size, pressure: model.settings.pressure, tilt: model.settings.tilt,
                  clearToken: clearToken, undoToken: undoToken,
                  onPointer: { p in pointer = p })
    }

    private static let sizes: [(CGFloat, String)] = [(0.6, "S"), (1, "M"), (2, "L")]

    /// Real buttons – tap them with a finger or the Pencil (= click).
    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(colors.indices, id: \.self) { i in colorButton(i) }
            Divider().frame(height: 24)
            ForEach(Self.sizes, id: \.1) { item in sizeButton(item.0, item.1) }
            Spacer()
            Button { undoToken += 1 } label: { Label(L("Widerrufen"), systemImage: "arrow.uturn.backward") }
                .buttonStyle(.bordered)
            Button(role: .destructive) { clearToken += 1 } label: { Label(L("Leeren"), systemImage: "trash") }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    private func colorButton(_ i: Int) -> some View {
        let c = colors[i]
        let selected = color == c
        return Button { color = c } label: {
            Circle().fill(c).frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: selected ? 3 : 0))
        }
    }

    private func sizeButton(_ s: CGFloat, _ label: String) -> some View {
        let on = size == s
        return Button(label) { size = s }
            .buttonStyle(.bordered)
            .tint(on ? Brand.mint : Color.gray)
    }

    private func click(at p: CGPoint) {
        let r = Ripple(at: p)
        ripples.append(r)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { ripples.removeAll { $0.id == r.id } }
    }
}

private struct RippleView: View {
    @State private var go = false
    var body: some View {
        Circle().stroke(Color.white, lineWidth: 2)
            .frame(width: 40, height: 40)
            .scaleEffect(go ? 1.6 : 0.3)
            .opacity(go ? 0 : 0.9)
            .onAppear { withAnimation(.easeOut(duration: 0.5)) { go = true } }
    }
}

/// Drawing surface: Pencil strokes with the user's pressure curve; tilt widens the line.
private struct DemoPaper: UIViewRepresentable {
    let color: UIColor
    let size: CGFloat
    let pressure: PressureCurve
    let tilt: TiltConverter
    let clearToken: Int
    let undoToken: Int
    let onPointer: (CGPoint?) -> Void

    func makeUIView(context: Context) -> PaperView { PaperView() }
    func updateUIView(_ v: PaperView, context: Context) {
        v.color = color; v.sizeFactor = size; v.curve = pressure
        v.onPointer = { p in onPointer(p.map { v.convert($0, to: nil) }) }
        if v.clearToken != clearToken { v.clearToken = clearToken; v.clear() }
        if v.undoToken != undoToken { v.undoToken = undoToken; v.undo() }
    }

    final class PaperView: UIView {
        var color: UIColor = .white
        var sizeFactor: CGFloat = 1
        var curve = PressureCurve()
        var clearToken = 0
        var undoToken = 0
        var onPointer: ((CGPoint?) -> Void)?

        private struct Dab { var p: CGPoint; var w: CGFloat }
        private var strokes: [(color: UIColor, dabs: [Dab])] = []
        private var image: UIImage?
        private var pencil: UITouch?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor(white: 0.97, alpha: 1)
            isMultipleTouchEnabled = true
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
            addGestureRecognizer(hover)
        }
        required init?(coder: NSCoder) { fatalError() }

        @objc private func hovered(_ g: UIHoverGestureRecognizer) {
            switch g.state {
            case .began, .changed: onPointer?(g.location(in: self))
            default: if pencil == nil { onPointer?(nil) }
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard pencil == nil, let t = touches.first(where: { $0.type == .pencil }) else { return }
            pencil = t
            strokes.append((color == .white ? .black : color, []))
            add(t, event)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = pencil, touches.contains(t) else { return }
            add(t, event)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finish(touches) }

        private func finish(_ touches: Set<UITouch>) {
            guard let t = pencil, touches.contains(t) else { return }
            pencil = nil
            bake()
        }

        private func add(_ t: UITouch, _ event: UIEvent?) {
            for c in event?.coalescedTouches(for: t) ?? [t] {
                let p = curve.apply(force: Double(c.force), maximumForce: Double(c.maximumPossibleForce))
                // Flatter Pencil = broader line, like a pencil lead on its side.
                let flat = 1 + 1.5 * (1 - min(Double(c.altitudeAngle) / (.pi / 2), 1))
                let w = CGFloat(1.5 + 14 * p * flat) * sizeFactor
                strokes[strokes.count - 1].dabs.append(Dab(p: c.preciseLocation(in: self), w: w))
                onPointer?(c.location(in: self))
            }
            setNeedsDisplay()
        }

        func clear() { strokes.removeAll(); baked.removeAll(); image = nil; setNeedsDisplay() }
        func undo() { if !baked.isEmpty { baked.removeLast(); bake() } }

        /// Finished strokes go into a bitmap so long drawings stay fast.
        private var baked: [(color: UIColor, dabs: [Dab])] = []
        private func bake() {
            guard bounds.width > 0 else { return }
            if pencil == nil { baked += strokes; strokes = [] }
            let all = baked
            image = UIGraphicsImageRenderer(bounds: bounds).image { ctx in
                for s in all { draw(s, in: ctx.cgContext) }
            }
            setNeedsDisplay()
        }

        private func draw(_ s: (color: UIColor, dabs: [Dab]), in ctx: CGContext) {
            ctx.setLineCap(.round)
            ctx.setStrokeColor(s.color.cgColor)
            for i in s.dabs.indices.dropFirst() {
                let a = s.dabs[i - 1], b = s.dabs[i]
                ctx.setLineWidth((a.w + b.w) / 2)
                ctx.move(to: a.p); ctx.addLine(to: b.p); ctx.strokePath()
            }
            if s.dabs.count == 1, let d = s.dabs.first {
                ctx.setFillColor(s.color.cgColor)
                ctx.fillEllipse(in: CGRect(x: d.p.x - d.w / 2, y: d.p.y - d.w / 2, width: d.w, height: d.w))
            }
        }

        override func draw(_ rect: CGRect) {
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            image?.draw(in: bounds)
            for s in strokes { draw(s, in: ctx) }
        }
    }
}

// MARK: - Tablet demo

private struct DemoTablet: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject var theme = Theme.shared
    @State private var cursor: CGPoint?        // normalised 0…1 on the "monitor"
    @State private var target = CGPoint(x: 0.5, y: 0.5)
    @State private var hits = 0
    @State private var tries = 0
    @State private var flash = false

    var body: some View {
        GeometryReader { g in
            ZStack {
                TabletSurfaceView()
                DemoTabletInput(area: model.tabletArea, onMove: { n in cursor = n }, onDown: { n in tap(n) })
                // Small monitor showing where the pointer is on the "Mac"
                let mw = min(g.size.width * 0.34, 420), mh = mw / 1.6
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.08))
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 2)
                    Circle()
                        .stroke(Brand.mint, lineWidth: 3)
                        .frame(width: 34, height: 34)
                        .scaleEffect(flash ? 1.5 : 1)
                        .opacity(flash ? 0 : 1)
                        .position(x: target.x * mw, y: target.y * mh)
                    if let c = cursor {
                        Circle().fill(.white).frame(width: 9, height: 9)
                            .shadow(color: Brand.mint, radius: 6)
                            .position(x: c.x * mw, y: c.y * mh)
                    }
                }
                .frame(width: mw, height: mh)
                .overlay(alignment: .bottom) {
                    Text(L("Treffer: %d / %d", hits, tries))
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .tafelOverlayGlass(Capsule())
                        .offset(y: 22)
                }
                .position(x: g.size.width / 2, y: 70 + mh / 2)
                .allowsHitTesting(false)
                Text(L("Mit dem Pencil im aktiven Bereich zielen und auf den Kreis tippen – der Bereich ist auf den ganzen „Monitor“ abgebildet."))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .position(x: g.size.width / 2, y: g.size.height - 40)
                    .allowsHitTesting(false)
            }
        }
    }

    private func tap(_ n: CGPoint) {
        cursor = n
        tries += 1
        // Target radius in monitor units (~17 pt of a ~420 pt wide monitor).
        if hypot((n.x - target.x) * 1.6, n.y - target.y) < 0.07 {
            hits += 1
            withAnimation(.easeOut(duration: 0.25)) { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                flash = false
                target = CGPoint(x: .random(in: 0.1...0.9), y: .random(in: 0.12...0.88))
            }
        }
    }
}

/// Pencil hover/touches mapped through the (possibly rotated) active area, like real tablet mode.
private struct DemoTabletInput: UIViewRepresentable {
    let area: TabletArea
    let onMove: (CGPoint) -> Void
    let onDown: (CGPoint) -> Void

    func makeUIView(context: Context) -> InputView { InputView() }
    func updateUIView(_ v: InputView, context: Context) {
        v.area = area; v.onMove = onMove; v.onDown = onDown
    }

    final class InputView: UIView {
        var area = TabletArea()
        var onMove: ((CGPoint) -> Void)?
        var onDown: ((CGPoint) -> Void)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
        }
        required init?(coder: NSCoder) { fatalError() }
        private func n(_ p: CGPoint) -> CGPoint { area.normalized(p, in: bounds.size) }
        @objc private func hover(_ g: UIHoverGestureRecognizer) {
            if g.state == .began || g.state == .changed { onMove?(n(g.location(in: self))) }
        }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first(where: { $0.type == .pencil }) else { return }
            onDown?(n(t.preciseLocation(in: self)))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first(where: { $0.type == .pencil }) else { return }
            onMove?(n(t.preciseLocation(in: self)))
        }
    }
}
