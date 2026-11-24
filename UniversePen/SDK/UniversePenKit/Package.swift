// swift-tools-version: 5.9
// UniversePenKit – client for the UniversePen developer API. MIT licensed (see ../LICENSE).
import PackageDescription

let package = Package(
    name: "UniversePenKit",
    platforms: [.macOS(.v13)],
    products: [.library(name: "UniversePenKit", targets: ["UniversePenKit"])],
    targets: [.target(name: "UniversePenKit")]
)
