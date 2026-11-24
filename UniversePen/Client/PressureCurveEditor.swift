import SwiftUI
import UIKit
import TafelKit

/// Freely editable pressure curve: drag the points with a finger, press with the Pencil on the
/// test pad to see where your pressure lands on the curve.
struct PressureCurveEditor: View {
    /// Redraw when the colours change.
    @ObservedObject var theme = Theme.shared
    @Binding var curve: PressureCurve
    @State private var live: Double?   // raw Pencil force 0…1 on the test pad

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { g in
                let size = g.size
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05))
                    grid(size)
                    // Curve
                    Path { p in
                        for i in 0...100 {
                            let x = Double(i) / 100
                            let pt = point(x, curve.map(x), size)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(Brand.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .shadow(color: Brand.mint.opacity(0.5), radius: 6)
                    // Live Pencil marker
                    if let live {
                        let pt = point(live, curve.map(live), size)
                        Circle().fill(.white).frame(width: 14, height: 14)
                            .shadow(color: .white.opacity(0.8), radius: 8)
                            .position(pt)
                    }
                    // Control points
                    let pts = curve.editablePoints()
                    ForEach(pts.indices, id: \.self) { i in
                        Circle()
                            .fill(Brand.slateDeep)
                            .overlay(Circle().strokeBorder(Brand.mint, lineWidth: 3))
                            .frame(width: 26, height: 26)
                            .contentShape(Circle().inset(by: -14))
                            .position(point(pts[i].x, pts[i].y, size))
                            .gesture(DragGesture(minimumDistance: 0).onChanged { v in drag(i, to: v.location, size) })
                    }
                }
            }
            .aspectRatio(1.4, contentMode: .fit)

            HStack {
                Text(L("leicht")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(L("Pencil-Druck →")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(L("fest")).font(.caption).foregroundStyle(.secondary)
            }

            ForceProbe(force: $live)
                .frame(height: 70)
                .overlay {
                    Text(live.map { L("Eingabe %d %% → Ausgabe %d %%", Int($0 * 100), Int(max(curve.map($0), curve.minimum) * 100)) }
                         ?? L("Hier mit dem Pencil drücken zum Testen"))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                ForEach([(L("Weich"), 0.6), (L("Normal"), 1.0), (L("Fest"), 1.6)], id: \.1) { preset in
                    Button(preset.0) {
                        withAnimation(Brand.spring) { curve.points = []; curve.gamma = preset.1 }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func point(_ x: Double, _ y: Double, _ s: CGSize) -> CGPoint {
        CGPoint(x: 13 + x * (s.width - 26), y: 13 + (1 - y) * (s.height - 26))
    }

    private func drag(_ i: Int, to loc: CGPoint, _ s: CGSize) {
        var pts = curve.editablePoints()
        let w = max(s.width - 26, 1), h = max(s.height - 26, 1)
        var x = Double((loc.x - 13) / w)
        let y = min(max(1 - Double((loc.y - 13) / h), 0), 1)
        // End points stay at x = 0 / 1; inner points stay between their neighbours.
        if i == 0 { x = 0 } else if i == pts.count - 1 { x = 1 } else {
            x = min(max(x, pts[i - 1].x + 0.02), pts[i + 1].x - 0.02)
        }
        pts[i] = CurvePoint(x, y)
        curve.points = pts
    }

    private func grid(_ s: CGSize) -> some View {
        Path { p in
            for k in 1..<4 {
                let f = CGFloat(k) / 4
                p.move(to: CGPoint(x: 13 + f * (s.width - 26), y: 13)); p.addLine(to: CGPoint(x: 13 + f * (s.width - 26), y: s.height - 13))
                p.move(to: CGPoint(x: 13, y: 13 + f * (s.height - 26))); p.addLine(to: CGPoint(x: s.width - 13, y: 13 + f * (s.height - 26)))
            }
            p.move(to: CGPoint(x: 13, y: s.height - 13)); p.addLine(to: CGPoint(x: s.width - 13, y: 13))
        }
        .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

/// Reports the raw Pencil force (0…1) while the Pencil presses on it.
private struct ForceProbe: UIViewRepresentable {
    @Binding var force: Double?

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.onForce = { f in force = f }
        return v
    }
    func updateUIView(_ v: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        var onForce: ((Double?) -> Void)?
        override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear }
        required init?(coder: NSCoder) { fatalError() }
        private func report(_ touches: Set<UITouch>) {
            guard let t = touches.first(where: { $0.type == .pencil }), t.maximumPossibleForce > 0 else { return }
            onForce?(Double(t.force / t.maximumPossibleForce))
        }
        override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { report(t) }
        override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { report(t) }
        override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { onForce?(nil) }
        override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { onForce?(nil) }
    }
}
