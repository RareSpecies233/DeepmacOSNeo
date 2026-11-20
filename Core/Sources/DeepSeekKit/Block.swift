import Foundation

/// UI 直接消费的唯一渲染单元：扁平 struct + kind，方便 SwiftUI diff 与 ForEach。
public struct Block: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case text
        case thinking
        case toolUse
        case searchResults
        case fetchResult
    }

    /// 稳定标识：text / thinking 用 `b{index}`；工具块用服务端 tool_use id
    /// （调用块与它的结果块因此可能共用同一个 id，UI 侧建议按数组下标做身份）。
    public var id: String
    public var kind: Kind
    /// text / thinking 内容（增量已合并）。
    public var text: String
    /// kind == .text
    public var citations: [Citation]
    /// kind == .thinking 的签名；kind == .fetchResult 成功时服务端解密密文页面的 signature。
    public var signature: String?
    public var toolUse: ServerToolUse?
    public var searchResults: [WebSearchResult]
    public var fetchResult: WebFetchResult?
    /// 工具失败（web_search_tool_result_error / web_fetch_tool_result_error 等）。
    public var failed: Bool

    public init(
        id: String,
        kind: Kind,
        text: String = "",
        citations: [Citation] = [],
        signature: String? = nil,
        toolUse: ServerToolUse? = nil,
        searchResults: [WebSearchResult] = [],
        fetchResult: WebFetchResult? = nil,
        failed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.citations = citations
        self.signature = signature
        self.toolUse = toolUse
        self.searchResults = searchResults
        self.fetchResult = fetchResult
        self.failed = failed
    }
}
