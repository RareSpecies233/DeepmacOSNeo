import Foundation

/// 解析门面：纯函数，可安全地在后台线程调用。
enum MarkdownParser {
    static func parse(_ text: String) -> MarkdownDocument {
        MarkdownBlockParser.parse(text)
    }
}

/// 解析调度 actor：保证解析不发生在主线程，并缓存最近一次结果
///（例如 SwiftUI 重建视图时避免重复解析同一段文本）。
actor MarkdownParseService {
    static let shared = MarkdownParseService()

    private var lastText: String?
    private var lastDocument: MarkdownDocument?

    func document(for text: String) async -> MarkdownDocument {
        if text == lastText, let cached = lastDocument {
            return cached
        }

        let parsed = await Task.detached(priority: .userInitiated) {
            MarkdownParser.parse(text)
        }.value

        lastText = text
        lastDocument = parsed
        return parsed
    }
}
