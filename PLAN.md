# DeepGlass — SwiftUI × Liquid Glass 复刻 DeepSeek Chat（macOS / iOS / iPadOS）

> 状态：**方案定稿，可开工 M0** · 版本 v0.3 · 2026-11-20
> 参考实现：[deepseek-ai/chat-demo](https://github.com/deepseek-ai/chat-demo)（MIT，官方静态聊天示例）
> 已定：**玻璃仅外壳层（A1）** · **原生渲染 + 公式/图表 Web 岛（B1）** · **真实 API 直连** · **最低版本 iOS/iPadOS/macOS 26.0**

---

## 0. 结论先行

技术上完全可行，参考实现是 MIT、协议公开、工具链已就绪。整体定位：

> **布局、排版、色彩、交互 1:1 对齐 Web 版；质感上按 Liquid Glass 重构外壳层。**

$$\boxed{\text{内容层 1:1 还原，外壳层原生玻璃重构}}$$

这条边界是一切取舍的裁判：凡属"内容"（消息、代码、表格、来源卡）→ 严格对齐；凡属"外壳"（侧栏、输入框、工具栏、弹窗）→ 允许玻璃化差异，但要写进 `docs/DEVIATIONS.md`。

| 范围 | 内容 | 工时（单人 + AI 结对） |
|---|---|---|
| **P0 可用版** | 会话管理、流式对话、Markdown、思考/搜索时间线、玻璃外壳 | **5–6 周** |
| **P1 功能对齐** | 附件、引用面板、设置、i18n、主题、导入导出 | +3–4 周 |
| **P2 完整复刻** | 语音输入/朗读、分支、保真打磨、发布 | +3–4 周 |
| 合计 | | **10–14 周** |

---

## 1. 已核实的事实

### 1.1 参考实现的真实体量

仓库已拉到本地逐层读完：

- **44 个 React 组件**，**4,639 行 CSS**，**19,210 行 TS/TSX/CSS**
- 功能域：`chatInput` / `messages` / `markdown` / `search` / `sider` / `session` / `settings` / `files` / `base`(设计系统) / `i18n` / `services`
- 语言包仅中英，各 ~180 行 → i18n 成本可控

### 1.2 协议：公开的 Anthropic 兼容 Messages API

不需要逆向私有接口、不需要登录 Cookie：

```
POST https://api.deepseek.com/anthropic/v1/messages   (stream: true)
鉴权：x-api-key: <KEY>   或   Authorization: Bearer <KEY>
```

请求体：

```swift
model: "deepseek-flash" | "deepseek-v4-pro"
system: String
messages: [.init(role: .user/.assistant/.latestReminder, content: ...)]
thinking: { type: "enabled" | "disabled" }
tools: [deepseek_web_search, deepseek_read_url]
safety_check: { level: "high" }          // 扩展模式（联网/读链接）
title: { enabled: true }                  // 自动生成会话标题
```

流式事件全集（SSE，`event` 名与 JSON `type` 相同，以 `message_stop` 结束，**不发 `[DONE]`**）：

| 事件 | 关键载荷 |
|---|---|
| `message_start` | message id / model / usage |
| `content_block_start` | index + 初始块（text / thinking / server_tool_use / 搜索结果 / 抓取结果） |
| `content_block_delta` | `text_delta`、`thinking_delta`、`signature_delta`、`citations_delta`、`input_json_delta` |
| `content_block_stop` | index |
| `message_delta` | stop_reason / usage / 自动标题 |
| `message_stop` | 结束 |
| `ping` | 保活（忽略） |

Files API：`POST /anthropic/v1/files`（需 `anthropic-beta: files-api-2025-04-14`），图片用 `image` 块、文档用 `document` 块回传 `file_id`。

### 1.3 工具链验证结果

| 项 | 结果 |
|---|---|
| Xcode / Swift / SDK | 27.2 (27B52) / 6.4.2 / macOS 27.2 · iOS 27.2 |
| `glassEffect` · `GlassEffectContainer` · `glassEffectID` · `glassEffectUnion` · `glassEffectTransition` · `.buttonStyle(.glass)` | **最小 SPM 包实机编译通过**（tools 6.2，目标 macOS 26） |

→ 直接用原生 Liquid Glass，**不引入社区 fallback 库**；部署目标 **26.0**（已确认），不做 17/18 兼容层。

### 1.4 部署目标（已定）

| 平台 | 最低版本 | 理由 |
|---|---|---|
| iOS | 26.0 | Liquid Glass 原生 API 起点，无需材质模拟 |
| iPadOS | 26.0 | 同上，`NavigationSplitView` 玻璃行为一致 |
| macOS | 26.0 | 同上，`glassEffect` 与窗口玻璃统一 |

单一多平台 target，`MACOSX_DEPLOYMENT_TARGET = 26.0`、`IPHONEOS_DEPLOYMENT_TARGET = 26.0`，无 `#available` 降级分支 —— 视觉代码只写一套，这是本项目能控住工期的关键前提。

### 1.5 设计令牌可直接移植

```css
--dsw-alias-brand-primary: rgb(57,100,254)   /* 亮 */  ↔ rgb(86,134,254) /* 暗 */
--dsw-alias-bg-base:       #FFFFFF                      ↔ rgb(21,21,23)
--dsw-alias-label-primary: rgb(15,17,21)                ↔ rgb(249,250,251)
--dsw-alias-label-secondary: rgb(97,102,107)             ↔ rgb(207,211,214)
--ds-control-height-xl: 44 · l: 40 · m: 36 · s: 32 · xs: 28
--ds-font-size-m: 14px        /* 正文基准 */
--ds-transition-duration: .2s / slow .3s，easing cubic-bezier(.4,0,.2,1)
--message-list-max-width: 840px（窄屏 712）· padding-h 44px（窄屏 36）
--sider width: 261px
```

---

## 2. 已定抉择（含"因此不做什么"）

### 2.1 【已定 A1】玻璃只加在外壳层

**判据**：可交互的容器可以是玻璃；承载阅读内容的表面必须是实色。

| 表面 | 处理 | 说明 |
|---|---|---|
| 侧栏背景 | `glassEffect(.regular)`，深色下加 tint | 与主内容之间保留 1px 分隔 |
| 顶栏 / 工具栏 | 原生 toolbar + glass 按钮 | macOS 用 `.hiddenTitleBar` 自绘 |
| 输入框容器 | 玻璃圆角矩形（r=26） | 内部文字仍为实色背景上的 `label-primary` |
| 发送/停止按钮 | `.buttonStyle(.glassProminent)` + accent tint | 唯一"高亮"玻璃 |
| 深度思考 / 智能搜索开关 | 玻璃胶囊，选中态 accent tint | `GlassEffectContainer` 内合组 |
| 浮动按钮（回到底部、附件预览） | 玻璃圆形 | `.interactive()` |
| 设置弹窗 / 会话抽屉 | 玻璃 sheet | 移除自定义 `presentationBackground` |
| **消息正文 / 代码块 / 表格 / 来源卡** | **实色，无玻璃** | 阅读区不透明化，保对比度与性能 |
| 消息气泡 | 保持原版的扁平底色 | 不做玻璃气泡 |

**因此不做**：不做全局玻璃、不做双皮肤切换、不做玻璃消息气泡。

**落地规范**（写进 DesignSystem 的 lint 清单）：
1. 玻璃元素必须汇聚在**同一个** `GlassEffectContainer` 内（玻璃无法采样玻璃）。
2. `container.spacing` == 内部布局 `spacing`，否则合并动画会跳。
3. `.interactive()` 只给真正可点的元素。
4. 减弱透明度 → `.ultraThinMaterial` 降级；减弱动效 → 禁用 morph。
5. 玻璃上不放正文；控件文字用 `label-primary` 并留足内边距。
6. 暗色模式下 tint 单独调校，跑对比度检查（正文 ≥ 4.5:1）。

### 2.2 【已定 B1】原生渲染为主，公式与图表走 Web 岛

按节点类型分流，边界清晰：

| Markdown 节点 | 渲染方式 | 备注 |
|---|---|---|
| 段落 / 标题 / 粗斜体 / 删除线 / 行内代码 / 链接 | 原生（`AttributedString`） | 可选中、可复制 |
| 无序 / 有序 / 任务列表 | 原生 | 缩进与 Web 版对齐 |
| 引用块 / 分割线 | 原生 | |
| 表格 | 原生 | 列宽按内容测量，支持横向滚动 |
| 代码块 | 原生 + 语法高亮 + 复制 + 折叠 | 高亮结果按内容哈希缓存 |
| 图片 | 原生 `AsyncImage` + 磁盘缓存 | |
| **行内公式 / 块公式** | **WKWebView 岛（本地 KaTeX）** | 按公式哈希缓存；宽度自适应 |
| **Mermaid 图** | **WKWebView 岛 → 截图为图片** | 渲染一次后缓存 PNG；流式未闭合时降级为代码块 |

**因此不做**：不整条消息套 WKWebView（高度测量 + 滚动嵌套 + 内存会失控）；不自己重画 Mermaid。

**性能红线——流式渲染策略**：
- 已完成的块 → 缓存为不可变视图；
- **只有正在流式的那一个块**以"纯文本 + 轻量内联样式"呈现；
- 收到 `content_block_stop` 才切成完整 Markdown 渲染。
- 效果：每帧成本 O(1)，与消息总长无关。

### 2.3 【已定】真实 API 直连

首版即接 `api.deepseek.com`，Key 存 Keychain，进设置时用 `GET /models` 校验（不产生费用）。
端点做成可配置项（`API_ORIGIN`），因此将来接 Ollama / 自建网关只是改一个常量，不需要额外开发。

### 2.4 平台形态

| 平台 | 导航 | 关键点 |
|---|---|---|
| iPhone | `NavigationStack` + 会话抽屉（`.sheet`） | 输入框 `safeAreaInset(edge: .bottom)`；录音时频谱替换输入区 |
| iPadOS | `NavigationSplitView`（可折叠侧栏） | 分屏 / 台前调度；拖拽附件 |
| macOS | `NavigationSplitView` + `.hiddenTitleBar` | 261pt 侧栏、菜单栏命令、⌘N / ⌘, / ⌘F、窗口最小尺寸 720×520 |

一个 Xcode 多平台 target + 一个本地 SPM 包（便于 `swift test`）。三端共用同一套 DesignSystem 与玻璃原语，平台差异只体现在导航容器与命令层。

---

## 3. 范围与优先级

### P0 — 没有它就不算"能用的复刻"

- 会话列表：新建、重命名、删除、置顶、自动标题、搜索
- 流式对话：发送、停止、继续生成、重新生成
- 内容块渲染：正文、思考过程（可折叠 + 用时）、工具步骤时间线
- Markdown：标题 / 列表 / 表格 / 引用 / 链接 / 行内代码 / 代码块（高亮 + 复制 + 折叠）+ 公式岛
- 玻璃外壳：侧栏、输入框、工具栏、设置弹窗
- 输入框：自适应高度、深度思考开关、智能搜索开关、模型选择、发送 / 停止
- 错误处理：HTTP / 流内错误 / 断流 / 网络，四类文案与重试行为各异
- 本地持久化 + 每会话草稿

### P1 — 功能对齐

- 附件：选择 / 拖拽 / 粘贴、上传进度、失败重试、图片预览、Files API
- 联网搜索与引用：来源卡片、站点图标、`[1]` 引用跳转、搜索面板、HoverCard
- 设置：API Key（Keychain + 校验）、主题、语言、朗读音色、位置
- i18n：zh-Hans / en（String Catalog）
- 主题：亮 / 暗 / 跟随系统
- 历史导入导出：**兼容官方导出包**（zip + JSON schema），双向迁移

### P2 — 完整度

- 语音输入（Speech framework）、朗读（AVSpeechSynthesizer）、移动端频谱
- 消息分支：编辑用户消息、切换版本（BranchSwitcher）
- macOS 菜单栏与全量快捷键
- 无障碍：VoiceOver、动态字体、减弱透明度 / 动效
- 性能预算与发布（签名、公证）

---

## 4. 架构

```
DeepGlass.xcodeproj
├── DeepSeekKit/                    ← 本地 SPM，纯逻辑，可 swift test
│   ├── Protocol/                   请求体、内容块、事件 Codable + 容错解码
│   ├── Transport/                  SSE 解析（WHATWG 语义）、URLSession.bytes、错误分类
│   ├── Reducer/                    事件 → 消息状态机（流式增量合并）
│   ├── Persistence/                SwiftData 模型 + 迁移
│   └── History/                    官方导出包 zip/JSON 读写
├── DesignSystem/                   颜色/字号/间距/圆角 + Glass 修饰符 + lint 检查
├── Features/
│   ├── Sider/  Session/  Chat/  Composer/  Markdown/  Search/  Settings/
└── App/                            平台入口、Scene、菜单命令、快捷键
```

### 4.1 核心传输层

```swift
public enum StreamEvent: Decodable, Sendable {
    case messageStart(id: String, model: String, usage: Usage?)
    case blockStart(index: Int, block: BlockStart)
    case blockDelta(index: Int, delta: BlockDelta)   // text / thinking / signature / citations / json
    case blockStop(index: Int)
    case messageDelta(stopReason: String?, title: String?, usage: Usage?)
    case messageStop
    case ping
}

public func stream(_ request: CreateMessageRequest,
                   key: String) -> AsyncThrowingStream<StreamEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var req = URLRequest(url: Self.messagesURL)
            req.httpMethod = "POST"
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.httpBody = try JSONEncoder().encode(request.with(stream: true))

            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            try Self.validate(response)                       // 非 2xx → ApiError.http
            for try await event in SSEParser(bytes.lines) {    // 含 CRLF/CR、注释 ping
                if let e = try StreamEvent.decode(event) { continuation.yield(e) }
                if case .messageStop = event { break }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }    // 停止生成
    }
}
```

要点：
- 不用 `DataTask` + delegate 拼字符串；`bytes(for:)` 的 `AsyncLineSequence` 已按行切分，再叠加 SSE 空行派发。
- SSE 必须移植 `sse.ts` 的边界行为（`\r` 结尾等下一段、多行 `data` 以 `\n` 连接、`:` 开头是注释）。
- 错误五类对齐 `errors.ts`：`http` / `stream` / `network` / `interrupted` / `protocol`，UI 文案与重试策略各不相同。

### 4.2 数据模型

```swift
@Model final class Session {
    var id: UUID; var title: String; var createdAt: Date; var updatedAt: Date
    var pinned: Bool; var model: String; var thinking: Bool; var search: Bool
    @Relationship(deleteRule: .cascade) var messages: [Message]
}

@Model final class Message {
    var id: UUID; var role: Role; var createdAt: Date
    var parentID: UUID?        // 分支树
    var versionGroup: UUID?    // 同一位置的多个版本
    var blocksData: Data       // [Block] 编码，便于协议演进
    var status: Status         // streaming / complete / stopped / failed
}
```

- `blocksData` 用 JSON 存而非展开成表：内容块是协议对齐的异构体，展开会带来大量迁移成本。
- 草稿与会话解耦：每会话一份草稿（文本 + 附件），持久化，切换不丢。
- API Key 存 Keychain，不用 UserDefaults。
- 流式态只在内存（`@Observable` 的 `StreamingSession`），每 ~500ms 落盘一次快照，崩溃可恢复部分内容。

### 4.3 Markdown 渲染管线

```
文本块 ──► swift-markdown 解析 AST ──► 节点分派
                                        ├─ 原生节点 → SwiftUI 视图（带缓存）
                                        └─ 公式/图表 → Web 岛（按源哈希缓存）
```

- 解析放后台 actor，主线程只做视图组装。
- 公式岛：本地 KaTeX 资源 `loadHTMLString`，JS 回传 `document.body.scrollHeight` 驱动高度；随动态字体缩放重算。
- 图表岛：Mermaid 渲染完成后 `WKSnapshotConfiguration` 截图，PNG 写缓存目录，原图变脏时重算。
- 流式期间未闭合的公式/图表 → 显示源码占位，闭合后升级为岛。

---

## 5. 里程碑

| 里程碑 | 交付物 | 验收标准 | 估时 |
|---|---|---|---|
| **M0 地基** | 多平台工程 + `DeepSeekKit` + DesignSystem + 玻璃原语 + **玻璃外壳样机** | 三端空壳可跑；`swift test` 绿；样机三端截图待你确认观感 | 3–4 天 |
| **M1 外壳与会话** | 侧栏、欢迎页、玻璃输入框、SwiftData 会话 CRUD | 三端布局与 Web 版截图重合（除玻璃层）；重启不丢 | 5–6 天 |
| **M2 流式核心** | SSE + reducer + 发送 / 停止 / 继续 / 重生成 + 自动标题 | 真实 Key 连续 10 轮无错；断网与中途停止状态正确 | 7–10 天 |
| **M3 Markdown 保真** | 原生渲染器 + 代码高亮 + KaTeX 岛 + Mermaid 岛 | 20 条"刁钻样本"视觉对比达标 | 8–12 天 |
| **M4 思考与搜索** | 思考折叠时间线、工具步骤、引用与来源卡、搜索面板 | 联网搜索全链路可用；引用可跳转 | 5–7 天 |
| **M5 附件** | 选择 / 拖拽 / 粘贴、上传、Files API 回传、预览 | 图片与 PDF 多轮对话正确；失败可重试 | 4–5 天 |
| **M6 设置与 i18n** | 设置弹窗、Keychain、主题、双语、导入导出 | 官方导出包可导入且内容完整 | 4–5 天 |
| **M7 语音** | 语音输入、朗读、频谱 | 中英识别可用；朗读可中断 | 3–4 天 |
| **M8 打磨发布** | 保真 diff、性能、无障碍、菜单、签名 | 见 §6；冷启动 < 1s，长会话 60fps | 7–10 天 |

M0–M4 是"能不能用"的分水岭（约 5–6 周）。

**M0 的样机是第一个决策点**：只做侧栏 + 输入框 + 一条假消息，三端各截一张图。玻璃观感最主观，先看图再投入，比写完再返工便宜。

---

## 6. 保真度怎么量化

把参考 Web 实现跑在固定视口（iPhone 390×844 / iPad 1024×1366 / Mac 1440×900），与原生实现同状态截图做叠加 diff。

| 层级 | 指标 | 目标 |
|---|---|---|
| L1 布局 | 元素矩形位置偏差 | ≤ 2px |
| L2 排版 | 字号 / 行高 / 字距 / 文本断行点 | 断行位置一致（中文按字、英文按词） |
| L3 色彩 | 语义色值 | 完全一致（直接取 token） |
| L4 外壳 | 玻璃层 | **允许差异**，按 §2.1 规范 |
| L5 动效 | 时长 / 曲线 | 对齐 `.2s` + `cubic-bezier(.4,0,.2,1)` |

差异清单本身是交付物：`docs/DEVIATIONS.md` 逐条记录"刻意的原生适配"（玻璃、语音、Keychain、菜单栏）。

---

## 7. 风险清单

| 风险 | 影响 | 缓解 |
|---|---|---|
| Markdown 全等（表格、嵌套列表、公式混排） | 高 | M3 建 20 条黄金样本；先做渲染器再接入聊天；接受"接近" |
| 流式性能 | 高 | 已定策略：完成块缓存 + 流式块纯文本；Instruments 卡 16ms |
| 长会话内存 | 中 | `LazyVStack` + 视口外释放高亮 + 图表 PNG 缓存 |
| 玻璃对比度（尤其暗色） | 中 | 只在 chrome；暗色单独调 tint；无障碍对比度检查 |
| macOS 窗口与 Web 视觉差异 | 中 | `.hiddenTitleBar` + 自绘顶栏；最小尺寸对齐 |
| 官方导出包格式变更 | 低 | 版本字段 + 宽容解码 + 导入失败不破坏现有数据 |
| App Store 审核（API Key、AI 内容） | 低 | 优先 Developer ID 直接分发；上架另评估 |

---

## 8. 目录

```
DeepmacOS/
├── PLAN.md                 ← 本文档
├── docs/
│   ├── DEVIATIONS.md       与原版的差异审计
│   └── FIDELITY.md         黄金样本与 diff 流程
├── DeepGlass.xcodeproj
├── DeepSeekKit/            SPM 包
└── Reference/chat-demo/    参考实现（只读拷贝）
```

---

## 9. 决策记录（ADR）

| # | 决策 | 结论 | 状态 |
|---|---|---|---|
| 1 | 玻璃覆盖范围 | **A1 仅外壳层**；正文/代码/表格保持实色 | ✅ 已定 |
| 2 | Markdown 渲染 | **B1 原生为主 + 公式/图表 Web 岛** | ✅ 已定 |
| 3 | 数据来源 | **真实 API 直连**，端点常量可配置 | ✅ 已定 |
| 4 | 最低版本 | iOS / iPadOS / macOS **26.0**（原生玻璃必需） | ✅ 已定（2026-11-20 确认） |
| 5 | 分发方式 | 先 Developer ID 直接分发，App Store 后议 | ⏳ 待确认（不阻塞开发） |

**当前无阻塞项**：五项决策已定其四，可直接进入 M0。分发方式在第 5 项确认前按 Developer ID 直接分发推进。

下一步执行顺序：
1. 建工程骨架（多平台 target + `DeepSeekKit` SPM + DesignSystem）
2. 做玻璃外壳样机（侧栏 + 输入框 + 一条假消息），三端各截一张图
3. 观感确认后进 M1（会话与外壳），再进 M2（流式核心）
