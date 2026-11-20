import SwiftUI
import UniformTypeIdentifiers

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
    /// 是否跟随到底部：用户向上滑后置 false，避免流式生成时抢滚动
    @State private var followBottom = true
    @State private var lastAutoScroll = Date.distantPast
    @State private var showFileImporter = false
    @State private var uploader = FileUploader()

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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // 距底部还有多远（>0 表示已经离开底部）
                geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
            } action: { _, distanceFromBottom in
                let atBottom = distanceFromBottom < 40
                if atBottom != followBottom {
                    followBottom = atBottom
                }
            }
            .onChange(of: scrollSignature) { _, _ in
                guard followBottom else { return }
                // 流式期间节流，避免每个 token 都触发一次滚动导致卡顿
                let now = Date()
                guard now.timeIntervalSince(lastAutoScroll) > 0.08 else { return }
                lastAutoScroll = now
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                if !followBottom {
                    Button {
                        followBottom = true
                        withAnimation(DS.Motion.fastEase) {
                            proxy.scrollTo(bottomAnchor, anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.labelSecondary)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle()
                                    .fill(DS.Colors.bgBase.opacity(0.92))
                                    .glassEffect(.regular.interactive(), in: .circle)
                            }
                            .overlay {
                                Circle().strokeBorder(DS.Colors.borderL2, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("回到最新")
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var canSend: Bool {
        let hasText = !(session?.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasFiles = session?.draftAttachments.contains { $0.state == .ready } ?? false
        return hasText || hasFiles
    }

    private func retryAttachment(_ id: String) {
        guard let item = session?.draftAttachments.first(where: { $0.id == id }),
              let path = item.localPath else { return }
        store.updateDraftAttachment(id, in: sessionID) { $0.retrying() }
        AttachmentIngest.ingest(
            [URL(fileURLWithPath: path)],
            settings: settings,
            uploader: uploader,
            add: { _ in },
            update: { uploaded in
                store.updateDraftAttachment(id, in: sessionID) { _ in uploaded }
            }
        )
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
            canSend: canSend,
            onSend: { _ = store.send(text: session?.draft ?? "",
                                      attachments: session?.draftAttachments ?? [],
                                      in: sessionID) },
            onStop: { store.stop(sessionID: sessionID) },
            onAttach: { showFileImporter = true },
            attachments: session?.draftAttachments ?? [],
            attachmentProgress: store.uploadProgress,
            onRemoveAttachment: { store.removeDraftAttachment($0, in: sessionID) },
            onRetryAttachment: { retryAttachment($0) }
        )
        .padding(.horizontal, DS.Metrics.messageListPadding)
        .frame(maxWidth: DS.Metrics.messageListMaxWidth)
        .centeredColumn()
        .padding(.bottom, 16)
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
                    add: { store.addDraftAttachment($0, in: sessionID) },
                    update: { item in
                        store.updateDraftAttachment(item.id, in: sessionID) { _ in item }
                    }
                )
            }
        }
    }
}
