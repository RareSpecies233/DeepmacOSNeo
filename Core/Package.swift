// swift-tools-version: 6.0
import PackageDescription

/// DeepSeekKit —— DeepGlass 的 Core 层：纯 Foundation 的协议类型、SSE 解析、请求编码与流式客户端。
/// 同一份源码既作为独立 SPM 包运行 `swift test`，也会被 xcodeproj 直接编入 App target，
/// 因此：不 import 自身、不含 `@main`、没有顶层可执行语句、不依赖任何 UI 框架。
let package = Package(
    name: "DeepSeekKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "DeepSeekKit", targets: ["DeepSeekKit"]),
    ],
    targets: [
        .target(
            name: "DeepSeekKit",
            path: "Sources/DeepSeekKit"
        ),
        .testTarget(
            name: "DeepSeekKitTests",
            dependencies: ["DeepSeekKit"],
            path: "Tests/DeepSeekKitTests"
        ),
    ]
)
