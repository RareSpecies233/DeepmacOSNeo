import SwiftUI

/// 展开的侧边栏：名称 + 收起按钮、开启新对话、按时间分组的会话列表、底部设置
struct SiderView: View {
    @Bindable var store: ChatStore
    @Bindable var settings: AppSettings
    var onOpenSettings: () -> Void
    var onCollapse: (() -> Void)?
    var onSelect: (UUID) -> Void
    /// 移动端抽屉需要关闭；桌面端为 nil
    var onNewChat: (() -> Void)?

    @State private var renaming: UUID?
    @State private var renameText: String = ""
    @State private var hovered: UUID?
    @State private var confirmDelete: UUID?
    @State private var now = Date.now
    @State private var balance = BalanceStore.shared
    @Environment(\.scenePhase) private var scenePhase

    private var groups: [SessionGroup] { SessionGroup.group(store.sortedSessions, now: now) }

    var body: some View {
        VStack(spacing: 0) {
            header
            newChatButton
            sessionList
            footer
        }
        .frame(width: DS.Metrics.sidebarWidth)
        .background(sidebarBackground)
        .confirmationDialog(
            L10n.t(.deleteSessionConfirmTitle),
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t(.delete), role: .destructive) {
                if let id = confirmDelete { store.delete(id) }
                confirmDelete = nil
            }
            Button(L10n.t(.cancel), role: .cancel) { confirmDelete = nil }
        } message: {
            Text(L10n.t(.deleteSessionConfirmMessage))
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            // 给窗口红绿灯留出空间
            Color.clear.frame(width: 66, height: 1)
            #endif
            Text(L10n.t(.appName))
                .font(DS.Typography.bodyMedium)
                .foregroundStyle(DS.Colors.labelPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let onCollapse {
                IconAction(systemName: "sidebar.left", help: L10n.t(.collapseSiderbarButton), action: onCollapse)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .windowDragArea()
    }

    private var newChatButton: some View {
        Button {
            store.startNewConversation()
            onNewChat?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .regular))
                Text(L10n.t(.newChat))
                    .font(DS.Typography.bodyMedium)
            }
            .foregroundStyle(DS.Colors.labelPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                Capsule().fill(dyn(0xFFFFFF, 0x43454A))
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: 列表

    private var sessionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    Text(groupTitle(group))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.labelTertiary)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(group.sessions) { session in
                        SessionRow(
                            session: session,
                            isActive: session.id == store.activeID,
                            isHovered: hovered == session.id,
                            isRenaming: renaming == session.id,
                            renameText: $renameText,
                            onSelect: { onSelect(session.id) },
                            onDelete: { confirmDelete = session.id },
                            onPin: { store.togglePin(session.id) },
                            onBeginRename: {
                                renameText = session.displayTitle
                                renaming = session.id
                            },
                            onCommitRename: {
                                store.rename(session.id, to: renameText)
                                renaming = nil
                            }
                        )
                        .onHover { inside in hovered = inside ? session.id : nil }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
    }

    /// 分组标题：「今天 / 昨天 / 7 天内 / 30 天内」按 id 取文案；年-月按当前语言格式化。
    private func groupTitle(_ group: SessionGroup) -> String {
        if let date = group.monthDate {
            return date.formatted(
                .dateTime.year().month().locale(settings.language.locale)
            )
        }
        switch group.id {
        case "today": return L10n.t(.sessionHistoryTimelineLabelToday)
        case "yesterday": return L10n.t(.sessionHistoryTimelineLabelYesterday)
        case "week": return L10n.t(.sessionHistoryTimelineLabel7days)
        case "month": return L10n.t(.sessionHistoryTimelineLabel30days)
        default: return group.id
        }
    }

    // MARK: 底部

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.Colors.borderL1)
            Button(action: onOpenSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                    Text(L10n.t(.settings))
                        .font(DS.Typography.body)
                    Spacer(minLength: 6)
                    if settings.showsBalance {
                        Text(balance.displayText ?? (balance.isLoading ? L10n.t(.balanceLoading) : "—"))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.labelTertiary)
                            .lineLimit(1)
                            .help(balance.lastError ?? L10n.t(.accountBalance))
                    }
                    Circle()
                        .fill(settings.hasAPIKey ? Color.green.opacity(0.85) : DS.Colors.labelTertiary.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .help(settings.hasAPIKey ? L10n.t(.apiKeyConfigured) : L10n.t(.apiKeyNotConfigured))
                }
                .foregroundStyle(DS.Colors.labelSecondary)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Toggle(L10n.t(.showBalance), isOn: Binding(
                    get: { settings.showsBalance },
                    set: { settings.showsBalance = $0 }
                ))
                Button(L10n.t(.refreshBalance)) {
                    Task { await balance.refresh(settings: settings, force: true) }
                }
            }
            .task(id: settings.showsBalance) {
                if settings.showsBalance { await balance.refresh(settings: settings) }
            }
            .task(id: settings.apiKey) {
                if settings.showsBalance { await balance.refresh(settings: settings, force: true) }
            }
            // 余额是动态的：每 90 秒静默刷新一次；回到前台立即刷新一次。
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(90))
                    guard settings.showsBalance else { continue }
                    await balance.refresh(settings: settings, force: true)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, settings.showsBalance else { return }
                Task { await balance.refresh(settings: settings, force: true) }
            }
        }
    }

    private var sidebarBackground: some View {
        // 与原版一致：侧栏是实色面（亮 #F9FAFB / 暗 #1B1B1C）。
        // 之前叠加系统材质会把深色侧栏抬亮到 #272727，并在接缝处形成一条亮缝。
        DS.Colors.sidebarFill
            .ignoresSafeArea()
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
}

