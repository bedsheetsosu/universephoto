import SwiftUI
import UIKit
import TafelKit

/// Pencil setup for one Mac (1.3): opens right after a Mac is paired (or from Settings → Pencil).
/// It starts when the Pencil tip rests on the glowing pad, then walks through pressure, click
/// threshold, hover, squeeze/double tap and a finger check. Everything it sets belongs to this Mac
/// and switches in whenever it connects.
struct MacSetupView: View {
    @EnvironmentObject var model: ClientModel
    @ObservedObject private var theme = Theme.shared
    let host: HostInfo

    enum Step: Int, CaseIterable { case start, light, firm, curve, click, hover, gestures, fingers, done }
    /// `-debugMacSetupStep N` opens the setup on step N (UI checks).
    @State private var step: Step = Step(rawValue: UserDefaults.standard.integer(forKey: "debugMacSetupStep")) ?? .start
    @State private var forward = true

    // Start pad
    @State private var holdProgress = 0.0
    @State private var holdTimer: Timer?
    @State private var burst = false

    // Strokes on the practice area
    @State private var strokes: [[TouchSample]] = []
    @State private var current: [TouchSample] = []
    @State private var light: [Double] = []
    @State private var firm: [Double] = []

    // Click
    @State private var clickByPressure = false
    @State private var clickPeaks: [Double] = []
    @State private var livePressure = 0.0
    @State private var peak = 0.0

    // Hover
    @State private var hoverPoint: CGPoint?
    @State private var hoverSeen = false
    @State private var litDots: Set<Int> = []

    // Fingers
    @State private var tappedTargets: Set<Int> = []
    @State private var twoFingerTap = false
    @State private var fingersDown: [Int: (CGPoint, Date)] = [:]
    @State private var maxFingers = 0

    // Finale: three taps and the setup bursts into the app.
    @State private var tapsDone = 0
    @State private var exploded = false
    @State private var shake = 0.0

    var body: some View {
        ZStack {
          ZStack {
            ThemeBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ZStack {
                    page
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .frame(maxWidth: 760, maxHeight: .infinity)
                .padding(.horizontal, 28)
                footer
            }
          }
          // The setup flies apart on the third tap.
          .scaleEffect(exploded ? 1.35 : 1)
          .blur(radius: exploded ? 22 : 0)
          .opacity(exploded ? 0 : 1)
          .animation(.easeIn(duration: 0.45), value: exploded)
          if exploded { Sparks().allowsHitTesting(false) }
        }
        .animation(Ultra.smooth, value: step)
        .sensoryFeedback(.selection, trigger: step)
        .onDisappear { holdTimer?.invalidate() }
    }

    // MARK: Frame

