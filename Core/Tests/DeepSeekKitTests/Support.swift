import Foundation
import XCTest
@testable import DeepSeekKit

// MARK: - 协议样本

/// 与服务端真实形状一致的样本（字段取自 Reference/chat-demo/src/services/api/types.ts）。
enum Samples {
    static let messageID = "9f2c1d7a4b6e4c0fa1b2c3d4e5f60718"
    static let model = "deepseek-flash"
    static let signature = "a1b2c3d4e5f60718293a4b5c6d7e8f90"

    static let searchToolID = "srvtoolu_s_1_0123456789abcdef0123456789abcdef"
    static let readToolID = "srvtoolu_rl_1_fedcba9876543210fedcba9876543210"

    static let messageStart = """
    {"type":"message_start","message":{"id":"\(messageID)","model":"\(model)","usage":{"input_tokens":120,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}
    """

    static let textBlockStart = """
    {"type":"content_block_start","index":3,"content_block":{"type":"text","text":""}}
    """

    static let thinkingBlockStart = """
    {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}
    """

    static let searchToolBlockStart = """
    {"type":"content_block_start","index":1,"content_block":{"type":"server_tool_use","id":"\(searchToolID)","name":"deepseek_web_search","input":{"action":"search","queries":["DeepSeek Chat 联网搜索","Liquid Glass macOS"]},"caller":{"type":"direct"},"kind":"search"}}
    """

    static let readToolBlockStart = """
    {"type":"content_block_start","index":2,"content_block":{"type":"server_tool_use","id":"\(readToolID)","name":"deepseek_read_url","input":{"action":"read_link","url":"https://example.com/page"},"caller":{"type":"direct"},"kind":"read_link"}}
    """

    static let searchResultBlockStart = """
    {"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","tool_use_id":"\(searchToolID)","content":[{"type":"web_search_result","title":"示例站点","url":"https://example.com/a","snippet":"第一段摘要","site_icon":"https://example.com/icon.png","site_name":"Example","encrypted_content":"ZW5jcnlwdGVk","page_age":"2026-01-02T03:04:05Z"},{"type":"web_search_result","title":"第二个站点","url":"https://example.com/b","snippet":null,"site_icon":null,"site_name":null,"encrypted_content":"","page_age":null}],"kind":"search"}}
    """

    static let searchResultErrorBlockStart = """
    {"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","tool_use_id":"\(searchToolID)","content":[{"type":"web_search_tool_result_error","error_code":"unavailable"}],"kind":"search"}}
    """

    static let fetchResultBlockStart = """
    {"type":"content_block_start","index":3,"content_block":{"type":"web_fetch_tool_result","tool_use_id":"\(readToolID)","content":{"type":"web_fetch_result","url":"https://example.com/page","content":{"type":"document","source":{"type":"text","media_type":"text/plain","data":""},"title":"页面标题"},"published_at":"2025-06-01"},"kind":"read_link","signature":"page-signature"}}
    """

    static let fetchResultErrorBlockStart = """
    {"type":"content_block_start","index":3,"content_block":{"type":"web_fetch_tool_result","tool_use_id":"\(readToolID)","content":{"type":"web_fetch_tool_result_error","error_code":"url_not_accessible"},"kind":"read_link"}}
    """

    static let citation = """
    {"type":"web_search_result_location","url":"https://example.com/a","title":"示例站点","cited_text":"截至引用处的正文","encrypted_index":""}
    """

    static let textDelta = """
    {"type":"content_block_delta","index":3,"delta":{"type":"text_delta","text":"你好"}}
    """

    static let thinkingDelta = """
    {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"先想一下"}}
    """

    static let signatureDelta = """
    {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"\(signature)"}}
    """

    static let citationDelta = """
    {"type":"content_block_delta","index":3,"delta":{"type":"citations_delta","citation":\(citation)}}
    """

    static let blockStop = """
    {"type":"content_block_stop","index":3}
    """

    static let messageDelta = """
    {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null,"title":"联网搜索演示"},"usage":{"input_tokens":120,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":512}}
    """

    static let messageStop = """
    {"type":"message_stop"}
    """

    static let ping = """
    {"type":"ping"}
    """
}

// MARK: - 编码辅助

func encodeObject<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
}

func encodeArray<T: Encodable>(_ value: T) throws -> [Any] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [Any])
}

func requireEvent(
    _ event: StreamEvent?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> StreamEvent {
    try XCTUnwrap(event, "事件应被解码", file: file, line: line)
}

// MARK: - 网络桩

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum TestHTTP {
    static func response(_ status: Int, contentType: String = "application/json") -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8787/test")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
    }

    static func sse(_ frames: [(event: String, json: String)]) -> Data {
        var text = ""
        for frame in frames {
            text += "event: \(frame.event)\ndata: \(frame.json)\n\n"
        }
        return Data(text.utf8)
    }

    static func client(
        origin: String = "http://127.0.0.1:8787",
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> DeepSeekClient {
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return DeepSeekClient(
            apiOrigin: URL(string: origin)!,
            apiKey: "test-key",
            session: URLSession(configuration: configuration)
        )
    }
}
