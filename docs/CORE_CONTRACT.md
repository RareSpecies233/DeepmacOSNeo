# Core 接口契约（DeepSeekKit）

> 本文件是 **UI 层与 Core 层之间的唯一约定**。实现方（kit）按此签名交付，消费方（App）按此签名编码。
> 任何签名变更必须先改本文件，由 lead 评审。

## 0. 模块边界

- 位置：`Core/`（SPM 包，同时被 xcodeproj 直接编入 App target，因此 App 内 **不 import**，直接用类型）
- 依赖：仅 Foundation。**禁止** SwiftUI / SwiftData / UIKit / AppKit —— Core 必须能在 `swift test` 下无 UI 运行。
- 并发：类型尽量 `Sendable`；网络与解析不碰主线程；不带 `@MainActor`。

## 1. 领域类型

```swift
public enum ChatRole: String, Codable, Sendable { case user, assistant }

public struct Citation: Codable, Sendable, Hashable, Identifiable {
    public var id: String { url }
    public let url: String
    public let title: String?
    public let citedText: String
}

public enum ToolKind: String, Codable, Sendable {
    case search, deepSearch = "deep_search", readLink = "read_link",
         imageSearch = "image_search", deepImageSearch = "deep_image_search"
}

public struct ServerToolUse: Codable, Sendable, Hashable {
    public let id: String
    public let kind: ToolKind
    public let queries: [String]      // action == search
    public let url: String?           // action == open_page / read_link / find_in_page
    public let pattern: String?       // action == find_in_page
    public let action: String         // "search" | "open_page" | "find_in_page" | "read_link"
}

public struct WebSearchResult: Codable, Sendable, Hashable, Identifiable {
    public var id: String { url }
    public let url: String
    public let title: String
    public let snippet: String?
    public let siteName: String?
    public let siteIcon: String?      // 远程 URL，UI 侧做磁盘缓存
    public let pageAge: String?       // RFC3339
}

public struct WebFetchResult: Codable, Sendable, Hashable {
    public let url: String
    public let title: String?
    public let publishedAt: String?
}
```

## 2. 内容块（UI 直接消费的唯一渲染单元）

用**扁平 struct + kind** 而非 enum with associated values：SwiftUI 的 diff 与 ForEach 更好写，Codable 更稳。

```swift
public struct Block: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case text, thinking, toolUse, searchResults, fetchResult
    }
    public var id: String            // 稳定：text/thinking 用 "b{index}"，工具用服务端 tool_use id
    public var kind: Kind
    public var text: String          // text / thinking 内容（增量已合并）
    public var citations: [Citation] // kind == .text
    public var signature: String?    // kind == .thinking
    public var toolUse: ServerToolUse?
    public var searchResults: [WebSearchResult]
    public var fetchResult: WebFetchResult?
    public var failed: Bool          // 工具失败（web_search_tool_result_error 等）

    public init(id: String, kind: Kind, text: String = "", citations: [Citation] = [], …)
}

public enum MessageStatus: String, Codable, Sendable { case streaming, complete, stopped, failed }

public struct ChatMessage: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var role: ChatRole
    public var blocks: [Block]
    public var createdAt: Date
    public var status: MessageStatus
    public var model: String?
    public var stopReason: String?
    public var errorText: String?

    public var plainText: String     // 所有 .text 块按序拼接
    public var thinkingText: String  // 所有 .thinking 块按序拼接
    public var sources: [WebSearchResult]  // 所有 searchResults 去重（按 url）
}
```

## 3. 请求

```swift
public struct ChatRequest: Sendable, Encodable {
    public var model: String                  // "deepseek-flash" | "deepseek-v4-pro"
    public var system: String
    public var messages: [RequestMessage]
    public var thinking: Bool                 // → thinking.type enabled/disabled
    public var search: Bool                   // → 声明 deepseek_web_search
    public var readURL: Bool                  // → 声明 deepseek_read_url
    public var titleGeneration: Bool          // → title.enabled
    public init(…)
}

public struct RequestMessage: Sendable, Encodable {
    public enum Role: String, Encodable, Sendable { case user, assistant, latestReminder = "latest_reminder" }
    public var role: Role
    public var blocks: [Block]      // 编码时：text/thinking/toolUse/searchResults/fetchResult
                                    // 按协议还原为 Anthropic content blocks
}
```

