import SwiftUI

@main
struct DeepGlassApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }
        #endif
    }
}

#if os(macOS)
struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建对话") { NotificationCenter.default.post(name: .newSessionRequested, object: nil) }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(replacing: .appSettings) {
            Button("设置…") { NotificationCenter.default.post(name: .settingsRequested, object: nil) }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}
#endif

extension Notification.Name {
    static let newSessionRequested = Notification.Name("DeepGlass.newSession")
    static let settingsRequested = Notification.Name("DeepGlass.settings")
}
