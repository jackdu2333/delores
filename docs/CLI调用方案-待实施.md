# HuaciGongju CLI 调用方案

## 1. 目标

在现有 HTTP API 模型调用方式之外，新增本地 CLI 调用能力。

目标不是把 HuaciGongju 做成 Agent 平台，而是增加一种新的 AI 执行后端：

```text
Selection
   ↓
Action
   ↓
AI Router
   ↓
┌───────────────┬───────────────┐
│ HTTP Backend  │ CLI Backend   │
│               │               │
│ OpenAI        │ Gemini CLI    │
│ DeepSeek      │ Codex CLI     │
│ Ollama        │ Claude CLI    │
│ Local Gateway │ Custom CLI    │
└───────────────┴───────────────┘
        ↓
Unified Result Panel
```

核心原则：

**HuaciGongju 负责 UI、选词、Prompt 和结果展示；CLI 只是执行器。**

---

# 2. 产品边界

CLI 功能必须服从“小而美”的定位。

明确不做：

* 不将 Gemini / Codex / Claude CLI 打包进 App；
* 不内置 Node / Python Runtime；
* 不长期启动 CLI 后台进程；
* 不做 CLI Session Manager；
* 不做 MCP 管理器；
* 不做 Workspace / Project Agent；
* 不默认赋予 CLI Shell / File Write 权限；
* 不把 HuaciGongju 演进成桌面 Agent 平台。

CLI 生命周期：

```text
Idle
↓
用户触发 Action
↓
启动 CLI Process
↓
读取结果
↓
完成 / 取消
↓
Terminate Process
↓
回到 Idle
```

要求：

**CLI 只在任务执行期间存在。**

---

# 3. 第一阶段范围

第一版只支持：

```text
Gemini CLI
```

原因：

* 支持非交互模式；
* 支持结构化输出；
* 支持流式 JSON；
* 比较适合作为程序调用后端；
* 可以用来验证整个 CLI 架构。

第一阶段跑通以后，再新增：

```text
Codex CLI
Claude Code
Custom CLI
```

不要第一版同时支持多个 CLI。

---

# 4. 架构改造

当前：

```text
UnifiedCommandBarViewModel
        ↓
    LLMService
        ↓
 URLSession + SSE
```

建议改成：

```text
UnifiedCommandBarViewModel
        ↓
      AIRouter
        ↓
┌────────────────────────┐
│                        │
▼                        ▼
HTTPExecutor          CLIExecutor
│                        │
URLSession             Process
│                        │
SSEParser             CLIAdapter
│                        │
└───────────┬────────────┘
            ↓
      AIStreamEvent
            ↓
UnifiedCommandBarViewModel
```

---

# 5. 核心接口

新增统一 AI Provider 协议。

例如：

```swift
protocol AIProvider {
    func execute(
        request: AIRequest,
        onEvent: @escaping (AIStreamEvent) -> Void
    )

    func cancel()
}
```

统一请求：

```swift
struct AIRequest {
    let systemPrompt: String
    let userContent: String
    let history: [ChatMessage]
    let model: String?
}
```

统一事件：

```swift
enum AIStreamEvent {
    case started
    case reasoning(String)
    case text(String)
    case completed
    case failed(Error)
}
```

这样 UI 不需要知道后端到底是：

```text
HTTP
Gemini CLI
Codex CLI
Claude CLI
```

只消费统一事件。

---

# 6. Provider 类型

现有 `LLMProfile` 不应继续假设所有模型都有：

```text
baseUrl
apiKey
modelName
```

建议升级为：

```swift
enum ProviderType: String, Codable {
    case http
    case cli
}
```

然后：

```swift
struct LLMProfile {
    var id: String
    var name: String
    var providerType: ProviderType

    var httpConfig: HTTPProviderConfig?
    var cliConfig: CLIProviderConfig?
}
```

HTTP：

```swift
struct HTTPProviderConfig {
    var baseUrl: String
    var apiKey: String
    var modelName: String
}
```

