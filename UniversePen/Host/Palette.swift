import AppKit
import ScreenCaptureKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import TafelKit

/// A small, slow live picture of one Mac area (e.g. a layers or colour panel) for the floating
/// palette window on the iPad. JPEG frames at up to 10 fps, and only when the area changes
/// (ScreenCaptureKit sends nothing for a still picture).
final class PaletteCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onJPEG: ((Data) -> Void)?
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "tafel.palette", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

    /// Longest side of the sent picture in pixels.
    static let maxPixels = 900

    /// `localRect`: points inside `display`, top-left origin.
    func start(display: SCDisplay, localRect: CGRect) async throws {
        await stop()
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = CGFloat(filter.pointPixelScale)
        let px = CGSize(width: localRect.width * scale, height: localRect.height * scale)
        let fit = min(1, CGFloat(Self.maxPixels) / max(px.width, px.height, 1))
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = localRect
        cfg.width = max(Int(px.width * fit), 16)
        cfg.height = max(Int(px.height * fit), 16)
        cfg.captureResolution = .best
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.colorSpaceName = CGColorSpace.displayP3
        cfg.showsCursor = false
        cfg.queueDepth = 3
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
    }

    func stop() async {
        guard let s = stream else { return }
        stream = nil
        try? await s.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pb = sb.imageBuffer, Self.isComplete(sb) else { return }
        let image = CIImage(cvPixelBuffer: pb)
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else { return }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return }
        onJPEG?(data as Data)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Tafel: palette capture stopped: %@", error.localizedDescription)
    }

    private static func isComplete(_ sb: CMSampleBuffer) -> Bool {
        guard let att = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = att.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}

/// Full-screen overlay on every display: drag out a rectangle (Esc cancels). Result in global
/// display coordinates (points, top-left origin, like CGDisplayBounds).
@MainActor
final class PalettePicker {
    private var windows: [NSWindow] = []
    private var monitor: Any?
    private var done: ((CGRect?) -> Void)?

    func run(_ completion: @escaping (CGRect?) -> Void) {
        cancel()
        done = completion
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = PickerView(frame: CGRect(origin: .zero, size: screen.frame.size))
            v.onDone = { [weak self, weak w] rectInView in
                guard let self else { return }
                guard let rectInView, let w else { self.finish(nil); return }
                let onScreen = w.convertToScreen(rectInView)
                self.finish(Self.toGlobalTopLeft(onScreen))
            }
            w.contentView = v
            w.makeKeyAndOrderFront(nil)
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.finish(nil); return nil }   // Esc
            return e
        }
    }

    func cancel() {
        guard done != nil else { return }
        finish(nil)
    }

    private func finish(_ rect: CGRect?) {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NSCursor.pop()
        let d = done
        done = nil
        d?(rect)
    }

    /// Cocoa screen coordinates (bottom-left origin) → global top-left coordinates.
    static func toGlobalTopLeft(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? r.maxY
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private final class PickerView: NSView {
        var onDone: ((CGRect?) -> Void)?
        private var start: CGPoint?
        private var current: CGPoint?

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with e: NSEvent) { start = convert(e.locationInWindow, from: nil); current = start; needsDisplay = true }
        override func mouseDragged(with e: NSEvent) { current = convert(e.locationInWindow, from: nil); needsDisplay = true }
        override func mouseUp(with e: NSEvent) {
            current = convert(e.locationInWindow, from: nil)
            guard let r = selection, r.width >= 24, r.height >= 24 else { start = nil; needsDisplay = true; return }
            onDone?(r)
        }

        private var selection: CGRect? {
            guard let a = start, let b = current else { return nil }
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.35).setFill()
            bounds.fill()
            let hint = L("Bereich für die Palette auf dem iPad aufziehen – Esc bricht ab") as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white]
            let size = hint.size(withAttributes: attrs)
            hint.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 90), withAttributes: attrs)
            guard let r = selection else { return }
            NSColor.clear.setFill()
            r.fill(using: .copy)
            let path = NSBezierPath(rect: r)
            path.lineWidth = 2
            NSColor(Brand.mint).setStroke()
            path.stroke()
        }
    }
}
