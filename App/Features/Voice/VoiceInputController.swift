import AVFoundation
import Foundation
import Observation
import Speech

// MARK: - 语音输入状态机
//
// 把「权限 → 引擎启动 → 实时识别 → 收尾提交」这段有状态、可失败、可被打断的流程
// 收成一个可重入的状态机；视图只读 phase，不碰音频对象。
//
// 几条硬约束（都是会直接崩或者串台的坑）：
//
// 1. installTap 只能装一次。重复装会抛 ObjC 异常（required condition is false: nullptr == Tap()），
//    不是 Swift error，接不住。所以：装之前必拆（tapInstalled 闸），拆除只走 stopAudioIO()，幂等。
// 2. 每次开始录音分配一个 sessionID。所有跨 await / 跨回调的地方都先校验它是否还是当前值，
//    过期的直接丢弃 —— 「点开始 → 立刻点停止 → 再点开始」不会串台。
// 3. macOS 没有 AVAudioSession（连符号都没有），平台差异只保留在 #if os(iOS) 里。
//    但录音权限双端都用 AVAudioApplication（iOS 17+/macOS 14+ 同签名），不用 AVAudioSession.requestRecordPermission。
// 4. 没接麦克风时 inputNode 的 format 采样率是 0，这时启动引擎会崩，必须先校验；
//    macOS 还要先确认存在默认输入设备（AVCaptureDevice.default(for: .audio)）。
// 5. 收尾不能只依赖 SFSpeechRecognizer 的 isFinal：网络差时它可能永远不来。
//    用 1.2s 超时兜底，把已经拿到的最好一份 partial 结果提交掉。
// 6. 提交只发生一次（didCommit 闸），避免「最终结果 + 超时」双写把同一段话追加两遍。

// MARK: - 错误

/// 语音输入的可展示错误。刻意做成数据而不是字符串，方便测试断言。
public enum VoiceInputError: LocalizedError, Equatable, Sendable {
    case speechDenied
    case speechRestricted
    case microphoneDenied
    case recognizerUnavailable
    case noMicrophone
    case engineFailed(String)
    case recognitionFailed(String)

    /// alert 标题
    public var title: String {
        switch self {
        case .microphoneDenied: "需要麦克风权限"
        case .speechDenied, .speechRestricted: "需要语音识别权限"
        case .recognizerUnavailable: "语音识别不可用"
        case .noMicrophone: "没有可用的麦克风"
        default: "语音输入失败"
        }
    }

    /// alert 正文：说清楚「为什么」+「怎么办」
    public var message: String {
        switch self {
        case .speechDenied:
            "语音识别权限已被关闭。请在系统设置的「隐私与安全性 → 语音识别」里允许 DeepGlass 使用后重试。"
        case .speechRestricted:
            "当前设备策略限制了语音识别（例如家长控制或 MDM 配置），无法使用语音输入。"
        case .microphoneDenied:
            "麦克风权限已被关闭。请在系统设置的「隐私与安全性 → 麦克风」里允许 DeepGlass 使用后重试。"
        case .recognizerUnavailable:
            "系统当前不支持该语言的语音识别，或服务暂时不可用。可以换一种语言或稍后重试。"
        case .noMicrophone:
            "没有检测到可用的音频输入设备，请连接麦克风后重试。"
        case .engineFailed(let detail):
            "音频引擎启动失败：\(detail)"
        case .recognitionFailed(let detail):
            "识别过程中断：\(detail)"
        }
    }

    public var errorDescription: String? { message }
}

// MARK: - 控制器

@MainActor
@Observable
public final class VoiceInputController {

    /// 录音阶段。视图只需要看这个。
    public enum Phase: Equatable, Sendable {
        case idle
        case preparing   // 取权限 / 起引擎
        case recording
        case finishing   // 已停止收音，等在途的最终结果（有超时兜底）
    }

    // MARK: 对外状态

    public private(set) var phase: Phase = .idle
    /// 实时识别到的文本（给 UI 做预览；目前按钮没用它，但留着便于后续加气泡）
    public private(set) var liveTranscript: String = ""
    /// 录音开始时刻；nil = 没在录
    public private(set) var startedAt: Date?
    /// 最近一次失败原因（视图读它决定弹什么 alert；读完调 clearError()）
    public private(set) var lastError: VoiceInputError?

