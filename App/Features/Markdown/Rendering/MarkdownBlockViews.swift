import SwiftUI

// MARK: - 文档容器

struct MarkdownDocumentView: View {
    let document: MarkdownDocument

    var body: some View {
        if document.blocks.isEmpty {
            if document.source.isEmpty {
                EmptyView()
            } else {
                Text(verbatim: document.source)
                    .font(.system(size: MarkdownMetrics.bodyFontSize))
                    .foregroundStyle(DS.Colors.labelPrimary)
            }
        } else {
            MarkdownBlocksView(blocks: document.blocks, context: .document)
        }
    }
}

struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    var context: MarkdownBlockContext = .document

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                if index > 0 {
                    Color.clear
                        .frame(height: MarkdownSpacing.gap(
                            previous: blocks[index - 1],
                            next: blocks[index],
                            context: context
                        ))
                        .accessibilityHidden(true)
                }
                MarkdownBlockView(block: blocks[index])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 块分派

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let inlines):
            InlineTextView(inlines: inlines, kind: .heading(level))
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let inlines):
            InlineTextView(inlines: inlines, kind: .body)

        case .list(let list):
            MarkdownListView(list: list)

        case .blockquote(let blocks):
            MarkdownQuoteView(blocks: blocks)

        case .code(let model):
            if model.isMermaid {
                MermaidBlockView(model: model)
            } else {
                CodeBlockView(model: model)
            }

        case .table(let table):
            MarkdownTableView(table: table)

        case .thematicBreak:
            MarkdownRuleView()

        case .math(let source, let isClosed):
            MathBlockView(source: source, isClosed: isClosed)
        }
    }
}

// MARK: - 行内文本 + 图片

struct InlineTextView: View {
    let inlines: [MarkdownInline]
    let kind: MarkdownTextKind
    var alignment: Alignment = .leading

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var mathImages: [String: InlineMathImage] = [:]

    private var scale: CGFloat { MarkdownMetrics.dynamicScale(dynamicTypeSize) }
    private var style: MarkdownInlineStyle { kind.style(scale: scale) }
    private var mathSources: [String] { inlines.mathSources }

    var body: some View {
        let style = self.style
        let rendered = InlineRenderer.render(inlines, style: style)
        let text = InlineRenderer.text(rendered, style: style, mathImages: mathImages)

        VStack(alignment: .leading, spacing: 8) {
            text
                .lineSpacing(style.lineSpacing)
                .multilineTextAlignment(textAlignment)
                .tint(style.linkColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: alignment)

            if !rendered.images.isEmpty {
                ForEach(rendered.images.indices, id: \.self) { index in
                    MarkdownRemoteImage(source: rendered.images[index])
                }
            }
        }
        .task(id: MathTaskKey(
            sources: mathSources,
            fontSize: style.fontSize,
            dark: colorScheme == .dark
        )) {
            await loadMathImages(style: style)
        }
    }

    private var textAlignment: TextAlignment {
        if alignment == .center { return .center }
        if alignment == .trailing { return .trailing }
        return .leading
    }

    private func loadMathImages(style: MarkdownInlineStyle) async {
        let sources = mathSources
        guard !sources.isEmpty else { return }
        for source in sources {
            if mathImages[source] != nil { continue }
            if Task.isCancelled { return }
            if let image = await MathSnapshotRenderer.shared.inlineImage(
                latex: source,
                fontSize: style.fontSize,
                dark: colorScheme == .dark
            ) {
                mathImages[source] = image
            }
        }
    }
}

private struct MathTaskKey: Hashable {
    var sources: [String]
    var fontSize: CGFloat
    var dark: Bool
}

// MARK: - 图片

struct MarkdownRemoteImage: View {
    let source: String

    var body: some View {
        if let url = MarkdownLink.url(from: source),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 520, maxHeight: 520, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                case .failure:
                    Label("图片加载失败", systemImage: "photo")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.labelTertiary)
                default:
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(DS.Colors.bgSkeleton)
                        .frame(width: 240, height: 120)
                }
            }
        } else if let url = MarkdownLink.url(from: source), url.isFileURL {
            if let image = MarkdownPlatformImage.markdownImage(contentsOf: url) {
                Image(markdownPlatformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 520, maxHeight: 520, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            } else {
                fallbackText
            }
        } else {
            fallbackText
        }
    }

    private var fallbackText: some View {
        Text(verbatim: source)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(DS.Colors.labelTertiary)
            .textSelection(.enabled)
    }
}

