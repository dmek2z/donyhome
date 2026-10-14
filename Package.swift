// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DonyHome",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DonyHome", targets: ["DonyClean"])],
    dependencies: [.package(url: "https://github.com/krisk/fuse-swift", exact: "1.4.0")],
    targets: [
        .target(name: "DonySystemBridge", publicHeadersPath: "include"),
        .target(name: "DonyCore", dependencies: ["DonySystemBridge", .product(name: "Fuse", package: "fuse-swift")]),
        .executableTarget(name: "DonyClean", dependencies: ["DonyCore"]),
        .testTarget(name: "DonyCoreTests", dependencies: ["DonyCore"]),
        .testTarget(name: "DonyCleanTests", dependencies: ["DonyClean"])
    ]
)
