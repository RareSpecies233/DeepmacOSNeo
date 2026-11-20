import SwiftUI

// MARK: - 朗读按钮
//
// 用法（放在 MessageRow 的操作栏里，挨着「复制」）：
//
//     ReadAloudButton(text: message.plainText)
//
// 点一下开始朗读，图标变停止；再点一下中断。切换消息（text 变化）或视图消失时自动停止，
// 不会出现「消息已经换了、声音还在念上一条」。

public struct ReadAloudButton: View {

    private let text: String

    @State private var controller = ReadAloudController()
    @State private var hovered = false

    /// 与 MessageRow 里的 ActionIcon 同尺寸（26×26 / 12pt 图标）
    private static let side: CGFloat = 26

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Button {
            // 清洗只在点击时做一次；放在 body 里会随流式渲染被反复执行
            withAnimation(DS.Motion.fastEase) {
                controller.toggle(ReadAloudController.speechText(from: text))
            }
        } label: {
            Image(systemName: controller.isSpeaking ? "stop.fill" : "speaker.wave.2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(controller.isSpeaking ? DS.Colors.brandPrimary : DS.Colors.labelTertiary)
                .frame(width: Self.side, height: Self.side)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .fill(background)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .opacity(isEmpty ? DS.Components.disabledOpacity : 1)
        .onHover { hovered = $0 }
        .help(controller.isSpeaking ? "停止朗读" : "朗读")
        .accessibilityLabel(controller.isSpeaking ? "停止朗读" : "朗读")
        .onChange(of: text) { _, _ in
            // 换消息：立刻停，别把上一条念完
            controller.stop()
        }
        .onDisappear {
            controller.stop()
        }
    }

    /// 廉价的空判断（不做正则，避免流式渲染时重复计算）
    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var background: Color {
        if controller.isSpeaking { return DS.Colors.brandSubtle }
        return hovered ? DS.Colors.interactiveHover : .clear
    }
}
