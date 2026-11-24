import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Workspace: View {
    @EnvironmentObject var s:Studio
    @AppStorage("workspace") private var workspace = "Photo"
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("photoAccent") private var accent = "mint"
    @AppStorage("photoFlow") private var flow = false
    @AppStorage("photoFlowSpeed") private var flowSpeed = 1.0
    @ObservedObject private var localization = Localization.shared
    @AppStorage("showInspector") private var showInspector = true
    @AppStorage("showNavigator") private var showNavigator = false
    @AppStorage("showHistogram") private var showHistogram = false
    @AppStorage("motionPath") private var motionPath = false
    @AppStorage("showTimeline") private var showTimeline = false
    @AppStorage("showRulers") private var rulers = true
    @AppStorage("showGrid") private var grid = false
    @AppStorage("snap") private var snap = false
    @State private var inspectorWidth = 276.0
    @State private var timelineHeight = 176.0
    @State private var showPreferences = false
    @State private var exportSheet = false
    @State private var textOptions = false
    @State private var recoverySheet = false
    @State private var exportType = "png"
    @AppStorage("exportQuality") private var exportQuality = 0.9
    @AppStorage("exportScale") private var exportScale = 1.0
    @AppStorage("exportGIFLoop") private var exportGIFLoop = true
    @State private var exportPlayRange = false
    @State private var exportEstimate = ""
    @State private var query = ""
    @State private var newWidth = 1200
    @AppStorage("documentBackground") private var newBackground = "white"
    @State private var newHeight = 800
    @Environment(\.colorScheme) private var systemScheme
    @Namespace private var workspaceMotion
    @Namespace private var documentMotion
    private var theme:PhotoTheme { PhotoTheme(isDark:appearance == "dark" || (appearance == "system" && systemScheme == .dark),accent:PhotoTheme.accent(accent)) }
    private var tint:Color { theme.accent }
    var body:some View {
        VStack(spacing:0) {
            if !s.focusMode { topbar.transition(.move(edge:.top).combined(with:.opacity)) }
            HStack(alignment:.top,spacing:10) {
                if !s.focusMode { toolPalette.transition(.move(edge:.leading).combined(with:.opacity)) }
                VStack(spacing:0) {
                    if !s.focusMode { tabs }
                    contextbar
                    ArtworkCanvas(studio:s,grid:grid,rulers:rulers,snap:snap,background:NSColor(theme.canvas),motionPath:motionPath && (workspace == "Animate" || s.frames.count > 1)).clipped()
                        .overlay(alignment:.bottomLeading) { canvasBadge.padding(14).allowsHitTesting(false) }
                        .overlay(alignment:.topLeading) { if s.focusMode { FocusPill().environmentObject(s).padding(12).transition(.scale(scale:0.9,anchor:.topLeading).combined(with:.opacity)) } }
                        .overlay(alignment:.bottomTrailing) { VStack(alignment:.trailing,spacing:10) { if showHistogram { HistogramPanel().environmentObject(s).transition(.scale(scale:0.9,anchor:.bottomTrailing).combined(with:.opacity)) }; if showNavigator { NavigatorPanel().environmentObject(s).transition(.scale(scale:0.9,anchor:.bottomTrailing).combined(with:.opacity)) } }.padding(14) }
                    if showTimeline || workspace == "Animate" { resizeTimeline;TimelinePanel().environmentObject(s).frame(height:timelineHeight).transition(.move(edge:.bottom).combined(with:.opacity)) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity).photoSurface(radius:20,elevated:true)
                if showInspector && !s.focusMode { HStack(spacing:0) { resizeInspector;InspectorPanel(simple:workspace == "Simple").environmentObject(s).frame(width:inspectorWidth) }.photoChrome(radius:20).transition(.move(edge:.trailing).combined(with:.opacity)) }
            }.padding(.horizontal,s.focusMode ? 6 : 12).padding(.bottom,s.focusMode ? 6 : 8).padding(.top,s.focusMode ? 30 : 0)
            if !s.focusMode { statusbar }
        }
        .background(PhotoAmbient())
        .foregroundStyle(theme.text)
        .environment(\.photoTheme,theme)
        .environment(\.locale,Locale(identifier:localization.language)).tint(tint).accentColor(tint).preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .animation(PhotoMotion.panel,value:showInspector)
        .animation(PhotoMotion.panel,value:showNavigator)
        .animation(PhotoMotion.panel,value:showHistogram)
        .animation(PhotoMotion.panel,value:s.focusMode)
        .modifier(FocusWindowSync(s:s))
        .animation(PhotoMotion.panel,value:workspace)
        .animation(PhotoMotion.panel,value:showTimeline)
        .onChange(of:localization.language) { _,_ in Task { @MainActor in Localization.shared.refreshNativeMenus() } }
        .sheet(isPresented:$showPreferences) { preferences }
        .sheet(isPresented:$s.showNewDocument) { newDocument }
        .sheet(isPresented:$s.guideDialog) { NewGuideDialog().environmentObject(s).environment(\.photoTheme,theme) }
        .sheet(item:$s.selectionDialog) { kind in SelectionModifyDialog(kind:kind).environmentObject(s).environment(\.photoTheme,theme) }
        .onChange(of:s.textEditKey) { if s.tool == .text { s.syncEditedText() } }
        .onChange(of:s.tool) { if s.tool != .text { s.editingText = nil }; if s.tool != .pen { s.editingPath = nil; s.penPath = nil } }
        .onChange(of:s.penPath) { s.syncEditedPath() }
        .onChange(of:s.selection == nil) { if s.selection == nil { s.applySelectionTransform() } }
        .onChange(of:s.textEditKey) { if s.editingPath != nil { s.commitEditedPathStyle() } }
        .sheet(isPresented:$s.showShortcuts) { ShortcutsSheet().environmentObject(s).environment(\.photoTheme,theme) }
        .sheet(isPresented:$s.strokeSelectionDialog) { StrokeSelectionDialog().environmentObject(s).environment(\.photoTheme,theme) }
        .sheet(item:$s.imageDialog) { kind in ImageSizeDialog(kind:kind).environmentObject(s).environment(\.photoTheme,theme) }
        .sheet(isPresented:$s.replaceColorDialog) { ReplaceColorDialog().environmentObject(s).environment(\.photoTheme,theme) }
        .sheet(isPresented:$s.commandSearch) { commandPalette }
        .sheet(isPresented:$exportSheet) { exportOptions }
        .sheet(isPresented:$recoverySheet) { recovery }
        .alert(L("UniverseStudio"),isPresented:Binding(get:{ s.message != nil },set:{ if !$0 { s.message = nil } })) { Button(L("OK")) { s.message = nil } } message: { Text(s.displayedMessage) }
        .overlay { if s.busy { ZStack { Color.black.opacity(0.15);ProgressView(L("Exporting…")).padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)) } } }
    }
    private var topbar:some View {
        HStack(spacing:10) {
            HStack(spacing:10) { Button { s.showStartScreen() } label: { PhotoMark() }.buttonStyle(PhotoPress()).help(L("Start screen") + " · ⇧⌘H");VStack(alignment:.leading,spacing:2) { Text("UniverseStudio").font(.system(size:16,weight:.bold,design:.rounded));Text(L("PHOTO")).lineLimit(1).font(.system(size:7.5,weight:.semibold)).tracking(1.6).foregroundStyle(theme.secondary) };iconButton("arrow.up.left.and.arrow.down.right",L("Focus mode") + " · ⌥⌘F") { withAnimation(PhotoMotion.panel) { s.focusMode = true } } }.padding(.leading,68)
            Spacer(minLength:6)
            HStack(spacing:3) { ForEach(["Simple","Photo","Animate"],id:\.self) { mode in
                let selected = workspace == mode
                Button { withAnimation(PhotoMotion.select) { workspace = mode } } label: { HStack(spacing:5) { Image(systemName:mode == "Simple" ? "pencil.tip" : mode == "Photo" ? "camera.aperture" : "play.rectangle").font(.system(size:10,weight:.semibold));Text(L(mode)).font(.system(size:11,weight:.semibold,design:.rounded)) }.frame(width:88,height:31).foregroundStyle(selected ? theme.onAccent : theme.secondary).background { if selected { Capsule().fill(theme.accentGradient).matchedGeometryEffect(id:"workspace",in:workspaceMotion).shadow(color:tint.opacity(0.18),radius:6,y:2) } }.contentShape(Capsule()) }.buttonStyle(PhotoPress()).accessibilityAddTraits(selected ? .isSelected : [])
            } }.padding(4).background(theme.deep.opacity(0.5),in:Capsule()).overlay(Capsule().strokeBorder(theme.outline,lineWidth:0.75))
            Spacer(minLength:6)
            iconButton("magnifyingglass",L("Command search · ⇧⌘P")) { s.commandSearch = true }
            iconButton("sidebar.right",L("Inspector")) { showInspector.toggle() }
            iconButton("slider.horizontal.3",L("Appearance & settings")) { showPreferences = true }
            Button { exportSheet = true } label: { Label(L("Export"),systemImage:"square.and.arrow.up") }.buttonStyle(PhotoButtonStyle(prominent:true))
        }.padding(.horizontal,17).frame(height:68)
    }
    private var tabs:some View {
        HStack(spacing:6) {
            ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:6) { ForEach(s.tabs) { tab in
                let selected = tab.id == s.tabID
                HStack(spacing:8) {
                    Image(systemName:"square.stack").font(.system(size:10)).foregroundStyle(selected ? tint : theme.secondary)
                    Button { s.switchTab(tab.id) } label: { HStack(spacing:7) { Text(tab.document.title).lineLimit(1);if tab.dirty { Circle().fill(tint).frame(width:4,height:4) } } }.buttonStyle(.plain)
                    Button { s.closeTab(tab.id) } label: { Image(systemName:"xmark").font(.system(size:7,weight:.semibold)).frame(width:14,height:18) }.buttonStyle(HoverButtonStyle()).accessibilityLabel(L("Close document")).foregroundStyle(theme.secondary)
                }.font(.system(size:11,weight:selected ? .semibold : .regular)).padding(.horizontal,12).frame(height:31).background { if selected { RoundedRectangle(cornerRadius:10,style:.continuous).fill(theme.card).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(theme.edge.opacity(0.5),lineWidth:0.7)).matchedGeometryEffect(id:"document",in:documentMotion) } }
            } } }
            iconButton("plus",L("New document")) { s.showNewDocument = true }
            iconButton("folder",L("Open")) { s.openPanel() }
            iconButton(s.dirty ? "square.and.arrow.down.fill" : "checkmark.circle",L("Save · ⌘S")) { s.savePanel() }
        }.padding(.horizontal,10).frame(height:45)
    }
    private var contextbar:some View {
        GeometryReader { g in HStack(spacing:11) {
            HStack(spacing:7) { Image(systemName:s.tool.symbol).foregroundStyle(tint);Text(L(s.tool.english)).fontWeight(.semibold) }.frame(minWidth:70,alignment:.leading)
            Rectangle().fill(theme.outline).frame(width:1,height:17)
            if s.tool == .text { TextField(L("Text"),text:$s.textContent).textFieldStyle(.plain).padding(6).background(theme.card,in:RoundedRectangle(cornerRadius:6)).frame(width:120);Button { textOptions.toggle() } label: { Image(systemName:"text.alignleft") }.buttonStyle(PhotoPress()).help(L("Text options")).accessibilityLabel(L("Text options")).popover(isPresented:$textOptions) { TextOptionsPopover().environmentObject(s).environment(\.photoTheme,theme) } }
            if s.tool == .text && g.size.width > 700 {
                Picker(L("Font"),selection:$s.fontFamily) { ForEach(NSFontManager.shared.availableFontFamilies,id:\.self) { Text($0).tag($0) } }.labelsHidden().frame(width:130).controlSize(.mini)
                Toggle(L("Bold"),isOn:$s.textBold).toggleStyle(.checkbox).controlSize(.mini)
            }
            if s.transformMode { Text(L("Corners scale · inside moves · outside rotates (⇧ 15°) · ↩ done")).foregroundStyle(tint).lineLimit(1) }
            if g.size.width > 575 && [.brush,.eraser,.rectangle,.ellipse,.line,.pen,.text,.clone,.heal,.smudge,.liquify,.dodge,.focus].contains(s.tool) { Text(L("Size")).foregroundStyle(theme.secondary);Slider(value:$s.brushSize,in:1...200).frame(width:65).controlSize(.mini).accessibilityLabel(L("Brush size"));Text("\(Int(s.brushSize))").monospacedDigit().frame(width:24,alignment:.leading) }
            if g.size.width > 460 && ![.pan,.move,.crop,.rectangleSelection,.ellipseSelection,.lasso,.wand,.eyedropper,.clone,.heal,.smudge,.liquify,.dodge,.focus].contains(s.tool) { Text(L("Opacity")).foregroundStyle(theme.secondary);Slider(value:$s.brushOpacity,in:0.05...1).frame(width:55).controlSize(.mini).accessibilityLabel(L("Brush opacity"));Text("\(Int(s.brushOpacity*100))%").monospacedDigit().frame(width:29) }
            if s.tool == .eyedropper {
                Text(L("Sample")).foregroundStyle(theme.secondary)
                Picker(L("Sample"),selection:$s.eyedropperSize) { ForEach(Studio.sampleSizes,id:\.self) { n in Text(n == 1 ? L("Point") : "\(n)×\(n)").tag(n) } }.labelsHidden().frame(width:84).controlSize(.mini)
                Toggle(L("All layers"),isOn:$s.eyedropperAllLayers).toggleStyle(.checkbox).controlSize(.mini)
            }
            if [.clone,.heal].contains(s.tool) {
                Toggle(L("Aligned"),isOn:$s.cloneAligned).toggleStyle(.checkbox).controlSize(.mini)
                Toggle(L("All layers"),isOn:$s.sampleMerged).toggleStyle(.checkbox).controlSize(.mini)
                if g.size.width > 760 { Text(s.cloneSource == nil ? L("⌥-click sets the source") : L("Source set · ⌥-click to change")).foregroundStyle(theme.secondary) }
            }
            if s.tool == .brush { Picker(L("Brush tip"),selection:$s.brushTip) { ForEach(BrushTip.allCases,id:\.self) { Image(systemName:$0.symbol).help(L($0.title)).accessibilityLabel(L($0.title)).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width:190).controlSize(.mini).help(L("Brush tip")) }
            if s.tool == .rectangle {
                Picker(L("Shape"),selection:$s.shapeStyle) { ForEach(ShapeStyle.allCases,id:\.self) { Image(systemName:$0.symbol).help(L($0.title)).accessibilityLabel(L($0.title)).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width:150).controlSize(.mini)
                if let r = s.shapeStyle.parameter { Text(L(s.shapeStyle.parameterTitle)).foregroundStyle(theme.secondary);Slider(value:Binding(get:{ min(r.upperBound,max(r.lowerBound,s.shapeParameter)) },set:{ s.shapeParameter = $0.rounded() }),in:r).frame(width:60).controlSize(.mini).accessibilityLabel(L(s.shapeStyle.parameterTitle));Text("\(Int(min(r.upperBound,max(r.lowerBound,s.shapeParameter))))").monospacedDigit().frame(width:26,alignment:.leading) }
            }
            if [.rectangle,.ellipse].contains(s.tool) { Toggle(L("Filled"),isOn:$s.shapeFill).toggleStyle(.checkbox).controlSize(.mini) }
            if s.tool == .line { Toggle(L("Arrow"),isOn:$s.lineArrow).toggleStyle(.checkbox).controlSize(.mini) }
            if s.tool == .brush && g.size.width > 900 {
                Text(L("Mode")).foregroundStyle(theme.secondary)
                Picker(L("Mode"),selection:$s.brushBlend) { ForEach(LayerBlend.allCases,id:\.self) { Text(L($0.title)).tag($0) } }.labelsHidden().frame(width:118).controlSize(.mini)
            }
            if s.tool == .gradient { GradientButton().environmentObject(s) }
            if s.tool == .gradient { Picker(L("Gradient"),selection:$s.gradientStyle) { ForEach(GradientStyle.allCases,id:\.self) { Label(L($0.title),systemImage:$0.symbol).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width:150).controlSize(.mini).help(L("Gradient")) }
            if s.tool == .dodge { Picker(L("Mode"),selection:$s.toneMode) { ForEach(Studio.ToneMode.allCases) { m in Image(systemName:m.symbol).help(L(m.title)).accessibilityLabel(L(m.title)).tag(m) } }.pickerStyle(.segmented).labelsHidden().frame(width:150).controlSize(.mini) }
            if s.tool == .focus { Picker(L("Mode"),selection:$s.sharpenMode) { Text(L("Blur")).tag(false);Text(L("Sharpen")).tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width:130).controlSize(.mini) }
            if s.tool == .liquify { Picker(L("Mode"),selection:$s.liquifyMode) { ForEach(LiquifyMode.allCases,id:\.self) { Image(systemName:$0.symbol).help(L($0.title)).accessibilityLabel(L($0.title)).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width:170).controlSize(.mini) }
            if s.transformingSelection { if let r = s.selectionFrame { Text("\(Int(r.width)) × \(Int(r.height)) px").monospacedDigit().foregroundStyle(theme.secondary) };Text("\(Int(s.selectionAngle.rounded()))°").monospacedDigit().foregroundStyle(theme.secondary).help(L("Drag just outside the frame to rotate · ⇧ in 15° steps"));Button(L("Apply")) { s.applySelectionTransform() }.buttonStyle(PhotoButtonStyle(prominent:true));Button(L("Cancel")) { s.cancelSelectionTransform() } }
            if s.distorting { Text(L("Drag the corners · ↩ applies · Esc cancels")).foregroundStyle(theme.secondary);Button(L("Apply")) { s.applyDistort() }.buttonStyle(PhotoButtonStyle(prominent:true));Button(L("Cancel")) { s.cancelDistort() } }
            if s.quickMaskActive { Button(L("Leave quick mask")) { s.toggleQuickMask() }.buttonStyle(PhotoButtonStyle(prominent:true)).help("⇧Q") }
            if [.brush,.eraser].contains(s.tool) && g.size.width > 700 {
                Picker(L("Symmetry"),selection:$s.symmetry) { ForEach(Symmetry.allCases) { Image(systemName:$0.symbol).help(L($0.title)).accessibilityLabel(L($0.title)).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width:170).controlSize(.mini).help(L("Symmetry"))
                if s.symmetry == .radial { Stepper("\(s.symmetrySegments)×",value:$s.symmetrySegments,in:2...24).controlSize(.mini).monospacedDigit().accessibilityLabel(L("Segments")) }
                if s.symmetry != .off {
                    iconButton("scope",L(s.settingSymmetryCenter ? "Click the canvas to place the centre" : "Set symmetry centre")) { s.settingSymmetryCenter.toggle() }.foregroundStyle(s.settingSymmetryCenter ? theme.accent : theme.secondary)
                    if s.symmetryCenter != nil { iconButton("arrow.uturn.backward.circle",L("Centre on canvas")) { s.symmetryCenter = nil; s.settingSymmetryCenter = false } }
                }
            }
            if s.tool == .crop {
                Picker(L("Ratio"),selection:$s.cropRatio) { ForEach(Studio.CropRatio.allCases) { Text(L($0.title)).tag($0) } }.labelsHidden().frame(width:96).controlSize(.mini).help(L("Aspect ratio"))
                Button { s.cropPortrait.toggle() } label: { Image(systemName:s.cropPortrait ? "rectangle.portrait" : "rectangle") }.buttonStyle(PhotoPress()).disabled(s.cropRatio == .free || s.cropRatio == .square).help(L("Swap portrait and landscape")).accessibilityLabel(L("Swap portrait and landscape"))
                if let r = s.cropRect { Text("\(Int(r.width)) × \(Int(r.height)) px").monospacedDigit().foregroundStyle(theme.secondary) }
                Button(L("Crop")) { s.applyCrop() }.disabled(s.cropRect == nil || s.isPlaying)
                Button(L("Cancel")) { s.cropRect = nil }.disabled(s.cropRect == nil)
                if g.size.width > 900 { Text(L("Drag a frame · edges and corners resize · ⇧ square · ↩ crops")).foregroundStyle(theme.secondary) }
            }
            if s.tool == .pen {
                let ready = (s.penPath?.nodes.count ?? 0) >= 2
                Button(L("Fill path")) { s.commitPath(fill:true) }.disabled(!ready || !s.canEdit)
                Button(L("Stroke path")) { s.commitPath(fill:false) }.disabled(!ready || !s.canEdit)
                Button(L("Path to selection")) { s.pathToSelection() }.disabled((s.penPath?.nodes.count ?? 0) < 3)
                Button(L(s.editingPath == nil ? "Clear path" : "Done")) { s.penPath = nil; s.editingPath = nil }.disabled(s.penPath == nil)
                if g.size.width > 900 { Text(L("Click a curve to add a point · ⌥ on a handle: move it alone · ⌥-click a point: corner")).foregroundStyle(theme.secondary) }
            }
            if [.smudge,.liquify,.dodge,.focus].contains(s.tool) { Text(L("Strength")).foregroundStyle(theme.secondary);Slider(value:$s.toolStrength,in:0.05...1).frame(width:60).controlSize(.mini).accessibilityLabel(L("Strength"));Text("\(Int(s.toolStrength*100))%").monospacedDigit().frame(width:30) }
            if [.bucket,.wand].contains(s.tool) {
                Text(L("Tolerance")).foregroundStyle(theme.secondary);Slider(value:$s.tolerance,in:0...255).frame(width:70).controlSize(.mini).accessibilityLabel(L("Tolerance"));Text("\(Int(s.tolerance))").monospacedDigit().frame(width:26,alignment:.leading)
                if g.size.width > 640 { Toggle(L("Contiguous"),isOn:$s.contiguous).toggleStyle(.checkbox).controlSize(.mini);Toggle(L("All layers"),isOn:$s.sampleMerged).toggleStyle(.checkbox).controlSize(.mini) }
                if s.tool == .wand && g.size.width > 820 { Text(L("⇧ adds · ⌥ removes")).foregroundStyle(theme.secondary) }
            }
            Spacer(minLength:2)
            iconButton("arrow.uturn.backward",L("Undo")) { s.undo() }.disabled(s.undoStack.isEmpty)
            iconButton("arrow.uturn.forward",L("Redo")) { s.redo() }.disabled(s.redoStack.isEmpty)
            Menu { Button(L("Fit")) { s.fit() };ForEach([0.25,0.5,1,2,4],id:\.self) { z in Button("\(Int(z*100))%") { s.zoom = z } } } label: { Text("\(Int(s.zoom*100))%").monospacedDigit() }.menuStyle(.borderlessButton).frame(width:60)
        }.font(.system(size:10)).padding(.horizontal,14).frame(height:41).background(theme.deep.opacity(0.15)).overlay(alignment:.bottom) { Rectangle().fill(theme.outline).frame(height:0.5) } }.frame(height:41)
    }
    private var toolPalette:some View {
        VStack(spacing:0) {
            ScrollView(showsIndicators:false) { VStack(spacing:4) {
                Text(L("TOOLS")).font(.system(size:7,weight:.semibold)).tracking(1.3).foregroundStyle(theme.secondary).padding(.top,14).padding(.bottom,8)
                ForEach(availableTools) { tool in
                    let selected = s.tool == tool
                    Button { withAnimation(PhotoMotion.select) { s.tool = tool } } label: {
                        Image(systemName:tool.symbol).font(.system(size:16,weight:selected ? .semibold : .regular)).frame(width:38,height:35).foregroundStyle(selected ? theme.onAccent : theme.text.opacity(0.8)).background { if selected { RoundedRectangle(cornerRadius:12,style:.continuous).fill(theme.accentGradient).shadow(color:tint.opacity(0.22),radius:7,y:2) } else { RoundedRectangle(cornerRadius:12,style:.continuous).fill(theme.card.opacity(0.4)) } }
                    }.buttonStyle(HoverButtonStyle()).help(L(tool.english)+" · "+tool.key.uppercased()).accessibilityLabel(L(tool.english)).accessibilityAddTraits(selected ? .isSelected : []).contextMenu { Button(L("Move up")) { moveTool(tool,-1) };Button(L("Move down")) { moveTool(tool,1) } }
                    if tool == .eyedropper || tool == .lasso || tool == .text { Capsule().fill(theme.outline).frame(width:22,height:1).padding(.vertical,7) }
                }
            }.padding(.horizontal,8).padding(.bottom,10) }
            VStack(spacing:6) {
                Rectangle().fill(theme.outline).frame(height:0.7).padding(.bottom,6)
                ColorPicker(L("Foreground"),selection:Binding(get:{s.color.color},set:{s.color = CodableColor($0)}),supportsOpacity:true).labelsHidden().frame(width:31)
                ColorPicker(L("Background"),selection:Binding(get:{s.secondaryColor.color},set:{s.secondaryColor = CodableColor($0)}),supportsOpacity:true).labelsHidden().frame(width:24)
                iconButton("arrow.left.arrow.right",L("Swap colors")) { let old = s.color;s.color = s.secondaryColor;s.secondaryColor = old }
            }.padding(.horizontal,10).padding(.bottom,10)
        }.frame(width:62).frame(maxHeight:.infinity).photoChrome(radius:20)
    }
    @AppStorage("toolOrder") private var toolOrder = ""
    private var availableTools:[Tool] { let all = workspace == "Simple" ? [Tool.brush,.eraser,.eyedropper,.move,.rectangle,.ellipse,.pan] : Tool.allCases;let order = toolOrder.split(separator:",").compactMap { Tool(rawValue:String($0)) };return order.filter { all.contains($0) } + all.filter { !order.contains($0) } }
    private func moveTool(_ tool:Tool,_ offset:Int) { var tools = availableTools;guard let i = tools.firstIndex(of:tool),tools.indices.contains(i+offset) else { return };tools.swapAt(i,i+offset);toolOrder = tools.map(\.rawValue).joined(separator:",") }
    private var resizeInspector:some View { Color.clear.frame(width:5).contentShape(Rectangle()).gesture(DragGesture().onChanged { value in inspectorWidth = min(420,max(232,inspectorWidth-value.translation.width*0.06)) }).onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } } }
    private var resizeTimeline:some View { Rectangle().fill(theme.outline).frame(height:4).gesture(DragGesture().onChanged { value in timelineHeight = min(320,max(130,timelineHeight-value.translation.height*0.06)) }) }
    private var canvasBadge:some View { HStack(spacing:8) { Text("\(s.width) × \(s.height)").monospacedDigit();Text("sRGB · RGBA").foregroundStyle(.secondary);if s.maskEditing { Text(L("MASK")).foregroundStyle(tint) } }.font(.system(size:9,weight:.medium)).padding(.horizontal,10).padding(.vertical,6).photoSurface(radius:12) }
    /// "iPad · USB · 60 fps · 🔋 80 %" from UniversePen's status.
    private func penDeviceLine(_ d:PenDeviceInfo)->some View {
        HStack(spacing:6) {
            Image(systemName:"ipad.landscape").foregroundStyle(tint)
            Text(d.device ?? "iPad").lineLimit(1)
            if let usb = d.usb { Text(usb ? L("USB") : L("Wi-Fi")).foregroundStyle(theme.secondary) }
            if let fps = d.fps, fps > 0 { Text("\(Int(fps)) fps").monospacedDigit().foregroundStyle(theme.secondary) }
            if let b = d.battery { Image(systemName:d.charging == true ? "battery.100.bolt" : b < 0.2 ? "battery.25" : "battery.75").foregroundStyle(b < 0.2 && d.charging != true ? .orange : theme.secondary);Text("\(Int(b*100)) %").monospacedDigit().foregroundStyle(theme.secondary) }
        }.accessibilityElement(children:.combine)
    }
    private var statusbar:some View { HStack(spacing:12) {
        Circle().fill(s.pen.connected ? Color.green : .secondary.opacity(0.4)).frame(width:5,height:5)
        Text(s.pen.status).lineLimit(1)
        if let d = s.pen.device { penDeviceLine(d) }
        Spacer()
        if let p = s.hoverPoint, let c = s.hoverColor, CGRect(x:0,y:0,width:s.width,height:s.height).contains(p) {
            HStack(spacing:6) { Text("X \(Int(p.x))  Y \(Int(p.y))").monospacedDigit();RoundedRectangle(cornerRadius:2).fill(Color(nsColor:NSColor(srgbRed:c.red,green:c.green,blue:c.blue,alpha:1))).frame(width:10,height:10).overlay(RoundedRectangle(cornerRadius:2).strokeBorder(theme.outline));Text(c.alpha < 0.01 ? L("Transparent") : "\(c.hex) · \(Int((c.alpha*100).rounded())) %").monospacedDigit() }.foregroundStyle(theme.secondary)
        } else { Text(L("Scroll: pan · ⌘ scroll: zoom · Esc: deselect")).lineLimit(1).foregroundStyle(theme.secondary.opacity(0.8)) }
        Spacer();Button { grid.toggle() } label: { Image(systemName:"grid").foregroundStyle(grid ? tint : .secondary) }.buttonStyle(.plain).help(L("Grid"))
        Button { snap.toggle() } label: { Image(systemName:"dot.scope").foregroundStyle(snap ? tint : .secondary) }.buttonStyle(.plain).help(L("25 px snapping"))
        Button { rulers.toggle() } label: { Image(systemName:"ruler").foregroundStyle(rulers ? tint : .secondary) }.buttonStyle(.plain).help(L("Rulers")).accessibilityLabel(L("Rulers"))
        Button { showTimeline.toggle() } label: { Image(systemName:"timeline.selection").foregroundStyle(showTimeline || workspace == "Animate" ? tint : .secondary) }.buttonStyle(.plain).help(L("Timeline")).accessibilityLabel(L("Timeline"))
    }.font(.system(size:9)).foregroundStyle(theme.secondary).padding(.horizontal,20).frame(height:28) }
    private var preferences:some View { VStack(alignment:.leading,spacing:18) {
        HStack(spacing:13) { PhotoMark();VStack(alignment:.leading,spacing:4) { Text(L("Your workspace")).font(.system(size:23,weight:.bold,design:.rounded));Text(L("A studio that feels like yours.")).font(.caption).foregroundStyle(theme.secondary) } }
        VStack(alignment:.leading,spacing:12) {
            Text(L("Appearance")).font(.system(size:11,weight:.semibold))
            HStack(spacing:8) { ForEach(["dark","light","system"],id:\.self) { mode in
                Button { withAnimation(PhotoMotion.select) { appearance = mode } } label: { VStack(spacing:8) {
                    ZStack(alignment:.leading) { RoundedRectangle(cornerRadius:7).fill(mode == "light" ? Color(red:0.93,green:0.90,blue:0.95) : Color(red:0x17/255.0,green:0x1A/255.0,blue:0x3F/255.0));RoundedRectangle(cornerRadius:4).fill(mode == "light" ? Color.white : Color.white.opacity(0.12)).frame(width:16).padding(5);Image(systemName:mode == "dark" ? "moon.stars" : mode == "light" ? "sun.max" : "circle.lefthalf.filled").foregroundStyle(mode == "light" ? .black.opacity(0.6) : .white.opacity(0.85)).frame(maxWidth:.infinity) }.frame(height:43)
                    Text(mode == "dark" ? L("Dark") : mode == "light" ? L("Light") : L("System")).font(.system(size:10,weight:.medium))
                }.padding(8).frame(maxWidth:.infinity).background(appearance == mode ? theme.accentSoft : theme.card,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(appearance == mode ? theme.accent.opacity(0.6) : theme.outline,lineWidth:1)) }.buttonStyle(PhotoPress())
            } }
            HStack(spacing:12) { Text(L("Accent")).font(.system(size:10)).foregroundStyle(theme.secondary);Spacer();ForEach(PhotoTheme.accentKeys,id:\.self) { key in Button { withAnimation(PhotoMotion.select) { accent = key } } label: { Circle().fill(PhotoTheme.accent(key)).frame(width:25,height:25).overlay(Circle().strokeBorder(theme.text.opacity(accent == key ? 0.9 : 0.1),lineWidth:accent == key ? 2.5 : 1)).scaleEffect(accent == key ? 1.08 : 1) }.buttonStyle(PhotoPress()).help(L(key.capitalized)).accessibilityLabel(L(key.capitalized)) } }
            Toggle(isOn:$flow.animation(PhotoMotion.panel)) { Text(L("Flowing background")).font(.system(size:11)) }.toggleStyle(.switch).controlSize(.mini).tint(tint)
            if flow { HStack(spacing:10) { Text(L("Speed")).font(.system(size:10)).foregroundStyle(theme.secondary);Slider(value:$flowSpeed,in:0.25...2).controlSize(.mini).accessibilityLabel(L("Speed")) } }
        }.photoCard()
        HStack { Text(L("Language")).font(.system(size:10));Spacer();Picker("",selection:$localization.language) { Text(L("German")).tag("de");Text(L("English")).tag("en") }.labelsHidden().pickerStyle(.segmented).frame(width:180) }.photoCard()
        VStack(alignment:.leading,spacing:10) {
            HStack { Image(systemName:"pencil.tip.crop.circle").foregroundStyle(theme.accent);Text("UniversePen").font(.system(size:12,weight:.semibold,design:.rounded));Spacer();Toggle(L("API"),isOn:Binding(get:{s.apiEnabled},set:{s.apiEnabled = $0;s.pen.enable($0)})).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel(L("Use UniversePen Developer API")) }
            Text(s.pen.status).font(.caption).foregroundStyle(theme.secondary)
            if let d = s.pen.device { penDeviceLine(d).font(.caption) }
            if s.pen.connected {
                HStack(spacing:8) {
                    Button { s.pen.installShortcutBar() } label: { Label(L("iPad bar for UniverseStudio"),systemImage:"ipad.landscape") }.buttonStyle(PhotoButtonStyle())
                    Button { s.pen.removeShortcutBar() } label: { Image(systemName:"trash") }.buttonStyle(PhotoButtonStyle()).help(L("Remove the iPad bar")).accessibilityLabel(L("Remove the iPad bar"))
                }
                Text(L("Adds a shortcut bar to UniversePen that shows on the iPad while UniverseStudio is in front: brush, eraser, eyedropper, clone, undo, redo, brush size, hand, fit.")).font(.system(size:10)).foregroundStyle(theme.secondary)
                if let reply = s.pen.lastReply { Text(reply).font(.system(size:10,weight:.medium)).foregroundStyle(tint) }
            }
            Text(L("Optional local pen input via 127.0.0.1:47800. Enable the API in UniversePen first.")).font(.system(size:10)).foregroundStyle(theme.secondary)
        }.photoCard()
        HStack { Button(L("Recovery")) { showPreferences = false;recoverySheet = true }.buttonStyle(PhotoButtonStyle());Spacer();Button(L("Done")) { showPreferences = false }.buttonStyle(PhotoButtonStyle(prominent:true)).keyboardShortcut(.defaultAction) }
    }.padding(26).frame(width:480).background(PhotoAmbient()).environment(\.photoTheme,theme) }
    private var newDocument:some View { VStack(alignment:.leading,spacing:18) { Text(L("New document")).font(.system(size:23,weight:.bold,design:.rounded));HStack { Text(L("Width"));TextField("px",value:$newWidth,format:.number).accessibilityLabel(L("Width"));Text(L("Height"));TextField("px",value:$newHeight,format:.number).accessibilityLabel(L("Height")) }.textFieldStyle(.roundedBorder);Picker(L("Background"),selection:$newBackground) { Text(L("White")).tag("white");Text(L("Transparent")).tag("transparent") }.pickerStyle(.segmented);Text(L("sRGB · 8 bit · RGBA")).font(.caption).foregroundStyle(.secondary);HStack { Button(L("Cancel")) { s.showNewDocument = false };Spacer();Button(L("Create")) { s.newDocument(width:newWidth,height:newHeight,background:newBackground == "transparent" ? nil : .white);s.showNewDocument = false }.buttonStyle(PhotoButtonStyle(prominent:true)).keyboardShortcut(.defaultAction).disabled(!(32...8192).contains(newWidth) || !(32...8192).contains(newHeight)) } }.padding(28).frame(width:430).background(PhotoAmbient()).environment(\.photoTheme,theme) }
    private var commandPalette:some View { VStack(spacing:0) { TextField(L("Search commands…"),text:$query).font(.title3).textFieldStyle(.plain).padding(20);Divider();ScrollView { VStack(spacing:2) { ForEach(Tool.allCases.filter { query.isEmpty || L($0.english).localizedCaseInsensitiveContains(query) }) { tool in Button { s.tool = tool;s.commandSearch = false } label: { HStack { Image(systemName:tool.symbol).frame(width:26);Text(L(tool.english));Spacer();Text(tool.key.uppercased()).foregroundStyle(.secondary) }.padding(10).contentShape(Rectangle()) }.buttonStyle(HoverButtonStyle()) };if query.isEmpty { Button(L("Import image…")) { s.commandSearch = false;s.importPanel() }.padding(10);Button(L("Fit canvas")) { s.fit();s.commandSearch = false }.padding(10) } }.padding(10) }.frame(height:340);Divider();HStack { Text("⇧⌘P").foregroundStyle(.tertiary);Spacer();Button(L("Close")) { s.commandSearch = false }.keyboardShortcut(.cancelAction) }.font(.caption).padding(12) }.frame(width:480).background(PhotoAmbient()).environment(\.photoTheme,theme) }
    private var exportOptions:some View { VStack(alignment:.leading,spacing:18) { Text(L("Export artwork")).font(.system(size:23,weight:.bold,design:.rounded));Picker(L("Format"),selection:$exportType) { Text(L("PNG · Alpha")).tag("png");Text(L("JPEG · White")).tag("jpeg");Text(L("TIFF · Alpha")).tag("tiff");Text(L("HEIC · Alpha")).tag("heic");Text(L("PSD · Layers")).tag("psd");Text(L("PNG Sequence")).tag("sequence");Text(L("Sprite sheet · PNG + JSON")).tag("sprites");Text(L("GIF · Loop")).tag("gif");Text(L("APNG · Alpha")).tag("apng");Text(L("MP4 · H.264")).tag("mp4");Text(L("MOV · ProRes 4444 · Alpha")).tag("prores") };Text(LF("%d × %d px · %d FPS · %d frames",s.width,s.height,Int(s.fps),max(s.frames.count,1))).font(.caption).foregroundStyle(.secondary);if ["png","jpeg","heic","tiff"].contains(exportType) { exportImageSettings };if ["sequence","gif","apng","mp4","prores","sprites"].contains(exportType) { animationExportSettings };HStack { Button(L("Cancel")) { exportSheet = false };Spacer();Button(L("Export")) { exportSheet = false;runExport() }.buttonStyle(PhotoButtonStyle(prominent:true)).keyboardShortcut(.defaultAction) } }.padding(28).frame(width:420).background(PhotoAmbient()).environment(\.photoTheme,theme) }
    private var recovery:some View { VStack(alignment:.leading,spacing:14) { Text(L("Recovery")).font(.title2);let files = s.recoveryFiles();if files.isEmpty { Text(L("No recovery copies available.")) };ForEach(files,id:\.self) { url in Button(url.lastPathComponent) { recoverySheet = false;s.restore(url) }.font(.caption) };Button(L("Close")) { recoverySheet = false } }.padding(28).frame(width:480).background(PhotoAmbient()).environment(\.photoTheme,theme) }
    /// Size and quality for single pictures, with the file size these settings give.
    /// Animation formats (0.79): output size, only the play range, GIF looping.
    @ViewBuilder private var animationExportSettings:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(L("Size")).font(.system(size:11)).frame(width:62,alignment:.leading);Slider(value:$exportScale,in:0.1...2).controlSize(.small).accessibilityLabel(L("Size"));Text("\(Int((exportScale*100).rounded())) %").monospacedDigit().frame(width:52,alignment:.trailing) }
            HStack(spacing:6) { ForEach([0.25,0.5,1.0,2.0],id:\.self) { f in Button("\(Int(f*100)) %") { exportScale = f }.buttonStyle(PhotoButtonStyle()) } }
            let size = ImageFiles.outputSize(s.width,s.height,scale:min(2,exportScale),even:(exportType == "mp4" || exportType == "prores") && abs(exportScale - 1) > 0.001)
            Text(LF("%d × %d px",size.0,size.1)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Toggle(L("Only the play range"),isOn:$exportPlayRange).disabled(Playback.clamp(s.playRange,count:s.frames.count) == nil)
            if exportType == "gif" || exportType == "apng" { Toggle(L("Loop forever"),isOn:$exportGIFLoop) }
        }.font(.system(size:11))
    }
    @ViewBuilder private var exportImageSettings:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Text(L("Size")).font(.system(size:11)).frame(width:62,alignment:.leading);Slider(value:$exportScale,in:0.1...4).controlSize(.small).accessibilityLabel(L("Size"));Text("\(Int((exportScale*100).rounded())) %").monospacedDigit().frame(width:52,alignment:.trailing) }
            HStack(spacing:6) { ForEach([0.25,0.5,1.0,2.0],id:\.self) { f in Button("\(Int(f*100)) %") { exportScale = f }.buttonStyle(PhotoButtonStyle()) } }
            if ["jpeg","heic"].contains(exportType) { HStack { Text(L("Quality")).font(.system(size:11)).frame(width:62,alignment:.leading);Slider(value:$exportQuality,in:0.1...1).controlSize(.small).accessibilityLabel(L("Quality"));Text("\(Int((exportQuality*100).rounded())) %").monospacedDigit().frame(width:52,alignment:.trailing) } }
            Text(LF("%d × %d px",max(1,Int((Double(s.width)*exportScale).rounded())),max(1,Int((Double(s.height)*exportScale).rounded()))) + (exportEstimate.isEmpty ? "" : " · " + exportEstimate)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .task(id:"\(exportType)|\(Int(exportScale*100))|\(Int(exportQuality*100))|\(s.undoStack.count)") {
            exportEstimate = ""
            try? await Task.sleep(for:.milliseconds(250))
            guard !Task.isCancelled else { return }
            let layers = s.composite(s.layers), w = s.width, h = s.height, scale = exportScale, quality = exportQuality
            let type:UTType = exportType == "png" ? .png : exportType == "jpeg" ? .jpeg : exportType == "heic" ? .heic : .tiff
            let bytes = await Task.detached(priority:.utility) { () -> Int? in
                guard let image = Renderer.render(layers:layers,width:w,height:h), let scaled = ImageFiles.scaled(image,by:scale) else { return nil }
                return try? ImageFiles.encodedData(image:scaled,type:type,quality:quality).count
            }.value
            if !Task.isCancelled, let bytes { exportEstimate = LF("about %@",ByteCountFormatter.string(fromByteCount:Int64(bytes),countStyle:.file)) }
        }
    }
    private func runExport() {
        s.stopPlayback();let quick = s.quickMaskLayer;let d = { var doc = s.document();doc.layers = s.composite(doc.layers.filter { $0.id != quick });return doc }();let frames = (d.frames.isEmpty ? [d.layers] : (exportPlayRange ? Playback.clamp(s.playRange,count:d.frames.count) : nil).map { r in r.flatMap { i in Array(repeating:d.frames[i],count:d.hold(i)) } } ?? d.expandedFrames).map { s.composite($0.filter { $0.id != quick }) };let range = exportPlayRange ? Playback.clamp(s.playRange,count:d.frames.count) : nil;let cut = { (all:[[ArtLayer]]) -> [[ArtLayer]] in guard let range else { return all };return Array(all[range]) };let spriteFrames = cut(d.frames.isEmpty ? [d.layers] : d.frames).map { s.composite($0.filter { $0.id != quick }) };let spriteHolds = range.map { r in Array((d.frameHolds ?? []).enumerated().filter { r.contains($0.offset) }.map(\.element)) } ?? (d.frameHolds ?? []);let spriteLabels = range.map { r in Array((d.frameLabels ?? []).enumerated().filter { r.contains($0.offset) }.map(\.element)) } ?? (d.frameLabels ?? []);let sound:(url:URL,start:Double,volume:Double)? = s.audio.flatMap { a in s.audioEngine.cache(for:a).map { c in (c.url,-s.soundTime(frame:range?.lowerBound ?? 0),a.volume) } };let loop = s.loop;let gifLoop = exportGIFLoop
        let format = exportType, scale = ["sequence","gif","apng","mp4","prores","sprites"].contains(exportType) ? min(2,exportScale) : exportScale, quality = exportQuality
        let url:URL
        if format == "sequence" { let p = NSOpenPanel();p.title = L("Export PNG sequence");p.prompt = L("Export");p.canChooseDirectories = true;p.canChooseFiles = false;p.canCreateDirectories = true;guard p.runModal() == .OK,let selected = p.url else { return };url = selected }
        else { let p = NSSavePanel();p.title = L("Export artwork");p.prompt = L("Export");p.allowedContentTypes = [format == "png" || format == "sprites" || format == "apng" ? .png : format == "jpeg" ? .jpeg : format == "tiff" ? .tiff : format == "heic" ? .heic : format == "psd" ? PSD.type : format == "gif" ? .gif : format == "prores" ? .quickTimeMovie : .mpeg4Movie];p.nameFieldStringValue = s.title;guard p.runModal() == .OK,let selected = p.url else { return };url = selected }
        s.busy = true
        Task { do { try await Task.detached(priority:.userInitiated) {
            if format == "sequence" { try ImageFiles.exportSequence(frames:frames,width:d.width,height:d.height,scale:scale,directory:url) }
            else if format == "sprites" { try SpriteSheet.export(frames:spriteFrames,width:d.width,height:d.height,fps:d.fps ?? 12,holds:spriteHolds,loop:loop,scale:scale,labels:spriteLabels,url:url) }
            else if format == "apng" { try ImageFiles.exportAPNG(frames:spriteFrames,holds:spriteHolds,width:d.width,height:d.height,fps:d.fps ?? 12,scale:scale,loopForever:gifLoop,url:url) }
            else if format == "gif" { try ImageFiles.exportGIF(frames:frames,width:d.width,height:d.height,fps:d.fps ?? 12,scale:scale,loopForever:gifLoop,url:url) }
            else if format == "prores" { try await ImageFiles.exportVideo(frames:frames,width:d.width,height:d.height,fps:d.fps ?? 12,scale:scale,sound:sound,proRes:true,url:url) }
            else if format == "mp4" { try await ImageFiles.exportVideo(frames:frames,width:d.width,height:d.height,fps:d.fps ?? 12,scale:scale,sound:sound,url:url) }
            else if format == "psd" { try PSD.write(layers:d.layers,width:d.width,height:d.height).write(to:url,options:.atomic) }
            else { guard let image = Renderer.render(layers:d.layers,width:d.width,height:d.height), let sized = ImageFiles.scaled(image,by:scale) else { throw StudioError.message("The canvas could not be rendered.") };try ImageFiles.export(image:sized,url:url,type:format == "png" ? .png : format == "jpeg" ? .jpeg : format == "heic" ? .heic : .tiff,quality:quality) }
        }.value;s.busy = false } catch { s.busy = false;s.report(error) } }
    }
    private func iconButton(_ icon:String,_ help:String,action:@escaping ()->Void)->some View { Button(action:action) { Image(systemName:icon).font(.system(size:12)).frame(width:25,height:26).contentShape(Rectangle()) }.buttonStyle(HoverButtonStyle()).help(help).accessibilityLabel(help) }
}
struct HoverButtonStyle:ButtonStyle { func makeBody(configuration:Configuration)->some View { HoverBody(configuration:configuration) };private struct HoverBody:View { let configuration:Configuration;@State var hover = false;var body:some View { configuration.label.background(Color.primary.opacity(configuration.isPressed ? 0.12 : hover ? 0.055 : 0),in:RoundedRectangle(cornerRadius:8)).scaleEffect(configuration.isPressed ? 0.97 : 1).onHover { hover = $0 }.animation(PhotoMotion.select,value:hover).animation(PhotoMotion.select,value:configuration.isPressed) } } }
