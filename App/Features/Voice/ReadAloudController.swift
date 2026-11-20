import AVFoundation
import Foundation
import Observation

// MARK: - 朗读状态机
//
// 只管「在念 / 没在念」这一个布尔，但把三件事收干净：
//   1. 同一时刻只念一条（新消息进来先停掉旧的，不排队）；
//   2. 自然念完（didFinish）与被打断（didCancel）都要把状态复位，
//      否则图标会一直停在「停止」上 —— 这是 AVSpeechSynthesizer 最常见的坑；
//   3. 合成器的 delegate 是 weak，必须自己强引用代理对象。

/// 合成器回调不保证在哪个线程，用代理 + 锁兜一层，再回主线程改状态。
private final class SpeechEndProxy: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private var _onEnd: (@Sendable () -> Void)?

    /// 不论是念完还是被打断，都算「结束」。
    /// 用 @Sendable 存：合成器的回调线程不保证是主线程，带主线程隔离的闭包在这里会崩。
    var onEnd: (@Sendable () -> Void)? {
        get { lock.withLock { _onEnd } }
        set { lock.withLock { _onEnd = newValue } }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onEnd?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onEnd?()
    }
}

@MainActor
@Observable
public final class ReadAloudController {

    /// 正在朗读
    public private(set) var isSpeaking = false

    /// 朗读语言（BCP-47 风格，例如 zh-CN）
    public var locale: Locale {
        didSet { voiceCache.removeAll() }
    }

    /// 语速：0.5 是系统默认（AVSpeechUtteranceDefaultSpeechRate），听感适中
    public var rate: Float = 0.5

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let proxy = SpeechEndProxy()
    @ObservationIgnored private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]

    public init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
        synthesizer.delegate = proxy
        proxy.onEnd = { @Sendable [weak self] in
            Task { @MainActor in
                self?.handleEnded()
            }
        }
    }

    // MARK: 外部入口

    /// 点一下：在念就停，没念就开始念。
    public func toggle(_ text: String) {
        if isSpeaking {
            stop()
        } else {
            speak(text)
        }
    }

    public func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 换消息 / 连点时先掐掉在途的那条，保证不排队、不叠音
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let language = Self.languageCode(for: locale)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice(for: language)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: 内部

    private func handleEnded() {
        isSpeaking = false
    }

    /// 优先挑质量最高的本地嗓音：premium > enhanced > default。
    /// 系统没装中文嗓音时退化成 AVSpeechSynthesisVoice(language:)（它自己会挑可用的）。
    private func voice(for language: String) -> AVSpeechSynthesisVoice? {
        if let cached = voiceCache[language] { return cached }
        let picked = Self.bestVoice(for: language)
        if let picked { voiceCache[language] = picked }
        return picked
    }

    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let target = language.lowercased()
        let all = AVSpeechSynthesisVoice.speechVoices()

        let exact = all.filter { $0.language.lowercased() == target }
        let prefix = all.filter { $0.language.lowercased().hasPrefix(target) }
        let primary = target.split(separator: "-").first.map(String.init) ?? target
        let family = all.filter {
            ($0.language.lowercased().split(separator: "-").first.map(String.init) ?? "") == primary
        }

        for pool in [exact, prefix, family] {
            if let voice = pickBestQuality(in: pool) { return voice }
        }
        return AVSpeechSynthesisVoice(language: language)
    }

    private static func pickBestQuality(in voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        voices.first { $0.quality == .premium }
            ?? voices.first { $0.quality == .enhanced }
            ?? voices.first
    }

    /// Locale(identifier: "zh_CN") 也能归一成 "zh-CN"
    static func languageCode(for locale: Locale) -> String {
        locale.identifier.replacingOccurrences(of: "_", with: "-")
    }

    // MARK: - 朗读文本清洗
    //
    // 消息正文是 Markdown 源码，直接丢给合成器会把 `**`、`#`、`](url)` 也念出来。
    // 这里只做「为朗读服务」的轻量清洗，不改动原文（原文仍用于显示 / 复制）。
    // 对本来就是纯文本的输入基本无损，重复调用也是幂等的。

    public static func speechText(from raw: String) -> String {
        var text = raw
        guard !text.isEmpty else { return "" }

        // 图片 → alt 文本；链接 → 链接文字
        text = text.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)

        // 裸 URL 念出来没有意义
        text = text.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)

        // 代码围栏标记（保留代码内容，只去掉 ```lang 这一行）
        text = text.replacingOccurrences(of: #"(?m)^\s*```.*$"#, with: "", options: .regularExpression)

        // 行首标题号 / 引用号
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\s{0,3}>\s?"#, with: "", options: .regularExpression)

        // 表格分隔行整行丢掉，其余竖线当空格
        text = text.replacingOccurrences(of: #"(?m)^\s*\|?[\s:|-]+\|[\s:|-]*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "|", with: " ")

        // 强调 / 删除线 / 行内代码记号（长记号先删，避免留下半个）
        for token in ["**", "__", "~~", "*", "`"] {
            text = text.replacingOccurrences(of: token, with: "")
        }

        // 压掉多余空行，合成器会把连续空行变成很长的停顿
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
