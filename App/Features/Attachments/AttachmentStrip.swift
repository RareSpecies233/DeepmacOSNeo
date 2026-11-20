import SwiftUI

// MARK: - 附件条

/// 输入框上方的附件条：图片显示缩略图，其余显示文件卡片。
///
/// 尺寸对齐 Reference `.attachments` / `.attachment`：单项 64pt 高、圆角 16、间距 10、
/// 顶部与左右各 12 内边距；横向滚动，不换行挤压输入框。
///
/// 用法（Composer 接线）：
/// ```swift
/// AttachmentStrip(items: attachments) { id in       // onRemove
///     attachments.removeAll { $0.id == id }
/// } onRetry: { id in                                // onRetry
///     Task { await uploader.retry(id) }
/// }
/// ```
struct AttachmentStrip: View {
    let items: [FileAttachment]
    /// 删除：按本地 id 回调。
    let onRemove: (String) -> Void
    /// 重试上传：按本地 id 回调；不可重试的失败项不会触发。
    let onRetry: (String) -> Void
    /// 上传进度：key 是附件本地 id，value 0...1；缺失时显示不确定进度。
    let progress: [String: Double]

    init(
        items: [FileAttachment],
        onRemove: @escaping (String) -> Void,
        onRetry: @escaping (String) -> Void,
        progress: [String: Double] = [:]
    ) {
        self.items = items
        self.onRemove = onRemove
        self.onRetry = onRetry
        self.progress = progress
    }

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(items) { item in
                        row(for: item)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
            }
            .frame(height: 76)
            .animation(DS.Motion.fastEase, value: items.map(\.id))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("附件 \(items.count) 个")
        }
    }

    @ViewBuilder
    private func row(for item: FileAttachment) -> some View {
        if item.isImage {
            ImageAttachmentView(
                attachment: item,
                progress: progress[item.id],
                onRemove: { onRemove(item.id) },
                onRetry: { onRetry(item.id) }
            )
        } else {
            FileCardView(
                attachment: item,
                progress: progress[item.id],
                onRemove: { onRemove(item.id) },
                onRetry: { onRetry(item.id) }
            )
        }
    }
}
