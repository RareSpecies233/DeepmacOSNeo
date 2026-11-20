import SwiftUI

/// 输入框：自适应高度文本域 + 深度思考/智能搜索开关 + 附件 + 发送/停止
struct ComposerView: View {
    @Binding var text: String
    @Binding var thinking: Bool
    @Binding var search: Bool
    var isStreaming: Bool
    var canSend: Bool
    /// nil 表示按当前语言取 `chatInputPlaceholderChat`
    var placeholder: String? = nil
    var onSend: () -> Void
    var onStop: () -> Void
    var onAttach: (() -> Void)? = nil
    var isHome: Bool = false
    var attachments: [FileAttachment] = []
    var attachmentProgress: [String: Double] = [:]
    var onRemoveAttachment: ((String) -> Void)? = nil
    var onRetryAttachment: ((String) -> Void)? = nil

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var attachHovered = false

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                AttachmentStrip(
                    items: attachments,
                    onRemove: { onRemoveAttachment?($0) },
                    onRetry: { onRetryAttachment?($0) },
                    progress: attachmentProgress
                )
                .padding(.top, 12)
            }
            field
            functionRow
        }
        .background(containerBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(dynAlpha(0x000000, 0.10, 0xFFFFFF, 0.06), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(isHome ? 0.18 : 0.12), radius: isHome ? 30 : 10, y: isHome ? 16 : 4)
    }

    // MARK: 文本区

    private var field: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder ?? L10n.t(.chatInputPlaceholderChat))
                .foregroundStyle(DS.Colors.labelTertiary),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .lineSpacing(4)
        .lineLimit(2...12)
        .focused($focused)
        .onSubmit {
            if canSend { onSend() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        #if os(iOS)
        .submitLabel(.send)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 功能行

    /// 紧凑宽度（iPhone、iPad 分屏）下开关只留图标，
    /// 否则「深度思考 + 智能搜索 + 麦克风 + 附件 + 发送」会挤爆一行。
    private var pillsCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var functionRow: some View {
        HStack(spacing: 8) {
            TogglePill(isOn: $thinking, systemImage: "brain", title: L10n.t(.thinkingSwitch),
                       help: L10n.t(.deactivatedThinkTooltip), compact: pillsCompact)
            TogglePill(isOn: $search, systemImage: "globe", title: L10n.t(.search),
                       help: L10n.t(.deactivatedSearchTooltip), compact: pillsCompact)
            Spacer(minLength: 0)
            VoiceInputButton(text: $text)
            if let onAttach {
                Button(action: onAttach) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(DS.Colors.labelSecondary)
                        .frame(width: 34, height: 34)
                        .background {
                            Circle().fill(attachHovered ? DS.Colors.interactiveHover : .clear)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { attachHovered = $0 }
                .help(L10n.t(.uploadFile))
                .accessibilityLabel(L10n.t(.uploadFile))
            }
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 2)
    }

    private var sendButton: some View {
        Button {
            if isStreaming { onStop() } else if canSend { onSend() }
        } label: {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background {
                    Circle()
                        .fill(DS.Colors.brandPrimary)
                        .opacity(isStreaming || canSend ? 1 : 0.28)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isStreaming && !canSend)
        .help(isStreaming ? L10n.t(.chatInputStopButtonTooltip) : L10n.t(.send))
        .accessibilityLabel(isStreaming ? L10n.t(.chatInputStopButtonTooltip) : L10n.t(.send))
    }

    // MARK: 外壳玻璃（A1：只在外壳层）

    @ViewBuilder
    private var containerBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 24).fill(DS.Colors.inputFill)
        } else {
            // 玻璃层次：半透明底 → 玻璃 → 顶部高光。
            // 纯实色会让 glassEffect 完全不可见，只剩一个灰盒子。
            RoundedRectangle(cornerRadius: 24)
                .fill(DS.Colors.inputFill.opacity(0.72))
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
        }
    }
}

// MARK: - 开关胶囊

private struct TogglePill: View {
    @Binding var isOn: Bool
    let systemImage: String
    let title: String
    var help: String
    var compact: Bool = false
    @State private var hovered = false

    var body: some View {
        Button {
            withAnimation(DS.Motion.fastEase) { isOn.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                if !compact {
                    Text(title)
                        .font(DS.Typography.body)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isOn ? DS.Colors.brandText : DS.Colors.labelSecondary)
            .padding(.horizontal, compact ? 0 : 12)
            .frame(width: compact ? 34 : nil, height: 34)
            .background {
                Capsule()
                    .fill(isOn ? DS.Colors.brandSubtle : (hovered ? DS.Colors.interactiveHover : .clear))
            }
            .overlay {
                Capsule()
                    .strokeBorder(isOn ? DS.Colors.brandPrimary.opacity(0.45) : DS.Colors.borderL2,
                                  lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
