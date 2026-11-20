import SwiftUI
import WebKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - 离屏 WebView 宿主

/// 不挂在 SwiftUI 树上的 WKWebView，放在屏幕外的 borderless 窗口里渲染。
/// 用于 mermaid 截图与行内公式快照；所有调用都在主线程。
@MainActor
final class OffscreenWebHost {
    let webView: WKWebView

    #if canImport(AppKit)
    private var window: NSWindow?
    #else
    private var window: UIWindow?
    #endif

    init(size: CGSize) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        #if canImport(AppKit)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        #endif
        self.webView = webView

        #if canImport(AppKit)
        let window = NSWindow(
            contentRect: CGRect(x: -30_000, y: -30_000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = webView
        window.orderBack(nil)
        self.window = window
        #else
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: -30_000, y: -30_000, width: size.width, height: size.height)
            let controller = UIViewController()
            controller.view.backgroundColor = .clear
            controller.view.addSubview(webView)
            window.rootViewController = controller
            window.isHidden = false
            self.window = window
        }
        #endif
    }

    func resize(to size: CGSize) {
        let clamped = CGSize(
            width: max(1, min(size.width, 2_000)),
            height: max(1, min(size.height, 8_000))
        )
        webView.frame = CGRect(origin: .zero, size: clamped)
        #if canImport(AppKit)
        window?.setContentSize(clamped)
        #else
        window?.frame = CGRect(x: -30_000, y: -30_000, width: clamped.width, height: clamped.height)
        #endif
    }

    func load(_ url: URL, readAccess: URL, readyScript: String) async -> Bool {
        webView.loadFileURL(url, allowingReadAccessTo: readAccess)
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return false }
            if let value = try? await webView.evaluateJavaScript(readyScript) {
                if let bool = value as? Bool, bool { return true }
                if let number = value as? NSNumber, number.boolValue { return true }
            }
        }
        return false
    }

    func snapshot(rect: CGRect, scale: CGFloat) async -> MarkdownPlatformImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<MarkdownPlatformImage?, Never>) in
            let configuration = WKSnapshotConfiguration()
            configuration.rect = rect
            configuration.snapshotWidth = NSNumber(value: Double(rect.width * scale))
            webView.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - 串行门

/// 让多个 Web 渲染请求在同一个离屏 WebView 上串行执行。
actor WebRenderGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if busy {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        } else {
            busy = true
        }
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

// MARK: - JS 调用

struct WebCallResult: Sendable {
    var ok: Bool
    var width: Double
    var height: Double
    var depth: Double
    var error: String?
}

enum WebScriptBridge {
    @MainActor
    static func call(
        _ webView: WKWebView,
        script: String,
        arguments: [String: Any]
    ) async -> WebCallResult? {
        await withCheckedContinuation { (continuation: CheckedContinuation<WebCallResult?, Never>) in
            webView.callAsyncJavaScript(
                script,
                arguments: arguments,
                in: nil,
                in: .page
            ) { result in
                switch result {
                case .success(let value):
                    // __dgRenderMath 返回 Bool，mermaid 返回字典；两种都要接。
                    if let flag = value as? Bool {
                        continuation.resume(returning: WebCallResult(
                            ok: flag, width: 0, height: 0, depth: 0, error: nil
                        ))
                        return
                    }
                    if let number = value as? NSNumber {
                        continuation.resume(returning: WebCallResult(
                            ok: number.boolValue, width: 0, height: 0, depth: 0, error: nil
                        ))
                        return
                    }
                    let dictionary = value as? [String: Any]
                    let okNumber = dictionary?["ok"] as? NSNumber
                    let okBool = dictionary?["ok"] as? Bool
                    continuation.resume(returning: WebCallResult(
                        ok: okBool ?? okNumber?.boolValue ?? false,
                        width: (dictionary?["width"] as? NSNumber)?.doubleValue ?? 0,
                        height: (dictionary?["height"] as? NSNumber)?.doubleValue ?? 0,
                        depth: (dictionary?["depth"] as? NSNumber)?.doubleValue ?? 0,
                        error: dictionary?["error"] as? String
                    ))
                case .failure(let error):
                    continuation.resume(returning: WebCallResult(
                        ok: false,
                        width: 0,
                        height: 0,
                        depth: 0,
                        error: error.localizedDescription
                    ))
                }
            }
        }
    }
}

// MARK: - 图片归一化

extension MarkdownPlatformImage {
    /// 把快照按 CSS 点数重新归一化，保证 `Text(Image)` / `Image` 用点尺寸排版。
    static func markdownNormalized(_ image: MarkdownPlatformImage, to size: CGSize) -> MarkdownPlatformImage {
        #if canImport(AppKit)
        let copy = image.copy() as? NSImage ?? image
        copy.size = size
        return copy
        #else
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        #endif
    }

    static func markdownDecoded(contentsOf url: URL, pointSize: CGSize) -> MarkdownPlatformImage? {
        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = pointSize
        return image
        #else
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data, scale: 2) else {
            return nil
        }
        return image
        #endif
    }
}
