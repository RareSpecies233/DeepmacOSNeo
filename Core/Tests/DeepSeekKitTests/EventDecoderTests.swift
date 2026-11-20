import Foundation
import XCTest
@testable import DeepSeekKit

/// 事件解码：契约 §8.2（覆盖 StreamEvent 的全部 case）。
final class EventDecoderTests: XCTestCase {

    private func decode(_ json: String, event: String = "message") throws -> StreamEvent? {
        try EventDecoder.decode(eventName: event, data: json)
    }

    // MARK: message_start

    func testMessageStart() throws {
        let event = try requireEvent(try decode(Samples.messageStart, event: "message_start"))
        guard case let .messageStart(id, model) = event else {
            return XCTFail("应为 messageStart")
        }
        XCTAssertEqual(id, Samples.messageID)
        XCTAssertEqual(model, Samples.model)
    }

    // MARK: content_block_start

    func testTextBlockStart() throws {
        let event = try requireEvent(try decode(Samples.textBlockStart, event: "content_block_start"))
        guard case let .blockStart(index, block) = event else { return XCTFail() }
        XCTAssertEqual(index, 3)
        XCTAssertEqual(block.id, "b3")
        XCTAssertEqual(block.kind, .text)
        XCTAssertEqual(block.text, "")
    }

    func testTextBlockStartKeepsValidCitations() throws {
        let json = """
        {"type":"content_block_start","index":4,"content_block":{"type":"text","text":"已有内容","citations":[\(Samples.citation),{"type":"unknown","url":"https://ignored"}]}}
        """
        let event = try requireEvent(try decode(json))
        guard case let .blockStart(_, block) = event else { return XCTFail() }
        XCTAssertEqual(block.citations.count, 1)
        XCTAssertEqual(block.citations.first?.url, "https://example.com/a")
        XCTAssertEqual(block.citations.first?.citedText, "截至引用处的正文")
    }

    func testThinkingBlockStart() throws {
        let event = try requireEvent(try decode(Samples.thinkingBlockStart))
        guard case let .blockStart(index, block) = event else { return XCTFail() }
        XCTAssertEqual(index, 0)
        XCTAssertEqual(block.id, "b0")
        XCTAssertEqual(block.kind, .thinking)
        XCTAssertEqual(block.signature, "")
    }

    func testSearchToolUseBlockStart() throws {
        let event = try requireEvent(try decode(Samples.searchToolBlockStart))
        guard case let .blockStart(index, block) = event else { return XCTFail() }
        XCTAssertEqual(index, 1)
        XCTAssertEqual(block.id, Samples.searchToolID)
        XCTAssertEqual(block.kind, .toolUse)
        let tool = try XCTUnwrap(block.toolUse)
        XCTAssertEqual(tool.id, Samples.searchToolID)
        XCTAssertEqual(tool.kind, .search)
        XCTAssertEqual(tool.action, "search")
        XCTAssertEqual(tool.queries, ["DeepSeek Chat 联网搜索", "Liquid Glass macOS"])
        XCTAssertNil(tool.url)
    }

    func testReadLinkToolUseBlockStart() throws {
        let event = try requireEvent(try decode(Samples.readToolBlockStart))
        guard case let .blockStart(_, block) = event else { return XCTFail() }
        XCTAssertEqual(block.id, Samples.readToolID)
        let tool = try XCTUnwrap(block.toolUse)
        XCTAssertEqual(tool.kind, .readLink)
        XCTAssertEqual(tool.action, "read_link")
        XCTAssertEqual(tool.url, "https://example.com/page")
        XCTAssertTrue(tool.queries.isEmpty)
    }

