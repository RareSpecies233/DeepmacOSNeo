import SwiftUI

// MARK: - 玻璃外壳工具（Liquid Glass）
//
// ┌─────────────────────────── 用法约束（务必遵守）───────────────────────────┐
// │ 1. 玻璃只用于「外壳层」：侧栏、输入框容器、工具栏、弹窗、浮动按钮。          │
// │    内容层（消息正文、代码块、表格、链接、引用）保持扁平，禁止套 dsGlass。    │
// │ 2. 玻璃无法采样玻璃（glass cannot sample glass）：                              │
// │    - 不要把一块玻璃直接叠在另一块玻璃上再指望它拿到背景内容；                │
// │    - 需要「嵌套」视觉时，外层用玻璃、内层用实色/半透明实色（DS 令牌）代替；  │
// │    - 同组玻璃必须放在同一个 DSGlassCluster 内，跨容器无法合并/形变。         │
// │ 3. 需要在同一个 DSGlassCluster 内做 morph（合并/拆分）时，                    │
// │    子元素必须同时拥有 `dsGlass(...)` 与 `dsGlassID(_, in:)`（同一个 Namespace）。│
// │ 4. 无障碍降级是自动的：Reduce Transparency → ultraThinMaterial + 细描边；     │
// │    Reduce Motion → 不注册 glassEffectID，因此不会发生 morph 动画。            │
// └──────────────────────────────────────────────────────────────────────────┘
//
// 原生 API：SwiftUI `View.glassEffect(_:in:)`、`GlassEffectContainer(spacing:)`
// 系统版本：iOS 26 / macOS 26（deployment target 已锁定 26.0，无需 @available 分支）

public enum DSGlass {

    /// 组装玻璃取值：`Glass.regular` →（可选 `.tint`）→（可选 `.interactive`）。
    ///
    /// 组合顺序遵循官方推荐 `Glass.regular.tint(x).interactive()`：
    /// tint 先着色、interactive 再打开交互反馈（hover/press 的形变与高光）。
    public static func make(interactive: Bool = false, tint: Color? = nil) -> Glass {
        var glass: Glass = .regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

// MARK: - 圆角玻璃

extension View {

    /// 给外壳层套一层 Liquid Glass（圆角矩形）。
    ///
    /// - Parameters:
    ///   - cornerRadius: 圆角，默认 `DS.Radius.card`；输入框用 `DS.Radius.composer`，胶囊用 `DS.Radius.pill`。
    ///   - interactive: 是否响应交互（hover/press 的形变与高光）。只给真正可点的玻璃控件打开。
    ///   - tint: 着色。选中态/强调态传 `DS.Colors.brandPrimary` 之类的品牌色；nil 表示系统默认。
    ///
    /// 注意：本方法只负责「玻璃本体」，不提供内边距与尺寸，布局由调用方决定。
    /// 玻璃无法采样玻璃——不要在已经 dsGlass 的视图内部再套一块玻璃。
    public func dsGlass(cornerRadius: CGFloat = DS.Radius.card,
                        interactive: Bool = false,
                        tint: Color? = nil) -> some View {
        modifier(DSGlassModifier(cornerRadius: cornerRadius,
                                 interactive: interactive,
                                 tint: tint))
    }

    /// 任意形状的玻璃（`Capsule()`、`Circle()` 等）。
    ///
    /// 与 `dsGlass(cornerRadius:)` 等价，只是把形状交给调用方，用于胶囊开关 / 圆形发送键。
    public func dsGlass<S: Shape>(in shape: S,
                                  interactive: Bool = false,
                                  tint: Color? = nil) -> some View {
        modifier(DSGlassShapeModifier(shape: shape,
                                      interactive: interactive,
                                      tint: tint))
    }
}

// MARK: - 玻璃 modifier 实现

/// 圆角玻璃：Reduce Transparency 降级为 ultraThinMaterial + 细描边。
private struct DSGlassModifier: ViewModifier {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            // 降级：不透明偏好下玻璃的折射会干扰可读性。
            // 有 tint 时说明调用方依赖这层色块承载对比度（例如品牌色胶囊 + 白字），
            // 此时降级为实色填充；无 tint 时才退到系统材质 + 1pt 描边。
            if let tint {
                content.background(tint, in: shape)
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .overlay {
                        shape.strokeBorder(DS.Colors.borderL2,
                                           lineWidth: DS.Components.hairline)
                    }
            }
        } else {
            content.glassEffect(DSGlass.make(interactive: interactive, tint: tint), in: shape)
        }
    }
}

