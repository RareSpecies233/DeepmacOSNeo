import SwiftUI

#if os(macOS)
import AppKit

/// macOS 隐藏标题栏后，用一小块透明视图承载窗口拖拽
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
#else
struct WindowDragHandle: View {
    var body: some View { Color.clear }
}
#endif

extension View {
    /// 让某个区域可拖动窗口（仅 macOS 生效）
    func windowDragArea() -> some View {
        #if os(macOS)
        // 必须是 background：overlay 会盖在内容上，把「收起边栏」等按钮的点击全部吞掉。
        background(WindowDragHandle())
        #else
        self
        #endif
    }
}
