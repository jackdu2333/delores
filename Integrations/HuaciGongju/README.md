# 划词小工具 (HuaciGongju) for macOS

从 Cherry Studio 核心灵感剥离、专为 macOS 打造的**纯原生极轻量 Floating Quick Action Bar**。

## 🌟 视觉与交互特性

- **macOS 26+ 原生 Liquid Glass 材质**：
  - 基于 macOS 原生 `NSGlassEffectView`（Liquid Glass Surface），配合 Specular Highlight Rim 边缘微折射光与 Organic Elevation 柔和阴影，呈现原生悬浮通透质感。
- **高圆角胶囊与无缝展开形态**：
  - 收起态为高 38pt 的轻巧胶囊（`Capsule`）；展开态平滑向下延展，几何上顶边锚点保持绝对恒定，视觉稳定不跳动。
- **物理反馈动效 (Apple Spring Physics)**：
  - **Hover**：150ms 局部柔光 + `1.03x` 微浮动；
  - **Press 压缩反馈**：Apple 经典物理压缩阻尼反馈（`1.0 -> 0.97 -> 1.0`），应用于所有动作按钮、控制按钮与追问操作；
  - **Show / Hide**：从屏幕顶部环境轻微凝结浮现（`scale 0.96 -> 1.0`, `y: -4pt -> 0`, `180ms`），消失灵敏迅速（`140ms`）。
- **固定顶部定位策略 (Selection 触发，Screen 定位)**：
  - **MacBook 刘海屏**：AppKit 原生 `safeAreaInsets` / `auxiliaryTopRightArea` 自动判定，固定在刘海右侧状态栏区域，视觉居中且绝不遮挡刘海；
  - **普通屏 / 外接显示器**：固定在屏幕顶部水平绝对居中；
  - **多屏自适应**：优先识别当前正在划选操作的显示器，连续选词再不跳动。

## 🧠 核心逻辑与状态机

- **多轮追问与上下文链条 (Follow-up Chat History)**：
  - 维护 `currentPrompt` 状态机，准确记录多轮对话中的上一轮用户问题与助手答复，彻底杜绝重复将划词原文塞入上下文的缺陷；
  - 在重试当前问题（Retry）或卡片内切换大模型时，精准复用 `currentPrompt` 重新生成。
- **Pin 保护与划选取消重置**：
  - 展开卡片被钉住（Pinned）时，外部新的划词不会突兀收起当前窗口，保护正在查阅的内容；
  - 未钉住状态下，新的划词将立即取消后台进行中的请求、清空脏状态（输出、思考过程、上下文与当前动作）并平滑回退至胶囊栏。
- **流式并发安全与内存管理**：
  - 通过 `currentRequestId: UUID` 严格保护所有流式回调（`onToken` / `onReasoning` / `onComplete` / `onError`），防止快速换模型或连续操作产生幽灵数据交织；
  - 显式管理 `URLSession` 生命周期，在取消与任务结束时执行 `invalidateAndCancel()`，彻底打破委托强引用循环导致的内存泄漏。
- **通道纯净与思考兜底语义重构**：
  - `reasoning_content`（思考通道）与 `content`（答案通道）绝对分离，彻底废除把思考过程作为兜底正文污染答案和上下文的旧机制；
  - 若模型仅有思考而无最终回答，保留思考过程供展开回看，下方提供清晰提示「模型未返回最终答复」与重试按钮，绝不污染答案与对话历史。

## 🔒 隐私与安全性

- **告别全局 `/tmp` 明文日志**：
  - 敏感调试日志安全迁移至用户个人保护目录 `~/Library/Logs/HuaciGongju/`，目录严格限定 POSIX `0o700`、文件限定 `0o600` 权限；
  - **明文日志默认关闭**：默认只记录统计信息与长度掩码，严禁明文记录用户选中文本与大模型完整对话；用户可在偏好设置中按需开启调试日志。

## 📋 待实施功能清单 (Roadmap)

- [ ] **本地 CLI 调用后端能力**（详见 [docs/CLI调用方案-待实施.md](docs/CLI调用方案-待实施.md)）
  - **状态**：待执行 (Backlog)，当下不开发。
  - **目标**：在现有 HTTP API 之外，扩展支持通过标准输入输出调用本地 CLI（如 Gemini CLI、Codex CLI、Claude CLI 或自定义命令），由 HuaciGongju 统一调度并呈现结果。

## 🛠 编译与构建

```bash
# 原生一键编译与本机构建签名
./build.sh
```

### 本地固定代码签名（辅助功能授权不再反复失效）

`build.sh` 会优先使用名为 `HuaciGongju CodeSign` 的**本地自签名证书**对 `.app` 签名；
若该证书不存在，才退回 ad-hoc 临时签名。

- **为什么必须这样**：ad-hoc 签名下 macOS 只能靠二进制哈希（`cdhash`）识别应用。
  每改一行代码重新编译，哈希就变一次，系统即视为"陌生应用"，
  「辅助功能」授权随之失效，只能重新授权——这是 ad-hoc 签名的先天限制，不是 bug。
- **签名后的效果**：指定要求（Designated Requirement）变为

  ```
  identifier "com.jackdu.huacigongju" and certificate root = H"<证书根指纹>"
  ```

  只绑定 **bundle ID + 证书**，与二进制内容无关。
  **改代码、重新编译、重新签名，授权始终保持有效。**
- **证书规格**：自签名根证书（`CA:true` + `codeSigning` 扩展），CN = `HuaciGongju CodeSign`，
  有效期 10 年，已装入 `login` 钥匙串并设为「代码签名」用途的受信任根。
- **备份位置**：`~/.config/huaci-codesign/`
  （刻意放在仓库之外，避免被 Obsidian Git 之类的自动备份脚本提交入库；
  该目录内含恢复步骤与重新生成方法说明）。
- **前提**：`.app` 的 `CFBundleIdentifier` 需保持稳定，修改它会生成新的授权条目。

> ⚠️ 授权认的是 `.app` 包。仓库根目录的裸二进制 `HuaciGongjuBin` 不携带 bundle 标识，
> 直接运行它属于另一条独立记录，不会复用 `.app` 的授权。
