import Foundation

/// UI 的流式状态机：把 `StreamEvent` 增量合并进一条 assistant 消息。
/// 不持有 UI，不碰主线程，纯值语义。
public struct StreamAccumulator: Sendable {
    public private(set) var message: ChatMessage
    public private(set) var title: String?

    /// SSE 的 content block index → message.blocks 下标。
    private var blockIndexes: [Int: Int] = [:]

    public init(id: String, model: String, createdAt: Date = .now) {
        message = ChatMessage(
            id: id,
            role: .assistant,
            blocks: [],
            createdAt: createdAt,
            status: .streaming,
            model: model
        )
    }

    public mutating func apply(_ event: StreamEvent) {
        switch event {
        case let .messageStart(id, model):
            if message.id.isEmpty { message.id = id }
            if message.model?.isEmpty ?? true, !model.isEmpty { message.model = model }

        case let .blockStart(index, block):
            blockIndexes[index] = message.blocks.count
            message.blocks.append(block)

        case let .textDelta(index, text):
            guard let position = position(for: index),
                  message.blocks[position].kind == .text
            else { return }
            message.blocks[position].text += text

        case let .thinkingDelta(index, text):
            guard let position = position(for: index),
                  message.blocks[position].kind == .thinking
            else { return }
            message.blocks[position].text += text

        case let .signatureDelta(index, signature):
            guard let position = position(for: index),
                  message.blocks[position].kind == .thinking
            else { return }
            message.blocks[position].signature =
                (message.blocks[position].signature ?? "") + signature

        case let .citationDelta(index, citation):
            guard let position = position(for: index),
                  message.blocks[position].kind == .text
            else { return }
            if !message.blocks[position].citations.contains(where: { $0.url == citation.url }) {
                message.blocks[position].citations.append(citation)
            }

        case .blockStop:
            // 连接已结束后才到的 signature_delta 仍然接收，因此不销毁 index 映射。
            break

        case let .messageDelta(stopReason, title):
            message.stopReason = stopReason
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.title = title
            }

        case .messageStop, .ping:
            break
        }
    }

    public mutating func finish(status: MessageStatus, error: String? = nil) {
        message.status = status
        message.errorText = error
    }

    private func position(for index: Int) -> Int? {
        guard let position = blockIndexes[index], message.blocks.indices.contains(position) else {
            return nil
        }
        return position
    }
}
