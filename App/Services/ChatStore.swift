import Foundation
import Observation
import SwiftUI

// MARK: - 会话模型（UI 层，持久化用 Codable JSON）

struct ChatSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var pinned: Bool = false
    var model: String = "deepseek-flash"
    var thinking: Bool = true
    var search: Bool = true
    var draft: String = ""
    var messages: [ChatMessage] = []
    /// 注意：必须是 Optional。合成 Codable 对非可选字段会用 decode（而非 decodeIfPresent），
    /// 旧版本 sessions.json 缺这个 key 会直接抛错，load() 里的 try? 会静默清空全部会话。
    var pendingAttachments: [FileAttachment]?
    /// 同一轮回答的多版本。键 = 该轮 assistant 回复之前那条 user 消息的 id。
    /// 同样必须是 Optional：旧数据没有这个 key 时行为与线性会话完全一致。
    var variantGroups: [String: VariantGroup]?

    var draftAttachments: [FileAttachment] { pendingAttachments ?? [] }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "新对话" : trimmed
    }

    var lastUserText: String {
        messages.last(where: { $0.role == .user })?.plainText ?? ""
    }
}

// MARK: - 流式上下文

@MainActor
final class StreamContext {
    let sessionID: UUID
    let messageID: String
    var accumulator: StreamAccumulator
    var task: Task<Void, Never>?
    var startedAt: Date = .now
    var titleFromServer: String?

    init(sessionID: UUID, messageID: String, accumulator: StreamAccumulator) {
        self.sessionID = sessionID
        self.messageID = messageID
        self.accumulator = accumulator
    }
}

// MARK: - 会话存储

@MainActor
@Observable
final class ChatStore {

    static let shared = ChatStore()

    private(set) var sessions: [ChatSession] = []
    private(set) var activeID: UUID?
    private(set) var streamingSessionIDs: Set<UUID> = []
    private(set) var lastError: String?
    private var streams: [UUID: StreamContext] = [:]

