import SwiftUI

// MARK: - 数据分组
//
// 会话存在本地 SwiftData。清空是不可恢复操作，必须二次确认后调用 onClearAll。

struct SettingsDataView: View {
    let onClearAll: () -> Void

    @State private var isConfirmingClear = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private static let version = "0.1.0"
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            storageBlock
                .padding(.top, 16)
                .padding(.bottom, 16)

            SettingsHairline()

            clearBlock
                .padding(.vertical, 16)

            SettingsHairline()

            aboutBlock
                .padding(.vertical, 16)
        }
        .alert(
            "删除后，所有对话都将被清空且无法找回",
            isPresented: $isConfirmingClear
        ) {
            Button("取消", role: .cancel) {}
            Button("清空全部会话", role: .destructive) { onClearAll() }
        } message: {
            Text("本地保存的附件及未发送的草稿也将被删除。")
        }
    }

    // MARK: 存储位置

    private var storageBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "internaldrive")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Colors.brandText)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DS.Colors.brandSubtle)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("会话保存在本机")
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.Colors.labelPrimary)
                Text("所有会话与附件都写入本地 SwiftData 数据库，不会上传到服务器。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.labelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 清空全部会话

    @ViewBuilder
    private var clearBlock: some View {
        if compact {
            VStack(alignment: .leading, spacing: 10) {
                SettingsRowHeader(
                    title: "清空全部会话",
                    subtitle: "删除后，所有对话都将被清空且无法找回。"
                )
                SettingsButton(
                    title: "清空全部会话",
                    kind: .danger,
                    expands: true
                ) {
                    isConfirmingClear = true
                }
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                SettingsRowHeader(
                    title: "清空全部会话",
                    subtitle: "删除后，所有对话都将被清空且无法找回。"
                )
                SettingsButton(
                    title: "清空全部会话",
                    kind: .danger
                ) {
                    isConfirmingClear = true
                }
            }
        }
    }

    // MARK: 版本与声明

    private var aboutBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("版本")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.labelPrimary)
                Spacer(minLength: 8)
                Text(Self.version)
                    .font(DS.Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(DS.Colors.labelSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("版本 \(Self.version)")

            Text("基于 DeepSeek 官方 chat-demo 设计，MIT")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.labelTertiary)
        }
    }
}
