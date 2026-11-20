import SwiftUI
import WebKit

/// 块级公式的 Web 岛。
///
/// - `isOpaque = false` + 透明背景，跟随深浅色；
/// - JS 通过 `document.body.scrollHeight` 经 message handler 回传高度；
/// - 字体随 Dynamic Type 缩放，字号变化会重新渲染并重算高度；
/// - 4 秒没有高度或 JS 报错就调用 `onFailure`，上层降级为 TeX 源码。
struct MathWebView {
    let latex: String
    let displayMode: Bool
    let fontSize: CGFloat
    let dark: Bool
    @Binding var height: CGFloat
    var onFailure: () -> Void
}

#if os(macOS)

extension MathWebView: NSViewRepresentable {
    func makeCoordinator() -> MathWebCoordinator {
        MathWebCoordinator(
            latex: latex,
            displayMode: displayMode,
            fontSize: fontSize,
            dark: dark,
            height: $height,
            onFailure: onFailure
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(
            latex: latex,
            displayMode: displayMode,
            fontSize: fontSize,
            dark: dark
        )
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: MathWebCoordinator) {
        coordinator.tearDown()
    }
}

#else

extension MathWebView: UIViewRepresentable {
    func makeCoordinator() -> MathWebCoordinator {
        MathWebCoordinator(
            latex: latex,
            displayMode: displayMode,
            fontSize: fontSize,
            dark: dark,
            height: $height,
            onFailure: onFailure
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(
            latex: latex,
            displayMode: displayMode,
            fontSize: fontSize,
            dark: dark
        )
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: MathWebCoordinator) {
        coordinator.tearDown()
    }
}

#endif

// MARK: - Coordinator

@MainActor
final class MathWebCoordinator: NSObject, WKScriptMessageHandler {

    private let webView: WKWebView
    private let height: Binding<CGFloat>
    private let onFailure: () -> Void

    private var latex: String
    private var displayMode: Bool
    private var fontSize: CGFloat
    private var dark: Bool

    private var isLoaded = false
    private var isLoading = false
    private var didReportHeight = false
    private var didFail = false
    private var timeoutTask: Task<Void, Never>?

    init(
        latex: String,
        displayMode: Bool,
        fontSize: CGFloat,
        dark: Bool,
        height: Binding<CGFloat>,
        onFailure: @escaping () -> Void
    ) {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        self.latex = latex
        self.displayMode = displayMode
        self.fontSize = fontSize
        self.dark = dark
        self.height = height
        self.onFailure = onFailure
        super.init()

        webView.configuration.userContentController.add(self, name: "dgMath")
        #if canImport(AppKit)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        #endif
    }

    func makeWebView() -> WKWebView {
        startLoading()
        return webView
    }

    func update(latex: String, displayMode: Bool, fontSize: CGFloat, dark: Bool) {
        let changed = latex != self.latex
            || displayMode != self.displayMode
            || abs(fontSize - self.fontSize) > 0.01
            || dark != self.dark

        guard changed else { return }

        self.latex = latex
        self.displayMode = displayMode
        self.fontSize = fontSize
        self.dark = dark
        didFail = false

        if isLoaded {
            render()
        } else {
            startLoading()
        }
    }

    func tearDown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "dgMath")
        webView.stopLoading()
    }

    // MARK: 加载

    private func startLoading() {
        guard !isLoaded, !isLoading else { return }
        isLoading = true

        Task { @MainActor in
            guard let directory = await MarkdownWebAssets.directoryAsync() else {
                self.isLoading = false
                self.fail()
                return
            }

            let page = directory.appendingPathComponent("math.html")
            self.webView.loadFileURL(page, allowingReadAccessTo: directory)

            for _ in 0..<100 {
                try? await Task.sleep(for: .milliseconds(50))

                if let value = try? await self.webView.evaluateJavaScript(
                    "typeof window.__dgRenderMath === 'function'"
                ) {
                    let ready = (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false
                    if ready {
                        self.isLoading = false
                        self.isLoaded = true
                        self.render()
                        return
                    }
                }
            }

            self.isLoading = false
            self.fail()
        }
    }

    // MARK: 渲染

    private func render() {
        guard isLoaded, !didFail else { return }
        didReportHeight = false

        let arguments: [String: Any] = [
            "tex": latex,
            "display": displayMode,
            "fontSize": Double(fontSize),
            "color": DS.Colors.labelPrimary.markdownCSSColor(dark: dark),
            "codeBg": DS.Colors.inlineCode.markdownCSSColor(dark: dark)
        ]

        webView.callAsyncJavaScript(
            "return await window.__dgRenderMath(tex, display, fontSize, color, codeBg);",
            arguments: arguments,
            in: nil,
            in: .page,
            completionHandler: nil
        )

        scheduleTimeout()
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if !self.didReportHeight {
                self.fail()
            }
        }
    }

    private func fail() {
        guard !didFail else { return }
        didFail = true
        onFailure()
    }

    // MARK: 消息

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            self.handle(message)
        }
    }

    private func handle(_ message: WKScriptMessage) {
        guard message.name == "dgMath",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        if type == "height" {
            guard let number = body["height"] as? NSNumber else { return }
            let value = max(0, CGFloat(truncating: number))
            didReportHeight = true
            timeoutTask?.cancel()
            if abs(value - height.wrappedValue) > 0.5 {
                height.wrappedValue = value
            }
        } else if type == "error" {
            fail()
        }
    }
}
