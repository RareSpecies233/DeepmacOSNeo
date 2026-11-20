import SwiftUI

/// DeepGlass 的 Markdown 渲染入口。
///
/// 外部只需要 `MarkdownView(text:)`。解析在后台 actor 中完成，视图层只做组装；
/// 文本可选中复制（macOS / iOS 均用 `.textSelection(.enabled)`）。
///
/// ```swift
/// MarkdownView(text: message.content)
/// ```
public struct MarkdownView: View {
    private let text: String
    private let isStreaming: Bool

    @State private var document: MarkdownDocument = .empty

    public init(text: String) {
        self.init(text: text, isStreaming: false)
    }

    /// `isStreaming` 为 true 时加一点防抖，避免每个 token 都重新解析整段。
    public init(text: String, isStreaming: Bool) {
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        MarkdownDocumentView(document: document)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .task(id: text) {
                await reload()
            }
    }

    @MainActor
    private func reload() async {
        let source = text

        guard !source.isEmpty else {
            document = .empty
            return
        }

        if !document.isEmpty {
            let delay = isStreaming ? 40 : 16
            try? await Task.sleep(for: .milliseconds(delay))
            if Task.isCancelled { return }
        }

        let parsed = await MarkdownParseService.shared.document(for: source)
        guard !Task.isCancelled else { return }

        if document.source != parsed.source {
            document = parsed
        }
    }
}
