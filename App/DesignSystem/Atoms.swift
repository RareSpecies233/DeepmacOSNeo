import SwiftUI

// MARK: - 组件级派生令牌
//
// Tokens.swift 是共享契约，这里只做「追加」，不改动、不重命名任何既有成员。
// 这些值全部有出处：要么来自 Reference/chat-demo 的 CSS 令牌，要么来自 HIG 硬性下限。
// 组件文件里不再出现裸数字，避免魔法数字扩散。

public extension DS {

    /// 组件派生尺寸/透明度（来源于 Reference 的 --dsw-alias-* / 控件 CSS）
    enum Components {

        /// 行内开关胶囊高度：参考 `.toggle { height: 34px }`
        static let pillHeight: CGFloat = 34

        /// 1pt 描边（玻璃降级时的边界线、分隔线）
        static let hairline: CGFloat = 1

        /// HIG 最小可点击区域（移动端 44pt）
        static let minTapTarget: CGFloat = 44

        /// 禁用态透明度：参考 `:disabled { opacity: 0.4 }`
        static let disabledOpacity: Double = 0.4

        /// 按下态缩放，给触感反馈但不动布局
        static let pressedScale: CGFloat = 0.97

        /// 打字点直径：参考 `.dotInner { width: 5px; height: 5px }`
        static let typingDot: CGFloat = 5

        /// 打字点动画的两端不透明度（静止态 / 收起态）
        static let typingDotDimOpacity: Double = 0.35
        /// 打字点在 Reduce Motion 下的静止不透明度（保持可见，不做脉冲）
        static let typingDotStillOpacity: Double = 0.75
    }
}

public extension DS.Colors {

    /// --dsw-alias-button-primary-hover
    /// 浅色 = blue-450，深色 = blue-500（正好是 brandPrimary 的明暗互换）
    static let buttonPrimaryHover = dyn(0x5686FE, 0x3964FE)

    /// --dsw-alias-button-ghost-active-fill（浅 blue-50 / 深 blue-900）
    static let buttonGhostActiveFill = dyn(0xEDF3FE, 0x283142)

    /// --dsw-alias-button-ghost-active-hover（浅 blue-100 / 深 blue-800）
    static let buttonGhostActiveHover = dyn(0xE4EDFD, 0x34415B)

    /// --dsw-alias-button-ghost-active-border（浅 blue-300 / 深 blue-600）
    static let buttonGhostActiveBorder = dyn(0xB7C8FE, 0x4868B2)
}

// MARK: - 通用小工具

extension View {

    /// 移动端把命中区域抬到 HIG 下限 44pt；桌面端原样返回（桌面控件更紧凑）。
    /// 视觉尺寸不变，只放大可点区域。
    @ViewBuilder
    func dsMinTapTarget() -> some View {
        #if os(iOS)
        self.frame(minWidth: DS.Components.minTapTarget,
                   minHeight: DS.Components.minTapTarget)
        #else
        self
        #endif
    }
}

/// macOS 悬浮提示；iOS 无对应控件，直接忽略。
private struct DSHelpModifier: ViewModifier {

    let text: String?

    func body(content: Content) -> some View {
        #if os(macOS)
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// 可复用的「hover 底色 + 按下底色」按钮样式。
///
/// 用来统一 DSIconButton / DSGhostButton 的交互反馈：
/// hover 只换底色不换尺寸，按下再加深一级，避免鼠标划过时布局抖动。
struct DSHoverFillButtonStyle: ButtonStyle {

    var cornerRadius: CGFloat
    var restingFill: Color
    var hoverFill: Color
    var pressedFill: Color
    var isHovering: Bool
    var animated: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fill: Color = configuration.isPressed
            ? pressedFill
            : (isHovering ? hoverFill : restingFill)
        return configuration.label
            .background(fill, in: shape)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && animated ? DS.Components.pressedScale : 1)
            .animation(animated ? DS.Motion.fastEase : nil, value: configuration.isPressed)
            .animation(animated ? DS.Motion.fastEase : nil, value: isHovering)
    }
}

/// 只做按压缩放/回弹的样式（给自带背景的控件，如 GlassPill）。
struct DSPressScaleStyle: ButtonStyle {

    var animated: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && animated ? DS.Components.pressedScale : 1)
            .animation(animated ? DS.Motion.fastEase : nil, value: configuration.isPressed)
    }
}

// MARK: - DSIconButton

