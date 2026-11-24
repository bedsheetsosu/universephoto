import AppKit
import TafelKit

/// Mac side of the clipboard copy. Only runs when the user taps "copy to/from Mac" on the iPad.
enum MacClipboard {
    static func read() -> ClipboardItem {
        let pb = NSPasteboard.general
        // Images first: copying an image in most apps also puts a file name or title as text.
        if let png = pb.data(forType: .png), png.count <= ClipboardItem.maxBytes {
            return ClipboardItem(kind: .png, data: png)
        }
        if let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]),
           png.count <= ClipboardItem.maxBytes, pb.string(forType: .string) == nil {
            return ClipboardItem(kind: .png, data: png)
        }
        if let s = pb.string(forType: .string), !s.isEmpty {
            return .text(s)
        }
        return ClipboardItem(kind: .empty)
    }

    static func write(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text:
            guard let t = item.text else { return }
            pb.clearContents()
            pb.setString(t, forType: .string)
        case .png:
            pb.clearContents()
            pb.setData(item.data, forType: .png)
            if let tiff = NSImage(data: item.data)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        case .empty:
            break
        }
    }
}
