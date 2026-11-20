import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - 平台图片

#if os(macOS)
typealias AttachmentPlatformImage = NSImage
#else
typealias AttachmentPlatformImage = UIImage
#endif

extension Image {
    /// 用平台原生图片构造，避免在视图层到处写 `Image(nsImage:)` / `Image(uiImage:)`。
    init(attachmentImage: AttachmentPlatformImage) {
        #if os(macOS)
        self.init(nsImage: attachmentImage)
        #else
        self.init(uiImage: attachmentImage)
        #endif
    }
}

enum AttachmentImageLoader {
    /// 同步读取本地缩略图。只用于 64pt 缩略图，文件由用户刚选中，读盘成本可接受。
    static func load(path: String?) -> AttachmentPlatformImage? {
        guard let path, !path.isEmpty else { return nil }
        #if os(macOS)
        return NSImage(contentsOfFile: path)
        #else
        return UIImage(contentsOfFile: path)
        #endif
    }
}

// MARK: - 本地缩略图

/// 图片附件缩略图：64×64 等比裁切填充；读不到原件时显示占位图标。
struct LocalImageThumbnail: View {
    let path: String?
    var side: CGFloat = 64

    @State private var image: AttachmentPlatformImage?

    var body: some View {
        ZStack {
            DS.Colors.bgSkeleton
            if let image {
                Image(attachmentImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: side * 0.3, weight: .regular))
                    .foregroundStyle(DS.Colors.labelTertiary)
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .task(id: path) {
            image = AttachmentImageLoader.load(path: path)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 交互辅助

/// macOS 上跟踪鼠标悬停；iOS 没有悬停概念，原样返回。
struct AttachmentHover: ViewModifier {
    @Binding var hovered: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onHover { hovered = $0 }
        #else
        content
        #endif
    }
}

extension View {
    func attachmentHover(_ hovered: Binding<Bool>) -> some View {
        modifier(AttachmentHover(hovered: hovered))
    }

    /// macOS 悬浮提示；iOS 没有对应控件，直接忽略（与 DesignSystem/Atoms.swift 同策略）。
    @ViewBuilder
    func attachmentHelp(_ text: String?) -> some View {
        #if os(macOS)
        if let text, !text.isEmpty {
            help(text)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - 删除按钮

/// 附件右上角的圆形删除按钮；macOS 悬停才显示，失败不可重试时常显红底。
struct AttachmentRemoveButton: View {
    var isVisible: Bool
    var isInvalid: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DS.Colors.labelOnBrand)
                .frame(width: 18, height: 18)
                .background {
                    Circle().fill(isInvalid ? DS.Colors.errorPrimary : Color.black.opacity(0.62))
                }
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(DS.Motion.fastEase, value: isVisible)
        .accessibilityLabel("删除附件")
    }
}

// MARK: - 进度

/// 上传进度环：有确定进度时按比例描边，没有时退回系统的不确定进度指示。
struct AttachmentProgressRing: View {
    var fraction: Double?
    var side: CGFloat = 20
    /// 环与不确定进度的颜色：深色蒙层上用白色，浅色卡片上用次级文字色。
    var color: Color = .white

    var body: some View {
        Group {
            if let fraction {
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.28), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: min(max(fraction, 0.02), 1))
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: side, height: side)
                .animation(DS.Motion.fastEase, value: fraction)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(color)
            }
        }
        .accessibilityLabel("正在上传")
    }
}
