import SwiftUI

/// 输入框：自适应高度文本域 + 模型/深度思考/智能搜索/推理强度 + 附件 + 发送/停止
struct ComposerView: View {
    @Binding var text: String
    @Binding var thinking: Bool
    @Binding var search: Bool
    /// 当前模型 id（`ModelOption.id`）。会话页绑会话、欢迎页绑全局设置。
    @Binding var model: String
    /// 推理强度（全局设置；仅深度思考开启时显示入口）
    @Binding var reasoningEffort: ReasoningEffort
    var isStreaming: Bool
    var canSend: Bool
    /// nil 表示按当前语言取 `chatInputPlaceholderChat`
    var placeholder: String? = nil
    var onSend: () -> Void
    var onStop: () -> Void
    var onAttach: (() -> Void)? = nil
    var isHome: Bool = false
    var attachments: [FileAttachment] = []
    var attachmentProgress: [String: Double] = [:]
    var onRemoveAttachment: ((String) -> Void)? = nil
    var onRetryAttachment: ((String) -> Void)? = nil
    /// 文件正被拖到窗口上：高亮外壳描边，与页面级蒙层配合。
    var isDropTargeted: Bool = false

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var attachHovered = false
    /// 功能行实测宽度：窗口被拉窄时也要收起文字标签，不能只依赖 sizeClass。
    @State private var measuredWidth: CGFloat = .infinity

