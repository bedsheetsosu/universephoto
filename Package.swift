// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UniverseStudio",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "UniverseStudio", targets: ["UniverseStudio"])],
    dependencies: [
        // TafelKit (wire protocol, pairing, UltraUI) comes from the UniversePen repository, so the
        // iPad app and the host built into the studio always speak the same protocol.
        .package(url: "https://github.com/bedsheetsosu/universepen.git", branch: "main"),
    ],
    targets: [
        .executableTarget(name: "UniverseStudio", dependencies: ["UniversePenHost"], resources: [.copy("Resources/Localizable.xcstrings")]),
        // The former stand-alone UniversePen Host (Swift 5 language mode, as in its own project).
        .target(name: "UniversePenHost", dependencies: [.product(name: "TafelKit", package: "universepen"), "CVirtualDisplay"],
                resources: [.copy("Resources/examples")], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Header for the private CGVirtualDisplay classes ("second screen" mode only).
        .target(name: "CVirtualDisplay"),
        .testTarget(name: "UniverseStudioTests", dependencies: ["UniverseStudio", "UniversePenHost"])
    ]
)
