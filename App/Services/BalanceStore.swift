import Foundation
import Observation

/// DeepSeek 账户余额（GET /user/balance），用于侧栏底部的连接状态区。
@MainActor
@Observable
final class BalanceStore {
    static let shared = BalanceStore()

    private(set) var displayText: String?
    private(set) var isLoading = false
    private(set) var lastError: String?
    private var lastFetchedAt: Date?

    private struct Payload: Decodable {
        let is_available: Bool?
        let balance_infos: [Info]?
        struct Info: Decodable {
            let currency: String
            let total_balance: String
        }
    }

    /// 60 秒内不重复请求
    func refresh(settings: AppSettings, force: Bool = false) async {
        guard settings.hasAPIKey, let origin = URL(string: settings.effectiveOrigin) else {
            displayText = nil
            return
        }
        if !force, let last = lastFetchedAt, Date().timeIntervalSince(last) < 60 { return }

        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: origin.appending(path: "user/balance"))
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "响应异常"
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                lastError = http.statusCode == 401 ? "Key 无效" : "HTTP \(http.statusCode)"
                displayText = nil
                return
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            lastFetchedAt = Date()
            lastError = nil
            if let info = payload.balance_infos?.first {
                displayText = Self.format(currency: info.currency, amount: info.total_balance)
            } else {
                displayText = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func format(currency: String, amount: String) -> String {
        let symbol: String
        switch currency.uppercased() {
        case "CNY": symbol = "¥"
        case "USD": symbol = "$"
        default: symbol = currency.uppercased() + " "
        }
        // 只保留两位小数
        if let value = Double(amount) {
            return symbol + String(format: "%.2f", value)
        }
        return symbol + amount
    }
}
