import Foundation
import XCTest
@testable import DeepSeekKit

/// 请求编码：契约 §8.4（用 JSONSerialization 逐字段断言）。
final class RequestEncodingTests: XCTestCase {

    private func assistantContent(_ blocks: [Block]) throws -> [Any] {
        let json = try encodeObject(RequestMessage(role: .assistant, blocks: blocks))
        return try XCTUnwrap(json["content"] as? [Any])
    }

    private func object(_ value: Any) throws -> [String: Any] {
        try XCTUnwrap(value as? [String: Any])
    }

    // MARK: 顶层形状

    func testMinimalRequestShape() throws {
        let request = ChatRequest(system: "系统提示", messages: [])
        let json = try encodeObject(request)

        XCTAssertEqual(json["model"] as? String, "deepseek-flash")
        XCTAssertEqual(json["system"] as? String, "系统提示")
        XCTAssertEqual(json["stream"] as? Bool, true)

        let thinking = try object(try XCTUnwrap(json["thinking"]))
        XCTAssertEqual(thinking["type"] as? String, "disabled")
        XCTAssertEqual(thinking.count, 1)

        let tools = try XCTUnwrap(json["tools"] as? [Any])
        XCTAssertTrue(tools.isEmpty)
        XCTAssertNil(json["safety_check"])
        XCTAssertNil(json["title"])
    }

