import Foundation

// MARK: - 附件

/// 输入框里的一条附件。既是 UI 的数据源（附件条 / 文件卡片），也是 `Block.kind == .file`
/// 的载荷：上传成功后 `fileID` 即 Files API 返回的 `file_id`，请求按它引用文件。
///
/// 状态机：`.uploading` → `.ready`（拿到 fileID）或 `.failed`（可重试时回到 `.uploading`）。
public struct FileAttachment: Codable, Sendable, Hashable, Identifiable {

    public enum State: String, Codable, Sendable {
        case uploading
        case ready
        case failed
    }

    /// 本地稳定标识：选中文件时生成，上传/重试/删除都按它定位，不随服务端 id 变化。
    public var id: String
    /// Files API 返回的 `file_id`；未上传成功时为 nil。
    public var fileID: String?
    /// 展示用文件名（含扩展名）。
    public var filename: String
    /// 上传时声明的 MIME；系统给不出时按扩展名推断。
    public var mimeType: String
    /// 原文件字节数（本地 size，与服务端 `size_bytes` 一致）。
    public var byteSize: Int
    /// 本地原件路径；只用于缩略图与失败重传，不上行。
    public var localPath: String?
    public var state: State
    /// 失败原因（已本地化的短文案）；成功时为 nil。
    public var errorText: String?
    /// 重试是否有意义：网络 / 限流 / 服务端错误可重试，格式或大小不合规不可重试。
    public var isRetryable: Bool

    public init(
        id: String = UUID().uuidString,
        fileID: String? = nil,
        filename: String,
        mimeType: String,
        byteSize: Int,
        localPath: String? = nil,
        state: State = .uploading,
        errorText: String? = nil,
        isRetryable: Bool = true
    ) {
        self.id = id
        self.fileID = fileID
        self.filename = filename
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.localPath = localPath
        self.state = state
        self.errorText = errorText
        self.isRetryable = isRetryable
    }

    /// 便捷构造：从本地文件 URL 读取名称、大小与 MIME。
    /// 读不到大小（例如文件已被移动）时按 0 处理，由上传阶段报错。
    public init(id: String = UUID().uuidString, fileURL: URL) {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        // 这里只 import Foundation：MIME 按扩展名推断，调用方拿到系统类型时可覆盖。
        let mime = FileAttachment.mimeType(forExtension: fileURL.pathExtension)
        self.init(
            id: id,
            filename: fileURL.lastPathComponent,
            mimeType: mime,
            byteSize: values?.fileSize ?? 0,
            localPath: fileURL.path,
            state: .uploading
        )
    }

    // MARK: 派生信息

    /// 小写扩展名（不含点）；没有扩展名时为空串。
    public var fileExtension: String {
        let dot = filename.lastIndex(of: ".")
        guard let dot, dot > filename.startIndex else { return "" }
        return filename[filename.index(after: dot)...].lowercased()
    }

    /// 卡片元信息里的扩展名（大写，不含点）。
    public var displayExtension: String { fileExtension.uppercased() }

    /// 系统给不出 MIME 时按扩展名补齐；仍然未知则退回 octet-stream。
    public var resolvedMimeType: String {
        if !mimeType.isEmpty { return mimeType }
        return Self.mimeType(forExtension: fileExtension)
    }

    /// 图片走 `image` 块并显示缩略图，其余走 `document` 块并显示文件卡片。
    public var isImage: Bool { resolvedMimeType.lowercased().hasPrefix("image/") }

    /// 上传时的 `purpose`：图片不传；PDF 与 Word、PPT 做版面解析；其余按 user_data。
    /// 与参考实现 `getUploadPurpose` 一致。
    public var uploadPurpose: FilePurpose? {
        if isImage { return nil }
        return Self.layoutRecognitionExtensions.contains(fileExtension)
            ? .richLayoutRecognition
            : .userData
    }

    /// 按 purpose 区分的单文件上限：user_data 更小（参考实现 MAX_USER_DATA_SIZE_MB = 32）。
    public var maxSizeBytes: Int {
        uploadPurpose == .userData ? Self.userDataMaxSizeBytes : Self.maxSizeBytes
    }

    /// 是否有可直接引用的服务端文件 id。
    public var hasServerFileID: Bool {
        guard let fileID else { return false }
        return !fileID.isEmpty
    }