    private var header: some View {
        HStack {
            Button(L("Später")) { model.cancelMacSetup() }
                .buttonStyle(UltraQuiet())
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Brand.mint : Color.white.opacity(0.18))
                        .frame(width: s == step ? 22 : 7, height: 7)
                }
            }
            .animation(Ultra.smooth, value: step)
            Spacer()
            Text(host.hostName).font(.callout.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 28).padding(.top, 22)
    }

    @ViewBuilder private var footer: some View {
        if step != .start && step != .light && step != .firm {
            HStack {
                Button { go(-1) } label: { Label(L("Zurück"), systemImage: "chevron.left") }
                    .buttonStyle(UltraQuiet())
                Spacer()
                if step != .done { Button {
                    go(1)
                } label: {
                    HStack(spacing: 8) {
                        Text(step == .done ? L("Los geht’s") : L("Weiter"))
                        Image(systemName: step == .done ? "checkmark" : "arrow.right")
                    }
                    .font(.callout.weight(.bold)).foregroundStyle(Brand.slateDeep)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Ultra.accentFill, in: Capsule())
                    .shadow(color: Brand.mint.opacity(0.5), radius: 14, y: 3)
                }
                .buttonStyle(UltraPress())
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.4) }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 28).padding(.bottom, 26)
        }
    }

    private var canContinue: Bool {
        switch step {
        case .click: return !clickByPressure || clickPeaks.count >= 3
        case .fingers: return tappedTargets.count == 3 && twoFingerTap
        default: return true
        }
    }

    private func go(_ d: Int) {
        forward = d > 0
        let next = Step(rawValue: step.rawValue + d) ?? step
        // Going back from the curve repeats both strokes.
        if next == .firm && d < 0 { step = .light; light = []; firm = []; strokes = []; return }
        step = next
        strokes = []; current = []
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(spacing: 10) {
            Text(t).font(.system(size: 32, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
            Text(sub).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .start: startPage
        case .light, .firm: strokePage
        case .curve: curvePage
        case .click: clickPage
        case .hover: hoverPage
        case .gestures: gesturesPage
        case .fingers: fingersPage
        case .done: donePage
        }
    }

    // MARK: Start – rest the Pencil on the pad

    private var startPage: some View {
        VStack(spacing: 34) {
            Spacer()
            title(L("Pencil-Setup für %@", host.hostName), L("Setz die Pencil-Spitze auf die leuchtende Fläche und halte sie kurz."))
            ZStack {
                // Breathing glow around the pad.
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Brand.mint.opacity(0.55), lineWidth: 2)
                    .frame(width: 340, height: 220)
                    .phaseAnimator([false, true]) { v, on in
                        v.scaleEffect(on ? 1.06 : 1).opacity(on ? 0.15 : 0.9)
                    } animation: { _ in .easeInOut(duration: 1.4) }
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Brand.mint.opacity(0.08 + 0.22 * holdProgress))
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Brand.mint.opacity(0.8), lineWidth: 1.5))
                    .frame(width: 320, height: 200)
                    .shadow(color: Brand.mint.opacity(0.25 + 0.5 * holdProgress), radius: 30)
                // Progress ring while the tip rests.
                Circle().stroke(.white.opacity(0.12), lineWidth: 6).frame(width: 96, height: 96)
                Circle().trim(from: 0, to: holdProgress)
                    .stroke(Brand.mint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 96, height: 96)
                Image(systemName: "applepencil.tip")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Brand.mint)
                    .symbolEffect(.bounce, options: .repeating.speed(0.5), isActive: holdProgress == 0)
                // Burst when it starts.
                ForEach(0..<3, id: \.self) { i in
                    Circle().stroke(Brand.mint.opacity(burst ? 0 : 0.8), lineWidth: 3)
                        .frame(width: 96, height: 96)
                        .scaleEffect(burst ? 3.2 + Double(i) * 0.7 : 1)
                        .animation(.easeOut(duration: 0.7).delay(Double(i) * 0.08), value: burst)
                }
                SetupTouchSurface(onTouch: startTouch).frame(width: 340, height: 220)
            }
            .sensoryFeedback(.success, trigger: burst)
            Text(L("Nur mit dem Pencil – Finger zählen hier nicht.")).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func startTouch(_ e: TouchEvent) {
        guard e.kind == .pencil, !burst else { return }
        switch e.phase {
        case .began:
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { t in
                MainActor.assumeIsolated {
                    holdProgress = min(1, holdProgress + 1.0 / 48)
                    if holdProgress >= 1 {
                        t.invalidate()
                        burst = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { forward = true; step = .light }
                    }
                }
            }
        case .moved: break
        case .ended:
            holdTimer?.invalidate()
            if !burst { withAnimation(Ultra.smooth) { holdProgress = 0 } }
        }
    }

    // MARK: Pressure

    private var strokePage: some View {
        VStack(spacing: 24) {
            title(step == .light ? L("Ganz leicht") : L("Jetzt kräftig"),
                  step == .light ? L("Zeichne eine Linie mit so wenig Druck, wie du sonst für feine Striche nimmst.")
                                 : L("Und jetzt eine Linie mit so viel Druck, wie du für volle Striche nimmst."))
                .padding(.top, 30)
            drawingArea { samples in
                let forces = samples.map(\.force).filter { $0 > 0 }
                guard forces.count >= 8 else { return }
                if step == .light { light = forces; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { go(1) } }
                else {
                    firm = forces
                    if let c = PressureCalibration.curve(light: light, firm: firm, minimum: model.settings.pressure.minimum) { model.settings.pressure = c }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { go(1) }
                }
            }
            Spacer(minLength: 10)
        }
    }

    private var curvePage: some View {
        VStack(spacing: 22) {
            title(L("Deine Druckkurve"), L("Dein leichter Strich ergibt etwa ein Viertel, dein kräftiger fast vollen Druck. Probier es unten aus."))
                .padding(.top, 30)
            HStack(spacing: 22) {
                CurveGraph(curve: model.settings.pressure, light: PressureCalibration.quantile(light, 0.5), firm: PressureCalibration.quantile(firm, 0.9))
                    .frame(width: 200, height: 200)
                drawingArea(curve: model.settings.pressure) { _ in }
            }
            Button { light = []; firm = []; forward = false; step = .light } label: { Label(L("Nochmal kalibrieren"), systemImage: "arrow.counterclockwise") }
                .buttonStyle(UltraQuiet())
            Spacer(minLength: 10)
        }
    }

    /// The practice area: Pencil strokes drawn with their (curved) pressure.
    private func drawingArea(curve: PressureCurve? = nil, done: @escaping ([TouchSample]) -> Void) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Ultra.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: Ultra.cardRadius, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            Canvas { ctx, _ in
                for s in strokes + [current] where s.count > 1 {
                    for i in 1..<s.count {
                        let p = curve.map { $0.map(s[i].force) } ?? s[i].force
                        var path = Path(); path.move(to: s[i - 1].point); path.addLine(to: s[i].point)
                        ctx.stroke(path, with: .color(Brand.mint), style: StrokeStyle(lineWidth: 1.5 + 16 * p, lineCap: .round))
                    }
                }
            }
            .allowsHitTesting(false)
            SetupTouchSurface { e in
                guard e.kind == .pencil else { return }
                switch e.phase {
                case .began: current = [TouchSample(point: e.point, force: e.force)]
                case .moved: current.append(contentsOf: e.samples.map { TouchSample(point: $0.0, force: $0.1) })
                case .ended:
                    let s = current; strokes.append(s); current = []
                    if strokes.count > 6 { strokes.removeFirst() }
                    done(s)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: Ultra.cardRadius, style: .continuous))
    }

    // MARK: Click

    private var clickPage: some View {
        VStack(spacing: 24) {
            title(L("Wann wird geklickt?"), L("Sofort bei Berührung – oder leichte Berührungen bleiben Schweben und erst fester Druck klickt."))
                .padding(.top, 30)
            HStack(spacing: 14) {
                choice(L("Sofort klicken"), "hand.tap", !clickByPressure) { clickByPressure = false; model.settings.tipThreshold = 0; clickPeaks = [] }
                choice(L("Erst ab Druck"), "hand.point.up.braille", clickByPressure) { clickByPressure = true; clickPeaks = [] }
            }
            if clickByPressure {
                VStack(spacing: 14) {
                    Text(clickPeaks.count < 3 ? L("Tippe %d× auf den Kreis – so fest, wie ein Klick sein soll.", 3 - clickPeaks.count)
                                              : L("Klick ab Druck: %d %%. Teste: leicht = Schweben, fest = Klick.", Int(model.settings.tipThreshold * 100)))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    let clicking = clickPeaks.count >= 3 && livePressure >= model.settings.tipThreshold && livePressure > 0
                    ZStack {
                        Circle().fill(clicking ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(0.08)))
                            .overlay(Circle().strokeBorder(Brand.mint.opacity(0.7), lineWidth: 2))
                        Circle().trim(from: 0, to: livePressure).stroke(Brand.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90)).padding(8)
                        Text(clicking ? L("Klick!") : livePressure > 0 ? L("Schweben") : "")
                            .font(.headline).foregroundStyle(clicking ? Brand.slateDeep : .primary)
                        SetupTouchSurface { e in
                            guard e.kind == .pencil else { return }
                            let p = model.settings.pressure.map(e.force)
                            switch e.phase {
                            case .began: peak = p; livePressure = p
                            case .moved: peak = max(peak, p); livePressure = p
                            case .ended:
                                livePressure = 0
                                if clickPeaks.count < 3 {
                                    clickPeaks.append(peak)
                                    if clickPeaks.count == 3, let t = PressureCalibration.clickThreshold(peaks: clickPeaks) { model.settings.tipThreshold = t }
                                }
                            }
                        }
                    }
                    .frame(width: 170, height: 170)
                    .sensoryFeedback(.impact(weight: .light), trigger: clicking) { _, n in n }
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: clicking)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            Spacer(minLength: 10)
        }
        .animation(Ultra.smooth, value: clickByPressure)
        .onAppear { clickByPressure = model.settings.tipThreshold > 0 }
    }

    private func choice(_ t: String, _ symbol: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 26, weight: .semibold))
                Text(t).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .foregroundStyle(on ? Brand.slateDeep : .primary)
            .background(RoundedRectangle(cornerRadius: Ultra.cardRadius, style: .continuous).fill(on ? AnyShapeStyle(Ultra.accentFill) : AnyShapeStyle(Color.white.opacity(0.07))))
            .overlay(RoundedRectangle(cornerRadius: Ultra.cardRadius, style: .continuous).strokeBorder(Color.white.opacity(on ? 0.35 : 0.12), lineWidth: 1))
        }
        .buttonStyle(UltraPress())
    }

    // MARK: Hover

    private var hoverPage: some View {
        VStack(spacing: 22) {
            title(L("Schweben"), hoverSeen ? L("Dein Pencil schwebt – fahr knapp über dem Display über die drei Punkte.")
                                           : L("Halte die Pencil-Spitze knapp über das Display, ohne es zu berühren."))
                .padding(.top, 30)
            ZStack {
                RoundedRectangle(cornerRadius: Ultra.cardRadius, style: .continuous).fill(Color.white.opacity(0.06))
                GeometryReader { g in
                    let dots = (0..<3).map { CGPoint(x: g.size.width * (0.2 + 0.3 * Double($0)), y: g.size.height * (0.5 + ($0 == 1 ? -0.2 : 0.15))) }
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(litDots.contains(i) ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(0.1)))
                            .overlay(Circle().strokeBorder(Brand.mint.opacity(0.6), lineWidth: 1.5))
                            .frame(width: 54, height: 54)
                            .scaleEffect(litDots.contains(i) ? 1.15 : 1)
                            .position(dots[i])
                    }
                    if let h = hoverPoint {
                        Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2).frame(width: 18, height: 18).position(h)
                    }
                    SetupTouchSurface(onTouch: { _ in }, onHover: { p in
                        hoverPoint = p
                        guard let p else { return }
                        if !hoverSeen { hoverSeen = true }
                        for (i, d) in dots.enumerated() where hypot(d.x - p.x, d.y - p.y) < 34 { litDots.insert(i) }
                    })
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 280)
            .sensoryFeedback(.selection, trigger: litDots.count)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: litDots)
            VStack(spacing: 0) {
                Toggle(L("Schweben an den Mac senden"), isOn: $model.settings.sendHover)
                Divider().opacity(0.3).padding(.vertical, 8)
                Toggle(L("Schwebe-Punkt auf dem iPad"), isOn: $model.settings.hoverDot)
                Divider().opacity(0.3).padding(.vertical, 8)
                Toggle(L("Neigung am Schwebe-Punkt zeigen"), isOn: $model.settings.hoverTilt)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Ultra.cardRadius, style: .continuous).fill(Color.white.opacity(0.06)))
            if !hoverSeen {
                Text(L("Kein Schweben erkannt? Ältere Pencils und iPads können das nicht – dann einfach weiter.")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
        }
    }

    // MARK: Squeeze & double tap

    private var gesturesPage: some View {
        VStack(spacing: 22) {
            title(L("Squeeze & Doppeltippen"), L("Was der Pencil auf diesem Mac tun soll. Squeeze gibt es nur beim Apple Pencil Pro."))
                .padding(.top, 30)
            VStack(spacing: 14) {
                ActionPicker(title: L("Doppeltippen"), action: $model.settings.doubleTap)
                Divider().opacity(0.3)
                ActionPicker(title: L("Squeeze"), action: $model.settings.squeeze)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: Ultra.cardRadius, style: .continuous).fill(Color.white.opacity(0.06)))
            Spacer(minLength: 10)
        }
    }

    // MARK: Fingers

    private var fingersPage: some View {
        VStack(spacing: 22) {
            title(L("Finger-Check"), tappedTargets.count < 3 ? L("Tippe die drei Punkte mit dem Finger an.") : L("Jetzt einmal kurz mit zwei Fingern gleichzeitig tippen."))
                .padding(.top, 30)
            ZStack {
                RoundedRectangle(cornerRadius: Ultra.cardRadius, style: .continuous).fill(Color.white.opacity(0.06))
                GeometryReader { g in
                    let targets = (0..<3).map { CGPoint(x: g.size.width * (0.22 + 0.28 * Double($0)), y: g.size.height * ($0 == 1 ? 0.32 : 0.62)) }
                    ForEach(0..<3, id: \.self) { i in
                        let done = tappedTargets.contains(i)
                        ZStack {
                            Circle().fill(done ? AnyShapeStyle(Brand.mint) : AnyShapeStyle(Color.white.opacity(0.1)))
                            Image(systemName: done ? "checkmark" : "hand.point.up.left").font(.title2.weight(.semibold))
                                .foregroundStyle(done ? Brand.slateDeep : .primary)
                        }
                        .frame(width: 70, height: 70).scaleEffect(done ? 1.1 : 1).position(targets[i])
                    }
                    if twoFingerTap {
                        Label(L("Zwei Finger erkannt"), systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(Brand.mint)
                            .position(x: g.size.width / 2, y: g.size.height - 28)
                            .transition(.scale.combined(with: .opacity))
                    }
                    SetupTouchSurface { e in
                        guard e.kind == .finger else { return }
                        switch e.phase {
                        case .began:
                            fingersDown[e.id] = (e.point, Date()); maxFingers = max(maxFingers, fingersDown.count)
                        case .moved: break
                        case .ended:
                            if let (start, t) = fingersDown[e.id], tappedTargets.count < 3, Date().timeIntervalSince(t) < 0.6 {
                                for (i, p) in targets.enumerated() where hypot(p.x - start.x, p.y - start.y) < 46 { tappedTargets.insert(i) }
                            }
                            fingersDown[e.id] = nil
                            if fingersDown.isEmpty {
                                if maxFingers == 2, tappedTargets.count == 3 { twoFingerTap = true }
                                maxFingers = 0
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 320)
            .sensoryFeedback(.success, trigger: tappedTargets.count + (twoFingerTap ? 10 : 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: tappedTargets)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: twoFingerTap)
            Spacer(minLength: 10)
        }
    }

    // MARK: Done

    private var donePage: some View {
        VStack(spacing: 22) {
            Spacer()
            title(L("Fertig für %@", host.hostName), L("Diese Einstellungen gelten jetzt nur für diesen Mac und kommen automatisch, sobald er verbunden ist. Ändern kannst du sie jederzeit unter Einstellungen → Pencil."))
            VStack(alignment: .leading, spacing: 8) {
                Label(model.settings.tipThreshold == 0 ? L("Klick ab Druck: sofort") : L("Klick ab Druck: %d %%", Int(model.settings.tipThreshold * 100)), systemImage: "hand.tap")
                Label(model.settings.sendHover ? L("Schweben an") : L("Schweben aus"), systemImage: "dot.circle.viewfinder")
                Label(L("Doppeltippen: %@", model.settings.doubleTap.display), systemImage: "applepencil.doubletap")
                Label(L("Squeeze: %@", model.settings.squeeze.display), systemImage: "applepencil.squeeze")
            }
            .font(.callout).foregroundStyle(.secondary)
            finaleButton.padding(.top, 10)
            Text(tapsDone == 0 ? L("Dreimal drauftippen, um loszulegen") : L("Noch %d×", 3 - tapsDone))
                .font(.headline).foregroundStyle(Brand.mint)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.25), value: tapsDone)
            Spacer()
        }
    }

    /// The big seal: each tap makes it jump and send out a ring, a bit more each time; the third
    /// one bursts the setup and opens the app.
    private var finaleButton: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(Brand.mint.opacity(tapsDone > i ? 0 : 0.7), lineWidth: 3)
                    .frame(width: 130, height: 130)
                    .scaleEffect(tapsDone > i ? 2.4 : 1)
                    .animation(.easeOut(duration: 0.6), value: tapsDone)
            }
            Circle().fill(Ultra.accentFill)
                .frame(width: 130, height: 130)
                .shadow(color: Brand.mint.opacity(0.4 + 0.2 * Double(tapsDone)), radius: 20 + 10 * Double(tapsDone))
            Image(systemName: "checkmark.seal.fill").font(.system(size: 58, weight: .semibold)).foregroundStyle(Brand.slateDeep)
                .symbolEffect(.bounce, value: tapsDone)
        }
        .scaleEffect(1 + 0.08 * Double(tapsDone))
        .rotationEffect(.degrees(sin(shake * .pi * 6) * 4 * Double(tapsDone)))
        .contentShape(Circle())
        .onTapGesture { tapFinale() }
        .sensoryFeedback(trigger: tapsDone) { _, n in n >= 3 ? .impact(weight: .heavy, intensity: 1) : .impact(weight: .medium, intensity: 0.5 + 0.2 * Double(n)) }
        .accessibilityLabel(L("Dreimal drauftippen, um loszulegen"))
        .accessibilityAddTraits(.isButton)
    }

    private func tapFinale() {
        guard !exploded else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { tapsDone += 1 }
        shake = 0
        withAnimation(.easeOut(duration: 0.35)) { shake = 1 }
        guard tapsDone >= 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            exploded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { model.finishMacSetup() }
        }
    }
}

