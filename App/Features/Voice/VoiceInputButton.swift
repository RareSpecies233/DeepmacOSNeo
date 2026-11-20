import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 语音输入按钮
//
// 用法（Composer 里接一行就够）：
//
//     VoiceInputButton(text: $draft)
//
// 点第一次开始录音（首次会依次请求「语音识别」「麦克风」授权），
// 点第二次停止；转写结果**追加**到绑定文本末尾，不覆盖用户已输入内容。
// 权限被拒 / 没有麦克风时按钮依然可用，点一下弹内部 alert 说明原因。

public struct VoiceInputButton: View {

    @Binding private var text: String
    private let locale: Locale

    @State private var controller = VoiceInputController()
    @State private var presentedError: VoiceInputError?
    @State private var hovered = false
    @State private var pulse = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 与 Composer 内部按钮同尺寸（ComposerView 的 attach / send 也是 34×34）
    private static let side: CGFloat = 34

    public init(text: Binding<String>, locale: Locale = Locale(identifier: "zh-CN")) {
        _text = text
        self.locale = locale
    }

    public var body: some View {
        // 刻意不做成 HStack(秒数 + 按钮)：秒数一出现会把按钮往右挤，
        // 手指还在原位置点下去就成了「点到徽标」，停不掉录音（实测踩过）。
        // 所以秒数直接画进 34×34 的圆里，按钮的位置永远不动。
        button
        .onAppear {
            controller.locale = locale
            controller.onCommit = { transcript in
                // 只追加，不覆盖：用户已经打了一半的字必须保留
                text = Self.appending(transcript, to: text)
            }
        }
        .onChange(of: locale) { _, newValue in
            controller.locale = newValue
        }
        .onChange(of: controller.isRecording, initial: true) { _, recording in
            updatePulse(recording)
        }
        .onChange(of: controller.lastError) { _, newValue in
            guard let newValue else { return }
            presentedError = newValue
            controller.clearError()
        }
        .alert(presentedError?.title ?? "语音输入", isPresented: alertBinding) {
            if let url = settingsURL {
                Button("打开设置") { openSettings(url) }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(presentedError?.message ?? "")
        }
        .onDisappear {
            // 视图没了就别留着引擎和麦克风
            controller.cancel()
        }
    }

    // MARK: 按钮本体

    private var button: some View {
        Button {
            controller.toggle()
        } label: {
            ZStack {
                if controller.isRecording, !reduceMotion {
                    // 脉冲圈：只做视觉，不参与命中测试
                    Circle()
                        .stroke(DS.Colors.errorPrimary.opacity(0.55), lineWidth: 2)
                        .scaleEffect(pulse ? 1.45 : 1)
                        .opacity(pulse ? 0 : 1)
                        .allowsHitTesting(false)
                }
                Circle()
                    .fill(circleFill)
                content
            }
            .frame(width: Self.side, height: Self.side)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(helpText)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle:
            Image(systemName: "mic")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DS.Colors.labelSecondary)
        case .preparing, .finishing:
            ProgressView()
                .controlSize(.mini)
                .tint(DS.Colors.brandPrimary)
        case .recording:
            // 停止图标 + 秒数一起塞进圆里：位置固定、信息齐全
            VStack(spacing: 1) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(Self.timeText(controller.elapsed))
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(DS.Colors.labelOnBrand)
        }
    }

    private var circleFill: Color {
        switch controller.phase {
        case .recording:
            DS.Colors.errorPrimary
        case .preparing, .finishing:
            DS.Colors.interactiveHover
        case .idle:
            hovered ? DS.Colors.interactiveHover : .clear
        }
    }

    // MARK: 文本追加

    /// 把一段转写追加到已有文本末尾。
    /// 规则：空串直接取；已有内容以空白结尾就直接接；中日韩文字之间不补空格（补了会难看），
    /// 其余情况补一个词间空格。
    public static func appending(_ transcript: String, to existing: String) -> String {
        let piece = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return existing }
        guard !existing.isEmpty else { return piece }
        if let last = existing.last, last.isWhitespace { return existing + piece }
        let needsSpace = !isCJK(existing.last) && !isCJK(piece.first)
        return existing + (needsSpace ? " " : "") + piece
    }

    private static func isCJK(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x2E80...0x9FFF,   // 部首 / 假名 / 中日韩统一表意文字（含 CJK 标点 0x3000-0x303F）
             0xAC00...0xD7AF,   // 谚文音节
             0xF900...0xFAFF,   // 兼容表意文字
             0xFF00...0xFFEF:   // 全角形式
            return true
        default:
            return false
        }
    }

    private static func timeText(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: 状态文案

    private var helpText: String {
        switch controller.phase {
        case .idle: "语音输入"
        case .preparing: "取消语音输入"
        case .recording: "停止并插入转写"
        case .finishing: "正在整理转写…"
        }
    }

    private var accessibilityLabel: String {
        switch controller.phase {
        case .idle: "语音输入"
        case .preparing: "取消语音输入"
        case .recording: "停止录音"
        case .finishing: "正在整理转写"
        }
    }

    // MARK: 脉冲

    private func updatePulse(_ recording: Bool) {
        guard !reduceMotion else {
            pulse = false
            return
        }
        if recording {
            pulse = false
            withAnimation(.easeOut(duration: 1.15).repeatForever(autoreverses: false)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                pulse = false
            }
        }
    }

    // MARK: alert 与设置跳转

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { if !$0 { presentedError = nil } }
        )
    }

    private var settingsURL: URL? {
        guard let presentedError else { return nil }
        switch presentedError {
        case .microphoneDenied, .noMicrophone:
            #if os(iOS)
            return URL(string: UIApplication.openSettingsURLString)
            #else
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            #endif
        case .speechDenied, .speechRestricted:
            #if os(iOS)
            return URL(string: UIApplication.openSettingsURLString)
            #else
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
            #endif
        case .recognizerUnavailable, .engineFailed, .recognitionFailed:
            return nil
        }
    }

    private func openSettings(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}
