import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

// MARK: - 行内样式

struct MarkdownInlineStyle {
    var fontSize: CGFloat
    var weight: Font.Weight
    var italic = false
    var strikethrough = false
    /// 标题里的 strong 继承标题字重（CSS: `h1 strong { font-weight: inherit }`）。
    var boldWeight: Font.Weight?
    var lineSpacing: CGFloat
    var monospacedCodeSize: CGFloat
    var textColor: Color
    var codeColor: Color
    var codeBackground: Color
    var linkColor: Color

    func bolding() -> MarkdownInlineStyle {
        var copy = self
        if let boldWeight { copy.weight = boldWeight }
        return copy
    }

    func italicizing() -> MarkdownInlineStyle {
        var copy = self
        copy.italic = true
        return copy
    }

    func striking() -> MarkdownInlineStyle {
        var copy = self
        copy.strikethrough = true
        return copy
    }

    func withSize(_ size: CGFloat) -> MarkdownInlineStyle {
        var copy = self
        copy.fontSize = size
        return copy
    }
}

enum MarkdownTextKind {
    case body
    case heading(Int)
    case tableCell
    case tableHead

    func style(scale: CGFloat) -> MarkdownInlineStyle {
        switch self {
        case .body:
            return MarkdownInlineStyle(
                fontSize: MarkdownMetrics.bodyFontSize * scale,
                weight: .regular,
                boldWeight: .semibold,
                lineSpacing: MarkdownMetrics.bodyLineSpacing * scale,
                monospacedCodeSize: MarkdownMetrics.inlineCodeFontSize * scale,
                textColor: DS.Colors.labelPrimary,
                codeColor: DS.Colors.labelPrimary,
                codeBackground: DS.Colors.inlineCode,
                linkColor: DS.Colors.brandText
            )

        case .heading(let level):
            return MarkdownInlineStyle(
                fontSize: MarkdownMetrics.headingFontSize(level: level) * scale,
                weight: MarkdownMetrics.headingWeight(level: level),
                boldWeight: nil,
                lineSpacing: MarkdownMetrics.headingLineSpacing(level: level) * scale,
                monospacedCodeSize: MarkdownMetrics.headingFontSize(level: level) * scale,
                textColor: DS.Colors.labelPrimary,
                codeColor: DS.Colors.labelPrimary,
                codeBackground: DS.Colors.inlineCode,
                linkColor: DS.Colors.brandText
            )

        case .tableCell:
            return MarkdownInlineStyle(
                fontSize: MarkdownMetrics.tableFontSize * scale,
                weight: .regular,
                boldWeight: .semibold,
                lineSpacing: MarkdownMetrics.tableLineSpacing * scale,
                monospacedCodeSize: 13 * scale,
                textColor: DS.Colors.labelPrimary,
                codeColor: DS.Colors.labelPrimary,
                codeBackground: DS.Colors.inlineCode,
                linkColor: DS.Colors.brandText
            )

        case .tableHead:
            return MarkdownInlineStyle(
                fontSize: MarkdownMetrics.tableFontSize * scale,
                weight: .medium,
                boldWeight: .semibold,
                lineSpacing: MarkdownMetrics.tableLineSpacing * scale,
                monospacedCodeSize: 13 * scale,
                textColor: DS.Colors.labelPrimary,
                codeColor: DS.Colors.labelPrimary,
                codeBackground: DS.Colors.inlineCode,
                linkColor: DS.Colors.brandText
            )
        }
    }
}

// MARK: - 代码配色（取自 highlight.css 的 light / dark 两套）

struct MarkdownCodePalette {
    var plain: Color
    var keyword: Color
    var string: Color
    var comment: Color
    var number: Color
    var type: Color

    func color(for kind: CodeToken.Kind) -> Color {
        switch kind {
        case .plain, .punctuation: return plain
        case .keyword: return keyword
        case .string: return string
        case .comment: return comment
        case .number: return number
        case .type: return type
        }
    }

    /// body.dark .md-code-block 的 Prism 配色
    static let dark = MarkdownCodePalette(
        plain: Color(markdownHex: 0xE3EAF2),
        keyword: Color(markdownHex: 0xE9AE7E),
        string: Color(markdownHex: 0x91D076),
        comment: Color(markdownHex: 0x8DA1B9),
        number: Color(markdownHex: 0xE6D37A),
        type: Color(markdownHex: 0x6CB8E6)
    )

    /// body.light .md-code-block 的 Prism 配色（One Light 系）
    static let light = MarkdownCodePalette(
        plain: Color(markdownHex: 0x383A42),
        keyword: Color(markdownHex: 0xA626A4),
        string: Color(markdownHex: 0x50A14F),
        comment: Color(markdownHex: 0xA0A1A7),
        number: Color(markdownHex: 0xB76B01),
        type: Color(markdownHex: 0x4078F2)
    )

    static func palette(dark: Bool) -> MarkdownCodePalette {
        dark ? .dark : .light
    }
}

// MARK: - 工具

extension Color {
    /// 十六进制构造（sRGB），仅 Markdown 内部使用。
    init(markdownHex hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// 给 WKWebView 用的 CSS 颜色，按指定外观解析，避免受当前窗口绘制状态影响。
    func markdownCSSColor(dark: Bool) -> String {
        var environment = EnvironmentValues()
        environment.colorScheme = dark ? .dark : .light
        let resolved = self.resolve(in: environment)
        let red = Int((resolved.red * 255).rounded())
        let green = Int((resolved.green * 255).rounded())
        let blue = Int((resolved.blue * 255).rounded())
        let alpha = max(0, min(1, Double(resolved.opacity)))
        return String(format: "rgba(%d,%d,%d,%.3f)", red, green, blue, alpha)
    }
}

enum MarkdownLink {
    static func url(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encoded) {
            return url
        }
        return URL(string: trimmed)
    }
}
