import Foundation

/// 轻量语法着色器。
///
/// 目标不是完整语法分析，而是「关键词 / 字符串 / 注释 / 数字 / 类型」五类 token 的稳定着色，
/// 覆盖 swift / typescript / javascript / python / json / bash / html / css / sql。
/// 未知语言退化为纯文本（仍然可复制、可横向滚动）。
enum SyntaxHighlighter {

    static func highlight(_ code: String, language: String?) -> [CodeLine] {
        let display = code.hasSuffix("\n") ? String(code.dropLast()) : code
        guard !display.isEmpty else { return [CodeLine(tokens: [])] }
        guard let spec = LanguageSpec.spec(for: language) else {
            return plainLines(display)
        }
        var lexer = Lexer(spec: spec, chars: Array(display))
        return lexer.run()
    }

    static func plainLines(_ code: String) -> [CodeLine] {
        code.components(separatedBy: "\n").map { line in
            CodeLine(tokens: line.isEmpty ? [] : [CodeToken(kind: .plain, text: line)])
        }
    }
}

// MARK: - 语言配置

struct LanguageSpec {
    var keywords: Set<String>
    var types: Set<String> = []
    var lineComments: [String] = []
    var blockComments: [(start: String, end: String)] = []
    var stringDelimiters: Set<Character> = ["\""]
    var tripleQuoted = false
    var caseInsensitiveKeywords = false
    var capitalizeIsType = false
    var isHTML = false
    var isCSS = false

    static func spec(for language: String?) -> LanguageSpec? {
        guard let raw = language?.lowercased(), !raw.isEmpty else { return nil }
        let name = raw.hasPrefix("language-") ? String(raw.dropFirst("language-".count)) : raw

        switch name {
        case "swift":
            return LanguageSpec(
                keywords: words("""
                func let var if else guard return class struct enum protocol extension import for while switch case default break continue init deinit self super throws throw try catch as is in where associatedtype typealias public private internal fileprivate open static final lazy weak unowned mutating nonmutating override required convenience subscript operator async await actor some any nil true false defer do repeat inout indirect willSet didSet nonisolated consuming borrowing package
                """),
                types: words("""
                String Int Int64 Int32 Double Float Bool CGFloat Character Array Dictionary Set Optional Any AnyObject Void Never Error Result URL Date Data Range ClosedRange UInt UInt8 UInt16 UInt32 UInt64 Task MainActor
                """),
                lineComments: ["//"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\""],
                tripleQuoted: true,
                capitalizeIsType: true
            )

        case "typescript", "ts", "tsx":
            return LanguageSpec(
                keywords: words("""
                const let var function return if else for while do switch case default break continue class extends new this super import export from as async await yield try catch finally throw typeof instanceof in of delete void null undefined true false interface type enum implements public private protected readonly static get set declare namespace satisfies keyof infer never unknown any string number boolean object symbol bigint
                """),
                types: words("""
                Promise Array Record Partial Readonly Pick Omit Map Set Date Error RegExp String Number Boolean Object Function Symbol JSON Math Number
                """),
                lineComments: ["//"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\"", "'", "`"],
                capitalizeIsType: true
            )

        case "javascript", "js", "jsx", "node", "mjs", "cjs", "javascriptreact":
            return LanguageSpec(
                keywords: words("""
                const let var function return if else for while do switch case default break continue class extends new this super import export from as async await yield try catch finally throw typeof instanceof in of delete void null undefined true false
                """),
                types: words("Promise Array Map Set Date Error RegExp String Number Boolean Object Function Symbol JSON Math console window document"),
                lineComments: ["//"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\"", "'", "`"],
                capitalizeIsType: true
            )

        case "python", "py", "python3":
            return LanguageSpec(
                keywords: words("""
                def class return if elif else for while break continue import from as with try except finally raise pass lambda yield global nonlocal assert del in is not and or None True False async await match case self
                """),
                types: words("str int float bool list dict set tuple bytes object Exception ValueError TypeError KeyError RuntimeError"),
                lineComments: ["#"],
                stringDelimiters: ["\"", "'"],
                tripleQuoted: true,
                capitalizeIsType: true
            )

        case "json", "jsonc", "json5":
            return LanguageSpec(
                keywords: words("true false null"),
                lineComments: ["//"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\""]
            )

        case "bash", "sh", "shell", "zsh", "console", "terminal":
            return LanguageSpec(
                keywords: words("""
                if then else elif fi for while until do done case esac function in select time coproc return break continue export local readonly declare typeset unset shift source alias echo printf cd pwd set trap exit
                """),
                lineComments: ["#"],
                stringDelimiters: ["\"", "'"],
                capitalizeIsType: false
            )

        case "html", "xml", "svg", "vue", "xhtml":
            return LanguageSpec(
                keywords: words("html head body div span a img script style link meta title section article header footer nav main p ul ol li table thead tbody tr td th form input button label select option textarea svg path g defs use"),
                lineComments: [],
                blockComments: [("<!--", "-->")],
                stringDelimiters: ["\"", "'"],
                isHTML: true
            )

        case "css", "scss", "less", "sass":
            return LanguageSpec(
                keywords: words("""
                @media @import @keyframes @font-face @supports @layer @container @charset @page @namespace
                """),
                lineComments: ["//"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["\"", "'"],
                isCSS: true
            )

        case "sql", "mysql", "postgres", "postgresql", "psql", "sqlite":
            return LanguageSpec(
                keywords: words("""
                select from where join inner left right outer full on group by order having limit offset insert into values update set delete create table index view drop alter add column primary key foreign references not null and or in exists as distinct union all case when then else end asc desc like between is count sum avg min max begin commit rollback transaction with returning default constraint unique if exists database schema grant revoke
                """),
                types: words("int integer bigint smallint varchar text char boolean date timestamp timestamptz numeric decimal float double serial uuid json jsonb blob"),
                lineComments: ["--"],
                blockComments: [("/*", "*/")],
                stringDelimiters: ["'", "\""],
                caseInsensitiveKeywords: true
            )

        default:
            return nil
        }
    }

    private static func words(_ raw: String) -> Set<String> {
        Set(raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init))
    }
}

