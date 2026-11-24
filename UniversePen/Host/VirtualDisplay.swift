import Foundation
import CoreGraphics
import ObjectiveC

/// An extra, virtual Mac display in the iPad's resolution ("second screen" like Sidecar).
///
/// ⚠️ Uses the PRIVATE `CGVirtualDisplay` API (see Private/CGVirtualDisplayPrivate.h). It is the
/// only private API in Tafel and only used when the user picks "Zweiter Bildschirm". The display
/// disappears when this object is released (or the app quits); macOS then moves its windows back.
final class VirtualDisplay {
    // MARK: Runtime check (private API may change with any macOS update)

    struct Availability {
        let isAvailable: Bool
        /// "Class" or "Class -selector" entries that are missing.
        let missing: [String]
    }

    /// Everything Tafel calls, per class. Checked once before the first use.
    private static let required: [(cls: String, selectors: [String])] = [
        ("CGVirtualDisplayDescriptor", ["init", "setDispatchQueue:", "setName:", "setMaxPixelsWide:", "setMaxPixelsHigh:",
                                        "setSizeInMillimeters:", "setProductID:", "setVendorID:", "setSerialNum:",
                                        "setTerminationHandler:"]),
        ("CGVirtualDisplayMode", ["initWithWidth:height:refreshRate:", "width", "height"]),
        ("CGVirtualDisplaySettings", ["init", "setModes:", "setHiDPI:"]),
        ("CGVirtualDisplay", ["initWithDescriptor:", "applySettings:", "displayID"]),
    ]

    static let availability: Availability = {
        var missing: [String] = []
        for (name, selectors) in required {
            guard let cls = NSClassFromString(name) else { missing.append(name); continue }
            for sel in selectors where !cls.instancesRespond(to: NSSelectorFromString(sel)) {
                missing.append("\(name) -\(sel)")
            }
        }
        if !missing.isEmpty { logWhatExists(missing: missing) }
        return Availability(isAvailable: missing.isEmpty, missing: missing)
    }()

    /// On mismatch, log what this macOS actually offers – that is what an update of
    /// CGVirtualDisplayPrivate.h needs.
    private static func logWhatExists(missing: [String]) {
        NSLog("Tafel: second screen unavailable on %@ – missing: %@",
              ProcessInfo.processInfo.operatingSystemVersionString, missing.joined(separator: ", "))
        for (name, _) in required {
            guard let cls = NSClassFromString(name) else { continue }
            var count: UInt32 = 0
            guard let list = class_copyMethodList(cls, &count) else { continue }
            let names = (0..<Int(count)).map { NSStringFromSelector(method_getName(list[$0])) }.sorted()
            free(list)
            NSLog("Tafel: %@ methods: %@", name, names.joined(separator: " "))
        }
    }

    let pixelWidth: Int
    let pixelHeight: Int
    private var display: CGVirtualDisplay?

    var displayID: CGDirectDisplayID { display?.displayID ?? 0 }

    /// `pixelWidth/Height`: the iPad's full-screen pixels. The display runs HiDPI (2×), so it
    /// has the iPad's point size – UI comes out at the same physical size as on the iPad.
    init?(pixelWidth: Int, pixelHeight: Int, name: String = "UniversePen (iPad)") {
        guard Self.availability.isAvailable else { return nil }
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        let w = UInt32(pixelWidth), h = UInt32(pixelHeight)

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.setDispatchQueue(DispatchQueue.main)
        descriptor.name = name
        // Room for the largest HiDPI mode (2× its point size), so "more space" stays sharp.
        let top = Self.scales.last!
        descriptor.maxPixelsWide = UInt32((Double(w) * top).rounded(.up)) + 2
        descriptor.maxPixelsHigh = UInt32((Double(h) * top).rounded(.up)) + 2
        // Physical size of an 11" iPad panel, so macOS picks a sensible default scale.
        let landscape = pixelWidth >= pixelHeight
        descriptor.sizeInMillimeters = landscape ? CGSize(width: 229, height: 159) : CGSize(width: 159, height: 229)
        descriptor.vendorID = 0x7AFE
        descriptor.productID = 0x0001
        descriptor.serialNum = 0x0001
        descriptor.terminationHandler = { _, _ in }

        guard let d = CGVirtualDisplay(descriptor: descriptor) else { return nil }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        // HiDPI modes (sizes in points, macOS renders them at 2×): the iPad's own point size and
        // steps with more space, all in the iPad's aspect ratio. The stream is scaled to the iPad.
        settings.modes = Self.scales.map { f in
            let (mw, mh) = Self.pointSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: f)
            return CGVirtualDisplayMode(width: UInt32(mw), height: UInt32(mh), refreshRate: 60)
        }
        guard d.apply(settings) else { return nil }
        display = d
        selectMode(scale: Self.preferredScale)
    }

    /// "More space" steps: points relative to the iPad's own point size (pixels / 2).
    static let scales: [Double] = [1.0, 1.125, 1.25, 1.4, 1.6]

    /// Point size of a mode, even numbers, iPad aspect ratio.
    static func pointSize(pixelWidth: Int, pixelHeight: Int, scale: Double) -> (Int, Int) {
        func even(_ v: Double) -> Int { Int((v / 2).rounded()) * 2 }
        return (even(Double(pixelWidth) / 2 * scale), even(Double(pixelHeight) / 2 * scale))
    }

    /// Step the user picked last (System Settings → Displays), restored on the next connection.
    static var preferredScale: Double {
        get { UserDefaults.standard.object(forKey: "virtualDisplayScale") as? Double ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: "virtualDisplayScale") }
    }

    /// Current step of this display (nil if macOS runs it in a mode that is not one of ours).
    var currentScale: Double? {
        guard let m = CGDisplayCopyDisplayMode(displayID) else { return nil }
        return Self.scales.first { Self.pointSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: $0).0 == m.width }
    }

    /// Picks the HiDPI mode of a step (public CGDisplay API); a low-resolution mode would be blurry.
    private func selectMode(scale: Double) {
        let id = displayID
        let pw = Self.pointSize(pixelWidth: pixelWidth, pixelHeight: pixelHeight, scale: scale).0
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode],
              let mode = modes.first(where: { $0.width == pw && $0.pixelWidth == pw * 2 })
                ?? modes.first(where: { $0.width == pixelWidth / 2 && $0.pixelWidth == pixelWidth }) else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
        CGCompleteDisplayConfiguration(config, .forSession)
    }

    deinit {
        display = nil
    }
}
