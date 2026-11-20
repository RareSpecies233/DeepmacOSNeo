import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 设计令牌（对齐 Reference/chat-demo/src/app/theme.css）
//
// 命名规则与来源：
//   --dsw-alias-*    → DS.Colors.*
//   --ds-control-*   → DS.Size.control*
//   --message-list-* → DS.Metrics.*
// 只做「值」的搬运，不在这里发明新色号。

public enum DS {

    // MARK: Colors

    public enum Colors {

        // 画布与层级
        public static let bgBase        = dyn(0xFFFFFF, 0x151517)
        public static let bgLayer2      = dyn(0xFFFFFF, 0x2C2C2E)
        public static let bgLayer3      = dyn(0xFFFFFF, 0x353638)
        public static let bgSkeleton    = dynAlpha(0x000000, 0.04, 0xFFFFFF, 0.08)

        // 分隔线
        public static let borderL1      = dynAlpha(0x000000, 0.04, 0xFFFFFF, 0.06)
        public static let borderL2      = dynAlpha(0x000000, 0.10, 0xFFFFFF, 0.12)
        public static let borderL3      = dynAlpha(0x000000, 0.12, 0xFFFFFF, 0.16)

        // 品牌
        public static let brandPrimary  = dyn(0x3964FE, 0x5686FE)
        public static let brandText     = dyn(0x3964FE, 0x679EFE)
        public static let brandSubtle   = dyn(0xE4EDFD, 0x283142)   // blue-100 / blue-900

        // 文本
        public static let labelPrimary   = dyn(0x0F1115, 0xF9FAFB)
        public static let labelSecondary = dyn(0x61666B, 0xCFD3D6)
        public static let labelTertiary  = dyn(0x81858C, 0xADB2B8)
        public static let labelCaption   = dyn(0xADB2B8, 0x81858C)
        public static let labelDimmed    = dyn(0xE1E5EE, 0x43454A)
        public static let labelOnBrand   = dyn(0xFFFFFF, 0xFFFFFF)

        // 交互态
        public static let interactiveHover        = dynAlpha(0x263148, 0.06, 0xFFFFFF, 0.08)
        public static let interactiveActive       = dynAlpha(0x263148, 0.10, 0xFFFFFF, 0.14)
        public static let interactiveHoverAccent  = dynAlpha(0x263148, 0.14, 0xFFFFFF, 0.24)
        public static let interactiveHoverDanger  = dynAlpha(0xEC1313, 0.05, 0xF25A5A, 0.15)

        // 面
        public static let sidebarFill      = dyn(0xF9FAFB, 0x1B1B1C)
        public static let sidebarActive    = dyn(0xE4EDFD, 0x283142)
        public static let bubble           = dyn(0xEDF3FE, 0x2C2C2E)   // 用户消息底色
        public static let inputFill        = dyn(0xFFFFFF, 0x2C2C2E)
        public static let menu             = dyn(0xFFFFFF, 0x353638)
        public static let tooltipBg        = dyn(0x2C2C2E, 0x43454A)
        public static let toastBg          = dyn(0x353638, 0x43454A)

        // Markdown
        public static let codeBlock        = dyn(0xF9FAFB, 0x1B1B1C)
        public static let codeBlockBanner  = dyn(0xF9FAFB, 0x2C2C2E)
        public static let inlineCode       = dyn(0xEBEEF2, 0x2C2C2E)
        public static let citation         = dyn(0xEBEEF2, 0x2C2C2E)
        public static let markdownTag      = dyn(0xF1F3F5, 0x2C2C2E)

        // 状态
        public static let errorPrimary     = dyn(0xEC1313, 0xF25A5A)
        public static let errorSecondary   = dyn(0xF25A5A, 0xF25A5A)
    }

    // MARK: Metrics

    public enum Metrics {
        /// --message-list-max-width
        public static let messageListMaxWidth: CGFloat = 840
        public static let messageListMaxWidthCompact: CGFloat = 712
        /// --message-list-padding-horizontal
        public static let messageListPadding: CGFloat = 44
        public static let messageListPaddingCompact: CGFloat = 36
        /// --sider width
        public static let sidebarWidth: CGFloat = 261
        public static let sidebarWidthCollapsed: CGFloat = 0
        public static let composerMaxHeight: CGFloat = 240
        public static let windowMinWidth: CGFloat = 720
        public static let windowMinHeight: CGFloat = 520
    }

    // MARK: Spacing

    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
    }

    // MARK: Radius

    public enum Radius {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 6
        public static let m: CGFloat = 8
        public static let l: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let card: CGFloat = 20
        /// 输入框容器（玻璃）
        public static let composer: CGFloat = 26
        public static let pill: CGFloat = 999
    }

    // MARK: Size

    public enum Size {
        public static let controlXL: CGFloat = 44
        public static let controlL: CGFloat = 40
        public static let controlM: CGFloat = 36
        public static let controlS: CGFloat = 32
        public static let controlXS: CGFloat = 28
        public static let iconS: CGFloat = 14
        public static let iconM: CGFloat = 16
        public static let iconL: CGFloat = 20
    }

    // MARK: Typography

    public enum Typography {
        /// 助手正文 / 全局基准：14px
        public static let body = Font.system(size: 14, weight: .regular)
        public static let bodyMedium = Font.system(size: 14, weight: .medium)
        public static let bodySemibold = Font.system(size: 14, weight: .semibold)
        /// 用户消息：16px
        public static let userBody = Font.system(size: 16, weight: .regular)
        public static let title = Font.system(size: 16, weight: .semibold)
        public static let sectionTitle = Font.system(size: 15, weight: .semibold)
        public static let caption = Font.system(size: 12, weight: .regular)
        public static let captionMedium = Font.system(size: 12, weight: .medium)
        public static let code = Font.system(size: 12.5, design: .monospaced)
        public static let codeSmall = Font.system(size: 11.5, design: .monospaced)

        public static let bodyLineSpacing: CGFloat = 6      // 14px 文本 → 约 22px 行高
        public static let userLineSpacing: CGFloat = 4      // 16/24
    }

    // MARK: Motion

    public enum Motion {
        public static let fast: Double = 0.2
        public static let slow: Double = 0.3
        public static let easing = Animation.timingCurve(0.4, 0, 0.2, 1)
        public static let fastEase = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.2)
    }
}

// MARK: - Helpers

/// 解析 hex（0xRRGGBB / 0xAARRGGBB）
func dsColor(_ hex: UInt32, alpha: Double = 1) -> Color {
    let a, r, g, b: Double
    if hex > 0xFFFFFF {
        a = Double((hex >> 24) & 0xFF) / 255
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    } else {
        a = alpha
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}

/// 深浅色各自解析
func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
    #if canImport(UIKit)
    return Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(dsColor(dark)) : UIColor(dsColor(light))
    })
    #elseif canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(dsColor(dark)) : NSColor(dsColor(light))
    })
    #else
    return dsColor(light)
    #endif
}

/// 深浅色 + 各自不透明度
func dynAlpha(_ lightHex: UInt32, _ lightAlpha: Double,
              _ darkHex: UInt32, _ darkAlpha: Double) -> Color {
    #if canImport(UIKit)
    return Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(dsColor(darkHex, alpha: darkAlpha))
            : UIColor(dsColor(lightHex, alpha: lightAlpha))
    })
    #elseif canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(dsColor(darkHex, alpha: darkAlpha))
            : NSColor(dsColor(lightHex, alpha: lightAlpha))
    })
    #else
    return dsColor(lightHex, alpha: lightAlpha)
    #endif
}