/// SF Symbol 图标按钮（外壳层：侧栏、消息操作条、工具栏）。
///
/// - 尺寸：xs / s / m / l 分别对应 DS.Size.controlXS(28) / controlS(32) / controlM(36) / controlL(40)
/// - hover：仅 macOS，通过 `dsHoverable` 注入，底色 DS.Colors.interactiveHover
/// - pressed：按下换 DS.Colors.interactiveActive 并轻微缩放
/// - disabled：整体降到 DS.Components.disabledOpacity
/// - tooltip：macOS 用 `.help()`；同时作为无障碍标签
public struct DSIconButton: View {

    public enum Size: Sendable {
        case xs, s, m, l

        /// 控件边长
        var dimension: CGFloat {
            switch self {
            case .xs: DS.Size.controlXS
            case .s:  DS.Size.controlS
            case .m:  DS.Size.controlM
            case .l:  DS.Size.controlL
            }
        }

        /// 图标（SF Symbol）字号
        var iconSize: CGFloat {
            switch self {
            case .xs, .s: DS.Size.iconS
            case .m:      DS.Size.iconM
            case .l:      DS.Size.iconL
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .xs, .s: DS.Radius.s
            case .m:      DS.Radius.m
            case .l:      DS.Radius.m
            }
        }
    }

    private let systemImage: String
    private let label: String
    private let size: Size
    private let tint: Color
    private let hoverTint: Color
    private let isDisabled: Bool
    private let tooltip: String?
    private let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    public init(_ systemImage: String,
                label: String,
                size: Size = .m,
                tint: Color = DS.Colors.labelSecondary,
                hoverTint: Color = DS.Colors.labelPrimary,
                isDisabled: Bool = false,
                tooltip: String? = nil,
                action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.size = size
        self.tint = tint
        self.hoverTint = hoverTint
        self.isDisabled = isDisabled
        self.tooltip = tooltip
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size.iconSize, weight: .regular))
                .foregroundStyle(isHovering && !isDisabled ? hoverTint : tint)
                .frame(width: size.dimension, height: size.dimension)
        }
        .buttonStyle(DSHoverFillButtonStyle(cornerRadius: size.cornerRadius,
                                            restingFill: .clear,
                                            hoverFill: DS.Colors.interactiveHover,
                                            pressedFill: DS.Colors.interactiveActive,
                                            isHovering: isHovering,
                                            animated: !reduceMotion))
        .disabled(isDisabled)
        .opacity(isDisabled ? DS.Components.disabledOpacity : 1)
        .dsMinTapTarget()
        .dsHoverable { isHovering = $0 }
        .dsPointerCursor()
        .accessibilityLabel(Text(label))
        .modifier(DSHelpModifier(text: tooltip ?? label))
    }
}

// MARK: - DSPrimaryButton

/// 品牌色实心按钮（外壳层主操作，如「发送」「保存」）。
///
/// 文字 DS.Typography.bodyMedium，白字，hover 用 buttonPrimaryHover，按下轻微缩放。
public struct DSPrimaryButton: View {

    private let title: String
    private let systemImage: String?
    private let cornerRadius: CGFloat
    private let isDisabled: Bool
    private let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    public init(_ title: String,
                systemImage: String? = nil,
                cornerRadius: CGFloat = DS.Radius.m,
                isDisabled: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.cornerRadius = cornerRadius
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: DS.Size.iconS, weight: .medium))
                }
                Text(title)
            }
            .font(DS.Typography.bodyMedium)
            .foregroundStyle(DS.Colors.labelOnBrand)
            .padding(.horizontal, DS.Spacing.l)
            .frame(minHeight: DS.Size.controlM)
            .background(isHovering ? DS.Colors.buttonPrimaryHover : DS.Colors.brandPrimary,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        // 按下缩放统一由 DSPressScaleStyle 负责，避免视图内再算一次造成双重缩放。
        .buttonStyle(DSPressScaleStyle(animated: !reduceMotion))
        .disabled(isDisabled)
        .opacity(isDisabled ? DS.Components.disabledOpacity : 1)
        .dsMinTapTarget()
        .dsHoverable { isHovering = $0 }
        .dsPointerCursor()
        .animation(reduceMotion ? nil : DS.Motion.fastEase, value: isHovering)
    }
}

// MARK: - DSGhostButton

/// 幽灵按钮：透明底 + hover 底色（外壳层的次要操作，如「停止生成」「清空」）。
public struct DSGhostButton: View {