    func testSearchResultBlockStart() throws {
        let event = try requireEvent(
            try decode(Samples.searchResultBlockStart, event: "content_block_start")
        )
        guard case let .blockStart(index, block) = event else { return XCTFail() }
        XCTAssertEqual(index, 2)
        XCTAssertEqual(block.kind, .searchResults)
        XCTAssertEqual(block.id, Samples.searchToolID)
        XCTAssertFalse(block.failed)
        XCTAssertEqual(block.searchResults.count, 2)

        let first = try XCTUnwrap(block.searchResults.first)
        XCTAssertEqual(first.url, "https://example.com/a")
        XCTAssertEqual(first.title, "示例站点")
        XCTAssertEqual(first.snippet, "第一段摘要")
        XCTAssertEqual(first.siteName, "Example")
        XCTAssertEqual(first.siteIcon, "https://example.com/icon.png")
        XCTAssertEqual(first.pageAge, "2026-01-02T03:04:05Z")

        let second = block.searchResults[1]
        XCTAssertNil(second.snippet)
        XCTAssertNil(second.siteName)
        XCTAssertNil(second.siteIcon)
        XCTAssertNil(second.pageAge)
    }

    func testSearchResultErrorBlock() throws {
        let event = try requireEvent(try decode(Samples.searchResultErrorBlockStart))
        guard case let .blockStart(_, block) = event else { return XCTFail() }
        XCTAssertTrue(block.failed)
        XCTAssertTrue(block.searchResults.isEmpty)
    }

    func testFetchResultBlockStart() throws {
        let event = try requireEvent(try decode(Samples.fetchResultBlockStart))
        guard case let .blockStart(_, block) = event else { return XCTFail() }
        XCTAssertEqual(block.id, Samples.readToolID)
        XCTAssertEqual(block.kind, .fetchResult)
        XCTAssertFalse(block.failed)
        // read_link 的页面密文挂在结果块的 signature 上，历史回传需要原样带回。
        XCTAssertEqual(block.signature, "page-signature")
        let result = try XCTUnwrap(block.fetchResult)
        XCTAssertEqual(result.url, "https://example.com/page")
        XCTAssertEqual(result.title, "页面标题")
        XCTAssertEqual(result.publishedAt, "2025-06-01")
    }

    func testFetchResultErrorBlock() throws {
        let event = try requireEvent(try decode(Samples.fetchResultErrorBlockStart))
        guard case let .blockStart(_, block) = event else { return XCTFail() }
        XCTAssertTrue(block.failed)
        XCTAssertNil(block.fetchResult)
    }

    func testUnknownBlockIsSkipped() throws {
        let json = """
        {"type":"content_block_start","index":0,"content_block":{"type":"future_block","payload":{"x":1}}}
        """
        XCTAssertNil(try decode(json))
    }

    func testToolUseBlockIsSkipped() throws {
        let json = """
        {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"x","input":{}}}
        """
        XCTAssertNil(try decode(json))
    }

    func testBlockWithMissingRequiredFieldIsSkipped() throws {
        let json = """
        {"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}
        """
        XCTAssertNil(try decode(json))
    }

    func testNegativeIndexIsSkipped() throws {
        let json = """
        {"type":"content_block_start","index":-1,"content_block":{"type":"text","text":""}}
        """
        XCTAssertNil(try decode(json))
    }

    func testBooleanIndexIsSkipped() throws {
        let json = """
        {"type":"content_block_start","index":true,"content_block":{"type":"text","text":""}}
        """
        XCTAssertNil(try decode(json))
    }

    // MARK: content_block_delta

    func testTextDelta() throws {
        let event = try requireEvent(try decode(Samples.textDelta, event: "content_block_delta"))
        guard case let .textDelta(index, text) = event else { return XCTFail() }
        XCTAssertEqual(index, 3)
        XCTAssertEqual(text, "你好")
    }

    func testThinkingDelta() throws {
        let event = try requireEvent(try decode(Samples.thinkingDelta))
        guard case let .thinkingDelta(index, text) = event else { return XCTFail() }
        XCTAssertEqual(index, 0)
        XCTAssertEqual(text, "先想一下")
    }

    func testSignatureDelta() throws {
        let event = try requireEvent(try decode(Samples.signatureDelta))
        guard case let .signatureDelta(index, signature) = event else { return XCTFail() }
        XCTAssertEqual(index, 0)
        XCTAssertEqual(signature, Samples.signature)
    }

