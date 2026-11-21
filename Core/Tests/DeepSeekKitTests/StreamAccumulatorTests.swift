import Foundation
import XCTest
@testable import DeepSeekKit

/// 累加器：契约 §8.3。
final class StreamAccumulatorTests: XCTestCase {

    private func makeAccumulator() -> StreamAccumulator {
        StreamAccumulator(id: "m1", model: "deepseek-flash", createdAt: Date(timeIntervalSince1970: 0))
    }

    func testTextDeltasAreMergedInOrder() {
        var accumulator = makeAccumulator()
        accumulator.apply(.blockStart(index: 0, block: Block(id: "b0", kind: .text)))
        accumulator.apply(.textDelta(index: 0, "你好"))
        accumulator.apply(.textDelta(index: 0, "，"))
        accumulator.apply(.textDelta(index: 0, "世界"))

        XCTAssertEqual(accumulator.message.blocks.count, 1)
        XCTAssertEqual(accumulator.message.blocks[0].kind, .text)
        XCTAssertEqual(accumulator.message.plainText, "你好，世界")
        XCTAssertEqual(accumulator.message.status, .streaming)
    }

    func testDeltasForUnknownIndexAreIgnored() {
        var accumulator = makeAccumulator()
        accumulator.apply(.textDelta(index: 9, "多余"))
        XCTAssertTrue(accumulator.message.blocks.isEmpty)
    }

    func testTextDeltaIgnoredOnThinkingBlock() {
        var accumulator = makeAccumulator()
        accumulator.apply(.blockStart(index: 0, block: Block(id: "b0", kind: .thinking)))
        accumulator.apply(.textDelta(index: 0, "不应写入"))
        XCTAssertEqual(accumulator.message.thinkingText, "")
    }

    func testThinkingAndSignatureAccumulate() {
        var accumulator = makeAccumulator()
        accumulator.apply(.blockStart(index: 0, block: Block(id: "b0", kind: .thinking)))
        accumulator.apply(.thinkingDelta(index: 0, "先拆解"))
        accumulator.apply(.thinkingDelta(index: 0, "问题"))
        accumulator.apply(.signatureDelta(index: 0, "sig-1"))
        accumulator.apply(.signatureDelta(index: 0, "sig-2"))

        XCTAssertEqual(accumulator.message.thinkingText, "先拆解问题")
        XCTAssertEqual(accumulator.message.blocks[0].signature, "sig-1sig-2")
    }

    func testCitationsDeduplicatedByURL() {
        var accumulator = makeAccumulator()
        accumulator.apply(.blockStart(index: 0, block: Block(id: "b0", kind: .text)))
        accumulator.apply(.textDelta(index: 0, "正文"))
        accumulator.apply(
            .citationDelta(index: 0, Citation(url: "https://a", title: "A", citedText: "正文"))
        )
        accumulator.apply(
            .citationDelta(index: 0, Citation(url: "https://a", title: "A2", citedText: "正文"))
        )
        accumulator.apply(
            .citationDelta(index: 0, Citation(url: "https://b", title: "B", citedText: "正文"))
        )

        XCTAssertEqual(accumulator.message.blocks[0].citations.map(\.url), ["https://a", "https://b"])
        // 引用出现后继续追加 text 到同一块（契约 §6 允许合并）。
        accumulator.apply(.textDelta(index: 0, "继续"))
        XCTAssertEqual(accumulator.message.blocks.count, 1)
        XCTAssertEqual(accumulator.message.plainText, "正文继续")
    }

    func testToolAndSearchResultBlocks() {
        var accumulator = makeAccumulator()
        let tool = ServerToolUse(
            id: "srvtoolu_s_1_x",
            kind: .search,
            queries: ["q"],
            action: "search"
        )
        accumulator.apply(.blockStart(index: 0, block: Block(id: tool.id, kind: .toolUse, toolUse: tool)))
        accumulator.apply(
            .blockStart(
                index: 1,
                block: Block(
                    id: tool.id,
                    kind: .searchResults,
                    searchResults: [WebSearchResult(url: "https://a", title: "A")]
                )
            )
        )

        XCTAssertEqual(accumulator.message.blocks.map(\.kind), [.toolUse, .searchResults])
        XCTAssertEqual(accumulator.message.blocks[0].toolUse?.queries, ["q"])
        XCTAssertEqual(accumulator.message.sources.map(\.url), ["https://a"])
    }

    func testMessageDeltaStoresStopReasonAndTitle() {
        var accumulator = makeAccumulator()
        accumulator.apply(.messageDelta(stopReason: "end_turn", title: "联网搜索演示"))
        accumulator.apply(.messageStop)

        XCTAssertEqual(accumulator.message.stopReason, "end_turn")
        XCTAssertEqual(accumulator.title, "联网搜索演示")
        XCTAssertEqual(accumulator.message.status, .streaming)
    }

