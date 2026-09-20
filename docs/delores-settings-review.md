# Delores 设置页评审

> 评审对象：`⌥Space` → 设置（`Tinycast/Features/Settings/`，19 个 pane）
> 评审依据：`docs/delores-product.md` 三层决策宪法 —— 发心 → 定位 → 设计 → 架构 → 实现
> 日期：2026-09-20

## 结论摘要

设置页现在的侧边栏按 **Tinycast 的「代码归属」** 分组（General / Launcher / Features /
Advanced）。这套轴对一个「功能平行并列的启动器工具」是成立的，但它不是 Delores 的轴。

Delores 是一个核心长出的三张脸。用户打开设置时问的是「**我要改哪张脸的设置**」，
而不是「这个 pane 属于哪个模块」。当前布局把产品自己的名字降级成一个功能项，
并把同一个能力的配置切到了两个 pane 里。

**改造方向：让侧边栏成为产品定位的镜像。** 三个 Surface 升为一级分组，
产品总览排在最前，能力与系统归入下方。

---

## 诊断

### D1 — 组织轴用错（定位层）

`SettingsSection` 只有四个分组，全部沿用上游语义：

| 分组 | 装了什么 |
| --- | --- |
| General | 通用、权限 |
| Launcher | 应用程序、系统设置、系统操作、命令、快捷链接、快捷指令、无结果回退 |
| Features | AI、快捷操作、文件搜索、笔记、导航、窗口管理、**Delores**、剪贴板 |
| Advanced | 备份、关于 |

`Launcher` 组七项全是**启动器搜索条目的来源**，即 Command Surface 的一个能力被摊成了
七个平级 pane；`Features` 组则混装了能力、Surface 配置和产品名。

### D2 — 产品名成了功能项（定位层）

`.delores` 排在 `.features` 组的倒数第二位（`SettingsTab.swift:83`），
与 `.ai`、`.notes`、`.clipboard` 并列。

而这个 pane（`DeloresSpatialSettingsView.swift`）实际装的是**三个 Surface 中的两个
加一个能力**：Context Bar、Companion、Window Capabilities —— 它是离产品定位最近的一个 pane，
却排在最末。

### D3 — 一个 Surface 的开关与配置分居两地（定位层）

Context Surface 的 opt-in 边界是 `quickActionsEnabled`（`delores-architecture.md` 明确记载
"is still the opt-in boundary for the Context Surface"），它住在 **Quick Actions pane**；
而它的行目录、每行的模型绑定住在 **Delores pane** 的 `contextBarSection`。

后果：用户要开 Context Surface 得去「快捷操作」，要配它的行得去「Delores」。

> **注意**：文档同时记载「A separate Context switch should only appear when the product
> needs independent control, so the consent semantics do not split prematurely」。
> 因此本评审**不建议拆出独立开关**，只要求把入口归位（见阶段 4）。

### D4 — 一个能力被切成两个 pane（架构层）

- 「窗口管理」pane（`WindowManagementSettingsView`）= 窗口布局 + 布局命令 + 选项
- 「Delores」pane 第三段（`deloresSpatial`）= 窗口吸附 + 中缝
- 「Delores」pane 还借用了 `WindowManagement` 的 `systemImage`

按产品定位，吸附 / 中缝 / 布局 / 命令**都是 window placement 这一个能力**
（`CONTEXT.md`：「Capability…例如 …Window Placement（含窗口吸附与分屏中缝）」），
却跨了两个分组、两个 pane。

### D5 — 「通用」名不副实（设计层）

`GeneralSettingsView` 的六个区块里，五个是 **Command Surface 专属**：

| 区块 | 实际归属 | 证据 |
| --- | --- | --- |
| Global Shortcuts | Command Surface 入口 | 行标题 "App Launcher"，副标题 "Summon the fuzzy app launcher." |
| Search | Command Surface 行为 | "Learned ranking" |
| Hyper Key | 输入层（全应用） | — |
| Appearance | **主要**是 palette | 副标题写 "Scale the launcher"、"the glass background"、"Open the launcher as a slim search bar" |
| General | 应用级 | 登录启动、菜单栏、Escape 行为、输入源切换 |

