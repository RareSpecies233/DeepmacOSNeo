import SwiftUI

/// Markdown 排版度量。
///
/// 来源：`Reference/chat-demo/src/components/markdown/markdown.css`、
/// `CodeBlock.module.css`、`highlight.css`、`app/theme.css` 的 `--dsw-font-markdown-*`。
///
/// 说明（与任务书的差异，按 CSS 原文取值）：
/// - 参考 CSS 正文 `--dsw-font-markdown-base` 是 **16px/28px**；本项目任务书与
///   `DS.Typography.body` 约定正文为 **14px/约 22px**，故以 14px 为正文基准。
/// - 代码块圆角 CSS 原文是 **12px**（`--dsl-code-block-border-radius`），
///   不是 8px；行内代码是 **6px + 0 5px**，不是 5px + 0 2px。这里按 CSS。
/// - 标题/表格字号沿用 CSS 绝对 px，保持与参考一致的层级关系。
enum MarkdownMetrics {

    // MARK: 正文与行内

    static let bodyFontSize: CGFloat = 14
    /// 14pt SF 的自然行高约 17px，+5 ≈ CSS 的 22px 行高。
    static let bodyLineSpacing: CGFloat = 5
    /// 行内代码：CSS `font-size: 0.875em`（16→14），以 14 基准取 12.25。
    static let inlineCodeFontSize: CGFloat = 12.25
    /// CSS `.ds-markdown code { border-radius: 6px; padding: 0 5px }`
    static let inlineCodeRadius: CGFloat = 6
    static let inlineCodeHorizontalPadding: CGFloat = 5

    // MARK: 标题（CSS: h1 24/34 700, h2 22/32 700, h3 20/30 700, h4 16/28 600）

    static func headingFontSize(level: Int) -> CGFloat {
        switch level {
        case 1: return 24
        case 2: return 22
        case 3: return 20
        case 4: return 16
        default: return bodyFontSize
        }
    }

    static func headingWeight(level: Int) -> Font.Weight {
        level <= 3 ? .bold : .semibold
    }

    /// CSS 行高 34/32/30/28，换算成 SwiftUI 的额外行距。
    static func headingLineSpacing(level: Int) -> CGFloat {
        switch level {
        case 1: return 5
        case 2: return 6
        case 3: return 6
        case 4: return 9
        default: return 5
        }
    }

    // MARK: 表格（CSS 15/25，表头 500）

    static let tableFontSize: CGFloat = 15
    static let tableLineSpacing: CGFloat = 7
    static let tableCellVerticalPadding: CGFloat = 10
    static let tableCellMinWidth: CGFloat = 100
    static let tableCellMaxWidth: CGFloat = 320
    static let tableColumnSpacing: CGFloat = 32

    // MARK: 代码块（CSS: 13/22，banner 13/20，name 12/18）

    static let codeBlockFontSize: CGFloat = 13
    static let codeBlockLineSpacing: CGFloat = 6
    static let codeBlockPadding: CGFloat = 16
    static let codeBlockRadius: CGFloat = 12
    static let codeBannerPadding: CGFloat = 6
    static let codeBannerLabelFontSize: CGFloat = 12
    static let codeBannerButtonFontSize: CGFloat = 13
    static let codeBannerButtonHeight: CGFloat = 28
    static let codeBannerButtonRadius: CGFloat = 8

    // MARK: 列表 / 引用 / 分隔线

    /// CSS `ul, ol { padding-left: 18px }`
    static let listIndent: CGFloat = 18
    static let listItemSpacing: CGFloat = 6
    static let listItemParagraphSpacing: CGFloat = 8
    static let nestedListTopSpacing: CGFloat = 4

    static let quoteBorderWidth: CGFloat = 2
    static let quotePadding: CGFloat = 14

    static let ruleThickness: CGFloat = 1

    // MARK: 块间距（CSS 外边距，折叠后取 max）

    static let headingTopSpacing: CGFloat = 32
    static let headingBottomSpacing: CGFloat = 16
    static let paragraphSpacing: CGFloat = 16
    static let blockSpacing: CGFloat = 16
    static let ruleSpacing: CGFloat = 32
    static let compactHeadingListSpacing: CGFloat = 8

    // MARK: 动态字体

    /// 把 SwiftUI Dynamic Type 映射成倍率；macOS 默认 .large = 1.0。
    static func dynamicScale(_ size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: return 0.82
        case .small: return 0.9
        case .medium: return 0.95
        case .large: return 1.0
        case .xLarge: return 1.08
        case .xxLarge: return 1.16
        case .xxxLarge: return 1.24
        case .accessibility1: return 1.36
        case .accessibility2: return 1.5
        case .accessibility3: return 1.64
        case .accessibility4: return 1.78
        case .accessibility5: return 1.92
        @unknown default: return 1.0
        }
    }
}

// MARK: - 上下文与间距

enum MarkdownBlockContext {
    case document
    case quote
    case listItem
}

enum MarkdownSpacing {

    static func top(_ block: MarkdownBlock, in context: MarkdownBlockContext) -> CGFloat {
        switch block {
        case .heading(let level, _):
            return level <= 3 ? MarkdownMetrics.headingTopSpacing : MarkdownMetrics.paragraphSpacing
        case .paragraph:
            return context == .listItem ? MarkdownMetrics.listItemParagraphSpacing : MarkdownMetrics.paragraphSpacing
        case .list:
            return MarkdownMetrics.blockSpacing
        case .blockquote:
            return MarkdownMetrics.blockSpacing
        case .code:
            return MarkdownMetrics.blockSpacing
        case .table:
            return MarkdownMetrics.blockSpacing
        case .thematicBreak:
            return MarkdownMetrics.ruleSpacing
        case .math:
            return MarkdownMetrics.blockSpacing
        }
    }

    static func bottom(_ block: MarkdownBlock, in context: MarkdownBlockContext) -> CGFloat {
        switch block {
        case .heading(let level, _):
            return level <= 3 ? MarkdownMetrics.headingBottomSpacing : MarkdownMetrics.paragraphSpacing
        case .paragraph:
            return context == .listItem ? MarkdownMetrics.listItemParagraphSpacing : MarkdownMetrics.paragraphSpacing
        case .list:
            return MarkdownMetrics.blockSpacing
        case .blockquote:
            return 0   // CSS: blockquote { margin: 16px 0 0 }
        case .code:
            return MarkdownMetrics.blockSpacing
        case .table:
            return MarkdownMetrics.blockSpacing
        case .thematicBreak:
            return MarkdownMetrics.ruleSpacing
        case .math:
            return MarkdownMetrics.blockSpacing
        }
    }

    /// 相邻块间距 = 两者外边距折叠（取大者），并还原 CSS 的特例。
    static func gap(previous: MarkdownBlock, next: MarkdownBlock, context: MarkdownBlockContext) -> CGFloat {
        if context == .listItem, next.isList { return MarkdownMetrics.nestedListTopSpacing }
        if case .heading(let level, _) = previous, level >= 4, next.isList {
            return MarkdownMetrics.compactHeadingListSpacing
        }
        return max(bottom(previous, in: context), top(next, in: context))
    }
}

extension MarkdownBlock {
    var isList: Bool {
        if case .list = self { return true }
        return false
    }
}
