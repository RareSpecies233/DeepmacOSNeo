import Foundation
import XCTest
@testable import DeepSeekKit

/// SSE 切分边界：契约 §8.1。
final class SSEDecoderTests: XCTestCase {

    func testCRLFSplitAcrossTwoChunks() {
        var decoder = SSEDecoder()
        // 第一段以 CR 结尾：CRLF 的前半，不能当作已完成的换行。
        XCTAssertTrue(decoder.push("event: message_start\r").isEmpty)
        let events = decoder.push("\ndata: {\"a\":1}\r\n\r\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "message_start")
        XCTAssertEqual(events.first?.data, "{\"a\":1}")
    }

    func testLoneCRIsLineBreak() {
        var decoder = SSEDecoder()
        let events = decoder.push("event: x\rdata: 1\r\r")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "x")
        XCTAssertEqual(events.first?.data, "1")
    }

    func testMultiLineDataJoinedWithNewline() {
        var decoder = SSEDecoder()
        let events = decoder.push("data: a\ndata: b\ndata: c\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "a\nb\nc")
    }

    func testCommentLinesIgnored() {
        var decoder = SSEDecoder()
        // 纯保活注释 + 空行：不产生事件。
        XCTAssertTrue(decoder.push(": keep-alive\n\n").isEmpty)
        // 注释夹在 data 之间不影响事件。
        let events = decoder.push("data: x\n: 中间注释\n\n")
        XCTAssertEqual(events.map(\.data), ["x"])
    }

    func testEventWithoutTrailingBlankLineIsDiscarded() {
        var decoder = SSEDecoder()
        XCTAssertTrue(decoder.push("data: {\"type\":\"message_stop\"}").isEmpty)
        XCTAssertTrue(decoder.finish().isEmpty)
    }

    func testEventWithSingleTrailingNewlineIsDiscarded() {
        var decoder = SSEDecoder()
        XCTAssertTrue(decoder.push("data: {\"type\":\"message_stop\"}\n").isEmpty)
        XCTAssertTrue(decoder.finish().isEmpty)
    }

    func testTrailingCROnlyIsCompleteLineButStillNeedsBlankLine() {
        var decoder = SSEDecoder()
        XCTAssertTrue(decoder.push("data: x\r").isEmpty)
        XCTAssertTrue(decoder.finish().isEmpty)
    }

    func testBOMIsStripped() {
        var decoder = SSEDecoder()
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("data: bom\n\n".utf8))
        let events = decoder.push(data)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "bom")
    }

    func testFieldWithoutColonHasEmptyValue() {
        var decoder = SSEDecoder()
        let events = decoder.push("data\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "")
    }

    func testOnlyOneLeadingSpaceStripped() {
        var decoder = SSEDecoder()
        let events = decoder.push("data:  x\n\n")
        XCTAssertEqual(events.first?.data, " x")
    }

    func testDefaultEventNameIsMessage() {
        var decoder = SSEDecoder()
        let events = decoder.push("data: x\n\n")
        XCTAssertEqual(events.first?.event, "message")
    }

    func testIDFieldIsTracked() {
        var decoder = SSEDecoder()
        let events = decoder.push("id: 42\ndata: x\n\n")
        XCTAssertEqual(events.first?.lastEventId, "42")
    }

    func testUTF8SplitAcrossChunksIsNotCorrupted() {
        let text = "data: 你好，世界\n\n"
        let bytes = Array(text.utf8)
        var decoder = SSEDecoder()
        var events: [SSEEvent] = []
        // 逐字节喂入，故意把多字节字符拆开。
        for byte in bytes {
            events.append(contentsOf: decoder.push(byte))
        }
        XCTAssertEqual(events.first?.data, "你好，世界")
    }

    func testByteByByteMatchesWholeBuffer() {
        let text = "event: ping\r\ndata: {\"type\":\"ping\"}\r\n\r\n: c\r\n\r\ndata: x\ndata: y\n\n"
        var whole = SSEDecoder()
        let expected = whole.push(text)

        var byteByByte = SSEDecoder()
        var actual: [SSEEvent] = []
        for byte in Data(text.utf8) {
            actual.append(contentsOf: byteByByte.push(byte))
        }

        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.count, 2)
        XCTAssertEqual(actual[0].event, "ping")
        XCTAssertEqual(actual[1].data, "x\ny")
    }

    func testMultipleEventsInOneChunk() {
        var decoder = SSEDecoder()
        let events = decoder.push("data: 1\n\ndata: 2\n\n")
        XCTAssertEqual(events.map(\.data), ["1", "2"])
    }
}
