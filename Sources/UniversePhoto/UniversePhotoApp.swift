import SwiftUI
import AppKit

@main struct UniversePhotoApp: App {
    @StateObject private var studio = Studio()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var localization = Localization.shared
    var body: some Scene {
        WindowGroup { Workspace().environmentObject(studio).environment(\.locale,Locale(identifier:localization.language)).frame(minWidth:880,minHeight:600).onAppear { delegate.studio = studio;Localization.shared.refreshNativeMenus() } }
            .windowStyle(.hiddenTitleBar).defaultSize(width:1380,height:880)
            .commands { StudioCommands(studio:studio) }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var studio:Studio?
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        guard let studio,studio.dirty || studio.tabs.contains(where: \.dirty) else { return .terminateNow }
        let a = NSAlert();a.messageText = L("Unsaved documents");a.informativeText = L("Unsaved changes remain available as recovery copies.");a.addButton(withTitle:L("Cancel"));a.addButton(withTitle:L("Quit"));return a.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func application(_ application:NSApplication,open urls:[URL]) { for url in urls { do { try studio?.open(url) } catch { studio?.report(error) } } }
}
struct StudioCommands: Commands {
    @ObservedObject var studio: Studio
    var body: some Commands {
        CommandGroup(replacing:.newItem) { Button(L("New document…")) { studio.showNewDocument = true }.keyboardShortcut("n");Button(L("Open…")) { studio.openPanel() }.keyboardShortcut("o");Button(L("Import image as layer…")) { studio.importPanel() }.keyboardShortcut("o",modifiers:[.command,.shift]) }
        CommandGroup(replacing:.saveItem) { Button(L("Save")) { studio.savePanel() }.keyboardShortcut("s");Button(L("Save as…")) { studio.saveAsPanel() }.keyboardShortcut("s",modifiers:[.command,.shift]) }
        CommandGroup(replacing:.pasteboard) {
            Button(L("Cut")) { if !forwardToTextField(#selector(NSText.cut(_:))) { studio.cutSelection() } }.keyboardShortcut("x")
            Button(L("Copy")) { if !forwardToTextField(#selector(NSText.copy(_:))) { studio.copySelection() } }.keyboardShortcut("c")
            Button(L("Copy merged")) { studio.copySelection(merged:true) }.keyboardShortcut("c",modifiers:[.command,.shift])
            Button(L("Paste")) { if !forwardToTextField(#selector(NSText.paste(_:))) { studio.paste() } }.keyboardShortcut("v")
            Button(L("Clear selection")) { studio.clearSelection() }.disabled(studio.selection == nil)
        }
        CommandGroup(replacing:.undoRedo) { Button(L("Undo")) { studio.undo() }.keyboardShortcut("z").disabled(studio.undoStack.isEmpty);Button(L("Redo")) { studio.redo() }.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(studio.redoStack.isEmpty) }
        CommandMenu(L("Tools")) {
            ForEach(Tool.allCases) { tool in Button(L(tool.english)) { studio.tool = tool }.keyboardShortcut(KeyEquivalent(Character(tool.key)),modifiers:[]) }
            Divider();Button(L("Increase brush size")) { studio.brushSize = min(300,studio.brushSize+2) }.keyboardShortcut("]",modifiers:[])
            Button(L("Decrease brush size")) { studio.brushSize = max(1,studio.brushSize-2) }.keyboardShortcut("[",modifiers:[])
            Button(L("Increase opacity")) { studio.brushOpacity = min(1,studio.brushOpacity+0.1) }.keyboardShortcut(".",modifiers:[])
            Button(L("Decrease opacity")) { studio.brushOpacity = max(0.1,studio.brushOpacity-0.1) }.keyboardShortcut(",",modifiers:[])
            Button(L("Next color")) { studio.cycleColor() }.keyboardShortcut("x",modifiers:[])
            Button(L("Select all")) { if !forwardToTextField(#selector(NSText.selectAll(_:))) { studio.selectAll() } }.keyboardShortcut("a",modifiers:.command)
            Button(L("Deselect")) { studio.selection = nil }.keyboardShortcut("d",modifiers:.command)
            Button(L("Invert selection")) { studio.invertSelection() }.keyboardShortcut("i",modifiers:[.command,.shift])
            Menu(L("Modify")) { ForEach(Studio.SelectionModify.allCases) { k in Button(L(k.title) + "…") { studio.selectionDialog = k } } }.disabled(studio.selection == nil)
            Button(L("Select color range")) { studio.selectColorRange() }
        }
        CommandMenu(L("Image")) {
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
            Button(L("Rasterize layer")) { studio.rasterizeLayer() }
        }
        CommandMenu(L("View")) {
            Button(L("Fit canvas")) { studio.fit() }.keyboardShortcut("0")
            Button(L("Zoom in")) { studio.zoom = min(16,studio.zoom*1.2) }.keyboardShortcut("+")
            Button(L("Zoom out")) { studio.zoom = max(0.1,studio.zoom/1.2) }.keyboardShortcut("-")
            Button(L("Mirror canvas")) { studio.mirrored.toggle() }.keyboardShortcut("h",modifiers:[])
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
