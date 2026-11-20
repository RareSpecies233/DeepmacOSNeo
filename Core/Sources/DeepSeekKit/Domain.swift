import Foundation

// MARK: - 角色

/// 会话角色。Chat Engine 的 `latest_reminder` 是请求侧概念，放在 `RequestMessage.Role`。
public enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

// MARK: - 引用

/// 正文中的联网引用。服务端在正文里把引用标记还原成来源，挂在对应文本块上。
public struct Citation: Codable, Sendable, Hashable, Identifiable {
    public var id: String { url }

    public let url: String
    /// 查不到标题时为 nil。
    public let title: String?
    /// 当前文本块截至该引用处的全部正文（已去首尾空白）。
    public let citedText: String

    public init(url: String, title: String? = nil, citedText: String = "") {
        self.url = url
        self.title = title
        self.citedText = citedText
    }
}

// MARK: - 服务端工具

/// 服务端识别联网能力用的 kind。
public enum ToolKind: String, Codable, Sendable {
    case search
    case deepSearch = "deep_search"
    case readLink = "read_link"
    case imageSearch = "image_search"
    case deepImageSearch = "deep_image_search"
}

/// `server_tool_use` 块：原子下发，`content_block_start` 时 input 已完整。
public struct ServerToolUse: Codable, Sendable, Hashable {
    /// `srvtoolu_{s|ds|rl|is|dis}_{序号}_{32 位 hex}`
    public let id: String
    public let kind: ToolKind
    /// action == "search" 时的查询词。
    public let queries: [String]
    /// action == "open_page" / "read_link" / "find_in_page" 时的页面地址。
    public let url: String?
    /// action == "find_in_page" 时的查找串。
    public let pattern: String?
    /// "search" | "open_page" | "find_in_page" | "read_link"
    public let action: String

    public init(
        id: String,
        kind: ToolKind,
        queries: [String] = [],
        url: String? = nil,
        pattern: String? = nil,
        action: String
    ) {
        self.id = id
        self.kind = kind
        self.queries = queries
        self.url = url
        self.pattern = pattern
        self.action = action
    }
}

/// 一条联网搜索结果。
public struct WebSearchResult: Codable, Sendable, Hashable, Identifiable {
    public var id: String { url }

    public let url: String
    public let title: String
    public let snippet: String?
    /// 无站点名称时为 nil。
    public let siteName: String?
    /// 站点图标远程 URL，UI 侧做磁盘缓存。
    public let siteIcon: String?
    /// RFC 3339，没有发布时间时为 nil。
    public let pageAge: String?

    public init(
        url: String,
        title: String,
        snippet: String? = nil,
        siteName: String? = nil,
        siteIcon: String? = nil,
        pageAge: String? = nil
    ) {
        self.url = url
        self.title = title
        self.snippet = snippet
        self.siteName = siteName
        self.siteIcon = siteIcon
        self.pageAge = pageAge
    }
}

/// 阅读链接的结果摘要。页面正文加密在结果块的 signature 里，这里只保留可展示的元信息。
public struct WebFetchResult: Codable, Sendable, Hashable {
    public let url: String
    public let title: String?
    /// read_link 为页面解析出的原始日期串；deep_search 为 RFC 3339。
    public let publishedAt: String?

    public init(url: String, title: String? = nil, publishedAt: String? = nil) {
        self.url = url
        self.title = title
        self.publishedAt = publishedAt
    }
}
