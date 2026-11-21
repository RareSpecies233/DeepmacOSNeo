import SwiftUI

struct RootView: View {
    @State private var store = ChatStore.shared
    @State private var settings = AppSettings.shared
    @State private var showSettings = false
    @State private var showSidebarSheet = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var showSidebarInline: Bool {
        !isCompact && !settings.sidebarCollapsed
    }

    var body: some View {
        main
            .configureWindowForGlass()
            .preferredColorScheme(settings.theme.colorScheme)
            .onAppear { AppearanceSync.apply(settings.theme) }
            .onChange(of: settings.theme) { _, newValue in AppearanceSync.apply(newValue) }
            .tint(DS.Colors.brandPrimary)
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings, onClearAll: { store.deleteAll() }, onClose: { showSettings = false })
            }
            .onReceive(NotificationCenter.default.publisher(for: .newSessionRequested)) { _ in
                store.startNewConversation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsRequested)) { _ in
                showSettings = true
            }
            .task {
                if CommandLine.arguments.contains("--dark") { settings.theme = .dark }
                if CommandLine.arguments.contains("--settings") { showSettings = true }
                if CommandLine.arguments.contains("--qa-fork") {
                    let id = store.newSession()
                    _ = store.send(text: "用一句话解释什么是上下文窗口", in: id)
                    while store.isStreaming(id) { try? await Task.sleep(for: .milliseconds(200)) }
                    try? await Task.sleep(for: .milliseconds(400))
                    if let lastAssistant = store.session(id)?.messages.last(where: { $0.role == .assistant }) {
                        _ = store.fork(sessionID: id, after: lastAssistant.id)
                    }
                    return
                }
                if CommandLine.arguments.contains("--qa-branch") {
                    // QA：连续两次「重新生成」，用于验证 ‹2/3› 版本切换
                    let id = store.newSession()
                    _ = store.send(text: "用一句话解释什么是版本分支", in: id)
                    while store.isStreaming(id) { try? await Task.sleep(for: .milliseconds(200)) }
                    try? await Task.sleep(for: .milliseconds(300))
                    store.regenerate(sessionID: id)
                    while store.isStreaming(id) { try? await Task.sleep(for: .milliseconds(200)) }
                    try? await Task.sleep(for: .milliseconds(300))
                    store.regenerate(sessionID: id)
                    return
                }
                guard DemoMode.isActive else { return }
                settings.runtimeOrigin = DemoMode.origin
                settings.thinking = true
                settings.search = true
                try? await Task.sleep(for: .milliseconds(600))
                try? await Task.sleep(for: .milliseconds(200))
                _ = store.sendNewConversation(text: DemoMode.prompt)
            }
            #if os(macOS)
            .frame(minWidth: DS.Metrics.windowMinWidth, minHeight: DS.Metrics.windowMinHeight)
            #endif
    }

    private var main: some View {
        HStack(spacing: 0) {
            if showSidebarInline {
                SiderView(
                    store: store,
                    settings: settings,
                    onOpenSettings: { showSettings = true },
                    onCollapse: { withAnimation(DS.Motion.fastEase) { settings.sidebarCollapsed = true } },
                    onSelect: { store.select($0) },
                    onNewChat: nil
                )

                EmptyView()
            }
            detail
                .background(DS.Colors.bgBase)
        }
        .overlay(alignment: .topLeading) {
            if !showSidebarInline && !isCompact {
                expandButton
            }
        }
        .sheet(isPresented: $showSidebarSheet) {
            SidebarSheet(store: store, settings: settings,
                         onOpenSettings: {
                             showSidebarSheet = false
                             showSettings = true
                         })
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = store.activeID, store.session(id) != nil {
            ChatView(
                store: store,
                settings: settings,
                sessionID: id,
                showsHeader: isCompact,
                onShowSidebar: { showSidebarSheet = true }
            )
        } else {
            WelcomeView(store: store, settings: settings)
        }
    }

    /// 侧栏收起后的浮动展开按钮（玻璃）
    private var expandButton: some View {
        Button {
            withAnimation(DS.Motion.fastEase) { settings.sidebarCollapsed = false }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Colors.labelSecondary)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.m)
                        .fill(DS.Colors.bgBase.opacity(0.6))
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: DS.Radius.m))
                }
        }
        .buttonStyle(.plain)
        .help("展开边栏")
        .padding(.leading, 12)
        .padding(.top, 12)
    }
}

// MARK: - 移动端会话抽屉

private struct SidebarSheet: View {
    @Bindable var store: ChatStore
    @Bindable var settings: AppSettings
    var onOpenSettings: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SiderView(
            store: store,
            settings: settings,
            onOpenSettings: onOpenSettings,
            onCollapse: { dismiss() },
            onSelect: { id in
                store.select(id)
                dismiss()
            },
            onNewChat: { dismiss() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

#Preview {
    RootView()
}
