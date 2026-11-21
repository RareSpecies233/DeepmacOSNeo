import SwiftUI

/// 来源面板的展示参数。用 `.sheet(item:)` 携带高亮编号，避免 Bool 驱动时
/// 闭包捕获到上一帧的 highlightedIndex。
struct SourcesSheetPresentation: Identifiable {
    let id = UUID()
    var highlightedSource: Int?
}

/// 来源面板里的一行。`index` 与正文角标编号一致（从 1 开始）。
struct ChatSource: Identifiable, Hashable {
    let index: Int
    let url: String
    let title: String
    let siteName: String
    let snippet: String?
    let pageAge: String?

    var id: String { url }
}

/// 把一条消息的搜索结果与正文引用合成稳定编号的来源列表。
///
/// 搜索结果优先（它们就是「已阅读的网页」）；只在正文引用里出现、没有搜索结果的
/// 页面（例如 deep_search 的阅读链接）追加到末尾，保证每个角标都能在面板里选中。
enum ChatSourceCatalog {
    static func sources(for message: ChatMessage) -> [ChatSource] {
        var seen = Set<String>()
        var result: [ChatSource] = []

        for item in message.sources {
            guard seen.insert(item.url).inserted else { continue }
            result.append(
                ChatSource(
                    index: result.count + 1,
                    url: item.url,
                    title: item.title,
                    siteName: displaySiteName(item.siteName, url: item.url),
                    snippet: item.snippet,
                    pageAge: item.pageAge
                )
            )
        }

        for block in message.blocks where block.kind == .text {
            for citation in block.citations {
                guard seen.insert(citation.url).inserted else { continue }
                result.append(
                    ChatSource(
                        index: result.count + 1,
                        url: citation.url,
                        title: citation.title ?? citation.url,
                        siteName: displaySiteName(nil, url: citation.url),
                        snippet: nil,
                        pageAge: nil
                    )
                )
            }
        }

        return result
    }

    /// 站点名缺失时回退到域名（去掉 www.）。
    static func displaySiteName(_ siteName: String?, url: String) -> String {
        let trimmed = siteName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        guard let host = URL(string: url)?.host, !host.isEmpty else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// 底部「已阅读 N 个网页」来源面板。
struct SourcesSheet: View {
    let sources: [ChatSource]
    /// 从正文角标打开时高亮并滚动到对应行。
    var highlightedIndex: Int?
    let onClose: () -> Void

    var body: some View {
        Group {
            #if os(macOS)
            panel.frame(width: 480, height: 560)
            #else
            panel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
            #endif
        }
        .presentationCornerRadius(DS.Radius.card)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(DS.Colors.borderL2)

            if sources.isEmpty {
                Text(L10n.language == .zhHans ? "没有可展示的来源" : "No sources to show")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.labelTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sources) { source in
                                SourceRow(
                                    source: source,
                                    highlighted: source.index == highlightedIndex
                                )
                                .id(source.index)
                                if source.id != sources.last?.id {
                                    Divider()
                                        .overlay(DS.Colors.borderL1)
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onAppear {
                        guard let highlightedIndex else { return }
                        proxy.scrollTo(highlightedIndex, anchor: .center)
                    }
                }
            }
        }
        .dsGlass(cornerRadius: DS.Radius.card)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Colors.labelSecondary)
            Text(title)
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.labelPrimary)
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.labelTertiary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L10n.language == .zhHans ? "关闭" : "Close")
            .accessibilityLabel(L10n.language == .zhHans ? "关闭来源面板" : "Close sources")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var title: String {
        let count = sources.count
        return count == 1
            ? L10n.t(.messageSearchResult)
            : L10n.t(.messageSearchResults, ["count": "\(count)"])
    }
}

// MARK: - 单行

private struct SourceRow: View {
    let source: ChatSource
    let highlighted: Bool
    @State private var hovered = false

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(DS.Colors.labelTertiary)
                .frame(width: 24, height: 24)
                .background {
                    Circle().fill(DS.Colors.bgSkeleton)
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(source.siteName)
                        .font(DS.Typography.captionMedium)
                        .foregroundStyle(DS.Colors.labelSecondary)
                        .lineLimit(1)
                    if let date = Self.dateText(source.pageAge) {
                        Text("·")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.labelCaption)
                        Text(date)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.labelTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("[\(source.index)]")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(DS.Colors.labelTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background {
                            RoundedRectangle(cornerRadius: DS.Radius.xs)
                                .fill(DS.Colors.citation)
                        }
                }

                Text(source.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let snippet = source.snippet?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.Colors.labelSecondary)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m)
                .fill(highlighted ? DS.Colors.brandSubtle : (hovered ? DS.Colors.interactiveHover : .clear))
        }
        .contentShape(Rectangle())
    }

    var body: some View {
        Group {
            if let url = URL(string: source.url), url.scheme != nil {
                Link(destination: url) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .onHover { hovered = $0 }
        .padding(.horizontal, 6)
        .help(source.url)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.language == .zhHans ? "在浏览器中打开" : "Open in browser")
    }

    /// RFC 3339 → YYYY/MM/DD；解析不了就原样显示（与参考实现一致）。
    private static func dateText(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let iso = ISO8601DateFormatter()
        let date = iso.date(from: raw) ?? {
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return iso.date(from: raw)
        }()
        guard let date else { return raw }
        let formatter = DateFormatter()
        formatter.locale = L10n.language.locale
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