// MARK: - 引用

struct MarkdownQuoteView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        MarkdownBlocksView(blocks: blocks, context: .quote)
            .padding(.leading, MarkdownMetrics.quotePadding + MarkdownMetrics.quoteBorderWidth)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DS.Colors.labelCaption)
                    .frame(width: MarkdownMetrics.quoteBorderWidth)
            }
    }
}

// MARK: - 列表

struct MarkdownListView: View {
    let list: MarkdownListModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var scale: CGFloat { MarkdownMetrics.dynamicScale(dynamicTypeSize) }

    var body: some View {
        VStack(alignment: .leading, spacing: MarkdownMetrics.listItemSpacing) {
            ForEach(list.items.indices, id: \.self) { index in
                let item = list.items[index]
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    marker(for: item, index: index)
                        .frame(width: 14, alignment: .trailing)
                        .padding(.trailing, 4)
                    MarkdownListItemView(item: item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownListItemModel, index: Int) -> some View {
        if let checked = item.taskState {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 13 * scale))
                .foregroundStyle(DS.Colors.labelSecondary)
        } else if list.isOrdered {
            Text(verbatim: "\(list.start + index).")
                .font(.system(size: MarkdownMetrics.bodyFontSize * scale))
                .foregroundStyle(DS.Colors.labelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        } else {
            Text(verbatim: "•")
                .font(.system(size: MarkdownMetrics.bodyFontSize * scale))
                .foregroundStyle(DS.Colors.labelSecondary)
        }
    }
}

struct MarkdownListItemView: View {
    let item: MarkdownListItemModel

    var body: some View {
        let blocks = item.blocks
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks.indices, id: \.self) { index in
                if index > 0 {
                    Color.clear.frame(height: MarkdownSpacing.gap(
                        previous: blocks[index - 1],
                        next: blocks[index],
                        context: .listItem
                    ))
                }

                if case .paragraph(let inlines) = blocks[index], blocks.count == 1 {
                    InlineTextView(inlines: inlines, kind: .body)
                } else {
                    MarkdownBlockView(block: blocks[index])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 表格

struct MarkdownTableView: View {
    let table: MarkdownTableModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(
                alignment: .leading,
                horizontalSpacing: 0,
                verticalSpacing: 0
            ) {
                GridRow(alignment: .top) {
                    ForEach(table.header.indices, id: \.self) { column in
                        cell(table.header[column], column: column, isHeader: true)
                            .gridColumnAlignment(horizontalAlignment(for: table.alignment(column)))
                    }
                }

                ForEach(table.rows.indices, id: \.self) { rowIndex in
                    GridRow(alignment: .top) {
                        ForEach(table.rows[rowIndex].indices, id: \.self) { column in
                            cell(table.rows[rowIndex][column], column: column, isHeader: false)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ cell: MarkdownTableCell, column: Int, isHeader: Bool) -> some View {
        let alignment = table.alignment(column)
        let frameAlignment = alignment == .leading ? Alignment.leading
            : (alignment == .center ? Alignment.center : Alignment.trailing)

        return Group {
            if cell.inlines.isEmpty {
                Text(verbatim: " ")
                    .font(.system(size: MarkdownMetrics.tableFontSize))
            } else {
                InlineTextView(
                    inlines: cell.inlines,
                    kind: isHeader ? .tableHead : .tableCell,
                    alignment: isHeader ? .leading : frameAlignment
                )
            }
        }
        // CSS: th/td padding 10px 16px，但 first-child 左、last-child 右为 0。
        .padding(.leading, column == 0 ? 0 : 16)
        .padding(.trailing, column == table.columnCount - 1 ? 0 : 16)
        .padding(.vertical, MarkdownMetrics.tableCellVerticalPadding)
        .frame(
            minWidth: MarkdownMetrics.tableCellMinWidth,
            maxWidth: MarkdownMetrics.tableCellMaxWidth,
            alignment: frameAlignment
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isHeader ? DS.Colors.borderL3 : DS.Colors.borderL2)
                .frame(height: 1)
        }
    }

    private func horizontalAlignment(for alignment: MarkdownAlignment) -> HorizontalAlignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - 分隔线

struct MarkdownRuleView: View {
    var body: some View {
        Rectangle()
            .fill(DS.Colors.borderL2)
            .frame(height: MarkdownMetrics.ruleThickness)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
