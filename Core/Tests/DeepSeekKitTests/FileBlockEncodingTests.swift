import Foundation
import XCTest
@testable import DeepSeekKit

/// 附件：user 消息里的 image / document 块编码、hasFiles 与 beta 请求头。
///
/// 协议要点（Reference/chat-demo/src/services/chat/reply.ts `toUserParam`）：
/// - 有文件时 content 变成数组，**先文件后文本**；
/// - 图片 `{"type":"image","source":{"type":"file","file_id":"..."}}`，其余为 `document`；
/// - 通过 file_id 引用文件时请求头必须带 `anthropic-beta: files-api-2025-04-14`。
final class FileBlockEncodingTests: XCTestCase {

    private final class RequestRecorder {
        var requests: [URLRequest] = []
    }

    // MARK: 构造

    private func attachment(
        id: String = "local-1",
        fileID: String? = "file-api-abc123",
        filename: String,
        mimeType: String,
        byteSize: Int = 1024
    ) -> FileAttachment {
        FileAttachment(
            id: id,
            fileID: fileID,
            filename: filename,
            mimeType: mimeType,
            byteSize: byteSize,
            localPath: "/tmp/\(filename)",
            state: fileID == nil ? .uploading : .ready
        )
    }

    private func userJSON(_ blocks: [Block]) throws -> [String: Any] {
        try encodeObject(RequestMessage(role: .user, blocks: blocks))
    }

    private func contentBlocks(_ blocks: [Block]) throws -> [[String: Any]] {
        let json = try userJSON(blocks)
        return try XCTUnwrap(json["content"] as? [[String: Any]])
    }

    private func drain(_ client: DeepSeekClient, _ request: ChatRequest) async throws {
        for try await _ in client.stream(request) {}
    }

    // MARK: 文件块形状

    func testImageAttachmentEncodesImageBlockBeforeText() throws {
        let blocks = [
            Block(id: "u0", kind: .text, text: "看这张图"),
            Block(id: "f0", kind: .file, attachment: attachment(filename: "chart.png", mimeType: "image/png")),
        ]
        let content = try contentBlocks(blocks)

        XCTAssertEqual(content.count, 2)
        // 先文件后文本
        let file = content[0]
        XCTAssertEqual(file["type"] as? String, "image")
        XCTAssertEqual(Set(file.keys), ["type", "source"])
        let source = try XCTUnwrap(file["source"] as? [String: Any])
        XCTAssertEqual(Set(source.keys), ["type", "file_id"])
        XCTAssertEqual(source["type"] as? String, "file")
        XCTAssertEqual(source["file_id"] as? String, "file-api-abc123")

        let text = content[1]
        XCTAssertEqual(text["type"] as? String, "text")
        XCTAssertEqual(text["text"] as? String, "看这张图")
    }

