import SwiftUI

#if os(macOS)
import AppKit
#endif

// MARK: - 跨平台 Hover
//
// macOS 用 onHover 驱动 hover 态；iOS/iPadOS 是触摸优先，按设计规范不做 hover
// （iPad 指针只影响光标形状，不影响配色），因此这里显式 no-op，避免各组件里
// 反复写 #if os(macOS)。
//
// 约定：
//   · hover 只改「背景/前景色」，不改尺寸，避免鼠标划过时布局抖动；
//   · 光标形状（NSCursor）只给可点元素用，且必须成对 push/pop。

extension View {

    /// 跨平台 hover 回调。macOS 触发，iOS/iPadOS 永远不触发。
    ///
    /// - Parameter onChange: `true` 进入、`false` 离开。回调在主线程执行。
    public func dsHoverable(_ onChange: @escaping (Bool) -> Void) -> some View {
        modifier(DSHoverModifier(onChange: onChange))
    }

    /// macOS 上把光标改成「手型」，提示可点击。iOS/iPadOS 无操作。
    ///
    /// 注意：push/pop 成对出现；视图在 hover 期间被移除时系统会在下一个 hover
    /// 周期自行回收，这里不做额外补偿，保持实现简单。
    public func dsPointerCursor() -> some View {
        modifier(DSPointerCursorModifier())
    }
}

// MARK: - 实现

private struct DSHoverModifier: ViewModifier {

    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onHover { isInside in
            onChange(isInside)
        }
        #else
        content
        #endif
    }
}

private struct DSPointerCursorModifier: ViewModifier {

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onHover { isInside in
            if isInside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        #else
        content
        #endif
    }
}

// MARK: - Preview

private struct DSHoverProbe: View {

    @State private var isHovering = false

    var body: some View {
        Text(isHovering ? "hovering" : "idle")
            .font(DS.Typography.bodyMedium)
            .foregroundStyle(DS.Colors.labelPrimary)
            .frame(width: 160, height: DS.Size.controlL)
            .background(isHovering ? DS.Colors.interactiveHover : DS.Colors.bgLayer2)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .dsHoverable { isHovering = $0 }
            .dsPointerCursor()
            .padding(DS.Spacing.xxxl)
    }
}

#Preview("Hoverable") {
    DSHoverProbe()
}
