// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UniverseStudio",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "UniverseStudio", targets: ["UniverseStudio"])],
    targets: [
        .executableTarget(name: "UniverseStudio", resources: [.copy("Resources/Localizable.xcstrings")]),
        .testTarget(name: "UniverseStudioTests", dependencies: ["UniverseStudio"])
    ]
)