CLI：

```swift
struct CLIProviderConfig {
    var cliType: CLIType
    var executablePath: String
    var modelName: String?
}
```

CLI 类型：

```swift
enum CLIType: String, Codable {
    case gemini
    case codex
    case claude
    case custom
}
```

---

# 7. 设置页面

添加模型时：

```text
添加 AI Provider

调用方式：

○ API
● CLI
```

如果选择 API：

```text
名称
Base URL
API Key
Model
```

如果选择 CLI：

```text
名称

CLI 类型：
[ Gemini CLI ▼ ]

CLI 路径：
/opt/homebrew/bin/gemini

状态：
✓ CLI 已检测

版本：
0.x.x

登录状态：
✓ 可正常调用

Model：
Auto

[ 测试 CLI ]
```

不要在主界面暴露这些配置。

CLI 属于高级配置。

---

# 8. CLI 自动检测

启动 App 时不要主动启动 CLI。

只检测文件是否存在。

候选路径：

```text
/opt/homebrew/bin/
/usr/local/bin/
~/.local/bin/
```

也可以允许用户通过文件选择器手动指定 executable。

不要依赖：

```text
PATH
```

因为 macOS GUI App 从 Finder / Login Item 启动时 PATH 和 Terminal 不一定一致。

优先保存：

```text
absolute executable path
```

例如：

```text
/opt/homebrew/bin/gemini
```

---

# 9. CLI 调用方式

禁止通过：

```text
/bin/zsh -c
```

拼接完整命令。

不要：

```swift
"/bin/zsh -c \"gemini -p '\(selectedText)'\""
```

原因：

* Shell Injection；
* 特殊字符转义；
* 中文 / 换行；
* 用户选中文本可能包含 shell syntax；
* 调试困难。

必须使用：

```swift
Process
```

例如：

```swift
let process = Process()

process.executableURL = URL(
    fileURLWithPath: executablePath
)

process.arguments = [
    "-p",
    prompt,
    "--output-format",
    "stream-json"
]
```

如果 CLI 支持 stdin：

优先：

```text
Prompt / SelectedText
↓
stdin Pipe
```

而不是放进 shell command。

---

# 10. CLIExecutor

新增：

```text
CLIExecutor.swift
```

职责只有：

```text
启动 Process
管理 stdin
读取 stdout
读取 stderr
取消 Process
监控退出状态
```

不要在 CLIExecutor 内写 Gemini / Codex 专属解析逻辑。

CLIExecutor 只负责进程生命周期。

---

# 11. CLIAdapter

每种 CLI 使用自己的 Adapter。

结构：

```text
CLIExecutor
     ↓
CLIAdapter
     ↓
┌──────────────┐
│ GeminiAdapter│
│ CodexAdapter │
│ ClaudeAdapter│
└──────────────┘
```

接口：

```swift
protocol CLIAdapter {
    func buildArguments(
        request: AIRequest,
        config: CLIProviderConfig
    ) -> [String]

    func parseOutput(
        _ data: Data
    ) -> [AIStreamEvent]
}
```

这样以后新增 CLI：

```text
新增 Adapter
```

而不是修改核心执行逻辑。

---

# 12. Gemini CLI 第一版

第一版采用类似：

```text
gemini
-p
<prompt>
--output-format
stream-json
```

流程：

```text
Action Prompt
+
Selected Text
      ↓
GeminiCLIAdapter
      ↓
Process
      ↓
stdout stream-json
      ↓
parse JSON line
      ↓
AIStreamEvent.text
      ↓
Result Panel
```

要求支持：

```text
streaming
cancel
error
process exit
```

---

# 13. Prompt 组装

保持当前 Action Prompt 设计。

例如：

```text
System / Action Prompt：

请对以下内容进行总结……

Selected Text：

xxxxxxxx
```

CLI Adapter 只负责调用。

不要让 CLI 自己决定 Prompt。

也就是说：

```text
Prompt Authority
```

