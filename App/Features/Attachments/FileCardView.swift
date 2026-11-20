import SwiftUI

// MARK: - 文件卡片

/// 文档附件卡片：图标 + 文件名 + 「扩展名 大小」或上传状态。
/// 尺寸对齐 Reference `.card`：240 × 64、圆角 16、左侧 14 内边距。
/// 失败时描边与副标题转红；可重试时整卡可点，不可重试时删除按钮常显。
struct FileCardView: View {
    let attachment: FileAttachment
    /// 0...1；nil 表示不确定进度。
    var progress: Double?
    var onRemove: (() -> Void)?
    var onRetry: (() -> Void)?

    @State private var hovered = false

    private var isFailed: Bool { attachment.state == .failed }
    private var canRetry: Bool { isFailed && attachment.isRetryable }
    private var showsRemove: Bool {
        #if os(macOS)
        return hovered || (isFailed && !canRetry)
        #else
        return true
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            icon
                .frame(width: 28, height: 28)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.filename)
                    .font(DS.Typography.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(DS.Colors.labelPrimary)

                Text(subtitle)
                    .font(DS.Typography.caption)
                    .lineLimit(1)
                    .foregroundStyle(isFailed ? DS.Colors.errorPrimary : DS.Colors.labelTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(width: 240, alignment: .leading)
        .frame(minHeight: 64)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hovered && canRetry ? DS.Colors.interactiveHover : DS.Colors.inputFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isFailed ? DS.Colors.errorPrimary : DS.Colors.borderL2, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if canRetry { onRetry?() }
        }
        .attachmentHover($hovered)
        .attachmentHelp(tooltip)
        .overlay(alignment: .topTrailing) {
            if let onRemove {
                AttachmentRemoveButton(
                    isVisible: showsRemove,
                    isInvalid: isFailed && !canRetry,
                    action: onRemove
                )
                .padding(4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(attachment.filename)，\(subtitle)")
    }

    // MARK: 图标

    @ViewBuilder
    private var icon: some View {
        switch attachment.state {
        case .uploading:
            AttachmentProgressRing(
                fraction: progress,
                side: 18,
                color: DS.Colors.labelTertiary
            )
        case .failed where attachment.isRetryable:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(DS.Colors.labelSecondary)
        case .failed, .ready:
            FileIconView(kind: FileIconKind(fileExtension: attachment.displayExtension))
        }
    }

    // MARK: 文案

    private var subtitle: String {
        switch attachment.state {
        case .uploading:
            if let progress, progress > 0.01, progress < 0.995 {
                return "上传中 \(Int(progress * 100))%"
            }
            return "上传中…"
        case .failed:
            return attachment.errorText ?? "上传失败"
        case .ready:
            return attachment.sizeDescription
        }
    }

    private var tooltip: String? {
        switch attachment.state {
        case .failed:
            return canRetry ? "重试上传：\(attachment.filename)" : attachment.errorText
        case .ready, .uploading:
            return attachment.filename
        }
    }
}
