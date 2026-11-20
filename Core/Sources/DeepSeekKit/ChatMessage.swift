import Foundation

public enum MessageStatus: String, Codable, Sendable {
    case streaming
    case complete
    case stopped
    case failed
}

/// 一条会话消息。UI 以 `blocks` 为唯一渲染来源，`plainText` 等只用于复制与统计。
public struct ChatMessage: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var role: ChatRole
    public var blocks: [Block]
    public var createdAt: Date
    public var status: MessageStatus
    public var model: String?
    public var stopReason: String?
    public var errorText: String?

    public init(
        id: String,
        role: ChatRole,
        blocks: [Block] = [],
        createdAt: Date = .now,
        status: MessageStatus = .streaming,
        model: String? = nil,
        stopReason: String? = nil,
        errorText: String? = nil
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.createdAt = createdAt
        self.status = status
        self.model = model
        self.stopReason = stopReason
        self.errorText = errorText
    }

    /// 所有 `.text` 块按序拼接（不含引用）。
    public var plainText: String {
        blocks.reduce(into: "") { text, block in
            if block.kind == .text { text += block.text }
        }
    }

    /// 所有 `.thinking` 块按序拼接。
    public var thinkingText: String {
        blocks.reduce(into: "") { text, block in
            if block.kind == .thinking { text += block.text }
        }
    }

    /// 所有 searchResults 按 url 去重（保留首次出现顺序）。
    public var sources: [WebSearchResult] {
        var seen = Set<String>()
        var result: [WebSearchResult] = []
        for block in blocks where block.kind == .searchResults {
            for item in block.searchResults where seen.insert(item.url).inserted {
                result.append(item)
            }
        }
        return result
    }
}