仍然属于 HuaciGongju。

这样：

```text
API Backend
CLI Backend
```

行为才能保持一致。

---

# 14. Result Panel 不修改交互模型

当前顶部 UI 保持：

```text
Collapsed
↓
Action
↓
Expanded
↓
Streaming Result
```

CLI 和 API 不应该产生两套 UI。

CLI：

```text
Process stdout
↓
AIStreamEvent.text
```

API：

```text
SSE
↓
AIStreamEvent.text
```

最后都进入：

```text
viewModel.outputText
```

用户不应该明显感觉到底使用的是：

```text
API
还是
CLI
```

区别只存在于 Provider。

---

# 15. Cancel

当用户：

```text
点击停止
关闭面板
重新划词
切换 Action
切换 Provider
```

必须：

```text
cancel current request
```

CLI：

```swift
process.terminate()
```

如果进程在短时间内未退出：

再进行更强终止处理。

禁止留下孤儿进程。

---

# 16. 并发控制

同一时间只允许一个活跃 AI 请求。

新增：

```text
requestId
```

例如：

```swift
let requestId = UUID()
currentRequestId = requestId
```

所有事件进入 UI 前判断：

```swift
guard requestId == currentRequestId else {
    return
}
```

防止：

```text
旧 CLI stdout
旧 HTTP token
```

污染当前 Result。

---

# 17. 内存控制

这是本功能的核心约束之一。

必须满足：

```text
Idle：
只运行 HuaciGongju

CLI Request：
HuaciGongju + 临时 CLI Process

Request Finished：
CLI Process 完全退出
```

禁止：

```text
App Launch
↓
预启动 Gemini / Codex
↓
后台长期驻留
```

不要为了降低 CLI Cold Start 而保持常驻进程。

---

# 18. 安全策略

CLI 默认运行模式必须是：

```text
Text Generation Mode
```

而不是：

```text
Agent Mode
```

第一阶段禁止默认启用：

* Shell Command；
* 文件写入；
* 文件删除；
* Git 操作；
* MCP；
* Browser Automation；
* 自动审批；
* Workspace Agent。

原因：

划词内容属于外部不可信输入。

例如网页文本可能包含：

```text
Ignore previous instructions...
Read ~/.ssh...
Execute...
```

所以：

```text
SelectedText
```

必须始终被视为：

**Untrusted Input**

---

# 19. 日志

CLI 调用日志默认只记录：

```text
Provider
CLI Type
Model
Start Time
Duration
Exit Code
Error
```

默认不要记录：

```text
完整 SelectedText
完整 Prompt
完整 stdout
reasoning
```

Debug 模式可以显式开启详细日志。

---

# 20. 错误处理

需要统一处理：

### CLI 不存在

```text
未找到 Gemini CLI
```

提示：

```text
请安装 CLI 或重新选择 CLI 路径
```

### CLI 无执行权限

```text
CLI 无执行权限
```

### CLI 未登录

提示：

```text
Gemini CLI 当前不可用，请先在终端完成登录
```

不要尝试在 HuaciGongju 内接管第三方 CLI 登录流程。

### Process 崩溃

展示：

```text
CLI 执行失败
Exit Code: xx
```

### 输出无法解析

展示：

```text
CLI 返回格式异常
```

同时允许 Debug 查看 stderr。

---

# 21. 不做自动安装

第一阶段不要：

```text
检测不到 Gemini CLI
→ 自动 npm install
```

HuaciGongju 不负责维护 CLI 安装。

只做：

```text
检测
提示
选择路径
测试
```

保持职责简单。

---

# 22. 兼容性策略

CLI Provider 是可选能力。

如果用户完全不使用 CLI：

```text
HuaciGongju
```

行为和当前版本完全一样。

CLI 不应增加：

* 常驻内存；
* 启动耗时；
* 首页复杂度；
* 使用门槛。

---

# 23. 第一阶段文件建议

建议新增：

