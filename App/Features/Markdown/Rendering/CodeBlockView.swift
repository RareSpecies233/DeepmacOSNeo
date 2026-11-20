import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - 代码块

/// 围栏代码块：banner（语言 + 复制）+ 横向滚动、不换行的高亮内容。
struct CodeBlockView: View {
    let model: MarkdownCodeModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var scale: CGFloat { MarkdownMetrics.dynamicScale(dynamicTypeSize) }
    private var fontSize: CGFloat { MarkdownMetrics.codeBlockFontSize * scale }
    private var palette: MarkdownCodePalette {
        MarkdownCodePalette.palette(dark: colorScheme == .dark)
    }

    var body: some View {
        VStack(spacing: 0) {
            banner
            content
        }
        .background(DS.Colors.codeBlock)
        .clipShape(RoundedRectangle(cornerRadius: MarkdownMetrics.codeBlockRadius, style: .continuous))
    }

    private var banner: some View {
        HStack(spacing: 0) {
            if !model.displayLanguage.isEmpty {
                Text(verbatim: model.displayLanguage)
                    .font(.system(size: MarkdownMetrics.codeBannerLabelFontSize * scale, design: .monospaced))
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .lineLimit(1)
                    .padding(.leading, 8)
            }
            Spacer(minLength: 8)
            MarkdownCopyButton(code: model.code)
        }
        .padding(MarkdownMetrics.codeBannerPadding)
        .background(DS.Colors.codeBlockBanner)
    }

    private var content: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(CodeTextBuilder.attributed(lines: model.lines, palette: palette))
                .font(.system(size: fontSize, design: .monospaced))
                .lineSpacing(MarkdownMetrics.codeBlockLineSpacing * scale)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .padding(MarkdownMetrics.codeBlockPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.codeBlock)
    }
}

// MARK: - 高亮文本

enum CodeTextBuilder {
    static func attributed(lines: [CodeLine], palette: MarkdownCodePalette) -> AttributedString {
        var result = AttributedString()
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                result.append(AttributedString("\n"))
            }
            for token in line.tokens {
                var piece = AttributedString(token.text)
                piece.foregroundColor = palette.color(for: token.kind)
                result.append(piece)
            }
        }
        return result
    }
}

// MARK: - 复制按钮

struct MarkdownCopyButton: View {
    let code: String

    @State private var copied = false
    @State private var hovering = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 3) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
                Text(verbatim: copied ? "已复制" : "复制")
                    .font(.system(size: MarkdownMetrics.codeBannerButtonFontSize))
            }
            .foregroundStyle(DS.Colors.labelSecondary)
            .padding(.horizontal, 10)
            .frame(height: MarkdownMetrics.codeBannerButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: MarkdownMetrics.codeBannerButtonRadius, style: .continuous)
                    .fill(hovering ? DS.Colors.interactiveHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(copied ? "已复制" : "复制代码")
    }

    private func copy() {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif

        copied = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
