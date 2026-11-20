import Foundation
import XCTest
@testable import DeepSeekKit

/// 与本地 mock 服务器的端到端联调，**默认跳过**，不依赖外网。
///
/// 运行方式：
/// ```
/// python3 scripts/mock-server.py &
/// DEEPSEEK_INTEGRATION=1 swift test --package-path Core --filter IntegrationTests
/// ```
final class IntegrationTests: XCTestCase {

    func testMockServerEndToEnd() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DEEPSEEK_INTEGRATION"] == "1" else {
            throw XCTSkip("默认跳过：设置 DEEPSEEK_INTEGRATION=1 并先运行 scripts/mock-server.py")
        }

        let originString = environment["DEEPSEEK_ORIGIN"] ?? "http://127.0.0.1:8787"
        let origin = try XCTUnwrap(URL(string: originString))
        let client = DeepSeekClient(apiOrigin: origin, apiKey: "mock-key")

        try await client.verifyKey()

        let request = ChatRequest(
            system: DeepSeekDefaults.systemPrompt,
            messages: [RequestMessage(role: .user, text: "DeepSeek Chat 的联网搜索如何展示引用？")],
            thinking: true,
            search: true,
            readURL: true,
            titleGeneration: true
        )

        var accumulator = StreamAccumulator(id: "integration", model: request.model)
        var textDeltaCount = 0
        var sawMessageStop = false
        for try await event in client.stream(request) {
            accumulator.apply(event)
            switch event {
            case .textDelta:
                textDeltaCount += 1
            case .messageStop:
                sawMessageStop = true
            default:
                break
            }
        }
        accumulator.finish(status: .complete)

        XCTAssertTrue(sawMessageStop)
        XCTAssertGreaterThanOrEqual(textDeltaCount, 20, "mock 会把正文拆成 20+ 段")
        XCTAssertEqual(accumulator.message.stopReason, "end_turn")
        XCTAssertEqual(accumulator.title, "联网搜索演示")
        XCTAssertEqual(accumulator.message.status, .complete)

        XCTAssertFalse(accumulator.message.thinkingText.isEmpty)
        let thinkingBlock = try XCTUnwrap(accumulator.message.blocks.first { $0.kind == .thinking })
        XCTAssertEqual(thinkingBlock.signature?.count, 32, "signature_delta 应下发 32 位 hex")

        let toolBlocks = accumulator.message.blocks.filter { $0.kind == .toolUse }
        XCTAssertEqual(toolBlocks.count, 1)
        XCTAssertEqual(toolBlocks.first?.toolUse?.kind, .search)
        XCTAssertEqual(toolBlocks.first?.toolUse?.queries.count, 2)

        XCTAssertEqual(accumulator.message.sources.count, 2)
        XCTAssertEqual(
            Set(accumulator.message.sources.map(\.url)),
            Set(["https://example.com/a", "https://example.com/b"])
        )

        let textBlock = try XCTUnwrap(accumulator.message.blocks.first { $0.kind == .text })
        XCTAssertEqual(textBlock.citations.count, 1)
        XCTAssertGreaterThan(accumulator.message.plainText.count, 80)
    }
}
