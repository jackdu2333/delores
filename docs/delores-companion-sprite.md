# Delores — Companion 像素宠物渲染方案（Companion Sprite Plan）

> **状态：定稿。** 2026-09-17 由三轮调研收敛而成：现状代码核查、
> [petex](https://github.com/iebb/petex)（Electron）与
> [desktop-pet](https://github.com/Imzl-zl/desktop-pet)（原生 Swift）两个开源项目源码评审；
> 同日经产品宪法三层评审，四项裁决已并入正文（标为「裁决 1–4」）。按「实施步骤」执行。
>
> 裁决摘要：**1** 呼吸不排 Timer，交给 Core Animation；**2** 8 fps 是位移与切帧的统一帧率，
> 是取舍不是纯收益；**3** 朝向取位移的水平分量，竖边保持上一朝向；**4** 排在当前 Shell WIP 之后。

## 一句话结论

占位图标换成像素宠物，**内存下限不在美术，而在渲染层选型**：一张 sprite atlas 常驻解码
（≈184 KB），一个 CALayer 用 `contentsRect` 切帧，SwiftUI 完全退出宠物面板；静止零帧成本，
走路才有 timer。Companion 现有的 wander 骨架、手势语法、窗口壳全部保留，只换「画什么」。

## 发心对齐（产品宪法检查）

- **发心**：Companion 的职责是「被找到」——一瞥、上次选区、一次交接。宪法对它的原文是
  *an ambient presence, not another workspace*，职责列了五条，其中与形象相关的是
  *be visible without demanding attention* 与 *very lightweight ambient feedback*。
  **像素形象是让这个 ambient presence 更容易被一瞥认出的设计层选择，不是宪法赋予的新形态**
  ——宪法里没有「宠物」，也没有「第二种常驻形态」这种表述，本文档先前那样引用是不准确的。
  因此它**不得引入新框架、新依赖、新的常驻主线程开销**。
- **定位**：小而美 = 资产小、帧少、静止零成本。任何「更生动」的诉求若以常驻内存或持续
  CPU 为代价，违反定位，一律否决。
- **设计**：像素风是主动选择而非预算妥协——存 1x 艺术像素、GPU 最近邻放大，天然分辨率
  无关，永不需要 2x/3x 资产。

### 反向边界（「宠物」这个词自带引力，先写下来比事后逐个否决便宜）

`CONTEXT.md` 明确 `_Avoid_: 桌宠聊天框`。一旦「宠物」这个名字落地，需求会自然往养成方向滑。
写死：**像素形象只承载 ambient feedback，不承载情绪值、养成、可装扮、可对话、音效。**
Companion 不得因此获得一个新的配置面、一套历史或一个对话入口。任何一条被提出，回到发心层
重新裁决，而不是在设计层讨论它好不好看。

> 2026-09-18 补记：宠物的右键菜单（改形象 / 关闭宠物）**不是新的配置面**——它只有两件事，
> 都写 Settings 里已有的键（`deloresCompanionKind`、`deloresCompanionEnabled`），不新增状态、
> 不新增历史、不新增入口，也不引入养成。它是已有两项设置的**另一个入口**，边界未动。

## 路线裁决

| 路线 | 增量内存（量级） | 静止成本 | 判决 | 理由 |
| --- | --- | --- | --- | --- |
| **CALayer + 图集切 contentsRect** | ≈1–3 MB | **零**（呼吸由 CA 驱动，见裁决 1） | ✅ 采用 | 零依赖、零解码切帧、单 CGImage 常驻 |
| SwiftUI 逐帧切 Image | 2–5 MB | 每帧视图树 diff | ✗ | desktop-pet 源码注释实证：SwiftUI 逐帧是常驻宠物最大 CPU 项 |
| SpriteKit / SceneKit | 30–50 MB | GPU 上下文常驻 | ✗ | 杀鸡用牛刀；拉起整个渲染栈 |
| GIF（NSImage 动画） | 全帧常驻解码 | 常驻 | ✗ | 帧全驻留、256 色限制、无法按状态切行 |
| Lottie / Rive / 矢量动画 | 库本身小 | 低 | ✗ | **第三方依赖，违反零依赖红线** |
| 实拍宠物透明视频 | 20–60 MB+ | 持续解码 | ✗ | 与小而美相悖；WebM 透明度 AVFoundation 不支持 |
| Electron（petex 路线） | 150 MB+ | 常驻渲染 | ✗ 架构 / ✅ 格式 | 架构不可学；其 Codex 宠物格式规范可借（Apache 2.0） |

**desktop-pet 的独立帧数组路线**（加载时切成 N 个 CGImage、每帧换 `layer.contents`）也不
采用：每帧一个 CGImage 意味着 N 份解码副本与指针管理；单图集 + `contentsRect` 每帧只写一个
`CGRect`，常驻解码内存只有一份。将来兼容 petdex 导入生态时再按需评估独立帧（见「生态预留」）。

顺带修掉一个现状缺陷：`play()` 目前是 `hosting.rootView = DeloresCompanionView(expression:)`
——**每次 glance 都整建一次 SwiftUI 视图树**。换心后表情变化只写一个 `CGRect`。

## 内存账本（确定性部分）

解码内存 = 宽 × 高 × 4 字节（RGBA），与文件格式无关：

| 资产 | 尺寸 | 解码后 | 说明 |
| --- | --- | --- | --- |
| 初版图集（5 列 × 4 行，48×48/格） | 240×192 | **≈184 KB** | 本方案初版规格 |
| Codex/petdex 全量格式（8×11 格，192×208/格） | 1536×2288 | ≈14 MB | 生态兼容时的上限参考，仍远低于视频路线 |
| 显示尺寸 | — | 0 | `magnificationFilter = .nearest`，GPU 采样放大，不增加解码内存 |

预算门禁：**Companion 开启 vs 关闭，进程 footprint 增量 ≤ 3 MB**（含图集、图层、面板）。

## 像素风纪律（不可协商）

1. **存 1x 艺术像素**，显示尺寸取艺术尺寸的**整数倍**（48 或 96 pt，不取 61 pt），
   否则最近邻采样产生不均匀像素行，肉眼即「抖」。
2. `layer.magnificationFilter = .nearest`（当前 desktop-pet 用 `.linear`，那是位图宠物；
   像素风必须 nearest）。`minificationFilter` 同理。
3. `contentsScale` 跟随 `window.backingScaleFactor`，在
   `viewDidChangeBackingProperties()` 里重设（跨屏拖拽时保持锐利）。
4. 帧格矩形用图集像素尺寸计算后归一化：`contentsRect` 是 0–1 单位空间，
   `CGRect(x: col/cols, y: row/rows, width: 1/cols, height: 1/rows)`；**行序从上往下数，
   Core Animation 的 y 轴原点在左下**，映射时翻转一次。

## 裁决 1：呼吸不排 Timer（静止零唤醒）

现状 `syncWanderTimers()` 在 `.resting` 只挂**一个一次性 wakeTimer**，resting 期间一帧都不跑。
这是 Companion 当前最硬的能耗性质，也是代码注释的原文。图集行 0 若用 Timer 驱动呼吸，这条性
质就没了——而本文档先前把验收门禁改成「零 timer 唤醒（呼吸除外）」，那是拿实现便利反过来改
产品方向，产品宪法禁止的正是这个动作。

**因此：呼吸由 Core Animation 驱动，主线程不排 Timer、不跑 Swift 代码。**

```swift
let animation = CAKeyframeAnimation(keyPath: "contentsRect")
animation.values = [rect(row: .idle, frame: 0), rect(row: .idle, frame: 1)]
animation.calculationMode = .discrete      // 见下：不加这一行就是错的
animation.repeatCount = .infinity
animation.duration = 2.0                   // 两帧各停 1s，即 1 fps 的呼吸
layer.add(animation, forKey: "breath")
```

三个必须遵守的点：

- **`calculationMode = .discrete` 是必需的，不是优化。** `contentsRect` 是可动画属性，默认
  会在两个 `CGRect` 之间线性插值，插值出来的矩形落在图集格子**之间**，切出一段错位的图像。
  离散模式让每帧直接跳变，这正是逐帧动画要的。
- **切行走前必须 `removeAnimation(forKey:)`。** 动画在跑时直接写 `layer.contentsRect` 改的是
  model value，屏幕上仍是 presentation value，写进去看不到。离开 resting 先移除再设值。
- **动画不是 Timer，也不是轮询。** 提交后由 render server 推进，主线程不唤醒。这是「零 timer
  唤醒」门禁的真实满足方式；剩余的合成成本在 render server 侧，不在我们的 RunLoop 上。

**眨眼**保留一次性 Timer，但它是**排期**而非驱动：3–8 s 随机一次，触发后播一个一次性的离散
关键帧动画（眨眼帧序列），播完回落 idle。这是静止期间主线程唯一的唤醒来源，量级为 3–8 s 一次
且非周期性——与「每 0.5 s 一次的常驻呼吸」不是一个数量级，可以接受，并在门禁里写明。

## 裁决 2：8 fps 是位移与切帧的统一帧率

`strollFrame = 1/20` 这个 timer 不只切帧，它同时驱动 `advanceWander()` → `companion.move(to:)`。
降到 8 fps，**位移本身也变成 8 fps**（speed 8–18 pt/s → 每帧 1.0–2.25 pt）。

所以这不是「timer 触发省 60%」的纯收益，而是一次取舍：行走的位移平滑度下降，换来帧率更符合
像素味、唤醒次数减少 60%。**接受，但必须按取舍记录，不得写成优化。**

解耦（位移 20 fps、切帧 8 fps）需要两个 timer，与「不新增 timer」冲突，不采用。

> 2026-09-18 应用户要求调成懒散节奏：walkFrame 12→8 fps，speed 16–34→8–18 pt/s，短歇
> 2–8→4–14 s，长歇概率 0.25→0.4，短程 120–360→90–240 pt，长途概率 0.2→0.15。Companion
> 的默认状态从「散步」改成「闲逛」：多数时间在原地歇着，走起来也是拖沓的步频。

## 裁决 3：朝向取位移的水平分量，竖边保持上一朝向

wander 沿**周长**移动，方向是周长的 sign；而「走左 / 走右」是**水平**语义。在 `.left` /
`.right` 竖边上移动时是垂直位移，sign 对应上下而不是左右——此时朝向无定义。
`DeloresCompanionWander.State` 里也没有方向字段（`Phase.strolling` 只有 `destination` 与
`speed`），朝向必须另算。

规则（放 `Model/`，进 harness 断言）：

```swift
static func facing(from previous: CGPoint, to current: CGPoint, fallback: Facing) -> Facing
```

- `dx > 0` → `.right`；`dx < 0` → `.left`；
- `dx == 0`（在竖边上纯垂直移动，或静止）→ **返回 `fallback`**，即保持上一朝向。宠物在竖边上
  不该每帧翻面。
- `fallback` 由调用方（coordinator）持有并随每次判定更新，纯函数本身无状态。

**行走行之外一律 idle 行**：`resting`、`isHoldingShell`、`isCaptured`、拖拽中（`wander == nil`）
都映射到行 0。这是最简规则，也顺带覆盖了拖拽与驻留捕获这两种先前未定义的状态。

## 裁决 4：排在当前 Shell WIP 之后

`Model/CompanionShell.swift`（未提交）**不是精灵的壳**：它定义的是「Companion 打开的 bar/card
挂在哪」——纯 CoreGraphics 几何，已进 `run-delores-tests.sh` 清单并有 98 行断言
（`testCompanionShell`）。

本方案的「面板尺寸 44→48」会牵动它整层：`visibleSize = 28` / `visibleRadius` / `circleFrame` /
`snapCenter` / `placeShell` / `hangDownFrame`，以及 panel `move(to:)` 里硬编码的 `22`。全部要
重算并重新断言。

**因此：先让 Shell WIP 落地并被验证，再动尺寸。** 精灵工作排在它之后。

2026-09-18 补记：Shell WIP 已落地并扩展——竖边竖条（`edgeForOpeningBar` 解析 resolved edge，
`hangDownFrame` 升级为书脊语义：竖条时卡与条共享贴宠物侧缘）与分屏岛宠物触发
（`planIslandOpening` + `dragHitFrame`，岛的长轴沿宠物所贴边，贴顶仅为无宠物兜底）均已进
`testCompanionShell` 断言并通过；尺寸 44→48 仍是本方案自己的返工项。

顺带一条命名纪律：**「shell」在 Companion 语境里已被占用**（指从身体长出的栏）。精灵相关类型
不得使用 `…Shell`；`…Sprite` 也应避开，以免与生态期的 `SpriteSlicer` 混淆。

## 架构：换什么、留什么

```text
现在（占位图标）                        规划（像素精灵）
─────────────────────                  ─────────────────────
DeloresCompanionCoordinator            DeloresCompanionCoordinator   ← 不动（+ 持有 facing）
  ├─ 手势/驻留/游走调度                  ├─ 同左，仅 play() 落点改为「切行」
  └─ DeloresCompanionPanel             └─ DeloresCompanionPanel      ← 壳不动，尺寸 44→48
       └─ NSHostingView<SwiftUI>            └─ NSView（空壳，wantsLayer）
            └─ 玻璃圆 + SF Symbol                └─ CALayer
                                                 ├─ contents = 图集 CGImage（唯一常驻）
                                                 ├─ contentsRect = 当前帧
                                                 ├─ magnificationFilter = .nearest
                                                 └─ 呼吸 = CA 离散关键帧（见裁决 1）

DeloresCompanionWander（Model）        ← 完全不动：静止零 timer、走路由单一 timer 驱动的骨架
                                         新增两条只读映射（放 Model 层，可进 harness）：
                                         ① 位移的水平分量 → 朝向行（走左/走右，见裁决 3）
                                         ② wander 相位 → 动画行（resting/holding/captured
                                            → idle 行；strolling → 行走行）
DeloresCompanionShell（Model）         ← 不动，但尺寸变更是它的返工项（见裁决 4）
```

**删掉的东西**：`NSHostingView`、`DeloresCompanionView`（SwiftUI）、玻璃圆
（`DeloresVisualEffectView` 在此面板的使用；snap island 仍在用它，不动）、
`play()` 整建 rootView 的写法。
`showBubble()` 首版语义不变——它当前就是 `play(.chat)`，映射到图集 chat 行即可。

## 初版图集规格（建议，资产制作时可调）

5 列 × 6 行，每格 48×48 艺术像素，PNG-8 带调色板（文件体积再省约 75%）：

| 行 | 动画 | 帧格 | 帧率 | 驱动 |
| --- | --- | --- | --- | --- |
| 0 | idle 呼吸（2 帧）+ 眨眼（1 帧） | 3/5 格 | 呼吸 1 fps | **CA 离散关键帧，无限重复（裁决 1）**；眨眼 = 一次性 Timer 排期 3–8 s，播一次即回落 |
| 1 | 走左 | 4/5 格 | 6 fps | 由 strollTimer 顺带切帧；四帧互不重复：接触 / 摆腿 / 对侧接触 / 对侧摆腿 |
| 2 | 走右 | 4/5 格 | 6 fps | 同上，镜像或对向源帧。位移权重与正在绘制的那一帧同号 |
| 3 | 反应：glance（2）+ wave（2）+ chat（1） | 5/5 格 | 8–12 fps | 一次性 CA 动画播 1–2 循环回落 idle |
| 4 | 待机闲趣：yawn / stretch / flop 趴地 | 4/5 格 | 2–4 fps | 长歇期间一次性 CA 动画，播完回落 idle |
| 5 | 杂技特写：hop / roll / landing 翻滚 | 4/5 格 | 5–8 fps | 特殊互动或掉落一次性 CA 动画，播完回落 idle |

**帧率策略（借 desktop-pet 生产验证）**：idle 呼吸恒钳 1–2 fps 封顶，与任何用户设置无关
（"calm CPU win"）；行走 8 fps——从初版 `strollFrame = 1/20` **下调**，慢步频配合懒散人设
（见裁决 2）。
行走切帧不新增 timer：`advanceWander()` 每 tick 已在主线程，顺带推进帧序，代价见裁决 2。

资产生成走 `Scripts/gen-companion-atlas.js`（Node，同 `gen-currencies.js` 家风）：输入源帧
PNG，输出图集 + `CompanionAtlas.generated.swift`（行列枚举与帧数常量）。生成物不手改，
且**必须提交**——构建不得依赖 Node。
Petdex 皮肤的走路行由 `Scripts/gen-companion-petdex.py` 重切：源表 8 帧取 0/2/4/6，贴地对齐、最近邻缩放，idle 等行不动。

**归属**：`CompanionAtlas.generated.swift` 放 `Features/Delores/Model/`（纯常量，可进 harness）；
图集 PNG 放 `Tinycast/Resources/`。

## 生命周期与并发（Swift 6 纪律）

- 图层帧循环**不新增常驻 Timer**：呼吸是 CA 动画，行走帧由 strollTimer 顺带驱动，只有眨眼是
  一次性排期（3–8 s，非周期）。
- 相位切换时**先移除动画再写 `contentsRect`**：resting → 挂 `breath`；离开 resting
  （strolling / holding / captured / 拖拽）→ `removeAnimation(forKey: "breath")` 后设值。
- `configure` 类方法必须**幂等**：状态没变不重启任何 timer、不重挂动画（desktop-pet 实证：
  SwiftUI 父层重渲染可达显示频率，非幂等 configure 会反复重建 timer）。
- **teardown 显式停 timer 并移除动画**：Swift 6 禁止 nonisolated deinit 触碰非 Sendable timer；
  面板 `hide()` 与 coordinator `stopCompanion()` 里逐个失效（现有代码已是此家风，保持）。
  `hide()` 一并 `removeAllAnimations()`——orderOut 后不保证还合成，不依赖这个假设。
- timer 挂 `RunLoop .common` mode——menu/scroll 跟踪期不断帧（现有 strollTimer 同款）。

## 开源借鉴清单（源码级评审结论）

| 来源 | 借什么 | 协议合规 |
| --- | --- | --- |
| **desktop-pet**（MIT，原生 Swift） | ① fps 按状态钳制策略；② configure 幂等 + teardown 显式回收；③ Timer 挂 .common；④ `ImageSpriteView` 注释作为「SwiftUI 逐帧是 CPU 大头」的反面教材存档；⑤ 生态期的 alpha 透明沟自动切帧算法（`SpriteSlicer`，137 行） | MIT，思路与策略自由借鉴，**不逐行拷贝代码**；拷贝则保留版权声明 |
| **petex**（Apache 2.0，Electron） | 仅格式：Codex 宠物规范 `pet.json` + 网格图集（v1 8×9 / v2 8×11，192×208/格，≤32 MB，PNG/WebP）作为未来导入生态的资产格式 | 规范本身自由实现；不引入其任何运行时代码 |

两者共同印证的窗口壳配置（borderless nonactivatingPanel / floating / clear /
canJoinAllSpaces + fullScreenAuxiliary / becomesKeyOnlyIfNeeded）与
`DeloresCompanionPanel` 现有实现一致，不动。

## 生态预留（明确不在本版）

「导入自定义宠物」（petdex/pet.json 兼容、alpha 沟切帧、参差行支持）**不做进首版**。
首版只交付内置图集 + `SpriteRow` 枚举；格式兼容在 Companion 稳定后另立任务，届时
desktop-pet 的 `SpriteSlicer` 算法与 petex 的格式文档即参考库。此为「最小充分方案」纪律：
不为未到来的生态预付复杂度。

## 实施步骤（每步可独立验证）

| # | 步骤 | 产出 | 验证 |
| --- | --- | --- | --- |
| 0 | **先落地当前 Shell WIP**（裁决 4） | `CompanionShell.swift` + `testCompanionShell` | ✅ 2026-09-17：harness 通过，Debug build 零警告 |
| 1 | 资产与生成脚本 | 源帧 + `gen-companion-atlas.js` + `Resources/` 下图集 PNG + `Model/CompanionAtlas.generated.swift` | 脚本重跑幂等；图集尺寸/行列符合规格；生成物已提交 |
| 2 | Model 层映射 | `CompanionAnimation.swift` 纯函数：① 相位→行；② `facing(from:to:fallback:)`（裁决 3）；③ `contentsRect(row:frame:)`，y 轴翻转只在这里发生一次。进 `run-delores-tests.sh` 清单 | ✅ 2026-09-18：harness 断言全过（resting/held→idle、strolling 左右→对应行、竖边 dx==0 保持 fallback、帧矩形与帧率钳制值） |
| 3 | CALayer 换心 | `DeloresCompanionBodyView`（空壳 NSView + CALayer）；删 `DeloresCompanionView` 与玻璃圆；呼吸接 CA 离散动画（裁决 1）；尺寸 44→48，真相源收进 `DeloresCompanionShell.visibleSize` | ✅ 2026-09-18：xcodebuild 零错误零警告，图集已进 bundle；材质差异已补记进架构文档；像素锐利度与「无玻璃底」仍需真机肉眼 |
| 4 | 手势表情接线 | `play()` → `react()`；wander 相位驱动 `rest()` / `step(frame:facing:)`；捕获、持 shell、拖拽一律 idle；帧率降到 8 fps（裁决 2） | ✅ 2026-09-18：编译通过、harness 通过。**五手势的实际观感与「播完回落 idle」仍需真机手动验收** |
| 5 | 设置页 | 尺寸档位 48/96 两档（`DeloresCompanionShell.Size`）；身体半径成为**注入参数**而非静态常量——这正是裁决 4 说的返工 | ✅ 2026-09-18：编译、harness、settings-search 全过。Shell 那 98 行断言因本就按 `radius` 书写，尺寸注入后**无一条需要改**。**切档后无像素抖、跨屏拖拽不糊仍需真机肉眼** |
| 6 | 验收门禁 | 见下 | 全绿 |

## 验收门禁

1. **内存**：`footprint` 对比 Companion 开/关，增量 ≤ 3 MB。
2. **静止能耗**：Instruments Time Profiler 60 s 采样，**resting 相位零 Timer 唤醒**，无例外。
   呼吸必须是 CA 动画（裁决 1）；唯一允许的唤醒是眨眼的一次性排期（3–8 s 一次、非周期）。
   若这一条做不到，回到发心层重新裁决，不得改门禁。
3. **视觉**：整数倍尺寸无像素抖；呼吸/行走切帧无错位矩形（即 `calculationMode = .discrete`
   生效）；离开 resting 后行走帧立即生效（即动画已移除）；深/浅桌面下边缘干净；全屏 Space、
   多屏、屏变更 relocate 后位置与朝向正确。
4. **回归**：`run-tests.sh` 全绿（2026-09-17 基线：172 断言通过；`ext-test` 在全量并行下会偶发
   时序失败，**先单独重跑再判定**，它与 Delores 无共享源文件）；`run-delores-tests.sh` 通过
   （含新增的朝向与相位映射断言）。
5. **交互**：拖拽/驻留捕获/长按/双击开 Context 行为与现在完全一致（只换皮，不改语法）。

## 风险与未决

- **图集资产从哪来**：程序生成的占位像素宠物（脚本可控，风格朴素）vs 委托像素画师
  （风格好，周期与授权要谈）。建议先程序生成跑通链路，美术后置替换——图集路径与行列规格
  不变，换资产零代码改动。
- **玻璃底的取舍**：宠物脱离玻璃材质后与桌面壁纸的对比度依赖资产配色；浅色壁纸 + 浅色宠物
  会「消失」。缓解：资产带 1px 深色描边（像素风惯例），不回玻璃。
- **y 轴翻转坑**：contentsRect 行序与图集视觉行序相反，写映射时用工具函数一次封装，
  harness 断言具体帧矩形。
- **CA 动画的两个坑**（裁决 1 已给对策，此处留档）：忘记 `discrete` 会插值出错位矩形；
  忘记 `removeAnimation` 会让行走帧写不进去。两者都不会报错，只会画错。
- **本机不可自证项**（既有约束）：真实 Liquid Glass 透出、TCC 状态。像素路线不涉及玻璃，
  风险面缩小；视觉验收仍需人工肉眼。
