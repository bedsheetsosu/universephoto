import SwiftUI
import AppKit

struct InspectorPanel: View {
    @EnvironmentObject var s: Studio
    @Environment(\.photoTheme) private var theme
    var simple = false
    @State private var tab = "layers"
    @State private var hoveringLayer: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Studio")).font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(L("INSPECTOR")).font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(theme.secondary)
            }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 13)
            HStack(spacing: 4) {
                panelTab("layers", "square.3.layers.3d", L("Layers"))
                panelTab("brush", "paintbrush.pointed", L("Brush"))
                if !simple {
                    panelTab("adjust", "slider.horizontal.3", L("Adjustments"))
                    panelTab("history", "clock.arrow.circlepath", L("History"))
                }
            }.padding(5).photoSurface(radius: 13).padding(.horizontal, 14).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    colors
                    if tab == "layers" { layerPanel }
                    if tab == "brush" { brushPanel }
                    if tab == "adjust" { adjustments }
                    if tab == "history" { history }
                }.padding(.horizontal, 13).padding(.bottom, 18)
            }.scrollIndicators(.hidden)
        }.foregroundStyle(theme.text)
    }

    private func panelTab(_ id: String, _ symbol: String, _ label: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.18)) { tab = id } } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                Text(label).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }.foregroundStyle(tab == id ? theme.accent : theme.secondary)
                .frame(maxWidth: .infinity).frame(height: 43)
                .background(tab == id ? theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).help(label)
    }
    private func heading(_ title: String, _ detail: String = "", symbol: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent) }
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            if !detail.isEmpty { Text(detail).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary) }
        }
    }
    private var colors: some View {
        VStack(alignment: .leading, spacing: 13) {
            heading(L("Colors"), "sRGB", symbol: "circle.lefthalf.filled")
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12).fill(s.color.color.gradient)
                    .frame(width: 45, height: 45)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.outline))
                    .overlay { ColorPicker(L("Foreground color"), selection: Binding(get: { s.color.color }, set: { s.color = CodableColor($0) }), supportsOpacity: true).labelsHidden().opacity(0.025).scaleEffect(2).frame(width: 35, height: 35).clipped() }
                    .help(L("Choose foreground color"))
                VStack(alignment: .leading, spacing: 5) {
                    Text(hex(s.color)).font(.system(size: 13, weight: .medium, design: .monospaced))
                    HStack(spacing: 4) {
                        Text(L("Foreground"))
                        Text(LF("· %d%%", Int(s.color.alpha * 100)))
                    }.font(.system(size: 10)).foregroundStyle(theme.secondary)
                }
                Spacer(minLength: 0)
                Button { s.tool = .eyedropper } label: { Image(systemName: "eyedropper").font(.system(size: 12)) }
                    .buttonStyle(PhotoButtonStyle()).help(L("Eyedropper · I"))
            }
            HStack(spacing: 7) {
                ForEach(Array(Studio.palette.enumerated()), id: \.offset) { _, color in
                    Button { s.color = color } label: {
                        Circle().fill(color.color).frame(maxWidth: .infinity).frame(height: 23)
                            .overlay(Circle().strokeBorder(s.color == color ? theme.accent : theme.outline, lineWidth: s.color == color ? 2 : 1))
                            .overlay { if s.color == color { Circle().fill(color == .white ? Color.black.opacity(0.7) : Color.white).frame(width: 4, height: 4) } }
                    }.buttonStyle(.plain).help(hex(color))
                }
            }
            HStack(spacing: 5) {
                component("R", s.color.red); component("G", s.color.green); component("B", s.color.blue)
                Spacer(minLength: 0)
                ColorPicker(L("Secondary"), selection: Binding(get: { s.secondaryColor.color }, set: { s.secondaryColor = CodableColor($0) })).labelsHidden().help(L("Secondary gradient color"))
            }
        }.photoCard()
    }
    private func component(_ title: String, _ value: Double) -> some View {
        HStack(spacing: 4) { Text(title).foregroundStyle(theme.secondary); Text("\(Int(value * 255))").monospacedDigit() }
            .font(.system(size: 9)).padding(.horizontal, 7).padding(.vertical, 5).background(theme.deep.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
    }
    private func hex(_ c: CodableColor) -> String { String(format: "#%02X%02X%02X", Int(max(0, min(1, c.red)) * 255), Int(max(0, min(1, c.green)) * 255), Int(max(0, min(1, c.blue)) * 255)) }

    private var layerPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 12) {
                heading(L("Layers"), "\(s.layers.count)", symbol: "square.3.layers.3d")
                if let layer = s.activeLayer {
                    HStack {
                        Text(L("Blend")).font(.system(size: 10)).foregroundStyle(theme.secondary)
                        Spacer()
                        Picker(L("Blend mode"), selection: Binding(get: { layer.blend }, set: { value in s.mutateLayer("Blend mode") { $0.blend = value } })) {
                            ForEach(LayerBlend.allCases, id: \.self) { Text(L($0.rawValue.capitalized)).tag($0) }
                        }.labelsHidden().font(.system(size: 10)).frame(maxWidth: 150).controlSize(.small)
                    }
                    valueSlider(L("Opacity"), value: layer.opacity, range: 0...1, suffix: "%", multiplier: 100) { v in s.mutateLayer("Opacity") { $0.opacity = v } }
                }
                VStack(spacing: 5) {
                    ForEach(Array(s.layers.enumerated().reversed()), id: \.element.id) { idx, layer in layerRow(layer, index: idx) }
                }
                HStack(spacing: 5) {
                    mini("plus", L("New layer")) { s.newLayer() }
                    mini("square.on.square", L("Duplicate")) { s.duplicateLayer() }
                    mini("arrow.up", L("Raise")) { s.reorderLayer(1) }.disabled(s.selectedLayer == s.layers.count - 1)
                    mini("arrow.down", L("Lower")) { s.reorderLayer(-1) }.disabled(s.selectedLayer == 0)
                    Spacer(minLength: 0)
                    mini("trash", L("Delete")) { s.deleteLayer() }.disabled(s.layers.count == 1 || s.activeLayer?.locked == true)
                }
            }.photoCard()
            if let layer = s.activeLayer {
                VStack(alignment: .leading, spacing: 13) {
                    heading(L("Properties"), symbol: "slider.horizontal.2.square")
                    TextField(L("Layer name"), text: Binding(get: { layer.name }, set: { name in s.mutateLayer("Rename layer") { $0.name = name } }))
                        .textFieldStyle(.plain).font(.system(size: 11)).padding(9).background(theme.deep.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    if !simple {
                        HStack(spacing: 9) {
                            numberField("X", layer.transform.x) { n in s.mutateLayer("Position") { $0.transform.x = n } }
                            numberField("Y", layer.transform.y) { n in s.mutateLayer("Position") { $0.transform.y = n } }
                        }
                        valueSlider(L("Scale"), value: layer.transform.scale, range: 0.1...3, suffix: "%", multiplier: 100) { v in s.mutateLayer("Scale layer") { $0.transform.scale = v } }
                        valueSlider(L("Rotation"), value: layer.transform.rotation, range: -180...180, suffix: "°") { v in s.mutateLayer("Rotate layer") { $0.transform.rotation = v } }
                        Divider().overlay(theme.outline)
                        HStack {
                            Button { s.addMask() } label: { Label(L("Mask"), systemImage: "circle.lefthalf.filled") }.disabled(layer.mask != nil)
                            if layer.mask != nil { Button { s.removeMask() } label: { Image(systemName: "trash") }.help(L("Remove mask")).accessibilityLabel(L("Remove mask")) }
                        }.buttonStyle(PhotoButtonStyle())
                        if s.maskEditing { Text(L("Mask active: black hides, white reveals.")).font(.system(size: 10)).foregroundStyle(theme.accent).lineSpacing(3) }
                        Button { s.mergeDown() } label: { Label(L("Merge down"), systemImage: "square.3.layers.3d.down.right").frame(maxWidth: .infinity) }
                            .buttonStyle(PhotoButtonStyle()).disabled(s.selectedLayer == 0 || layer.locked)
                        Button { s.importPanel() } label: { Label(L("Import image as layer"), systemImage: "photo.badge.plus").frame(maxWidth: .infinity) }.buttonStyle(PhotoButtonStyle())
                    }
                }.photoCard()
            }
        }
    }
    private func layerRow(_ layer: ArtLayer, index: Int) -> some View {
        let selected = index == s.selectedLayer
        return HStack(spacing: 8) {
            Button { s.selectedLayer = index; s.mutateLayer("Layer visibility") { $0.visible.toggle() } } label: {
                Image(systemName: layer.visible ? "eye" : "eye.slash").font(.system(size: 10)).foregroundStyle(layer.visible ? theme.secondary : theme.secondary.opacity(0.45))
            }.buttonStyle(.plain).frame(width: 15).help(L("Visibility")).accessibilityLabel(L("Toggle layer visibility"))
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(selected ? theme.accentSoft : theme.deep)
                Image(systemName: layer.imageData == nil ? "scribble.variable" : "photo").font(.system(size: 18, weight: .light)).foregroundStyle(selected ? theme.accent : theme.secondary)
            }.frame(width: 36, height: 37).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.outline))
            VStack(alignment: .leading, spacing: 4) {
                Text(layer.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(layer.mask != nil ? L("Layer + mask") : layer.imageData != nil ? LF("Raster · %d%%", Int(layer.opacity * 100)) : LC("%d stroke", "%d strokes", layer.strokes.count))
                    .font(.system(size: 9)).foregroundStyle(theme.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 7) {
                Button { s.selectedLayer = index; s.mutateLayer("Layer lock") { $0.locked.toggle() } } label: {
                    Image(systemName: layer.locked ? "lock.fill" : "lock.open").font(.system(size: 9)).foregroundStyle(layer.locked ? theme.accent : theme.secondary.opacity(hoveringLayer == layer.id || selected ? 0.8 : 0.3))
                }.buttonStyle(.plain).help(L("Lock layer")).accessibilityLabel(L("Toggle layer lock"))
                if layer.mask != nil {
                    Button { let wasEditing = s.maskEditing && index == s.selectedLayer; s.selectedLayer = index; s.maskEditing = !wasEditing } label: {
                        Image(systemName: s.maskEditing && selected ? "circle.lefthalf.filled" : "circle.dotted").font(.system(size: 10)).foregroundStyle(s.maskEditing && selected ? theme.accent : theme.secondary)
                    }.buttonStyle(.plain).help(L("Edit mask")).accessibilityLabel(L("Edit mask"))
                }
            }
        }.padding(.horizontal, 8).padding(.vertical, 8)
            .background(selected ? theme.accentSoft : hoveringLayer == layer.id ? theme.deep.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? theme.accent.opacity(0.4) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 10)).onTapGesture { s.selectedLayer = index; s.maskEditing = false }
            .onHover { hoveringLayer = $0 ? layer.id : nil }
    }

    private var brushPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 14) {
                heading(L("Brush studio"), symbol: "paintbrush.pointed")
                Canvas { context, size in
                    var p = Path(); p.move(to: CGPoint(x: 14, y: size.height * 0.6))
                    p.addCurve(to: CGPoint(x: size.width - 14, y: size.height * 0.4), control1: CGPoint(x: size.width * 0.3, y: -10), control2: CGPoint(x: size.width * 0.65, y: size.height + 10))
                    context.stroke(p, with: .color(s.color.color.opacity(s.brushOpacity)), style: StrokeStyle(lineWidth: min(28, s.brushSize), lineCap: .round))
                }.accessibilityLabel(L("Brush preview")).frame(height: 70).background(theme.deep, in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(theme.outline))
                valueSlider(L("Size"), value: s.brushSize, range: 1...300, suffix: " px") { s.brushSize = $0 }
                valueSlider(L("Opacity"), value: s.brushOpacity, range: 0.05...1, suffix: "%", multiplier: 100) { s.brushOpacity = $0 }
                valueSlider(L("Stabilization"), value: s.smoothing, range: 0...0.9, suffix: "%", multiplier: 100) { s.smoothing = $0 }
                Toggle(L("Pressure controls size"), isOn: $s.pressureEnabled).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                Text(L("Tilt and barrel rotation shape the tip when provided by the input device.")).font(.system(size: 10)).foregroundStyle(theme.secondary).lineSpacing(3)
            }.photoCard()
            VStack(alignment: .leading, spacing: 12) {
                heading(L("Presets"), "\(s.presets.count)", symbol: "square.stack")
                ForEach(s.presets) { preset in
                    Button { s.brushSize = preset.size; s.brushOpacity = preset.opacity; s.smoothing = preset.smoothing; s.tool = .brush } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.size > 20 ? "highlighter" : "paintbrush.pointed").font(.system(size: 15)).foregroundStyle(theme.accent).frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) { Text(preset.name).font(.system(size: 11, weight: .medium)); Text(LF("%d px · %d%%", Int(preset.size), Int(preset.opacity * 100))).font(.system(size: 9)).foregroundStyle(theme.secondary) }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(theme.secondary)
                        }.padding(9).background(theme.deep.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                Button { s.presets.append(BrushPreset(name: LF("Custom %d", s.presets.count + 1), size: s.brushSize, opacity: s.brushOpacity, smoothing: s.smoothing)) } label: { Label(L("Save preset"), systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(PhotoButtonStyle())
                HStack { Button(L("Import")) { importPresets() }; Button(L("Export")) { exportPresets() } }.buttonStyle(PhotoButtonStyle())
            }.photoCard()
        }
    }
    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 15) {
                heading(L("Adjustments"), symbol: "slider.horizontal.3")
                HStack(spacing: 5) { Image(systemName: "checkmark.shield"); Text(L("Nondestructive · active layer")) }.font(.system(size: 9)).foregroundStyle(theme.accent).padding(7).frame(maxWidth: .infinity, alignment: .leading).background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 7))
                if let a = s.activeLayer?.adjustment {
                    valueSlider(L("Brightness"), value: a.brightness, range: -1...1, suffix: "", multiplier: 100) { v in s.mutateLayer("Brightness") { $0.adjustment.brightness = v } }
                    valueSlider(L("Contrast"), value: a.contrast, range: 0...3, suffix: "", multiplier: 100) { v in s.mutateLayer("Contrast") { $0.adjustment.contrast = v } }
                    valueSlider(L("Saturation"), value: a.saturation, range: 0...2, suffix: "%", multiplier: 100) { v in s.mutateLayer("Saturation") { $0.adjustment.saturation = v } }
                    valueSlider(L("Exposure"), value: a.exposure, range: -4...4, suffix: " EV") { v in s.mutateLayer("Exposure") { $0.adjustment.exposure = v } }
                    valueSlider(L("Gaussian blur"), value: a.blur, range: 0...40, suffix: " px") { v in s.mutateLayer("Gaussian blur") { $0.adjustment.blur = v } }
                    Toggle(L("Invert"), isOn: Binding(get: { a.inverted }, set: { v in s.mutateLayer("Invert") { $0.adjustment.inverted = v } })).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                    HStack {
                        Button { s.mutateLayer("Monochrome") { $0.adjustment.saturation = 0 } } label: { Label(L("Monochrome"), systemImage: "circle.lefthalf.filled") }
                        Button { s.mutateLayer("Reset adjustments") { $0.adjustment = LayerAdjustment() } } label: { Image(systemName: "arrow.counterclockwise") }.help(L("Reset adjustments")).accessibilityLabel(L("Reset adjustments"))
                    }.buttonStyle(PhotoButtonStyle())
                }
            }.photoCard()
            Text(L("Original strokes and image data are preserved. All values are saved in the project.")).font(.system(size: 10)).foregroundStyle(theme.secondary).lineSpacing(4).padding(.horizontal, 6)
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 13) {
            heading(L("History"), "\(s.undoStack.count) / 60", symbol: "clock.arrow.circlepath")
            HStack {
                Button { s.undo() } label: { Label(L("Undo"), systemImage: "arrow.uturn.backward") }.disabled(s.undoStack.isEmpty)
                Button { s.redo() } label: { Label(L("Redo"), systemImage: "arrow.uturn.forward") }.disabled(s.redoStack.isEmpty)
            }.buttonStyle(PhotoButtonStyle())
            if s.undoStack.isEmpty { Text(L("Your next editing steps will appear here.")).font(.system(size: 11)).foregroundStyle(theme.secondary).lineSpacing(4).padding(.vertical, 10) }
            ForEach(Array(s.undoStack.enumerated().reversed()), id: \.offset) { idx, item in
                HStack(spacing: 10) {
                    Image(systemName: idx == s.undoStack.count - 1 ? "circle.inset.filled" : "circle").font(.system(size: 10)).foregroundStyle(idx == s.undoStack.count - 1 ? theme.accent : theme.secondary.opacity(0.5))
                    Text(L(item.label)).font(.system(size: 11)).foregroundStyle(idx == s.undoStack.count - 1 ? theme.text : theme.secondary)
                    Spacer()
                    Text(String(format: "%02d", idx + 1)).font(.system(size: 9, design: .monospaced)).foregroundStyle(theme.secondary.opacity(0.7))
                }.padding(.vertical, 6)
            }
        }.photoCard()
    }
    private func mini(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)).frame(width: 28, height: 28).background(theme.text.opacity(0.055), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(PhotoPress()).help(help).accessibilityLabel(help)
    }
    private func numberField(_ label: String, _ value: Double, _ set: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        HStack(spacing: 7) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.secondary)
            TextField("", value: Binding(get: { value }, set: set), format: .number.precision(.fractionLength(0...1))).textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
        }.padding(8).background(theme.deep.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
    }
    private func valueSlider(_ title: String, value: Double, range: ClosedRange<Double>, suffix: String, multiplier: Double = 1, set: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.system(size: 10))
                Spacer()
                Text("\(Int(value * multiplier))\(suffix)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(theme.secondary)
            }
            Slider(value: Binding(get: { value }, set: set), in: range).controlSize(.mini).tint(theme.accent).accessibilityLabel(title)
        }
    }
    private func importPresets() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.title = L("Import brush presets"); p.prompt = L("Import")
        if p.runModal() == .OK, let url = p.url {
            do {
                let presets = try JSONDecoder().decode([BrushPreset].self, from: Data(contentsOf: url))
                guard presets.count <= 100, presets.allSatisfy({ $0.size.isFinite && (1...300).contains($0.size) && (0...1).contains($0.opacity) && (0...0.9).contains($0.smoothing) }) else { throw StudioError.message("Invalid brush presets.") }
                s.presets = presets
            } catch { s.report(error) }
        }
    }
    private func exportPresets() {
        let p = NSSavePanel(); p.allowedContentTypes = [.json]; p.nameFieldStringValue = L("UniversePhoto-Brushes") + ".json"; p.title = L("Export brush presets"); p.prompt = L("Export")
        if p.runModal() == .OK, let url = p.url { do { try JSONEncoder.pretty.encode(s.presets).write(to: url, options: .atomic) } catch { s.report(error) } }
    }
}
