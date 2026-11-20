import SwiftUI

// MARK: - 通用分组
//
// 字段顺序对齐 Reference/chat-demo/src/components/settings/SettingsDialog.tsx：
// 主题 → 语言 → …；DeepGlass 按组件需求改为 API Key → 接口地址 → 模型 →
// 深度思考 → 智能搜索 → 主题 → 语言，连接信息在前、外观偏好在后。
//
// 文案统一走 L10n：L10n.t 读取 AppSettings.shared.language，切换语言后随
// SwiftUI 观察一起刷新，无需重启。

struct SettingsGeneralView: View {
    let settings: AppSettings

    var body: some View {
        @Bindable var bindable = settings

        LazyVStack(alignment: .leading, spacing: 0) {
            SettingsAPIKeySection(settings: settings)
                .padding(.top, 16)
                .padding(.bottom, 16)

            SettingsHairline()

            SettingsOriginRow(settings: settings)
                .padding(.vertical, 16)

            SettingsHairline()

            SettingsModelRow(settings: settings)
                .padding(.vertical, 16)

            SettingsHairline()

            SettingsToggleRow(
                title: L10n.t(.thinkingSwitch),
                subtitle: L10n.t(.deactivatedThinkTooltip),
                isOn: $bindable.thinking
            )
            .padding(.vertical, 16)

            SettingsHairline()

            SettingsToggleRow(
                title: L10n.t(.search),
                subtitle: L10n.t(.deactivatedSearchTooltip),
                isOn: $bindable.search
            )

            SettingsHairline()

            SettingsToggleRow(
                title: L10n.t(.showBalance),
                subtitle: L10n.t(.showBalanceSubtitle),
                isOn: $bindable.showsBalance
            )
            .padding(.vertical, 16)

            SettingsHairline()

            SettingsThemeRow(theme: $bindable.theme)
                .padding(.vertical, 16)

            SettingsHairline()

            SettingsLanguageRow(language: $bindable.language)
                .padding(.vertical, 16)
        }
    }
}

// MARK: - 接口地址

struct SettingsOriginRow: View {
    let settings: AppSettings

    @Environment(\.horizontalSizeClass) private var sizeClass

    private static let mockOrigin = "http://127.0.0.1:8787"
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        @Bindable var bindable = settings

        VStack(alignment: .leading, spacing: 10) {
            SettingsRowHeader(
                title: L10n.t(.apiOriginTitle),
                subtitle: L10n.t(.apiOriginSubtitle)
            )

            HStack(spacing: 8) {
                TextField("https://api.deepseek.com", text: $bindable.apiOrigin)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .settingsPlainInput()
                    .padding(.horizontal, 12)
                    .frame(height: compact ? 44 : 40)
                    .settingsSolidField()

                if settings.isUsingMock {
                    Text("Mock")
                        .font(DS.Typography.captionMedium)
                        .foregroundStyle(DS.Colors.brandText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DS.Colors.brandSubtle)
                        }
                        .accessibilityLabel(L10n.t(.usingMockService))
                }
            }

            Button {
                bindable.apiOrigin = Self.mockOrigin
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.t(.useLocalMock))
                        .font(DS.Typography.caption)
                }
                .foregroundStyle(DS.Colors.brandText)
                .frame(minHeight: compact ? 44 : 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t(.useLocalMockAccessibility))
        }
    }
}

// MARK: - 模型单选卡片

struct SettingsModelRow: View {
    let settings: AppSettings

    var body: some View {
        @Bindable var bindable = settings

        VStack(alignment: .leading, spacing: 10) {
            SettingsRowHeader(
                title: L10n.t(.modelRowTitle),
                subtitle: L10n.t(.modelRowSubtitle)
            )

            HStack(spacing: 10) {
                ForEach(ModelOption.all) { option in
                    SettingsModelCard(
                        option: option,
                        blurb: SettingsModelRow.blurb(for: option),
                        isSelected: settings.model == option.id
                    ) {
                        bindable.model = option.id
                    }
                }
            }
        }
    }

    /// 模型简介来自 AppSettings 的 `ModelOption.blurb`，按 id 取对应译文；
    /// 新增模型没配文案时回退到 `blurb` 原文。
    static func blurb(for option: ModelOption) -> String {
        switch option.id {
        case "deepseek-flash": L10n.t(.modelFlashBlurb)
        case "deepseek-v4-pro": L10n.t(.modelProBlurb)
        default: option.blurb
        }
    }
}

struct SettingsModelCard: View {
    let option: ModelOption
    let blurb: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var hovering = false

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(option.label)
                        .font(DS.Typography.bodyMedium)
                        .foregroundStyle(DS.Colors.labelPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? DS.Colors.brandPrimary : DS.Colors.labelCaption)
                }

                Text(blurb)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.labelTertiary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 58, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? DS.Colors.brandSubtle
                            : (hovering ? DS.Colors.interactiveHover : Color.clear)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? DS.Colors.brandPrimary : DS.Colors.borderL2,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
    }
}

// MARK: - 主题

struct SettingsThemeRow: View {
    @Binding var theme: ThemePreference

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRowHeader(
                title: L10n.t(.avatarMenuSettingsDialogThemeItemLabel),
                subtitle: L10n.t(.themeSubtitle)
            )

            SettingsSegmentedControl(
                values: ThemePreference.allCases,
                selection: $theme,
                label: { Self.label(for: $0) }
            )
        }
    }

    /// `ThemePreference.label` 是 AppSettings 里的固定中文，语言层在这里按 case 取译文。
    static func label(for theme: ThemePreference) -> String {
        switch theme {
        case .light: L10n.t(.avatarMenuSettingsDialogThemeSelectLightOption)
        case .dark: L10n.t(.avatarMenuSettingsDialogThemeSelectDarkOption)
        case .system: L10n.t(.avatarMenuSettingsDialogThemeSelectSystemOption)
        }
    }
}

// MARK: - 语言

struct SettingsLanguageRow: View {
    @Binding var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRowHeader(
                title: L10n.t(.settingsLocalePreference),
                subtitle: L10n.t(.languageSubtitle)
            )

            SettingsSegmentedControl(
                values: AppLanguage.allCases,
                selection: $language,
                label: { Self.label(for: $0) }
            )
        }
    }

    /// 语言名按当前界面语言显示（照抄原版 settingsLocaleZhCN / settingsLocaleEnUS）
    static func label(for language: AppLanguage) -> String {
        switch language {
        case .zhHans: L10n.t(.settingsLocaleZhCN)
        case .enUS: L10n.t(.settingsLocaleEnUS)
        }
    }
}
