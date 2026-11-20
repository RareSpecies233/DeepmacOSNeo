import SwiftUI
import UniformTypeIdentifiers

/// 新对话欢迎页：问候语 + 居中输入框
struct WelcomeView: View {
    @Bindable var store: ChatStore
    @Bindable var settings: AppSettings
    @State private var text = ""
    @State private var attachments: [FileAttachment] = []
    @State private var showFileImporter = false
    @State private var uploader = FileUploader()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 21) {
                // 原版 Welcome.module.css：24/32、600、下边距 21
                Text(L10n.t(.welcomeMessageChat250808))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .multilineTextAlignment(.center)

                ComposerView(
                    text: $text,
                    thinking: Binding(get: { settings.thinking }, set: { settings.thinking = $0 }),
                    search: Binding(get: { settings.search }, set: { settings.search = $0 }),
                    isStreaming: false,
                    canSend: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || attachments.contains { $0.state == .ready },
                    onSend: send,
                    onStop: {},
                    onAttach: { showFileImporter = true },
                    isHome: true,
                    attachments: attachments,
                    onRemoveAttachment: { id in attachments.removeAll { $0.id == id } },
                    onRetryAttachment: retry
                )
            }
            // 原版：容器 max-width 840（含 padding 0 32px）→ 输入框 776
            .padding(.horizontal, 32)
            .frame(maxWidth: DS.Metrics.messageListMaxWidth)
            Spacer(minLength: 0)
            Text(L10n.t(.contentCaveat))
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.labelCaption)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.bgBase)
        .onAppear { focused = true }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                AttachmentIngest.ingest(
                    urls,
                    settings: settings,
                    uploader: uploader,
                    add: { attachments.append($0) },
                    update: { item in
                        if let index = attachments.firstIndex(where: { $0.id == item.id }) {
                            attachments[index] = item
                        }
                    }
                )
            }
        }
    }

    private func retry(_ id: String) {
        guard let item = attachments.first(where: { $0.id == id }),
              let path = item.localPath else { return }
        if let index = attachments.firstIndex(where: { $0.id == id }) {
            attachments[index] = item.retrying()
        }
        AttachmentIngest.ingest(
            [URL(fileURLWithPath: path)],
            settings: settings,
            uploader: uploader,
            add: { _ in },
            update: { uploaded in
                if let index = attachments.firstIndex(where: { $0.id == id }) {
                    attachments[index] = uploaded
                }
            }
        )
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.sendNewConversation(text: trimmed,
                                  attachments: attachments.filter { $0.state == .ready })
        text = ""
        attachments = []
    }
}