用户以为点「通用」会看到产品的通用设置，实际看到的是**启动器设置**。
更糟的是：**用户打开设置的第一眼是「App Launcher 快捷键」**，
这个第一印象把 Delores 定义成了一个启动器，与发心相悖。

### D6 — 图标重复（缺陷）

`SettingsTab.systemImage` 中 `.ai` 与 `.delores` **都返回 `"sparkles"`**
（`SettingsTab.swift:42` 与 `:48`）。两个 pane 在侧边栏里图标完全相同，用户无法凭图标区分。

---

## 改造原则

1. **分组轴换成用户处境**：一级是「我在跟哪张脸说话」，不是「这段代码住在哪」。
2. **总览优先**：设置的第一屏回答「Delores 是什么、有几种用法」，而不是某个功能的一个快捷键。
3. **能力不下放**：Capability 属于 Core，在 UI 上应集中在一处，不随 Surface 复制。
4. **一个 Surface 的开关与配置同处**：找得到开关的地方，就找得到它的设置。
5. **不发明独立开关**：Context 的 opt-in 语义先不拆（尊重既有产品决策）。

---

## 目标信息架构

| 一级分组 | 二级 pane | 由来 |
| --- | --- | --- |
| **Delores** | 总览 | 新增 |
| **Command Surface** | 外观与输入 | 拆自 `general` 的 Global Shortcuts / Hyper Key / Appearance |
| | 搜索与排序 | 拆自 `general` 的 Search + `applications`、`systemSettings`、`systemActions`、`commands`、`fallbacks` |
| | 快捷链接 | `quicklinks` |
| | 快捷指令 | `appleShortcuts` |
| **Context Surface** | 划词栏 | `delores` 的 `contextBarSection` + Context 的 opt-in 入口 |
| **Companion Surface** | 陪伴者 | `delores` 的 `companionSection` |
| **能力** | 窗口摆放 | `windowManagement` + `delores` 的 `windowSection` |
| | AI | `ai` |
| | 快捷操作 | `quickActions` |
| | 剪贴板 | `clipboard` |
| | 笔记 | `notes` |
| | 文件搜索与导航 | `fileSearch` + `navigation` |
| **系统** | 权限 | `permissions` |
| | 备份 | `backup` |
| | 关于 | `about` |

---

## 分阶段落地

每阶段独立可验证、可回滚。建议按序推进，也可只做阶段 0–1。

### 阶段 0 — 图标去重（零风险，可立即做）

- **改动**：`SettingsTab.swift` 给 `.delores`（或拆分后的新 pane）换一个非 `sparkles` 的图标。
- **验证**：构建后看侧边栏，两个 pane 可区分。
- **风险**：无。

### 阶段 1 — 信息架构（只动 `SettingsSection`）

- **改动**：`SettingsSection` 的 `case` 与 `tabs` 改为上表的六个分组；
  `SettingsTab.allCases` 的声明顺序同步。
- **不涉及**：pane 内部、锚点、搜索索引 —— 因为 pane 归属集合未变。
- **验证**：
  - `node Scripts/check-settings-search.js`
  - `./Scripts/run-tests.sh settings-history-test`（该测试 pin 每个 pane 都被覆盖）
- **风险**：低。这是**收益/成本比最高**的一步 —— 不改任何 pane 内部逻辑，
  就能把「Delores 是功能列表里的一项」这个最刺眼的问题解决掉。

### 阶段 2 — 拆 `Delores` pane 为三个 Surface pane（核心）

- **改动**：
  - `DeloresSpatialSettingsView.swift` 拆为总览 / Context / Companion 三个 view
  - `SettingsTab` 新增对应 `case` 及其 `title`、`systemImage`
  - `SettingsAnchor` 新增对应常量
  - `SettingsSearchCatalog` 新增 pane 与行条目
  - 各 view 的 `.settingsScrollTarget(...)`
- **验证**：
  - `node Scripts/check-settings-search.js`（**必跑**，见下节）
  - `./Scripts/run-tests.sh settings-history-test`
  - `node Scripts/check-localization.js`（新增文案需进 `Localizable.xcstrings`）
- **风险**：中。这是本评审的**必要步骤** —— 不拆 pane，就无法真正按 Surface 组织。

### 阶段 3 — 能力合并

