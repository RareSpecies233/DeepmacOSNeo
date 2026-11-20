import SwiftUI

#if os(macOS)
import AppKit

/// macOS 下把主题偏好同步到 NSApp.appearance，
/// 保证弹窗、菜单等独立窗口与主窗口的深浅色一致。
enum AppearanceSync {
    static func apply(_ preference: ThemePreference) {
        switch preference {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:  NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }
}
#else
enum AppearanceSync {
    static func apply(_ preference: ThemePreference) {}
}
#endif