    private let title: String
    private let systemImage: String?
    private let tint: Color
    private let isDisabled: Bool
    private let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    public init(_ title: String,
                systemImage: String? = nil,
                tint: Color = DS.Colors.labelPrimary,
                isDisabled: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: DS.Size.iconS, weight: .medium))
                }
                Text(title)
            }
            .font(DS.Typography.bodyMedium)
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Spacing.m)
            .frame(minHeight: DS.Size.controlM)
        }
        .buttonStyle(DSHoverFillButtonStyle(cornerRadius: DS.Radius.m,
                                            restingFill: .clear,
                                            hoverFill: DS.Colors.interactiveHover,
                                            pressedFill: DS.Colors.interactiveActive,
                                            isHovering: isHovering,
                                            animated: !reduceMotion))
        .disabled(isDisabled)
        .opacity(isDisabled ? DS.Components.disabledOpacity : 1)
        .dsMinTapTarget()
        .dsHoverable { isHovering = $0 }
        .dsPointerCursor()
    }
}

// MARK: - GlassPill

/// 行内开关胶囊（深度思考 / 智能搜索）。
///
/// 形态对齐参考实现的 `.toggle`：高 34、全圆角、（实色外观下）1pt border-l2、
/// 选中用 brand 系底色 + brandText。
///
/// - appearance `.solid`：扁平实色，用于内容层附近（默认，1:1 对齐参考实现）
/// - appearance `.glass`：Liquid Glass，用于浮动/外壳层；选中时用 brandPrimary 着色
///
/// 注意：`.glass` 外观下不要再把胶囊塞进另一块玻璃，玻璃无法采样玻璃。
public struct GlassPill: View {

    public enum Appearance: Sendable {
        case solid, glass
    }

    private let title: String
    private let systemImage: String?
    @Binding private var isOn: Bool
    private let appearance: Appearance
    private let isDisabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    public init(_ title: String,
                systemImage: String? = nil,
                isOn: Binding<Bool>,
                appearance: Appearance = .solid,
                isDisabled: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self._isOn = isOn
        self.appearance = appearance
        self.isDisabled = isDisabled
    }

    public var body: some View {
        Button(action: toggle) {
            pillLabel
        }
        .buttonStyle(DSPressScaleStyle(animated: !reduceMotion))
        .disabled(isDisabled)
        .opacity(isDisabled ? DS.Components.disabledOpacity : 1)
        .dsMinTapTarget()
        .dsHoverable { isHovering = $0 }
        .dsPointerCursor()
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: 外观

    private var pillLabel: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: DS.Size.iconS, weight: .medium))
            }
            Text(title)
                .font(DS.Typography.bodyMedium)
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, DS.Spacing.m)
        .frame(height: DS.Components.pillHeight)
        .background { solidBackground }
        .overlay { solidBorder }
        .modifier(GlassPillBackground(isOn: isOn, appearance: appearance))
        .contentShape(Capsule())
    }

    private var foreground: Color {
        guard isOn, !isDisabled else { return DS.Colors.labelPrimary }
        return appearance == .glass ? DS.Colors.labelOnBrand : DS.Colors.brandText
    }

    @ViewBuilder
    private var solidBackground: some View {
        if appearance == .solid {
            Capsule()
                .fill(solidFill)
        }
    }

    private var solidFill: Color {
        if isOn {
            return isHovering ? DS.Colors.buttonGhostActiveHover : DS.Colors.buttonGhostActiveFill
        }
        return isHovering ? DS.Colors.interactiveHover : .clear
    }

    @ViewBuilder
    private var solidBorder: some View {
        if appearance == .solid {
            Capsule()
                .strokeBorder(isOn ? DS.Colors.buttonGhostActiveBorder : DS.Colors.borderL2,
                              lineWidth: DS.Components.hairline)
        }
    }

    private func toggle() {
        if reduceMotion {
            isOn.toggle()
        } else {
            withAnimation(DS.Motion.fastEase) { isOn.toggle() }
        }
    }
}

/// 玻璃外观的胶囊底：只在 `.glass` 时生效，选中时用品牌色着色。
private struct GlassPillBackground: ViewModifier {

    let isOn: Bool
    let appearance: GlassPill.Appearance

    func body(content: Content) -> some View {
        if appearance == .glass {
            content.dsGlass(in: Capsule(),
                            interactive: true,
                            tint: isOn ? DS.Colors.brandPrimary : nil)
        } else {
            content
        }
    }
}

// MARK: - DSDivider

/// 分隔线（内容层与外壳层通用）。1pt 细线，走 border 令牌。
public struct DSDivider: View {

    public enum Axis: Sendable {
        case horizontal, vertical
    }

    private let axis: Axis
    private let color: Color

    public init(_ axis: Axis = .horizontal, color: Color = DS.Colors.borderL1) {
        self.axis = axis
        self.color = color
    }