/// Sparks flying out from the centre when the setup bursts.
private struct Sparks: View {
    @State private var out = false
    private let sparks: [(angle: Double, dist: Double, size: Double, delay: Double)] = (0..<42).map { i in
        let a = Double(i) / 42 * 2 * .pi + Double((i * 37) % 11) / 11 * 0.3
        return (a, 220 + Double((i * 53) % 9) * 55, 5 + Double((i * 29) % 7) * 2, Double(i % 5) * 0.02)
    }

    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height * 0.62)
            ZStack {
                Circle().fill(Brand.mint.opacity(out ? 0 : 0.6))
                    .frame(width: 140, height: 140).scaleEffect(out ? 9 : 1)
                    .position(c)
                ForEach(0..<sparks.count, id: \.self) { i in
                    let s = sparks[i]
                    Circle().fill(i % 3 == 0 ? Color.white : Brand.mint)
                        .frame(width: s.size, height: s.size)
                        .position(x: c.x + (out ? cos(s.angle) * s.dist : 0), y: c.y + (out ? sin(s.angle) * s.dist : 0))
                        .opacity(out ? 0 : 1)
                        .animation(.easeOut(duration: 0.8).delay(s.delay), value: out)
                }
            }
            .animation(.easeOut(duration: 0.7), value: out)
        }
        .ignoresSafeArea()
        .onAppear { out = true }
    }
}

