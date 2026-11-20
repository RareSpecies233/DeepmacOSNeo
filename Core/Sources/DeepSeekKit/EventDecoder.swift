import Foundation

/// 把 SSE `data` 载荷解码为 `StreamEvent`。
///
/// 规则（与官方客户端 `parseEvent.ts` 一致）：
/// - 只校验消费所需的字段；未知事件、未知内容块、字段缺失都返回 nil（跳过），绝不抛错；
/// - 唯一会抛错的是服务端下发的错误帧：`{"error": {"message": ...}}`，以及 `event: error` 的裸载荷；
/// - 事件分派以 JSON 的 `type` 为准，SSE 的 `event` 名只用于错误帧兜底。
enum EventDecoder {

    static func decode(eventName: String, data: String) throws -> StreamEvent? {
        guard !data.isEmpty else { return nil }

        let object: Any?
        if let bytes = data.data(using: .utf8) {
            object = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
        } else {
            object = nil
        }

        guard let payload = obj(object) else {
            if eventName == "error" { throw DeepSeekError.stream(data) }
            return nil
        }

        if let error = obj(payload["error"]) {
            throw DeepSeekError.stream(str(error["message"]) ?? "未知错误")
        }
        if eventName == "error" { throw DeepSeekError.stream(data) }

        guard let type = str(payload["type"]) else { return nil }

        switch type {
        case "message_start":
            guard let message = obj(payload["message"]) else { return nil }
            return .messageStart(
                id: str(message["id"]) ?? "",
                model: str(message["model"]) ?? ""
            )

        case "content_block_start":
            guard let index = intIndex(payload["index"]),
                  let block = readBlock(payload["content_block"], index: index)
            else { return nil }
            return .blockStart(index: index, block: block)

        case "content_block_delta":
            guard let index = intIndex(payload["index"]),
                  let delta = obj(payload["delta"]),
                  let deltaType = str(delta["type"])
            else { return nil }
            switch deltaType {
            case "text_delta":
                guard let text = str(delta["text"]) else { return nil }
                return .textDelta(index: index, text)
            case "thinking_delta":
                guard let thinking = str(delta["thinking"]) else { return nil }
                return .thinkingDelta(index: index, thinking)
            case "signature_delta":
                guard let signature = str(delta["signature"]) else { return nil }
                return .signatureDelta(index: index, signature)
            case "citations_delta":
                guard let citation = readCitation(delta["citation"]) else { return nil }
                return .citationDelta(index: index, citation)
            default:
                // input_json_delta 等客户端工具增量当前不消费。
                return nil
            }

        case "content_block_stop":
            guard let index = intIndex(payload["index"]) else { return nil }
            return .blockStop(index: index)

        case "message_delta":
            // 容错：stop_reason 缺失或属于未来新增值时仍然保留，交由 UI 展示。
            guard let delta = obj(payload["delta"]) else { return nil }
            return .messageDelta(
                stopReason: str(delta["stop_reason"]),
                title: str(delta["title"])
            )

        case "message_stop":
            return .messageStop

        case "ping":
            return .ping

        default:
            return nil
        }
    }

    // MARK: - 内容块

