import SwiftUI

/// ```mermaid 围栏：渲染成图片；未闭合/失败/用户切到源码时显示代码。
struct MermaidBlockView: View {
    let model: MarkdownCodeModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    @State private var rendered: MermaidImage?
    @State private var failed = false
    @State private var showCode = false
    @State private var width: CGFloat = 0

    private var scale: CGFloat { MarkdownMetrics.dynamicScale(dynamicTypeSize) }
    private var fontSize: CGFloat { MarkdownMetrics.codeBlockFontSize * scale }
    private var palette: MarkdownCodePalette {
        MarkdownCodePalette.palette(dark: colorScheme == .dark)
    }
    private var isDark: Bool { colorScheme == .dark }

    private var canRender: Bool {
        model.isClosed && !model.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var widthBucket: CGFloat {
        max(160, (width / 10).rounded() * 10)
    }

    private var shouldShowDiagram: Bool {
        canRender && !showCode && !failed
    }

    var body: some View {
        VStack(spacing: 0) {
            banner
            content
        }
        .background(DS.Colors.codeBlock)
        .clipShape(RoundedRectangle(cornerRadius: MarkdownMetrics.codeBlockRadius, style: .continuous))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: MarkdownWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(MarkdownWidthKey.self) { value in
            if abs(value - width) > 0.5 {
                width = value
            }
        }
        .onChange(of: model.code) { _, _ in
            failed = false
        }
        .task(id: RenderKey(
            code: shouldShowDiagram ? model.code : "",
            width: widthBucket,
            dark: isDark,
            enabled: shouldShowDiagram && width > 0
        )) {
            await renderIfNeeded()
        }
    }

    // MARK: Banner

    private var banner: some View {
        HStack(spacing: 6) {
            Text(verbatim: "mermaid")
                .font(.system(size: MarkdownMetrics.codeBannerLabelFontSize * scale, design: .monospaced))
                .foregroundStyle(DS.Colors.labelPrimary)
                .padding(.leading, 8)

            if canRender {
                HStack(spacing: 4) {
                    modeButton("图表", selected: !showCode) {
                        showCode = false
                        failed = false
                    }
                    modeButton("源码", selected: showCode) {
                        showCode = true
                    }
                }
                .padding(.leading, 4)
            }

            Spacer(minLength: 8)

            MarkdownCopyButton(code: model.code)
        }
        .padding(MarkdownMetrics.codeBannerPadding)
        .background(DS.Colors.codeBlockBanner)
    }

    private func modeButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 12))
                .foregroundStyle(selected ? DS.Colors.labelPrimary : DS.Colors.labelSecondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? DS.Colors.codeBlock : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if !canRender || showCode {
            codePane
        } else if let rendered {
            diagram(rendered)
        } else if failed {
            VStack(alignment: .leading, spacing: 8) {
                codePane
                Text(verbatim: "图表渲染失败，已降级为源码")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.labelTertiary)
                    .padding(.horizontal, MarkdownMetrics.codeBlockPadding)
                    .padding(.bottom, 12)
            }
        } else {
            placeholder
        }
    }

    private var codePane: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(CodeTextBuilder.attributed(lines: model.lines, palette: palette))
                .font(.system(size: fontSize, design: .monospaced))
                .lineSpacing(MarkdownMetrics.codeBlockLineSpacing * scale)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(MarkdownMetrics.codeBlockPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diagram(_ rendered: MermaidImage) -> some View {
        let available = max(width - MarkdownMetrics.codeBlockPadding * 2, 80)
        let displayWidth = min(rendered.size.width, available)
        let aspect = rendered.size.height / max(rendered.size.width, 1)

        return Image(markdownPlatformImage: rendered.image)
            .resizable()
            .interpolation(.high)
            .frame(width: displayWidth, height: displayWidth * aspect)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(MarkdownMetrics.codeBlockPadding)
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(verbatim: "正在渲染图表…")
                .font(.system(size: 13))
                .foregroundStyle(DS.Colors.labelSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: 渲染

    private func renderIfNeeded() async {
        guard shouldShowDiagram, width > 0 else { return }

        if let cached = MermaidRenderer.shared.cachedImage(
            code: model.code,
            width: widthBucket,
            dark: isDark
        ) {
            rendered = cached
            failed = false
            return
        }

        // 流式内容变化很快，合并一下请求。
        do {
            try await Task.sleep(for: .milliseconds(120))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        let image = await MermaidRenderer.shared.render(
            code: model.code,
            width: widthBucket,
            dark: isDark
        )

        guard !Task.isCancelled else { return }

        if let image {
            rendered = image
            failed = false
        } else {
            failed = true
        }
    }
}

struct MarkdownWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct RenderKey: Hashable {
    var code: String
    var width: CGFloat
    var dark: Bool
    var enabled: Bool
}
