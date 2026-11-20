import Foundation

/// 官方客户端的默认配置，避免 UI 层散落魔法字符串。
public enum DeepSeekDefaults {
    /// 生产环境 API 地址；本地联调可指向 `http://127.0.0.1:8787`。
    public static let apiOrigin = URL(string: "https://api.deepseek.com")!
    /// 官方客户端使用的系统提示词。
    public static let systemPrompt = "该助手为DeepSeek，由深度求索公司创造。"
    /// Files API 与「通过 file_id 引用文件」时必须携带的 beta 标记。
    public static let filesBeta = "files-api-2025-04-14"
}

/// DeepSeek Messages API（Anthropic 兼容格式）客户端。
///
/// 仅依赖 Foundation；`stream` 返回 `AsyncThrowingStream`，取消消费即中断网络请求。
public struct DeepSeekClient: Sendable {
    public let apiOrigin: URL
    public let apiKey: String
    private let session: URLSession

    public init(apiOrigin: URL = DeepSeekDefaults.apiOrigin, apiKey: String) {
        self.init(apiOrigin: apiOrigin, apiKey: apiKey, session: .shared)
    }

    /// 测试用入口：注入自定义 URLSession（例如挂载 URLProtocol 桩）。
    public init(apiOrigin: URL, apiKey: String, session: URLSession) {
        self.apiOrigin = apiOrigin
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - 校验 Key

    /// GET /models，2xx 即视为有效。不产生费用。
    public func verifyKey() async throws {
        var request = URLRequest(url: try endpoint("/models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DeepSeekError.protocolViolation("服务响应无效")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw DeepSeekError.http(
                    status: http.statusCode,
                    message: Self.errorMessage(from: data)
                        ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                )
            }
        } catch let error as DeepSeekError {
            throw error
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            throw DeepSeekError.network(error.localizedDescription)
        }
    }

    // MARK: - 流式生成

    /// POST /anthropic/v1/messages, stream=true。
    ///
    /// 流在 `message_stop` 之前结束会抛 `DeepSeekError.interrupted`；
    /// 消费方取消（`onTermination`）会取消底层任务与连接。
    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [self] in
                do {
                    try await run(request, into: continuation)
                    continuation.finish()
                } catch {
                    if Self.isCancellation(error) {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: Self.normalize(error))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ request: ChatRequest,
        into continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var urlRequest = URLRequest(url: try endpoint("/anthropic/v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // 通过 file_id 引用已上传文件时必须声明 Files API beta；纯文本聊天不携带。
        if request.hasFiles {
            urlRequest.setValue(DeepSeekDefaults.filesBeta, forHTTPHeaderField: "anthropic-beta")
        }
        urlRequest.timeoutInterval = 300

        do {
            urlRequest.httpBody = try Self.makeEncoder().encode(request)
        } catch {
            throw DeepSeekError.protocolViolation("请求编码失败：\(error.localizedDescription)")
        }

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.protocolViolation("服务响应无效")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = try await Self.collect(bytes, limit: 64 * 1024)
            throw DeepSeekError.http(
                status: http.statusCode,
                message: Self.errorMessage(from: body)
                    ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.contains("text/event-stream") else {
            let body = try await Self.collect(bytes, limit: 8 * 1024)
            throw DeepSeekError.protocolViolation(
                Self.errorMessage(from: body) ?? "响应不是事件流"
            )
        }

        var decoder = SSEDecoder()
        var sawMessageStop = false

        for try await byte in bytes {
            if Task.isCancelled { throw CancellationError() }
            for event in decoder.push(byte) {
                if let streamEvent = try EventDecoder.decode(
                    eventName: event.event,
                    data: event.data
                ) {
                    if case .messageStop = streamEvent { sawMessageStop = true }
                    if case .terminated = continuation.yield(streamEvent) { return }
                    if sawMessageStop { return }
                }
            }
        }

        guard sawMessageStop else { throw DeepSeekError.interrupted }
    }

    // MARK: - 内部

    private func endpoint(_ path: String) throws -> URL {
        let base = apiOrigin.absoluteString.hasSuffix("/")
            ? String(apiOrigin.absoluteString.dropLast())
            : apiOrigin.absoluteString
        guard let url = URL(string: base + path) else {
            throw DeepSeekError.protocolViolation("无效的 API 地址：\(apiOrigin.absoluteString)")
        }
        return url
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(limit, 4096))
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }

    /// 非 2xx 响应体：优先取 `{"error":{"message":...}}`，否则退回原文。
    static func errorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let record = object as? [String: Any],
           let error = record["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(500))
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private static func normalize(_ error: Error) -> DeepSeekError {
        if let error = error as? DeepSeekError { return error }
        return .network(error.localizedDescription)
    }
}
