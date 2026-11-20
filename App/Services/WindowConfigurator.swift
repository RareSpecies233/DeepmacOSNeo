import SwiftUI

#if os(macOS)
import AppKit

/// macOS：把窗口设为非不透明，让 Liquid Glass 能采样到桌面与窗口后方内容。
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // 不透明窗口：避免侧栏与内容之间透出桌面，造成"没拼接上"的缝隙
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.hasShadow = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#else
struct WindowConfigurator: View {
    var body: some View { Color.clear }
}
#endif

extension View {
    func configureWindowForGlass() -> some View {
        #if os(macOS)
        background(WindowConfigurator().frame(width: 0, height: 0))
        #else
        self
        #endif
    }
}
