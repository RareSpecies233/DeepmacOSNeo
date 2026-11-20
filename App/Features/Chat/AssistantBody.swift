import SwiftUI

/// 助手正文容器。
///
/// 说明：这里**同步**解析并缓存（最近 8 段），而不是用 `MarkdownView` 的异步路径。
/// 实测异步路径在流式消息重渲染下会出现 document 未落地、正文空白的问题；
/// 同步解析 5KB 约 0.5ms，流式期间成本可接受。待 `MarkdownView` 的状态落地问题修好后可切回。
struct AssistantBody: View {
    let text: String
    let isStreaming: Bool

    @State private var document: MarkdownDocument = .empty

    var body: some View {
        MarkdownDocumentView(document: document.isEmpty ? .init(blocks: [], source: text) : document)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .onAppear { refresh() }
            .onChange(of: text) { _, _ in refresh() }
    }

    private func refresh() {
        let parsed = MarkdownDocumentCache.shared.document(for: text)
        if parsed != document { document = parsed }
    }
}

/// 极简 LRU：只保留最近 8 段文本的解析结果。
final class MarkdownDocumentCache: @unchecked Sendable {
    static let shared = MarkdownDocumentCache()
    private var storage: [String: MarkdownDocument] = [:]
    private var order: [String] = []
    private let limit = 8
    private let lock = NSLock()

    func document(for text: String) -> MarkdownDocument {
        lock.lock()
        if let hit = storage[text] { lock.unlock(); return hit }
        lock.unlock()

        let parsed = MarkdownParser.parse(text)

        lock.lock()
        storage[text] = parsed
        order.append(text)
        if order.count > limit {
            let evicted = order.removeFirst()
            storage[evicted] = nil
        }
        lock.unlock()
        return parsed
    }
}