    func testBlankTitleIsIgnored() {
        var accumulator = makeAccumulator()
        accumulator.apply(.messageDelta(stopReason: "end_turn", title: "   "))
        XCTAssertNil(accumulator.title)
    }

    func testFinishSetsStatusAndError() {
        var accumulator = makeAccumulator()
        accumulator.apply(.blockStart(index: 0, block: Block(id: "b0", kind: .text)))
        accumulator.apply(.textDelta(index: 0, "半截"))
        accumulator.finish(status: .failed, error: "网络断开")

        XCTAssertEqual(accumulator.message.status, .failed)
        XCTAssertEqual(accumulator.message.errorText, "网络断开")
        XCTAssertEqual(accumulator.message.blocks.count, 1)
        XCTAssertEqual(accumulator.message.plainText, "半截")
    }

    func testFinishCompleteClearsError() {
        var accumulator = makeAccumulator()
        accumulator.finish(status: .streaming, error: "临时错误")
        accumulator.finish(status: .complete)
        XCTAssertEqual(accumulator.message.status, .complete)
        XCTAssertNil(accumulator.message.errorText)
    }

    func testSourcesDeduplicatedAcrossBlocks() {
        var accumulator = makeAccumulator()
        accumulator.apply(
            .blockStart(
                index: 0,
                block: Block(
                    id: "a",
                    kind: .searchResults,
                    searchResults: [
                        WebSearchResult(url: "https://a", title: "A"),
                        WebSearchResult(url: "https://b", title: "B"),
                    ]
                )
            )
        )
        accumulator.apply(
            .blockStart(
                index: 1,
                block: Block(
                    id: "b",
                    kind: .searchResults,
                    searchResults: [
                        WebSearchResult(url: "https://b", title: "B"),
                        WebSearchResult(url: "https://c", title: "C"),
                    ]
                )
            )
        )

        XCTAssertEqual(accumulator.message.sources.map(\.url), ["https://a", "https://b", "https://c"])
    }

    func testPingAndMessageStartAreHarmless() {
        var accumulator = makeAccumulator()
        accumulator.apply(.ping)
        accumulator.apply(.messageStart(id: "server-id", model: "deepseek-v4-pro"))
        XCTAssertEqual(accumulator.message.id, "m1")
        XCTAssertTrue(accumulator.message.blocks.isEmpty)
    }

    // MARK: 思考用时（客户端计时）

    /// 测试用可拨动时钟。
    private final class TestClock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    func testThinkingSecondsRecordedWhenFirstTextArrives() {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = TestClock(start)
        var accumulator = StreamAccumulator(
            id: "m1",
            model: "deepseek-flash",
            createdAt: start,
            now: { clock.now }
        )

        accumulator.apply(.blockStart(index: 0, block: Block(id: "b0", kind: .thinking)))
        accumulator.apply(.thinkingDelta(index: 0, "先想一想"))

        clock.now = start.addingTimeInterval(3.6)
        accumulator.apply(.blockStart(index: 1, block: Block(id: "b1", kind: .text)))
        XCTAssertEqual(accumulator.message.thinkingSeconds ?? -1, 3.6, accuracy: 0.0001)

        // 后续正文增量与新的正文块都不应覆盖首次记录。
        clock.now = start.addingTimeInterval(9)
        accumulator.apply(.textDelta(index: 1, "正文"))
        accumulator.apply(.blockStart(index: 2, block: Block(id: "b2", kind: .text)))
        XCTAssertEqual(accumulator.message.thinkingSeconds ?? -1, 3.6, accuracy: 0.0001)
    }

    func testThinkingSecondsFallsBackToTotalDurationAtFinish() {
        let start = Date(timeIntervalSince1970: 2_000)
        let clock = TestClock(start)
        var accumulator = StreamAccumulator(
            id: "m1",
            model: "deepseek-flash",
            createdAt: start,
            now: { clock.now }
        )

        accumulator.apply(.blockStart(index: 0, block: Block(id: "b0", kind: .thinking)))
        accumulator.apply(.thinkingDelta(index: 0, "只思考，没有正文"))

        clock.now = start.addingTimeInterval(5.25)
        accumulator.finish(status: .stopped)
        XCTAssertEqual(accumulator.message.thinkingSeconds ?? -1, 5.25, accuracy: 0.0001)

        // 没有思考块时保持 nil。
        var plain = StreamAccumulator(
            id: "m2",
            model: "deepseek-flash",
            createdAt: start,
            now: { clock.now }
        )
        plain.apply(.blockStart(index: 0, block: Block(id: "b0", kind: .text)))
        plain.apply(.textDelta(index: 0, "直接回答"))
        plain.finish(status: .complete)
        XCTAssertNil(plain.message.thinkingSeconds)
    }
}
