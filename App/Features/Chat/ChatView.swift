import SwiftUI

/// 会话主视图：消息列表 + 底部输入框
struct ChatView: View {
    @Bindable var store: ChatStore
    @Bindable var settings: AppSettings
    let sessionID: UUID
    var showsHeader: Bool = true
    var onShowSidebar: (() -> Void)?

    private var session: ChatSession? { store.session(sessionID) }
    private var isStreaming: Bool { store.isStreaming(sessionID) }

    private let bottomAnchor = "chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            if showsHeader { mobileHeader }
            #endif
            messageList
            composer
        }
        .background(DS.Colors.bgBase)
    }

    // MARK: 移动端顶栏

    #if os(iOS)
    private var mobileHeader: some View {
        HStack(spacing: 8) {
            Button { onShowSidebar?() } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)

            Text(session?.displayTitle ?? "")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.labelPrimary)
                .lineLimit(1)
            Spacer()
            Button { _ = store.newSession() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .frame(height: 44)
    }
    #endif

    // MARK: 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let messages = session?.messages {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            MessageRow(
                                message: message,
                                isStreaming: message.status == .streaming,
                                isLastAssistant: index == messages.count - 1 && message.role == .assistant,
                                onRegenerate: { store.regenerate(sessionID: sessionID) }
                            )
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, DS.Metrics.messageListPadding)
                .padding(.top, 24)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: DS.Metrics.messageListMaxWidth)
            .centeredColumn()
            .onChange(of: scrollSignature) { _, _ in
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    /// 用于触发滚动的轻量签名：消息条数 + 末条内容长度
    private var scrollSignature: Int {
        guard let last = session?.messages.last else { return 0 }
        return (session?.messages.count ?? 0) * 100_000 + last.plainText.count + last.blocks.count
    }

    // MARK: 输入框

    private var composer: some View {
        ComposerView(
            text: Binding(
                get: { session?.draft ?? "" },
                set: { store.updateDraft(sessionID, text: $0) }
            ),
            thinking: Binding(
                get: { session?.thinking ?? true },
                set: { store.setThinking(sessionID, $0) }
            ),
            search: Binding(
                get: { session?.search ?? true },
                set: { store.setSearch(sessionID, $0) }
            ),
            isStreaming: isStreaming,
            canSend: !(session?.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            onSend: { _ = store.send(text: session?.draft ?? "", in: sessionID) },
            onStop: { store.stop(sessionID: sessionID) }
        )
        .padding(.horizontal, DS.Metrics.messageListPadding)
        .frame(maxWidth: DS.Metrics.messageListMaxWidth)
        .centeredColumn()
        .padding(.bottom, 16)
    }
}
