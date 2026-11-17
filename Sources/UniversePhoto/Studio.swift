import SwiftUI
import AppKit
import Combine

struct OpenArtwork: Identifiable {
    var id = UUID(); var document: ArtDocument; var url: URL?; var dirty = false
    var undo: [HistoryEntry] = []; var redo: [HistoryEntry] = []; var saved: ArtDocument? = nil
}
struct HistoryEntry { var document: ArtDocument; var label: String }
struct BrushPreset: Codable, Identifiable {
    var id = UUID(); var name: String; var size: Double; var opacity: Double; var smoothing: Double
}

@MainActor final class Studio: ObservableObject {
    @Published var layers = [ArtLayer(name: L("Sketch"))]
    @Published var selectedLayer = 0
    /// Further selected layers (Shift/⌘-click in the list); the active one is `selectedLayer`.
    @Published var selectedIDs: Set<UUID> = []
    @Published var groups: [LayerGroup] = []
    @Published var color = CodableColor.black
    @Published var secondaryColor = CodableColor.white
    @Published var brushSize = 12.0
    @Published var brushOpacity = 1.0
    @Published var smoothing = 0.15
    @Published var pressureEnabled = true
    @Published var tool = Tool.brush
    @Published var frames: [[ArtLayer]] = []
    @Published var frameIndex = 0
    @Published var fps = 12.0
    @Published var isPlaying = false
    @Published var loop = true
    @Published var zoom = 1.0
    @Published var pan = CGSize.zero
    @Published var rotation = 0.0
    @Published var mirrored = false
    @Published var onionSkin = false
    @Published var selection: CanvasSelection?
    @Published var fileURL: URL?
    @Published var documentName = L("Untitled")
    @Published var width = 1200
    @Published var height = 800
    @Published var dirty = false
    @Published var undoStack: [HistoryEntry] = []
    @Published var redoStack: [HistoryEntry] = []
    @Published var tabs: [OpenArtwork] = []
    @Published var tabID = UUID()
    @Published var message: String? { didSet { if message != "__localized_error" { presentedError = nil } } }
    private var presentedError:Error?
    var displayedMessage:String { if let presentedError { return LocalizedText.errorDescription(presentedError) };return L(message ?? "") }
    func report(_ error:Error) { presentedError = error;message = "__localized_error" }
    @Published var commandSearch = false
    @Published var textContent = "UniversePhoto"
    @Published var showNewDocument = false
    @Published var busy = false
    @Published var apiEnabled = false
    @Published var hoverPoint: CGPoint?
    @Published var presets = [BrushPreset(name: "Ink", size: 8, opacity: 1, smoothing: 0.12), BrushPreset(name: "Marker", size: 34, opacity: 0.45, smoothing: 0.2), BrushPreset(name: "Detail", size: 3, opacity: 1, smoothing: 0.05)]
    let pen = UniversePenAdapter()
    var playback: Timer?
    private var autosaveTask: Task<Void, Never>?
    private var penObservation: AnyCancellable?
    private var languageObservation:AnyCancellable?
    private let recoveryRoot: URL?
    private var savedDocument: ArtDocument?
    private var lastMutation: (String, Date)?
    var title: String { documentName }
    var eraser: Bool { get { tool == .eraser } set { tool = newValue ? .eraser : .brush } }
    var eyedropper: Bool { get { tool == .eyedropper } set { tool = newValue ? .eyedropper : .brush } }
    var activeLayer: ArtLayer? { layers.indices.contains(selectedLayer) ? layers[selectedLayer] : nil }
    var canEdit: Bool { activeLayer?.locked == false && !isPlaying && !busy }
    init(recoveryRoot: URL? = nil) { self.recoveryRoot = recoveryRoot; tabs = [OpenArtwork(id: tabID, document: document(), url: nil)]; savedDocument = document(); penObservation = pen.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() };languageObservation = Localization.shared.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }
    func document() -> ArtDocument {
        var currentFrames = frames
        if currentFrames.indices.contains(frameIndex) { currentFrames[frameIndex] = layers }
        return ArtDocument(title: documentName, width: width, height: height, layers: layers, frames: currentFrames, fps: fps, activeFrame: frameIndex, groups: groups.isEmpty ? nil : groups)
    }
    func checkpoint(_ label: String = "Edit") {
        lastMutation = nil
        undoStack.append(HistoryEntry(document: document(), label: label))
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    func changed() { pruneGroups(); dirty = document() != savedDocument; syncTab(); scheduleRecovery() }
    func mutateLayer(_ label: String, _ body: (inout ArtLayer) -> Void) {
        guard layers.indices.contains(selectedLayer), !isPlaying else { return }
        if lastMutation?.0 != label || Date().timeIntervalSince(lastMutation?.1 ?? .distantPast) > 0.4 { checkpoint(label) }; lastMutation = (label,Date());body(&layers[selectedLayer]); changed()
    }
    func add(_ stroke: InkStroke) {
        guard canEdit else { return }; checkpoint(tool.english)
        let stroke = bakeRetouch(stroke)
        if activeLayer?.mask != nil && maskEditing { layers[selectedLayer].mask?.append(stroke) } else { layers[selectedLayer].strokes.append(stroke) }
        changed()
    }
    @Published var maskEditing = false
    /// Paint bucket and magic wand: colour distance 0…255, connected pixels only, all layers.
    @Published var tolerance = 32.0
    @Published var contiguous = true
    @Published var sampleMerged = false
    /// Our last copy (document size, in place) and the pasteboard state right after it.
    var copiedPixels: CGImage?
    var copiedChangeCount = -1
    /// Retouch: clone source (document pixels), the offset kept while "aligned", brush strength,
    /// dodge ↔ burn and blur ↔ sharpen.
    @Published var cloneSource: CGPoint?
    var cloneOffset: CGSize?
    @Published var cloneAligned = true
    @Published var toolStrength = 0.5
    @Published var burnMode = false
    @Published var sharpenMode = false
    var smudgeState: SmudgeState?
    /// The system pasteboard; tests use a private one so they never touch the user's clipboard.
    var pasteboard = NSPasteboard.general
    func undo() {
        stopPlayback(); guard let last = undoStack.popLast() else { return }
        redoStack.append(HistoryEntry(document: document(), label: last.label)); apply(last.document); changed()
    }
    func redo() {
        stopPlayback(); guard let last = redoStack.popLast() else { return }
        undoStack.append(HistoryEntry(document: document(), label: last.label)); apply(last.document); changed()
    }
    func newLayer() { checkpoint("New layer"); layers.insert(ArtLayer(name: L("Layer") + " \(layers.count + 1)"), at: min(selectedLayer + 1, layers.count)); selectedLayer = min(selectedLayer + 1, layers.count - 1); maskEditing = false; changed() }
    func duplicateLayer() { guard var copy = activeLayer else { return }; checkpoint("Duplicate layer"); copy.id = UUID(); copy.name += L(" copy"); layers.insert(copy, at: selectedLayer + 1); selectedLayer += 1; changed() }
    func deleteLayer() { guard layers.count > 1, activeLayer?.locked == false else { return }; checkpoint("Delete layer"); layers.remove(at: selectedLayer); selectedLayer = max(0, selectedLayer - 1); changed() }
    func reorderLayer(_ offset: Int) { let next = selectedLayer + offset; guard layers.indices.contains(next) else { return }; checkpoint("Reorder layers"); layers.swapAt(selectedLayer, next); selectedLayer = next; changed() }
    func mergeDown() {
        guard selectedLayer > 0, let top = activeLayer, !top.locked, !layers[selectedLayer-1].locked else { return }
        let pair = [layers[selectedLayer-1], top]
        guard let image = Renderer.render(layers: pair, width: width, height: height), let data = try? Renderer.png(image) else { return }
        checkpoint("Merge layers"); var layer = ArtLayer(name: layers[selectedLayer-1].name); layer.imageData = data
        layers.replaceSubrange((selectedLayer-1)...selectedLayer, with: [layer]); selectedLayer -= 1; changed()
    }
    func addMask() { mutateLayer("Add mask") { $0.mask = [] }; maskEditing = true }
    func removeMask() { mutateLayer("Remove mask") { $0.mask = nil }; maskEditing = false }
    func addFrame() { stopPlayback(); checkpoint("Duplicate frame"); if frames.isEmpty { frames = [layers] }; frames[frameIndex] = layers; frames.insert(layers, at: frameIndex + 1); frameIndex += 1; changed() }
    func blankFrame() { addFrame(); layers = layers.map { var l = $0; l.strokes = []; l.imageData = nil; l.mask = nil; return l }; frames[frameIndex] = layers; changed() }
    func selectFrame(_ index: Int) {
        guard frames.indices.contains(index), index != frameIndex else { return }
        if frames.indices.contains(frameIndex) { frames[frameIndex] = layers }; frameIndex = index; layers = frames[index]; selectedLayer = min(selectedLayer, max(0, layers.count - 1)); selection = nil
    }
    func removeFrame() { guard frames.count > 1 else { return }; checkpoint("Delete frame"); frames.remove(at: frameIndex); frameIndex = min(frameIndex, frames.count - 1); layers = frames[frameIndex]; changed() }
    func togglePlayback() {
        if isPlaying { stopPlayback(); return }; guard frames.count > 1 else { return }
        frames[frameIndex] = layers; isPlaying = true
        playback = Timer.scheduledTimer(withTimeInterval: 1 / max(1, fps), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; if self.frameIndex + 1 >= self.frames.count && !self.loop { self.stopPlayback() } else { self.selectFrame((self.frameIndex + 1) % self.frames.count) } }
        }
    }
    func stopPlayback() { playback?.invalidate(); playback = nil; isPlaying = false }
    func fit() { zoom = 1; pan = .zero; rotation = 0; mirrored = false }
    func cycleColor() { let colors = Self.palette; let idx = colors.firstIndex(of: color) ?? -1; color = colors[(idx + 1) % colors.count] }
    static let palette = [CodableColor.black, .white, CodableColor(red: 0.47, green: 0.39, blue: 0.96, alpha: 1), CodableColor(red: 0.98, green: 0.38, blue: 0.43, alpha: 1), CodableColor(red: 1, green: 0.73, blue: 0.29, alpha: 1), CodableColor(red: 0.25, green: 0.76, blue: 0.65, alpha: 1), CodableColor(red: 0.27, green: 0.61, blue: 0.94, alpha: 1)]
    func apply(_ d: ArtDocument) { groups = d.groups ?? []; selectedIDs = []; width = d.width; height = d.height; documentName = d.title; layers = d.layers; frames = d.frames; fps = d.fps ?? 12; frameIndex = min(max(0,d.activeFrame ?? frames.firstIndex(of:d.layers) ?? 0), max(0, frames.count-1)); selectedLayer = min(selectedLayer, max(0, layers.count-1)); maskEditing = false; selection = nil }
    func syncTab() { if let i = tabs.firstIndex(where: { $0.id == tabID }) { tabs[i].document = document(); tabs[i].dirty = dirty; tabs[i].url = fileURL;tabs[i].undo = undoStack;tabs[i].redo = redoStack;tabs[i].saved = savedDocument } }
    func switchTab(_ id: UUID) { guard let tab = tabs.first(where: { $0.id == id }), id != tabID else { return }; stopPlayback(); syncTab(); tabID = id; apply(tab.document); fileURL = tab.url; dirty = tab.dirty; undoStack = tab.undo; redoStack = tab.redo; savedDocument = tab.saved ?? (tab.dirty ? nil : tab.document); fit() }
    func newDocument(width: Int = 1200, height: Int = 800) {
        stopPlayback(); syncTab(); tabID = UUID(); fileURL = nil; selectedLayer = 0; frameIndex = 0
        apply(ArtDocument(title: L("Untitled"), width: width, height: height, layers: [ArtLayer(name: L("Sketch"))])); dirty = false; savedDocument = document(); undoStack = []; redoStack = []; tabs.append(OpenArtwork(id: tabID, document: document(), url: nil)); fit()
    }
    func save(to url: URL? = nil) throws {
        guard let dest = url ?? fileURL else { throw StudioError.message("No save location was selected.") }
        var d = document(); d.title = dest.deletingPathExtension().lastPathComponent
        let data = try JSONEncoder.pretty.encode(d); try data.write(to: dest, options: .atomic)
        fileURL = dest; documentName = d.title; savedDocument = d; dirty = false; syncTab(); removeRecovery()
    }
    func open(_ url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count < 256 * 1024 * 1024 else { throw StudioError.message("The project exceeds the current 256 MB file limit.") }
        let d = try JSONDecoder().decode(ArtDocument.self, from: data)
        try Self.validate(d)
        stopPlayback(); syncTab(); tabID = UUID(); fileURL = url; frameIndex = 0; apply(d); selectedLayer = max(0,layers.count-1); dirty = false; savedDocument = d; undoStack = []; redoStack = []; tabs.append(OpenArtwork(id: tabID, document: d, url: url)); fit()
    }
    static func validate(_ d: ArtDocument) throws {
        guard (1...2).contains(d.version), (1...8192).contains(d.width), (1...8192).contains(d.height), !d.layers.isEmpty, d.layers.count <= 256, d.frames.count <= 10000 else { throw StudioError.message("Unsupported document version or invalid dimensions.") }
        guard d.width * d.height <= 64_000_000, (d.fps ?? 12).isFinite, (1...120).contains(d.fps ?? 12), (d.activeFrame ?? 0) >= 0, (d.frames.isEmpty || (d.activeFrame ?? 0) < d.frames.count) else { throw StudioError.message("Invalid animation data or image dimensions.") }
        func valid(_ layer: ArtLayer) -> Bool {
            let t = layer.transform, a = layer.adjustment
            return layer.opacity.isFinite && (0...1).contains(layer.opacity) && t.scale.isFinite && t.scale > 0 && t.scale <= 100 && t.x.isFinite && t.y.isFinite && t.rotation.isFinite && a.numbers.allSatisfy(\.isFinite) && (layer.style?.numbers ?? []).allSatisfy(\.isFinite) && layer.strokes.allSatisfy { stroke in stroke.width.isFinite && (0.1...10000).contains(stroke.width) && stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.pressure.isFinite } }
        }
        guard d.layers.allSatisfy(valid), d.frames.allSatisfy({ !$0.isEmpty && $0.count <= 256 && $0.allSatisfy(valid) }) else { throw StudioError.message("Invalid layer data.") }
    }
    func savePanel() { if let url = fileURL { do { try save(to:url) } catch { report(error) }; return }; saveAsPanel() }
    func saveAsPanel() { let p = NSSavePanel();p.title = L("Save project");p.prompt = L("Save"); p.allowedContentTypes = [.universePhoto]; p.nameFieldStringValue = documentName + ".universephoto"; if p.runModal() == .OK, let url = p.url { do { try save(to: url) } catch { report(error) } } }
    func openPanel() { let p = NSOpenPanel();p.title = L("Open project");p.prompt = L("Open"); p.allowedContentTypes = [.universePhoto, .json]; if p.runModal() == .OK, let url = p.url { do { try open(url) } catch { report(error) } } }
    func importPanel() { let p = NSOpenPanel();p.title = L("Import image as layer");p.prompt = L("Import"); p.allowedContentTypes = [.png, .jpeg, .tiff]; if p.runModal() == .OK, let url = p.url { do { let imported = try ImageFiles.importImage(url: url); checkpoint("Import image"); layers.append(imported.layer); selectedLayer = layers.count-1; changed() } catch { report(error) } } }
    func recoveryDirectory() -> URL { if let recoveryRoot { return recoveryRoot }; return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UniversePhoto/Recovery", isDirectory: true) }
    private func scheduleRecovery() {
        autosaveTask?.cancel(); guard dirty else { removeRecovery(); return }
        let d = document(), url = recoveryDirectory().appendingPathComponent(tabID.uuidString + ".universephoto")
        autosaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)); try await Task.detached(priority: .utility) { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(d).write(to: url, options: .atomic) }.value } catch is CancellationError { } catch { self?.report(error) }
        }
    }
    private func removeRecovery() { autosaveTask?.cancel(); let url = recoveryDirectory().appendingPathComponent(tabID.uuidString + ".universephoto"); if FileManager.default.fileExists(atPath:url.path) { do { try FileManager.default.removeItem(at:url) } catch { report(error) } } }
    func recoveryFiles() -> [URL] { ((try? FileManager.default.contentsOfDirectory(at: recoveryDirectory(), includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "universephoto" } }
    func restore(_ url: URL) { do { try open(url); fileURL = nil; dirty = true; syncTab() } catch { report(error) } }
    func closeTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if tab.dirty { let a = NSAlert(); a.messageText = L("Close unsaved document?"); a.informativeText = tab.document.title; a.addButton(withTitle: L("Cancel")); a.addButton(withTitle: L("Discard")); guard a.runModal() == .alertSecondButtonReturn else { return } }
        if tabID == id { removeRecovery() }; tabs.removeAll { $0.id == id }
        if id == tabID { if let next = tabs.first { let oldID = tabID; tabID = oldID; switchTab(next.id) } else { newDocument() } }
    }
    
}
enum StudioError: LocalizedError { case message(String); var errorDescription: String? { switch self { case .message(let s): L(s) } } }
import UniformTypeIdentifiers
extension UTType { static let universePhoto = UTType(exportedAs: "local.universephoto.document", conformingTo: .json) }