    var body: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                AttachmentStrip(
                    items: attachments,
                    onRemove: { onRemoveAttachment?($0) },
                    onRetry: { onRetryAttachment?($0) },
                    progress: attachmentProgress
                )
                .padding(.top, 12)
            }
            field
            functionRow
        }
        .background(containerBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    isDropTargeted ? DS.Colors.brandPrimary
                        : dynAlpha(0x000000, 0.10, 0xFFFFFF, 0.06),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(isHome ? 0.18 : 0.12), radius: isHome ? 30 : 10, y: isHome ? 16 : 4)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, width in
            // 只在变化明显时写回，避免布局微调引起状态抖动
            if abs(width - measuredWidth) > 1 { measuredWidth = width }
        }
        .animation(DS.Motion.fastEase, value: isDropTargeted)
    }

    // MARK: 文本区

    private var field: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder ?? L10n.t(.chatInputPlaceholderChat))
                .foregroundStyle(DS.Colors.labelTertiary),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .lineSpacing(4)
        .lineLimit(2...12)
        .focused($focused)
        .onSubmit {
            if canSend { onSend() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        #if os(iOS)
        .submitLabel(.send)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 功能行

    /// 紧凑宽度（iPhone、iPad 分屏、被拉窄的 macOS 窗口）下开关只留图标，
    /// 否则「模型 + 深度思考 + 智能搜索 + 推理强度 + 麦克风 + 附件 + 发送」会挤爆一行。
    private var pillsCompact: Bool {
        #if os(iOS)
        if horizontalSizeClass == .compact { return true }
        #endif
        // 700 是英文标签（Deep thinking / Smart search / Reasoning）也能容下的下限；
        // 再窄就收起文字，避免功能行溢出。
        return measuredWidth < 700
    }

    private var functionRow: some View {
        HStack(spacing: 8) {
            modelMenu
            TogglePill(isOn: $thinking, systemImage: "brain", title: L10n.t(.thinkingSwitch),
                       help: L10n.t(.deactivatedThinkTooltip), compact: pillsCompact)
            TogglePill(isOn: $search, systemImage: "globe", title: L10n.t(.search),
                       help: L10n.t(.deactivatedSearchTooltip), compact: pillsCompact)
            if thinking {
                effortControl
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            Spacer(minLength: 0)
            VoiceInputButton(text: $text)
            if let onAttach {
                Button(action: onAttach) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(DS.Colors.labelSecondary)
                        .frame(width: 34, height: 34)
                        .background {
                            Circle().fill(attachHovered ? DS.Colors.interactiveHover : .clear)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { attachHovered = $0 }
                .help(L10n.t(.uploadFile))
                .accessibilityLabel(L10n.t(.uploadFile))
            }
            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 2)
        .animation(DS.Motion.fastEase, value: thinking)
        .animation(DS.Motion.fastEase, value: pillsCompact)
    }

    // MARK: 模型切换

    private var modelLabel: String {
        ModelOption.label(for: model)
    }

    /// 功能行空间有限，宽标签去掉产品前缀（DeepSeek Flash → Flash）。
    private var modelShortLabel: String {
        let label = modelLabel
        let prefix = "DeepSeek "
        return label.hasPrefix(prefix) ? String(label.dropFirst(prefix.count)) : label
    }

    private var modelMenu: some View {
        Menu {
            Section(ComposerCopy.modelTitle) {
                ForEach(ModelOption.all) { option in
                    Button {
                        model = option.id
                    } label: {
                        if option.id == model {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if !pillsCompact {
                    Image(systemName: "cpu")
                        .font(.system(size: 12.5, weight: .regular))
                }
                Text(modelShortLabel)
                    .font(pillsCompact ? .system(size: 12, weight: .medium) : DS.Typography.body)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Colors.labelTertiary)
            }
            .pillChrome(active: false, hovered: false, compact: pillsCompact)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(ComposerCopy.modelTitle + "：" + modelLabel)
        .accessibilityLabel(ComposerCopy.modelTitle)
        .accessibilityValue(modelLabel)
    }

    // MARK: 推理强度（仅深度思考开启时出现）

    /// 短标签：紧凑宽度下用单字，避免把功能行挤爆。
    private var effortShortLabel: String {
        ComposerCopy.effortShort(reasoningEffort)
    }

    @ViewBuilder
    private var effortControl: some View {
        if pillsCompact {
            Menu {
                Section(ComposerCopy.reasoningTitle) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Button {
                            reasoningEffort = effort
                        } label: {
                            if effort == reasoningEffort {
                                Label(effort.label, systemImage: "checkmark")
                            } else {
                                Text(effort.label)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(effortShortLabel)
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DS.Colors.labelTertiary)
                }
                .pillChrome(active: true, hovered: false, compact: true)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(ComposerCopy.reasoningTitle + "：" + reasoningEffort.label)
            .accessibilityLabel(ComposerCopy.reasoningTitle)
            .accessibilityValue(reasoningEffort.label)
        } else {
            HStack(spacing: 2) {
                ForEach(ReasoningEffort.allCases) { effort in
                    Button {
                        reasoningEffort = effort
                    } label: {
                        Text(effort.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(effort == reasoningEffort
                                             ? DS.Colors.brandText
                                             : DS.Colors.labelSecondary)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background {
                                Capsule().fill(effort == reasoningEffort
                                               ? DS.Colors.brandSubtle
                                               : Color.clear)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(effort.blurb)
                    .accessibilityLabel("\(ComposerCopy.reasoningTitle)：\(effort.label)")
                    .accessibilityAddTraits(effort == reasoningEffort ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background { Capsule().fill(DS.Colors.interactiveHover) }
            .overlay {
                Capsule().strokeBorder(DS.Colors.borderL2, lineWidth: 1)
            }
            .help(ComposerCopy.reasoningTitle)
        }
    }

    private var sendButton: some View {
        Button {
            if isStreaming { onStop() } else if canSend { onSend() }
        } label: {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background {
                    Circle()
                        .fill(DS.Colors.brandPrimary)
                        .opacity(isStreaming || canSend ? 1 : 0.28)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isStreaming && !canSend)
        .help(isStreaming ? L10n.t(.chatInputStopButtonTooltip) : L10n.t(.send))
        .accessibilityLabel(isStreaming ? L10n.t(.chatInputStopButtonTooltip) : L10n.t(.send))
    }

    // MARK: 外壳玻璃（A1：只在外壳层）

    @ViewBuilder
    private var containerBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 24).fill(DS.Colors.inputFill)
        } else {
            // 玻璃层次：半透明底 → 玻璃 → 顶部高光。
            // 纯实色会让 glassEffect 完全不可见，只剩一个灰盒子。
            RoundedRectangle(cornerRadius: 24)
                .fill(DS.Colors.inputFill.opacity(0.72))
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
        }
    }
}

// MARK: - 胶囊外壳

/// 功能行上胶囊按钮的统一外观（模型菜单、推理强度）。
private struct PillChrome: ViewModifier {
    var active: Bool
    var hovered: Bool
    var compact: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(active ? DS.Colors.brandText : DS.Colors.labelSecondary)
            .padding(.horizontal, compact ? 8 : 10)
            .frame(height: 34)
            .frame(minWidth: compact ? 34 : nil)
            .background {
                Capsule()
                    .fill(active ? DS.Colors.brandSubtle
                          : (hovered ? DS.Colors.interactiveHover : Color.clear))
            }
            .overlay {
                Capsule()
                    .strokeBorder(active ? DS.Colors.brandPrimary.opacity(0.45)
                                  : DS.Colors.borderL2,
                                  lineWidth: 1)
            }
            .contentShape(Capsule())
    }
}

private extension View {
    func pillChrome(active: Bool, hovered: Bool, compact: Bool) -> some View {
        modifier(PillChrome(active: active, hovered: hovered, compact: compact))
    }
}

// MARK: - 开关胶囊

private struct TogglePill: View {
    @Binding var isOn: Bool
    let systemImage: String
    let title: String
    var help: String
    var compact: Bool = false
    @State private var hovered = false

    var body: some View {
        Button {
            withAnimation(DS.Motion.fastEase) { isOn.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                if !compact {
                    Text(title)
                        .font(DS.Typography.body)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isOn ? DS.Colors.brandText : DS.Colors.labelSecondary)
            .padding(.horizontal, compact ? 0 : 12)
            .frame(width: compact ? 34 : nil, height: 34)
            .background {
                Capsule()
                    .fill(isOn ? DS.Colors.brandSubtle : (hovered ? DS.Colors.interactiveHover : .clear))
            }
            .overlay {
                Capsule()
                    .strokeBorder(isOn ? DS.Colors.brandPrimary.opacity(0.45) : DS.Colors.borderL2,
                                  lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - 拖拽文件入窗

/// 拖拽文件的通用接线：接受 Finder / 文件 App 拖入的**文件** URL，
/// 拖拽中在视图上盖一层「松开以添加文件」蒙层（玻璃 + DS 令牌）。
///
/// 只取文件 URL：从浏览器拖来的 http 链接、纯文本等一律不接，避免把非文件当附件。
/// 权限受限（沙盒外路径、无访问权）不在这里拦截 —— `FileUploader` 读取失败时
/// 会把附件置为 `.failed`，UI 显示失败态并提供重试，不会崩溃。
struct FileDropTargetModifier: ViewModifier {
    @Binding var isTargeted: Bool
    var onFiles: ([URL]) -> Void

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                onFiles(files)
                return true
            } isTargeted: { targeted in
                withAnimation(DS.Motion.fastEase) { isTargeted = targeted }
            }
            .overlay {
                if isTargeted {
                    DropHintOverlay()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// 让视图接收拖入的文件，并在拖拽中显示高亮蒙层。
    func fileDropTarget(isTargeted: Binding<Bool>, onFiles: @escaping ([URL]) -> Void) -> some View {
        modifier(FileDropTargetModifier(isTargeted: isTargeted, onFiles: onFiles))
    }
}

/// 拖拽中的轻量蒙层：整页压暗 + 虚线框 + 居中提示卡片。
struct DropHintOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Rectangle()
                .fill(DS.Colors.bgBase.opacity(reduceTransparency ? 0.94 : 0.55))

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    DS.Colors.brandPrimary,
                    style: StrokeStyle(lineWidth: 2, dash: [9, 6])
                )
                .padding(DS.Spacing.l + 8)

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(DS.Colors.brandText)
                Text(ComposerCopy.dropHint)
                    .font(DS.Typography.bodyMedium)
                    .foregroundStyle(DS.Colors.labelPrimary)
                Text(ComposerCopy.dropHintDetail)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.labelTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(DS.Colors.inputFill)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(DS.Colors.inputFill.opacity(0.72))
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(DS.Colors.borderL2, lineWidth: 1)
            }
        }
    }
}

// MARK: - 输入区文案

/// 输入区新增文案。资源表里没有对应键，这里按当前语言就地取，
/// 不改 L10n / 资源文件（那不在本改造范围内）。
@MainActor
enum ComposerCopy {
    private static var isZh: Bool { L10n.language == .zhHans }

    static func t(_ zh: String, _ en: String) -> String { isZh ? zh : en }

    static var modelTitle: String { t("模型", "Model") }
    static var reasoningTitle: String { t("推理强度", "Reasoning effort") }
    static var dropHint: String { t("松开以添加文件", "Drop to add files") }
    static var dropHintDetail: String {
        t("文件会作为附件加入本次提问", "Files will be attached to this message")
    }

    /// 紧凑宽度下的单字短标签
    static func effortShort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .fast: t("快", "S")
        case .standard: t("标", "M")
        case .deep: t("深", "D")
        }
    }
}
