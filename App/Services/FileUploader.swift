import Foundation

// MARK: - 上传错误

/// 上传失败的原因。文案只给短句，服务端原文可能很长且是英文，不直接展示（参考实现同样处理）。
enum FileUploadError: Error, LocalizedError, Sendable {
    /// origin 拼不出合法地址。
    case invalidOrigin
    /// 本地文件读不出来（已移动、无权限、被沙盒隔离）。
    case unreadableFile(String)
    /// 超过该 purpose 的大小上限。
    case tooLarge(limitMB: Int)
    /// 非 2xx。
    case http(status: Int, message: String)
    /// 请求没到达服务端。
    case network(String)
    /// 2xx 但响应体不是预期的 file 对象。
    case invalidResponse(String)

    /// 重试是否有意义：网络、限流、服务端错误可重试；参数、鉴权、体积类不可重试。
    /// 对应 Reference/chat-demo/src/services/api/errors.ts `isRetryableApiError`。
    var isRetryable: Bool {
        switch self {
        case .network, .invalidOrigin:
            return true
        case let .http(status, _):
            return status == 408 || status == 429 || status >= 500
        case .invalidResponse:
            return true
        case .unreadableFile, .tooLarge:
            return false
        }
    }

    /// 附件卡片上显示的短文案。
    var userMessage: String {
        switch self {
        case .invalidOrigin:
            return "接口地址无效"
        case .unreadableFile:
            return "无法读取文件"
        case let .tooLarge(limitMB):
            return "超过 \(limitMB) MB 上限"
        case let .http(status, message):
            switch status {
            case 401:
                return "API Key 无效"
            case 402:
                return "余额不足"
            case 413:
                return "文件过大"
            case 429:
                return "请求过于频繁"
            default:
                if status >= 500 { return "服务繁忙" }
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "上传失败" : String(trimmed.prefix(60))
            }
        case .network:
            return "网络连接失败"
        case .invalidResponse:
            return "服务响应异常"
        }
    }

    var errorDescription: String? { userMessage }
}

// MARK: - 上传服务

/// Files API 上传服务：`POST {origin}/anthropic/v1/files`，multipart/form-data。
///
/// 协议要点（Reference/chat-demo/src/services/api/client.ts `uploadFile`）：
/// - 字段顺序固定：先 `purpose`（图片不传）再 `file`；
/// - 请求头 `x-api-key` + `anthropic-beta: files-api-2025-04-14`；
/// - purpose：pdf/doc/docx/ppt/pptx → `rich_layout_recognition`，其余 → `user_data`；
/// - 响应 `{id, type, size_bytes, created_at, filename, mime_type}`。
struct FileUploader: Sendable {

    /// 上传时用的会话；测试可注入挂了 URLProtocol 桩的会话。
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: 上传

