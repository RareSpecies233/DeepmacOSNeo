import Foundation

/// 流式事件。未知事件不会变成 error，解析层直接跳过。
public enum StreamEvent: Sendable {
    case messageStart(id: String, model: String)
    case blockStart(index: Int, block: Block)
    case textDelta(index: Int, _ text: String)
    case thinkingDelta(index: Int, _ text: String)
    case signatureDelta(index: Int, _ signature: String)
    case citationDelta(index: Int, _ citation: Citation)
    case blockStop(index: Int)
    case messageDelta(stopReason: String?, title: String?)
    case messageStop
    case ping
}