// MARK: - 词法器

private struct Lexer {
    let spec: LanguageSpec
    let chars: [Character]
    var index = 0
    var tokens: [CodeToken] = []

    init(spec: LanguageSpec, chars: [Character]) {
        self.spec = spec
        self.chars = chars
    }

    mutating func run() -> [CodeLine] {
        while index < chars.count {
            if spec.isHTML, scanHTMLTag() { continue }
            if scanBlockComment() { continue }
            if scanLineComment() { continue }
            if scanString() { continue }

            let ch = chars[index]

            if ch == "\n" {
                emit("\n", .plain)
                index += 1
                continue
            }

            if ch == " " || ch == "\t" {
                var end = index
                while end < chars.count, chars[end] == " " || chars[end] == "\t" { end += 1 }
                emit(String(chars[index..<end]), .plain)
                index = end
                continue
            }

            if ch.isNumber {
                scanNumber()
                continue
            }

            if spec.isCSS, ch == "@", index + 1 < chars.count, isIdentifierStart(chars[index + 1]) {
                scanAtRule()
                continue
            }

            if spec.isCSS, ch == "#", index + 1 < chars.count, chars[index + 1].isHexDigit {
                scanHexColor()
                continue
            }

            if isIdentifierStart(ch) {
                scanIdentifier()
                continue
            }

            emit(String(ch), .punctuation)
            index += 1
        }
        return splitLines()
    }

    // MARK: 输出

    private mutating func emit(_ text: String, _ kind: CodeToken.Kind) {
        guard !text.isEmpty else { return }
        if let last = tokens.last, last.kind == kind {
            tokens[tokens.count - 1].text += text
        } else {
            tokens.append(CodeToken(kind: kind, text: text))
        }
    }