/// 任意形状玻璃：同上，只是形状泛型化。
private struct DSGlassShapeModifier<S: Shape>: ViewModifier {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        if reduceTransparency {
            // 与圆角版本一致：有色 tint 降级为实色，保证白字对比度。
            if let tint {
                content.background(tint, in: shape)
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .overlay {
                        shape.stroke(DS.Colors.borderL2, lineWidth: DS.Components.hairline)
                    }
            }
        } else {
            content.glassEffect(DSGlass.make(interactive: interactive, tint: tint), in: shape)
        }
    }
}

// MARK: - 玻璃容器

/// 同组玻璃的容器：**所有需要互相采样/合并/morph 的玻璃必须放在同一个簇里**。
///
/// 内部即 `GlassEffectContainer(spacing:)`。`spacing` 是「两块玻璃靠近到多少距离时
/// 开始融合」的阈值，不是布局间距——布局间距请继续用 `HStack(spacing:)` / `DS.Spacing.*`。
///
/// 降级：Reduce Transparency 时直接透传内容（不创建玻璃容器，因为没有玻璃可融合），
/// 子元素各自的 `dsGlass` 会同步降级为材质。
public struct DSGlassCluster<Content: View>: View {

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let spacing: CGFloat
    private let content: Content

    /// - Parameters:
    ///   - spacing: 融合阈值，默认 `DS.Spacing.s`（8pt）。紧贴的按钮组建议 8–12，松散排列建议 16+。
    ///   - content: 簇内玻璃元素；需要 morph 的成员请再加 `dsGlassID(_, in:)`。
    public init(spacing: CGFloat = DS.Spacing.s,
                @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if reduceTransparency {
            content
        } else {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - morph 标识

extension View {

    /// 给玻璃元素打 morph 标识：同一 Namespace 内 id 变化时，玻璃会按 id 做合并/拆分形变。
    ///
    /// 必须与 `dsGlass(...)` 搭配，且父级是 `DSGlassCluster`（或原生 GlassEffectContainer），
    /// 否则 morph 不生效。Reduce Motion 为 true 时不注册 id，因此不会有形变动画，
    /// 元素的出现/消失退化为普通过渡。
    public func dsGlassID<ID: Hashable & Sendable>(_ id: ID,
                                                  in namespace: Namespace.ID) -> some View {
        modifier(DSGlassIDModifier(id: id, namespace: namespace))
    }
}

private struct DSGlassIDModifier<ID: Hashable & Sendable>: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let id: ID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.glassEffectID(id, in: namespace)
        }
    }
}

// MARK: - Preview

#Preview("玻璃 / 降级") {
    VStack(spacing: DS.Spacing.xl) {
        DSGlassCluster(spacing: DS.Spacing.m) {
            HStack(spacing: DS.Spacing.m) {
                Text("侧栏")
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.vertical, DS.Spacing.m)
                    .dsGlass(cornerRadius: DS.Radius.card, interactive: true)

                Text("工具栏")
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.vertical, DS.Spacing.m)
                    .dsGlass(cornerRadius: DS.Radius.card, interactive: true, tint: DS.Colors.brandPrimary)
            }
        }

        Text("输入框（composer 圆角）")
            .font(DS.Typography.body)
            .foregroundStyle(DS.Colors.labelSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.l)
            .dsGlass(cornerRadius: DS.Radius.composer, interactive: true)

        Capsule()
            .fill(.clear)
            .frame(width: DS.Size.controlXL, height: DS.Size.controlS)
            .dsGlass(in: Capsule(), interactive: true, tint: DS.Colors.brandPrimary)
    }
    .padding(DS.Spacing.xxxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DS.Colors.bgBase)
}