    static func readBlock(_ value: Any?, index: Int) -> Block? {
        guard let payload = obj(value), let type = str(payload["type"]) else { return nil }

        switch type {
        case "text":
            guard let text = str(payload["text"]) else { return nil }
            let citations = arr(payload["citations"])?.compactMap(readCitation) ?? []
            return Block(id: "b\(index)", kind: .text, text: text, citations: citations)

        case "thinking":
            guard let thinking = str(payload["thinking"]) else { return nil }
            return Block(
                id: "b\(index)",
                kind: .thinking,
                text: thinking,
                signature: str(payload["signature"])
            )

        case "server_tool_use":
            guard let id = str(payload["id"]),
                  let kindRaw = str(payload["kind"]),
                  let kind = ToolKind(rawValue: kindRaw),
                  let name = str(payload["name"]),
                  ["deepseek_web_search", "deepseek_read_url"].contains(name),
                  let input = obj(payload["input"]),
                  let action = str(input["action"])
            else { return nil }

            var queries: [String] = []
            var url: String?
            var pattern: String?
            switch action {
            case "search":
                guard let raw = arr(input["queries"]) else { return nil }
                let parsed = raw.compactMap(str)
                guard parsed.count == raw.count else { return nil }
                queries = parsed
            case "open_page", "read_link":
                guard let parsed = str(input["url"]) else { return nil }
                url = parsed
            case "find_in_page":
                guard let parsed = str(input["url"]),
                      let parsedPattern = str(input["pattern"])
                else { return nil }
                url = parsed
                pattern = parsedPattern
            default:
                return nil
            }

            return Block(
                id: id,
                kind: .toolUse,
                toolUse: ServerToolUse(
                    id: id,
                    kind: kind,
                    queries: queries,
                    url: url,
                    pattern: pattern,
                    action: action
                )
            )

        case "web_search_tool_result":
            guard let toolUseID = str(payload["tool_use_id"]),
                  let kindRaw = str(payload["kind"]),
                  ["search", "deep_search", "image_search", "deep_image_search"].contains(kindRaw),
                  let items = arr(payload["content"])
            else { return nil }

            var results: [WebSearchResult] = []
            var failed = false
            for item in items {
                guard let itemPayload = obj(item), let itemType = str(itemPayload["type"]) else {
                    continue
                }
                if itemType == "web_search_tool_result_error" {
                    if str(itemPayload["error_code"]) != nil { failed = true }
                    continue
                }
                guard itemType == "web_search_result",
                      let url = str(itemPayload["url"]),
                      let title = str(itemPayload["title"]),
                      isStringOrNull(itemPayload["snippet"]),
                      isStringOrNull(itemPayload["site_name"]),
                      isStringOrNull(itemPayload["site_icon"]),
                      isStringOrNull(itemPayload["page_age"])
                else { continue }
                results.append(
                    WebSearchResult(
                        url: url,
                        title: title,
                        snippet: str(itemPayload["snippet"]),
                        siteName: str(itemPayload["site_name"]),
                        siteIcon: str(itemPayload["site_icon"]),
                        pageAge: str(itemPayload["page_age"])
                    )
                )
            }
            return Block(
                id: toolUseID,
                kind: .searchResults,
                searchResults: results,
                failed: failed
            )

        case "web_fetch_tool_result":
            guard let toolUseID = str(payload["tool_use_id"]),
                  let kindRaw = str(payload["kind"]),
                  ["read_link", "deep_search"].contains(kindRaw),
                  let content = obj(payload["content"]),
                  let contentType = str(content["type"])
            else { return nil }

            if contentType == "web_fetch_tool_result_error" {
                guard str(content["error_code"]) != nil else { return nil }
                return Block(
                    id: toolUseID,
                    kind: .fetchResult,
                    signature: str(payload["signature"]),
                    failed: true
                )
            }

            guard contentType == "web_fetch_result",
                  let url = str(content["url"]),
                  let page = obj(content["content"]),
                  isStringOrNull(page["title"]),
                  isStringOrNull(content["published_at"])
            else { return nil }

            return Block(
                id: toolUseID,
                kind: .fetchResult,
                signature: str(payload["signature"]),
                fetchResult: WebFetchResult(
                    url: url,
                    title: str(page["title"]),
                    publishedAt: str(content["published_at"])
                )
            )

        case "tool_use":
            // 客户端工具内容不在本应用展示范围。
            return nil

        default:
            return nil
        }
    }

    static func readCitation(_ value: Any?) -> Citation? {
        guard let payload = obj(value),
              str(payload["type"]) == "web_search_result_location",
              let url = str(payload["url"]),
              isStringOrNull(payload["title"])
        else { return nil }
        return Citation(
            url: url,
            title: str(payload["title"]),
            citedText: str(payload["cited_text"]) ?? ""
        )
    }

    // MARK: - JSON 取值（区分 null / 缺失 / 类型错误）

    static func str(_ value: Any?) -> String? {
        value as? String
    }

    static func obj(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    static func arr(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    /// 非负安全整数；拒绝布尔（JSON 的 true/false 会桥接成 NSNumber）。
    static func intIndex(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              String(cString: number.objCType) != "c"
        else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, double >= 0, double <= Double(Int.max) else { return nil }
        return Int(double)
    }

    /// 字段可缺失、可为 null、可为字符串；数字等非法类型视为不合法。
    static func isStringOrNull(_ value: Any?) -> Bool {
        if value == nil || value is NSNull { return true }
        return value is String
    }
}
