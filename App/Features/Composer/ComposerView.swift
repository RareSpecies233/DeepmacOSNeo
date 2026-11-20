import SwiftUI

/// 输入框：自适应高度文本域 + 深度思考/智能搜索开关 + 附件 + 发送/停止
struct ComposerView: View {
    @Binding var text: String
    @Binding var thinking: Bool
    @Binding var search: Bool
    var isStreaming: Bool
    var canSend: Bool
    var placeholder: String = "请输入消息"
    var onSend: () -> Void
    var onStop: () -> Void
    var onAttach: (() -> Void)? = nil
    var isHome: Bool = false

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var attachHovered = false

    var body: some View {
        VStack(spacing: 0) {
            field
            functionRow
        }
        .background(containerBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(dynAlpha(0x000000, 0.10, 0xFFFFFF, 0.06), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(isHome ? 0.03 : 0.02), radius: isHome ? 24 : 6, y: isHome ? 18 : 2)
    }

    // MARK: 文本区

    private var field: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Colors.labelTertiary)
                    .padding(.top, 12)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineSpacing(4)
                .lineLimit(2...12)
                .focused($focused)
                .onSubmit {
                    if canSend { onSend() }
                }
                .padding(.vertical, 12)
                #if os(iOS)
                .submitLabel(.send)
                #endif
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    // MARK: 功能行

    private var functionRow: some View {
        HStack(spacing: 8) {
            TogglePill(isOn: $thinking, systemImage: "brain", title: "深度思考",
                       help: "先思考后回答，解决推理问题")
            TogglePill(isOn: $search, systemImage: "globe", title: "智能搜索",
                       help: "按需搜索网页")
            Spacer(minLength: 0)
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
                .help("上传文件")
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
        .help(isStreaming ? "停止生成" : "发送")
    }

    // MARK: 外壳玻璃（A1：只在外壳层）

    @ViewBuilder
    private var containerBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 24).fill(DS.Colors.inputFill)
        } else {
            // 玻璃必须与同一容器内的其他玻璃元素同组，这里单独成组（输入框内没有别的玻璃）
            RoundedRectangle(cornerRadius: 24)
                .fill(DS.Colors.inputFill.opacity(0.55))
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
    }
}

// MARK: - 开关胶囊

private struct TogglePill: View {
    @Binding var isOn: Bool
    let systemImage: String
    let title: String
    var help: String
    @State private var hovered = false

    var body: some View {
        Button {
            withAnimation(DS.Motion.fastEase) { isOn.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                Text(title)
                    .font(DS.Typography.body)
            }
            .foregroundStyle(isOn ? DS.Colors.brandText : DS.Colors.labelSecondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
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
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
