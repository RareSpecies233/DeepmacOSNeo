import Foundation

/// QA / 演示用启动开关：`--demo` 自动发起一次对话，便于截屏与冒烟测试。
/// 正式使用不会触发。
enum DemoMode {
    static var isActive: Bool { CommandLine.arguments.contains("--demo") }

    static var origin: String {
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--origin=") }) {
            return String(arg.dropFirst("--origin=".count))
        }
        return "http://127.0.0.1:8787"
    }

    static var prompt: String {
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--prompt=") }) {
            return String(arg.dropFirst("--prompt=".count))
        }
        return "结合联网搜索，说明一下 DeepSeek 的深度思考模式是怎么工作的"
    }
}