    func testCitationDelta() throws {
        let event = try requireEvent(try decode(Samples.citationDelta))
        guard case let .citationDelta(index, citation) = event else { return XCTFail() }
        XCTAssertEqual(index, 3)
        XCTAssertEqual(citation.url, "https://example.com/a")
        XCTAssertEqual(citation.title, "示例站点")
        XCTAssertEqual(citation.citedText, "截至引用处的正文")
    }

    func testInputJSONDeltaIsIgnored() throws {
        let json = """
        {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{}"}}
        """
        XCTAssertNil(try decode(json))
    }

    // MARK: 生命周期

    func testBlockStop() throws {
        let event = try requireEvent(try decode(Samples.blockStop))
        guard case let .blockStop(index) = event else { return XCTFail() }
        XCTAssertEqual(index, 3)
    }

    func testMessageDeltaCarriesStopReasonAndTitle() throws {
        let event = try requireEvent(try decode(Samples.messageDelta, event: "message_delta"))
        guard case let .messageDelta(stopReason, title) = event else { return XCTFail() }
        XCTAssertEqual(stopReason, "end_turn")
        XCTAssertEqual(title, "联网搜索演示")
    }

    func testMessageDeltaToleratesMissingTitle() throws {
        let json = """
        {"type":"message_delta","delta":{"stop_reason":"max_tokens","stop_sequence":null}}
        """
        let event = try requireEvent(try decode(json))
        guard case let .messageDelta(stopReason, title) = event else { return XCTFail() }
        XCTAssertEqual(stopReason, "max_tokens")
        XCTAssertNil(title)
    }

    func testMessageStop() throws {
        let event = try requireEvent(try decode(Samples.messageStop))
        guard case .messageStop = event else { return XCTFail() }
    }

    func testPing() throws {
        let event = try requireEvent(try decode(Samples.ping, event: "ping"))
        guard case .ping = event else { return XCTFail() }
    }

    // MARK: 容错与错误帧

    func testUnknownEventTypeIsSkipped() throws {
        let json = """
        {"type":"future_event","data":{"x":1}}
        """
        XCTAssertNil(try decode(json))
    }

    func testJSONTypeWinsOverEventName() throws {
        let event = try requireEvent(try decode(Samples.messageStop, event: "ping"))
        guard case .messageStop = event else { return XCTFail() }
    }

    func testStreamErrorFrameThrows() {
        XCTAssertThrowsError(
            try EventDecoder.decode(
                eventName: "message",
                data: "{\"error\":{\"message\":\"等待生成超时\"}}"
            )
        ) { error in
            guard case let DeepSeekError.stream(message) = error else {
                return XCTFail("应为 stream 错误")
            }
            XCTAssertEqual(message, "等待生成超时")
        }
    }

    func testBareErrorEventWithNonJSONDataThrows() {
        XCTAssertThrowsError(
            try EventDecoder.decode(eventName: "error", data: "gateway timeout")
        ) { error in
            guard case let DeepSeekError.stream(message) = error else {
                return XCTFail("应为 stream 错误")
            }
            XCTAssertEqual(message, "gateway timeout")
        }
    }

    func testGarbageDataIsSkipped() throws {
        XCTAssertNil(try EventDecoder.decode(eventName: "message", data: "not json"))
    }

    func testEmptyDataIsSkipped() throws {
        XCTAssertNil(try EventDecoder.decode(eventName: "message", data: ""))
    }

    func testErrorDescriptionIsChinese() {
        let error = DeepSeekError.http(status: 401, message: "Invalid API key")
        XCTAssertTrue(error.errorDescription?.contains("401") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("Invalid API key") ?? false)
        XCTAssertTrue(DeepSeekError.interrupted.errorDescription?.isEmpty == false)
        XCTAssertTrue(DeepSeekError.network("").errorDescription?.isEmpty == false)
        XCTAssertTrue(DeepSeekError.stream("").errorDescription?.isEmpty == false)
        XCTAssertTrue(DeepSeekError.protocolViolation("").errorDescription?.isEmpty == false)
    }
}
