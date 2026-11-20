import Foundation

/// 行内解析器（CommonMark 子集 + GFM 自动链接/删除线 + `$...$` 数学）。
///
/// 解析是纯函数；所有不完整输入（未闭合的强调/链接/公式）都原样保留为文本。
enum MarkdownInlineParser {

    static func parse(_ text: String) -> [MarkdownInline] {
        parse(Array(text), allowAutolink: true)
    }

    private struct Span {
        let inline: MarkdownInline
        let end: Int
    }

    private static let escapable: Set<Character> = [
        "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#",
        "+", "-", ".", "!", "|", ">", "~", "$", "\"", "'", ":", ";",
        "=", "<", "@", "^", "/", "&", "%"
    ]

    private static let trailingURLPunctuation: Set<Character> = [
        ".", ",", ";", ":", "!", "?", "'", "\""
    ]

    static func parse(_ chars: [Character], allowAutolink: Bool) -> [MarkdownInline] {
        guard !chars.isEmpty else { return [] }

        var output: [MarkdownInline] = []
        var buffer = ""

        func flush() {
            if !buffer.isEmpty {
                output.append(.text(buffer))
                buffer = ""
            }
        }

        var index = 0
        while index < chars.count {
            let ch = chars[index]

            switch ch {
            case "\\":
                if index + 1 < chars.count {
                    let next = chars[index + 1]
                    if next == "\n" {
                        flush()
                        output.append(.hardBreak)
                        index += 2
                        continue
                    }
                    if escapable.contains(next) {
                        buffer.append(next)
                        index += 2
                        continue
                    }
                }
                buffer.append(ch)
                index += 1

            case "\n":
                var spaces = 0
                while buffer.last == " " {
                    buffer.removeLast()
                    spaces += 1
                }
                flush()
                output.append(spaces >= 2 ? .hardBreak : .softBreak)
                index += 1

            case "`":
                let run = runLength(of: "`", in: chars, at: index)
                if let close = findRun(of: "`", length: run, in: chars, from: index + run) {
                    var content = String(chars[(index + run)..<close])
                    content = content.replacingOccurrences(of: "\n", with: " ")
                    if content.count >= 2,
                       content.hasPrefix(" "),
                       content.hasSuffix(" "),
                       content.contains(where: { $0 != " " }) {
                        content = String(content.dropFirst().dropLast())
                    }
                    flush()
                    output.append(.code(content))
                    index = close + run
                } else {
                    buffer.append(contentsOf: String(repeating: "`", count: run))
                    index += run
                }

            case "$":
                if let span = parseMath(chars, at: index) {
                    flush()
                    output.append(span.inline)
                    index = span.end
                } else {
                    buffer.append(ch)
                    index += 1
                }

            case "!":
                if index + 1 < chars.count,
                   chars[index + 1] == "[",
                   let span = parseLinkLike(chars, at: index, isImage: true) {
                    flush()
                    output.append(span.inline)
                    index = span.end
                } else {
                    buffer.append(ch)
                    index += 1
                }

            case "[":
                if let span = parseLinkLike(chars, at: index, isImage: false) {
                    flush()
                    output.append(span.inline)
                    index = span.end
                } else {
                    buffer.append(ch)
                    index += 1
                }

            case "<":
                if let span = parseAutolink(chars, at: index) {
                    flush()
                    output.append(span.inline)
                    index = span.end
                } else {
                    buffer.append(ch)
                    index += 1
                }

            case "*", "_":
                if let span = parseEmphasis(chars, at: index) {
                    flush()
                    output.append(span.inline)
                    index = span.end
                } else {
                    buffer.append(ch)
                    index += 1
                }

            case "~":
                if let span = parseStrikethrough(chars, at: index) {
                    flush()
                    output.append(span.inline)
                    index = span.end
                } else {
                    buffer.append(ch)
                    index += 1
                }

            case "&":
                if let entity = parseEntity(chars, at: index) {
                    buffer.append(entity.text)
                    index = entity.end
                } else {
                    buffer.append(ch)
                    index += 1
                }

            default:
                if allowAutolink,
                   (ch == "h" || ch == "H" || ch == "w" || ch == "W"),
                   isURLBoundary(chars, at: index),
                   let span = parseBareURL(chars, at: index) {
                    flush()
                    output.append(span.inline)
                    index = span.end
                } else {
                    buffer.append(ch)
                    index += 1
                }
            }
        }

        flush()
        return output
    }

