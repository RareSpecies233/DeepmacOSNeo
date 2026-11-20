import Foundation

// MARK: - 请求消息

/// 请求里的一条消息。`blocks` 只在 assistant 历史里还原成 Anthropic content blocks；
/// user / latest_reminder 还原成字符串。
public struct RequestMessage: Sendable, Encodable {
    public enum Role: String, Encodable, Sendable {
        case user
        case assistant
        case latestReminder = "latest_reminder"
    }

    public var role: Role
    public var blocks: [Block]

    public init(role: Role, blocks: [Block]) {
        self.role = role
        self.blocks = blocks
    }

    /// 便捷构造：单段文本消息（用户提问或 latest_reminder）。
    public init(role: Role, text: String) {
        self.init(role: role, blocks: [Block(id: "t0", kind: .text, text: text)])
    }

    /// 便捷构造：从已保存的消息转换（assistant 历史或用户提问）。
    public init(_ message: ChatMessage) {
        self.init(role: message.role == .user ? .user : .assistant, blocks: message.blocks)
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case content
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role.rawValue, forKey: .role)
        switch role {
        case .user:
            try encodeUserContent(into: &container)
        case .latestReminder:
            try container.encode(userText, forKey: .content)
        case .assistant:
            var list = container.nestedUnkeyedContainer(forKey: .content)
            for block in assistantWireBlocks() {
                try list.encode(block)
            }
        }
    }

    /// 有已上传的附件时用内容块数组：**先文件后文本**（与参考实现 `toUserParam` 一致）。
    /// 没有附件时保持字符串，老请求的形状不变；文本为空则不补空 text 块。
    private func encodeUserContent(into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        let files = userFileBlocks()
        guard !files.isEmpty else {
            try container.encode(userText, forKey: .content)
            return
        }
        var list = container.nestedUnkeyedContainer(forKey: .content)
        for file in files {
            try list.encode(file)
        }
        let text = userText
        if !text.isEmpty {
            try list.encode(WireTextBlock(text: text))
        }
    }

    /// 请求里是否带文件块。客户端据此决定是否附带 `anthropic-beta: files-api-2025-04-14`。
    public var hasFiles: Bool {
        blocks.contains { block in
            block.kind == .file && (block.attachment?.hasServerFileID ?? false)
        }
    }

    /// 可上行的文件块：只取已拿到 file_id 的附件；未上传成功的跳过。
    private func userFileBlocks() -> [WireFileBlock] {
        blocks.compactMap { block in
            guard block.kind == .file,
                  let attachment = block.attachment,
                  let fileID = attachment.fileID,
                  !fileID.isEmpty
            else { return nil }
            return WireFileBlock(
                blockType: attachment.isImage ? "image" : "document",
                fileID: fileID
            )
        }
    }

    /// 用户消息的纯文本：多个 text 块按换行拼接（正常路径只有一块）。
    private var userText: String {
        blocks
            .filter { $0.kind == .text }
            .map(\.text)
            .joined(separator: "\n")
    }

    /// 历史 assistant 只回传：text、非空 thinking（含 signature）、kind == read_link 的
    /// server_tool_use 及配对的 web_fetch_tool_result；**不回传** web_search_tool_result。
    private func assistantWireBlocks() -> [AssistantWireBlock] {
        // 结果块靠 tool_use_id 与调用块配对；只有 read_link 这一路历史需要回传。
        var toolsByID: [String: Block] = [:]
        var fetchBlocks: [String: Block] = [:]
        for block in blocks {
            if block.kind == .toolUse, let tool = block.toolUse, toolsByID[tool.id] == nil {
                toolsByID[tool.id] = block
            }
            if block.kind == .fetchResult, fetchBlocks[block.id] == nil {
                fetchBlocks[block.id] = block
            }
        }

        var output: [AssistantWireBlock] = []
        /// 当前正在拼接的文本块在 output 里的下标；遇到任何非文本块（含不回传的块）就结束。
        var textIndex: Int?

        for block in blocks {
            switch block.kind {
            case .text:
                if let index = textIndex, case let .text(existing) = output[index] {
                    output[index] = .text(existing + block.text)
                } else {
                    var prefix = ""
                    if let last = output.last, case .text = last { prefix = "\n\n" }
                    output.append(.text(prefix + block.text))
                    textIndex = output.count - 1
                }

            case .thinking:
                // 空思考不回传，也不把前后正文隔断（避免服务端多插空行）。
                if block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                textIndex = nil
                output.append(.thinking(text: block.text, signature: block.signature ?? ""))

            case .toolUse:
                textIndex = nil
                guard let tool = block.toolUse, tool.kind == .readLink else { continue }
                // 没有可解密的结果块（或结果块未签名）时，调用与结果都不回传。
                guard let fetch = fetchBlocks[tool.id] else { continue }
                guard fetch.failed || !(fetch.signature ?? "").isEmpty else { continue }
                output.append(.serverToolUse(tool))

            case .fetchResult:
                textIndex = nil
                // deep_search 抓取的页面不进入历史；只有配对的 read_link 才回传。
                guard toolsByID[block.id]?.toolUse?.kind == .readLink else { continue }
                if block.failed {
                    output.append(.webFetch(toolUseID: block.id, result: nil, signature: nil))
                } else if let signature = block.signature, !signature.isEmpty,
                          let result = block.fetchResult {
                    output.append(.webFetch(toolUseID: block.id, result: result, signature: signature))
                }

            case .searchResults:
                // 历史搜索结果不回传。
                textIndex = nil
            }
        }

        return output.filter { block in
            if case let .text(text) = block { return !text.isEmpty }
            return true
        }
    }
}

// MARK: - 请求

