import SwiftUI

// MARK: - DesignGallery
//
// 人工核对用的组件画廊：把 DesignSystem 里的全部组件按「外壳层 / 内容层」分组排出来。
//
// 用途：
//   · 在 Xcode Preview 里快速逐项对像素（浅色 / 深色两套）；
//   · 需要真机/模拟器看 Liquid Glass 折射时，可临时把 RootView 指向 DesignGallery()。
//
// 这里只做「摆样」，不实现业务逻辑。

public struct DesignGallery: View {

    @State private var thinking = true
    @State private var search = false
    @State private var glassThinking = true
    @State private var glassSearch = false
    @State private var isExpanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var morphNamespace

    /// 是否包一层 ScrollView。预览/嵌入宿主页面时为 true；
    /// 用 ImageRenderer 离屏导出截图（ScrollView 离屏不渲染内容）时传 false。
    private let scrolls: Bool

    public init(scrolls: Bool = true) {
        self.scrolls = scrolls
    }

    public var body: some View {
        if scrolls {
            ScrollView { content }
                .background(DS.Colors.bgBase)
        } else {
            content
                .background(DS.Colors.bgBase)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxxl) {
            header
            iconButtonsSection
            primaryButtonsSection
            pillsSection
            chipsSection
            feedbackSection
            glassSection
            motionSection
        }
        .padding(DS.Spacing.xxxl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("DeepGlass DesignSystem")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.labelPrimary)
            Text("外壳层用玻璃，内容层保持扁平。所有尺寸/颜色/间距来自 DS 令牌。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.labelTertiary)
        }
    }

    // MARK: - 按钮

    private var iconButtonsSection: some View {
        section("DSIconButton · xs / s / m / l") {
            HStack(spacing: DS.Spacing.s) {
                DSIconButton("sidebar.left", label: "侧栏", size: .l, tooltip: "折叠侧栏") {}
                DSIconButton("square.and.pencil", label: "新建对话", size: .m, tooltip: "新建对话") {}
                DSIconButton("doc.on.doc", label: "复制", size: .s, tooltip: "复制") {}
                DSIconButton("xmark", label: "关闭", size: .xs, tooltip: "关闭") {}
                DSIconButton("trash", label: "删除", size: .m, tint: DS.Colors.errorPrimary, tooltip: "删除") {}
                DSIconButton("arrow.up", label: "禁用示例", size: .m, isDisabled: true) {}
            }
        }
    }

    private var primaryButtonsSection: some View {
        section("DSPrimaryButton / DSGhostButton") {
            HStack(spacing: DS.Spacing.m) {
                DSPrimaryButton("发送", systemImage: "arrow.up") {}
                DSPrimaryButton("新对话", systemImage: "plus", cornerRadius: DS.Radius.pill) {}
                DSPrimaryButton("不可用", isDisabled: true) {}
                DSGhostButton("停止生成", systemImage: "stop.fill") {}
                DSGhostButton("清空", isDisabled: true) {}
            }
        }
    }

