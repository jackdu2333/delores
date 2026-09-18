# Delores backlog — designed but not yet built

> 快照时间：2026-09-18 00:02，基线 `39f5d13`（工作树含未提交的 Companion Shell WIP）。
> 方法：设计文档（product / architecture / action-core / verification / companion-sprite / release /
> extensions）逐份与代码 grep 对照，每项都有证据链；只列「明确写过设计」的项，
> 泛化愿望与未决产品问题单独分层，不与确定欠账混淆。
> 本文件是快照，不是任务清单——完成一项就划掉一项，并注明完成它的提交。

## 一、完全没开始（Delores 自有，9 项）

| # | 功能 | 设计出处 | 代码现状 |
| --- | --- | --- | --- |
| 1 | **像素宠物渲染**（Companion Sprite） | `delores-companion-sprite.md`（已定稿，含 6 步实施表） | 只有步骤 0（Shell WIP）完成；`Scripts/gen-companion-atlas.js`、`Model/CompanionAtlas.generated.swift`、`Model/CompanionAnimation.swift` 全不存在，面板仍是 `NSHostingView` + 玻璃圆（`DeloresSpatialPanels.swift`） |
| 2 | **卡片头部模型选择器** | 参考实现 `ToolbarPanel.swift:1272`（卡片头 Menu，可换模型重跑）；工作日志 2026-09-17 05:49 明确「留给下一步」 | `DeloresContextIslandView` 卡片头部只有动作 chip + 重试/复制/替换原文；换模型只能去 Settings → Delores → Context Bar 预先绑定 |
| 3 | **思考过程可折叠块** | 参考 `ToolbarPanel.swift:1778-1810`（`ReasoningBlockView`：思考期展开、答案开始折叠、可回看） | `ActionSessionRunner` 的流循环 `guard case .text` 直接丢弃 `.thinking` 事件；UI 无任何思考块 |
| 4 | **玻璃基底主题纱** | 参考 `surfaceScrimOpacity`（浅 0.30 / 深 0.36），注释写明原因：全屏黑菜单栏下系统玻璃变黑、浅色主题文字对比度仅 1.2:1 | Delores 的 `Theme.glassFrost` 是白色 0.25/0.05；修它要波及 palette/HUD 等上游组件，未动 |
| 5 | **Companion 打字时暂停游走** | `delores-verification.md` 明写 *not implemented*；信号 `CGEventSource.secondsSinceLastEventType`，无需新权限 | 全仓零引用该 API；无键盘空闲检测、无暂停/恢复状态机 |
| 6 | **Companion 全屏 Space 抑制** | `delores-verification.md`（accepted gap） | 面板 `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`，无全屏检测与抑制逻辑 |
| 7 | **Companion 无障碍 label + 菜单栏入口** | `delores-verification.md`（键盘-only 用户无法触达） | `DeloresCompanionView` 无 accessibilityLabel；Delores 自有代码无 `NSStatusItem`（vendored Huaci 里的不算，未编译进 target） |
| 8 | **表情回落 idle / 捕获变化提示 / 无选区真气泡** | `delores-verification.md` 三连缺口 | `play()` 只整建 rootView、无回落 timer；捕获变化无可见通知；`showBubble()` 现在只是 `play(.chat)`，不是真 bubble panel |
| 9 | **公共发布通道** | `delores-release.md`（有意不配，防误用 Tinycast feed） | GitHub release feed、stable/beta/dev bundle IDs、签名/公证 identity、Homebrew cask、updater 兼容全部待配置；`release.yml` 被 `DELORES_RELEASE_ENABLED` 门禁禁用 |

## 二、收敛未完成（Phase B 剩余）

| 项 | 状态 | 证据 |
| --- | --- | --- |
| **Translate 一个 id 两个 backend** | 2026-09-17 已拍板（`delores-action-core.md` §Translate），**代码未落地** | `QuickActionRunner` 仍是 `builtInAction == .summarize` 的 enum 分支；「绑定了路由就用路由，否则用框架」未实现；同名 summarize 双上限（512 vs `min(count/3,512)`）仍并存 |
| **步骤 4：Tinycast 四 case → 四 definition** | 未决（依赖上一项） | `delores-action-core.md` §The order 第 4 步 |
| **Ask AI（selection-aware Chat 入口）** | seam 已建、无 row 使用——有意保留 | `.ask` 分支在 `DeloresContextCoordinator.run`；catalog 四行无一是 `.ask`（`ContextAction.swift`）；启用与否待产品拍板 |
| **fixGrammar / rewrite 回不回 Context bar** | 未决产品问题 | `delores-action-core.md` §What this document does not decide |
| **explain / search 上不上 Command Surface** | 未决（Phase C） | 同上 |

## 三、上游 Raycast 兼容明确不支持

以下为 Tinycast 上游边界（`docs/features/extensions.md` §What isn't supported yet），不是 Delores 欠账，同步上游时留意：

- `menu-bar` commands（可识别、展示不支持原因，无 runtime）
- Raycast PKCE proxy（`oauth.raycast.com`）——本地 PKCE 已有，代理转发无
- `AI` / `BrowserExtension` / `WindowManagement` 服务（import 可过、调用抛错）
- WebSocket（无 polyfill）
- 真正取消 in-flight fetch（AbortSignal 有 API、信号未传到 `URLSessionTask`）
- streaming `child_process.spawn`（现等待结束后一次性收集）
- `net` / `tls`（显式 unsupported stub）
- streaming HTTP（现一次性 buffered body）
- `tools/` AI-extension entry points（未暴露）

## 四、部分实现（有代码、有明确缺口）

- **Spatial 边界条件**（`delores-architecture.md` "Still experimental"）：`findSplitPair` 不排除遮挡窗口/其他 Space/焦点在别处的应用；seam 扫描 80ms 节流且在主线程 IPC；无 per-surface rollback、无 Space/全屏/display-change 观察者；Companion click-through 与多屏行为无自动化测试
- **Companion Shell（工作树 WIP）**：`Model/CompanionShell.swift` + 五个文件改动 + 98 行断言已实现并过 harness，但**未提交**——动任何一项前先把它 commit，避免与像素宠物步骤 1 混在一个变更集

## 五、有意不算欠账的（避免重复排查）

- `future context-appropriate actions`（product.md）——泛化扩展空间，无具体验收
- ESC 不两段式、搜索默认 Bing、润色/问 AI 目录删除——记录在案的有意取舍
- Huaci vendored 源码不编译进 app target——ADR 0002 明确决策
- 像素宠物「导入自定义宠物生态」——sprite 方案明确「明确不在本版」

## 优先级直觉（2026-09-18）

- **模型选择器**：万事俱备（`setModelOverride(_:forActionID:)` 写入接缝已存在），跨 view/controller/coordinator/AppCore/store 五文件，单独切片
- **像素宠物步骤 1–2**：方案定稿 + 步骤 0 已就绪，纯新增文件（记得 `xcodegen generate` + 手加 harness 清单）
- 其余 Companion 缺口可搭像素宠物的手势表情接线（步骤 4）顺手做
