# Delores 领域词汇

Delores 是一个根据用户当前意图选择交互形态的 macOS 原生 AI Command Layer。
本词汇表只记录产品与领域概念，不记录具体实现名称。

## 交互概念

**Surface**：用户在某一类意图下看到的交互形态。Surface 只表达任务，不拥有底层能力。
_Avoid_: 页面、功能模块

**Command Surface**：用户主动召唤 Delores、搜索能力或发起新任务时使用的交互形态。
_Avoid_: Launcher、万能窗口

**Context Surface**：用户已经选中文字或其他对象后，围绕该对象提供最小操作入口的交互形态。
_Avoid_: 划词工具栏、快捷菜单

**Spatial Surface**：用户拖动窗口等空间对象时，围绕位置和布局提供反馈的交互形态。
_Avoid_: 窗口小功能

**Action**：一个可从多个 Surface 进入的用户能力，例如翻译、总结或改写。
_Avoid_: 按钮、入口

**Invocation Context**：一次任务启动时捕获的来源、目标对象和环境快照。
它让不同 Surface 共享同一任务上下文，而不重复读取或询问用户已经提供的信息。
_Avoid_: 当前状态、全局上下文

## 代码来源关系

**Upstream Overlay**：以 Tinycast 上游代码为基线、把 Delores 定制限制在独立层和少数接缝中的产品组织方式。
_Avoid_: 全量复制、二次开发分支

**Upstream Sync**：将 Tinycast 新提交引入 Delores，并重新验证定制层边界和产品行为的过程。
_Avoid_: 自动升级、直接覆盖
