import Foundation

// MARK: - 语言

/// App 界面语言。`rawValue` 同时是 `.lproj` 目录名（`zh-Hans` / `en`）。
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case zhHans = "zh-Hans"
    case enUS = "en"

    var id: String { rawValue }

    /// 该语言对应的区域，用于日期等系统格式化
    var locale: Locale { Locale(identifier: rawValue) }

    /// 并列项连接符：「A、B」/「A, B」
    var listSeparator: String { self == .zhHans ? "、" : ", " }
}

// MARK: - 文案键

/// 全部文案键，与 `App/Resources/Localizable.xcstrings` 一一对应。
/// 命名沿用原版 chat-demo 的 i18n key（`Reference/chat-demo/src/i18n/zh.ts`）。
enum L10nKey: String, CaseIterable, Sendable {
    case appName
    case settings
    case closeSettings
    case settingsGroupGeneral
    case settingsGroupData
    case settingDialogAsideGeneralOptionLabel
    case settingDialogAsideDataOptionLabel
    case settingsLocalePreference
    case languageSubtitle
    case settingsLocaleZhCN
    case settingsLocaleEnUS
    case themeSubtitle
    case avatarMenuSettingsDialogThemeItemLabel
    case avatarMenuSettingsDialogThemeSelectLightOption
    case avatarMenuSettingsDialogThemeSelectDarkOption
    case avatarMenuSettingsDialogThemeSelectSystemOption
    case version
    case versionA11y
    case aboutCredit
    case apiKeyStorageNote
    case apiKeyPlaceholder
    case save
    case verify
    case apiKeySaveFailed
    case apiKeyVerifying
    case apiKeyEmptyHint
    case apiKeyValid
    case apiKeyVerificationFailed
    case apiKeyUnsaved
    case apiKeySavedUnverified
    case apiKeySavedNote
    case showAPIKey
    case hideAPIKey
    case apiOriginTitle
    case apiOriginSubtitle
    case usingMockService
    case useLocalMock
    case useLocalMockAccessibility
    case modelRowTitle
    case modelRowSubtitle
    case modelFlashBlurb
    case modelProBlurb
    case thinkingSwitch
    case deactivatedThinkTooltip
    case search
    case deactivatedSearchTooltip
    case showBalance
    case showBalanceSubtitle
    case accountBalance
    case balanceLoading
    case refreshBalance
    case apiKeyConfigured
    case apiKeyNotConfigured
    case newChat
    case collapseSiderbarButton
    case sessionName
    case sessionItemMenuRenameOption
    case pin
    case unpin
    case delete
    case cancel
    case deleteSessionConfirmTitle
    case deleteSessionConfirmMessage
    case sessionHistoryTimelineLabelToday
    case sessionHistoryTimelineLabelYesterday
    case sessionHistoryTimelineLabel7days
    case sessionHistoryTimelineLabel30days
    case welcomeMessageChat250808
    case contentCaveat
    case chatInputPlaceholderChat
    case uploadFile
    case chatInputStopButtonTooltip
    case send
    case thinkingDone
    case messageThinkStopped
    case deepSearchSearching
    case messageThinking
    case searchFailed
    case messageSearchResult
    case messageSearchResults
    case readFailed
    case searchQuery
    case readingURL
    case findInPage
    case toolCall
    case webPage
    case localStorageTitle
    case localStorageDescription
    case deleteAllSessions
    case deleteAllSessionsModalTitle
    case deleteAllSessionsModalDescription
}

// MARK: - 本地化

/// 运行时本地化入口。
///
/// 语言以 `AppSettings.language` 为唯一真源；`t(_:)` 每次都会读取它，
/// 因此 SwiftUI 在 body 里调用 `L10n.t(...)` 时会自动建立观察依赖 ——
/// 切换语言后无需重启，所有读文案的视图会一起刷新。
///
/// 文案从当前语言对应的 `.lproj/Localizable.strings` 读取（由
/// `Localizable.xcstrings` 编译产出）；缺失时回退到中文源文案，再回退到 key 本身。
@MainActor
enum L10n {

    /// 当前语言。视图里读它同样会触发刷新。
    static var language: AppLanguage { AppSettings.shared.language }

    // MARK: 取文案

    static func t(_ key: L10nKey) -> String {
        t(key, [:])
    }

    static func t(_ key: L10nKey, _ args: [String: String]) -> String {
        t(key.rawValue, args)
    }

    /// 直接按原版 i18n 的 key 字符串取文案。
    /// `args` 用于替换文案里的 `{name}` 占位符（例如 `{count}`）。
    static func t(_ rawKey: String, _ args: [String: String] = [:]) -> String {
        // 观察点：语言变化驱动视图刷新
        let language = AppSettings.shared.language
        let value = table(for: language)[rawKey]
            ?? (language == .zhHans ? nil : table(for: .zhHans)[rawKey])
            ?? rawKey
        return interpolate(value, args)
    }

    /// 按当前语言拼接列表（中文「、」，英文「, 」）
    static func list(_ items: [String]) -> String {
        items.joined(separator: language.listSeparator)
    }

    // MARK: 文案表

    /// 每个语言只解析一次，之后直接查字典
    private static var tables: [AppLanguage: [String: String]] = [:]

    private static func table(for language: AppLanguage) -> [String: String] {
        if let cached = tables[language] { return cached }

        var table: [String: String] = [:]
        if let bundle = lprojBundle(for: language) {
            // 用哨兵区分「译文恰好等于 key」和「没有这条译文」
            let missing = "\u{0}"
            for key in L10nKey.allCases {
                let value = bundle.localizedString(forKey: key.rawValue, value: missing, table: "Localizable")
                if value != missing { table[key.rawValue] = value }
            }
        }
        tables[language] = table
        return table
    }

    /// 语言对应的 `.lproj` 子 bundle
    private static func lprojBundle(for language: AppLanguage) -> Bundle? {
        #if SWIFT_PACKAGE
        let host = Bundle.module
        #else
        let host = Bundle.main
        #endif
        guard let path = host.path(forResource: language.rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private static func interpolate(_ template: String, _ args: [String: String]) -> String {
        guard !args.isEmpty, template.contains("{") else { return template }
        var result = template
        for (name, value) in args {
            result = result.replacingOccurrences(of: "{" + name + "}", with: value)
        }
        return result
    }
}
