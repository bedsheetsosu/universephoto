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
        CommandGroup(replacing:.undoRedo) { Button(L("Undo")) { studio.undo() }.keyboardShortcut("z").disabled(studio.undoStack.isEmpty);Button(L("Redo")) { studio.redo() }.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(studio.redoStack.isEmpty) }
        CommandMenu(L("Tools")) {
            ForEach(Tool.allCases) { tool in Button(L(tool.english)) { studio.tool = tool }.keyboardShortcut(KeyEquivalent(Character(tool.key)),modifiers:[]) }
            Divider();Button(L("Increase brush size")) { studio.brushSize = min(300,studio.brushSize+2) }.keyboardShortcut("]",modifiers:[])
            Button(L("Decrease brush size")) { studio.brushSize = max(1,studio.brushSize-2) }.keyboardShortcut("[",modifiers:[])
            Button(L("Increase opacity")) { studio.brushOpacity = min(1,studio.brushOpacity+0.1) }.keyboardShortcut(".",modifiers:[])
            Button(L("Decrease opacity")) { studio.brushOpacity = max(0.1,studio.brushOpacity-0.1) }.keyboardShortcut(",",modifiers:[])
            Button(L("Next color")) { studio.cycleColor() }.keyboardShortcut("x",modifiers:[])
            Button(L("Select all")) { studio.selectAll() }.keyboardShortcut("a",modifiers:.command)
            Button(L("Deselect")) { studio.selection = nil }.keyboardShortcut("d",modifiers:.command)
            Button(L("Invert selection")) { studio.invertSelection() }.keyboardShortcut("i",modifiers:[.command,.shift])
        }
        CommandMenu(L("Layers")) {
            Button(L("New layer")) { studio.newLayer() }.keyboardShortcut("n",modifiers:[.command,.shift])
            Button(L("Duplicate")) { studio.duplicateLayer() }.keyboardShortcut("j")
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
