import SwiftUI
import AppKit
import UniversePenHost

@main struct UniverseStudioApp: App {
    @StateObject private var studio = Studio()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    init() { AppMigration.run() }
    @ObservedObject private var localization = Localization.shared
    var body: some Scene {
        WindowGroup(id:"main") { StudioRoot().environmentObject(studio).environment(\.locale,Locale(identifier:localization.language)).frame(minWidth:880,minHeight:600).onAppear { delegate.studio = studio;Localization.shared.refreshNativeMenus();connectPen() }
                .onChange(of:localization.language) { UniversePenModule.setLanguage(localization.language) } }
            .windowStyle(.hiddenTitleBar).defaultSize(width:1380,height:880)
            .commands { StudioCommands(studio:studio);PenCommands(studio:studio,pen:pen) }
        // Windows and menu bar item of the built-in UniversePen host.
        Window(L("Animation preview"),id:AnimationPreview.windowID) { AnimationPreviewWindow().environmentObject(studio).environment(\.locale,Locale(identifier:localization.language)) }
            .defaultSize(width:560,height:420)
        Window(L("Panels"),id:FocusMode.windowID) { FocusPanelsWindow().environmentObject(studio).environment(\.locale,Locale(identifier:localization.language)) }
            .windowStyle(.hiddenTitleBar).defaultSize(width:290,height:760).defaultPosition(.trailing)
        Window("UniversePen – " + L("Pen test"),id:"pentest") { UniversePenModule.penTestView() }
        Window("UniversePen – Plugins",id:"plugins") { UniversePenModule.pluginsView() }
        MenuBarExtra(isInserted:Binding(get:{ pen.running },set:{ _ in })) { UniversePenModule.menuPanel() } label: { UniversePenModule.menuIcon() }
            .menuBarExtraStyle(.window)
    }
    @ObservedObject private var pen = PenHost.shared
    private func connectPen() {
        UniversePenModule.showInStudio = { [weak studio] in
            studio?.enter(.pen)
            if let w = NSApp.windows.first(where: { ($0.identifier?.rawValue ?? "").hasPrefix("main") }) { if w.isMiniaturized { w.deminiaturize(nil) }; w.makeKeyAndOrderFront(nil) }
        }
        UniversePenModule.setLanguage(localization.language)
        pen.startIfWanted()
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var studio:Studio?
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        guard let studio,studio.dirty || studio.tabs.contains(where: \.dirty) else { return .terminateNow }
        let a = NSAlert();a.messageText = L("Unsaved documents");a.informativeText = studio.unsavedSummary() + "\n\n" + L("Unsaved changes remain available as recovery copies.");a.addButton(withTitle:L("Cancel"));a.addButton(withTitle:L("Quit"));return a.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func application(_ application:NSApplication,open urls:[URL]) {
        for url in urls {
            // universepen:// and tafel:// links (Shortcuts, iPad) go to the built-in UniversePen host.
            if ["universepen","tafel"].contains(url.scheme?.lowercased() ?? "") { UniversePenModule.handle(url:url); continue }
            do { try studio?.open(url) } catch { studio?.report(error) }
        }
    }
}
/// UniversePen menu, only while the built-in host runs.
struct PenCommands: Commands {
    @ObservedObject var studio: Studio
    @ObservedObject var pen: PenHost
    var body: some Commands {
        CommandMenu("UniversePen") { Group {
            Button(L("Open UniversePen")) { UniversePenModule.showInStudio?() }
            Button(L("Pair iPad…")) { UniversePenModule.showInStudio?(); UniversePenModule.beginPairing() }.keyboardShortcut("k",modifiers:[.command,.shift])
            Button(L("Find Pencil")) { studio.findPencil() }
            Divider()
            Button(L("Front window to the iPad")) { UniversePenModule.moveFrontWindowToIPad() }
            Button(L("Choose palette for the iPad…")) { UniversePenModule.pickPalette() }
            Button(L("Start or stop time-lapse")) { UniversePenModule.toggleTimelapse() }
            Divider()
            PenWindowButton(title:L("Pen test…"),id:"pentest")
            PenWindowButton(title:L("Plugins…"),id:"plugins")
        }.disabled(!pen.running) }
    }
}
private struct PenWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    let title:String, id:String
    var body: some View { Button(title) { openWindow(id:id); NSApp.activate() } }
}
private struct MotionPathToggle: View {
    @AppStorage("motionPath") private var on = false
    var body: some View { Toggle(L("Motion path"),isOn:$on) }
}
private struct PixelGridToggle: View {
    @AppStorage("pixelGrid") private var on = true
    var body: some View { Toggle(L("Pixel grid"),isOn:$on) }
}
private struct HistogramToggle: View {
    @AppStorage("showHistogram") private var on = false
    var body: some View { Toggle(L("Histogram"),isOn:$on) }
}
private struct NavigatorToggle: View {
    @AppStorage("showNavigator") private var on = false
    var body: some View { Toggle(L("Navigator"),isOn:$on).keyboardShortcut("n",modifiers:[.command,.option]) }
}
struct StudioCommands: Commands {
    @ObservedObject var studio: Studio
    var body: some Commands {
        CommandGroup(replacing:.newItem) { Button(L("New document…")) { studio.showNewDocument = true }.keyboardShortcut("n");Button(L("Open…")) { studio.openPanel() }.keyboardShortcut("o");Button(L("Import image as layer…")) { studio.importPanel() }.keyboardShortcut("o",modifiers:[.command,.shift]) }
        CommandGroup(replacing:.saveItem) { Button(L("Save")) { studio.savePanel() }.keyboardShortcut("s");Button(L("Save as…")) { studio.saveAsPanel() }.keyboardShortcut("s",modifiers:[.command,.shift]);Divider();Button(L("Export layers as files…")) { studio.exportLayersPanel() };Button(L("Export selection…")) { studio.exportSelectionPanel() }.disabled(studio.selection == nil) }
        CommandGroup(replacing:.pasteboard) {
            Button(L("Cut")) { if !forwardToTextField(#selector(NSText.cut(_:))) { studio.cutSelection() } }.keyboardShortcut("x")
            Button(L("Copy")) { if !forwardToTextField(#selector(NSText.copy(_:))) { studio.copySelection() } }.keyboardShortcut("c")
            Button(L("Copy merged")) { studio.copySelection(merged:true) }.keyboardShortcut("c",modifiers:[.command,.shift])
            Button(L("Paste")) { if !forwardToTextField(#selector(NSText.paste(_:))) { studio.paste() } }.keyboardShortcut("v")
            Button(L("Clear selection")) { studio.clearSelection() }.disabled(studio.selection == nil)
            Button(L("Fill selection")) { studio.fillSelection() }.keyboardShortcut(.delete,modifiers:.option).disabled(studio.selection == nil || !studio.canEdit)
            Button(L("Stroke selection") + "…") { studio.strokeSelectionDialog = true }.disabled(studio.selection == nil || !studio.canEdit)
            PatternMenu(studio:studio)
            Button(L("Content-aware fill")) { studio.contentAwareFill() }.keyboardShortcut(.delete,modifiers:.shift).disabled(studio.selection == nil || !studio.canEdit)
        }
        CommandGroup(replacing:.undoRedo) { Button(L("Undo")) { studio.undo() }.keyboardShortcut("z").disabled(studio.undoStack.isEmpty);Button(L("Redo")) { studio.redo() }.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(studio.redoStack.isEmpty) }
        CommandGroup(before:.windowList) { Button(L("Start screen")) { studio.showStartScreen() }.keyboardShortcut("h",modifiers:[.command,.shift]);Divider() }
        CommandGroup(replacing:.help) { Button(L("Keyboard shortcuts")) { studio.showShortcuts = true }.keyboardShortcut("/",modifiers:.command) }
        CommandMenu(L("Tools")) {
            ForEach(Tool.allCases) { tool in Button(L(tool.english)) { studio.tool = tool }.keyboardShortcut(KeyEquivalent(Character(tool.key)),modifiers:[]) }
            Divider();Button(L("Increase brush size")) { studio.brushSize = min(300,studio.brushSize+2) }.keyboardShortcut("]",modifiers:[])
            Button(L("Decrease brush size")) { studio.brushSize = max(1,studio.brushSize-2) }.keyboardShortcut("[",modifiers:[])
            Button(L("Increase opacity")) { studio.brushOpacity = min(1,studio.brushOpacity+0.1) }.keyboardShortcut(".",modifiers:[])
            Button(L("Decrease opacity")) { studio.brushOpacity = max(0.1,studio.brushOpacity-0.1) }.keyboardShortcut(",",modifiers:[])
            Button(L("Swap colors")) { studio.swapColors() }.keyboardShortcut("x",modifiers:[])
            Button(L("Next color")) { studio.cycleColor() }.keyboardShortcut("x",modifiers:.shift)
            Button(L("Select all")) { if !forwardToTextField(#selector(NSText.selectAll(_:))) { studio.selectAll() } }.keyboardShortcut("a",modifiers:.command)
            Button(L("Deselect")) { studio.selection = nil }.keyboardShortcut("d",modifiers:.command)
            Button(L("Invert selection")) { studio.invertSelection() }.keyboardShortcut("i",modifiers:[.command,.shift])
            Button(L("Transform selection")) { studio.beginSelectionTransform() }.disabled(studio.selection == nil)
            Menu(L("Modify")) { ForEach(Studio.SelectionModify.allCases) { k in Button(L(k.title) + "…") { studio.selectionDialog = k } } }.disabled(studio.selection == nil)
            Button(L("Select color range")) { studio.selectColorRange() }
            Divider()
            Button(L("Load layer transparency")) { studio.loadLayerTransparency() }.disabled(studio.activeLayer?.isAdjustmentLayer != false)
            Button(L("Save selection")) { studio.saveSelection() }.disabled(studio.selection == nil)
            Button(L("Load selection")) { studio.loadSavedSelection() }.disabled(!studio.hasSavedSelection)
            Divider()
            Button(L(studio.quickMaskActive ? "Leave quick mask" : "Edit in quick mask")) { studio.toggleQuickMask() }.keyboardShortcut("q",modifiers:.shift)
            Button(L("Subject")) { if !studio.selectSubject() { studio.message = "No subject found in the picture." } }
        }
        CommandMenu(L("Image")) {
            Button(L("Auto tone")) { if !studio.autoTone() { studio.message = "Nothing to adjust on this layer." } }.keyboardShortcut("l",modifiers:[.command,.shift]).disabled(!studio.canEdit)
            Button(L("Remove red eye")) { if studio.removeRedEye() == 0 { studio.message = "Select the pupils first (ellipse selection), then try again." } }.disabled(studio.selection == nil || !studio.canEdit)
            Button(L("Replace color") + "…") { studio.replaceColorDialog = true }.disabled(!studio.canEdit || studio.activeLayer?.isAdjustmentLayer == true)
            Button(L("Auto contrast")) { if !studio.autoContrast() { studio.message = "Nothing to adjust on this layer." } }.keyboardShortcut("l",modifiers:[.command,.option,.shift]).disabled(!studio.canEdit)
            Divider()
            Button(L("Duplicate image")) { studio.duplicateImage() }
            Button(L("Image size…")) { studio.imageDialog = .imageSize }.keyboardShortcut("i",modifiers:[.command,.option])
            Button(L("Canvas size…")) { studio.imageDialog = .canvasSize }.keyboardShortcut("c",modifiers:[.command,.option])
            Divider()
            Button(L("Crop to selection")) { studio.cropToSelection() }.disabled(studio.selection == nil)
            Button(L("Reveal all")) { studio.revealAll() };Button(L("Trim transparent pixels")) { studio.trim() }
            Divider()
            Button(L("Rotate 90° clockwise")) { studio.rotateCanvas(.clockwise) }
            Button(L("Rotate 90° counter-clockwise")) { studio.rotateCanvas(.counterClockwise) }
            Button(L("Rotate 180°")) { studio.rotateCanvas(.halfTurn) }
            Button(L("Flip canvas horizontally")) { studio.flipCanvas(horizontal:true) }
            Button(L("Flip canvas vertically")) { studio.flipCanvas(horizontal:false) }
            Divider()
            Button(L("Flip layer horizontally")) { studio.flipLayer(horizontal:true) }
            Button(L("Flip layer vertically")) { studio.flipLayer(horizontal:false) }
            Button(L("Remove background")) { if !studio.removeBackground() { studio.message = "No subject found in the picture." } }.disabled(!studio.canEdit)
            Button(L("Reveal selection")) { studio.maskFromSelection(reveal:true) }.disabled(studio.selection == nil)
            Button(L("Hide selection")) { studio.maskFromSelection(reveal:false) }.disabled(studio.selection == nil)
        }
        CommandMenu(L("Layers")) {
            Button(L("New layer")) { studio.newLayer() }.keyboardShortcut("n",modifiers:[.command,.shift])
            Button(L("New adjustment layer")) { studio.newAdjustmentLayer() }.keyboardShortcut("j",modifiers:[.command,.option])
            Button(L("Duplicate")) { studio.duplicateLayer() }
            Button(L("Layer via copy")) { studio.layerFromSelection(cut:false) }.keyboardShortcut("j")
            Button(L("Layer via cut")) { studio.layerFromSelection(cut:true) }.keyboardShortcut("j",modifiers:[.command,.shift])
            Button(L("Free transform")) { studio.transformMode.toggle() }.keyboardShortcut("t",modifiers:.command)
            Button(L("Distort")) { studio.distorting ? studio.applyDistort() : studio.beginDistort() }.keyboardShortcut("t",modifiers:[.command,.option]).disabled(!studio.canEdit)
            Button(L("Reset transform")) { studio.resetTransform() }
            Menu(L("Align to canvas")) {
                Button(L("Left edges")) { studio.align(.left) };Button(L("Horizontal centers")) { studio.align(.centerX) };Button(L("Right edges")) { studio.align(.right) }
                Divider()
                Button(L("Top edges")) { studio.align(.top) };Button(L("Vertical centers")) { studio.align(.centerY) };Button(L("Bottom edges")) { studio.align(.bottom) }
            }
            Button(L("Group layers")) { studio.groupSelected() }.keyboardShortcut("g",modifiers:.command)
            Button(L("Ungroup")) { studio.ungroup() }.keyboardShortcut("g",modifiers:[.command,.shift]).disabled(studio.activeLayer?.groupID == nil)
            Button(L("Clipping mask")) { studio.toggleClipping() }.keyboardShortcut("g",modifiers:[.command,.option]).disabled(studio.selectedLayer == 0)
            Button(L("Delete layer")) { studio.deleteLayer() }.keyboardShortcut(.delete,modifiers:[.command,.shift])
            Button(L("Visibility")) { studio.mutateLayer("Visibility") { $0.visible.toggle() } }.keyboardShortcut("h",modifiers:.option)
            Button(L("Merge down")) { studio.mergeDown() }.keyboardShortcut("e",modifiers:.command)
            Button(L("Merge visible")) { studio.mergeVisible() }.keyboardShortcut("e",modifiers:[.command,.shift])
            Button(L("Stamp visible")) { studio.stampVisible() }.keyboardShortcut("e",modifiers:[.command,.shift,.option])
            Button(L("Flatten image")) { studio.flattenImage() }
            Button(L("Rasterize layer")) { studio.rasterizeLayer() }
        }
        CommandGroup(before:.toolbar) {   // into the system View menu (a second "View" menu would appear otherwise)
            Toggle(L("Show guides"),isOn:Binding(get:{ studio.showGuides },set:{ studio.showGuides = $0 })).keyboardShortcut(";",modifiers:.command)
            Toggle(L("Snap to guides"),isOn:Binding(get:{ studio.snapToGuides },set:{ studio.snapToGuides = $0 })).keyboardShortcut(";",modifiers:[.command,.shift])
            Toggle(L("Lock guides"),isOn:Binding(get:{ studio.guidesLocked },set:{ studio.guidesLocked = $0 }))
            Button(L("New guide…")) { studio.guideDialog = true }
            Button(L("Guides from selection")) { studio.guidesFromSelection() }
            Button(L("Clear guides")) { studio.clearGuides() }.disabled(studio.guides.isEmpty)
            Divider()
            Button(L("Fit canvas")) { studio.fit() }.keyboardShortcut("0")
            Button(L("Zoom in")) { studio.zoom = min(16,studio.zoom*1.2) }.keyboardShortcut("+")
            Button(L("Zoom out")) { studio.zoom = max(0.1,studio.zoom/1.2) }.keyboardShortcut("-")
            Button(L("Mirror canvas")) { studio.mirrored.toggle() }.keyboardShortcut("h",modifiers:.shift)
            Toggle(L("Focus mode"),isOn:$studio.focusMode).keyboardShortcut("f",modifiers:[.command,.option])
            NavigatorToggle()
            HistogramToggle()
            PixelGridToggle()
            Button(L("Command search")) { studio.commandSearch = true }.keyboardShortcut("p",modifiers:[.command,.shift])
        }
        CommandMenu(L("Animation")) { Group {
            Button(L("Duplicate frame")) { studio.addFrame() }.keyboardShortcut("f",modifiers:.shift)
            Button(L("Blank frame")) { studio.blankFrame() }.keyboardShortcut("f",modifiers:[.shift,.option])
            Button(L("Hold frame longer")) { studio.nudgeHold(1) }.keyboardShortcut(.upArrow,modifiers:.option)
            Button(L("Hold frame shorter")) { studio.nudgeHold(-1) }.keyboardShortcut(.downArrow,modifiers:.option)
            Button(L("Previous frame")) { studio.stepToFrame(max(0,studio.frameIndex-1)) }.keyboardShortcut(.leftArrow,modifiers:.option)
            Button(L("Next frame")) { studio.stepToFrame(min(studio.frames.count-1,studio.frameIndex+1)) }.keyboardShortcut(.rightArrow,modifiers:.option)
            Button(L("First frame")) { studio.firstFrame() }.keyboardShortcut(.leftArrow,modifiers:[.option,.shift])
            Button(L("Last frame")) { studio.lastFrame() }.keyboardShortcut(.rightArrow,modifiers:[.option,.shift])
            Button(L("Move frame earlier")) { studio.moveFrame(from: studio.frameIndex, to: studio.frameIndex - 1) }
                .keyboardShortcut(.leftArrow,modifiers:[.option,.command]).disabled(studio.frameIndex == 0)
            Button(L("Move frame later")) { studio.moveFrame(from: studio.frameIndex, to: studio.frameIndex + 1) }
                .keyboardShortcut(.rightArrow,modifiers:[.option,.command]).disabled(studio.frameIndex >= studio.frames.count - 1)
            Button(L("Delete frame")) { studio.removeFrame() }
                .keyboardShortcut(.delete,modifiers:[.option,.command]).disabled(studio.frames.count < 2)
            Button(L("Onion Skin")) { studio.onionSkin.toggle() }.keyboardShortcut("o",modifiers:.option)
            Button(L("Play / Pause")) { studio.togglePlayback() }.keyboardShortcut(.space,modifiers:[])
            AnimationPreviewButton()
            MotionPathToggle()
            Divider()
            Menu(L("Effects")) { Group {
                Menu(L("Typewriter")) {
                    Button(L("Letter by letter")) { studio.typewriter(byWord: false, restTicks: Int(studio.fps)) }
                    Button(L("Two letters at a time")) { studio.typewriter(byWord: false, perStep: 2, restTicks: Int(studio.fps)) }
                    Button(L("Word by word")) { studio.typewriter(byWord: true, restTicks: Int(studio.fps)) }
                }.disabled(studio.activeLayer?.strokes.contains { $0.kind == "text" } != true).help(L("The text on the active layer appears bit by bit"))
                Menu(L("Draw on")) {
                    Button(L("Stroke by stroke")) { studio.drawOn(count: 0, byStroke: true, restTicks: Int(studio.fps)) }
                    Divider()
                    ForEach([1.0, 2.0, 4.0], id: \.self) { sec in Button(LF("%@ s, smooth", String(Int(sec)))) { studio.drawOn(count: max(2, Int((studio.fps * sec).rounded())), byStroke: false, restTicks: Int(studio.fps)) } }
                }.disabled(studio.activeLayer?.strokes.contains(where: DrawOn.drawable) != true).help(L("The drawing on the active layer draws itself"))
                Menu(L("Colour cycle")) {
                    ForEach([1.0, 2.0, 4.0], id: \.self) { sec in Button(LF("%@ s, rainbow", String(Int(sec)))) { studio.colorCycle(count: max(2, Int((studio.fps * sec).rounded()))) } }
                    Divider()
                    ForEach([1.0, 2.0], id: \.self) { sec in Button(LF("%@ s, pulse to brush colour", String(Int(sec)))) { studio.colorCycle(count: max(2, Int((studio.fps * sec).rounded())), to: studio.color) } }
                    Divider()
                    Button(L("Rainbow over existing frames")) { studio.rainbowAllFrames() }.disabled(studio.frames.count < 2)
                }.disabled(studio.activeLayer?.strokes.isEmpty != false).help(L("Strokes, shapes and text change colour in a loop; pixels keep theirs"))
                Menu(L("Camera move")) {
                    ForEach(CameraMove.allCases) { c in
                        Menu { ForEach([1.0, 2.0, 4.0], id: \.self) { sec in Button(LF("%@ s", String(Int(sec)))) { studio.cameraMove(c, count: max(2, Int((studio.fps * sec).rounded()))) } }
                            Divider()
                            Button(L("Over all frames")) { studio.cameraMove(c, count: 0) }.disabled(studio.frames.count < 2)
                        } label: { Label(L(c.title), systemImage: c.symbol) }
                    }
                }.help(L("A virtual camera zooms, pans or shakes over the whole picture"))
                Menu(L("Weather")) {
                    ForEach(Weather.allCases) { w in
                        Menu { if studio.frames.count > 1 { Button(L("Over all frames")) { studio.addWeather(w, count: 0) } } else { ForEach([1.0, 2.0], id: \.self) { sec in Button(LF("%@ s", String(Int(sec)))) { studio.addWeather(w, count: max(2, Int((studio.fps * sec).rounded()))) } } } }
                        label: { Label(L(w.title), systemImage: w.symbol) }
                    }
                }.help(L("Snow, rain or sparkles on a new layer, as a seamless loop"))
                Menu(L("Burst")) {
                    ForEach(BurstStyle.allCases) { b in
                        Menu { if studio.frames.count > 1 { Button(L("Over all frames")) { studio.addBurst(b, count: 0) } } else { ForEach([1.0, 2.0], id: \.self) { sec in Button(LF("%@ s", String(Int(sec)))) { studio.addBurst(b, count: max(2, Int((studio.fps * sec).rounded()))) } } } }
                        label: { Label(L(b.title), systemImage: b.symbol) }
                    }
                }.help(L("A one-off pop of confetti or sparks from the middle of the active layer, on a new layer"))
                Button(L("Speed lines")) { studio.addSpeedLines() }.disabled(studio.frames.count < 2)
                    .help(L("Comic-style streaks behind the active layer, from how fast it actually moves – on a new layer below it"))
                Button(L("Landing dust")) { studio.addLandingDust() }.disabled(studio.frames.count < 3)
                    .help(L("A little dust cloud where the active layer touches down – pairs with Bounce"))
                Menu(L("One after another")) {
                    ForEach(Stagger.styles) { p in
                        Menu { ForEach([("Quick", 0.15), ("Calm", 0.35)], id: \.0) { name, sec in
                            Button(L(name)) { studio.staggerIn(p, gap: max(1, Int((studio.fps * sec).rounded())), duration: max(2, Int((studio.fps * sec * 2).rounded())), restTicks: Int(studio.fps)) } } }
                        label: { Label(L(p.title), systemImage: p.symbol) }
                    }
                }.help(L("The layers come in one by one, each a little after the one below"))
                Menu(L("Bend & wobble")) {
                    ForEach(DeformLoop.allCases) { d in
                        Menu { ForEach([1.0, 2.0], id: \.self) { sec in
                            Button(LF("%@ s", String(Int(sec)))) { studio.deformLoop(d, count: max(2, Int((studio.fps * sec).rounded()))) }
                            Button(LF("%@ s, strong", String(Int(sec)))) { studio.deformLoop(d, count: max(2, Int((studio.fps * sec).rounded())), strength: 2) } } }
                        label: { Label(L(d.title), systemImage: d.symbol) }
                    }
                }.disabled(studio.activeLayer?.strokes.contains { $0.imageData == nil } != true).help(L("The drawing on the active layer waves, sways or squashes in a loop"))
                Menu(L("Follow path")) {
                    ForEach([1.0, 2.0, 4.0], id: \.self) { sec in Button(LF("%@ s", String(Int(sec)))) { studio.followPath(count: max(2, Int((studio.fps * sec).rounded())), eased: true, orient: false) } }
                    Divider()
                    ForEach([1.0, 2.0, 4.0], id: \.self) { sec in Button(LF("%@ s, turning along", String(Int(sec)))) { studio.followPath(count: max(2, Int((studio.fps * sec).rounded())), eased: true, orient: true) } }
                }.disabled(studio.routePath() == nil).help(L("Draw a route with the pen tool first"))
                Menu(L("Motion preset")) {
                    ForEach(MotionPreset.allCases) { p in
                        Menu { ForEach([0.5, 1.0, 2.0], id: \.self) { sec in Button(LF("%@ s", sec == 0.5 ? "0.5" : String(Int(sec)))) { studio.applyMotionPreset(p, count: max(2, Int((studio.fps * sec).rounded()))) } } }
                        label: { Label(L(p.title), systemImage: p.symbol) }
                    }
                }
            } }.help(L("Ready-made animations that create new frames"))
            Menu(L("Layer motion")) { Group {
                Section(L("Timing")) {
                    Menu(L("Delay layer")) {
                        ForEach([1, 2, 3], id: \.self) { n in Button(LF("%d frames later", n)) { studio.delayLayer(by: n) } }
                        Divider()
                        ForEach([1, 2], id: \.self) { n in Button(LF("%d frames earlier", n)) { studio.delayLayer(by: -n) } }
                        Divider()
                        Button(L("1 frame later, hold the start")) { studio.delayLayer(by: 1, wrap: false) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer runs a few frames behind the rest – hair or a tail that follows a moment later"))
                    Menu(L("Ease the motion")) {
                        ForEach(Studio.EaseMode.allCases) { m in Button(L(m.title)) { studio.easeLayerMotion(m) } }
                    }.disabled(studio.frames.count < 3)
                        .help(L("Re-times the active layer's movement – slow in, slow out or both – without adding frames"))
                    Menu(L("Step the motion")) {
                        Button(L("On twos")) { studio.stepLayerMotion(every: 2) }
                        Button(L("On threes")) { studio.stepLayerMotion(every: 3) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer only moves every 2nd or 3rd frame – a stop-motion look for one layer"))
                    Button(L("Reverse this layer only")) { studio.reverseLayerOnly() }.disabled(studio.frames.count < 2)
                        .help(L("The active layer plays backwards while everything else runs forward"))
                }
                Section(L("Path")) {
                    Menu(L("Shift in all frames")) {
                        ForEach([10.0, 50.0], id: \.self) { d in
                            Button(LF("Left %@ px", String(Int(d)))) { studio.shiftLayerAllFrames(dx: -d, dy: 0) }
                            Button(LF("Right %@ px", String(Int(d)))) { studio.shiftLayerAllFrames(dx: d, dy: 0) }
                            Button(LF("Up %@ px", String(Int(d)))) { studio.shiftLayerAllFrames(dx: 0, dy: -d) }
                            Button(LF("Down %@ px", String(Int(d)))) { studio.shiftLayerAllFrames(dx: 0, dy: d) }
                            Divider()
                        }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Moves the active layer by the same amount in every frame – the movement stays"))
                    Menu(L("Motion strength")) {
                        Button(L("Stronger (1.5×)")) { studio.amplifyMotion(factor: 1.5) }
                        Button(L("Much stronger (2×)")) { studio.amplifyMotion(factor: 2) }
                        Divider()
                        Button(L("Calmer (0.7×)")) { studio.amplifyMotion(factor: 0.7) }
                        Button(L("Half (0.5×)")) { studio.amplifyMotion(factor: 0.5) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Makes the active layer's movement bigger or smaller around its middle – same timing"))
                    Menu(L("Smooth motion")) {
                        Button(L("Gentle")) { studio.smoothMotion(passes: 1) }
                        Button(L("Strong")) { studio.smoothMotion(passes: 4) }
                        Divider()
                        Button(L("As a loop")) { studio.smoothMotion(passes: 2, loop: true) }
                    }.disabled(studio.frames.count < 3)
                        .help(L("Takes the jitter out of the active layer's movement – averages each frame with its neighbours"))
                    Menu(L("Mirror the motion")) {
                        Button(L("Left ↔ right")) { studio.mirrorLayerMotion(horizontal: true) }
                        Button(L("Up ↕ down")) { studio.mirrorLayerMotion(horizontal: false) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer's path is mirrored around its start – it moves the other way"))
                    Button(L("Remove drift")) { studio.removeDrift() }.disabled(studio.frames.count < 2)
                        .help(L("Takes out the active layer's net travel – a walk cycle walks on the spot, wiggles stay"))
                    Menu(L("Arc the path")) {
                        Button(L("Gentle arc, one side")) { studio.arcLayerPath(amount: 0.15) }
                        Button(L("Strong arc, one side")) { studio.arcLayerPath(amount: 0.35) }
                        Divider()
                        Button(L("Gentle arc, other side")) { studio.arcLayerPath(amount: -0.15) }
                        Button(L("Strong arc, other side")) { studio.arcLayerPath(amount: -0.35) }
                    }.disabled(studio.frames.count < 3)
                        .help(L("Bends the active layer's straight movement into an arc – natural motion rarely runs straight"))
                }
                Section(L("Other layers")) {
                    Button(L("Copy motion to selected layers")) { studio.copyMotionToSelected() }
                        .disabled(studio.frames.count < 2 || studio.selectedIDs.subtracting([studio.activeLayer?.id].compactMap { $0 }).isEmpty)
                        .help(L("The other selected layers move like the active one, each from its own starting point"))
                    Menu(L("Follow in a chain")) {
                        ForEach([1, 2, 3], id: \.self) { n in Button(LF("%d frames apart", n)) { studio.followInChain(step: n) } }
                    }.disabled(studio.frames.count < 2 || studio.selectedIDs.subtracting([studio.activeLayer?.id].compactMap { $0 }).isEmpty)
                        .help(L("The other selected layers repeat the active layer's movement one after another – a wave through a tail or chain"))
                    Button(L("Out of step")) { studio.desyncSelectedLayers() }
                        .disabled(studio.frames.count < 2 || studio.selectedIDs.count < 2)
                        .help(L("Gives every selected layer its own time offset, so copies of one animation stop moving in lockstep"))
                }
                Section(L("Whole layer")) {
                    Button(L("Pin layer state to all frames")) { studio.pinLayerStateToAllFrames() }.disabled(studio.frames.count < 2)
                        .help(L("Copies the active layer's position, size, turn and opacity from this frame into every frame"))
                    Button(L("Copy drawing to all frames")) { studio.copyDrawingToAllFrames() }.disabled(studio.frames.count < 2)
                        .help(L("Puts this frame's drawing of the active layer into every frame – each frame keeps its own position"))
                    Menu(L("Flip layer in all frames")) {
                        Button(L("Horizontally")) { studio.flipLayerAllFrames(horizontal: true) }
                        Button(L("Vertically")) { studio.flipLayerAllFrames(horizontal: false) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Mirrors the active layer's drawing in every frame – turn a cycle to face the other way"))
                    Button(L("Remove layer from all frames")) { studio.removeLayerFromAllFrames() }.disabled(studio.frames.count < 2)
                        .help(L("Deletes the active layer from every frame – e.g. a rotoscope or reference underlay"))
                }
            } }.help(L("Rework the movement the active layer already has, across all frames"))
            Menu(L("Layer effects")) { Group {
                Section(L("Move")) {
                    Menu(L("Travel over the frames")) {
                        ForEach([false, true], id: \.self) { eased in
                            Button(L(eased ? "Left to right, soft" : "Left to right")) { studio.travelLayer(dx: Double(studio.width), dy: 0, eased: eased) }
                            Button(L(eased ? "Right to left, soft" : "Right to left")) { studio.travelLayer(dx: -Double(studio.width), dy: 0, eased: eased) }
                            Button(L(eased ? "Up, soft" : "Up")) { studio.travelLayer(dx: 0, dy: -Double(studio.height), eased: eased) }
                            Button(L(eased ? "Down, soft" : "Down")) { studio.travelLayer(dx: 0, dy: Double(studio.height), eased: eased) }
                            Divider()
                        }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer crosses the whole canvas over the existing frames – its own motion stays"))
                    Menu(L("Orbit")) {
                        Button(L("Small circle")) { studio.orbitLayer(radius: 20) }
                        Button(L("Big circle")) { studio.orbitLayer(radius: 80) }
                        Button(L("Flat ellipse")) { studio.orbitLayer(radius: 80, squash: 0.35) }
                        Divider()
                        Button(L("Small circle, other way")) { studio.orbitLayer(radius: 20, clockwise: false) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer runs on a circle that starts at its position – a seamless loop"))
                    Menu(L("Bounce over the frames")) {
                        Button(L("One big jump")) { studio.bounceLayer(height: Double(studio.height) * 0.3, bounces: 1) }
                        Button(L("Ball, 3 hops")) { studio.bounceLayer(height: Double(studio.height) * 0.3, bounces: 3) }
                        Button(L("Small hops")) { studio.bounceLayer(height: Double(studio.height) * 0.08, bounces: 4, decay: 0.85) }
                        Divider()
                        Button(L("Ball, 3 hops, squashy")) { studio.bounceWithSquash(height: Double(studio.height) * 0.3, bounces: 3) }
                        Button(L("One big jump, squashy")) { studio.bounceWithSquash(height: Double(studio.height) * 0.3, bounces: 1) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer hops across the frames, each hop lower, and lands where it started"))
                    Menu(L("Shake layer")) {
                        Button(L("Trembling")) { studio.shakeLayer(amount: 3) }
                        Button(L("Shaking")) { studio.shakeLayer(amount: 10) }
                        Button(L("Rattling, with turn")) { studio.shakeLayer(amount: 8, turn: true) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Small random jolts of the active layer in every frame – fear, cold or an impact"))
                    Menu(L("Sway layer (rotate)")) {
                        Button(L("Gentle")) { studio.swayLayer(degrees: 6) }
                        Button(L("Strong")) { studio.swayLayer(degrees: 16) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Rocks the active layer back and forth across the frames – a gentle swing"))
                    Menu(L("Float layer (drift)")) {
                        Button(L("Up and down, gentle")) { studio.floatLayer(amplitude: 18, horizontal: false) }
                        Button(L("Up and down, strong")) { studio.floatLayer(amplitude: 44, horizontal: false) }
                        Divider()
                        Button(L("Side to side, gentle")) { studio.floatLayer(amplitude: 18, horizontal: true) }
                        Button(L("Side to side, strong")) { studio.floatLayer(amplitude: 44, horizontal: true) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("A soft, seamless drift over the whole animation – gentle secondary motion"))
                    Menu(L("Spin over the frames")) {
                        Button(L("Clockwise, 1 turn")) { studio.spinLayerOverFrames(turns: 1) }
                        Button(L("Clockwise, 2 turns")) { studio.spinLayerOverFrames(turns: 2) }
                        Divider()
                        Button(L("Counter-clockwise, 1 turn")) { studio.spinLayerOverFrames(turns: -1) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer turns full circles across the existing frames – a seamless loop"))
                }
                Section(L("Shape")) {
                    Menu(L("Squash & stretch")) {
                        Button(L("Normal")) { studio.squashStretch(amount: 1) }
                        Button(L("Cartoony")) { studio.squashStretch(amount: 1.8) }
                        Divider()
                        Button(L("None")) { studio.clearSquashStretch() }
                    }.disabled(studio.frames.count < 3)
                        .help(L("Stretches the active layer while it moves fast and squashes it where it lands – pairs with Bounce"))
                    Menu(L("Breathe")) {
                        Button(L("Calm")) { studio.stretchEffect(jelly: false, amount: 0.04) }
                        Button(L("Deep")) { studio.stretchEffect(jelly: false, amount: 0.1) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("A calm stretch in and out as a loop – an idle character or a sleeping animal"))
                    Menu(L("Jelly")) {
                        Button(L("Soft")) { studio.stretchEffect(jelly: true, amount: 0.2) }
                        Button(L("Wobbly")) { studio.stretchEffect(jelly: true, amount: 0.4) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("A damped wobble that starts strong and settles – after a landing or a poke"))
                    Menu(L("Grow over the frames")) {
                        Button(L("Grow")) { studio.growLayerOverFrames(grow: true) }
                        Button(L("Shrink")) { studio.growLayerOverFrames(grow: false) }
                        Divider()
                        Button(L("Pop in (overshoot)")) { studio.growLayerOverFrames(grow: true, pop: true) }
                        Button(L("Pop out (overshoot)")) { studio.growLayerOverFrames(grow: false, pop: true) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer grows out of nothing or shrinks away across the existing frames"))
                    Menu(L("Pulse size")) {
                        Button(L("Subtle")) { studio.scalePulseLayer(amount: 0.08) }
                        Button(L("Strong")) { studio.scalePulseLayer(amount: 0.22) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Grows and shrinks the active layer across the frames – a gentle breathing or heartbeat"))
                    Menu(L("Boil all frames")) {
                        Button(L("Normal")) { studio.boilAllFrames(amount: 1.5) }
                        Button(L("Stronger")) { studio.boilAllFrames(amount: 3) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Wobbles the active layer a little in every frame – a living, hand-drawn line across the whole animation"))
                }
                Section(L("Appear")) {
                    Menu(L("Fade over the frames")) {
                        Button(L("Fade in")) { studio.fadeLayerOverFrames(fadeIn: true) }
                        Button(L("Fade out")) { studio.fadeLayerOverFrames(fadeIn: false) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer fades in or out across the existing frames – no frames added"))
                    Menu(L("Wipe")) {
                        Section(L("Reveal")) { ForEach(Studio.WipeDirection.allCases) { d in Button(L(d.title)) { studio.wipeLayer(d, reveal: true) } } }
                        Section(L("Wipe away")) { ForEach(Studio.WipeDirection.allCases) { d in Button(L(d.title)) { studio.wipeLayer(d, reveal: false) } } }
                        Section(L("Circle")) {
                            Button(L("Iris open")) { studio.irisLayer(open: true) }
                            Button(L("Iris close")) { studio.irisLayer(open: false) }
                        }
                        Divider()
                        Button(L("Remove mask in all frames")) { studio.clearMaskAllFrames() }
                    }.disabled(studio.frames.count < 2)
                        .help(L("The active layer is revealed or wiped away from one side across the frames – done with its mask"))
                    Menu(L("Pulse layer (glow)")) {
                        Button(L("Subtle")) { studio.pulseLayer(floor: 0.45) }
                        Button(L("Strong")) { studio.pulseLayer(floor: 0.1) }
                        Divider()
                        Button(L("None")) { studio.unpulseLayer() }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Fades the active layer up and down across the frames – a soft glow or breathing"))
                    Menu(L("Blink layer")) {
                        Button(L("Every frame")) { studio.blinkLayer(period: 1) }
                        Button(L("Every 2 frames")) { studio.blinkLayer(period: 2) }
                        Button(L("Every 3 frames")) { studio.blinkLayer(period: 3) }
                        Divider()
                        Button(L("Steady (show always)")) { studio.steadyLayer() }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Switches the active layer on and off across the frames – a blinking light or sign"))
                    Menu(L("Motion echo")) {
                        ForEach([2, 3, 4], id: \.self) { n in Button(LF("%d ghosts", n)) { studio.motionEcho(count: n) } }
                        Menu(L("Stronger")) { ForEach([2, 3, 4], id: \.self) { n in Button(LF("%d ghosts", n)) { studio.motionEcho(count: n, strong: true) } } }
                        Divider()
                        Button(L("None")) { studio.motionEcho(count: 0) }
                    }.disabled(studio.frames.count < 2)
                        .help(L("Fading ghosts of the active layer from the frames before it – a motion trail"))
                }
            } }.help(L("Give the active layer a new movement across the existing frames"))
            Menu(L("Edit frames")) { Group {
                Button(L("Reverse frames")) { studio.reverseFrames() }.disabled(studio.frames.count < 2)
                Button(L("Merge identical frames")) { studio.mergeIdenticalFrames() }.disabled(studio.frames.count < 2)
                    .help(L("Runs of frames with the same drawing become one held frame – same motion, fewer frames"))
                Menu(L("Tween all frames")) {
                    ForEach(Studio.tweenChoices, id: \.self) { n in Button(LF("%d between each", n)) { studio.tweenAll(count: n, curve: .smooth) } }
                    Menu(L("Morph strokes")) { ForEach(Studio.tweenChoices, id: \.self) { n in Button(LF("%d between each", n)) { studio.tweenAll(count: n, curve: .smooth, morph: true) } } }
                        .help(L("Blends brush strokes and shapes point by point when both frames have the same strokes"))
                }.disabled(studio.frames.count < 2)
                    .help(L("Inserts in-betweens between every pair of frames at once – a whole animation turns smooth"))
                Menu(L("Close loop")) {
                    ForEach(Studio.tweenChoices, id: \.self) { n in Button(LF("%d frames", n)) { studio.closeLoop(count: n) } }
                    Menu(L("Crossfade drawings")) { ForEach(Studio.tweenChoices, id: \.self) { n in Button(LF("%d frames", n)) { studio.closeLoop(count: n, crossfade: true) } } }
                }.disabled(studio.frames.count < 2).help(L("In-betweens from the last frame back to the first, so the loop runs on without a jump"))
                Button(L("Remove empty frames")) { studio.removeEmptyFrames() }.disabled(studio.frames.count < 2)
                    .help(L("Deletes every frame in which nothing is drawn"))
                Menu(L("Repeat animation")) {
                    ForEach([2, 3, 4], id: \.self) { n in Button(LF("%d×", n)) { studio.repeatAnimation(times: n) } }
                }.disabled(studio.frames.count < 2)
                    .help(L("Appends copies of the whole animation so it plays through several times – a longer clip"))
                Menu(L("Repeat play range")) {
                    ForEach([2, 3, 4], id: \.self) { n in Button(LF("%d×", n)) { studio.repeatPlayRange(times: n) } }
                }.disabled(studio.playRange == nil)
                    .help(L("Copies the frames of the play range right behind it – one passage happens several times"))
                Menu(L("Pause at the end")) {
                    ForEach([0.5, 1.0, 2.0], id: \.self) { sec in Button(LF("%@ s", sec == 0.5 ? "0.5" : String(Int(sec)))) { studio.addPauseAtEnd(seconds: sec) } }
                }.disabled(studio.frames.isEmpty)
                    .help(L("The last frame holds longer, so a loop rests a moment before it starts again"))
                Menu(L("Retime")) {
                    Button(L("Slow motion (2×)")) { studio.retimeRange(factor: 2) }
                    Button(L("Slow motion (3×)")) { studio.retimeRange(factor: 3) }
                    Button(L("Fast forward (½×)")) { studio.retimeRange(factor: 0.5) }
                    Divider()
                    Button(L("Slow start (ease in)")) { studio.rampTiming(slowStart: true) }
                    Button(L("Slow end (ease out)")) { studio.rampTiming(slowStart: false) }
                    Button(L("Reset timing (all on ones)")) { studio.resetTiming() }
                    Divider()
                    Menu(L("Set total length")) {
                        ForEach([1.0, 2.0, 3.0, 5.0, 10.0], id: \.self) { sec in
                            Button(LF("%@ s", String(Int(sec)))) { studio.fitToDuration(seconds: sec) }
                        }
                    }.help(L("Scales all holds so the whole animation runs about this long"))
                }.disabled(studio.frames.isEmpty)
                    .help(L("Slows down or speeds up by scaling how long each frame holds – no frames added or removed"))
                Menu(L("Thin frames")) {
                    Button(L("On twos")) { studio.thinFrames(every: 2) }
                    Button(L("On threes")) { studio.thinFrames(every: 3) }
                    Button(L("On fours")) { studio.thinFrames(every: 4) }
                }.disabled(studio.frames.count < 2)
                    .help(L("Keeps every 2nd/3rd/4th drawing and holds it for the gap – same length, fewer frames"))
                Button(L("Bake ping-pong into frames")) { studio.bakePingPong() }.disabled(studio.frames.count < 3)
            } }.help(L("Reorder, smooth, loop and retime the frames"))
            Divider()
            Menu(L("Import & sound")) { Group {
                Button(L("Import frames…")) { studio.importFramesPanel() }
                Button(L("Import video for tracing…")) { studio.importVideoPanel() }
                Button(L("Import sound…")) { studio.importAudioPanel() }
                Button(L("Remove sound")) { studio.removeAudio() }.disabled(studio.audio == nil)
                Menu(L("React to sound")) { ForEach(SoundReaction.allCases) { r in Button(L(r.title)) { studio.reactToSound(r) } } }.disabled(studio.audio == nil)
            } }.help(L("Bring in frames, video or sound"))
        }.disabled(studio.module != .animate) }
    }
}
