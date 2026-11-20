import SwiftUI

// MARK: - 设置面板的局部玻璃容器
//
// 面板外壳用原生 Liquid Glass（`.glassEffect`）。系统开启「降低透明度」时
// 退化为 `.ultraThinMaterial`，与「玻璃外壳、内部实色」的可读性策略一致。
// 这个 helper 只属于设置目录，不依赖 DesignSystem 里并行开发的 Atoms / Glass。

struct SettingsGlassSurface: ViewModifier {
    let shape: AnyShape
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init<S: Shape>(_ shape: S) {
        self.shape = AnyShape(shape)
    }

    init(cornerRadius: CGFloat) {
        self.init(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background { shape.fill(.ultraThinMaterial) }
                .overlay { shape.stroke(DS.Colors.borderL2, lineWidth: 0.5) }
        } else {
            content
                .glassEffect(.regular, in: shape)
                .overlay { shape.stroke(DS.Colors.borderL3.opacity(0.55), lineWidth: 0.5) }
        }
    }
}

extension View {
    /// 居中弹窗形态：四角统一圆角
    func settingsGlassSurface(cornerRadius: CGFloat) -> some View {
        modifier(SettingsGlassSurface(cornerRadius: cornerRadius))
    }

    /// 底部 sheet 形态：只圆上两角
    func settingsGlassSheetSurface(cornerRadius: CGFloat) -> some View {
        modifier(
            SettingsGlassSurface(
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    topTrailingRadius: cornerRadius,
                    style: .continuous
                )
            )
        )
    }
}

// MARK: - 设置面板用到的补充色
//
// Tokens 里只有 error 状态色，没有 success，这里补一个设置面板专用的成功色。
enum SettingsPalette {
    static let success = dyn(0x0E8A4B, 0x4ADE80)
    static let dangerFill = dynAlpha(0xEC1313, 0.08, 0xF25A5A, 0.16)
}