    /// 「EXT SIZE」形式的元信息，文件卡片副标题用。
    public var sizeDescription: String {
        [displayExtension, Self.formatSize(byteSize)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: 状态迁移

    /// 上传成功：写入服务端字段并置为 `.ready`。服务端没回填的名称/大小保持本地值。
    public func ready(
        fileID: String,
        byteSize: Int? = nil,
        filename: String? = nil,
        mimeType: String? = nil
    ) -> FileAttachment {
        var copy = self
        copy.fileID = fileID
        copy.state = .ready
        copy.errorText = nil
        if let byteSize { copy.byteSize = byteSize }
        if let filename, !filename.isEmpty { copy.filename = filename }
        if let mimeType, !mimeType.isEmpty { copy.mimeType = mimeType }
        return copy
    }

    /// 上传失败：保留本地信息，记下原因与可重试性；重试前调用 `retrying()`。
    public func failed(message: String, retryable: Bool = true) -> FileAttachment {
        var copy = self
        copy.state = .failed
        copy.errorText = message.isEmpty ? "上传失败" : message
        copy.isRetryable = retryable
        return copy
    }

    /// 重新进入上传中：清空上一次的失败原因。
    public func retrying() -> FileAttachment {
        var copy = self
        copy.state = .uploading
        copy.errorText = nil
        copy.isRetryable = true
        return copy
    }

    // MARK: 常量

    /// 单文件上限 64 MB（与 Files API 一致）。
    public static let maxSizeBytes = 64 * 1024 * 1024
    /// user_data 用途的原文件上限 32 MB。
    public static let userDataMaxSizeBytes = 32 * 1024 * 1024
    /// 单条消息最多附件数。
    public static let maxCount = 50

    /// 需要服务端做版面解析的扩展名。
    static let layoutRecognitionExtensions: Set<String> = ["pdf", "doc", "docx", "ppt", "pptx"]

    /// 按扩展名推断 MIME（系统拿不到 `contentType` 时用）。
    static func mimeType(forExtension ext: String) -> String {
        let key = ext.lowercased()
        return mimeByExtension[key] ?? "application/octet-stream"
    }

    private static let mimeByExtension: [String: String] = [
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "bmp": "image/bmp",
        "svg": "image/svg+xml",
        "svgz": "image/svg+xml",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "heic": "image/heic",
        "heif": "image/heif",
        "avif": "image/avif",
        "ico": "image/x-icon",
        "pdf": "application/pdf",
        "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "ppt": "application/vnd.ms-powerpoint",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "csv": "text/csv",
        "tsv": "text/tab-separated-values",
        "txt": "text/plain",
        "md": "text/markdown",
        "html": "text/html",
        "htm": "text/html",
        "json": "application/json",
        "xml": "application/xml",
        "yaml": "text/yaml",
        "yml": "text/yaml",
        "swift": "text/x-swift",
        "js": "text/javascript",
        "ts": "text/typescript",
        "tsx": "text/typescript",
        "py": "text/x-python",
        "go": "text/x-go",
        "rs": "text/x-rust",
        "java": "text/x-java",
        "c": "text/x-c",
        "h": "text/x-c",
        "cpp": "text/x-c++",
        "cs": "text/x-csharp",
        "php": "text/x-php",
        "rb": "text/x-ruby",
        "sh": "application/x-sh",
        "epub": "application/epub+zip",
    ]

    /// 1024 进制、保留一位小数；≥10 时取整（参考实现 formatSize）。
    public static func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB"]
        var value = Double(bytes) / 1024
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let text = value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
        return "\(text) \(units[unit])"
    }
}

// MARK: - 上传用途

/// POST /anthropic/v1/files 的 `purpose` 字段值。
public enum FilePurpose: String, Codable, Sendable, CaseIterable {
    /// PDF / doc / docx / ppt / pptx：服务端做版面解析。
    case richLayoutRecognition = "rich_layout_recognition"
    /// 纯文本、代码、表格、电子书等无需解析的文件。
    case userData = "user_data"
}

// MARK: - Files API 响应

/// POST /anthropic/v1/files 的响应体。
/// 只声明用得到的字段，且除 `id` 外全部可选：mock 与服务端版本差异不应让上传失败。
public struct UploadedFile: Codable, Sendable, Hashable {
    public let id: String
    public let type: String?
    public let sizeBytes: Int?
    public let createdAt: String?
    public let filename: String?
    public let mimeType: String?

    public init(
        id: String,
        type: String? = "file",
        sizeBytes: Int? = nil,
        createdAt: String? = nil,
        filename: String? = nil,
        mimeType: String? = nil
    ) {
        self.id = id
        self.type = type
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.filename = filename
        self.mimeType = mimeType
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case sizeBytes = "size_bytes"
        case createdAt = "created_at"
        case filename
        case mimeType = "mime_type"
    }
}