    private var pillsSection: some View {
        section("GlassPill · solid / glass") {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                HStack(spacing: DS.Spacing.s) {
                    GlassPill("深度思考", systemImage: "brain", isOn: $thinking)
                    GlassPill("智能搜索", systemImage: "globe", isOn: $search)
                    GlassPill("已禁用", systemImage: "lock", isOn: .constant(true), isDisabled: true)
                }
                HStack(spacing: DS.Spacing.s) {
                    GlassPill("深度思考", systemImage: "brain", isOn: $glassThinking, appearance: .glass)
                    GlassPill("智能搜索", systemImage: "globe", isOn: $glassSearch, appearance: .glass)
                }
            }
        }
    }

    private var chipsSection: some View {
        section("DSChip · 内容层标签") {
            HStack(spacing: DS.Spacing.s) {
                DSChip("deepseek-flash", systemImage: "cpu")
                DSChip("v4-pro", systemImage: "sparkles", tint: DS.Colors.brandText, background: DS.Colors.brandSubtle)
                DSChip("api.deepseek.com", systemImage: "link")
                DSChip("report.pdf", systemImage: "doc", action: {})
                DSChip("2025-11-20")
            }
        }
    }

    private var feedbackSection: some View {
        section("DSTypingDots / DSDivider") {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                HStack(spacing: DS.Spacing.m) {
                    DSTypingDots()
                    Text("正在生成")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.labelTertiary)
                    DSTypingDots(tint: DS.Colors.labelTertiary)
                }
                DSDivider()
                HStack(spacing: DS.Spacing.m) {
                    Text("左")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.labelSecondary)
                    DSDivider(.vertical)
                        .frame(height: DS.Size.iconL)
                    Text("右")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.labelSecondary)
                }
            }
        }
    }

    // MARK: - 玻璃

    private var glassSection: some View {
        section("dsGlass / DSGlassCluster · 外壳层") {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                // 浮动工具栏：同组玻璃同一个容器
                DSGlassCluster(spacing: DS.Spacing.m) {
                    HStack(spacing: DS.Spacing.s) {
                        DSIconButton("textformat", label: "格式", size: .s) {}
                        DSIconButton("paperclip", label: "附件", size: .s) {}
                        DSIconButton("mic", label: "语音", size: .s) {}
                    }
                    .padding(DS.Spacing.xs)
                    .dsGlass(cornerRadius: DS.Radius.card, interactive: true)
                }

                // 输入框外壳：composer 圆角
                HStack(spacing: DS.Spacing.s) {
                    Text("给 DeepSeek 发送消息…")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.labelTertiary)
                    Spacer(minLength: DS.Spacing.m)
                    Image(systemName: "arrow.up")
                        .font(.system(size: DS.Size.iconS, weight: .semibold))
                        .foregroundStyle(DS.Colors.labelOnBrand)
                        .frame(width: DS.Size.controlS, height: DS.Size.controlS)
                        .background(DS.Colors.brandPrimary, in: Circle())
                }
                .padding(.leading, DS.Spacing.l)
                .padding(.trailing, DS.Spacing.xs)
                .padding(.vertical, DS.Spacing.xs)
                .dsGlass(cornerRadius: DS.Radius.composer, interactive: true)

                // 胶囊玻璃按钮
                HStack(spacing: DS.Spacing.s) {
                    Text("玻璃胶囊")
                        .font(DS.Typography.bodyMedium)
                        .foregroundStyle(DS.Colors.labelOnBrand)
                        .padding(.horizontal, DS.Spacing.l)
                        .frame(height: DS.Components.pillHeight)
                        .dsGlass(in: Capsule(), interactive: true, tint: DS.Colors.brandPrimary)
                }
            }
        }
    }

    // MARK: - morph

    private var motionSection: some View {
        section("morph · dsGlassID + DSGlassCluster") {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                DSGlassCluster(spacing: DS.Spacing.xl) {
                    HStack(spacing: isExpanded ? DS.Spacing.xxl : DS.Spacing.xxs) {
                        glassMorphDot("mic.fill")
                            .dsGlassID("mic", in: morphNamespace)
                        glassMorphDot("arrow.up")
                            .dsGlassID("send", in: morphNamespace)
                    }
                }

                DSGhostButton(isExpanded ? "合并" : "拆分",
                              systemImage: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                    if reduceMotion {
                        isExpanded.toggle()
                    } else {
                        withAnimation(DS.Motion.easing) { isExpanded.toggle() }
                    }
                }
                Text("Reduce Motion 开启时不会注册 glassEffectID，因此没有形变动画。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.labelTertiary)
            }
        }
    }

    private func glassMorphDot(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: DS.Size.iconM, weight: .medium))
            .foregroundStyle(DS.Colors.labelPrimary)
            .frame(width: DS.Size.controlXL, height: DS.Size.controlXL)
            .dsGlass(in: Circle(), interactive: true)
    }

    // MARK: - 分组外壳

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text(title)
                .font(DS.Typography.captionMedium)
                .foregroundStyle(DS.Colors.labelTertiary)
            content()
            DSDivider()
        }
    }
}

// MARK: - Preview

#Preview("DesignGallery · Light") {
    DesignGallery()
        .preferredColorScheme(.light)
        .frame(width: 860, height: 900)
}

#Preview("DesignGallery · Dark") {
    DesignGallery()
        .preferredColorScheme(.dark)
        .frame(width: 860, height: 900)
}