    private let settings: AppSettings
    private let storeURL: URL
    private var saveTask: Task<Void, Never>?

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.storeURL = Self.makeStoreURL()
        load()
        // 清理历史遗留的空会话（旧版本会点一次就建一个）
        let before = sessions.count
        sessions.removeAll { $0.messages.isEmpty && $0.draft.isEmpty && $0.title.isEmpty }
        if sessions.count != before { scheduleSave(debounce: 0) }
        if activeID == nil { activeID = sessions.first?.id }
    }

    // MARK: 派生

    var activeSession: ChatSession? {
        guard let activeID else { return nil }
        return sessions.first { $0.id == activeID }
    }

    var sortedSessions: [ChatSession] {
        sessions.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func isStreaming(_ id: UUID) -> Bool { streamingSessionIDs.contains(id) }

    func session(_ id: UUID) -> ChatSession? { sessions.first { $0.id == id } }

    func index(of id: UUID) -> Int? { sessions.firstIndex { $0.id == id } }

    // MARK: 消息版本

    /// 当前可见的消息：每个版本组只保留选中的那条，渲染与请求历史共用。
    func visibleMessages(in sessionID: UUID) -> [ChatMessage] {
        guard let session = session(sessionID) else { return [] }
        return Branching.visibleMessages(in: session)
    }

    /// 某条消息的版本信息；不在任何版本组里时为 nil。
    func versionInfo(for messageID: String, in sessionID: UUID) -> Branching.VersionInfo? {
        guard let session = session(sessionID) else { return nil }
        return Branching.versionInfo(for: messageID, in: session)
    }

    /// 切换到某个版本。只改选中下标，不删除任何历史版本。
    func selectVersion(_ messageID: String, in sessionID: UUID) {
        guard let i = index(of: sessionID), !isStreaming(sessionID),
              let groups = sessions[i].variantGroups else { return }
        for (anchor, group) in groups {
            guard let position = group.messageIDs.firstIndex(of: messageID),
                  position != group.selected else { continue }
            sessions[i].variantGroups?[anchor]?.selected = position
            scheduleSave()
            return
        }
    }

    // MARK: 会话操作

    /// 点「开启新对话」只清空选择，真正建会话发生在第一条消息发送时。
    func startNewConversation() {
        activeID = nil
    }

    /// 从欢迎页发第一条消息：此时才创建会话。
    @discardableResult
    func sendNewConversation(text: String, attachments: [FileAttachment] = []) -> Bool {
        let id = newSession()
        return send(text: text, attachments: attachments, in: id)
    }

    @discardableResult
    func newSession(select: Bool = true) -> UUID {
        let session = ChatSession(model: settings.model, thinking: settings.thinking, search: settings.search)
        sessions.insert(session, at: 0)
        if select { activeID = session.id }
        scheduleSave()
        return session.id
    }

    func select(_ id: UUID?) {
        activeID = id
    }

    func delete(_ id: UUID) {
        stopStreaming(for: id)
        sessions.removeAll { $0.id == id }
        if activeID == id { activeID = sessions.first?.id }
        scheduleSave()
    }

    func deleteAll() {
        for id in sessions.map(\.id) { stopStreaming(for: id) }
        sessions.removeAll()
        activeID = nil
        scheduleSave()
    }

    func rename(_ id: UUID, to title: String) {
        guard let i = index(of: id) else { return }
        sessions[i].title = String(title.prefix(80))
        sessions[i].updatedAt = .now
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let i = index(of: id) else { return }
        sessions[i].pinned.toggle()
        scheduleSave()
    }

    func updateDraft(_ id: UUID, text: String) {
        guard let i = index(of: id) else { return }
        sessions[i].draft = text
        scheduleSave(debounce: 0.8)
    }

    func setThinking(_ id: UUID, _ value: Bool) {
        guard let i = index(of: id) else { return }
        sessions[i].thinking = value
        scheduleSave()
    }

    func setSearch(_ id: UUID, _ value: Bool) {
        guard let i = index(of: id) else { return }
        sessions[i].search = value
        scheduleSave()
    }

    func setModel(_ id: UUID, _ model: String) {
        guard let i = index(of: id) else { return }
        sessions[i].model = model
        scheduleSave()
    }

    // MARK: 附件

    /// 上传进度（按附件 id），仅内存
    private(set) var uploadProgress: [String: Double] = [:]

    func setProgress(_ value: Double, for id: String) {
        uploadProgress[id] = value
    }

    func addDraftAttachment(_ attachment: FileAttachment, in sessionID: UUID) {
        guard let i = index(of: sessionID) else { return }
        var list = sessions[i].draftAttachments
        list.append(attachment)
        sessions[i].pendingAttachments = list
        scheduleSave()
    }

    func updateDraftAttachment(_ id: String, in sessionID: UUID, _ transform: (FileAttachment) -> FileAttachment) {
        guard let i = index(of: sessionID) else { return }
        var list = sessions[i].draftAttachments
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index] = transform(list[index])
        sessions[i].pendingAttachments = list
        if list[index].state != .uploading { uploadProgress[id] = nil }
        scheduleSave()
    }

    func removeDraftAttachment(_ id: String, in sessionID: UUID) {
        guard let i = index(of: sessionID) else { return }
        sessions[i].pendingAttachments = sessions[i].draftAttachments.filter { $0.id != id }
        uploadProgress[id] = nil
        scheduleSave()
    }

    // MARK: 发送

    @discardableResult
    func send(text: String, attachments: [FileAttachment] = [], in sessionID: UUID) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments.filter { $0.fileID != nil }
        guard !trimmed.isEmpty || !files.isEmpty,
              let i = index(of: sessionID), !isStreaming(sessionID) else { return false }
        guard let client = settings.client else {
            lastError = "接口地址无效"
            return false
        }

        var blocks: [Block] = []
        if !trimmed.isEmpty {
            blocks.append(Block(id: "u0", kind: .text, text: trimmed))
        }
        for (index, file) in files.enumerated() {
            blocks.append(Block(id: "f\(index)", kind: .file, attachment: file))
        }
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            blocks: blocks,
            createdAt: .now,
            status: .complete
        )
        sessions[i].messages.append(userMessage)

        let isFirstExchange = !sessions[i].messages.contains { $0.role == .assistant }
        if sessions[i].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sessions[i].title = Self.autoTitle(from: trimmed)
        }
        sessions[i].updatedAt = .now

        let assistantID = UUID().uuidString
        let placeholder = ChatMessage(
            id: assistantID,
            role: .assistant,
            blocks: [],
            createdAt: .now,
            status: .streaming,
            model: sessions[i].model
        )
        sessions[i].messages.append(placeholder)
        sessions[i].draft = ""
        sessions[i].pendingAttachments = nil

        let request = buildRequest(session: sessions[i], generateTitle: isFirstExchange)
        startStream(client: client, request: request, sessionID: sessionID, messageID: assistantID)
        scheduleSave()
        return true
    }

    /// 重新生成最后一条助手回复：旧回答保留为历史版本，新回答追加并选中。
    func regenerate(sessionID: UUID) {
        guard let i = index(of: sessionID), !isStreaming(sessionID) else { return }
        let messages = sessions[i].messages
        guard let last = messages.last, last.role == .assistant,
              let anchor = Branching.anchorID(forAssistantAt: messages.count - 1, in: messages) else { return }
        guard let client = settings.client else {
            lastError = "接口地址无效"
            return
        }

        let assistantID = UUID().uuidString
        sessions[i].variantGroups = Branching.registerVersion(
            assistantID,
            replacing: last.id,
            anchorID: anchor,
            in: sessions[i].variantGroups
        )
        sessions[i].messages.append(
            ChatMessage(id: assistantID, role: .assistant, blocks: [], createdAt: .now,
                        status: .streaming, model: sessions[i].model)
        )
        sessions[i].updatedAt = .now

        let request = buildRequest(session: sessions[i], generateTitle: false)
        startStream(client: client, request: request, sessionID: sessionID, messageID: assistantID)
        scheduleSave()
    }

    /// 从某条助手消息分叉：新会话保留该消息及其之前的全部上下文。
    @discardableResult
    func fork(sessionID: UUID, after messageID: String) -> UUID? {
        guard let i = index(of: sessionID) else { return nil }
        let source = sessions[i]
        guard let cut = source.messages.firstIndex(where: { $0.id == messageID }) else { return nil }

        var copy = ChatSession(
            title: String("\(source.displayTitle)（分支）".prefix(80)),
            model: source.model,
            thinking: source.thinking,
            search: source.search
        )
        copy.messages = Array(source.messages[...cut])
        copy.updatedAt = .now
        sessions.insert(copy, at: 0)
        activeID = copy.id
        scheduleSave()
        return copy.id
    }

    /// 编辑用户消息并重新请求：截断该消息之后的所有消息（含其版本组），
    /// 原地替换文本，然后自动发起新的回答。
    @discardableResult
    func editAndResend(sessionID: UUID, messageID: String, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = index(of: sessionID), !isStreaming(sessionID),
              let mi = sessions[i].messages.firstIndex(where: { $0.id == messageID }),
              sessions[i].messages[mi].role == .user else { return false }

        let original = sessions[i].messages[mi]
        let files = original.blocks.filter { $0.kind == .file }
        guard !trimmed.isEmpty || !files.isEmpty else { return false }
        guard let client = settings.client else {
            lastError = "接口地址无效"
            return false
        }

        // 1. 先裁剪版本组，再截断消息，避免留下指向已删除消息的下标。
        //    被编辑消息自己的版本组也一并丢弃（其回答都会被截断）。
        let removedIDs = Set(sessions[i].messages[(mi + 1)...].map(\.id))
        sessions[i].variantGroups = Branching.prune(
            sessions[i].variantGroups,
            removingMessageIDs: removedIDs,
            anchorIDs: [messageID]
        )

        // 2. 截断该消息之后的所有消息（含失效的版本与后续对话）。
        if mi + 1 < sessions[i].messages.count {
            sessions[i].messages.removeSubrange((mi + 1)...)
        }

        // 3. 原地替换文本，保留已上传附件。
        var blocks: [Block] = []
        if !trimmed.isEmpty {
            blocks.append(Block(id: "u0", kind: .text, text: trimmed))
        }
        blocks.append(contentsOf: files)
        sessions[i].messages[mi].blocks = blocks
        sessions[i].messages[mi].createdAt = .now

        // 4. 自动重新请求。
        let assistantID = UUID().uuidString
        sessions[i].messages.append(
            ChatMessage(id: assistantID, role: .assistant, blocks: [], createdAt: .now,
                        status: .streaming, model: sessions[i].model)
        )
        sessions[i].updatedAt = .now

        let request = buildRequest(session: sessions[i], generateTitle: false)
        startStream(client: client, request: request, sessionID: sessionID, messageID: assistantID)
        scheduleSave()
        return true
    }

    /// 继续生成被停止的回复
    func continueReply(sessionID: UUID) {
        guard let i = index(of: sessionID), !isStreaming(sessionID),
              let last = sessions[i].messages.last, last.role == .assistant else { return }
        guard let client = settings.client else { return }
        let assistantID = UUID().uuidString
        sessions[i].messages.append(
            ChatMessage(id: assistantID, role: .assistant, blocks: [], createdAt: .now,
                        status: .streaming, model: sessions[i].model)
        )
        let request = buildRequest(session: sessions[i], generateTitle: false)
        startStream(client: client, request: request, sessionID: sessionID, messageID: assistantID)
    }

    func stop(sessionID: UUID) {
        stopStreaming(for: sessionID)
    }

    // MARK: 流式实现

    private func startStream(client: DeepSeekClient, request: ChatRequest,
                             sessionID: UUID, messageID: String) {
        let accumulator = StreamAccumulator(id: messageID, model: request.model, createdAt: .now)
        let context = StreamContext(sessionID: sessionID, messageID: messageID, accumulator: accumulator)
        streams[sessionID] = context
        streamingSessionIDs.insert(sessionID)

        context.task = Task { [weak self] in
            let stream = client.stream(request)
            do {
                for try await event in stream {
                    guard let self, !Task.isCancelled else { break }
                    if self.streams[sessionID] === context {
                        context.accumulator.apply(event)
                        if case .messageDelta(_, let title) = event, let title, !title.isEmpty {
                            context.titleFromServer = title
                        }
                        self.sync(context)
                    }
                }
                guard let self, !Task.isCancelled else { return }
                if self.streams[sessionID] === context {
                    context.accumulator.finish(status: .complete)
                    self.sync(context, finalize: true)
                    self.applyServerTitle(context)
                    self.finishStream(sessionID: sessionID)
                }
            } catch {
                guard let self else { return }
                let wasCancelled = Task.isCancelled || (error as? CancellationError) != nil
                if self.streams[sessionID] === context {
                    if wasCancelled {
                        context.accumulator.finish(status: .stopped)
                    } else {
                        let message = (error as? DeepSeekError)?.errorDescription ?? error.localizedDescription
                        context.accumulator.finish(status: .failed, error: message)
                        self.lastError = message
                    }
                    self.sync(context, finalize: true)
                    self.finishStream(sessionID: sessionID)
                }
            }
        }
    }

    private func sync(_ context: StreamContext, finalize: Bool = false) {
        guard let i = index(of: context.sessionID),
              let mi = sessions[i].messages.firstIndex(where: { $0.id == context.messageID }) else { return }
        sessions[i].messages[mi] = context.accumulator.message
        if finalize { sessions[i].updatedAt = .now }
    }

    private func applyServerTitle(_ context: StreamContext) {
        guard let title = context.titleFromServer?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty, let i = index(of: context.sessionID) else { return }
        sessions[i].title = String(title.prefix(80))
        scheduleSave()
    }

    private func finishStream(sessionID: UUID) {
        streams[sessionID]?.task = nil
        streams[sessionID] = nil
        streamingSessionIDs.remove(sessionID)
        scheduleSave(debounce: 0.2)
        // 每轮结束刷新一次余额，配合侧栏的定时刷新实现"动态更新"
        Task { await BalanceStore.shared.refresh(settings: settings, force: true) }
    }

    private func stopStreaming(for sessionID: UUID) {
        guard let context = streams[sessionID] else { return }
        context.task?.cancel()
        context.accumulator.finish(status: .stopped)
        sync(context, finalize: true)
        streams[sessionID] = nil
        streamingSessionIDs.remove(sessionID)
        scheduleSave()
    }

    // MARK: 请求构造

    private func buildRequest(session: ChatSession, generateTitle: Bool) -> ChatRequest {
        var history: [RequestMessage] = []
        // 版本组只发送当前选中的回答；否则同一轮会出现多份上下文。
        // 旧会话没有 variantGroups 时 visibleMessages 原样返回 messages。
        for message in Branching.visibleMessages(in: session) {
            if message.role == .assistant && message.status == .streaming && message.blocks.isEmpty {
                continue // 跳过空占位
            }
            history.append(RequestMessage(role: message.role == .user ? .user : .assistant,
                                          blocks: message.blocks))
        }
        return ChatRequest(
            model: session.model,
            system: Self.systemPrompt,
            messages: history,
            thinking: session.thinking,
            thinkingBudget: session.thinking ? settings.reasoningEffort.budgetTokens : nil,
            search: session.search,
            readURL: true,
            titleGeneration: generateTitle
        )
    }

    // MARK: 持久化

    private static func makeStoreURL() -> URL {
        // 支持独立数据目录，便于 QA 与真实使用隔离（绝不触碰用户数据）
        if let custom = ProcessInfo.processInfo.environment["DEEPGLASS_STORE_DIR"], !custom.isEmpty {
            let dir = URL(fileURLWithPath: custom, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appending(path: "sessions.json")
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let dir = base.appending(path: "DeepGlass", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "sessions.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let payload = try? decoder.decode(StorePayload.self, from: data) {
            sessions = payload.sessions
            activeID = payload.activeID
        }
    }

    func scheduleSave(debounce: Double = 0.4) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(debounce))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let payload = StorePayload(sessions: sessions, activeID: activeID)
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private struct StorePayload: Codable {
        var sessions: [ChatSession]
        var activeID: UUID?
    }

    // MARK: 文案

    private static func autoTitle(from text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        return String(cleaned.prefix(24))
    }

    static let systemPrompt = DeepSeekDefaults.systemPrompt
}