编码规则（必须严格，否则 400）：
- `thinking` → `{"type": "enabled"|"disabled"}`
- `tools` → `[]`，或含 `{"type":"deepseek_web_search","name":"deepseek_web_search"}` / `read_link` 同名
- `safety_check` → `{"level":"high"}`（仅当 search || readURL）
- `title` → `{"enabled": true}`
- 历史里的 assistant 消息只回传：`text`、`thinking`（含 signature）、`server_tool_use`（仅 read_link）、`web_fetch_tool_result`（成功时含 signature）；**不回传** `web_search_tool_result`
- 空 thinking 块不回传

## 4. 客户端

```swift
public struct DeepSeekClient: Sendable {
    public init(apiOrigin: URL, apiKey: String)
    /// GET {origin}/models，200 即有效。抛出 DeepSeekError。
    public func verifyKey() async throws
    /// POST {origin}/anthropic/v1/messages, stream=true
    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error>
}
```

`apiOrigin` 默认 `https://api.deepseek.com`，可指向本地 mock（`http://127.0.0.1:8787`）。

## 5. 事件

```swift
public enum StreamEvent: Sendable {
    case messageStart(id: String, model: String)
    case blockStart(index: Int, block: Block)
    case textDelta(index: Int, _ text: String)
    case thinkingDelta(index: Int, _ text: String)
    case signatureDelta(index: Int, _ signature: String)
    case citationDelta(index: Int, _ citation: Citation)
    case blockStop(index: Int)
    case messageDelta(stopReason: String?, title: String?)
    case messageStop
    case ping
}
```

解析要点：
- SSE `event:` 名与 JSON `type` 相同，以 JSON `type` 为准；`ping` 与注释行忽略但保留 case。
- 未知事件/未知 block 类型**不得抛错**，跳过（向前兼容）。
- `data` 中出现 `{"error":{...}}` → 抛 `DeepSeekError.stream(msg)`。
- 流在 `message_stop` 前结束 → `DeepSeekError.interrupted`。

## 6. 累加器（UI 的流式状态机）

```swift
public struct StreamAccumulator: Sendable {
    public private(set) var message: ChatMessage
    public private(set) var title: String?
    public init(id: String, model: String, createdAt: Date = .now)
    public mutating func apply(_ event: StreamEvent)   // 纯函数式增量合并
    public mutating func finish(status: MessageStatus, error: String? = nil)
}
```

合并规则：
- `blockStart` 追加到 `blocks`，index → block id 映射记录在内部。
- `textDelta/thinkingDelta/signatureDelta/citationDelta` 落到对应 index 的块。
- 同一 text 块内 citation 按 url 去重；citation 出现后继续追加 text 到**同一块**（参考实现会另起块，这里允许合并，UI 用 `citedText` 定位）。
- `messageDelta` 保存 stopReason 与 title。
- `finish` 设置 status / errorText。

## 7. 错误

```swift
public enum DeepSeekError: Error, LocalizedError, Sendable {
    case http(status: Int, message: String)
    case stream(String)
    case network(String)
    case interrupted
    case protocolViolation(String)
    public var errorDescription: String? { … 中文文案 … }
}
```

## 8. 测试要求（`swift test --package-path Core` 必须全绿）

必须覆盖：
1. SSE 切分：`\r\n` / 单 `\r` 被拆成两个 chunk、多行 `data`、注释行、结尾未空行。
2. 事件解码：7 种事件各一条真实样本（可从 `Reference/chat-demo/src/services/api/` 推导）。
3. 累加器：text 增量拼接、thinking + signature、citation 去重、工具块、stopReason。
4. 请求编码：thinking/tools/safety_check/title 的 JSON 形状逐字段断言（用 JSONSerialization 比较）。
5. 错误映射：非 2xx、流内 error、无 message_stop 结束。

## 9. Mock 服务器

`scripts/mock-server.py`：实现 `GET /models` 与 `POST /anthropic/v1/messages`，按真实事件序列输出一段"思考 + 联网搜索 + 正文"的 SSE，用于无 Key 联调与截屏。kit 需保证客户端能与之完整跑通（可写集成测试，默认 skip 联网）。