    func testFullRequestShape() throws {
        let request = ChatRequest(
            model: "deepseek-v4-pro",
            system: "系统提示",
            messages: [RequestMessage(role: .user, text: "你好")],
            thinking: true,
            search: true,
            readURL: true,
            titleGeneration: true
        )
        let json = try encodeObject(request)

        XCTAssertEqual(json["model"] as? String, "deepseek-v4-pro")
        let thinking = try object(try XCTUnwrap(json["thinking"]))
        XCTAssertEqual(thinking["type"] as? String, "enabled")

        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0]["type"] as? String, "deepseek_read_url")
        XCTAssertEqual(tools[0]["name"] as? String, "deepseek_read_url")
        XCTAssertEqual(tools[1]["type"] as? String, "deepseek_web_search")
        XCTAssertEqual(tools[1]["name"] as? String, "deepseek_web_search")

        let safety = try object(try XCTUnwrap(json["safety_check"]))
        XCTAssertEqual(safety["level"] as? String, "high")
        XCTAssertEqual(safety.count, 1)

        let title = try object(try XCTUnwrap(json["title"]))
        XCTAssertEqual(title["enabled"] as? Bool, true)
        XCTAssertEqual(title.count, 1)

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "你好")
    }

    func testSearchOnlyDeclaresWebSearchAndSafetyCheck() throws {
        let request = ChatRequest(system: "s", messages: [], search: true)
        let json = try encodeObject(request)
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["type"] as? String, "deepseek_web_search")
        XCTAssertNotNil(json["safety_check"])
        XCTAssertNil(json["title"])
    }

    func testReadOnlyDeclaresReadURLAndSafetyCheck() throws {
        let request = ChatRequest(system: "s", messages: [], readURL: true)
        let json = try encodeObject(request)
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["type"] as? String, "deepseek_read_url")
        XCTAssertNotNil(json["safety_check"])
    }

    // MARK: 消息角色

    func testUserMessageContentIsString() throws {
        let json = try encodeObject(RequestMessage(role: .user, text: "你好"))
        XCTAssertEqual(json["role"] as? String, "user")
        XCTAssertEqual(json["content"] as? String, "你好")
    }

    func testLatestReminderRoleRawValue() throws {
        let json = try encodeObject(RequestMessage(role: .latestReminder, text: "现在是 2026 年"))
        XCTAssertEqual(json["role"] as? String, "latest_reminder")
        XCTAssertEqual(json["content"] as? String, "现在是 2026 年")
    }

    func testConvenienceInitFromChatMessage() {
        let message = ChatMessage(id: "x", role: .user, blocks: [Block(id: "b0", kind: .text, text: "hi")])
        XCTAssertEqual(RequestMessage(message).role, .user)
        XCTAssertEqual(RequestMessage(message).blocks.count, 1)
    }

    // MARK: assistant 历史

    func testAssistantHistoryFiltersMergesAndPairs() throws {
        let tool = ServerToolUse(
            id: Samples.readToolID,
            kind: .readLink,
            url: "https://example.com/page",
            action: "read_link"
        )
        let blocks: [Block] = [
            Block(id: "b0", kind: .text, text: "回答前半"),
            // 空思考：不回传，也不隔断前后正文。
            Block(id: "b1", kind: .thinking, text: "   ", signature: "empty"),
            Block(id: "b2", kind: .text, text: "，回答后半"),
            Block(id: "b3", kind: .thinking, text: "想法", signature: "sig-think"),
            Block(id: "b4", kind: .text, text: "引用之后"),
            // 搜索调用与搜索结果都不回传。
            Block(
                id: Samples.searchToolID,
                kind: .toolUse,
                toolUse: ServerToolUse(id: Samples.searchToolID, kind: .search, queries: ["q"], action: "search")
            ),
            Block(
                id: Samples.searchToolID,
                kind: .searchResults,
                searchResults: [WebSearchResult(url: "https://example.com/a", title: "示例站点")]
            ),
            Block(id: Samples.readToolID, kind: .toolUse, toolUse: tool),
            Block(
                id: Samples.readToolID,
                kind: .fetchResult,
                signature: "page-signature",
                fetchResult: WebFetchResult(
                    url: "https://example.com/page",
                    title: "页面标题",
                    publishedAt: "2025-06-01"
                )
            ),
        ]

        let content = try assistantContent(blocks)
        XCTAssertEqual(content.count, 5)

        let first = try object(content[0])
        XCTAssertEqual(first["type"] as? String, "text")
        XCTAssertEqual(first["text"] as? String, "回答前半，回答后半")
        XCTAssertEqual(Set(first.keys), ["type", "text"])

        let second = try object(content[1])
        XCTAssertEqual(second["type"] as? String, "thinking")
        XCTAssertEqual(second["thinking"] as? String, "想法")
        XCTAssertEqual(second["signature"] as? String, "sig-think")

        let third = try object(content[2])
        XCTAssertEqual(third["type"] as? String, "text")
        XCTAssertEqual(third["text"] as? String, "引用之后")

        let toolBlock = try object(content[3])
        XCTAssertEqual(toolBlock["type"] as? String, "server_tool_use")
        XCTAssertEqual(toolBlock["id"] as? String, Samples.readToolID)
        XCTAssertEqual(toolBlock["name"] as? String, "deepseek_read_url")
        XCTAssertEqual(toolBlock["kind"] as? String, "read_link")
        let input = try object(try XCTUnwrap(toolBlock["input"]))
        XCTAssertEqual(input["action"] as? String, "read_link")
        XCTAssertEqual(input["url"] as? String, "https://example.com/page")

        let fetchBlock = try object(content[4])
        XCTAssertEqual(fetchBlock["type"] as? String, "web_fetch_tool_result")
        XCTAssertEqual(fetchBlock["tool_use_id"] as? String, Samples.readToolID)
        XCTAssertEqual(fetchBlock["kind"] as? String, "read_link")
        XCTAssertEqual(fetchBlock["signature"] as? String, "page-signature")

        let fetchContent = try object(try XCTUnwrap(fetchBlock["content"]))
        XCTAssertEqual(fetchContent["type"] as? String, "web_fetch_result")
        XCTAssertEqual(fetchContent["url"] as? String, "https://example.com/page")
        XCTAssertEqual(fetchContent["published_at"] as? String, "2025-06-01")

        let page = try object(try XCTUnwrap(fetchContent["content"]))
        XCTAssertEqual(page["type"] as? String, "document")
        XCTAssertEqual(page["title"] as? String, "页面标题")
        let source = try object(try XCTUnwrap(page["source"]))
        XCTAssertEqual(source["type"] as? String, "text")
        XCTAssertEqual(source["media_type"] as? String, "text/plain")
        XCTAssertEqual(source["data"] as? String, "")

        let raw = try XCTUnwrap(
            String(
                data: try JSONEncoder().encode(RequestMessage(role: .assistant, blocks: blocks)),
                encoding: .utf8
            )
        )
        XCTAssertFalse(raw.contains("web_search_tool_result"))
        XCTAssertFalse(raw.contains(Samples.searchToolID))
    }

    func testUnsignedReadLinkIsNotResent() throws {
        let tool = Block(
            id: "srvtoolu_rl_1_x",
            kind: .toolUse,
            toolUse: ServerToolUse(
                id: "srvtoolu_rl_1_x",
                kind: .readLink,
                url: "https://example.com/e",
                action: "read_link"
            )
        )
        let fetch = Block(
            id: "srvtoolu_rl_1_x",
            kind: .fetchResult,
            signature: nil,
            fetchResult: WebFetchResult(url: "https://example.com/e", title: "T")
        )
        XCTAssertTrue(try assistantContent([tool, fetch]).isEmpty)
    }

    func testFailedFetchIsResentAsError() throws {
        let tool = Block(
            id: "srvtoolu_rl_1_y",
            kind: .toolUse,
            toolUse: ServerToolUse(
                id: "srvtoolu_rl_1_y",
                kind: .readLink,
                url: "https://example.com/gone",
                action: "read_link"
            )
        )
        let fetch = Block(id: "srvtoolu_rl_1_y", kind: .fetchResult, failed: true)
        let content = try assistantContent([tool, fetch])
        XCTAssertEqual(content.count, 2)

        let fetchBlock = try object(content[1])
        let fetchContent = try object(try XCTUnwrap(fetchBlock["content"]))
        XCTAssertEqual(fetchContent["type"] as? String, "web_fetch_tool_result_error")
        XCTAssertEqual(fetchContent["error_code"] as? String, "unavailable")
        XCTAssertNil(fetchBlock["signature"])
    }

    func testSearchResultsAloneAreNotSent() throws {
        let results = Block(
            id: Samples.searchToolID,
            kind: .searchResults,
            searchResults: [WebSearchResult(url: "https://example.com/a", title: "A")]
        )
        XCTAssertTrue(try assistantContent([results]).isEmpty)
    }

    func testDeepSearchFetchIsNotResent() throws {
        let id = "srvtoolu_ds_1_abc"
        let tool = Block(
            id: id,
            kind: .toolUse,
            toolUse: ServerToolUse(
                id: id,
                kind: .deepSearch,
                url: "https://example.com/ds",
                action: "open_page"
            )
        )
        let fetch = Block(
            id: id,
            kind: .fetchResult,
            signature: "sig-ds",
            fetchResult: WebFetchResult(url: "https://example.com/ds", title: "深度搜索页")
        )
        XCTAssertTrue(try assistantContent([tool, fetch]).isEmpty)
    }

    func testOrphanFetchResultIsNotResent() throws {
        let fetch = Block(
            id: "srvtoolu_rl_1_orphan",
            kind: .fetchResult,
            signature: "sig",
            fetchResult: WebFetchResult(url: "https://example.com/o", title: "孤立页面")
        )
        XCTAssertTrue(try assistantContent([fetch]).isEmpty)
    }

    func testFetchResultEncodesExplicitNullsForMissingMetadata() throws {
        let id = "srvtoolu_rl_1_nulls"
        let tool = Block(
            id: id,
            kind: .toolUse,
            toolUse: ServerToolUse(
                id: id,
                kind: .readLink,
                url: "https://example.com/nulls",
                action: "read_link"
            )
        )
        let fetch = Block(
            id: id,
            kind: .fetchResult,
            signature: "sig",
            fetchResult: WebFetchResult(url: "https://example.com/nulls")
        )
        let content = try assistantContent([tool, fetch])
        let fetchContent = try object(try XCTUnwrap(try object(content[1])["content"]))
        XCTAssertTrue(fetchContent.keys.contains("published_at"))
        XCTAssertTrue(fetchContent["published_at"] is NSNull)
        let page = try object(try XCTUnwrap(fetchContent["content"]))
        XCTAssertTrue(page.keys.contains("title"))
        XCTAssertTrue(page["title"] is NSNull)
    }

    func testSkippedBlockStartsNewTextBlockWithBlankLinePrefix() throws {
        // 参考实现：被省略的非文本块会结束当前文本块，下一段正文另起一块并以空行开头，
        // 服务端据此保留原本被思考/工具隔开的段落间距。
        let content = try assistantContent([
            Block(id: "b0", kind: .text, text: "A"),
            Block(id: "x", kind: .searchResults),
            Block(id: "b1", kind: .text, text: "B"),
        ])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(try object(content[0])["text"] as? String, "A")
        XCTAssertEqual(try object(content[1])["text"] as? String, "\n\nB")
    }

    func testCitationsAreNotResent() throws {
        let content = try assistantContent([
            Block(
                id: "b0",
                kind: .text,
                text: "有引用",
                citations: [Citation(url: "https://example.com/a", title: "A", citedText: "有引用")]
            )
        ])
        let first = try object(content[0])
        XCTAssertEqual(Set(first.keys), ["type", "text"])
    }

    func testEmptyThinkingAndEmptyTextAreDropped() throws {
        XCTAssertTrue(
            try assistantContent([
                Block(id: "b0", kind: .thinking, text: " ", signature: "s")
            ]).isEmpty
        )
        XCTAssertTrue(
            try assistantContent([Block(id: "b0", kind: .text, text: "")]).isEmpty
        )
    }

    func testThinkingWithoutSignatureEncodesEmptyString() throws {
        let content = try assistantContent([
            Block(id: "b0", kind: .thinking, text: "想法", signature: nil)
        ])
        let first = try object(content[0])
        XCTAssertEqual(first["signature"] as? String, "")
    }
}
