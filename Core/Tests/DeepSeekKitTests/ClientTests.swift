import Foundation
import XCTest
@testable import DeepSeekKit

/// 错误映射：契约 §8.5。
final class ClientTests: XCTestCase {

    private final class RequestRecorder {
        var requests: [URLRequest] = []
    }

    private func makeRequest() -> ChatRequest {
        ChatRequest(
            system: "s",
            messages: [RequestMessage(role: .user, text: "hi")],
            thinking: true,
            search: true,
            readURL: true,
            titleGeneration: true
        )
    }

    private func collect(_ client: DeepSeekClient) async -> Result<[StreamEvent], Error> {
        var events: [StreamEvent] = []
        do {
            for try await event in client.stream(makeRequest()) {
                events.append(event)
            }
            return .success(events)
        } catch {
            return .failure(error)
        }
    }

    private func bodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while true {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // MARK: verifyKey

    func testVerifyKeySendsBearerTokenToModels() async throws {
        let recorder = RequestRecorder()
        let client = TestHTTP.client { request in
            recorder.requests.append(request)
            return (
                TestHTTP.response(200),
                Data("{\"data\":[{\"id\":\"deepseek-flash\"}]}".utf8)
            )
        }

        try await client.verifyKey()

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testOriginWithTrailingSlashStillBuildsModelsPath() async throws {
        let recorder = RequestRecorder()
        let client = TestHTTP.client(origin: "http://127.0.0.1:8787/") { request in
            recorder.requests.append(request)
            return (TestHTTP.response(200), Data("{}".utf8))
        }

        try await client.verifyKey()

        XCTAssertEqual(recorder.requests.first?.url?.path, "/models")
    }

    func testVerifyKeyMapsNon2xxToHTTPError() async throws {        let client = TestHTTP.client { _ in
            (TestHTTP.response(401), Data("{\"error\":{\"message\":\"Invalid API key\"}}".utf8))
        }

        do {
            try await client.verifyKey()
            XCTFail("应抛出错误")
        } catch {
            guard let deepSeekError = error as? DeepSeekError,
                  case let .http(status, message) = deepSeekError
            else { return XCTFail("应为 http 错误，实际 \(error)") }
            XCTAssertEqual(status, 401)
            XCTAssertEqual(message, "Invalid API key")
        }
    }

    func testVerifyKeyMapsTransportFailureToNetworkError() async throws {
        let client = TestHTTP.client { _ in throw URLError(.notConnectedToInternet) }

        do {
            try await client.verifyKey()
            XCTFail("应抛出错误")
        } catch {
            guard let deepSeekError = error as? DeepSeekError,
                  case .network = deepSeekError
            else { return XCTFail("应为 network 错误，实际 \(error)") }
        }
    }

    // MARK: stream

    func testStreamHappyPathYieldsAllEventsAndCorrectRequest() async throws {
        let recorder = RequestRecorder()
        let frames: [(event: String, json: String)] = [
            ("message_start", Samples.messageStart),
            ("content_block_start", Samples.textBlockStart),
            ("content_block_delta", Samples.textDelta),
            ("content_block_delta", Samples.textDelta),
            ("content_block_stop", Samples.blockStop),
            ("message_delta", Samples.messageDelta),
            ("message_stop", Samples.messageStop),
        ]
        let client = TestHTTP.client { request in
            recorder.requests.append(request)
            return (
                TestHTTP.response(200, contentType: "text/event-stream; charset=utf-8"),
                TestHTTP.sse(frames)
            )
        }

        let result = await collect(client)
        let events = try result.get()
        XCTAssertEqual(events.count, 7)
        guard case .messageStop = try XCTUnwrap(events.last) else {
            return XCTFail("最后一个事件应为 messageStop")
        }

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/anthropic/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

        let body = try XCTUnwrap(bodyData(request))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)
        let thinking = try XCTUnwrap(json["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "enabled")
        let tools = try XCTUnwrap(json["tools"] as? [Any])
        XCTAssertEqual(tools.count, 2)
    }

    func testStreamMapsNon2xxToHTTPError() async throws {
        let client = TestHTTP.client { _ in
            (TestHTTP.response(400), Data("{\"error\":{\"message\":\"bad request\"}}".utf8))
        }

        let result = await collect(client)
        guard case let .failure(error) = result else { return XCTFail("应失败") }
        guard let deepSeekError = error as? DeepSeekError,
              case let .http(status, message) = deepSeekError
        else { return XCTFail("应为 http 错误，实际 \(error)") }
        XCTAssertEqual(status, 400)
        XCTAssertEqual(message, "bad request")
    }

    func testStreamUsesRawBodyWhenErrorBodyIsNotJSON() async throws {
        let client = TestHTTP.client { _ in
            (TestHTTP.response(500), Data("internal boom".utf8))
        }

        let result = await collect(client)
        guard case let .failure(error) = result else { return XCTFail("应失败") }
        guard let deepSeekError = error as? DeepSeekError,
              case let .http(status, message) = deepSeekError
        else { return XCTFail("应为 http 错误，实际 \(error)") }
        XCTAssertEqual(status, 500)
        XCTAssertEqual(message, "internal boom")
    }

    func testStreamRejectsNonEventStreamContentType() async throws {
        let client = TestHTTP.client { _ in
            (TestHTTP.response(200, contentType: "application/json"), Data("{\"oops\":true}".utf8))
        }

        let result = await collect(client)
        guard case let .failure(error) = result else { return XCTFail("应失败") }
        guard let deepSeekError = error as? DeepSeekError,
              case .protocolViolation = deepSeekError
        else { return XCTFail("应为 protocolViolation，实际 \(error)") }
    }

    func testStreamMapsErrorFrameToStreamError() async throws {
        let frames: [(event: String, json: String)] = [
            ("message_start", Samples.messageStart),
            ("error", "{\"error\":{\"message\":\"等待生成超时\"}}"),
        ]
        let client = TestHTTP.client { _ in
            (TestHTTP.response(200, contentType: "text/event-stream"), TestHTTP.sse(frames))
        }

        let result = await collect(client)
        guard case let .failure(error) = result else { return XCTFail("应失败") }
        guard let deepSeekError = error as? DeepSeekError,
              case let .stream(message) = deepSeekError
        else { return XCTFail("应为 stream 错误，实际 \(error)") }
        XCTAssertEqual(message, "等待生成超时")
    }

    func testStreamEndingBeforeMessageStopIsInterrupted() async throws {
        let frames: [(event: String, json: String)] = [
            ("message_start", Samples.messageStart),
            ("content_block_start", Samples.textBlockStart),
            ("content_block_delta", Samples.textDelta),
        ]
        let client = TestHTTP.client { _ in
            (TestHTTP.response(200, contentType: "text/event-stream"), TestHTTP.sse(frames))
        }

        var received = 0
        do {
            for try await _ in client.stream(makeRequest()) {
                received += 1
            }
            XCTFail("应抛出 interrupted")
        } catch {
            guard let deepSeekError = error as? DeepSeekError,
                  case .interrupted = deepSeekError
            else { return XCTFail("应为 interrupted，实际 \(error)") }
            XCTAssertEqual(received, 3)
        }
    }

    func testStreamMapsTransportFailureToNetworkError() async throws {
        let client = TestHTTP.client { _ in throw URLError(.timedOut) }

        let result = await collect(client)
        guard case let .failure(error) = result else { return XCTFail("应失败") }
        guard let deepSeekError = error as? DeepSeekError,
              case .network = deepSeekError
        else { return XCTFail("应为 network 错误，实际 \(error)") }
    }

    func testBreakingOutOfStreamIsHarmless() async throws {
        let frames: [(event: String, json: String)] = [
            ("message_start", Samples.messageStart),
            ("content_block_start", Samples.textBlockStart),
            ("content_block_delta", Samples.textDelta),
            ("message_stop", Samples.messageStop),
        ]
        let client = TestHTTP.client { _ in
            (TestHTTP.response(200, contentType: "text/event-stream"), TestHTTP.sse(frames))
        }

        var count = 0
        for try await _ in client.stream(makeRequest()) {
            count += 1
            break
        }
        XCTAssertEqual(count, 1)
    }

    func testTrailingEventWithoutBlankLineIsInterrupted() async throws {
        // 与真实服务端行为一致：没有以空行收尾的 message_stop 不会被派发。
        let text = "event: message_start\ndata: \(Samples.messageStart)\n\n"
            + "event: message_stop\ndata: {\"type\":\"message_stop\"}"
        let client = TestHTTP.client { _ in
            (TestHTTP.response(200, contentType: "text/event-stream"), Data(text.utf8))
        }

        let result = await collect(client)
        guard case let .failure(error) = result else { return XCTFail("应失败") }
        guard let deepSeekError = error as? DeepSeekError,
              case .interrupted = deepSeekError
        else { return XCTFail("应为 interrupted，实际 \(error)") }
    }
}
