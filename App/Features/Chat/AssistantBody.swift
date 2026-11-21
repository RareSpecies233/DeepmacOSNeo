import SwiftUI

/// 正文里的一枚引用角标：number 是它在来源面板里的编号（从 1 开始）。
struct CitationBadge: Hashable {
    let number: Int
    let url: String
    let citedText: String
}

/// 助手正文容器。
///
/// 说明：这里**同步**解析并缓存（最近 8 段），而不是用 `MarkdownView` 的异步路径。
/// 实测异步路径在流式消息重渲染下会出现 document 未落地、正文空白的问题；
/// 同步解析 5KB 约 0.5ms，流式期间成本可接受。待 `MarkdownView` 的状态落地问题修好后可切回。
struct AssistantBody: View {
    let text: String
    var badges: [CitationBadge] = []
    var onOpenCitation: ((Int) -> Void)?
    let isStreaming: Bool

    @State private var document: MarkdownDocument = .empty

    /// 角标以自定义 scheme 的 Markdown 链接插入正文，点击时由 openURL 拦截。
    private var sourceText: String {
        CitationMarkdown.annotate(text, badges: badges)
    }

    var body: some View {
        MarkdownDocumentView(document: document.isEmpty ? .init(blocks: [], source: sourceText) : document)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard let number = CitationMarkdown.number(from: url) else {
                    return .systemAction
                }
                onOpenCitation?(number)
                return .handled
            })
            .onAppear { refresh() }
            .onChange(of: sourceText) { _, _ in refresh() }
    }

    private func refresh() {
        let parsed = MarkdownDocumentCache.shared.document(for: sourceText)
        if parsed != document { document = parsed }
    }
}

// MARK: - 角标插入

/// 把服务端挂在 text 块上的 citation 还原成正文角标。
///
/// 协议只给 `citedText`（截至该引用处的正文），没有角标位置；因此在原文中定位
/// `citedText`，在其末尾插入 `[n](deepglass-citation://n)`。多个引用按从后往前
/// 的顺序插入，避免前面的插入影响后面的字符位置。
enum CitationMarkdown {
    static let scheme = "deepglass-citation"

    static func number(from url: URL) -> Int? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        if let host = url.host, let number = Int(host) { return number }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Int(path)
    }

    static func annotate(_ text: String, badges: [CitationBadge]) -> String {
        guard !text.isEmpty, !badges.isEmpty else { return text }

        let source = text as NSString
        var insertions: [(location: Int, number: Int, markdown: String)] = []
        var inserted = Set<Int>()
        // 累计型 citedText 从同一段起点开始，后续引用会匹配到更长的前缀；
        // 只把游标停在匹配起点，不跳过已引用段落。
        var cursor = 0

        for badge in badges {
            guard !inserted.contains(badge.number) else { continue }
            let needle = badge.citedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { continue }

            var range = source.range(
                of: needle,
                options: [],
                range: NSRange(location: cursor, length: max(0, source.length - cursor))
            )
            if range.location == NSNotFound {
                range = source.range(of: needle)
            }
            guard range.location != NSNotFound else { continue }

            let end = range.location + range.length
            insertions.append((
                location: end,
                number: badge.number,
                markdown: "[\\[\(badge.number)\\]](\(scheme)://\(badge.number))"
            ))
            inserted.insert(badge.number)
            cursor = min(range.location, source.length)
        }

        guard !insertions.isEmpty else { return text }

        // 从后往前插入；同一位置的多个角标按编号倒序写入，最终呈现为 [1][2]。
        insertions.sort { lhs, rhs in
            lhs.location == rhs.location ? lhs.number > rhs.number : lhs.location > rhs.location
        }
        let result = NSMutableString(string: text)
        for insertion in insertions {
            result.insert(insertion.markdown, at: insertion.location)
        }
        return result as String
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
