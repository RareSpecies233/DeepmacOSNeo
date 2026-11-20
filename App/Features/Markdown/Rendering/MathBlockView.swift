import SwiftUI

/// 块级公式：优先 Web 岛，未闭合/渲染失败时降级为带 TeX 着色的源码块。
struct MathBlockView: View {
    let source: String
    let isClosed: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 0
    @State private var failed = false

    private var scale: CGFloat { MarkdownMetrics.dynamicScale(dynamicTypeSize) }
    private var fontSize: CGFloat { MarkdownMetrics.bodyFontSize * scale }

    var body: some View {
        Group {
            if !isClosed || failed || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MathSourceFallback(
                    source: source,
                    note: isClosed ? "公式渲染失败，已显示源码" : "公式尚未闭合，已显示源码"
                )
            } else {
                MathWebView(
                    latex: source,
                    displayMode: true,
                    fontSize: fontSize,
                    dark: colorScheme == .dark,
                    height: $height,
                    onFailure: { failed = true }
                )
                .frame(height: max(height, 1))
                .frame(maxWidth: .infinity)
                .opacity(height > 0 ? 1 : 0)
                .allowsHitTesting(height > 0)
            }
        }
        .onChange(of: source) { _, _ in
            failed = false
        }
    }
}

// MARK: - 降级源码块

struct MathSourceFallback: View {
    let source: String
    let note: String?

    @Environment(\.colorScheme) private var colorScheme

    private var palette: MarkdownCodePalette {
        MarkdownCodePalette.palette(dark: colorScheme == .dark)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(TeXHighlighter.attributed(source, palette: palette))
                    .font(.system(size: MarkdownMetrics.codeBlockFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Colors.codeBlock)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))

            if let note {
                Text(verbatim: note)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.labelTertiary)
            }
        }
    }
}

// MARK: - TeX 源码着色

enum TeXHighlighter {
    static func attributed(_ source: String, palette: MarkdownCodePalette) -> AttributedString {
        let chars = Array(source)
        var tokens: [CodeToken] = []
        var buffer = ""
        var kind: CodeToken.Kind = .plain

        func flush() {
            guard !buffer.isEmpty else { return }
            if let last = tokens.last, last.kind == kind {
                tokens[tokens.count - 1].text += buffer
            } else {
                tokens.append(CodeToken(kind: kind, text: buffer))
            }
            buffer = ""
        }

        func append(_ text: String, _ next: CodeToken.Kind) {
            if next != kind {
                flush()
                kind = next
            }
            buffer += text
        }

        var index = 0
        while index < chars.count {
            let ch = chars[index]

            if ch == "%" {
                var end = index
                while end < chars.count, chars[end] != "\n" { end += 1 }
                append(String(chars[index..<end]), .comment)
                index = end
                continue
            }

            if ch == "\\" {
                var end = index + 1
                if end < chars.count, chars[end].isLetter {
                    while end < chars.count, chars[end].isLetter { end += 1 }
                } else if end < chars.count {
                    end += 1
                }
                append(String(chars[index..<end]), .keyword)
                index = end
                continue
            }

            if ch.isNumber || ch == "." {
                var end = index
                while end < chars.count, chars[end].isNumber || chars[end] == "." { end += 1 }
                append(String(chars[index..<end]), .number)
                index = end
                continue
            }

            if "{}[]()$^_&".contains(ch) {
                append(String(ch), .punctuation)
                index += 1
                continue
            }

            append(String(ch), .plain)
            index += 1
        }

        flush()
        return CodeTextBuilder.attributed(lines: [CodeLine(tokens: tokens)], palette: palette)
    }
}
