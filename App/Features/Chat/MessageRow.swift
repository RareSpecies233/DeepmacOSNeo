import SwiftUI

/// 单条消息：用户为右侧气泡，助手为全宽内容 + 操作栏
struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    var isLastAssistant: Bool = false
    /// 当前消息所属的版本组；nil 表示不显示切换器（旧数据 / 首版）。
    var version: Branching.VersionInfo?
    var versionSwitchDisabled: Bool = false
    var onSelectVersion: ((String) -> Void)?
    var onRegenerate: (() -> Void)?
    var onEditUserMessage: (() -> Void)?
    /// 从此处分叉；由 ChatView 注入，未接线时为 nil（按钮不出现）。
    var onFork: (() -> Void)? = nil
    @State private var hovered = false
    @State private var copied = false
    @State private var sourcesPresentation: SourcesSheetPresentation?

    /// 搜索结果 + 仅被正文引用到的页面，编号与角标一致。
    private var sourceCatalog: [ChatSource] { ChatSourceCatalog.sources(for: message) }

    /// 正文角标：同一 URL 只插一次，编号取来源面板里的行号。
    private var citationBadges: [CitationBadge] {
        let catalog = sourceCatalog
        var seen = Set<String>()
        var badges: [CitationBadge] = []
        for block in message.blocks where block.kind == .text {
            for citation in block.citations where seen.insert(citation.url).inserted {
                guard let source = catalog.first(where: { $0.url == citation.url }) else { continue }
                badges.append(
                    CitationBadge(
                        number: source.index,
                        url: citation.url,
                        citedText: citation.citedText
                    )
                )
            }
        }
        return badges
    }

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: assistantBlock
        }
    }

    // MARK: 用户

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.plainText)
                .font(DS.Typography.userBody)
                .foregroundStyle(DS.Colors.labelPrimary)
                .lineSpacing(DS.Typography.userLineSpacing)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DS.Colors.bubble)
                }
        }
        .contextMenu {
            if let onEditUserMessage {
                Button("编辑并重新发送", systemImage: "square.and.pencil", action: onEditUserMessage)
            }
        }
    }

    // MARK: 助手

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThinkingTimeline(message: message, isStreaming: isStreaming)

            if message.status == .failed, let error = message.errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error)
                }
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.errorPrimary)
                .padding(.vertical, 6)
            }

            if !message.plainText.isEmpty {
                AssistantBody(
                    text: message.plainText,
                    badges: citationBadges,
                    onOpenCitation: { number in
                        openCitation(number)
                    },
                    isStreaming: isStreaming
                )
            } else if isStreaming && message.blocks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在生成…")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.labelTertiary)
                }
                .padding(.vertical, 4)
            }

            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovered = $0 }
        .sheet(item: $sourcesPresentation) { presentation in
            SourcesSheet(
                sources: sourceCatalog,
                highlightedIndex: presentation.highlightedSource,
                onClose: { sourcesPresentation = nil }
            )
        }
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            if !message.plainText.isEmpty {
                ActionIcon(systemName: copied ? "checkmark" : "doc.on.doc", help: "复制") {
                    copyToPasteboard(message.plainText)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                }
            }
            if !message.plainText.isEmpty {
                ReadAloudButton(text: message.plainText)
            }
            if !message.sources.isEmpty {
                SourceCountButton(count: sourceCatalog.count) {
                    sourcesPresentation = SourcesSheetPresentation(highlightedSource: nil)
                }
            }
            if let onFork {
                ActionIcon(systemName: "arrow.triangle.branch", help: "从此处分叉", action: onFork)
            }
            if isLastAssistant && !isStreaming, let onRegenerate {
                ActionIcon(systemName: "arrow.clockwise", help: "重新生成", action: onRegenerate)
            }
            if let version, version.count > 1 {
                versionSwitcher(version)
            }
            Spacer()
        }
        .opacity(hovered || isStreaming == false ? 1 : 1)
        .padding(.top, 6)
        .frame(height: 26)
    }

    /// `‹ 2/3 ›`：仅在存在多个版本时出现，切换只改变选中项，不删除历史。
    private func versionSwitcher(_ version: Branching.VersionInfo) -> some View {
        HStack(spacing: 0) {
            ActionIcon(
                systemName: "chevron.left",
                help: "上一版本",
                isEnabled: version.index > 0 && !versionSwitchDisabled
            ) {
                if let id = version.previousID { onSelectVersion?(id) }
            }
            Text("\(version.displayIndex)/\(version.count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DS.Colors.labelTertiary)
                .frame(minWidth: 30)
                .accessibilityLabel("版本 \(version.displayIndex) / \(version.count)")
            ActionIcon(
                systemName: "chevron.right",
                help: "下一版本",
                isEnabled: version.index + 1 < version.count && !versionSwitchDisabled
            ) {
                if let id = version.nextID { onSelectVersion?(id) }
            }
        }
        .padding(.horizontal, 2)
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// 正文角标点击：打开来源面板并高亮对应行。
    private func openCitation(_ number: Int) {
        sourcesPresentation = SourcesSheetPresentation(highlightedSource: number)
    }
}

private struct ActionIcon: View {
    let systemName: String
    var help: String
    var isEnabled: Bool = true
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Colors.labelTertiary)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .fill(hovered ? DS.Colors.interactiveHover : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// 操作栏里的「来源 N」：只在有搜索结果时出现。
private struct SourceCountButton: View {
    let count: Int
    let action: () -> Void
    @State private var hovered = false

    private var label: String {
        L10n.language == .zhHans ? "来源 \(count)" : "Sources \(count)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10.5, weight: .medium))
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(DS.Colors.labelTertiary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s)
                    .fill(hovered ? DS.Colors.interactiveHover : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(L10n.language == .zhHans ? "查看来源" : "View sources")
    }
}
