import SwiftUI

#if os(macOS)
import AppKit

/// macOS 原生侧栏材质（Finder / Mail 同款）：窗口透明时对后方内容做模糊 + 去饱和，
/// 比裸玻璃更适合长时间阅读，且自动跟随深浅色与窗口激活态。
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
#else
struct VisualEffectBackground: View {
    var material: Never? = nil
    var blending: Never? = nil
    var body: some View { Color.clear }
}
#endif