// MARK: - 分组

struct SessionGroup: Identifiable {
    let id: String
    /// 年-月分组的日期，标题按当前语言格式化；今天/昨天等分组为 nil，按 id 取文案
    let monthDate: Date?
    var sessions: [ChatSession]

    static func group(_ sessions: [ChatSession], now: Date) -> [SessionGroup] {
        let calendar = Calendar.current
        var groups: [SessionGroup] = []
        let today = calendar.startOfDay(for: now)

        for session in sessions {
            let day = calendar.startOfDay(for: session.updatedAt)
            let diff = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let key: String
            var monthDate: Date?
            switch diff {
            case ..<1: key = "today"
            case 1: key = "yesterday"
            case 2..<7: key = "week"
            case 7..<30: key = "month"
            default:
                let comps = calendar.dateComponents([.year, .month], from: session.updatedAt)
                key = "m-\(comps.year ?? 0)-\(comps.month ?? 0)"
                monthDate = calendar.date(from: comps)
            }
            if groups.last?.id == key {
                groups[groups.count - 1].sessions.append(session)
            } else {
                groups.append(SessionGroup(id: key, monthDate: monthDate, sessions: [session]))
            }
        }
        return groups
    }
}

// MARK: - 行

private struct SessionRow: View {
    let session: ChatSession
    let isActive: Bool
    let isHovered: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onPin: () -> Void
    var onBeginRename: () -> Void
    var onCommitRename: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isRenaming {
                TextField(L10n.t(.sessionName), text: $renameText)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.body)
                    .onSubmit(onCommitRename)
            } else {
                Text(session.displayTitle)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.labelPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if session.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Colors.labelTertiary)
                }
                if isHovered {
                    Menu {
                        Button(L10n.t(.sessionItemMenuRenameOption), action: onBeginRename)
                        Button(session.pinned ? L10n.t(.unpin) : L10n.t(.pin), action: onPin)
                        Divider()
                        Button(L10n.t(.delete), role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Colors.labelTertiary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m)
                .fill(isActive ? DS.Colors.sidebarActive : (isHovered ? DS.Colors.interactiveHover : .clear))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(L10n.t(.sessionItemMenuRenameOption), action: onBeginRename)
            Button(session.pinned ? L10n.t(.unpin) : L10n.t(.pin), action: onPin)
            Divider()
            Button(L10n.t(.delete), role: .destructive, action: onDelete)
        }
    }
}

// MARK: - 小图标按钮（本文件局部实现，后续可换 DS 组件）

private struct IconAction: View {
    let systemName: String
    var help: String
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15))
                .foregroundStyle(DS.Colors.labelSecondary)
                .frame(width: 28, height: 28)
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