    private func splitLines() -> [CodeLine] {
        var lines: [CodeLine] = []
        var current: [CodeToken] = []

        for token in tokens {
            let parts = token.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (offset, part) in parts.enumerated() {
                if offset > 0 {
                    lines.append(CodeLine(tokens: current))
                    current = []
                }
                guard !part.isEmpty else { continue }
                let text = String(part)
                if let last = current.last, last.kind == token.kind {
                    current[current.count - 1].text += text
                } else {
                    current.append(CodeToken(kind: token.kind, text: text))
                }
            }
        }
        lines.append(CodeLine(tokens: current))
        return lines
    }

    // MARK: 注释

    private mutating func scanBlockComment() -> Bool {
        for pair in spec.blockComments where match(pair.start) {
            var end = index + pair.start.count
            var found = false
            while end < chars.count {
                if match(pair.end, at: end) {
                    end += pair.end.count
                    found = true
                    break
                }
                end += 1
            }
            emit(String(chars[index..<(found ? min(end, chars.count) : chars.count)]), .comment)
            index = found ? end : chars.count
            return true
        }
        return false
    }

    private mutating func scanLineComment() -> Bool {
        for prefix in spec.lineComments where match(prefix) {
            var end = index
            while end < chars.count, chars[end] != "\n" { end += 1 }
            emit(String(chars[index..<end]), .comment)
            index = end
            return true
        }
        return false
    }

    // MARK: 字符串

    private mutating func scanString() -> Bool {
        let ch = chars[index]
        guard spec.stringDelimiters.contains(ch) else { return false }

        var delimiterCount = 1
        if spec.tripleQuoted {
            let run = countRun(ch, from: index)
            if run >= 3 { delimiterCount = 3 }
        }

        let triple = delimiterCount == 3
        var cursor = index + delimiterCount
        let allowsNewline = triple || ch == "`"

        while cursor < chars.count {
            let current = chars[cursor]
            if current == "\\" {
                cursor += 2
                continue
            }
            if current == "\n", !allowsNewline {
                break
            }
            if current == ch {
                if triple {
                    if countRun(ch, from: cursor) >= 3 {
                        cursor += 3
                        emit(String(chars[index..<cursor]), .string)
                        index = cursor
                        return true
                    }
                } else {
                    cursor += 1
                    emit(String(chars[index..<cursor]), .string)
                    index = cursor
                    return true
                }
            }
            cursor += 1
        }

        // 未闭合：把已有内容当字符串，避免吞掉后续内容。
        let end = min(cursor, chars.count)
        emit(String(chars[index..<end]), .string)
        index = end
        return true
    }

    // MARK: 数字与标识符

    private mutating func scanNumber() {
        var cursor = index
        if chars[cursor] == "0", cursor + 1 < chars.count, chars[cursor + 1] == "x" || chars[cursor + 1] == "X" {
            cursor += 2
            while cursor < chars.count, chars[cursor].isHexDigit || chars[cursor] == "_" { cursor += 1 }
        } else {
            while cursor < chars.count, chars[cursor].isNumber || chars[cursor] == "_" { cursor += 1 }
            if cursor < chars.count, chars[cursor] == ".", cursor + 1 < chars.count, chars[cursor + 1].isNumber {
                cursor += 1
                while cursor < chars.count, chars[cursor].isNumber || chars[cursor] == "_" { cursor += 1 }
            }
            if cursor < chars.count, chars[cursor] == "e" || chars[cursor] == "E" {
                var exponent = cursor + 1
                if exponent < chars.count, chars[exponent] == "+" || chars[exponent] == "-" { exponent += 1 }
                if exponent < chars.count, chars[exponent].isNumber {
                    cursor = exponent
                    while cursor < chars.count, chars[cursor].isNumber { cursor += 1 }
                }
            }
        }
        emit(String(chars[index..<cursor]), .number)
        index = cursor
    }