    /// 上传单个文件，返回已带 `fileID` 的 `.ready` 附件。
    ///
    /// - Parameters:
    ///   - fileURL: 本地原件地址。
    ///   - apiKey: DeepSeek API Key。
    ///   - origin: API 根地址（如 `https://api.deepseek.com`，允许结尾斜杠）。
    ///   - id: 本地附件 id；重试时传入原 id 可保持 UI 身份不变。
    ///   - onProgress: 上传进度 0...1，在主线程外回调，调用方自行切回 MainActor。
    /// - Throws: `FileUploadError`；取消时抛 `CancellationError`。
    @discardableResult
    func upload(
        fileURL: URL,
        apiKey: String,
        origin: URL,
        id: String = UUID().uuidString,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> FileAttachment {
        var attachment = FileAttachment(id: id, fileURL: fileURL)

        // 系统给不出 MIME 时 FileAttachment 已按扩展名推断；这里再兜底一次。
        if attachment.mimeType.isEmpty {
            attachment.mimeType = FileAttachment.mimeType(forExtension: fileURL.pathExtension)
        }

        let limit = attachment.maxSizeBytes
        if attachment.byteSize > limit {
            throw FileUploadError.tooLarge(limitMB: limit / (1024 * 1024))
        }

        // 沙盒 / 权限受限的路径需要显式取用，否则读写会被拒绝。
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw FileUploadError.unreadableFile(error.localizedDescription)
        }
        // 预检用的是元数据大小，实际字节数可能不同（例如并发写入）。
        if data.count > limit {
            throw FileUploadError.tooLarge(limitMB: limit / (1024 * 1024))
        }
        attachment.byteSize = data.count

        let boundary = "DeepGlass-\(UUID().uuidString)"
        let body = Self.multipartBody(
            boundary: boundary,
            purpose: attachment.uploadPurpose,
            filename: attachment.filename,
            mimeType: attachment.resolvedMimeType,
            fileData: data
        )

        var request = URLRequest(url: try Self.filesEndpoint(origin))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        // 上传与引用文件都必须声明 Files API beta。
        request.setValue(DeepSeekDefaults.filesBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300

        let progress = UploadProgressDelegate(onProgress: onProgress)
        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.upload(
                for: request,
                from: body,
                delegate: progress
            )
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            throw FileUploadError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FileUploadError.invalidResponse("服务响应无效")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FileUploadError.http(
                status: http.statusCode,
                message: Self.errorMessage(from: responseData)
            )
        }

        let uploaded: UploadedFile
        do {
            uploaded = try JSONDecoder().decode(UploadedFile.self, from: responseData)
        } catch {
            throw FileUploadError.invalidResponse("响应缺少 file id")
        }
        guard !uploaded.id.isEmpty else {
            throw FileUploadError.invalidResponse("响应缺少 file id")
        }

        onProgress?(1)
        // 服务端回填的名称/类型优先，缺失时保留本地值。
        return attachment.ready(
            fileID: uploaded.id,
            byteSize: uploaded.sizeBytes ?? attachment.byteSize,
            filename: uploaded.filename,
            mimeType: uploaded.mimeType
        )
    }

    // MARK: 删除

    /// `DELETE {origin}/anthropic/v1/files/{file_id}`；删除失败不抛给 UI，
    /// 服务端文件未清理只会占用配额，不影响会话内容。
    func delete(fileID: String, apiKey: String, origin: URL) async throws {
        guard !fileID.isEmpty else { return }
        var request = URLRequest(
            url: try Self.filesEndpoint(origin).appending(path: fileID)
        )
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(DeepSeekDefaults.filesBeta, forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FileUploadError.invalidResponse("服务响应无效")
        }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 404 else {
            throw FileUploadError.http(
                status: http.statusCode,
                message: Self.errorMessage(from: data)
            )
        }
    }

    // MARK: 内部

    static func filesEndpoint(_ origin: URL) throws -> URL {
        var base = origin.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/anthropic/v1/files") else {
            throw FileUploadError.invalidOrigin
        }
        return url
    }

    /// multipart/form-data 请求体。**purpose 必须排在 file 之前**（服务端按顺序解析）。
    static func multipartBody(
        boundary: String,
        purpose: FilePurpose?,
        filename: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"

        func appendText(_ text: String) {
            body.append(Data(text.utf8))
        }

        if let purpose {
            appendText("--\(boundary)\(crlf)")
            appendText("Content-Disposition: form-data; name=\"purpose\"\(crlf)\(crlf)")
            appendText(purpose.rawValue)
            appendText(crlf)
        }

        appendText("--\(boundary)\(crlf)")
        appendText("Content-Disposition: form-data; name=\"file\"; filename=\"\(sanitizedFilename(filename))\"\(crlf)")
        appendText("Content-Type: \(mimeType.isEmpty ? "application/octet-stream" : mimeType)\(crlf)\(crlf)")
        body.append(fileData)
        appendText(crlf)
        appendText("--\(boundary)--\(crlf)")
        return body
    }

    /// 文件名里的引号与换行会破坏 Content-Disposition，必须替换掉。
    static func sanitizedFilename(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return cleaned.isEmpty ? "file" : cleaned
    }

    /// 非 2xx 响应体：优先取 `{"error":{"message":...}}`，否则退回原文。
    static func errorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data),
           let record = object as? [String: Any],
           let error = record["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

// MARK: - 进度

/// 把 `URLSession` 的上行字节数换算成 0...1；只在有回调时注册，避免无谓开销。
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: (@Sendable (Double) -> Void)?

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let onProgress, totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(min(max(fraction, 0), 1))
    }
}
