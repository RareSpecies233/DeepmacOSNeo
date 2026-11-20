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
            "删除这个对话？",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = confirmDelete { store.delete(id) }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            // 给窗口红绿灯留出空间
            Color.clear.frame(width: 66, height: 1)
            #endif
            Text("API 使用 demo")
                .font(DS.Typography.bodyMedium)
                .foregroundStyle(DS.Colors.labelPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let onCollapse {
                IconAction(systemName: "sidebar.left", help: "收起边栏", action: onCollapse)
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
                Text("开启新对话")
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
                    Text(group.label)
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

    // MARK: 底部

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.Colors.borderL1)
            Button(action: onOpenSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                    Text("设置")
                        .font(DS.Typography.body)
                    Spacer(minLength: 6)
                    if settings.showsBalance {
                        Text(balance.displayText ?? (balance.isLoading ? "查询余额…" : "—"))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.labelTertiary)
                            .lineLimit(1)
                            .help(balance.lastError ?? "账户余额")
                    }
                    Circle()
                        .fill(settings.hasAPIKey ? Color.green.opacity(0.85) : DS.Colors.labelTertiary.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .help(settings.hasAPIKey ? "已配置 API Key" : "未配置 API Key")
                }
                .foregroundStyle(DS.Colors.labelSecondary)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Toggle("显示账户余额", isOn: Binding(
                    get: { settings.showsBalance },
                    set: { settings.showsBalance = $0 }
                ))
                Button("刷新余额") {
                    Task { await balance.refresh(settings: settings, force: true) }
                }
            }
            .task(id: settings.showsBalance) {
                if settings.showsBalance { await balance.refresh(settings: settings) }
            }
            .task(id: settings.apiKey) {
                if settings.showsBalance { await balance.refresh(settings: settings, force: true) }
            }
        }
    }

    private var sidebarBackground: some View {
        ZStack {
            #if os(macOS)
            // 窗口透明 + 原生侧栏材质：模糊后方内容，保证长文阅读时的可读性
            if reduceTransparency {
                DS.Colors.sidebarFill
            } else {
                VisualEffectBackground(material: .sidebar, blending: .withinWindow)
                DS.Colors.sidebarFill.opacity(0.55)
            }
            #else
            DS.Colors.sidebarFill
            #endif
        }
        .ignoresSafeArea()
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
}

// MARK: - 分组

struct SessionGroup: Identifiable {
    let id: String
    let label: String
    var sessions: [ChatSession]

    static func group(_ sessions: [ChatSession], now: Date) -> [SessionGroup] {
        let calendar = Calendar.current
        var groups: [SessionGroup] = []
        let today = calendar.startOfDay(for: now)

        for session in sessions {
            let day = calendar.startOfDay(for: session.updatedAt)
            let diff = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let key: String
            let label: String
            switch diff {
            case ..<1: (key, label) = ("today", "今天")
            case 1: (key, label) = ("yesterday", "昨天")
            case 2..<7: (key, label) = ("week", "7 天内")
            case 7..<30: (key, label) = ("month", "30 天内")
            default:
                let comps = calendar.dateComponents([.year, .month], from: session.updatedAt)
                key = "m-\(comps.year ?? 0)-\(comps.month ?? 0)"
                label = "\(comps.year ?? 0) 年 \(comps.month ?? 0) 月"
            }
            if groups.last?.id == key {
                groups[groups.count - 1].sessions.append(session)
            } else {
                groups.append(SessionGroup(id: key, label: label, sessions: [session]))
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
                TextField("对话名称", text: $renameText)
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
                        Button("重命名", action: onBeginRename)
                        Button(session.pinned ? "取消置顶" : "置顶", action: onPin)
                        Divider()
                        Button("删除", role: .destructive, action: onDelete)
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
            Button("重命名", action: onBeginRename)
            Button(session.pinned ? "取消置顶" : "置顶", action: onPin)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
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
