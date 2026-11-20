import Foundation

// MARK: - 消息版本组

/// 同一轮提问下的多个 assistant 回答版本。
///
/// 在 `ChatSession.variantGroups` 里，键是「锚点」：该轮 assistant 回复之前那条
/// user 消息的 id；值按创建顺序保存该轮所有回答的消息 id。
///
/// 设计约束：`ChatSession.variantGroups` 必须是 Optional。合成的 Codable 对非可选
/// 字段会用 `decode`（而不是 `decodeIfPresent`），旧版 sessions.json 缺这个 key
/// 会抛错，而 `ChatStore.load()` 里的 `try?` 会静默丢掉全部会话。
struct VariantGroup: Codable, Hashable, Sendable {
    /// 该轮回答的所有版本，按创建顺序排列。
    var messageIDs: [String]
    /// 当前选中的版本下标（0-based），越界时由 `Branching` 回退到最后一个。
    var selected: Int

    init(messageIDs: [String], selected: Int) {
        self.messageIDs = messageIDs
        self.selected = selected
    }
}

// MARK: - 分支纯函数

/// 消息分支的纯函数集合：不触碰存储，方便在 Store 与渲染层复用同一套语义。
///
/// 旧会话没有 `variantGroups`，以下所有函数都退化为「原样返回线性消息列表」，
/// 行为与加分支之前完全一致。
enum Branching {

    /// 单条消息的版本信息，供 UI 渲染 `‹ 2/3 ›`。
    struct VersionInfo: Equatable, Sendable {
        let ids: [String]
        /// 当前消息在版本组里的下标（0-based）。
        let index: Int

        init?(ids: [String], index: Int) {
            guard ids.indices.contains(index) else { return nil }
            self.ids = ids
            self.index = index
        }

        var count: Int { ids.count }
        /// 展示用下标（1-based）。
        var displayIndex: Int { index + 1 }
        var currentID: String { ids[index] }
        var previousID: String? { index > 0 ? ids[index - 1] : nil }
        var nextID: String? { index + 1 < ids.count ? ids[index + 1] : nil }
    }

    /// 版本组里合法选中的下标；空组返回 nil。
    static func selectedIndex(of group: VariantGroup) -> Int? {
        guard !group.messageIDs.isEmpty else { return nil }
        return min(max(group.selected, 0), group.messageIDs.count - 1)
    }

    /// 渲染与请求共用的可见消息：每个版本组只保留当前选中的那条。
    ///
    /// 未分组的消息（以及没有 `variantGroups` 的旧会话）全部保留，顺序不变。
    static func visibleMessages(in session: ChatSession) -> [ChatMessage] {
        guard let groups = session.variantGroups, !groups.isEmpty else { return session.messages }

        var hidden = Set<String>()
        for group in groups.values {
            guard let selected = selectedIndex(of: group) else { continue }
            for (offset, id) in group.messageIDs.enumerated() where offset != selected {
                hidden.insert(id)
            }
        }
        guard !hidden.isEmpty else { return session.messages }
        return session.messages.filter { !hidden.contains($0.id) }
    }

    /// 某条消息所属版本组的展示信息；不在任何版本组里时返回 nil（不显示切换器）。
    static func versionInfo(for messageID: String, in session: ChatSession) -> VersionInfo? {
        guard let groups = session.variantGroups, !groups.isEmpty else { return nil }
        for group in groups.values {
            if let index = group.messageIDs.firstIndex(of: messageID) {
                return VersionInfo(ids: group.messageIDs, index: index)
            }
        }
        return nil
    }

    /// 某条 assistant 消息的锚点：它之前最近的一条 user 消息 id。
    static func anchorID(forAssistantAt index: Int, in messages: [ChatMessage]) -> String? {
        guard messages.indices.contains(index), messages[index].role == .assistant else { return nil }
        var cursor = index - 1
        while cursor >= 0 {
            if messages[cursor].role == .user { return messages[cursor].id }
            cursor -= 1
        }
        return nil
    }

    /// 重新生成时登记新版本：第一次把原消息纳入 `[oldID, newID]` 并选中新版本；
    /// 之后在同一组里追加并选中。
    static func registerVersion(
        _ newID: String,
        replacing oldID: String,
        anchorID: String,
        in groups: [String: VariantGroup]?
    ) -> [String: VariantGroup] {
        var updated = groups ?? [:]
        if var group = updated[anchorID] {
            // 防御脏数据：当前选中的回答理论上一定在组里，缺失时补上再追加。
            if !group.messageIDs.contains(oldID) {
                group.messageIDs.append(oldID)
            }
            group.messageIDs.append(newID)
            group.selected = group.messageIDs.count - 1
            updated[anchorID] = group
        } else {
            updated[anchorID] = VariantGroup(messageIDs: [oldID, newID], selected: 1)
        }
        return updated
    }

    /// 截断消息后裁剪版本组：锚点被编辑/删除的组、以及引用了被删除消息的组整体丢弃。
    static func prune(
        _ groups: [String: VariantGroup]?,
        removingMessageIDs removed: Set<String>,
        anchorIDs: Set<String> = []
    ) -> [String: VariantGroup]? {
        guard let groups, !groups.isEmpty else { return groups }

        var result: [String: VariantGroup] = [:]
        for (anchor, group) in groups {
            guard !anchorIDs.contains(anchor) else { continue }
            // 版本组必须完整存活：只要引用了被截断的消息就整组丢弃，
            // 否则选中下标会指向已不存在的消息。
            guard !group.messageIDs.contains(where: removed.contains) else { continue }
            result[anchor] = group
        }
        return result.isEmpty ? nil : result
    }
}