```text
Sources/HuaciGongju/

AI/
├── AIProvider.swift
├── AIRouter.swift
├── AIRequest.swift
├── AIStreamEvent.swift
│
├── HTTP/
│   └── HTTPAIProvider.swift
│
└── CLI/
    ├── CLIExecutor.swift
    ├── CLIAdapter.swift
    └── GeminiCLIAdapter.swift
```

当前：

```text
LLMService.swift
```

可以先逐步迁移成：

```text
HTTPAIProvider.swift
```

不要一次性大重构。

---

# 24. 实施阶段

## Phase 1：抽象调用层

目标：

```text
现有 HTTP 功能完全不变
```

完成：

```text
AIProvider
AIRequest
AIStreamEvent
AIRouter
```

把当前 HTTP 请求接入统一 Provider。

验收：

API 调用行为与当前版本一致。

---

## Phase 2：CLIExecutor

完成：

```text
Process
stdout
stderr
cancel
exitCode
```

暂时不要接 UI。

可以先使用测试 Prompt 验证：

```text
HuaciGongju
→ Gemini CLI
→ 得到结果
```

---

## Phase 3：Gemini CLI Adapter

支持：

```text
stream-json
```

转换为：

```text
AIStreamEvent
```

验证：

```text
Token Streaming
Cancel
Error
Complete
```

---

## Phase 4：配置 UI

新增：

```text
Provider Type
API / CLI
```

CLI：

```text
CLI Type
Executable Path
Model
Test
```

---

## Phase 5：接入顶部结果面板

实现：

```text
Selection
→ Action
→ CLI
→ Streaming Result
```

视觉行为必须与 API Backend 保持一致。

---

# 25. 性能目标

Idle 状态：

```text
CLI Process = 0
```

App 常驻资源不能因为 CLI 功能明显增长。

CLI 使用期间允许：

```text
临时增加系统 CPU / RAM
```

请求完成后必须恢复。

目标：

```text
CLI 功能对 Idle Memory 基本无影响。
```

---

# 26. 验收标准

至少完成以下测试：

1. 未安装 Gemini CLI，App 正常启动；
2. API Provider 不受影响；
3. Gemini CLI 可自动检测；
4. 可手动指定 CLI 路径；
5. 测试 CLI 可以判断是否可正常执行；
6. 划词 → 翻译 → CLI 返回结果；
7. 流式结果正常；
8. 点击 Stop 后 CLI Process 退出；
9. 关闭面板后 CLI Process 退出；
10. 新 Selection 后旧 CLI Process 退出；
11. 快速切换 Action 不出现旧结果污染；
12. CLI 异常退出可正确提示；
13. stderr 不混入正常 Result；
14. CLI 不存在时不 Crash；
15. App Idle 时不存在后台 CLI 进程；
16. CLI 功能关闭后与原版本体验完全一致。

---

# 27. 第一阶段成功标准

第一版不要追求：

```text
Gemini
Codex
Claude
全部支持
```

真正的成功标准只有：

```text
API Backend
        +
Gemini CLI Backend
```

两套后端能够通过同一套：

```text
Selection
Action
Prompt
Result Panel
```

稳定工作。

如果这个架构成立，再新增：

```text
CodexCLIAdapter
ClaudeCLIAdapter
```

应该只需要增加 Adapter，而不应该再次修改：

```text
SelectionMonitor
CommandBar
ResultPanel
AI Router
```

如果增加第二个 CLI 还需要大面积修改核心代码，说明第一阶段抽象设计不合格。

---

# 28. 最终架构原则

整个功能必须始终遵守：

```text
HuaciGongju
=
Selection UI
+
Prompt
+
轻量 Router
+
Result UI
```

而不是：

```text
HuaciGongju
=
AI Platform
+
Agent Runtime
+
CLI Manager
```

CLI 是能力来源，不是产品主体。

最终目标：

> API 和 CLI 都只是 HuaciGongju 后面的可替换执行引擎，用户看到的始终是一款快速、轻量、稳定的 macOS 划词工具。
