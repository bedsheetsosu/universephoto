// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UniverseStudio",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "UniverseStudio", targets: ["UniverseStudio"])],
    targets: [
        .executableTarget(name: "UniverseStudio", dependencies: ["UniversePenHost"], resources: [.copy("Resources/Localizable.xcstrings")]),
        // The former stand-alone UniversePen Host (Swift 5 language mode, as in its own project).
        .target(name: "UniversePenHost", dependencies: ["TafelKit", "CVirtualDisplay"],
                resources: [.copy("Resources/examples")], swiftSettings: [.swiftLanguageMode(.v5)]),
        // TafelKit (wire protocol, pairing, UltraUI), shared with the iPad app in UniversePen/ –
        // one copy of the sources, so both sides always speak the same protocol.
        .target(name: "TafelKit", path: "UniversePen/Packages/TafelKit/Sources/TafelKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        // Header for the private CGVirtualDisplay classes ("second screen" mode only).
        .target(name: "CVirtualDisplay"),
        .testTarget(name: "UniverseStudioTests", dependencies: ["UniverseStudio", "UniversePenHost"])
    ]
)
