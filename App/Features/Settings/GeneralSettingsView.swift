import SwiftUI

// MARK: - 通用分组
//
// 字段顺序对齐 Reference/chat-demo/src/components/settings/SettingsDialog.tsx：
// 主题 → 语言 → …；DeepGlass 按组件需求改为 API Key → 接口地址 → 模型 →
// 深度思考 → 智能搜索 → 主题，连接信息在前、外观偏好在后。

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
                title: "深度思考",
                subtitle: "先思考后回答，解决推理问题",
                isOn: $bindable.thinking
            )
            .padding(.vertical, 16)

            SettingsHairline()

            SettingsToggleRow(
                title: "智能搜索",
                subtitle: "按需搜索网页",
                isOn: $bindable.search
            )
            .padding(.vertical, 16)

            SettingsHairline()

            SettingsThemeRow(theme: $bindable.theme)
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
                title: "接口地址",
                subtitle: "默认 https://api.deepseek.com，可指向自建服务或本地 Mock"
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
                        .accessibilityLabel("当前使用本地 Mock 服务")
                }
            }

            Button {
                bindable.apiOrigin = Self.mockOrigin
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("使用本地 Mock（http://127.0.0.1:8787）")
                        .font(DS.Typography.caption)
                }
                .foregroundStyle(DS.Colors.brandText)
                .frame(minHeight: compact ? 44 : 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("使用本地 Mock 接口地址")
        }
    }
}

// MARK: - 模型单选卡片

struct SettingsModelRow: View {
    let settings: AppSettings

    var body: some View {
        @Bindable var bindable = settings

        VStack(alignment: .leading, spacing: 10) {
            SettingsRowHeader(title: "模型", subtitle: "选择对话使用的 DeepSeek 模型")

            HStack(spacing: 10) {
                ForEach(ModelOption.all) { option in
                    SettingsModelCard(
                        option: option,
                        isSelected: settings.model == option.id
                    ) {
                        bindable.model = option.id
                    }
                }
            }
        }
    }
}

struct SettingsModelCard: View {
    let option: ModelOption
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

                Text(option.blurb)
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
                title: "主题",
                subtitle: "选择浅色、深色，或跟随系统外观自动切换"
            )

            SettingsSegmentedControl(
                values: ThemePreference.allCases,
                selection: $theme,
                label: { $0.label }
            )
        }
    }
}
