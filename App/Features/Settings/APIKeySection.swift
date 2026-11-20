import SwiftUI

// MARK: - API Key
//
// 三态展示：
//   · 未填写 → 灰色提示
//   · 校验通过 → 绿色「Key 可用」
//   · 校验失败 → 红色「Key 校验失败：原因」
// 保存写入 Keychain（AppSettings.saveAPIKey），验证走 GET /models，不产生费用。

struct SettingsAPIKeySection: View {
    let settings: AppSettings

    @State private var draft = ""
    @State private var isRevealed = false
    @State private var isVerifying = false
    @State private var saveError: String?
    @State private var notice: String?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var compact: Bool { sizeClass == .compact }
    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsRowHeader(
                title: "API Key",
                subtitle: "只保存在本机钥匙串；验证只请求 GET /models，不产生费用"
            )
            inputRow
            actionRow
            statusRow
        }
    }

    // MARK: 输入

    private var inputRow: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField("请输入 API Key", text: $draft)
                } else {
                    SecureField("请输入 API Key", text: $draft)
                }
            }
            .textFieldStyle(.plain)
            .font(DS.Typography.body)
            .foregroundStyle(DS.Colors.labelPrimary)
            .settingsPlainInput()
            .onSubmit { save() }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Colors.labelTertiary)
                    .frame(width: compact ? 44 : 28, height: compact ? 44 : 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "隐藏 API Key" : "显示 API Key")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: compact ? 44 : 40)
        .settingsSolidField()
    }

    // MARK: 操作

    private var actionRow: some View {
        HStack(spacing: 8) {
            SettingsButton(
                title: "保存",
                kind: .primary,
                isEnabled: !trimmedDraft.isEmpty
            ) {
                save()
            }

            SettingsButton(
                title: "验证",
                kind: .secondary,
                isLoading: isVerifying,
                isEnabled: settings.hasAPIKey || !trimmedDraft.isEmpty
            ) {
                Task { await verify() }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: 三态

    @ViewBuilder
    private var statusRow: some View {
        if let saveError {
            statusLine(
                icon: "exclamationmark.circle.fill",
                text: "保存失败：\(saveError)",
                color: DS.Colors.errorPrimary
            )
        } else if isVerifying {
            statusLine(icon: "clock", text: "正在验证 API Key…", color: DS.Colors.labelSecondary)
        } else if !settings.hasAPIKey && trimmedDraft.isEmpty {
            statusLine(
                icon: "info.circle",
                text: "尚未填写 API Key，填写并保存后即可连接 DeepSeek 接口",
                color: DS.Colors.labelTertiary
            )
        } else {
            switch settings.keyStatus {
            case .valid:
                statusLine(
                    icon: "checkmark.circle.fill",
                    text: "Key 可用",
                    color: SettingsPalette.success
                )
            case .invalid(let reason):
                statusLine(
                    icon: "xmark.circle.fill",
                    text: "Key 校验失败：\(reason)",
                    color: DS.Colors.errorPrimary
                )
            case .unknown:
                if !trimmedDraft.isEmpty {
                    statusLine(
                        icon: "circle.dashed",
                        text: "已输入新的 Key，尚未保存",
                        color: DS.Colors.labelTertiary
                    )
                } else if let notice {
                    statusLine(icon: "checkmark.seal", text: notice, color: DS.Colors.labelSecondary)
                } else {
                    statusLine(
                        icon: "clock",
                        text: "已保存，尚未验证",
                        color: DS.Colors.labelTertiary
                    )
                }
            }
        }
    }

    private func statusLine(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(DS.Typography.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }

    // MARK: 动作

    private func save() {
        guard !trimmedDraft.isEmpty else { return }
        saveError = nil
        do {
            try settings.saveAPIKey(draft)
            draft = ""
            isRevealed = false
            notice = "已保存到钥匙串"
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func verify() async {
        saveError = nil
        notice = nil

        if !trimmedDraft.isEmpty {
            do {
                try settings.saveAPIKey(trimmedDraft)
                draft = ""
            } catch {
                saveError = error.localizedDescription
                return
            }
        }

        isVerifying = true
        await settings.verifyAPIKey()
        isVerifying = false
    }
}
