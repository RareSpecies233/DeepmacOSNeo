import SwiftUI

// MARK: - 分组

enum SettingsGroup: String, CaseIterable, Identifiable {
    case general
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .data: "数据"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .general: "通用设置"
        case .data: "数据管理"
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .data: "internaldrive"
        }
    }
}

// MARK: - 设置面板

/// 设置面板。
/// - macOS / iPad：720×520 居中弹窗，左侧 160pt 分组导航，右侧滚动内容区。
/// - iPhone（compact width）：底部 sheet 形态，分组导航横排在顶部。
struct SettingsView: View {
    let settings: AppSettings
    let onClearAll: () -> Void
    /// 由承载方注入关闭动作；存在时才会显示关闭按钮并响应 Esc。
    var onClose: (() -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var group: SettingsGroup = .general
    @FocusState private var isPanelFocused: Bool

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return sizeClass == .compact
        #endif
    }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        // 打开时焦点落在面板本身而不是 API Key 输入框：不抢键盘焦点，
        // 同时让 Esc（onExitCommand）有稳定的接收者。
        .focusable()
        .focused($isPanelFocused)
        .defaultFocus($isPanelFocused, true)
        .focusEffectDisabled()
        .onAppear { isPanelFocused = true }
    }

    // MARK: 桌面 / iPad 居中弹窗

    private var regularLayout: some View {
        VStack(spacing: 0) {
            header(topPadding: 18)

            SettingsHairline()

            HStack(spacing: 0) {
                SettingsNavigation(group: $group, compact: false)

                SettingsHairline(vertical: true)

                scrollContent(horizontalPadding: 24, topPadding: 0, bottomPadding: 20)
            }
        }
        .frame(width: 720, height: 520)
        .settingsGlassSurface(cornerRadius: 20)
        .settingsEscapeToClose(onClose)
    }

    // MARK: iPhone 底部 sheet

    private var compactLayout: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header(topPadding: 14)

                SettingsNavigation(group: $group, compact: true)
                    .padding(.bottom, 6)

                SettingsHairline()
            }

            scrollContent(horizontalPadding: 20, topPadding: 0, bottomPadding: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsGlassSheetSurface(cornerRadius: 24)
        .settingsEscapeToClose(onClose)
    }

    // MARK: 头部

    private func header(topPadding: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text("设置")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.labelPrimary)

            Spacer(minLength: 8)

            if let onClose {
                SettingsCloseButton(compact: isCompact, action: onClose)
            }
        }
        .padding(.horizontal, isCompact ? 20 : 20)
        .padding(.top, topPadding)
        .padding(.bottom, isCompact ? 8 : 14)
    }

    // MARK: 内容

    private func scrollContent(
        horizontalPadding: CGFloat,
        topPadding: CGFloat,
        bottomPadding: CGFloat
    ) -> some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch group {
                case .general:
                    SettingsGeneralView(settings: settings)
                case .data:
                    SettingsDataView(onClearAll: onClearAll)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 分组导航

struct SettingsNavigation: View {
    @Binding var group: SettingsGroup
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 6) {
                ForEach(SettingsGroup.allCases) { item in
                    SettingsNavigationItem(
                        group: item,
                        isActive: group == item,
                        compact: true
                    ) {
                        withAnimation(DS.Motion.fastEase) { group = item }
                    }
                }
            }
            .padding(.horizontal, 16)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsGroup.allCases) { item in
                    SettingsNavigationItem(
                        group: item,
                        isActive: group == item,
                        compact: false
                    ) {
                        withAnimation(DS.Motion.fastEase) { group = item }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .padding(.top, 4)
            .frame(width: 160, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

struct SettingsNavigationItem: View {
    let group: SettingsGroup
    let isActive: Bool
    let compact: Bool
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var hovering = false

    private var tapHeight: CGFloat {
        if compact { return 44 }
        return sizeClass == .compact ? 44 : 36
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: group.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)

                Text(group.title)
                    .font(DS.Typography.body)
                    .lineLimit(1)

                if !compact {
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(isActive ? DS.Colors.labelPrimary : DS.Colors.labelSecondary)
            .padding(.horizontal, 10)
            .frame(maxWidth: compact ? .infinity : nil)
            .frame(minHeight: tapHeight, alignment: compact ? .center : .leading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundFill)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(group.accessibilityTitle)
        .accessibilityAddTraits(isActive ? .isSelected : AccessibilityTraits())
    }

    private var backgroundFill: Color {
        if isActive { return DS.Colors.interactiveHover }
        return hovering ? DS.Colors.interactiveHover.opacity(0.6) : .clear
    }
}

// MARK: - 承载方式

extension View {
    /// 打开设置面板：
    /// - macOS / iPad：居中玻璃浮层，点遮罩或 Esc 关闭；
    /// - iPhone（compact width）：带拖拽指示的底部 sheet。
    func settingsPresented(
        _ isPresented: Binding<Bool>,
        settings: AppSettings,
        onClearAll: @escaping () -> Void
    ) -> some View {
        modifier(
            SettingsPresentationModifier(
                isPresented: isPresented,
                settings: settings,
                onClearAll: onClearAll
            )
        )
    }
}

struct SettingsPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let settings: AppSettings
    let onClearAll: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return sizeClass == .compact
        #endif
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        if isCompact {
            content
                .sheet(isPresented: $isPresented) {
                    SettingsView(
                        settings: settings,
                        onClearAll: onClearAll,
                        onClose: { isPresented = false }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
                    .presentationBackground(.clear)
                }
        } else {
            overlayHost(content)
        }
        #else
        overlayHost(content)
        #endif
    }

    private func overlayHost(_ content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented = false }
                        .accessibilityHidden(true)

                    SettingsView(
                        settings: settings,
                        onClearAll: onClearAll,
                        onClose: { isPresented = false }
                    )
                    .shadow(color: .black.opacity(0.28), radius: 36, y: 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
                .animation(DS.Motion.fastEase, value: isPresented)
            }
        }
    }
}

// MARK: - Esc

private extension View {
    @ViewBuilder
    func settingsEscapeToClose(_ action: (() -> Void)?) -> some View {
        #if os(macOS)
        if let action {
            self.onExitCommand(perform: action)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - 打开时不抢键盘焦点
//
// 焦点由 body 里的 `.defaultFocus($isPanelFocused, true)` 落在面板容器上，
// SwiftUI 就不会再把 API Key 输入框设为首个响应者，移动端也不会弹起键盘。
