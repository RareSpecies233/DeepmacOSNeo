import SwiftUI

/// 助手正文容器。
/// 解析结果按「文本」做进程内缓存，流式期间每帧只增加一次 O(n) 解析，
/// 已完成消息则直接命中缓存，不重复解析。
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
        if let hit = storage[text] {
            lock.unlock()
            return hit
        }
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
