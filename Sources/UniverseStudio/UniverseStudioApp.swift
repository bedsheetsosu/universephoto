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
        let a = NSAlert();a.messageText = L("Unsaved documents");a.informativeText = L("Unsaved changes remain available as recovery copies.");a.addButton(withTitle:L("Cancel"));a.addButton(withTitle:L("Quit"));return a.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
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
            Button(L(studio.quickMaskActive ? "Leave quick mask" : "Edit in quick mask")) { studio.toggleQuickMask() }.keyboardShortcut("q",modifiers:.shift)
            Button(L("Subject")) { if !studio.selectSubject() { studio.message = "No subject found in the picture." } }
        }
        CommandMenu(L("Image")) {
            Button(L("Auto tone")) { if !studio.autoTone() { studio.message = "Nothing to adjust on this layer." } }.keyboardShortcut("l",modifiers:[.command,.shift]).disabled(!studio.canEdit)
            Button(L("Replace color") + "…") { studio.replaceColorDialog = true }.disabled(!studio.canEdit || studio.activeLayer?.isAdjustmentLayer == true)
            Button(L("Auto contrast")) { if !studio.autoContrast() { studio.message = "Nothing to adjust on this layer." } }.keyboardShortcut("l",modifiers:[.command,.option,.shift]).disabled(!studio.canEdit)
            Divider()
            Button(L("Image size…")) { studio.imageDialog = .imageSize }.keyboardShortcut("i",modifiers:[.command,.option])
            Button(L("Canvas size…")) { studio.imageDialog = .canvasSize }.keyboardShortcut("c",modifiers:[.command,.option])
            Divider()
            Button(L("Crop to selection")) { studio.cropToSelection() }.disabled(studio.selection == nil)
            Button(L("Trim transparent pixels")) { studio.trim() }
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
            NavigatorToggle()
            Button(L("Command search")) { studio.commandSearch = true }.keyboardShortcut("p",modifiers:[.command,.shift])
        }
        CommandMenu(L("Animation")) {
            Button(L("Duplicate frame")) { studio.addFrame() }.keyboardShortcut("f",modifiers:.shift)
            Button(L("Previous frame")) { studio.selectFrame(max(0,studio.frameIndex-1)) }.keyboardShortcut(.leftArrow,modifiers:.option)
            Button(L("Next frame")) { studio.selectFrame(min(studio.frames.count-1,studio.frameIndex+1)) }.keyboardShortcut(.rightArrow,modifiers:.option)
            Button(L("Onion Skin")) { studio.onionSkin.toggle() }.keyboardShortcut("o",modifiers:.option)
            Button(L("Play / Pause")) { studio.togglePlayback() }.keyboardShortcut(.space,modifiers:[])
        }
    }
}
