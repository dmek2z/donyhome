// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DonyClean",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DonyClean", targets: ["DonyClean"])],
    targets: [
        .target(name: "DonySystemBridge", publicHeadersPath: "include"),
        .target(name: "DonyCore", dependencies: ["DonySystemBridge"]),
        .executableTarget(name: "DonyClean", dependencies: ["DonyCore"]),
        .testTarget(name: "DonyCoreTests", dependencies: ["DonyCore"])
    ]
)
