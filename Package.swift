// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UniversePhoto",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "UniversePhoto", targets: ["UniversePhoto"])],
    targets: [
        .executableTarget(name: "UniversePhoto", resources: [.copy("Resources/Localizable.xcstrings")]),
        .testTarget(name: "UniversePhotoTests", dependencies: ["UniversePhoto"])
    ]
)