- **改动**：`windowManagement` 与 `delores` 的 `windowSection` 合并为「窗口摆放」；
  `general` 按目标结构拆分。
- **验证**：同阶段 2，另需人工确认没有设置项在搬迁中丢失。
- **风险**：中高。涉及跨 pane 搬迁设置项，**建议先列清单再动手**。

### 阶段 4 — Context 开关入口归位（需产品决策）

- **目标**：让 Context Surface 的 opt-in 开关在 Context pane 里可触达。
- **约束**：**不新增独立开关**。既有决策是不提前拆 consent 语义。
- **做法（二选一，需拍板）**：
  - A：Context pane 显示开关的**只读状态**，并提供跳转到 Quick Actions pane 的入口；
  - B：Context pane 内嵌一个绑定到同一个 `quickActionsEnabled` 的 `Toggle`
    （同一个 key，不产生第二个开关，但两处可写）。
- **风险**：产品决策，不是实现问题。**不要在没有明确指令的情况下自行选择。**

---

## 必须同步的技术约束

改设置结构时，以下三件套必须同时更新，否则 lint 红或运行时出现
「点了搜索结果、跳过去、停在那儿什么都不发生」：

```text
SettingsAnchor（声明 section）
        ↓  被引用
SettingsSearchCatalog（手写搜索索引）
        ↓  被校验
Scripts/check-settings-search.js（lint.sh 调用）
```

具体规则（来自 `docs/ui.md`）：

- 每个 anchor 必须被某个 `Section` 的 `header:` 声明（`SettingsSectionHeader(.x)`）。
- 每个 row 条目必须有匹配的 `SettingsRowTitle(.x, "标题")` 或 `SettingsRow(title:anchor:)`。
- 新增可见文案必须走 `L10n`，并进 `Localizable.xcstrings`；
  `node Scripts/check-localization.js` 会查。

另需注意：`SettingsTab` / `SettingsAnchor` / `SettingsDetailView` / `SettingsSearchCatalog`
同时是 Notes 接线的接缝（见 `delores-architecture.md` 的 ownership 表），
改动时一并复核。

---

## 本评审明确不做的事

- **不拆 Context 的独立开关** —— 见阶段 4，这是产品决策。
- **不重命名上游 `Tinycast/` 目录或上游文件** —— 制造同步冲突。
- **不重写 pane 的视觉** —— 每个 pane 保持 stock `Form` + `.formGrouped`，
  这是 `ui.md` 的既定规范，本评审只动信息架构与归属。
- **不动 `PaletteWindowController`、`AppCore` 等上游接缝** —— 与本议题无关。

---

## 实施记录 — 2026-09-20

**状态：阶段 0–4 已全部实施。**

### 与原计划的一处偏离

原方案阶段 3 要求把 `WindowManagementSettingsView` 与 Delores 的窗口段**合并成一个 pane**。
实施前核查发现 **`WindowManagementSettingsView.swift` 是上游文件**
（`delores-architecture.md` 的 ownership 表把 window engine 归 Tinycast），改它会新增上游同步冲突面。

改为：**窗口吸附独立成自己的 pane（`.windowSnapping`），与 `.windowManagement` 同属「能力」分组并相邻。**
产品目标（一个能力集中在一处）达成，上游边界不动。

### 最终信息架构

| 分组 | panes |
| --- | --- |
| Delores | Overview |
| Command Surface | Command Surface、Applications、System Settings、System Actions、Commands、Quicklinks、Apple Shortcuts、Fallbacks |
| Context Surface | Context Surface |
| Companion Surface | Companion Surface |
| Capabilities | Window Management、Window Snapping、AI、Quick Actions、Clipboard、Notes、File Search、Navigation |
| System | General、Permissions、Backup、About |

23 个 pane。（原 19 个；新增 5 个：Overview 复用 `.delores`、`.commandSurface`、
`.contextSurface`、`.companionSurface`、`.windowSnapping`；删除 1 个：原 `.delores` 三合一视图。）

### 改动清单

