import SwiftUI
import WebKit

/// 行内公式快照。`depth` 是公式基线到图片底部的距离（点），用来做 `baselineOffset`。
struct InlineMathImage {
    let image: MarkdownPlatformImage
    let size: CGSize
    let depth: CGFloat
}

/// 把行内 `$...$` 渲染成透明 PNG，供 `Text(Image)` 拼回文本流。
///
/// - 内存 NSCache（按 latex + 字号 + 主题）；
/// - 串行使用一个离屏 WKWebView，避免多个公式并发争抢；
/// - 任何失败返回 nil，调用方退回 TeX 源码文本。
@MainActor
final class MathSnapshotRenderer {
    static let shared = MathSnapshotRenderer()

    private struct Rendered {
        let image: MarkdownPlatformImage
        let size: CGSize
        let depth: CGFloat
    }

    private final class CacheBox {
        let value: Rendered
        init(_ value: Rendered) { self.value = value }
    }

    private let cache = NSCache<NSString, CacheBox>()
    private let gate = WebRenderGate()
    private var host: OffscreenWebHost?
    private var loaded = false
    private var loading = false

    private init() {
        cache.countLimit = 64
    }

    func inlineImage(latex: String, fontSize: CGFloat, dark: Bool) async -> InlineMathImage? {
        let key = "\(Int((fontSize * 10).rounded()))|\(dark ? "dark" : "light")|\(latex)"
        if let cached = cache.object(forKey: key as NSString) {
            return InlineMathImage(
                image: cached.value.image,
                size: cached.value.size,
                depth: cached.value.depth
            )
        }

        await gate.acquire()

        if let cached = cache.object(forKey: key as NSString) {
            await gate.release()
            return InlineMathImage(
                image: cached.value.image,
                size: cached.value.size,
                depth: cached.value.depth
            )
        }

        let rendered = await perform(latex: latex, fontSize: fontSize, dark: dark)
        await gate.release()

        guard let rendered else { return nil }
        cache.setObject(CacheBox(rendered), forKey: key as NSString)
        return InlineMathImage(image: rendered.image, size: rendered.size, depth: rendered.depth)
    }

    private func perform(latex: String, fontSize: CGFloat, dark: Bool) async -> Rendered? {
        guard await ensureLoaded(), let host else { return nil }

        host.resize(to: CGSize(width: 1_600, height: 900))

        let arguments: [String: Any] = [
            "tex": latex,
            "display": false,
            "fontSize": Double(fontSize),
            "color": DS.Colors.labelPrimary.markdownCSSColor(dark: dark),
            "codeBg": DS.Colors.inlineCode.markdownCSSColor(dark: dark)
        ]

        guard let result = await WebScriptBridge.call(
            host.webView,
            script: "return await window.__dgRenderMath(tex, display, fontSize, color, codeBg);",
            arguments: arguments
        ), result.ok else {
            return nil
        }

        guard let metrics = await WebScriptBridge.call(
            host.webView,
            script: "return window.__dgMetrics();",
            arguments: [:]
        ), metrics.width > 1, metrics.height > 1 else {
            return nil
        }

        let size = CGSize(
            width: min(CGFloat(metrics.width), 1_560),
            height: min(CGFloat(metrics.height), 880)
        )

        host.resize(to: size)
        try? await Task.sleep(for: .milliseconds(35))

        guard let snapshot = await host.snapshot(
            rect: CGRect(origin: .zero, size: size),
            scale: 2
        ) else {
            return nil
        }

        let image = MarkdownPlatformImage.markdownNormalized(snapshot, to: size)
        return Rendered(image: image, size: size, depth: CGFloat(metrics.depth))
    }

    private func ensureLoaded() async -> Bool {
        if loaded, host != nil { return true }

        if loading {
            for _ in 0..<120 {
                if loaded, host != nil { return true }
                if !loading { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return loaded && host != nil
        }

        loading = true
        defer { loading = false }

        guard let directory = await MarkdownWebAssets.directoryAsync() else { return false }

        let host = self.host ?? OffscreenWebHost(size: CGSize(width: 1_600, height: 900))
        self.host = host

        let ok = await host.load(
            directory.appendingPathComponent("math.html"),
            readAccess: directory,
            readyScript: "typeof window.__dgRenderMath === 'function'"
        )
        loaded = ok
        if !ok {
            self.host = nil
        }
        return ok
    }
}