    // MARK: - 基础扫描

    private static func runLength(of target: Character, in chars: [Character], at index: Int) -> Int {
        var count = 0
        var i = index
        while i < chars.count, chars[i] == target {
            count += 1
            i += 1
        }
        return count
    }

    /// 查找长度恰好为 `length` 的连续 target 序列（跳过更长的 run，避免 `*` 误吃 `**`）。
    private static func findRun(of target: Character, length: Int, in chars: [Character], from start: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == target {
                let run = runLength(of: target, in: chars, at: i)
                if run == length { return i }
                i += run
            } else {
                i += 1
            }
        }
        return nil
    }

    private static func isWordCharacter(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_"
    }

    // MARK: - 数学

    private static func parseMath(_ chars: [Character], at index: Int) -> Span? {
        guard chars[index] == "$" else { return nil }

        if index + 1 < chars.count, chars[index + 1] == "$" {
            var j = index + 2
            while j + 1 < chars.count {
                if chars[j] == "$", chars[j + 1] == "$" {
                    let content = String(chars[(index + 2)..<j])
                    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    return Span(inline: .math(content), end: j + 2)
                }
                j += 1
            }
            return nil
        }

        guard index + 1 < chars.count,
              !chars[index + 1].isWhitespace,
              chars[index + 1] != "$" else { return nil }

        var j = index + 1
        while j < chars.count {
            let ch = chars[j]
            if ch == "\n" { return nil }
            if ch == "\\" {
                j += 2
                continue
            }
            if ch == "$", j > index + 1, !chars[j - 1].isWhitespace {
                let content = String(chars[(index + 1)..<j])
                // `$5`、`$1,000.00` 这类货币不当公式
                let looksLikeMoney = content.allSatisfy { $0.isNumber || $0 == "," || $0 == "." }
                if looksLikeMoney { return nil }
                return Span(inline: .math(content), end: j + 1)
            }
            j += 1
        }
        return nil
    }

    // MARK: - 强调 / 删除线

    private static func parseEmphasis(_ chars: [Character], at index: Int) -> Span? {
        let marker = chars[index]
        let run = runLength(of: marker, in: chars, at: index)
        let length = min(run, 3)
        guard index + length < chars.count else { return nil }
        guard !chars[index + length].isWhitespace else { return nil }
        if marker == "_", index > 0, isWordCharacter(chars[index - 1]) { return nil }

        var j = index + length
        while j < chars.count {
            if chars[j] == "\\" {
                j += 2
                continue
            }
            if chars[j] == marker {
                let closeRun = runLength(of: marker, in: chars, at: j)
                if closeRun == length, j > index + length, !chars[j - 1].isWhitespace {
                    if marker == "_", j + length < chars.count, isWordCharacter(chars[j + length]) {
                        j += closeRun
                        continue
                    }
                    let inner = Array(chars[(index + length)..<j])
                    let children = parse(inner, allowAutolink: false)
                    if children.isEmpty {
                        j += closeRun
                        continue
                    }
                    let wrapped: MarkdownInline
                    switch length {
                    case 1: wrapped = .emphasis(children)
                    case 2: wrapped = .strong(children)
                    default: wrapped = .strong([.emphasis(children)])
                    }
                    return Span(inline: wrapped, end: j + length)
                }
                j += closeRun
            } else {
                j += 1
            }
        }
        return nil
    }

    private static func parseStrikethrough(_ chars: [Character], at index: Int) -> Span? {
        guard index + 1 < chars.count,
              chars[index] == "~",
              chars[index + 1] == "~" else { return nil }
        let start = index + 2
        guard start < chars.count, !chars[start].isWhitespace else { return nil }
        var j = start
        while j + 1 < chars.count {
            if chars[j] == "~", chars[j + 1] == "~", j > start, !chars[j - 1].isWhitespace {
                let inner = Array(chars[start..<j])
                let children = parse(inner, allowAutolink: false)
                guard !children.isEmpty else { return nil }
                return Span(inline: .strikethrough(children), end: j + 2)
            }
            j += 1
        }
        return nil
    }

    // MARK: - 链接 / 图片

    private static func parseLinkLike(_ chars: [Character], at index: Int, isImage: Bool) -> Span? {
        let bracket = isImage ? index + 1 : index
        guard bracket < chars.count, chars[bracket] == "[" else { return nil }

        var depth = 0
        var cursor = bracket
        var closeBracket: Int?
        while cursor < chars.count {
            let ch = chars[cursor]
            if ch == "\\" {
                cursor += 2
                continue
            }
            if ch == "[" {
                depth += 1
            } else if ch == "]" {
                depth -= 1
                if depth == 0 {
                    closeBracket = cursor
                    break
                }
            }
            cursor += 1
        }
        guard let close = closeBracket, close + 1 < chars.count, chars[close + 1] == "(" else {
            return nil
        }

        var parenDepth = 0
        var k = close + 1
        var closeParen: Int?
        while k < chars.count {
            let ch = chars[k]
            if ch == "\\" {
                k += 2
                continue
            }
            if ch == "(" {
                parenDepth += 1
            } else if ch == ")" {
                parenDepth -= 1
                if parenDepth == 0 {
                    closeParen = k
                    break
                }
            }
            k += 1
        }
        guard let endParen = closeParen else { return nil }

        let labelChars = Array(chars[(bracket + 1)..<close])
        let rawDestination = String(chars[(close + 2)..<endParen])
        guard let destination = splitDestination(rawDestination) else { return nil }

        if isImage {
            let alt = parse(labelChars, allowAutolink: false)
            return Span(inline: .image(source: destination, alt: alt), end: endParen + 1)
        }

        let children = parse(labelChars, allowAutolink: false)
        guard !children.isEmpty else { return nil }
        return Span(inline: .link(destination: destination, children: children), end: endParen + 1)
    }

    private static func splitDestination(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("<") {
            guard let close = trimmed.firstIndex(of: ">") else { return nil }
            let url = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            guard !url.isEmpty else { return nil }
            return unescape(url)
        }

        var urlEnd = trimmed.endIndex
        var depth = 0
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let ch = trimmed[index]
            if ch == "\\" {
                index = trimmed.index(after: index)
                if index < trimmed.endIndex { index = trimmed.index(after: index) }
                continue
            }
            if ch == "(" { depth += 1 }
            if ch == ")" { depth = max(0, depth - 1) }
            if (ch == " " || ch == "\t" || ch == "\n"), depth == 0 {
                urlEnd = index
                break
            }
            index = trimmed.index(after: index)
        }

        let urlPart = String(trimmed[..<urlEnd])
        guard !urlPart.isEmpty else { return nil }
        return unescape(urlPart)
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        var pending: Character?
        while let ch = pending ?? iterator.next() {
            pending = nil
            if ch == "\\", let next = iterator.next() {
                result.append(next)
            } else {
                result.append(ch)
            }
        }
        return result
    }

    // MARK: - 自动链接

    private static func parseAutolink(_ chars: [Character], at index: Int) -> Span? {
        var j = index + 1
        while j < chars.count, chars[j] != ">", chars[j] != "\n", chars[j] != " " { j += 1 }
        guard j < chars.count, chars[j] == ">" else { return nil }
        let content = String(chars[(index + 1)..<j])
        guard !content.isEmpty else { return nil }

        if isEmailAddress(content) {
            return Span(inline: .link(destination: "mailto:\(content)", children: [.text(content)]), end: j + 1)
        }
        if hasScheme(content) {
            return Span(inline: .link(destination: content, children: [.text(content)]), end: j + 1)
        }
        return nil
    }

    private static func hasScheme(_ value: String) -> Bool {
        guard let colon = value.firstIndex(of: ":") else { return false }
        let scheme = value[value.startIndex..<colon]
        guard (2...32).contains(scheme.count) else { return false }
        guard let first = scheme.first, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
    }

    private static func isEmailAddress(_ value: String) -> Bool {
        guard let at = value.firstIndex(of: "@"), at != value.startIndex else { return false }
        let domain = value[value.index(after: at)...]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return !value.contains(" ") && !value.contains("\n")
    }

    private static func isURLBoundary(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = chars[index - 1]
        if previous.isWhitespace { return true }
        if !previous.isASCII { return true }   // 允许「见https://…」这类中文直连
        return !(previous.isLetter || previous.isNumber || previous == "@" || previous == "." || previous == "-" || previous == "_")
    }

    private static func parseBareURL(_ chars: [Character], at index: Int) -> Span? {
        let candidate = String(chars[index...])
        let lowered = candidate.lowercased()
        let prefix: String
        if lowered.hasPrefix("https://") {
            prefix = "https://"
        } else if lowered.hasPrefix("http://") {
            prefix = "http://"
        } else if lowered.hasPrefix("www.") {
            prefix = "www."
        } else {
            return nil
        }

        var j = index
        while j < chars.count {
            let ch = chars[j]
            if ch.isWhitespace || ch == "<" || ch == ">" || ch == "\"" || ch == "`" { break }
            j += 1
        }
        var urlChars = Array(chars[index..<j])
        while let last = urlChars.last, trailingURLPunctuation.contains(last) {
            urlChars.removeLast()
        }
        while let last = urlChars.last,
              last == ")",
              urlChars.filter({ $0 == "(" }).count < urlChars.filter({ $0 == ")" }).count {
            urlChars.removeLast()
        }
        guard urlChars.count > prefix.count else { return nil }

        var url = String(urlChars)
        if prefix == "www." { url = "https://" + url }
        let display = String(urlChars)
        return Span(inline: .link(destination: url, children: [.text(display)]), end: index + urlChars.count)
    }

    // MARK: - HTML 实体

    private static func parseEntity(_ chars: [Character], at index: Int) -> (text: String, end: Int)? {
        var j = index + 1
        var body = ""
        while j < chars.count, j - index <= 12 {
            let ch = chars[j]
            if ch == ";" {
                guard let decoded = decodeEntity(body) else { return nil }
                return (decoded, j + 1)
            }
            guard ch.isLetter || ch.isNumber || ch == "#" else { return nil }
            body.append(ch)
            j += 1
        }
        return nil
    }

    private static func decodeEntity(_ body: String) -> String? {
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "nbsp": "\u{00A0}", "mdash": "—", "ndash": "–", "hellip": "…",
            "copy": "©", "reg": "®", "trade": "™", "times": "×", "divide": "÷",
            "plusmn": "±", "le": "≤", "ge": "≥", "ne": "≠", "rarr": "→",
            "larr": "←", "harr": "↔", "deg": "°", "middot": "·", "laquo": "«",
            "raquo": "»", "sup2": "²", "sup3": "³", "frac12": "½"
        ]
        if body.hasPrefix("#") {
            let digits = String(body.dropFirst())
            let scalarValue: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                scalarValue = UInt32(digits.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(digits)
            }
            if let scalarValue, let scalar = Unicode.Scalar(scalarValue) {
                return String(Character(scalar))
            }
            return nil
        }
        return named[body]
    }
}
