import Foundation

/// 块级解析器。
///
/// 设计取舍：
/// - 纯函数、无状态，可在后台线程安全调用；
/// - 永不抛错：任何不完整输入（流式中的半截围栏/表格/公式）都退化成一个可渲染的块；
/// - 只覆盖 GFM 子集 + `$$` 数学 + mermaid 围栏，不执行原始 HTML。
enum MarkdownBlockParser {

    static func parse(_ text: String) -> MarkdownDocument {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else { return .empty }

        let lines = normalized.components(separatedBy: "\n")
        let blocks = parseBlocks(lines)
        if blocks.isEmpty, !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MarkdownDocument(blocks: [.paragraph([.text(normalized)])], source: text)
        }
        return MarkdownDocument(blocks: blocks, source: text)
    }

    // MARK: - 主循环

    static func parseBlocks(_ lines: [String]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let rawLine = lines[i]

            if isBlank(rawLine) {
                i += 1
                continue
            }

            // 围栏代码块
            if let fence = fenceOpen(rawLine) {
                var body: [String] = []
                var j = i + 1
                var closed = false
                while j < lines.count {
                    if fenceClose(lines[j], fence) {
                        closed = true
                        break
                    }
                    body.append(lines[j])
                    j += 1
                }
                let code = body.joined(separator: "\n")
                let language = fenceLanguage(fence.info)
                blocks.append(.code(MarkdownCodeModel(
                    language: language,
                    code: code,
                    isClosed: closed,
                    lines: SyntaxHighlighter.highlight(code, language: language)
                )))
                i = closed ? j + 1 : lines.count
                continue
            }

            // ATX 标题
            if let heading = heading(rawLine) {
                blocks.append(.heading(
                    level: heading.level,
                    inlines: MarkdownInlineParser.parse(heading.text)
                ))
                i += 1
                continue
            }

            // 块级公式
            if let math = mathBlock(lines, at: i) {
                blocks.append(.math(source: math.source, isClosed: math.closed))
                i = math.next
                continue
            }

            // 分割线（需在列表之前判断：`- - -` 是 hr 而不是列表）
            if isThematicBreak(rawLine) {
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            // 引用块
            if quoteContent(rawLine) != nil {
                var quoteLines: [String] = []
                var j = i
                while j < lines.count, let content = quoteContent(lines[j]) {
                    quoteLines.append(content)
                    j += 1
                }
                blocks.append(.blockquote(parseBlocks(quoteLines)))
                i = j
                continue
            }

            // 列表
            if listMarker(rawLine) != nil {
                let (list, next) = parseList(lines, at: i)
                blocks.append(.list(list))
                i = next
                continue
            }

            // 表格
            if let table = table(lines, at: i) {
                blocks.append(.table(table.model))
                i = table.next
                continue
            }

            // 段落
            var paragraph: [String] = []
            var j = i
            while j < lines.count {
                let line = lines[j]
                if isBlank(line) { break }
                if j > i {
                    if fenceOpen(line) != nil
                        || heading(line) != nil
                        || isThematicBreak(line)
                        || quoteContent(line) != nil
                        || listMarker(line) != nil
                        || mathBlock(lines, at: j) != nil
                        || table(lines, at: j) != nil {
                        break
                    }
                }
                paragraph.append(line)
                j += 1
            }

            if j == i {
                // 防御：绝不能原地踏步或丢内容。
                paragraph = [lines[i]]
                j = i + 1
            }

            let joined = paragraph.joined(separator: "\n")
            blocks.append(.paragraph(MarkdownInlineParser.parse(joined)))
            i = j
        }

        return blocks
    }

    // MARK: - 基础工具

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func indentation(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 }
            else if ch == "\t" { count += 4 }
            else { break }
        }
        return count
    }

    static func strippingIndent(_ line: String, _ width: Int) -> String {
        var remaining = width
        var index = line.startIndex
        while index < line.endIndex, remaining > 0 {
            let ch = line[index]
            if ch == " " {
                remaining -= 1
                index = line.index(after: index)
            } else if ch == "\t" {
                remaining -= 4
                index = line.index(after: index)
            } else {
                break
            }
        }
        return String(line[index...])
    }

    // MARK: - 围栏

    struct Fence {
        let char: Character
        let length: Int
        let info: String
    }

    static func fenceOpen(_ line: String) -> Fence? {
        let trimmed = line.drop(while: { $0 == " " })
        let leading = line.count - trimmed.count
        guard leading <= 3, let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix(while: { $0 == first })
        guard run.count >= 3 else { return nil }
        let info = trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
        if first == "`" && info.contains("`") { return nil }
        return Fence(char: first, length: run.count, info: info)
    }

    static func fenceClose(_ line: String, _ fence: Fence) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == fence.char else { return false }
        let run = trimmed.prefix(while: { $0 == first })
        guard run.count >= fence.length else { return false }
        return trimmed.dropFirst(run.count).allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func fenceLanguage(_ info: String) -> String? {
        guard let token = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else { return nil }
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "{}.,;"))
        return cleaned.isEmpty ? nil : String(cleaned)
    }

    // MARK: - 标题

    static func heading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.drop(while: { $0 == " " })
        let leading = line.count - trimmed.count
        guard leading <= 3 else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var content = rest.trimmingCharacters(in: .whitespaces)
        if content.hasSuffix("#") {
            let chars = Array(content)
            var cut = chars.count
            while cut > 0, chars[cut - 1] == "#" { cut -= 1 }
            if cut == 0 {
                content = ""
            } else if chars[cut - 1] == " " {
                content = String(chars[..<cut]).trimmingCharacters(in: .whitespaces)
            }
        }
        return (hashes.count, content)
    }

    // MARK: - 分割线

    static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.filter { $0 != " " && $0 != "\t" }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    // MARK: - 引用

    static func quoteContent(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " })
        let leading = line.count - trimmed.count
        guard leading <= 3, trimmed.first == ">" else { return nil }
        var rest = trimmed.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }

    // MARK: - 数学

    static func mathBlock(_ lines: [String], at index: Int) -> (source: String, closed: Bool, next: Int)? {
        guard index < lines.count else { return nil }
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("$$") else { return nil }

        // 单行 $$...$$
        if line.count >= 4, line.hasSuffix("$$") {
            let start = line.index(line.startIndex, offsetBy: 2)
            let end = line.index(line.endIndex, offsetBy: -2)
            let inner = String(line[start..<end]).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return nil }
            return (inner, true, index + 1)
        }

        guard line == "$$" else {
            // `$$ 内容` 开跨行：一直找到以 $$ 结尾的行
            var body: [String] = []
            let firstContent = String(line.dropFirst(2))
            if !firstContent.isEmpty { body.append(firstContent) }
            var j = index + 1
            while j < lines.count {
                let candidate = lines[j]
                if candidate.trimmingCharacters(in: .whitespaces).hasSuffix("$$") {
                    var text = candidate
                    if let range = text.range(of: "$$", options: .backwards) {
                        text.removeSubrange(range)
                    }
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty { body.append(text) }
                    return (body.joined(separator: "\n"), true, j + 1)
                }
                body.append(candidate)
                j += 1
            }
            return (body.joined(separator: "\n"), false, lines.count)
        }

        // 独占一行的 $$ 围栏
        var body: [String] = []
        var j = index + 1
        while j < lines.count {
            if lines[j].trimmingCharacters(in: .whitespaces) == "$$" {
                return (body.joined(separator: "\n"), true, j + 1)
            }
            body.append(lines[j])
            j += 1
        }
        return (body.joined(separator: "\n"), false, lines.count)
    }

    // MARK: - 列表

    struct ListMarker {
        var ordered: Bool
        var number: Int
        var indent: Int
        var contentIndent: Int
        var rest: String
    }

    static func listMarker(_ line: String) -> ListMarker? {
        var index = line.startIndex
        var spaces = 0
        while index < line.endIndex, line[index] == " " {
            spaces += 1
            index = line.index(after: index)
        }
        guard spaces <= 3, index < line.endIndex else { return nil }

        let first = line[index]
        if first == "-" || first == "*" || first == "+" {
            let after = line.index(after: index)
            if after == line.endIndex {
                return ListMarker(ordered: false, number: 0, indent: spaces, contentIndent: spaces + 1, rest: "")
            }
            guard line[after] == " " || line[after] == "\t" else { return nil }
            let contentStart = line.index(after: after)
            return ListMarker(
                ordered: false,
                number: 0,
                indent: spaces,
                contentIndent: spaces + 2,
                rest: String(line[contentStart...])
            )
        }

        var cursor = index
        var digits = ""
        while cursor < line.endIndex, line[cursor].isNumber, digits.count < 9 {
            digits.append(line[cursor])
            cursor = line.index(after: cursor)
        }
        guard !digits.isEmpty, cursor < line.endIndex, line[cursor] == "." || line[cursor] == ")" else {
            return nil
        }
        let afterMarker = line.index(after: cursor)
        guard afterMarker < line.endIndex, line[afterMarker] == " " || line[afterMarker] == "\t" else {
            return nil
        }
        let contentStart = line.index(after: afterMarker)
        return ListMarker(
            ordered: true,
            number: Int(digits) ?? 1,
            indent: spaces,
            contentIndent: spaces + digits.count + 2,
            rest: String(line[contentStart...])
        )
    }

    static func parseList(_ lines: [String], at start: Int) -> (MarkdownListModel, Int) {
        guard let first = listMarker(lines[start]) else { return (MarkdownListModel(isOrdered: false, start: 1, items: []), start + 1) }

        var items: [MarkdownListItemModel] = []
        var itemLines: [String] = []
        var taskState: Bool?
        var hasOpenItem = false
        var index = start

        func finishItem() {
            guard hasOpenItem else { return }
            while let last = itemLines.last, isBlank(last) {
                itemLines.removeLast()
            }
            let blocks = parseBlocks(itemLines)
            items.append(MarkdownListItemModel(blocks: blocks, taskState: taskState))
            itemLines = []
            taskState = nil
            hasOpenItem = false
        }

        while index < lines.count {
            let line = lines[index]

            if let marker = listMarker(line), marker.ordered == first.ordered, marker.indent == first.indent {
                finishItem()
                itemLines = [marker.rest]
                taskState = consumeTaskMarker(&itemLines)
                hasOpenItem = true
                index += 1
                continue
            }

            if isBlank(line) {
                var lookahead = index + 1
                while lookahead < lines.count, isBlank(lines[lookahead]) { lookahead += 1 }
                if lookahead >= lines.count { break }
                if let marker = listMarker(lines[lookahead]),
                   marker.ordered == first.ordered,
                   marker.indent == first.indent {
                    index = lookahead
                    continue
                }
                if indentation(lines[lookahead]) >= first.contentIndent {
                    itemLines.append("")
                    index += 1
                    continue
                }
                break
            }

            if indentation(line) >= first.contentIndent {
                itemLines.append(strippingIndent(line, first.contentIndent))
                index += 1
                continue
            }

            break
        }

        finishItem()

        let model = MarkdownListModel(
            isOrdered: first.ordered,
            start: first.ordered ? first.number : 1,
            items: items
        )
        return (model, index)
    }

    /// `- [ ] foo` / `- [x] foo`；返回是否勾选，并把首行内容改成去掉标记后的文本。
    static func consumeTaskMarker(_ itemLines: inout [String]) -> Bool? {
        guard !itemLines.isEmpty else { return nil }
        let line = itemLines[0].drop(while: { $0 == " " })
        guard line.hasPrefix("[") else { return nil }
        let chars = Array(line)
        guard chars.count >= 3, chars[2] == "]" else { return nil }
        guard chars[1] == " " || chars[1] == "x" || chars[1] == "X" else { return nil }
        let rest = String(chars.dropFirst(3))
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        itemLines[0] = String(rest.drop(while: { $0 == " " }))
        return chars[1] != " "
    }

    // MARK: - 表格

    static func table(_ lines: [String], at index: Int) -> (model: MarkdownTableModel, next: Int)? {
        guard index + 1 < lines.count else { return nil }
        let headerLine = lines[index]
        guard headerLine.contains("|") else { return nil }
        guard let alignments = tableAlignments(lines[index + 1]) else { return nil }
        guard !alignments.isEmpty else { return nil }

        var header = splitCells(headerLine).map { MarkdownTableCell(inlines: MarkdownInlineParser.parse($0)) }
        guard !header.isEmpty else { return nil }
        if header.count != alignments.count {
            if header.count < alignments.count {
                header.append(contentsOf: Array(repeating: MarkdownTableCell(inlines: []), count: alignments.count - header.count))
            } else {
                header = Array(header.prefix(alignments.count))
            }
        }

        var rows: [[MarkdownTableCell]] = []
        var j = index + 2
        while j < lines.count {
            let line = lines[j]
            if isBlank(line) { break }
            guard line.contains("|") else { break }
            guard fenceOpen(line) == nil, heading(line) == nil else { break }
            var cells = splitCells(line).map { MarkdownTableCell(inlines: MarkdownInlineParser.parse($0)) }
            if cells.count < alignments.count {
                cells.append(contentsOf: Array(repeating: MarkdownTableCell(inlines: []), count: alignments.count - cells.count))
            } else if cells.count > alignments.count {
                cells = Array(cells.prefix(alignments.count))
            }
            rows.append(cells)
            j += 1
        }

        return (MarkdownTableModel(header: header, rows: rows, alignments: alignments), j)
    }

    static func tableAlignments(_ line: String) -> [MarkdownAlignment]? {
        let raw = splitCells(line)
        guard !raw.isEmpty else { return nil }
        var alignments: [MarkdownAlignment] = []
        for cell in raw {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            guard trimmed.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }
            guard trimmed.contains("-") else { return nil }
            let left = trimmed.hasPrefix(":")
            let right = trimmed.hasSuffix(":")
            if left && right {
                alignments.append(.center)
            } else if right {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }
        return alignments
    }

    /// 按未转义、且不在反引号内的 `|` 切分；去掉首尾管道产生的空单元格。
    static func splitCells(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var escaped = false
        var inCode = false

        for ch in line {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                current.append(ch)
                escaped = true
                continue
            }
            if ch == "`" {
                inCode.toggle()
                current.append(ch)
                continue
            }
            if ch == "|" && !inCode {
                cells.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        cells.append(current)

        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.hasPrefix("|"), cells.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeFirst()
        }
        if trimmedLine.hasSuffix("|"), cells.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            cells.removeLast()
        }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