    func testPDFAttachmentEncodesDocumentBlock() throws {
        let blocks = [
            Block(id: "u0", kind: .text, text: "总结一下"),
            Block(
                id: "f0",
                kind: .file,
                attachment: attachment(filename: "论文.pdf", mimeType: "application/pdf")
            ),
        ]
        let content = try contentBlocks(blocks)

        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "document")
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "file")
        XCTAssertEqual(source["file_id"] as? String, "file-api-abc123")
    }

    func testAttachmentWithoutFileIDFallsBackToPlainString() throws {
        let blocks = [
            Block(id: "u0", kind: .text, text: "还没上传完"),
            Block(
                id: "f0",
                kind: .file,
                attachment: attachment(fileID: nil, filename: "a.pdf", mimeType: "application/pdf")
            ),
        ]
        let json = try userJSON(blocks)
        XCTAssertEqual(json["content"] as? String, "还没上传完")
    }

    func testEmptyTextWithFileOmitsTextBlock() throws {
        let blocks = [
            Block(id: "f0", kind: .file, attachment: attachment(filename: "b.docx", mimeType: "application/msword")),
        ]
        let content = try contentBlocks(blocks)
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "document")
    }

    func testMultipleAttachmentsKeepDeclarationOrder() throws {
        let blocks = [
            Block(id: "u0", kind: .text, text: "两个文件"),
            Block(id: "f0", kind: .file, attachment: attachment(id: "a", fileID: "file-api-a",
                                                                filename: "a.png", mimeType: "image/png")),
            Block(id: "f1", kind: .file, attachment: attachment(id: "b", fileID: "file-api-b",
                                                                filename: "b.pdf", mimeType: "application/pdf")),
        ]
        let content = try contentBlocks(blocks)
        XCTAssertEqual(content.count, 3)
        XCTAssertEqual(content[0]["type"] as? String, "image")
        XCTAssertEqual(content[1]["type"] as? String, "document")
        XCTAssertEqual(content[2]["type"] as? String, "text")
    }

    // MARK: purpose / 上限

    func testUploadPurposeFollowsExtension() {
        XCTAssertNil(attachment(filename: "a.png", mimeType: "image/png").uploadPurpose)
        XCTAssertEqual(attachment(filename: "a.pdf", mimeType: "application/pdf").uploadPurpose,
                       .richLayoutRecognition)
        XCTAssertEqual(attachment(filename: "a.doc", mimeType: "application/msword").uploadPurpose,
                       .richLayoutRecognition)
        XCTAssertEqual(attachment(filename: "a.pptx", mimeType: "").uploadPurpose,
                       .richLayoutRecognition)
        XCTAssertEqual(attachment(filename: "notes.txt", mimeType: "text/plain").uploadPurpose,
                       .userData)
        XCTAssertEqual(attachment(filename: "data.csv", mimeType: "text/csv").uploadPurpose,
                       .userData)
        // 大写扩展名同样识别
        XCTAssertEqual(attachment(filename: "REPORT.PDF", mimeType: "").uploadPurpose,
                       .richLayoutRecognition)
    }

    func testMaxSizeDependsOnPurpose() {
        XCTAssertEqual(attachment(filename: "a.txt", mimeType: "text/plain").maxSizeBytes,
                       FileAttachment.userDataMaxSizeBytes)
        XCTAssertEqual(attachment(filename: "a.pdf", mimeType: "application/pdf").maxSizeBytes,
                       FileAttachment.maxSizeBytes)
        XCTAssertEqual(attachment(filename: "a.png", mimeType: "image/png").maxSizeBytes,
                       FileAttachment.maxSizeBytes)
    }

    func testMimeFallbackFromExtension() {
        let png = attachment(filename: "photo.PNG", mimeType: "")
        XCTAssertEqual(png.resolvedMimeType, "image/png")
        XCTAssertTrue(png.isImage)
        XCTAssertEqual(png.displayExtension, "PNG")
    }

    // MARK: hasFiles

    func testHasFilesOnlyCountsUploadedAttachments() throws {
        let ready = RequestMessage(role: .user, blocks: [
            Block(id: "f0", kind: .file, attachment: attachment(filename: "a.png", mimeType: "image/png")),
        ])
        XCTAssertTrue(ready.hasFiles)

        let pending = RequestMessage(role: .user, blocks: [
            Block(id: "f0", kind: .file,
                  attachment: attachment(fileID: nil, filename: "a.png", mimeType: "image/png")),
        ])
        XCTAssertFalse(pending.hasFiles)

        XCTAssertFalse(RequestMessage(role: .user, text: "纯文本").hasFiles)
    }

    func testChatRequestHasFilesAggregatesMessages() {
        let withFile = ChatRequest(system: "s", messages: [
            RequestMessage(role: .user, text: "问题"),
            RequestMessage(role: .user, blocks: [
                Block(id: "f0", kind: .file,
                      attachment: attachment(filename: "a.pdf", mimeType: "application/pdf")),
            ]),
        ])
        XCTAssertTrue(withFile.hasFiles)

        let plain = ChatRequest(system: "s", messages: [RequestMessage(role: .user, text: "问题")])
        XCTAssertFalse(plain.hasFiles)
    }

    // MARK: beta 请求头

    func testStreamSendsFilesBetaHeaderWhenAttachmentPresent() async throws {
        let recorder = RequestRecorder()
        let client = TestHTTP.client { request in
            recorder.requests.append(request)
            return (
                TestHTTP.response(200, contentType: "text/event-stream; charset=utf-8"),
                TestHTTP.sse([("message_stop", Samples.messageStop)])
            )
        }
        let request = ChatRequest(system: "s", messages: [
            RequestMessage(role: .user, blocks: [
                Block(id: "u0", kind: .text, text: "看图"),
                Block(id: "f0", kind: .file,
                      attachment: attachment(filename: "a.png", mimeType: "image/png")),
            ]),
        ])

        try await drain(client, request)

        let sent = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "anthropic-beta"), "files-api-2025-04-14")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-api-key"), "test-key")

        let body = try XCTUnwrap(bodyData(sent))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "image")
    }

    func testStreamOmitsFilesBetaHeaderWithoutAttachment() async throws {
        let recorder = RequestRecorder()
        let client = TestHTTP.client { request in
            recorder.requests.append(request)
            return (
                TestHTTP.response(200, contentType: "text/event-stream; charset=utf-8"),
                TestHTTP.sse([("message_stop", Samples.messageStop)])
            )
        }

        try await drain(client, ChatRequest(system: "s", messages: [
            RequestMessage(role: .user, text: "纯文本"),
        ]))

        let sent = try XCTUnwrap(recorder.requests.first)
        XCTAssertNil(sent.value(forHTTPHeaderField: "anthropic-beta"))
    }

    // MARK: 向后兼容

    func testPlainTextAndDerivedPropertiesIgnoreFileBlocks() {
        let message = ChatMessage(
            id: "m1",
            role: .user,
            blocks: [
                Block(id: "f0", kind: .file,
                      attachment: attachment(filename: "a.pdf", mimeType: "application/pdf")),
                Block(id: "t0", kind: .text, text: "正文"),
            ],
            status: .complete
        )
        XCTAssertEqual(message.plainText, "正文")
        XCTAssertEqual(message.thinkingText, "")
        XCTAssertTrue(message.sources.isEmpty)
    }

    func testLegacyBlockJSONDecodesWithoutAttachment() throws {
        let legacy = """
        {"id":"b0","kind":"text","text":"旧数据","citations":[],"searchResults":[],"failed":false}
        """
        let block = try JSONDecoder().decode(Block.self, from: Data(legacy.utf8))
        XCTAssertNil(block.attachment)
        XCTAssertEqual(block.text, "旧数据")
    }

    func testBlockWithAttachmentRoundTrips() throws {
        let block = Block(
            id: "f0",
            kind: .file,
            attachment: attachment(id: "local-9", filename: "a.pdf", mimeType: "application/pdf", byteSize: 2048)
        )
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(Block.self, from: data)
        XCTAssertEqual(decoded, block)
        XCTAssertEqual(decoded.attachment?.state, .ready)
        XCTAssertEqual(decoded.attachment?.byteSize, 2048)
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
}
