import CryptoKit
import SwiftUI
import WebKit

struct MermaidImage {
    let image: MarkdownPlatformImage
    let size: CGSize
}

/// ```mermaid 围栏 → WKWebView 渲染 → 截图 PNG。
///
/// 缓存策略：key = SHA256(版本 | 主题 | 宽度档位 | 源码)，PNG + 尺寸 sidecar 写入
/// `Caches/DeepGlass/Mermaid/`，重启后仍然命中；内存里再套一层 NSCache。
@MainActor
final class MermaidRenderer {
    static let shared = MermaidRenderer()

    private final class CacheBox {
        let value: MermaidImage
        init(_ value: MermaidImage) { self.value = value }
    }

    private let cache = NSCache<NSString, CacheBox>()
    private let gate = WebRenderGate()
    private let fileManager = FileManager.default
    private var host: OffscreenWebHost?
    private var loaded = false
    private var loading = false

    private init() {
        cache.countLimit = 32
    }

    // MARK: 公共入口

    func cachedImage(code: String, width: CGFloat, dark: Bool) -> MermaidImage? {
        let key = cacheKey(code: code, width: width, dark: dark)
        if let box = cache.object(forKey: key as NSString) {
            return box.value
        }
        guard let disk = loadFromDisk(key: key) else { return nil }
        cache.setObject(CacheBox(disk), forKey: key as NSString)
        return disk
    }

    func render(code: String, width: CGFloat, dark: Bool) async -> MermaidImage? {
        let key = cacheKey(code: code, width: width, dark: dark)

        if let cached = cachedImage(code: code, width: width, dark: dark) {
            return cached
        }

        await gate.acquire()

        if let cached = cachedImage(code: code, width: width, dark: dark) {
            await gate.release()
            return cached
        }

        let rendered = await perform(code: code, width: width, dark: dark, key: key)
        await gate.release()

        if let rendered {
            cache.setObject(CacheBox(rendered), forKey: key as NSString)
        }
        return rendered
    }

    // MARK: 渲染

    private func perform(code: String, width: CGFloat, dark: Bool, key: String) async -> MermaidImage? {
        guard await ensureLoaded(), let host else { return nil }

        let bucket = bucketWidth(width)
        host.resize(to: CGSize(width: bucket, height: 800))

        let arguments: [String: Any] = [
            "code": code,
            "theme": dark ? "dark" : "light",
            "width": Double(bucket),
            "fontFamily": "-apple-system, BlinkMacSystemFont, \"Helvetica Neue\", sans-serif"
        ]

        guard let result = await WebScriptBridge.call(
            host.webView,
            script: "return await window.__dgRenderMermaid(code, theme, width, fontFamily);",
            arguments: arguments
        ), result.ok, result.width > 1, result.height > 1 else {
            return nil
        }

        let size = CGSize(
            width: min(CGFloat(result.width), 1_600),
            height: min(CGFloat(result.height), 4_000)
        )

        host.resize(to: size)
        try? await Task.sleep(for: .milliseconds(40))

        guard let snapshot = await host.snapshot(
            rect: CGRect(origin: .zero, size: size),
            scale: 2
        ) else {
            return nil
        }

        let image = MarkdownPlatformImage.markdownNormalized(snapshot, to: size)
        persist(image: image, size: size, key: key)
        return MermaidImage(image: image, size: size)
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

        let host = self.host ?? OffscreenWebHost(size: CGSize(width: 1_200, height: 800))
        self.host = host

        let ok = await host.load(
            directory.appendingPathComponent("mermaid.html"),
            readAccess: directory,
            readyScript: "window.__dgReady === true && typeof window.__dgRenderMermaid === 'function'"
        )
        loaded = ok
        if !ok {
            self.host = nil
        }
        return ok
    }

    // MARK: 缓存

    private func bucketWidth(_ width: CGFloat) -> CGFloat {
        max(160, (width / 10).rounded() * 10)
    }

    private func cacheKey(code: String, width: CGFloat, dark: Bool) -> String {
        let bucket = Int(bucketWidth(width))
        let payload = "mermaid-v1|\(dark ? 1 : 0)|\(bucket)|\(code)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var cacheDirectory: URL? {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = caches.appendingPathComponent("DeepGlass/Mermaid", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func loadFromDisk(key: String) -> MermaidImage? {
        guard let directory = cacheDirectory else { return nil }
        let pngURL = directory.appendingPathComponent(key + ".png")
        let metaURL = directory.appendingPathComponent(key + ".json")

        guard fileManager.fileExists(atPath: pngURL.path),
              let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let width = (meta["w"] as? NSNumber)?.doubleValue,
              let height = (meta["h"] as? NSNumber)?.doubleValue,
              width > 1, height > 1 else {
            return nil
        }

        let size = CGSize(width: width, height: height)
        guard let image = MarkdownPlatformImage.markdownDecoded(contentsOf: pngURL, pointSize: size) else {
            return nil
        }
        return MermaidImage(image: image, size: size)
    }

    private func persist(image: MarkdownPlatformImage, size: CGSize, key: String) {
        guard let directory = cacheDirectory else { return }

        #if canImport(AppKit)
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:]) else {
            return
        }
        #else
        guard let png = image.pngData() else { return }
        #endif

        let metadata = try? JSONSerialization.data(withJSONObject: ["w": size.width, "h": size.height])
        let pngURL = directory.appendingPathComponent(key + ".png")
        let metaURL = directory.appendingPathComponent(key + ".json")

        Task.detached(priority: .utility) {
            try? png.write(to: pngURL)
            if let metadata {
                try? metadata.write(to: metaURL)
            }
        }
    }
}