    public var body: some View {
        switch axis {
        case .horizontal:
            Rectangle()
                .fill(color)
                .frame(height: DS.Components.hairline)
        case .vertical:
            Rectangle()
                .fill(color)
                .frame(width: DS.Components.hairline)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - DSChip

/// 小圆角标签：来源标记、文件标记、模型标记。
///
/// 属于内容层，保持扁平：只用底色 + 文字色，不加玻璃、不加阴影。
/// 传 `action` 时变成可点标签（hover 才有底色变化）。
public struct DSChip: View {

    private let title: String
    private let systemImage: String?
    private let tint: Color
    private let background: Color
    private let action: (() -> Void)?

    @State private var isHovering = false

    public init(_ title: String,
                systemImage: String? = nil,
                tint: Color = DS.Colors.labelSecondary,
                background: Color = DS.Colors.markdownTag,
                action: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.background = background
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { chipLabel }
                .buttonStyle(.plain)
                .dsHoverable { isHovering = $0 }
                .dsPointerCursor()
                .accessibilityLabel(Text(title))
        } else {
            chipLabel
                .accessibilityLabel(Text(title))
        }
    }

    private var chipLabel: some View {
        HStack(spacing: DS.Spacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: DS.Size.iconS, weight: .regular))
            }
            Text(title)
                .font(DS.Typography.captionMedium)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xxs)
        .background(isHovering ? DS.Colors.interactiveHover : background,
                    in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
        .animation(DS.Motion.fastEase, value: isHovering)
    }
}

// MARK: - DSTypingDots

/// 三点跳动加载动画（助手正在生成时显示在消息头部）。
///
/// Reduce Motion 开启时完全静止（保留可见度，不做脉冲），符合无障碍预期。
public struct DSTypingDots: View {

    private let tint: Color
    private let count: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    public init(tint: Color = DS.Colors.brandPrimary, count: Int = 3) {
        self.tint = tint
        self.count = count
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(tint)
                    .frame(width: DS.Components.typingDot, height: DS.Components.typingDot)
                    .opacity(dotOpacity(index: index))
                    .offset(y: dotOffset(index: index))
                    .animation(dotAnimation(index: index), value: isAnimating)
            }
        }
        .frame(height: DS.Size.iconM, alignment: .center)
        .onAppear { isAnimating = !reduceMotion }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在输入"))
    }

    private func dotOpacity(index: Int) -> Double {
        if reduceMotion { return DS.Components.typingDotStillOpacity }
        return isAnimating ? 1 : DS.Components.typingDotDimOpacity
    }

    private func dotOffset(index: Int) -> CGFloat {
        if reduceMotion { return 0 }
        return isAnimating ? -DS.Spacing.xxs : 0
    }

    private func dotAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: DS.Motion.slow)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * DS.Motion.fast / 2)
    }
}

// MARK: - Preview

private struct DSAtomsPreview: View {

    @State private var thinking = true
    @State private var search = false
    @State private var glassThinking = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            HStack(spacing: DS.Spacing.s) {
                DSIconButton("square.and.pencil", label: "新建对话", size: .l, tooltip: "新建对话") {}
                DSIconButton("arrow.up", label: "发送", size: .m) {}
                DSIconButton("doc.on.doc", label: "复制", size: .s) {}
                DSIconButton("xmark", label: "关闭", size: .xs, isDisabled: true) {}
            }

            HStack(spacing: DS.Spacing.m) {
                DSPrimaryButton("发送", systemImage: "arrow.up") {}
                DSPrimaryButton("已禁用", isDisabled: true) {}
                DSGhostButton("停止生成", systemImage: "stop.fill") {}
            }

            HStack(spacing: DS.Spacing.xs) {
                GlassPill("深度思考", systemImage: "brain", isOn: $thinking)
                GlassPill("智能搜索", systemImage: "globe", isOn: $search)
                GlassPill("玻璃外观", systemImage: "sparkles", isOn: $glassThinking, appearance: .glass)
            }

            HStack(spacing: DS.Spacing.s) {
                DSChip("deepseek-flash", systemImage: "cpu")
                DSChip("api.deepseek.com", systemImage: "link")
                DSChip("report.pdf", systemImage: "doc", action: {})
            }

            HStack(spacing: DS.Spacing.l) {
                DSTypingDots()
                DSDivider(.vertical)
                    .frame(height: DS.Size.iconL)
                Text("正在生成")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.labelTertiary)
            }

            DSDivider()

            Text("玻璃外壳样本")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.labelTertiary)

            Text("浮动工具栏")
                .font(DS.Typography.bodyMedium)
                .foregroundStyle(DS.Colors.labelPrimary)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.vertical, DS.Spacing.m)
                .dsGlass(cornerRadius: DS.Radius.card, interactive: true)
        }
        .padding(DS.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Colors.bgBase)
    }
}

#Preview("Atoms") {
    DSAtomsPreview()
}
