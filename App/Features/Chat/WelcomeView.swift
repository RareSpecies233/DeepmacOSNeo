import SwiftUI

/// 新对话欢迎页：问候语 + 居中输入框
struct WelcomeView: View {
    @Bindable var store: ChatStore
    @Bindable var settings: AppSettings
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 28) {
                Text("今天有什么可以帮到你？")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .multilineTextAlignment(.center)

                ComposerView(
                    text: $text,
                    thinking: Binding(get: { settings.thinking }, set: { settings.thinking = $0 }),
                    search: Binding(get: { settings.search }, set: { settings.search = $0 }),
                    isStreaming: false,
                    canSend: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onSend: send,
                    onStop: {},
                    isHome: true
                )
                .frame(maxWidth: 720)
            }
            .frame(maxWidth: DS.Metrics.messageListMaxWidth)
            .padding(.horizontal, 44)
            Spacer(minLength: 0)
            Text("内容由 AI 生成，请仔细甄别")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.labelCaption)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.bgBase)
        .onAppear { focused = true }
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.sendNewConversation(text: trimmed)
        text = ""
    }
}
