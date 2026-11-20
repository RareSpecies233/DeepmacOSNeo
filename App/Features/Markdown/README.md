# Markdown 渲染层

SwiftUI 原生渲染 DeepSeek Chat 的 GFM 子集 + `$...$` / `$$...$$` 数学 + mermaid。
公式与图表走受控 Web 岛（本地 KaTeX / mermaid，不联网），失败一律降级，不阻塞主线程。

## 外部入口

```swift
// 唯一推荐入口：解析在后台 actor，视图只做组装
MarkdownView(text: message.content)
MarkdownView(text: streamingText, isStreaming: true)

// 已经自己解析过（例如 Chat 侧有缓存）时：
let document = MarkdownParser.parse(text)      // nonisolated，可在 Task.detached 中调用
MarkdownDocumentView(document: document)
```

- `MarkdownView`、`MarkdownDocumentView`、`MarkdownParser` 均为同模块 internal/public 可见，Chat 可直接调用。
- 选中复制：容器与行内 `Text` 都启用了 `.textSelection(.enabled)`。

## 文件结构

```
Markdown/
  MarkdownView.swift              公共入口（后台解析 + 防抖）
  MarkdownMetrics.swift           CSS 度量的唯一来源（含块间距/外边距折叠）
  MarkdownPlatform.swift          平台图片类型与 Image 桥
  Parsing/
    MarkdownModel.swift           AST（块/行内/高亮 token）
    MarkdownBlockParser.swift     块级解析（标题/列表/引用/表格/围栏/公式/hr）
    MarkdownInlineParser.swift    行内解析（强调/链接/自动链接/行内码/公式/转义/实体）
    SyntaxHighlighter.swift       轻量词法器（9 种语言）
    MarkdownParser.swift          MarkdownParser + MarkdownParseService(actor)
  Rendering/
    MarkdownStyle.swift           字号/字重/行距/代码配色
    InlineRenderer.swift          行内 AST → AttributedString / Text
    MarkdownBlockViews.swift      原生块视图 + 表格 + 列表 + 引用
    CodeBlockView.swift           代码块 banner/复制/横向滚动
    MathBlockView.swift           块级公式 + TeX 源码降级
    MermaidBlockView.swift        图表/源码切换 + 失败降级
  Web/
    MarkdownWebAssets.swift       资源暂存到 Caches + HTML 模板
    OffscreenWebHost.swift        离屏 WKWebView、串行门、截图、JS 桥
    MathSnapshotRenderer.swift    行内公式快照（内存缓存）
    MermaidRenderer.swift         图表截图 + PNG 磁盘缓存
    MathWebView.swift             块级公式 Web 岛（高度回传）
  Resources/
    KaTeX/                        katex.min.js/css + 20 个 woff2
    Mermaid/mermaid.min.js        单文件 IIFE（globalThis.mermaid）
```

## 度量来源

逐条取自 `Reference/chat-demo/src/components/markdown/markdown.css`、
`CodeBlock.module.css`、`highlight.css`、`app/theme.css`：

| 项 | 值 | 来源 |
|---|---|---|
| 正文 | 14pt / 行距 5（≈22） | 任务书 + `DS.Typography.body`（CSS 原文 16/28，见下） |
| h1–h4 | 24 / 22 / 20 / 16，h1–h3 700、h4 600 | `--dsw-font-markdown-h*` |
| h1–h3 外边距 | 32 / 16 | `markdown.css` |
| h4–h6 / 段落 | 16 / 16 | `markdown.css` |
| 列表 | margin 16、padding-left 18、项间 6、嵌套列表 4 | `markdown.css` |
| 引用 | 左边框 2px、padding-left 14、margin 16 0 0 | `markdown.css` |
| 表格 | 单元格 10/16、表头 15/500、首尾列去内边距、min 100 / max 320 | `markdown.css` |
| 行内码 | 0.875em、圆角 6、padding 0 5 | `markdown.css` |
| 代码块 | 圆角 12、内容 13px/22、padding 16、banner 6 + 按钮 28/r8 | `CodeBlock.module.css` + `theme.css` |
| 分隔线 | margin 32、1px | `markdown.css` |
| 高亮 | light = One Light HSL、dark = bluish 配色 | `highlight.css` |

