// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WinnowCore",
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [.library(name: "WinnowCore", targets: ["WinnowCore"])],
    targets: [
        .target(name: "WinnowCore"),
        .testTarget(name: "WinnowCoreTests", dependencies: ["WinnowCore"]),
    ]
)
