import SwiftUI

/// 思考与工具步骤时间线：可折叠标题 + 思考正文 + 搜索/抓取步骤
struct ThinkingTimeline: View {
    let message: ChatMessage
    let isStreaming: Bool
    /// nil 表示跟随规则自动折叠：有正文时折叠，思考中展开
    @State private var manualExpanded: Bool?

    private var thinkingBlocks: [Block] { message.blocks.filter { $0.kind == .thinking } }
    private var toolBlocks: [Block] {
        message.blocks.filter { $0.kind == .toolUse || $0.kind == .searchResults || $0.kind == .fetchResult }
    }
    private var hasResponse: Bool { !message.plainText.isEmpty }
    private var hasContent: Bool { !thinkingBlocks.isEmpty || !toolBlocks.isEmpty }

    private var isExpanded: Bool { manualExpanded ?? !hasResponse }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 6) {
                header
                if isExpanded || !hasResponse {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(thinkingBlocks) { block in
                            Text(block.text)
                                .font(.system(size: 13.5))
                                .foregroundStyle(DS.Colors.labelSecondary)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                        ForEach(Array(toolBlocks.enumerated()), id: \.offset) { _, block in
                            ToolStepRow(block: block)
                        }
                    }
                    .padding(.leading, 2)
                }
            }
            .padding(.bottom, 10)
        }
    }

    private var header: some View {
        Button {
            withAnimation(DS.Motion.fastEase) { manualExpanded = !isExpanded }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Colors.labelTertiary)
                Text(title)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.labelSecondary)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Colors.labelTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if hasResponse { return L10n.t(.thinkingDone) }
        if !isStreaming { return L10n.t(.messageThinkStopped) }
        if toolBlocks.contains(where: { $0.kind == .searchResults }) { return L10n.t(.deepSearchSearching) }
        return L10n.t(.messageThinking)
    }
}

// MARK: - 工具步骤

private struct ToolStepRow: View {
    let block: Block

    var body: some View {
        switch block.kind {
        case .toolUse:
            if let tool = block.toolUse {
                HStack(spacing: 6) {
                    Image(systemName: tool.kind == .readLink ? "link" : "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.labelTertiary)
                    Text(label(for: tool))
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Colors.labelSecondary)
                        .lineLimit(2)
                }
            }
        case .searchResults:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: block.failed ? "exclamationmark.triangle" : "doc.text.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(block.failed ? DS.Colors.errorSecondary : DS.Colors.labelTertiary)
                    Text(searchSummary)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Colors.labelSecondary)
                }
                if !block.failed {
                    ForEach(block.searchResults.prefix(4)) { result in
                        HStack(spacing: 6) {
                            Circle().fill(DS.Colors.labelTertiary.opacity(0.4))
                                .frame(width: 3, height: 3)
                            Text(result.title)
                                .font(.system(size: 12.5))
                                .foregroundStyle(DS.Colors.labelTertiary)
                                .lineLimit(1)
                        }
                        .padding(.leading, 4)
                    }
                }
            }
        case .fetchResult:
            if let fetch = block.fetchResult {
                HStack(spacing: 6) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.labelTertiary)
                    Text(block.failed ? L10n.t(.readFailed) : (fetch.title ?? fetch.url))
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Colors.labelSecondary)
                        .lineLimit(1)
                }
            }
        default:
            EmptyView()
        }
    }

    /// 搜索结果条数：1 条用单数文案，其余按 `{count}` 插值
    private var searchSummary: String {
        if block.failed { return L10n.t(.searchFailed) }
        let count = block.searchResults.count
        return count == 1
            ? L10n.t(.messageSearchResult)
            : L10n.t(.messageSearchResults, ["count": "\(count)"])
    }

    private func label(for tool: ServerToolUse) -> String {
        switch tool.action {
        case "search":
            return tool.queries.isEmpty
                ? L10n.t(.deepSearchSearching)
                : L10n.t(.searchQuery, ["query": L10n.list(tool.queries)])
        case "open_page", "read_link":
            return L10n.t(.readingURL, ["url": tool.url ?? L10n.t(.webPage)])
        case "find_in_page":
            return L10n.t(.findInPage, ["pattern": tool.pattern ?? ""])
        default:
            return L10n.t(.toolCall)
        }
    }
}
