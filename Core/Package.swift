// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeepSeekKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "DeepSeekKit", targets: ["DeepSeekKit"])],
    targets: [
        .target(name: "DeepSeekKit"),
        .testTarget(name: "DeepSeekKitTests", dependencies: ["DeepSeekKit"]),
    ]
)