| 动作 | 文件 |
| --- | --- |
| 重写 | `Settings/SettingsTab.swift`（23 个 case、六分组、图标去重） |
| 重写 | `Settings/Panes/GeneralSettingsView.swift`（收窄为应用级两项） |
| 新建 | `Settings/Panes/CommandSurfaceSettingsView.swift`（承接 palette 专属项 + 两个私有辅助视图） |
| 新建 | `Delores/UI/DeloresOverviewView.swift`（产品总览，只读 + 导航） |
| 新建 | `Delores/UI/ContextSurfaceSettingsView.swift`（含 `ContextActionModelSheet`） |
| 新建 | `Delores/UI/CompanionSurfaceSettingsView.swift` |
| 新建 | `Delores/UI/WindowSnappingSettingsView.swift` |
| 删除 | `Delores/UI/DeloresSpatialSettingsView.swift` |
| 改锚点 | `Settings/SettingsAnchor.swift` |
| 改索引 | `Settings/SettingsSearchCatalog.swift` |
| 改路由 | `Settings/SettingsDetailView.swift` |
| 改测试 | `Tests/settings-history-test.swift`（2 条搜索断言 + 4 处锚点引用） |
| 改本地化 | `Resources/Localizable.xcstrings`（**+162 行纯追加，0 删除**） |
| 重新生成 | `Tinycast.xcodeproj/project.pbxproj`（20 增 4 删） |

**`CommandCatalog.swift` 的 `ownedCommands` 未改动** —— 三个新 pane 都不拥有 launcher 命令。

### 阶段 4 的决定

由 jackdu 拍板为「**面板内直接开关**」：Context Surface pane 内放一个绑定**同一个
`quickActionsEnabled`** 的 `Toggle`，与 Quick Actions pane 是同一个开关的两个入口，
不新增开关、不拆分 consent 语义。两处状态由 `@Bindable` 自动同步。

### 验证结果（本机 CommandLineTools，无 Xcode）

| 检查 | 结果 |
| --- | --- |
| `node Scripts/check-settings-search.js` | **✓ 退出码 0** |
| `node Scripts/check-localization.js` | **✓ 562 条目全部已翻译**（新增 18 键） |
| `./Scripts/run-tests.sh settings-history-test` | **✓ 通过** —— 覆盖「23 个 pane 全覆盖无重复」「索引覆盖每个 pane」「锚点归属正确」 |
| `./Scripts/run-delores-tests.sh` | **✓ 通过** |
| `TOOLCHAIN_DIR=… ./Scripts/lint.sh` | **✓ lint-clean** |
| `xcodegen generate` | **✓ 确定性生成，20 增 4 删** |
| `./Scripts/run-tests.sh`（全量） | **51 / 56**。5 个失败（appearance / interface-size / palette-placement / callout / notes-editor）**全部**是 `SwiftUIMacros.EntryMacro` 缺失所致，与本次改动无关 |
| swift-format 逐文件核对 | **✓ 本次改动与新建的 10 个 Swift 文件全部格式干净** |

### 本机无法执行的验证（如实记录）

- **app target 编译**：`xcode-select -p` 指向 `/Library/Developer/CommandLineTools`，无 Xcode，
  **无法编译 app target**。因此以下无法确证，需要一台有 Xcode 的机器补做：
  - 界面实际渲染（侧边栏六分组、总览页三行、开关与禁用态）
  - `Toggle` 在两处（Context Surface / Quick Actions）的状态同步
  - `SettingsRow` 包在 `Button` 里点击跳转的命中区域
- **格式**：`SettingsAnchor.swift` 有 1 处既有空行（第 96–97 行两个连续空行，位于
  `clipboardDisabledApplications` 与 `permissionsAccessibility` 之间）。**非本次引入，按
  「严禁顺手格式化无关内容」未动。**
- **SwiftLint 警告**：本次新增 2 条 `Line Length Violation`（`DeloresOverviewView.swift:34`、`:43`），
  均为无法拆分的完整文案字符串（拆开会使 catalog key 失配）。项目既有大量同类警告且警告不失败。

### 后续待办

1. 在有 Xcode 的机器上 `xcodebuild … -scheme Delores -configuration Debug build` 并肉眼验收。
2. 更新 `docs/delores-architecture.md` 的 ownership 表：`SettingsTab` / `SettingsAnchor` /
   `SettingsDetailView` / `SettingsSearchCatalog` 四个接缝的说明需要反映新的 pane 集合。
3. `docs/` 与 `website/` 里描述设置侧边栏的页面需要跟进（若有）。

