import Foundation

/// 把 Bundle 里的 KaTeX / Mermaid 资源暂存到 Caches，供 `loadFileURL` 使用。
///
/// 为什么不直接 `loadHTMLString`：WKWebView 对 html-string 的文件子资源有额外限制，
/// 字体与脚本会加载失败；Xcode 又把资源扁平复制进 bundle，KaTeX 的 `fonts/` 相对路径会失效。
/// 所以首次使用时把资源复制到缓存目录，并把 CSS 里的 `url(fonts/…)` 改写成同目录 `url(./…)`。
///
/// 运行期不联网；资源缺失时返回 nil，上层降级为源码文本。
enum MarkdownWebAssets {

    /// 资源结构变化时 +1，让旧缓存失效。
    private static let version = "2"
    private static let lock = NSLock()

    static func directory() -> URL? {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let root = caches
            .appendingPathComponent("DeepGlass/MarkdownWeb/\(version)", isDirectory: true)
        let readyMarker = root.appendingPathComponent(".ready")

        if fileManager.fileExists(atPath: readyMarker.path) {
            return root
        }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

            try copyIfPresent("katex.min.js", to: root)
            try copyIfPresent("mermaid.min.js", to: root)

            if let cssURL = Bundle.main.url(forResource: "katex.min", withExtension: "css"),
               let css = try? String(contentsOf: cssURL, encoding: .utf8) {
                let patched = css
                    .replacingOccurrences(of: "url(fonts/", with: "url(./")
                    .replacingOccurrences(of: "url(\"fonts/", with: "url(\"./")
                try patched.write(
                    to: root.appendingPathComponent("katex.min.css"),
                    atomically: true,
                    encoding: .utf8
                )
            }

            if let fontURLs = Bundle.main.urls(forResourcesWithExtension: "woff2", subdirectory: nil) {
                for fontURL in fontURLs where fontURL.lastPathComponent.hasPrefix("KaTeX_") {
                    let destination = root.appendingPathComponent(fontURL.lastPathComponent)
                    try? fileManager.removeItem(at: destination)
                    try? fileManager.copyItem(at: fontURL, to: destination)
                }
            }

            try mathHTML.write(to: root.appendingPathComponent("math.html"), atomically: true, encoding: .utf8)
            try mermaidHTML.write(to: root.appendingPathComponent("mermaid.html"), atomically: true, encoding: .utf8)

            try Data().write(to: readyMarker)
            return root
        } catch {
            try? fileManager.removeItem(at: root)
            return nil
        }
    }

    /// 后台暂存（首次会复制 6MB 左右的资源，不能放在主线程）。
    static func directoryAsync() async -> URL? {
        await Task.detached(priority: .userInitiated) { directory() }.value
    }

    static func pageURL(named name: String) -> (url: URL, directory: URL)? {
        guard let directory = directory() else { return nil }
        return (directory.appendingPathComponent(name), directory)
    }

    private static func copyIfPresent(_ name: String, to directory: URL) throws {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let source = Bundle.main.url(forResource: parts[0], withExtension: parts[1]) else {
            return
        }
        let destination = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    // MARK: - KaTeX 页面

    private static let mathHTML = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<link rel="stylesheet" href="katex.min.css">
<style>
  html, body { margin: 0; padding: 0; background: transparent; }
  body {
    -webkit-font-smoothing: antialiased;
    font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", "PingFang SC", sans-serif;
    line-height: 1.5;
    overflow-x: auto;
    overflow-y: hidden;
  }
  #root { padding: 2px; }
  .katex { font-size: 1.21em; }
  .katex-display { margin: 0; padding: 2px 0; text-align: center; }
  .dg-fallback {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.9em;
    white-space: pre-wrap;
    word-break: break-word;
    background: rgba(127,127,127,0.12);
    border-radius: 6px;
    padding: 4px 6px;
    display: inline-block;
  }
</style>
</head>
<body>
<div id="root"></div>
<script src="katex.min.js"></script>
<script>
(function () {
  var root = document.getElementById('root');
  var baseline = null;
  var bridge = (window.webkit && window.webkit.messageHandlers) ? window.webkit.messageHandlers.dgMath : null;
  var lastHeight = -1;

  function postHeight() {
    var height = Math.ceil(document.body.scrollHeight);
    if (height !== lastHeight && bridge) {
      lastHeight = height;
      bridge.postMessage({ type: 'height', height: height });
    }
  }

  function makeBaseline() {
    var marker = document.createElement('span');
    marker.id = 'dg-baseline';
    marker.style.cssText = 'display:inline-block;width:0;height:0;vertical-align:baseline';
    return marker;
  }

  function showFallback(tex) {
    root.innerHTML = '';
    var block = document.createElement('div');
    block.className = 'dg-fallback';
    block.textContent = tex;
    root.appendChild(block);
    baseline = makeBaseline();
    root.appendChild(baseline);
  }

  window.__dgRenderMath = async function (tex, display, fontSize, color, codeBg) {
    document.body.style.fontSize = fontSize + 'px';
    document.body.style.color = color;
    root.style.display = display ? 'block' : 'inline-block';
    root.style.setProperty('--dg-code-bg', codeBg);
    root.innerHTML = '';

    var target = document.createElement('div');
    if (display) { target.style.textAlign = 'center'; }
    root.appendChild(target);

    var ok = true;
    try {
      if (!window.katex) { throw new Error('katex-unavailable'); }
      katex.render(tex, target, {
        displayMode: !!display,
        throwOnError: true,
        strict: false,
        trust: false
      });
      baseline = makeBaseline();
      target.appendChild(baseline);
    } catch (error) {
      ok = false;
      showFallback(tex);
      if (bridge) {
        bridge.postMessage({ type: 'error', message: String(error && error.message ? error.message : error) });
      }
    }

    try {
      await Promise.race([
        document.fonts.ready,
        new Promise(function (resolve) { setTimeout(resolve, 800); })
      ]);
    } catch (error) {}
    await new Promise(function (resolve) { setTimeout(resolve, 30); });
    postHeight();
    setTimeout(postHeight, 120);
    return ok;
  };

  window.__dgMetrics = function () {
    var rect = root.getBoundingClientRect();
    var top = baseline ? baseline.getBoundingClientRect().top : rect.top;
    return {
      width: Math.ceil(rect.width),
      height: Math.ceil(rect.height),
      depth: Math.max(0, Math.ceil(rect.bottom - top))
    };
  };

  window.__dgMeasure = function () {
    lastHeight = -1;
    postHeight();
    return document.body.scrollHeight;
  };

  if (window.ResizeObserver) {
    new ResizeObserver(function () { postHeight(); }).observe(document.body);
  }
  window.addEventListener('load', postHeight);
})();
</script>
</body>
</html>
"""#

    // MARK: - Mermaid 页面

    private static let mermaidHTML = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; padding: 0; background: transparent; }
  body {
    -webkit-font-smoothing: antialiased;
    font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", "PingFang SC", sans-serif;
    overflow: hidden;
  }
  #root { display: inline-block; padding: 0; }
  #root svg { display: block; max-width: 100%; height: auto; margin: 0 auto; }
  .dg-error {
    font: 12px ui-monospace, SFMono-Regular, Menlo, monospace;
    color: #8a8f98;
    padding: 12px;
  }
</style>
</head>
<body>
<div id="root"></div>
<script src="mermaid.min.js"></script>
<script>
window.__dgReady = false;
(function () {
  function mermaidAPI() {
    if (window.mermaid) { return window.mermaid; }
    try {
      var namespace = window.__esbuild_esm_mermaid_nm;
      if (namespace && namespace.mermaid) {
        return namespace.mermaid.default || namespace.mermaid;
      }
    } catch (error) {}
    return null;
  }

  function settle() {
    return new Promise(function (resolve) { setTimeout(resolve, 40); });
  }

  window.__dgRenderMermaid = async function (code, theme, width, fontFamily) {
    var root = document.getElementById('root');
    try {
      var mermaid = mermaidAPI();
      if (!mermaid) { throw new Error('mermaid-unavailable'); }

      var dark = theme === 'dark';
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'strict',
        theme: dark ? 'dark' : 'default',
        fontFamily: fontFamily,
        flowchart: { htmlLabels: true, useMaxWidth: true },
        themeVariables: dark
          ? {
              background: 'transparent',
              primaryColor: '#2C2C2E',
              primaryTextColor: '#F9FAFB',
              primaryBorderColor: '#4A4A4E',
              lineColor: '#ADB2B8',
              secondaryColor: '#353638',
              tertiaryColor: '#1B1B1C',
              fontSize: '13px'
            }
          : {
              background: 'transparent',
              primaryColor: '#EDF3FE',
              primaryTextColor: '#0F1115',
              primaryBorderColor: '#B9C7E6',
              lineColor: '#61666B',
              secondaryColor: '#F1F3F5',
              tertiaryColor: '#FFFFFF',
              fontSize: '13px'
            }
      });

      root.innerHTML = '';
      root.style.maxWidth = width > 0 ? (width + 'px') : 'none';
      var id = 'dg-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
      var output = await mermaid.render(id, code);
      root.innerHTML = output.svg;

      var svg = root.querySelector('svg');
      if (!svg) { throw new Error('empty-svg'); }
      svg.removeAttribute('height');
      svg.style.maxWidth = '100%';
      svg.style.height = 'auto';
      svg.style.display = 'block';
      svg.style.margin = '0 auto';

      try {
        await Promise.race([
          document.fonts.ready,
          new Promise(function (resolve) { setTimeout(resolve, 800); })
        ]);
      } catch (error) {}
      await settle();

      var rect = root.getBoundingClientRect();
      return {
        ok: true,
        width: Math.ceil(rect.width),
        height: Math.ceil(rect.height)
      };
    } catch (error) {
      root.innerHTML = '';
      var message = document.createElement('div');
      message.className = 'dg-error';
      message.textContent = 'Mermaid render failed: ' + (error && error.message ? error.message : String(error));
      root.appendChild(message);
      return { ok: false, error: String(error && error.message ? error.message : error) };
    }
  };

  window.__dgReady = true;
})();
</script>
</body>
</html>
"""#
}
