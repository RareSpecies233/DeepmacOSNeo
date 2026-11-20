import SwiftUI

// MARK: - 基础分隔线

struct SettingsHairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(DS.Colors.borderL1)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

// MARK: - 行标题 + 说明

struct SettingsRowHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DS.Typography.bodyMedium)
                .foregroundStyle(DS.Colors.labelPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.labelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 实色输入框外观
//
// 玻璃外壳里只有这类输入控件保持实色，保证文字对比度与可读性。

extension View {
    func settingsSolidField(cornerRadius: CGFloat = 10) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.Colors.inputFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.Colors.borderL2, lineWidth: 0.5)
            }
    }

    /// iOS 上的输入习惯：关闭自动大写与自动纠错
    @ViewBuilder
    func settingsPlainInput() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    /// macOS 上让按钮承接 Esc（cancelAction）
    @ViewBuilder
    func settingsCancelKeyEquivalent() -> some View {
        #if os(macOS)
        self.keyboardShortcut(.cancelAction)
        #else
        self
        #endif
    }
}

// MARK: - 按钮

struct SettingsButton: View {
    enum Kind {
        case primary
        case secondary
        case danger
        case ghost
        case link
    }

    let title: String
    var kind: Kind = .secondary
    var isLoading = false
    var isEnabled = true
    var expands = false
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                }
                Text(title)
                    .font(DS.Typography.bodyMedium)
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .link ? 0 : 14)
            .frame(minHeight: compact ? 44 : 36)
            .frame(maxWidth: expands ? .infinity : nil)
            .background { background }
            .overlay { border }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SettingsPressButtonStyle())
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch kind {
        case .primary: DS.Colors.labelOnBrand
        case .secondary: DS.Colors.labelPrimary
        case .danger: DS.Colors.errorPrimary
        case .ghost: DS.Colors.labelSecondary
        case .link: DS.Colors.brandText
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Colors.brandPrimary)
        case .secondary:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DS.Colors.bgLayer2.opacity(0.65))
        case .danger:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsPalette.dangerFill)
        case .ghost, .link:
            Color.clear
        }
    }

    @ViewBuilder
    private var border: some View {
        switch kind {
        case .primary, .ghost, .link:
            EmptyView()
        case .secondary:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DS.Colors.borderL2, lineWidth: 0.5)
        case .danger:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DS.Colors.errorPrimary.opacity(0.45), lineWidth: 0.5)
        }
    }
}

struct SettingsPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(DS.Motion.fastEase, value: configuration.isPressed)
    }
}

// MARK: - 关闭按钮

struct SettingsCloseButton: View {
    var compact = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? DS.Colors.labelPrimary : DS.Colors.labelTertiary)
                .frame(width: compact ? 44 : 28, height: compact ? 44 : 28)
                .background {
                    Circle().fill(hovering ? DS.Colors.interactiveHover : Color.clear)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("关闭设置")
        .settingsCancelKeyEquivalent()
    }
}

// MARK: - 开关行

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsRowHeader(title: title, subtitle: subtitle)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DS.Colors.brandPrimary)
                .frame(minWidth: 44, minHeight: compact ? 44 : 24)
                .accessibilityLabel(title)
        }
    }
}

// MARK: - 分段控件

struct SettingsSegmentedControl<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                let isSelected = selection == value
                Button {
                    withAnimation(DS.Motion.fastEase) { selection = value }
                } label: {
                    Text(label(value))
                        .font(DS.Typography.bodyMedium)
                        .foregroundStyle(isSelected ? DS.Colors.labelPrimary : DS.Colors.labelSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: compact ? 44 : 32)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DS.Colors.bgLayer2)
                                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : AccessibilityTraits())
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(DS.Colors.bgSkeleton)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(DS.Colors.borderL1, lineWidth: 0.5)
        }
    }
}