    /// 识别语言。运行中改语言会取消当前会话，避免「用 zh-CN 的引擎吃 en-US 的音频」。
    public var locale: Locale {
        didSet {
            guard locale != oldValue else { return }
            cancel()
        }
    }

    /// true 时优先走设备端识别（完全离线）。默认 false：让系统自己决定，
    /// 模拟器上 on-device 模型常常不可用，强制它会直接报错。
    public var preferOnDevice: Bool = false

    /// 一段话说完（或超时收尾）后回调一次，参数是已去空白的整段转写。由调用方负责「追加」到输入框。
    public var onCommit: ((String) -> Void)?
    /// 失败回调。权限被拒绝也走这里，视图弹 alert，不崩。
    public var onError: ((VoiceInputError) -> Void)?

    public var isRecording: Bool { phase == .recording }
    public var isBusy: Bool { phase != .idle }

    /// 已录制时长（秒）。视图用 TimelineView 驱动刷新。
    public var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, Date().timeIntervalSince(startedAt))
    }

    // MARK: 内部对象

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var bestTranscript = ""
    @ObservationIgnored private var didCommit = false
    @ObservationIgnored private var finishTimeout: Task<Void, Never>?

    public init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
    }

    // MARK: - 唯一的入口

    /// 一次点击。幂等 + 可重入：任何阶段重复点都不会破坏内部状态。
    public func toggle() {
        switch phase {
        case .idle:
            begin()
        case .preparing:
            // 还没真正开始收音：点名「取消」的语义 —— 撤掉这次会话
            cancel()
        case .recording:
            end()
        case .finishing:
            // 已在收尾，忽略连点，避免重复提交
            break
        }
    }

    /// 彻底中止并丢弃结果（视图消失、切换会话时用）。
    public func cancel() {
        sessionID = nil
        finishTimeout?.cancel()
        finishTimeout = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        stopAudioIO()
        bestTranscript = ""
        liveTranscript = ""
        didCommit = false
        startedAt = nil
        phase = .idle
    }

    // MARK: - 开始

    private func begin() {
        guard phase == .idle else { return }
        let token = UUID()
        sessionID = token
        didCommit = false
        bestTranscript = ""
        liveTranscript = ""
        lastError = nil
        startedAt = nil
        phase = .preparing

        Task { [weak self] in
            await self?.prepareAndStart(token: token)
        }
    }

    private func prepareAndStart(token: UUID) async {
        do {
            try await ensureAuthorized(token: token)
        } catch let error as VoiceInputError {
            fail(error, token: token)
            return
        } catch {
            fail(.engineFailed(error.localizedDescription), token: token)
            return
        }

        // 取权限期间可能已经被取消 / 被新会话顶掉
        guard sessionID == token, phase == .preparing else { return }

        do {
            try startAudio(token: token)
        } catch let error as VoiceInputError {
            fail(error, token: token)
        } catch {
            fail(.engineFailed(error.localizedDescription), token: token)
        }
    }

    private func ensureAuthorized(token: UUID) async throws {
        #if os(macOS)
        // 先看硬件，再看权限：没麦克风时直接给准确原因，不去打扰系统弹窗
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw VoiceInputError.noMicrophone
        }
        #endif

        let speechStatus = await Self.requestSpeechAuthorization()
        guard sessionID == token else { throw CancellationError() }
        switch speechStatus {
        case .authorized: break
        case .denied: throw VoiceInputError.speechDenied
        case .restricted: throw VoiceInputError.speechRestricted
        case .notDetermined: throw VoiceInputError.recognizerUnavailable
        @unknown default: throw VoiceInputError.recognizerUnavailable
        }

        let micGranted = await Self.requestMicrophoneAuthorization()
        guard sessionID == token else { throw CancellationError() }
        guard micGranted else { throw VoiceInputError.microphoneDenied }
    }

    // MARK: - 权限（双端同一套 API）
    //
    // 两个函数必须是 `nonisolated`。在 @MainActor 上下文里写 withCheckedContinuation 时，
    // continuation 的 body 会被推断成主线程隔离，而 Speech / AVAudioApplication 的授权回调
    // 是在 TCC 的后台队列上触发的 —— Swift 6 运行时会做 dispatch_assert_queue 断言并直接
    // SIGTRAP 崩溃（实测：EXC_BREAKPOINT in _swift_task_checkIsolatedSwift / _dispatch_assert_queue_fail）。
    // nonisolated 之后闭包不带隔离，也就不会被断言。
    // 反过来说：单独的 swiftc -typecheck 抓不到这个，必须真跑一次权限流程。

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated private static func requestMicrophoneAuthorization() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    // MARK: - 起引擎

    private func startAudio(token: UUID) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw VoiceInputError.recognizerUnavailable
        }

        #if os(iOS)
        try activateAudioSession()
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // 采样率 0 的 format 塞给 installTap / start 会直接崩
        guard format.sampleRate > 0, format.channelCount > 0 else {
            #if os(iOS)
            deactivateAudioSession()
            #endif
            throw VoiceInputError.noMicrophone
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if preferOnDevice, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        // 先拆后装：同一个 bus 上只允许一个 tap
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        // @Sendable 必须显式写：AVAudioNodeTapBlock 在 SDK 里是 NS_SWIFT_NONSENDABLE，
        // 不标的话闭包会继承 @MainActor 隔离，而它是在音频线程上被调用的 —— 又是一次
        // dispatch_assert_queue 崩溃。
        // sink 用 nonisolated(unsafe)：SFSpeechAudioBufferRecognitionRequest.append 本身就是
        // 给音频回调调用的（官方写法即如此），这里只是把「跨线程共享」这件事说明白。
        nonisolated(unsafe) let sink = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            sink.append(buffer)
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopAudioIO()
            throw VoiceInputError.engineFailed(error.localizedDescription)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            // 回调线程不固定：先把值取成纯数据，再回主线程
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorText = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handle(transcript: transcript, isFinal: isFinal, errorText: errorText, token: token)
            }
        }

        startedAt = .now
        phase = .recording
    }

    // MARK: - 识别回调

    private func handle(transcript: String?, isFinal: Bool, errorText: String?, token: UUID) {
        guard sessionID == token, !didCommit else { return }

        if let transcript, !transcript.isEmpty {
            bestTranscript = transcript
            liveTranscript = transcript
        }

        if let errorText, phase == .recording {
            // 录音途中识别侧自己结束了（没听到人声 / 服务断开 / 单次时长到顶）。
            // 已经有内容就先交出去，别把用户说的话丢掉；一个字都没有才报错。
            if bestTranscript.isEmpty {
                fail(.recognitionFailed(errorText), token: token)
            } else {
                commit(token: token)
            }
            return
        }

        if isFinal {
            commit(token: token)
        }
    }

    // MARK: - 停止

    /// 用户点停止：先断音频输入，再等最终结果；超时用已有 partial 兜底。
    private func end() {
        guard let token = sessionID else {
            cancel()
            return
        }
        recognitionRequest?.endAudio()
        stopAudioIO()
        phase = .finishing

        finishTimeout?.cancel()
        finishTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, !Task.isCancelled else { return }
            self.commit(token: token)
        }
    }

    /// 唯一提交点。守卫 sessionID + didCommit，保证一段话只追加一次。
    private func commit(token: UUID) {
        guard sessionID == token, !didCommit else { return }
        didCommit = true
        finishTimeout?.cancel()
        finishTimeout = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopAudioIO()

        let transcript = bestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        sessionID = nil
        startedAt = nil
        liveTranscript = ""
        phase = .idle

        if !transcript.isEmpty {
            onCommit?(transcript)
        }
    }

    private func fail(_ error: VoiceInputError, token: UUID) {
        guard sessionID == token else { return }
        sessionID = nil
        finishTimeout?.cancel()
        finishTimeout = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopAudioIO()
        bestTranscript = ""
        liveTranscript = ""
        didCommit = false
        startedAt = nil
        phase = .idle
        lastError = error
        onError?(error)
    }

    /// 视图处理完 alert 后调用，避免判断条件一直为真
    public func clearError() {
        lastError = nil
    }

    // MARK: - 音频 IO 收尾（幂等）

    /// 只负责「停止喂音频」。可以在任何阶段重复调用。
    /// 注意：这里不 cancel recognitionTask —— 收尾阶段还要等它的最终结果。
    private func stopAudioIO() {
        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.reset()
        #if os(iOS)
        deactivateAudioSession()
        #endif
    }

    #if os(iOS)
    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .playAndRecord：录音期间不打断朗读（ReadAloudButton）；.measurement 关掉系统音效处理，利于识别
        try session.setCategory(.playAndRecord,
                                mode: .measurement,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    #endif
}
