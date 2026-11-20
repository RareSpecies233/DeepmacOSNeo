import SwiftUI

/// 单条消息：用户为右侧气泡，助手为全宽内容 + 操作栏
struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    var isLastAssistant: Bool = false
    var onRegenerate: (() -> Void)?
    @State private var hovered = false
    @State private var copied = false

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: assistantBlock
        }
    }

    // MARK: 用户

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.plainText)
                .font(DS.Typography.userBody)
                .foregroundStyle(DS.Colors.labelPrimary)
                .lineSpacing(DS.Typography.userLineSpacing)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DS.Colors.bubble)
                }
        }
    }

    // MARK: 助手

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThinkingTimeline(message: message, isStreaming: isStreaming)

            if message.status == .failed, let error = message.errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error)
                }
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.errorPrimary)
                .padding(.vertical, 6)
            }

            if !message.plainText.isEmpty {
                AssistantBody(text: message.plainText, isStreaming: isStreaming)
            } else if isStreaming && message.blocks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在生成…")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.labelTertiary)
                }
                .padding(.vertical, 4)
            }

            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovered = $0 }
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            if !message.plainText.isEmpty {
                ActionIcon(systemName: copied ? "checkmark" : "doc.on.doc", help: "复制") {
                    copyToPasteboard(message.plainText)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                }
            }
            if !message.plainText.isEmpty {
                ReadAloudButton(text: message.plainText)
            }
            if isLastAssistant && !isStreaming, let onRegenerate {
                ActionIcon(systemName: "arrow.clockwise", help: "重新生成", action: onRegenerate)
            }
            Spacer()
        }
        .opacity(hovered || isStreaming == false ? 1 : 1)
        .padding(.top, 6)
        .frame(height: 26)
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

private struct ActionIcon: View {
    let systemName: String
    var help: String
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Colors.labelTertiary)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .fill(hovered ? DS.Colors.interactiveHover : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}