与任务书数字的差异（按「以 CSS 为准」处理，集中常量可一键改）：

- 正文：任务书 14px、CSS 16px。本项目 `DS.Typography.body` = 14，故取 14。
- 代码块圆角：任务书 8px，CSS `--dsl-code-block-border-radius` = 12px。取 12。
- 行内码：任务书 5px + `0 2px`，CSS 6px + `0 5px`。取 6/5。
- 标题：任务书「h1≈32」，CSS h1 = 24px/34。取 CSS。

## 公式岛

- KaTeX 资源在构建期进入 bundle；XcodeGen 会把资源**扁平**复制，所以首次运行时
  把 js/css/woff2 复制到 `Caches/DeepGlass/MarkdownWeb/<version>/`，同时把
  CSS 的 `url(fonts/…)` 改写成 `url(./…)`，再 `loadFileURL`（运行期零网络）。
- 块级：`MathWebView` 每块一个常驻 WKWebView；JS 渲染后把
  `document.body.scrollHeight` 通过 `dgMath` message handler 回传，SwiftUI 用
  `frame(height:)` 固定；`isOpaque=false`（macOS 用 `drawsBackground=false` +
  `underPageBackgroundColor=.clear`），透明跟随深浅色；Dynamic Type 字号变化会重渲染。
- 行内：离屏 WKWebView 渲染后 `WKSnapshotConfiguration` 截图，按
  「latex + 字号 + 主题」缓存在内存；用 `Text(Image).baselineOffset(-depth)`
  拼回文本流，baseline 取 JS 里 0 宽 baseline 标记的位置。
- 降级：KaTeX 缺失、JS 抛错、4 秒无高度、公式未闭合 → 显示带 TeX 语法着色的源码块，
  并注明原因。

## Mermaid 岛

- 闭合且非空的 ` ```mermaid ` 围栏才渲染；离屏 WKWebView 用
  `mermaid.render` 生成 SVG，等待字体后测量尺寸并截图。
- 缓存 key = `SHA256(版本 | 主题 | 宽度档 | 源码)`，PNG + 尺寸 sidecar 写入
  `Caches/DeepGlass/Mermaid/`，内存再套 NSCache。
- 失败或流式未闭合 → 原样显示代码块（失败时追加一行说明）。
- banner 提供「图表 / 源码」切换与复制。

## 已知限制（诚实清单）

1. **行内代码的圆角/padding 无法在 SwiftUI `Text` 的 AttributedString 里逐 run 实现**：
   背景色能上，但圆角与水平内边距不能。当前保留方形背景；`MarkdownMetrics`
   里的 `inlineCodeRadius` / `inlineCodeHorizontalPadding` 已留位。要完全还原需换
   TextKit 自绘 `NSLayoutManager.drawBackground`。
2. 行内公式以图片进文本流，**复制段落时公式会被跳过**（图片不是可选文本）；
   块级公式是独立 WebView，同样不参与文本复制。
3. 不支持：setext 标题、缩进式代码块、原始 HTML 渲染、引用式链接 `[a][b]`、
   脚注、定义列表。原始 HTML 会按纯文本显示。
4. 表格单元格按 GFM 只解析行内；不支持单元格内块级内容。
5. 嵌套「无序里的有序」列表仍按每层 18px 缩进（CSS 对 `ul ol` 用
   `list-style-position: inside`，视觉差异很小）。
6. 每个块级公式一个 WKWebView；同一消息里公式很多时内存占用高于理想值，
   后续可换共享池或图片快照。
7. Mermaid 磁盘缓存命中在主线程序列化解码 PNG，超大图可能有一次几毫秒的抖动。
8. 解析是整段重解析（40ms 防抖）；52KB 文档约 6.5ms，流式场景可接受。

## 构建

```bash
scripts/gen.sh
scripts/build.sh markdown mac
```
