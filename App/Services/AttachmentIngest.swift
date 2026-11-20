import Foundation

/// 附件入口的公共编排：建本地占位 → 上传 → 回填 fileID 或失败态。
/// ChatView 与 WelcomeView 共用，避免两处逻辑漂移。
///
/// 说明：不做逐字节进度回调。进度闭包需要跨 @Sendable 边界捕获 UI 状态，
/// 在 Swift 6 严格并发下容易引入数据竞争；附件条使用「不确定进度」表现。
@MainActor
enum AttachmentIngest {
    static func ingest(
        _ urls: [URL],
        settings: AppSettings,
        uploader: FileUploader,
        add: @escaping (FileAttachment) -> Void,
        update: @escaping (FileAttachment) -> Void
    ) {
        for url in urls {
            let pending = FileAttachment(fileURL: url)
            add(pending)

            guard settings.hasAPIKey, let origin = URL(string: settings.effectiveOrigin) else {
                update(pending.failed(message: "请先在设置里填写 API Key", retryable: true))
                continue
            }

            Task {
                do {
                    let done = try await uploader.upload(
                        fileURL: url,
                        apiKey: settings.apiKey,
                        origin: origin,
                        id: pending.id
                    )
                    await MainActor.run { update(done) }
                } catch let error as FileUploadError {
                    await MainActor.run {
                        update(pending.failed(message: error.userMessage, retryable: error.isRetryable))
                    }
                } catch {
                    await MainActor.run {
                        update(pending.failed(message: error.localizedDescription, retryable: true))
                    }
                }
            }
        }
    }
}
