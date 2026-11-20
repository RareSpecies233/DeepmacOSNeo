import Foundation

public enum DeepSeekError: Error, LocalizedError, Sendable {
    case http(status: Int, message: String)
    case stream(String)
    case network(String)
    case interrupted
    case protocolViolation(String)

    public var errorDescription: String? {
        switch self {
        case let .http(status, message):
            if message.isEmpty {
                return "请求失败（HTTP \(status)），请稍后重试。"
            }
            return "请求失败（HTTP \(status)）：\(message)"
        case let .stream(message):
            if message.isEmpty {
                return "生成被服务端中断，请重试。"
            }
            return "生成被中断：\(message)"
        case let .network(message):
            if message.isEmpty {
                return "网络连接失败，请检查网络后重试。"
            }
            return "网络连接失败：\(message)"
        case .interrupted:
            return "连接意外中断，回答可能不完整，请重试。"
        case let .protocolViolation(message):
            if message.isEmpty {
                return "服务返回了无法识别的响应。"
            }
            return "响应格式异常：\(message)"
        }
    }
}
