import Foundation

// MARK: - 行内

/// 行内节点。解析在后台完成，视图层只做属性字符串组装。
enum MarkdownInline: Sendable, Equatable {
    case text(String)
    case strong([MarkdownInline])
    case emphasis([MarkdownInline])
    case strikethrough([MarkdownInline])
    case code(String)
    case math(String)
    case link(destination: String, children: [MarkdownInline])
    case image(source: String, alt: [MarkdownInline])
    case softBreak
    case hardBreak

    var plainText: String {
        switch self {
        case .text(let value):
            return value
        case .strong(let children), .emphasis(let children), .strikethrough(let children):
            return children.map(\.plainText).joined()
        case .code(let value), .math(let value):
            return value
        case .link(_, let children):
            return children.map(\.plainText).joined()
        case .image(_, let alt):
            return alt.map(\.plainText).joined()
        case .softBreak:
            return " "
        case .hardBreak:
            return "\n"
        }
    }
}

extension Array where Element == MarkdownInline {
    var plainText: String { map(\.plainText).joined() }

    /// 段落里是否含未缓存的公式（视图层用来决定是否触发 Web 渲染）。
    var mathSources: [String] {
        var sources: [String] = []
        var seen = Set<String>()

        func walk(_ items: [MarkdownInline]) {
            for item in items {
                switch item {
                case .math(let tex):
                    if seen.insert(tex).inserted { sources.append(tex) }
                case .strong(let children), .emphasis(let children), .strikethrough(let children):
                    walk(children)
                case .link(_, let children):
                    walk(children)
                default:
                    break
                }
            }
        }

        walk(self)
        return sources
    }
}

// MARK: - 块级

enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, inlines: [MarkdownInline])
    case paragraph([MarkdownInline])
    case list(MarkdownListModel)
    case blockquote([MarkdownBlock])
    case code(MarkdownCodeModel)
    case table(MarkdownTableModel)
    case thematicBreak
    case math(source: String, isClosed: Bool)
}

struct MarkdownDocument: Sendable, Equatable {
    var blocks: [MarkdownBlock]
    var source: String

    static let empty = MarkdownDocument(blocks: [], source: "")

    var isEmpty: Bool { blocks.isEmpty }
}

struct MarkdownListModel: Sendable, Equatable {
    var isOrdered: Bool
    var start: Int
    var items: [MarkdownListItemModel]
}

struct MarkdownListItemModel: Sendable, Equatable {
    var blocks: [MarkdownBlock]
    /// nil = 普通列表项；true = 已勾选；false = 未勾选。
    var taskState: Bool?
}

struct MarkdownCodeModel: Sendable, Equatable {
    var language: String?
    var code: String
    /// 流式输出中围栏是否已闭合；未闭合时 mermaid 不渲染，降级为代码。
    var isClosed: Bool
    var lines: [CodeLine]

    var isMermaid: Bool {
        guard let language else { return false }
        return language.lowercased() == "mermaid"
    }

    var displayLanguage: String {
        guard let language, !language.isEmpty else { return "" }
        return language
    }
}

struct MarkdownTableModel: Sendable, Equatable {
    var header: [MarkdownTableCell]
    var rows: [[MarkdownTableCell]]
    var alignments: [MarkdownAlignment]

    func alignment(_ index: Int) -> MarkdownAlignment {
        alignments.indices.contains(index) ? alignments[index] : .leading
    }

    var columnCount: Int { header.count }
}

struct MarkdownTableCell: Sendable, Equatable {
    var inlines: [MarkdownInline]
}

enum MarkdownAlignment: String, Sendable, Equatable {
    case leading
    case center
    case trailing
}

// MARK: - 代码高亮

struct CodeLine: Sendable, Equatable {
    var tokens: [CodeToken]

    var plainText: String { tokens.map(\.text).joined() }
}

struct CodeToken: Sendable, Equatable {
    enum Kind: String, Sendable, Equatable {
        case plain
        case keyword
        case string
        case comment
        case number
        case type
        case punctuation
    }

    var kind: Kind
    var text: String
}
