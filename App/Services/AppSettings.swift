import SwiftUI
import Observation
import Security

// MARK: - 主题

enum ThemePreference: String, CaseIterable, Identifiable, Sendable {
    case light, dark, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "浅色"
        case .dark: "深色"
        case .system: "跟随系统"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

// MARK: - 模型

struct ModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let blurb: String
    static let all: [ModelOption] = [
        .init(id: "deepseek-flash", label: "DeepSeek Flash", blurb: "快速响应，日常对话"),
        .init(id: "deepseek-v4-pro", label: "DeepSeek V4 Pro", blurb: "复杂推理与长任务"),
    ]
    static func label(for id: String) -> String {
        all.first { $0.id == id }?.label ?? id
    }
}

// MARK: - 全局设置

@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    private enum Key {
        static let apiOrigin = "ds.apiOrigin"
        static let model = "ds.model"
        static let thinking = "ds.thinking"
        static let search = "ds.search"
        static let theme = "ds.theme"
        static let sidebarCollapsed = "ds.sidebarCollapsed"
        static let hasOnboarded = "ds.hasOnboarded"
    }

    var apiOrigin: String {
        didSet { UserDefaults.standard.set(apiOrigin, forKey: Key.apiOrigin) }
    }
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Key.model) }
    }
    var thinking: Bool {
        didSet { UserDefaults.standard.set(thinking, forKey: Key.thinking) }
    }
    var search: Bool {
        didSet { UserDefaults.standard.set(search, forKey: Key.search) }
    }
    var theme: ThemePreference {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Key.theme) }
    }
    var sidebarCollapsed: Bool {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: Key.sidebarCollapsed) }
    }

    /// 内存中的 API Key（初始化时从 Keychain 读取）
    private(set) var apiKey: String
    /// 最近一次校验结果；nil 表示未知
    private(set) var keyStatus: KeyStatus = .unknown

    enum KeyStatus: Equatable, Sendable {
        case unknown, valid, invalid(String)
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }
    var isUsingMock: Bool { apiOrigin.contains("127.0.0.1") || apiOrigin.contains("localhost") }

    init() {
        let defaults = UserDefaults.standard
        self.apiOrigin = defaults.string(forKey: Key.apiOrigin) ?? "https://api.deepseek.com"
        self.model = defaults.string(forKey: Key.model) ?? "deepseek-flash"
        self.thinking = defaults.object(forKey: Key.thinking) as? Bool ?? true
        self.search = defaults.object(forKey: Key.search) as? Bool ?? true
        self.theme = ThemePreference(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        self.sidebarCollapsed = defaults.object(forKey: Key.sidebarCollapsed) as? Bool ?? false
        // 开发/测试便捷路径：DEEPSEEK_API_KEY 环境变量优先于 Keychain，
        // 仅用于本地联调，发布构建请依赖 Keychain。
        if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !envKey.isEmpty {
            self.apiKey = envKey
        } else {
            self.apiKey = KeychainStore.read() ?? ""
        }
    }

    // MARK: Key 管理

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete()
            apiKey = ""
            keyStatus = .unknown
            return
        }
        try KeychainStore.save(trimmed)
        apiKey = trimmed
        keyStatus = .unknown
    }

    /// 用 GET /models 校验，不产生费用
    func verifyAPIKey() async {
        guard hasAPIKey else {
            keyStatus = .invalid("请先填写 API Key")
            return
        }
        guard let origin = URL(string: apiOrigin) else {
            keyStatus = .invalid("接口地址无效")
            return
        }
        var request = URLRequest(url: origin.appending(path: "models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                keyStatus = .invalid("响应异常")
                return
            }
            if (200..<300).contains(http.statusCode) {
                keyStatus = .valid
            } else {
                keyStatus = .invalid(http.statusCode == 401 ? "API Key 无效" : "服务返回 \(http.statusCode)")
            }
        } catch {
            keyStatus = .invalid(error.localizedDescription)
        }
    }

    /// 供 ChatStore 使用：没有 Key 时退化为本地演示模式
    var client: DeepSeekClient? {
        guard let origin = URL(string: apiOrigin) else { return nil }
        return DeepSeekClient(apiOrigin: origin, apiKey: apiKey)
    }
}

// MARK: - Keychain

enum KeychainStore {
    private static let service = "com.deepglass.app"
    private static let account = "deepseek-api-key"

    static func save(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "无法写入钥匙串（\(status)）"])
        }
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