public struct ChatRequest: Sendable, Encodable {
    public var model: String
    public var system: String
    public var messages: [RequestMessage]
    /// → thinking.type enabled / disabled
    public var thinking: Bool
    /// → 声明 deepseek_web_search
    public var search: Bool
    /// → 声明 deepseek_read_url
    public var readURL: Bool
    /// → title.enabled
    public var titleGeneration: Bool

    public init(
        model: String = "deepseek-flash",
        system: String,
        messages: [RequestMessage],
        thinking: Bool = false,
        search: Bool = false,
        readURL: Bool = false,
        titleGeneration: Bool = false
    ) {
        self.model = model
        self.system = system
        self.messages = messages
        self.thinking = thinking
        self.search = search
        self.readURL = readURL
        self.titleGeneration = titleGeneration
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case thinking
        case tools
        case safetyCheck = "safety_check"
        case title
        case stream
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(system, forKey: .system)
        try container.encode(messages, forKey: .messages)
        try container.encode(ThinkingFlag(type: thinking ? "enabled" : "disabled"), forKey: .thinking)
        try container.encode(tools, forKey: .tools)
        // 扩展模式：声明联网工具或阅读链接时固定带 high 安全审核。
        if search || readURL {
            try container.encode(SafetyCheck(level: "high"), forKey: .safetyCheck)
        }
        if titleGeneration {
            try container.encode(TitleFlag(enabled: true), forKey: .title)
        }
        // 参考实现把 stream 合并进请求体末尾。
        try container.encode(true, forKey: .stream)
    }

    /// 顺序与官方客户端一致：先 read_url，再 web_search。
    private var tools: [ToolFlag] {
        var result: [ToolFlag] = []
        if readURL { result.append(ToolFlag(type: "deepseek_read_url", name: "deepseek_read_url")) }
        if search {
            result.append(ToolFlag(type: "deepseek_web_search", name: "deepseek_web_search"))
        }
        return result
    }
}

// MARK: - 线格式

private struct ThinkingFlag: Encodable {
    let type: String
}

private struct SafetyCheck: Encodable {
    let level: String
}

private struct TitleFlag: Encodable {
    let enabled: Bool
}

private struct ToolFlag: Encodable {
    let type: String
    let name: String
}

/// 允许任意字符串键的容器。
private struct WireKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private enum AssistantWireBlock: Encodable {
    case text(String)
    case thinking(text: String, signature: String)
    case serverToolUse(ServerToolUse)
    case webFetch(toolUseID: String, result: WebFetchResult?, signature: String?)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKey.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: WireKey("type"))
            try container.encode(text, forKey: WireKey("text"))

        case let .thinking(text, signature):
            try container.encode("thinking", forKey: WireKey("type"))
            try container.encode(text, forKey: WireKey("thinking"))
            try container.encode(signature, forKey: WireKey("signature"))

        case let .serverToolUse(tool):
            try container.encode("server_tool_use", forKey: WireKey("type"))
            try container.encode(tool.id, forKey: WireKey("id"))
            try container.encode("deepseek_read_url", forKey: WireKey("name"))
            try container.encode(WireToolInput(tool), forKey: WireKey("input"))
            try container.encode(tool.kind, forKey: WireKey("kind"))

        case let .webFetch(toolUseID, result, signature):
            try container.encode("web_fetch_tool_result", forKey: WireKey("type"))
            try container.encode(toolUseID, forKey: WireKey("tool_use_id"))
            if let result {
                try container.encode(WireFetchResult(result), forKey: WireKey("content"))
            } else {
                try container.encode(WireFetchError(), forKey: WireKey("content"))
            }
            try container.encode("read_link", forKey: WireKey("kind"))
            if let signature, !signature.isEmpty {
                try container.encode(signature, forKey: WireKey("signature"))
            }
        }
    }
}

private struct WireToolInput: Encodable {
    let tool: ServerToolUse

    init(_ tool: ServerToolUse) {
        self.tool = tool
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKey.self)
        try container.encode(tool.action, forKey: WireKey("action"))
        switch tool.action {
        case "search":
            try container.encode(tool.queries, forKey: WireKey("queries"))
        case "open_page", "read_link":
            try container.encode(tool.url ?? "", forKey: WireKey("url"))
        case "find_in_page":
            try container.encode(tool.url ?? "", forKey: WireKey("url"))
            try container.encode(tool.pattern ?? "", forKey: WireKey("pattern"))
        default:
            break
        }
    }
}

private struct WireFetchResult: Encodable {
    let result: WebFetchResult

    init(_ result: WebFetchResult) {
        self.result = result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKey.self)
        try container.encode("web_fetch_result", forKey: WireKey("type"))
        try container.encode(result.url, forKey: WireKey("url"))
        try container.encode(WireFetchDocument(title: result.title), forKey: WireKey("content"))
        try container.encode(result.publishedAt, forKey: WireKey("published_at"))
    }
}

private struct WireFetchDocument: Encodable {
    let title: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKey.self)
        try container.encode("document", forKey: WireKey("type"))
        try container.encode(WireFetchSource(), forKey: WireKey("source"))
        try container.encode(title, forKey: WireKey("title"))
    }
}

private struct WireFetchSource: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKey.self)
        try container.encode("text", forKey: WireKey("type"))
        try container.encode("text/plain", forKey: WireKey("media_type"))
        // read_link / deep_search 均为空串：页面正文在结果块 signature 里。
        try container.encode("", forKey: WireKey("data"))
    }
}

private struct WireFetchError: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKey.self)
        try container.encode("web_fetch_tool_result_error", forKey: WireKey("type"))
        try container.encode("unavailable", forKey: WireKey("error_code"))
    }
}
