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
    /// 刚发送消息后的短暂「强制跟随」窗口：期间忽略几何回调把 followBottom 置 false，
    /// 否则新消息把内容撑高会被判成"用户离开了底部"，第二次回答就不再自动滚动。
    @State private var pinUntil = Date.distantPast
    @State private var showFileImporter = false
    @State private var uploader = FileUploader()
    @State private var editingDraft: EditDraft?
    /// 文件正被拖到窗口上（用于整页蒙层与输入框高亮）
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            if showsHeader { mobileHeader }
            #endif
            messageList
            composer
        }
        .background(DS.Colors.bgBase)
        .fileDropTarget(isTargeted: $isDropTargeted) { urls in
            addDroppedFiles(urls)
        }
        .sheet(item: $editingDraft) { draft in
            EditMessageSheet(initialText: draft.text) {
                editingDraft = nil
            } onResend: { text in
                if store.editAndResend(sessionID: sessionID, messageID: draft.id, text: text) {
                    editingDraft = nil
                }
            }
        }
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
                    if let session {
                        let messages = Branching.visibleMessages(in: session)
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            MessageRow(
                                message: message,
                                isStreaming: message.status == .streaming,
                                isLastAssistant: index == messages.count - 1 && message.role == .assistant,
                                version: Branching.versionInfo(for: message.id, in: session),
                                versionSwitchDisabled: isStreaming,
                                onSelectVersion: { store.selectVersion($0, in: sessionID) },
                                onRegenerate: { store.regenerate(sessionID: sessionID) },
                                onEditUserMessage: message.role == .user && !isStreaming
                                    ? { editingDraft = EditDraft(id: message.id, text: message.plainText) }
                                    : nil,
                                // 流式生成中不给分叉入口：此时消息还不完整。
                                onFork: isStreaming
                                    ? nil
                                    : { _ = store.fork(sessionID: sessionID, after: message.id) }
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
                guard Date() >= pinUntil else { return }
                // 阈值给足：内容内边距、圆角与安全区都会被算进 contentSize，
                // 阈值过小会在明明贴底时误判为"已离开底部"。
                let atBottom = distanceFromBottom < 200
                if atBottom != followBottom {
                    followBottom = atBottom
                }
            }
            .onChange(of: messageCount) { oldValue, newValue in
                // 用户发出一条消息（消息数增加且末条是用户消息）→ 强制跟随到最新
                guard newValue > oldValue,
                      session?.messages.last?.role == .user else { return }
                pinUntil = Date().addingTimeInterval(2.5)
                followBottom = true
                lastAutoScroll = .distantPast
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: scrollSignature) { _, _ in
                guard followBottom || Date() < pinUntil else { return }
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

    /// 统一口径（与 WelcomeView 一致）：有文字**或**有 `.ready` 附件，且不在流式生成中。
    private var canSend: Bool {
        let hasText = !(session?.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasFiles = session?.draftAttachments.contains { $0.state == .ready } ?? false
        return (hasText || hasFiles) && !isStreaming
    }

    /// 拖拽落入的文件：与「选择文件」走同一条 `AttachmentIngest` 编排。
    /// 读不到内容（无权限 / 已移动）由上传层置为失败态，UI 显示并可重试。
    private func addDroppedFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
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

    private var messageCount: Int { session?.messages.count ?? 0 }

    /// 用于触发滚动的轻量签名：可见消息条数 + 末条内容长度
    private var scrollSignature: Int {
        guard let session else { return 0 }
        let messages = Branching.visibleMessages(in: session)
        guard let last = messages.last else { return 0 }
        return messages.count * 100_000 + last.plainText.count + last.blocks.count
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
            model: Binding(
                get: { session?.model ?? settings.model },
                set: { store.setModel(sessionID, $0) }
            ),
            reasoningEffort: Binding(
                get: { settings.reasoningEffort },
                set: { settings.reasoningEffort = $0 }
            ),
            isStreaming: isStreaming,
            canSend: canSend,
            onSend: { _ = store.send(text: session?.draft ?? "",
                                      attachments: (session?.draftAttachments ?? []).filter { $0.state == .ready },
                                      in: sessionID) },
            onStop: { store.stop(sessionID: sessionID) },
            onAttach: { showFileImporter = true },
            attachments: session?.draftAttachments ?? [],
            attachmentProgress: store.uploadProgress,
            onRemoveAttachment: { store.removeDraftAttachment($0, in: sessionID) },
            onRetryAttachment: { retryAttachment($0) },
            isDropTargeted: isDropTargeted
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

// MARK: - 编辑用户消息

/// 当前正在编辑的用户消息（用于 `.sheet(item:)`）。
private struct EditDraft: Identifiable {
    /// 被编辑的 user 消息 id。
    let id: String
    let text: String
}

/// 编辑并重新发送的弹窗。确认后由 ChatStore 截断后续消息并自动重新请求。
private struct EditMessageSheet: View {
    let onCancel: () -> Void
    let onResend: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(initialText: String, onCancel: @escaping () -> Void, onResend: @escaping (String) -> Void) {
        self.onCancel = onCancel
        self.onResend = onResend
        _text = State(initialValue: initialText)
    }

    private var canResend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑并重新发送")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.labelPrimary)

            Text("确认后会截断这条消息之后的对话（含历史版本），并重新请求回答。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.Typography.userBody)
                .lineLimit(3...8)
                .focused($focused)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.m)
                        .fill(DS.Colors.inputFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.m)
                        .strokeBorder(DS.Colors.borderL2, lineWidth: 1)
                }

            HStack(spacing: 8) {
                Spacer()
                Button("取消", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("重新发送") { onResend(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canResend)
            }
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(DS.Colors.bgBase)
        .onAppear { focused = true }
    }
}
