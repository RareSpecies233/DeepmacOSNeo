import Foundation

/// 一条完整的 SSE 事件。
public struct SSEEvent: Sendable, Equatable {
    /// `event` 字段，缺省为 "message"。
    public var event: String
    /// 多行 `data` 以 "\n" 连接。
    public var data: String
    public var lastEventId: String

    public init(event: String = "message", data: String, lastEventId: String = "") {
        self.event = event
        self.data = data
        self.lastEventId = lastEventId
    }
}

/// SSE（text/event-stream）增量解码器，按 WHATWG 规范实现：
/// 字节流 → 按 CRLF / LF / CR 切行 → 字段累积 → 空行派发事件。
///
/// 在**字节**层切行，因此 UTF-8 多字节字符即使跨网络分片也不会被截断；
/// CRLF 被拆到两个 chunk、单独 CR、多行 data、注释行都能正确处理。
/// 与规范一致：结尾没有空行的事件不会被派发（`finish()` 丢弃未完成事件）。
/// 这样「流在 message_stop 前结束」才能被上层识别为 interrupted。
public struct SSEDecoder: Sendable {
    private var line: [UInt8] = []
    private var dataBytes: [UInt8] = []
    private var hasData = false
    private var eventType = ""
    private var lastEventId = ""
    /// 上一个字节是 CR：下一个字节若是 LF 属于同一个换行。
    private var pendingCR = false
    /// 开头可能出现的 UTF-8 BOM，最多缓存 3 字节用于判断。
    private var bomBuffer: [UInt8] = []
    private var bomResolved = false

    public init() {}

    /// 送入一个字节，返回本次可派发的事件（通常为空）。
    public mutating func push(_ byte: UInt8) -> [SSEEvent] {
        if !bomResolved {
            bomBuffer.append(byte)
            let resolved: Bool
            if bomBuffer.count == 3 {
                resolved = true
            } else if bomBuffer.count == 1 {
                resolved = bomBuffer[0] != 0xEF
            } else {
                resolved = bomBuffer != [0xEF, 0xBB]
            }
            guard resolved else { return [] }
            bomResolved = true
            let pending = bomBuffer
            bomBuffer = []
            if pending == [0xEF, 0xBB, 0xBF] { return [] }
            var events: [SSEEvent] = []
            for value in pending {
                events.append(contentsOf: consume(value))
            }
            return events
        }
        return consume(byte)
    }

    /// 送入一段已编码的字节。
    public mutating func push(_ data: Data) -> [SSEEvent] {
        var events: [SSEEvent] = []
        events.reserveCapacity(2)
        for byte in data {
            events.append(contentsOf: push(byte))
        }
        return events
    }

    /// 送入一段文本（测试与已解码场景的便捷入口）。
    public mutating func push(_ text: String) -> [SSEEvent] {
        push(Data(text.utf8))
    }

    /// 流结束。按规范丢弃还没有以空行收尾的未完成事件。
    public mutating func finish() -> [SSEEvent] {
        line = []
        dataBytes = []
        hasData = false
        eventType = ""
        bomBuffer = []
        bomResolved = true
        pendingCR = false
        return []
    }

    // MARK: - 内部

    private mutating func consume(_ byte: UInt8) -> [SSEEvent] {
        if pendingCR {
            pendingCR = false
            if byte == 0x0A { return [] }
        }
        switch byte {
        case 0x0D:
            pendingCR = true
            return processLine()
        case 0x0A:
            return processLine()
        default:
            line.append(byte)
            return []
        }
    }

    private mutating func processLine() -> [SSEEvent] {
        let current = line
        line = []
        if current.isEmpty { return dispatch() }
        if current[0] == 0x3A { return [] }

        let fieldBytes: [UInt8]
        var valueBytes: [UInt8]
        if let colon = current.firstIndex(of: 0x3A) {
            fieldBytes = Array(current[0..<colon])
            valueBytes = Array(current[(colon + 1)...])
        } else {
            fieldBytes = current
            valueBytes = []
        }
        if valueBytes.first == 0x20 { valueBytes.removeFirst() }

        switch String(decoding: fieldBytes, as: UTF8.self) {
        case "data":
            if hasData { dataBytes.append(0x0A) }
            dataBytes.append(contentsOf: valueBytes)
            hasData = true
        case "event":
            eventType = String(decoding: valueBytes, as: UTF8.self)
        case "id":
            let value = String(decoding: valueBytes, as: UTF8.self)
            if !value.contains("\0") { lastEventId = value }
        default:
            break
        }
        return []
    }

    private mutating func dispatch() -> [SSEEvent] {
        defer {
            dataBytes = []
            hasData = false
            eventType = ""
        }
        guard hasData else { return [] }
        return [
            SSEEvent(
                event: eventType.isEmpty ? "message" : eventType,
                data: String(decoding: dataBytes, as: UTF8.self),
                lastEventId: lastEventId
            )
        ]
    }
}
