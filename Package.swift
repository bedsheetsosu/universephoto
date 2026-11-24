// swift-tools-version:6.0
// Root manifest so other packages (UniverseStudio) can depend on this repository by URL.
// The Xcode project keeps using Packages/TafelKit directly; both point at the same sources.
import PackageDescription

let package = Package(
    name: "UniversePen",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TafelKit", targets: ["TafelKit"]),
    ],
    targets: [
        .target(name: "TafelKit", path: "Packages/TafelKit/Sources/TafelKit", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