    private mutating func scanIdentifier() {
        var cursor = index
        while cursor < chars.count, isIdentifierPart(chars[cursor]) { cursor += 1 }
        let word = String(chars[index..<cursor])
        index = cursor

        let lowered = word.lowercased()
        let lookup = spec.caseInsensitiveKeywords ? lowered : word
        if spec.keywords.contains(lookup) {
            emit(word, .keyword)
            return
        }
        if spec.types.contains(lookup) {
            emit(word, .type)
            return
        }
        if spec.capitalizeIsType, let first = word.first, first.isUppercase, word.count > 1 {
            emit(word, .type)
            return
        }
        if spec.isCSS {
            var lookahead = cursor
            while lookahead < chars.count, chars[lookahead] == " " { lookahead += 1 }
            if lookahead < chars.count, chars[lookahead] == ":" {
                emit(word, .type)
                return
            }
        }
        emit(word, .plain)
    }

    private mutating func scanAtRule() {
        var cursor = index + 1
        while cursor < chars.count, isIdentifierPart(chars[cursor]) { cursor += 1 }
        emit(String(chars[index..<cursor]), .keyword)
        index = cursor
    }

    private mutating func scanHexColor() {
        var cursor = index
        while cursor < chars.count, chars[cursor].isHexDigit { cursor += 1 }
        emit(String(chars[index..<cursor]), .number)
        index = cursor
    }

    // MARK: HTML

    private mutating func scanHTMLTag() -> Bool {
        guard chars[index] == "<" else { return false }

        if match("<!--") {
            var end = index + 4
            while end < chars.count {
                if match("-->", at: end) {
                    end += 3
                    emit(String(chars[index..<end]), .comment)
                    index = end
                    return true
                }
                end += 1
            }
            emit(String(chars[index...]), .comment)
            index = chars.count
            return true
        }

        let next = index + 1
        guard next < chars.count else { return false }
        let isClosing = chars[next] == "/"
        let nameStart = isClosing ? next + 1 : next
        guard nameStart < chars.count, isIdentifierStart(chars[nameStart]) else { return false }

        emit("<", .punctuation)
        if isClosing { emit("/", .punctuation) }
        index = nameStart

        var cursor = index
        while cursor < chars.count, isIdentifierPart(chars[cursor]) { cursor += 1 }
        emit(String(chars[index..<cursor]), .keyword)
        index = cursor

        while index < chars.count {
            let ch = chars[index]
            if ch == ">" {
                emit(">", .punctuation)
                index += 1
                return true
            }
            if ch == "\n" {
                emit("\n", .plain)
                index += 1
                return true
            }
            if ch == " " || ch == "\t" {
                var end = index
                while end < chars.count, chars[end] == " " || chars[end] == "\t" { end += 1 }
                emit(String(chars[index..<end]), .plain)
                index = end
                continue
            }
            if spec.stringDelimiters.contains(ch) {
                _ = scanString()
                continue
            }
            if ch == "=" || ch == "/" || ch == "-" {
                emit(String(ch), .punctuation)
                index += 1
                continue
            }
            if isIdentifierStart(ch) {
                var end = index
                while end < chars.count, isIdentifierPart(chars[end]) || chars[end] == "-" || chars[end] == ":" {
                    end += 1
                }
                emit(String(chars[index..<end]), .type)
                index = end
                continue
            }
            emit(String(ch), .plain)
            index += 1
        }
        return true
    }

    // MARK: 工具

    private func match(_ text: String, at position: Int? = nil) -> Bool {
        let start = position ?? index
        let needle = Array(text)
        guard start + needle.count <= chars.count else { return false }
        for offset in 0..<needle.count where chars[start + offset] != needle[offset] {
            return false
        }
        return true
    }

    private func countRun(_ ch: Character, from start: Int) -> Int {
        var count = 0
        var cursor = start
        while cursor < chars.count, chars[cursor] == ch {
            count += 1
            cursor += 1
        }
        return count
    }

    private func isIdentifierStart(_ ch: Character) -> Bool {
        ch.isLetter || ch == "_" || ch == "$"
    }

    private func isIdentifierPart(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_" || ch == "$"
    }
}
