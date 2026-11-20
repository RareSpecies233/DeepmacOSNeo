import SwiftUI

// MARK: - 图片附件

/// 图片附件缩略图：64 × 64、圆角 16（对齐 Reference `.attachment`）。
/// 上传中盖半透明蒙层 + 进度环；失败盖更深的蒙层，可重试时整块可点。
struct ImageAttachmentView: View {
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
        LocalImageThumbnail(path: attachment.localPath, side: 64)
            .overlay { stateOverlay }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isFailed ? DS.Colors.errorPrimary : DS.Colors.borderL2, lineWidth: 1)
            }
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
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .attachmentHover($hovered)
            .attachmentHelp(tooltip)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(attachment.filename)，\(accessibilityState)")
    }

    // MARK: 状态蒙层

    @ViewBuilder
    private var stateOverlay: some View {
        switch attachment.state {
        case .uploading:
            ZStack {
                Color.black.opacity(0.30)
                AttachmentProgressRing(fraction: progress, side: 20)
            }

        case .failed where attachment.isRetryable:
            Button {
                onRetry?()
            } label: {
                ZStack {
                    Color.black.opacity(0.48)
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .regular))
                        // 具体原因写在图标下方；只放得下两行短句
                        if let reason, reason != "上传失败" {
                            Text(reason)
                                .font(.system(size: 9))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(DS.Colors.labelOnBrand)
                    .padding(.horizontal, 3)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重试上传 \(attachment.filename)")

        case .failed:
            VStack {
                Spacer(minLength: 0)
                Text(reason ?? "上传失败")
                    .font(.system(size: 9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.Colors.labelOnBrand)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.24))

        case .ready:
            EmptyView()
        }
    }

    // MARK: 文案

    private var reason: String? { attachment.errorText }

    private var tooltip: String? {
        switch attachment.state {
        case .failed: return reason ?? "上传失败"
        default: return attachment.filename
        }
    }

    private var accessibilityState: String {
        switch attachment.state {
        case .uploading: return "正在上传"
        case .failed: return reason ?? "上传失败"
        case .ready: return "已上传"
        }
    }
}
