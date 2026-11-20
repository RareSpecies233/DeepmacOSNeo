import SwiftUI

/// 行内节点 → `AttributedString` 片段。
///
/// 公式无法放进 `AttributedString`，单独作为 piece；视图层把公式快照成图片后用
/// `Text(Image)` 拼回同一行，保证行内流式排版；快照失败时退回 TeX 源码文本。
enum InlinePiece {
    case text(AttributedString)
    case math(String)
    case image(String)
}

struct InlineRenderResult {
    var pieces: [InlinePiece] = []
    var images: [String] = []
}

enum InlineRenderer {

    static func render(_ inlines: [MarkdownInline], style: MarkdownInlineStyle) -> InlineRenderResult {
        var builder = Builder()
        builder.walk(inlines, style: style)
        builder.flush()
        return InlineRenderResult(pieces: builder.pieces, images: builder.images)
    }

    /// 组合成可选中、可复制的 `Text`。
    static func text(
        _ result: InlineRenderResult,
        style: MarkdownInlineStyle,
        mathImages: [String: InlineMathImage]
    ) -> Text {
        var output = Text(verbatim: "")
        for piece in result.pieces {
            switch piece {
            case .text(let attributed):
                output = output + Text(attributed)

            case .math(let tex):
                if let image = mathImages[tex] {
                    output = output + image.image.markdownInlineText.baselineOffset(-image.depth)
                } else {
                    output = output
                        + Text(verbatim: "$\(tex)$")
                        .font(.system(size: style.monospacedCodeSize, design: .monospaced))
                        .foregroundColor(DS.Colors.labelTertiary)
                }

            case .image:
                break
            }
        }
        return output
    }

    // MARK: - 组装

    private static func styled(_ text: String, style: MarkdownInlineStyle) -> AttributedString {
        var attributed = AttributedString(text)
        var font = Font.system(size: style.fontSize, weight: style.weight)
        if style.italic {
            font = font.italic()
        }
        attributed.font = font
        attributed.foregroundColor = style.textColor
        if style.strikethrough {
            attributed.strikethroughStyle = .single
        }
        return attributed
    }

    private struct Builder {
        var pieces: [InlinePiece] = []
        var images: [String] = []
        var buffer = AttributedString()

        mutating func flush() {
            guard !buffer.characters.isEmpty else { return }
            pieces.append(.text(buffer))
            buffer = AttributedString()
        }

        mutating func appendStyled(_ text: String, style: MarkdownInlineStyle) {
            guard !text.isEmpty else { return }
            buffer.append(InlineRenderer.styled(text, style: style))
        }

        mutating func absorb(_ sub: Builder) {
            for piece in sub.pieces {
                switch piece {
                case .text(let attributed):
                    buffer.append(attributed)
                default:
                    flush()
                    pieces.append(piece)
                }
            }
            images.append(contentsOf: sub.images)
        }

        mutating func walk(_ inlines: [MarkdownInline], style: MarkdownInlineStyle) {
            for inline in inlines {
                switch inline {
                case .text(let value):
                    appendStyled(value, style: style)

                case .code(let value):
                    var attributed = AttributedString(value)
                    attributed.font = .system(size: style.monospacedCodeSize, design: .monospaced)
                    attributed.foregroundColor = style.codeColor
                    attributed.backgroundColor = style.codeBackground
                    buffer.append(attributed)

                case .strong(let children):
                    absorb(subResult(children, style: style.bolding()))

                case .emphasis(let children):
                    absorb(subResult(children, style: style.italicizing()))

                case .strikethrough(let children):
                    absorb(subResult(children, style: style.striking()))

                case .link(let destination, let children):
                    var sub = subResult(children, style: style)
                    let url = MarkdownLink.url(from: destination)
                    for index in sub.pieces.indices {
                        guard case .text(var attributed) = sub.pieces[index] else { continue }
                        if let url {
                            attributed.link = url
                        }
                        attributed.foregroundColor = style.linkColor
                        sub.pieces[index] = .text(attributed)
                    }
                    absorb(sub)

                case .image(let source, _):
                    flush()
                    images.append(source)

                case .math(let tex):
                    flush()
                    pieces.append(.math(tex))

                case .softBreak:
                    appendStyled(" ", style: style)

                case .hardBreak:
                    appendStyled("\n", style: style)
                }
            }
        }

        private func subResult(_ inlines: [MarkdownInline], style: MarkdownInlineStyle) -> Builder {
            var builder = Builder()
            builder.walk(inlines, style: style)
            builder.flush()
            return builder
        }
    }
}