// MARK: - Touch input

struct TouchSample { var point: CGPoint; var force: Double }

struct TouchEvent {
    enum Kind { case pencil, finger }
    enum Phase { case began, moved, ended }
    var id: Int
    var kind: Kind
    var phase: Phase
    var point: CGPoint
    /// Normalised force 0…1 (pencil); 0 for fingers.
    var force: Double
    /// Coalesced samples since the last event (point, force), for smooth strokes.
    var samples: [(CGPoint, Double)]
}

/// A transparent UIKit view that reports raw touches (Pencil force, finger count) and Pencil hover.
struct SetupTouchSurface: UIViewRepresentable {
    var onTouch: (TouchEvent) -> Void
    var onHover: ((CGPoint?) -> Void)? = nil

    func makeUIView(context: Context) -> SurfaceView {
        let v = SurfaceView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true
        let hover = UIHoverGestureRecognizer(target: v, action: #selector(SurfaceView.hovered(_:)))
        v.addGestureRecognizer(hover)
        return v
    }

    func updateUIView(_ v: SurfaceView, context: Context) { v.onTouch = onTouch; v.onHover = onHover }

    final class SurfaceView: UIView {
        var onTouch: ((TouchEvent) -> Void)?
        var onHover: ((CGPoint?) -> Void)?

        private func send(_ touches: Set<UITouch>, _ event: UIEvent?, _ phase: TouchEvent.Phase) {
            for t in touches {
                let pencil = t.type == .pencil
                let norm = { (x: UITouch) -> Double in pencil && x.maximumPossibleForce > 0 ? Double(x.force / x.maximumPossibleForce) : 0 }
                let co = (event?.coalescedTouches(for: t) ?? [t]).map { ($0.location(in: self), norm($0)) }
                onTouch?(TouchEvent(id: ObjectIdentifier(t).hashValue, kind: pencil ? .pencil : .finger, phase: phase,
                                    point: t.location(in: self), force: norm(t), samples: co))
            }
        }
        override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { send(t, e, .began) }
        override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { send(t, e, .moved) }
        override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { send(t, e, .ended) }
        override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { send(t, e, .ended) }

        @objc func hovered(_ g: UIHoverGestureRecognizer) {
            switch g.state {
            case .began, .changed: onHover?(g.location(in: self))
            default: onHover?(nil)
            }
        }
    }
}

/// Small read-only graph of a pressure curve, with your light and firm pressure marked.
private struct CurveGraph: View {
    let curve: PressureCurve
    let light: Double?
    let firm: Double?

    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16), with: .color(.white.opacity(0.06)))
            var grid = Path(); grid.move(to: CGPoint(x: r.minX, y: r.maxY)); grid.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            ctx.stroke(grid, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            var p = Path()
            for i in 0...60 {
                let x = Double(i) / 60, y = curve.map(x)
                let pt = CGPoint(x: r.minX + r.width * x, y: r.maxY - r.height * y)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            ctx.stroke(p, with: .color(Brand.mint), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for v in [light, firm].compactMap({ $0 }) {
                let pt = CGPoint(x: r.minX + r.width * v, y: r.maxY - r.height * curve.map(v))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(.white))
            }
        }
    }
}
