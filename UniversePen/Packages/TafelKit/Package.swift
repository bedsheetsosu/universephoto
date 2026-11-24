// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TafelKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "TafelKit", targets: ["TafelKit"]),
    ],
    targets: [
        .target(name: "TafelKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "TafelKitTests", dependencies: ["TafelKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
