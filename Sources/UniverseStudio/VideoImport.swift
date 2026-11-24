import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Animation → Import video for tracing… (0.97): a video becomes a locked, half-transparent
/// "Video" layer at the bottom of every frame – frame by frame at the animation's timing – with
/// extra frames added until the clip is covered (up to 600). Draw on the layers above.
enum VideoImport {
    static let maxFrames = 600

    /// Times (s) to grab for every frame: existing frames keep their timing, then one frame per
    /// tick until `duration` is covered. Also returns how many frames to add.
    static func plan(holds: [Int], fps: Double, duration: Double, cap: Int = maxFrames) -> (times: [Double], added: Int) {
        let f = max(1, fps)
        var times: [Double] = [], t = 0.0
        for h in holds { times.append(t); t += Double(max(1, h)) / f }
        var added = 0
        while t < duration - 0.5 / f && times.count < cap { times.append(t); t += 1 / f; added += 1 }
        return (times, added)
    }

    static func images(url: URL, times: [Double], maxSide: Int) async throws -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 120); gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 120)
        gen.maximumSize = CGSize(width: maxSide, height: maxSide)
        var out: [CGImage] = []
        for t in times { try Task.checkCancellation(); out.append(try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image) }
        return out
    }
}

extension Studio {
    /// Puts `images` (one per frame, existing frames first) into a new bottom layer "Video".
    @discardableResult func importVideoFrames(_ images: [CGImage], added: Int, name: String) -> Bool {
        guard !images.isEmpty else { return false }
        let pngs = images.compactMap { ImageFiles.fitted($0, width: width, height: height).flatMap { try? Renderer.png($0) } }
        guard pngs.count == images.count else { return false }
        stopPlayback(); checkpoint("Import video")
        if frames.isEmpty { frames = [layers] }
        frames[frameIndex] = layers
        if added > 0 {
            let template = frames[frames.count - 1].map { var l = $0; guard l.allFrames != true else { return l }; l.strokes = []; l.imageData = nil; l.mask = nil; return l }
            metaInsert(at: frames.count, holds: Array(repeating: 1, count: added))
            frames.append(contentsOf: Array(repeating: template, count: added))
        }
        var video = ArtLayer(name: name); video.opacity = 0.5; video.locked = true
        frames = frames.enumerated().map { i, f in
            var l = video; l.imageData = pngs.indices.contains(i) ? pngs[i] : nil
            return [l] + f
        }
        selectedLayer += 1
        layers = frames[frameIndex]
        changed()
        return true
    }

    func importVideoPanel() {
        let p = NSOpenPanel(); p.title = L("Import video for tracing"); p.prompt = L("Import"); p.allowedContentTypes = [.movie]
        guard p.runModal() == .OK, let url = p.url else { return }
        let holds = frames.isEmpty ? [1] : (0..<frames.count).map { hold($0) }
        let fps = fps, side = max(width, height)
        busy = true
        Task {
            defer { busy = false }
            do {
                let duration = try await AVURLAsset(url: url).load(.duration).seconds
                let plan = VideoImport.plan(holds: holds, fps: fps, duration: duration)
                let images = try await VideoImport.images(url: url, times: plan.times, maxSide: side)
                if !importVideoFrames(images, added: plan.added, name: L("Video") + " · " + url.deletingPathExtension().lastPathComponent) {
                    report(StudioError.message("The video could not be read."))
                }
            } catch { report(error) }
        }
    }
}
