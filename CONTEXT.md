# Delores 领域词汇

Delores 是一个根据用户当前意图选择交互形态的 macOS 原生 AI Command Layer。
本词汇表只记录产品与领域概念，不记录具体实现名称。

## 交互概念

**Surface**：用户在某一类意图下看到的交互形态。Surface 只表达任务，不拥有底层能力。
Delores 只有三个 Surface：Command、Context、Companion。
_Avoid_: 页面、功能模块

**Command Surface**：用户主动召唤 Delores、搜索能力或发起新任务时使用的交互形态。
它是三个形态里最完整的一个，负责复杂任务、AI 对话与设置。
_Avoid_: Launcher、万能窗口

**Context Surface**：用户已经选中文字或其他对象后，围绕该对象提供最小操作入口的交互形态。
它存在于屏幕顶部，出现的理由是「我已经选好了东西」。
_Avoid_: 划词工具栏、快捷菜单

**Companion Surface**：不需要被召唤、平时就待在桌面上的一点点存在感，让 Delores 随手指得到。
它的职责是「被找到」——看一眼、回到最近一次选区、把用户送去真正干活的 Surface。
_Avoid_: 桌宠聊天框、第二个 AI 客户端

**Capability**：真正做事的能力，属于 Core 而不属于任何 Surface。例如 AI Actions、Search、
Clipboard、Notes、Text Injection、Window Placement（含窗口吸附与分屏中缝）。
Surface 呈现任务和结果，不拥有产生它的能力。
_Avoid_: 把 Capability 当成第四个 Surface

**Action**：一个可从多个 Surface 进入的用户能力，例如翻译、总结或改写。
能力只有一个，入口可以有多个。
_Avoid_: 按钮、入口

**Invocation Context**：一次任务启动时捕获的来源、目标对象和环境快照。
它让不同 Surface 共享同一任务上下文，而不重复读取或询问用户已经提供的信息。
_Avoid_: 当前状态、全局上下文

**Surface Arbitration**：当多个 Surface 可能响应同一输入时，根据可交互性和任务状态决定
哪个 Surface 接收事件，避免一个输入同时启动或关闭多个 Surface。
_Avoid_: 把所有可见窗口视为同一种 Surface

**Gesture Admission**：一次瞬时鼠标手势只允许被一个消费者接管——可能是某个 Surface，
也可能是一个 Capability（例如窗口吸附或分屏中缝）。开关可以同时打开，手势不能同时被消费。
_Avoid_: 用「某个功能开着就关掉另一个功能」来代替手势仲裁

## 代码来源关系

**Upstream Overlay**：以 Tinycast 上游代码为基线、把 Delores 定制限制在独立层和少数接缝中的产品组织方式。
_Avoid_: 全量复制、二次开发分支

**Upstream Sync**：将 Tinycast 新提交引入 Delores，并重新验证定制层边界和产品行为的过程。
_Avoid_: 自动升级、直接覆盖

**Vendored Integration**：把另一个项目的最新源代码以明确目录边界纳入 Delores，保留其独立
构建和测试入口，再通过适配层逐步接入运行时。
_Avoid_: 直接把两个 AppDelegate 合并、双重 AI 管线
