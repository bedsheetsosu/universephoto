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
    @Published var layers = Studio.startLayers(background: Studio.preferredBackground)
    @Published var selectedLayer = Studio.preferredBackground == nil ? 0 : 1
    /// Background of new documents (Preferences / new-document sheet): white by default, or transparent.
    static var preferredBackground: CodableColor? { UserDefaults.standard.string(forKey: "documentBackground") == "transparent" ? nil : .white }
    /// A filled "Background" layer under the first drawing layer (nil colour = transparent, one layer).
    static func startLayers(background: CodableColor?) -> [ArtLayer] {
        guard let background else { return [ArtLayer(name: L("Sketch"))] }
        var bg = ArtLayer(name: L("Background"))
        var fill = InkStroke(points: [InkPoint(x: 0, y: 0, pressure: 1)], color: background, width: 1); fill.kind = "fill"
        bg.strokes = [fill]
        return [bg, ArtLayer(name: L("Sketch"))]
    }
    /// Further selected layers (Shift/⌘-click in the list); the active one is `selectedLayer`.
    @Published var selectedIDs: Set<UUID> = []
    @Published var groups: [LayerGroup] = []
    /// Free transform (⌘T): handles around the active layer's content.
    @Published var transformMode = false
    var boundsCache: [String: CGRect] = [:]
    /// Text tool: font family and weight.
    @Published var fontFamily = "Helvetica"
    @Published var textBold = false
    @Published var textItalic = false
    @Published var recentColors: [CodableColor] = []
    @Published var guides: [Guide] = []
    @Published var showGuides = true
    @Published var guidesLocked = false
    @Published var snapToGuides = true
    @Published var guideDialog = false
    @Published var textAlign = TextAlign.left
    @Published var textTracking = 0.0
    @Published var textLineSpacing = 1.2
    @Published var color = CodableColor.black
    @Published var secondaryColor = CodableColor.white
    /// Gradient tool: linear, radial or reflected (mirrored around the start point).
    @Published var gradientStyle = GradientStyle.linear
    /// Rectangle tool: which shape, its value (corner radius / corners / points), filled or outlined.
    @Published var shapeStyle = ShapeStyle.rectangle
    @Published var shapeParameter = 6.0
    @Published var shapeFill = false
    @Published var brushTip = BrushTip.round
    /// Line tool: arrow head at the end.
    @Published var lineArrow = false
    @Published var brushSize = 12.0
    @Published var brushOpacity = 1.0
    @Published var smoothing = 0.15
    @Published var pressureEnabled = true
    /// Stylus pressure → stroke pressure (any tablet and the UniversePen Pencil). Kept per Mac.
    @Published var pressureCurve: [CurvePoint] = Studio.loadPressureCurve() { didSet { Studio.savePressureCurve(pressureCurve) } }
    func mapPressure(_ p: Double) -> Double { pressureEnabled ? max(0.02, ToneCurve.evaluate(pressureCurve, at: p)) : 1 }
    static func loadPressureCurve() -> [CurvePoint] {
        (UserDefaults.standard.data(forKey: "pressureCurve")).flatMap { try? JSONDecoder().decode([CurvePoint].self, from: $0) } ?? ToneCurve.identity
    }
    static func savePressureCurve(_ c: [CurvePoint]) { UserDefaults.standard.set(try? JSONEncoder().encode(c), forKey: "pressureCurve") }
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
    @Published var textContent = "UniverseStudio"
    /// Active part of UniverseStudio; nil shows the start screen.
    @Published var module: StudioModule? = UserDefaults.standard.object(forKey: "startScreenAtLaunch") as? Bool == false ? .photo : nil
    @Published var showNewDocument = false
    @Published var imageDialog: ImageDialog?
    @Published var selectionDialog: SelectionModify?
    @Published var strokeSelectionDialog = false
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
        return ArtDocument(title: documentName, width: width, height: height, layers: layers, frames: currentFrames, fps: fps, activeFrame: frameIndex, groups: groups.isEmpty ? nil : groups, guides: guides.isEmpty ? nil : guides)
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
        if stroke.kind == "liquify" { finishLiquify(stroke); return }
        guard canEdit else { return }; checkpoint(tool.english)
        if !stroke.isEraser, stroke.kind != "bitmap", !maskEditing { rememberColor(stroke.color) }
        var stroke = bakeRetouch(stroke)
        if activeLayer?.lockAlpha == true, !maskEditing, !stroke.isEraser, activeLayer?.isAdjustmentLayer != true { stroke.atop = true }
        if activeLayer?.isAdjustmentLayer == true { layers[selectedLayer].mask = (layers[selectedLayer].mask ?? []) + [stroke] }   // paints its mask
        else if activeLayer?.mask != nil && maskEditing { layers[selectedLayer].mask?.append(stroke) } else { layers[selectedLayer].strokes.append(stroke) }
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
    var liquifyState: LiquifyState?
    var liquifyTimer: Timer?
    /// Lets the canvas redraw after a timer tick (twirl and friends change pixels without mouse events).
    var liquifyChanged: (() -> Void)?
    @Published var liquifyMode = LiquifyMode.push
    /// The pen tool's path in document pixels (not part of the document until filled or stroked).
    @Published var penPath: PenPath?
    /// The crop tool's frame (document pixels), nil when none is drawn.
    @Published var cropRect: CGRect?
    /// The text stroke (active layer) the text tool is editing, nil when the next click places new text.
    @Published var editingText: UUID?
    /// The finished path (active layer) the pen tool has reopened, nil for a new path.
    @Published var editingPath: UUID?
    @Published var symmetry = Symmetry.off
    /// Quick mask layer while the mode is on, and the layer to return to.
    @Published var quickMaskLayer: UUID?
    var quickMaskReturn = 0
    @Published var symmetrySegments = 6
    /// Symmetry centre in document pixels (nil = canvas centre); the next click sets it while `settingSymmetryCenter`.
    @Published var symmetryCenter: CGPoint?
    @Published var settingSymmetryCenter = false
    /// Visible colour under the pointer (status bar).
    @Published var hoverColor: CodableColor?
    @Published var showShortcuts = false
    /// Transform selection: the frame (document pixels) and the selection with its box at the start.
    @Published var selectionFrame: CGRect?
    var selectionFrameOriginal: (CanvasSelection, CGRect)?
    @Published var pressureOpacity = UserDefaults.standard.bool(forKey: "pressureOpacity") { didSet { UserDefaults.standard.set(pressureOpacity, forKey: "pressureOpacity") } }
    /// Distort: the four corners (document pixels, TL TR BR BL) while it runs, and what it warps.
    @Published var distortCorners: [CGPoint]?
    var distortSource: CGImage?
    var distortBounds: CGRect?
    var distortStroke: InkStroke?
    var symmetryPivot: CGPoint { symmetryCenter ?? CGPoint(x: Double(width) / 2, y: Double(height) / 2) }
    /// The system pasteboard; tests use a private one so they never touch the user's clipboard.
    var pasteboard = NSPasteboard.general
    /// Jumps to the state after history step `count` (0 = before the first step), undoing or redoing.
    func jumpToHistory(_ count: Int) {
        while undoStack.count > max(0, count) { undo() }
        while undoStack.count < count, !redoStack.isEmpty { redo() }
    }
    func undo() {
        stopPlayback(); guard let last = undoStack.popLast() else { return }
        redoStack.append(HistoryEntry(document: document(), label: last.label)); apply(last.document); changed()
    }
    func redo() {
        stopPlayback(); guard let last = redoStack.popLast() else { return }
        undoStack.append(HistoryEntry(document: document(), label: last.label)); apply(last.document); changed()
    }
    /// A new adjustment layer above the active one; painting on it paints its mask.
    func newAdjustmentLayer() {
        checkpoint("New adjustment layer")
        var l = ArtLayer(name: L("Adjustment") + " \(layers.count + 1)"); l.adjustsBelow = true; l.mask = []
        layers.insert(l, at: min(selectedLayer + 1, layers.count)); selectedLayer = min(selectedLayer + 1, layers.count - 1); maskEditing = true; changed()
    }
    func newLayer() { checkpoint("New layer"); layers.insert(ArtLayer(name: L("Layer") + " \(layers.count + 1)"), at: min(selectedLayer + 1, layers.count)); selectedLayer = min(selectedLayer + 1, layers.count - 1); maskEditing = false; changed() }
    func duplicateLayer() { guard var copy = activeLayer else { return }; checkpoint("Duplicate layer"); copy.id = UUID(); copy.name += L(" copy"); layers.insert(copy, at: selectedLayer + 1); selectedLayer += 1; changed() }
    func deleteLayer() { guard layers.count > 1, activeLayer?.locked == false else { return }; checkpoint("Delete layer"); layers.remove(at: selectedLayer); selectedLayer = max(0, selectedLayer - 1); changed() }
    func reorderLayer(_ offset: Int) { let next = selectedLayer + offset; guard layers.indices.contains(next) else { return }; checkpoint("Reorder layers"); layers.swapAt(selectedLayer, next); selectedLayer = next; changed() }
    func mergeDown() {
        guard selectedLayer > 0, let top = activeLayer, !top.locked, !layers[selectedLayer-1].locked, !top.isAdjustmentLayer, !layers[selectedLayer-1].isAdjustmentLayer else { return }
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
    func apply(_ d: ArtDocument) { groups = d.groups ?? []; guides = d.guides ?? []; selectedIDs = []; width = d.width; height = d.height; documentName = d.title; layers = d.layers; frames = d.frames; fps = d.fps ?? 12; frameIndex = min(max(0,d.activeFrame ?? frames.firstIndex(of:d.layers) ?? 0), max(0, frames.count-1)); selectedLayer = min(selectedLayer, max(0, layers.count-1)); maskEditing = false; selection = nil }
    func syncTab() { if let i = tabs.firstIndex(where: { $0.id == tabID }) { tabs[i].document = document(); tabs[i].dirty = dirty; tabs[i].url = fileURL;tabs[i].undo = undoStack;tabs[i].redo = redoStack;tabs[i].saved = savedDocument } }
    func switchTab(_ id: UUID) { guard let tab = tabs.first(where: { $0.id == id }), id != tabID else { return }; stopPlayback(); syncTab(); tabID = id; apply(tab.document); fileURL = tab.url; dirty = tab.dirty; undoStack = tab.undo; redoStack = tab.redo; savedDocument = tab.saved ?? (tab.dirty ? nil : tab.document); fit() }
    func newDocument(width: Int = 1200, height: Int = 800, background: CodableColor? = nil) {
        stopPlayback(); syncTab(); tabID = UUID(); fileURL = nil; selectedLayer = background == nil ? 0 : 1; frameIndex = 0
        apply(ArtDocument(title: L("Untitled"), width: width, height: height, layers: Self.startLayers(background: background))); dirty = false; savedDocument = document(); undoStack = []; redoStack = []; tabs.append(OpenArtwork(id: tabID, document: document(), url: nil)); fit()
    }
    func save(to url: URL? = nil) throws {
        guard let dest = url ?? fileURL else { throw StudioError.message("No save location was selected.") }
        var d = document(); d.title = dest.deletingPathExtension().lastPathComponent
        let data = try JSONEncoder.pretty.encode(d); try data.write(to: dest, options: .atomic)
        fileURL = dest; documentName = d.title; savedDocument = d; dirty = false; syncTab(); removeRecovery()
    }
    func open(_ url: URL) throws {
        module = .photo
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count < 256 * 1024 * 1024 else { throw StudioError.message("The project exceeds the current 256 MB file limit.") }
        let isPSD = url.pathExtension.lowercased() == "psd"
        let d = isPSD ? try PSD.read(data, title: url.deletingPathExtension().lastPathComponent) : try JSONDecoder().decode(ArtDocument.self, from: data)
        try Self.validate(d)
        // A Photoshop file opens as a new project: saving asks for a .universephoto name.
        stopPlayback(); syncTab(); tabID = UUID(); fileURL = isPSD ? nil : url; frameIndex = 0; apply(d); selectedLayer = max(0,layers.count-1); dirty = false; savedDocument = d; undoStack = []; redoStack = []; tabs.append(OpenArtwork(id: tabID, document: d, url: url)); fit()
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
    func openPanel() { let p = NSOpenPanel();p.title = L("Open project");p.prompt = L("Open"); p.allowedContentTypes = [.universePhoto, .json, PSD.type]; if p.runModal() == .OK, let url = p.url { do { try open(url) } catch { report(error) } } }
    func importPanel() { let p = NSOpenPanel();p.title = L("Import image as layer");p.prompt = L("Import"); p.allowedContentTypes = ImageFiles.supportedImports; if p.runModal() == .OK, let url = p.url { do { let imported = try ImageFiles.importImage(url: url); checkpoint("Import image"); layers.append(imported.layer); selectedLayer = layers.count-1; changed() } catch { report(error) } } }
    func recoveryDirectory() -> URL { if let recoveryRoot { return recoveryRoot }; return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(AppMigration.supportFolder + "/Recovery", isDirectory: true) }
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
        if id == tabID { if let next = tabs.first { let oldID = tabID; tabID = oldID; switchTab(next.id) } else { newDocument(background: Self.preferredBackground) } }
    }
    
}
enum StudioError: LocalizedError { case message(String); var errorDescription: String? { switch self { case .message(let s): L(s) } } }
import UniformTypeIdentifiers
extension UTType { static let universePhoto = UTType(exportedAs: "local.universephoto.document", conformingTo: .json) }
