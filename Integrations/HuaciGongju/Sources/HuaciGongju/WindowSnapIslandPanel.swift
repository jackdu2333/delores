//
//  WindowSnapIslandPanel.swift
//  HuaciGongju
//

import Cocoa
import SwiftUI

// MARK: - Snap Slot Definitions (Canonical Production Slots)
public enum SnapSlot: String, CaseIterable, Identifiable {
    case leftHalf          // 1/2 Left
    case rightHalf         // 1/2 Right
    case mainWorkspace     // 2/3 Left (Scheme B)
    case sideWorkspace     // 1/3 Right (Scheme B)
    case maximize          // 100% Fullscreen
    case leftThird         // 1/3 Left (Scheme A)
    case centerThird       // 1/3 Center (Scheme A)
    case rightThird        // 1/3 Right (Scheme A)
    case topLeftQuarter     // 1/4 Top-Left
    case topRightQuarter    // 1/4 Top-Right
    case bottomLeftQuarter  // 1/4 Bottom-Left
    case bottomRightQuarter // 1/4 Bottom-Right

    // Backward-compatibility aliases
    public static var leftTwoThirds: SnapSlot { .mainWorkspace }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftHalf: return "左半屏"
        case .rightHalf: return "右半屏"
        case .mainWorkspace: return "主工作区"
        case .sideWorkspace: return "辅资料区"
        case .maximize: return "全屏最大化"
        case .leftThird: return "左三分之一"
        case .centerThird: return "居中三分之一"
        case .rightThird: return "右三分之一"
        case .topLeftQuarter: return "左上 1/4"
        case .topRightQuarter: return "右上 1/4"
        case .bottomLeftQuarter: return "左下 1/4"
        case .bottomRightQuarter: return "右下 1/4"
        }
    }

    public var ratioSubtitle: String {
        switch self {
        case .leftHalf: return "1/2"
        case .rightHalf: return "1/2"
        case .mainWorkspace: return "2/3"
        case .sideWorkspace: return "1/3"
        case .maximize: return "100%"
        case .leftThird: return "1/3"
        case .centerThird: return "1/3"
        case .rightThird: return "1/3"
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return "1/4"
        }
    }

    public var systemImageName: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .mainWorkspace: return "rectangle.leadinghalf.filled"
        case .sideWorkspace: return "rectangle.trailinghalf.filled"
        case .maximize: return "rectangle.fill"
        case .leftThird: return "rectangle.split.3x1"
        case .centerThird: return "rectangle.split.3x1"
        case .rightThird: return "rectangle.split.3x1"
        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            return "rectangle.split.2x2"
        }
    }

    // 呼吸间距参数配置：外边距 6pt，窗口间距 8pt
    public static let outerMargin: CGFloat = 6.0
    public static let innerGap: CGFloat = 8.0

    public static func targetRect(for slot: SnapSlot, in visibleFrame: NSRect) -> NSRect {
        let vf = visibleFrame
        guard vf.width > (outerMargin * 2 + innerGap * 2) && vf.height > (outerMargin * 2 + innerGap) else {
            return visibleFrame
        }

        let outer = outerMargin
        let gap = innerGap
        let usableY = vf.minY + outer
        let usableH = max(0.0, vf.height - outer * 2)

        switch slot {
        case .leftHalf:
            let availW = max(0.0, vf.width - outer * 2 - gap)
            let w = floor(availW * 0.5)
            return NSRect(x: vf.minX + outer, y: usableY, width: w, height: usableH)

        case .rightHalf:
            let availW = max(0.0, vf.width - outer * 2 - gap)
            let leftW = floor(availW * 0.5)
            let rightW = max(0.0, availW - leftW)
            return NSRect(x: vf.maxX - outer - rightW, y: usableY, width: rightW, height: usableH)

        case .mainWorkspace:
            let availW = max(0.0, vf.width - outer * 2 - gap)
            let w = round(availW * (2.0 / 3.0))
            return NSRect(x: vf.minX + outer, y: usableY, width: w, height: usableH)

        case .sideWorkspace:
            let availW = max(0.0, vf.width - outer * 2 - gap)
            let mainW = round(availW * (2.0 / 3.0))
            let sideW = max(0.0, availW - mainW)
            return NSRect(x: vf.maxX - outer - sideW, y: usableY, width: sideW, height: usableH)

        case .maximize:
            return vf.insetBy(dx: outer, dy: outer)

        case .leftThird:
            let availW = max(0.0, vf.width - outer * 2 - gap * 2)
            let w = round(availW / 3.0)
            return NSRect(x: vf.minX + outer, y: usableY, width: w, height: usableH)

        case .centerThird:
            let availW = max(0.0, vf.width - outer * 2 - gap * 2)
            let w1 = round(availW / 3.0)
            let w3 = round(availW / 3.0)
            let w2 = max(0.0, availW - w1 - w3)
            return NSRect(x: vf.minX + outer + w1 + gap, y: usableY, width: w2, height: usableH)

        case .rightThird:
            let availW = max(0.0, vf.width - outer * 2 - gap * 2)
            let w = round(availW / 3.0)
            return NSRect(x: vf.maxX - outer - w, y: usableY, width: w, height: usableH)

        case .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            let halfW = floor((vf.width - outer * 2 - gap) * 0.5)
            let halfH = floor((vf.height - outer * 2 - gap) * 0.5)
            let rightW = max(0.0, vf.width - outer * 2 - gap - halfW)
            let topH = max(0.0, vf.height - outer * 2 - gap - halfH)
            let leftX = vf.minX + outer
            let rightX = vf.minX + outer + halfW + gap
            let bottomY = vf.minY + outer
            let topY = vf.minY + outer + halfH + gap

            switch slot {
            case .topLeftQuarter:
                return NSRect(x: leftX, y: topY, width: halfW, height: topH)
            case .topRightQuarter:
                return NSRect(x: rightX, y: topY, width: rightW, height: topH)
            case .bottomLeftQuarter:
                return NSRect(x: leftX, y: bottomY, width: halfW, height: halfH)
            case .bottomRightQuarter:
                return NSRect(x: rightX, y: bottomY, width: rightW, height: halfH)
            default:
                return visibleFrame
            }
        }
    }
}

// MARK: - Snap Island Geometry (UI 布局与命中测试的唯一真源)

/// 分屏岛的几何真源。
///
/// **这是唯一允许定义分屏岛尺寸的地方**，UI 布局与命中测试同时消费它：
///
/// ```
///        UI Layout (SwiftUI)  ──▶  同一份 Geometry  ◀──  Hit Testing (slot(at:))
/// ```
///
/// 坐标系与 `NSWindow.frame` 一致：原点在面板**左下角**，y 轴向上，单位 pt。
///
/// 四张卡片宽度之和刻意凑成「面板宽度 − 左右内边距」，使 HStack 不产生居中偏移，
/// 命中区与视觉严格 1:1 对齐（`fitsExactly` 守护该不变量）。
/// 此后调整任一常量都会自动同步到命中测试，无需再在 `slot(at:)` 里维护魔法数字。
public struct SnapIslandGeometry {

    // MARK: - 卡片（顺序与 UI 从左到右一致）

    public enum Card: Int, CaseIterable {
        case halfSplit   // 二分屏 1/2
        case mainSide    // 主辅 2:1
        case quarter     // 四等分 1/4
        case thirds      // 标准三等分 1/3

        /// 条目宽度 —— 同时是**不可见命中区**的宽度。
        ///
        /// 它明显大于 `glyphSize.width`，两者之差就是「命中区可以大，
        /// 但视觉上不画出来」的那部分余量。
        public static let itemWidth: CGFloat = 140

        /// 图元（视觉）尺寸。
        ///
        /// 宽度随分区列数略有差别，高度统一为 64pt。
        /// 宽高比刻意保持在 **1.66 ~ 1.75**，接近真实显示器 ——
        /// 一旦比例失衡（例如只拉高不拉宽），图元就读不成「一块屏幕」了。
        public var glyphSize: CGSize {
            switch self {
            case .halfSplit: return CGSize(width: 108, height: 64)
            case .mainSide:  return CGSize(width: 110, height: 64)
            case .quarter:   return CGSize(width: 106, height: 64)
            case .thirds:    return CGSize(width: 112, height: 64)
            }
        }

        /// 条目宽度（布局与命中测试共用）
        public var width: CGFloat { Self.itemWidth }
    }

    // MARK: - 布局常量（UI 与命中测试共用）

    public static let panelSize = CGSize(width: 620, height: 88)
    /// 条目区左右内边距
    public static let horizontalPadding: CGFloat = 12
    /// 条目区上下内边距
    public static let verticalPadding: CGFloat = 8
    /// 相邻条目之间的间距 —— 条目之间**不再有分隔线**，关系完全由间距建立。
    ///
    /// 24 → 12：文案移除后条目的「重心」完全落在图元上，原间距（连同左右各一圈
    /// 条目内留白，图元边缘之间实测 76pt）会把四个图元推得过于疏离。
    /// 收窄后图元边缘间距约 43pt，同时条目宽度得以从 130 涨到 140（命中区同步变大）。
    public static let interItemSpacing: CGFloat = 12
    /// 岛体圆角（= 面板高度的一半，形成完整胶囊）
    public static let cornerRadius: CGFloat = 44

    /// 图元内分割线宽度
    public static let glyphDividerWidth: CGFloat = 1.4
    /// 图元圆角。
    ///
    /// 刻意取小：图元语义是「屏幕」，4.5 / 64 ≈ 7%，接近真实显示器比例。
    /// 早期用 8（在 46pt 高下是 17%）时，四枚图元会读成「四个带说明文字的 App 图标」，
    /// 和 44pt 完整胶囊的容器分属两套圆角语言。
    public static let glyphCornerRadius: CGFloat = 4.5

    /// 相邻两个条目外缘之间的距离（已无分隔线，等于 `interItemSpacing`）
    public static var cardGap: CGFloat { interItemSpacing }

    /// 条目高度 = 面板高度 − 上下内边距
    public static var cardHeight: CGFloat {
        panelSize.height - verticalPadding * 2
    }

    // MARK: - 卡片矩形（命中测试直接使用）

    /// 四张卡片的矩形，按 UI 从左到右顺序铺排。
    ///
    /// 铺排规则与 `HStack` 完全一致：左内边距起排，每个条目后追加 `interItemSpacing`。
    public static let cardRects: [Card: CGRect] = {
        var rects: [Card: CGRect] = [:]
        var x = horizontalPadding
        for card in Card.allCases {
            rects[card] = CGRect(x: x, y: verticalPadding, width: card.width, height: cardHeight)
            x += card.width + cardGap
        }
        return rects
    }()

    public static func rect(for card: Card) -> CGRect {
        cardRects[card] ?? .zero
    }

    public static var halfCardRect: CGRect { rect(for: .halfSplit) }
    public static var mainSideCardRect: CGRect { rect(for: .mainSide) }
    public static var quarterCardRect: CGRect { rect(for: .quarter) }
    public static var thirdsCardRect: CGRect { rect(for: .thirds) }

    // MARK: - 卡片内部分区边界

    /// 二分屏左右分界（卡片内相对位置）
    public static let halfSplitRatio: CGFloat = 0.50
    /// 四等分左右分界（卡片内相对位置）
    public static let quarterSplitRatio: CGFloat = 0.50

    /// 主辅屏「主区 / 辅区」分界（条目内相对位置，0~1）。
    ///
    /// **由几何真源推导，不再硬编码** —— 图元尺寸、条目宽度、分割线宽度任一变化都会自动跟随：
    /// ```
    /// 图元在条目内水平居中 → 左留白 = (itemWidth − glyphWidth) / 2 = (140 − 110) / 2 = 15
    /// 图元内主区宽        = (glyphWidth − dividerWidth) × 2/3 = (110 − 1.4) × 2/3 = 72.4
    /// 分割线中心          = 左留白 + 主区宽 + dividerWidth / 2 = 15 + 72.4 + 0.7 = 88.1
    /// ratio              = 88.1 / 140 ≈ 0.6293
    /// ```
    ///
    /// 旧值是硬编码的 0.62。它既不等于布局语义的 2/3（0.667），也不等于图元实际分割线
    /// （≈0.629）—— 后果是**肉眼看到的分界线与鼠标真正切换 2/3 ↔ 1/3 的位置差约 1.3pt**。
    /// 既然 `SnapIslandGeometry` 已是 UI 与命中测试的唯一真源，这里就不该再留一个
    /// 「目前差不多」的常量；权重（`LayoutGlyphSpec.mainSide.columnWeights`）
    /// 本来就是图元绘制时用的同一份数据，直接推导即可保证二者永不脱钩。
    ///
    /// ⚠️ 命中边界因此右移约 1.3pt（0.62 → 0.6293）。视觉分毫未动，
    /// 只是把那 1.3pt 宽的判定带从「辅区」改判为「主区」—— 这正是要修的东西。
    public static var mainSideSplitRatio: CGFloat {
        let spec = LayoutGlyphSpec.mainSide
        let glyphWidth = Card.mainSide.glyphSize.width
        let weights = spec.columnWeights
        let weightSum = weights.reduce(0, +)
        guard !weights.isEmpty, weightSum > 0 else { return 0.5 }

        let inset = (Card.itemWidth - glyphWidth) / 2
        let dividerCount = max(0, weights.count - 1)
        let available = glyphWidth - glyphDividerWidth * CGFloat(dividerCount)
        let mainWidth = available * (weights[0] / weightSum)

        return (inset + mainWidth + glyphDividerWidth / 2) / Card.itemWidth
    }

    /// 四等分图元的垂直中线（面板坐标系，自底向上），用作上下格的命中分界。
    ///
    /// **由几何常量推导，不再硬编码** —— 任一常量变化都会自动跟随：
    /// ```
    /// 条目高 = panelSize.height − verticalPadding × 2
    /// 中线   = verticalPadding + 条目高 / 2      （图元在条目内垂直居中）
    /// ```
    /// 当前取值：8 + (88 − 8×2) / 2 = **44.0**。
    ///
    /// ⚠️ 44.0 恰好等于面板中线，但这是**推导的结果、不是假设**。
    /// 文案还在时图元被下压，中线是 54.0；那时若图省事直接取面板中点，
    /// 图元下半区就会被判成上半格。
    public static var quarterGlyphCenterY: CGFloat {
        verticalPadding + cardHeight / 2
    }

    // MARK: - 布局自检

    /// 卡片区是否正好铺满可用宽度。
    ///
    /// 为 true 时 HStack 无需居中偏移，命中矩形与视觉位置严格重合；
    /// 若为 false，命中区会整体偏移半个差值，肉眼难察但边界判定会漂。
    public static var fitsExactly: Bool {
        let contentWidth = Card.allCases.reduce(CGFloat(0)) { $0 + $1.width }
            + cardGap * CGFloat(Card.allCases.count - 1)
        return contentWidth == panelSize.width - horizontalPadding * 2
    }
}

// MARK: - View Model
public class WindowSnapIslandViewModel: ObservableObject {
    @Published public var hoveredSlot: SnapSlot? = nil
    @Published public var isAppearing: Bool = false
    public static let shared = WindowSnapIslandViewModel()
}

// MARK: - Layout Glyph Spec (统一分屏图元语言)

/// 单一屏幕的几何描述。
///
/// 把一块屏幕按列 / 行权重切开，每一格绑定一个落点。
/// 四种布局共享同一套图元语言，彼此只差分割线结构。
///
/// 每格曾另带一段文案（idle 显示布局名、hover 显示落点名），随条目文案一并移除 ——
/// 落点信息现在完全由图元自身的结构 + 被点亮的格子表达。
private struct LayoutGlyphSpec {

    /// 屏幕中的一格：承载一个落点
    struct Region {
        let slot: SnapSlot
    }

    /// 列宽权重（按比例分配可用宽度）
    let columnWeights: [CGFloat]
    /// 行高权重（按比例分配可用高度）
    let rowWeights: [CGFloat]
    /// 行优先的格子矩阵；每行的元素数量须与 `columnWeights` 数量一致
    let rows: [[Region]]

    var allRegions: [Region] { rows.flatMap { $0 } }

    // MARK: 四种生产布局

    /// 二分屏 1/2 —— 左右对半
    static let halfSplit = LayoutGlyphSpec(
        columnWeights: [1, 1],
        rowWeights: [1],
        rows: [[
            Region(slot: .leftHalf),
            Region(slot: .rightHalf)
        ]]
    )

    /// 主辅 2:1 —— 左主 2/3、右辅 1/3
    static let mainSide = LayoutGlyphSpec(
        columnWeights: [2, 1],
        rowWeights: [1],
        rows: [[
            Region(slot: .mainWorkspace),
            Region(slot: .sideWorkspace)
        ]]
    )

    /// 四等分 1/4 —— 田字格
    static let quarter = LayoutGlyphSpec(
        columnWeights: [1, 1],
        rowWeights: [1, 1],
        rows: [
            [
                Region(slot: .topLeftQuarter),
                Region(slot: .topRightQuarter)
            ],
            [
                Region(slot: .bottomLeftQuarter),
                Region(slot: .bottomRightQuarter)
            ]
        ]
    )

    /// 三等分 1/3 —— 左中右
    static let thirds = LayoutGlyphSpec(
        columnWeights: [1, 1, 1],
        rowWeights: [1],
        rows: [[
            Region(slot: .leftThird),
            Region(slot: .centerThird),
            Region(slot: .rightThird)
        ]]
    )
}

// MARK: - Layout Glyph Renderer (唯一图元渲染器)

/// ⚠️ **临时对比开关** —— 用于在四个图元方向上取图给用户挑选，定稿后删除，只保留选中的一套。
///
/// - `flat`   平玻璃片：均匀柔边 + 暗缝，最"示意图"
/// - `inset`  内嵌凹槽：图元**暗于**容器，顶阴影底微光 —— 像玻璃里挖出来的窗口
/// - `lifted` 浮起亮片：图元**亮于**容器，连续光泽 + 顶柔光 —— 像容器里的玻璃窗
/// - `pane`   分级透光片：浅色下主动**分级加暗**（顶部接光 → 底部落影），深色下保持受光凸起
///
/// 为什么需要 `pane`：浅色下容器背景实测 ≈ 249（近白），而 `flat` / `lifted` 的填充是
/// `Color.white.opacity(...)` —— 白色叠在近白上饱和，两者实测填充亮度都锁死在 246.3，
/// 与容器只差 2.7 级，肉眼只剩一圈描边，于是读成「容器里嵌了四个 App 图标」。
/// 浅色下要拉开层次只能**加暗**；但 `inset` 的均匀黑洗又会糊成灰块，
/// 所以 `pane` 用一层很弱、且沿垂直方向**分段加深**的暗色：既有轮廓，又有纵深。
/// 冷白（ice white）—— 白里透一点冷，用来替代 accent 蓝。
///
/// 这是整个分屏岛系统共用的那层 “very subtle cool tint”：靠**色相偏冷**拿到玻璃的冷调，
/// 而不是往里掺蓝色颜料，因此可以在完全不出现系统蓝的前提下成立。
///
/// 刻意放在文件级而非某个 struct 内部：图元（`LayoutGlyphView`）与落点预览
/// （`GhostPreviewContentView`）都要用它表达「被照亮」，两处必须共用同一份色值，
/// 否则同一套视觉语言会分叉。
private func iceWhite(_ alpha: Double) -> Color {
    Color(red: 0.93, green: 0.96, blue: 1.0).opacity(alpha)
}

public enum GlyphSkin: String, CaseIterable {
    case flat
    case inset
    case lifted
    case pane
    public static var active: GlyphSkin = .pane
}

/// 分屏图元渲染器 —— 一个「小型透明玻璃窗口模型」。
///
/// 视觉层级刻意压到最低：整个组件**只有一层外轮廓**。
///
/// 1. 分区填充**零间距**相接，整体被屏幕形状裁切 —— 所以内部边界是笔直的，
///    不会出现「小块各自带圆角」的卡片感；
/// 2. 明暗由**盖在整块图元上的一层连续光泽**（`glassSheen`）统一提供，
///    每格不再各自跑一遍渐变 —— 否则每道缝都会重启一次明暗，缝上出现亮度断崖；
/// 3. 分割线是主动画出来的接缝，不是填充之间露出的缝隙；
/// 4. 外轮廓是唯一的描边，且不随 hover 整体变色。
///
/// hover 只做一件事：把**被指向的那一格**换成 accent 玻璃，并在其后溢出一圈柔和
/// bloom 透到相邻格子里 —— 高亮的是「落点」，不是整个条目。
///
/// 尺寸来自 `SnapIslandGeometry.Card.glyphSize`，与命中几何共用同一份真源。
///
/// 约束：禁止在此组件内外引入 background、border、shadow 或第二层容器。
private struct LayoutGlyphView: View {
    let card: SnapIslandGeometry.Card
    let spec: LayoutGlyphSpec
    let hoveredSlot: SnapSlot?
    @Environment(\.colorScheme) var colorScheme

    private var size: CGSize { card.glyphSize }
    private var dividerWidth: CGFloat { SnapIslandGeometry.glyphDividerWidth }
    private let outlineWidth: CGFloat = 1.2

    private var isDark: Bool { colorScheme == .dark }

    private var screenShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SnapIslandGeometry.glyphCornerRadius, style: .continuous)
    }

    // MARK: 玻璃语义配色（按当前 skin）

    private var skin: GlyphSkin { GlyphSkin.active }

    /// 未激活单元格 —— 一层**均匀**的透光面。
    ///
    /// 刻意不做逐格渐变：每格各自从亮到暗，会在每一道缝上重启一次明暗，
    /// 行缝处因此出现 ~50 级亮度的断崖（真机实测 100 → 138 → 84），肉眼看起来发脏。
    /// 明暗统一交给下面盖在**整块图元**上的 `glassSheen`，缝上不再重启。
    private var idleCellColor: Color {
        switch skin {
        case .flat:   return Color.white.opacity(isDark ? 0.10 : 0.30)
        case .inset:  return Color.black.opacity(isDark ? 0.20 : 0.06)
        case .lifted: return Color.white.opacity(isDark ? 0.14 : 0.34)
        // pane：浅色走加暗（近白容器上唯一能出层次的方向），深色走受光的凸起面。
        case .pane:   return isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.05)
        }
    }

    private var idleCellStyle: AnyShapeStyle { AnyShapeStyle(idleCellColor) }

    /// 整块图元的连续光泽 —— **跨格不重启**。
    private var glassSheen: LinearGradient {
        switch skin {
        case .flat:
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(isDark ? 0.15 : 0.40), location: 0.00),
                    .init(color: Color.white.opacity(isDark ? 0.03 : 0.10), location: 0.40),
                    .init(color: Color.white.opacity(0.00), location: 0.62),
                    .init(color: Color.black.opacity(isDark ? 0.18 : 0.05), location: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .inset:
            // 上暗下亮 = 凹陷：顶部一道内阴影，底部一道微光
            return LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(isDark ? 0.28 : 0.10), location: 0.00),
                    .init(color: Color.black.opacity(isDark ? 0.10 : 0.03), location: 0.28),
                    .init(color: Color.white.opacity(0.00), location: 0.58),
                    .init(color: Color.white.opacity(isDark ? 0.13 : 0.32), location: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .lifted:
            // 上亮下沉 = 浮起
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(isDark ? 0.22 : 0.48), location: 0.00),
                    .init(color: Color.white.opacity(isDark ? 0.05 : 0.15), location: 0.42),
                    .init(color: Color.white.opacity(0.00), location: 0.66),
                    .init(color: Color.black.opacity(isDark ? 0.14 : 0.04), location: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            )
        case .pane:
            // 上亮下沉：同一份「受光凸起」的语义，但浅色下靠**逐段加深**而不是加白 ——
            // 加白在近白容器上没有余量，逐段加深才能在 249 的天花板下拿到约 17 级的纵向层次。
            return LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(isDark ? 0.14 : 0.30), location: 0.00),
                    .init(color: Color.white.opacity(isDark ? 0.02 : 0.04), location: 0.38),
                    .init(color: Color.black.opacity(0.00), location: 0.60),
                    .init(color: Color.black.opacity(isDark ? 0.16 : 0.05), location: 1.00)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    /// 激活单元格 —— 「玻璃局部被光照亮」，不是「按钮被选中后变成蓝色」。
    ///
    /// 旧实现铺的是 accentColor 0.95 → 0.58 的不透明渐变，那已经是不折不扣的**实心蓝色色板**，
    /// 读起来就是一块传统 macOS 蓝按钮，而不是被照亮的玻璃。现在整条语义从「染色」改为「受光」：
    ///
    /// - 材质：ice white / silver white，**不含任何 accent 填充**；
    /// - 结构：顶亮底暗，模拟顶光打在玻璃上，保留纵向层次与透光感；
    /// - 亮度：相对 idle 只提升约 8~12%（idle 深色为 white 0.11，此处 0.30 → 0.13）；
    /// - 冷色：作为「白里透一点冷」存在于 `iceWhite`，而不是掺进系统蓝。
    private var activeCellStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                stops: [
                    .init(color: iceWhite(isDark ? 0.30 : 0.48), location: 0.0),
                    .init(color: iceWhite(isDark ? 0.13 : 0.24), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// 允许出现在岛上的**唯一**蓝，且严格压在 0.08 以内。
    ///
    /// 它只落在被激活的那一格**内部**，不覆盖整个 layout item，也不参与描边 ——
    /// 从根本上避免回到「整块 layout item 变蓝」的旧观感。
    private var activeCoolTint: Color {
        Color.accentColor.opacity(isDark ? 0.08 : 0.05)
    }

    /// 分割线 —— 玻璃接缝。
    /// 凸起面（lifted / flat / pane）用暗线；凹陷面（inset）反过来用亮线，表示凹槽之间的凸起料。
    private var seamColor: Color {
        switch skin {
        case .flat:   return Color.black.opacity(isDark ? 0.26 : 0.12)
        case .inset:  return Color.white.opacity(isDark ? 0.13 : 0.55)
        case .lifted: return Color.black.opacity(isDark ? 0.20 : 0.10)
        case .pane:   return Color.black.opacity(isDark ? 0.26 : 0.14)
        }
    }

    /// 唯一外框。
    ///
    /// 早期版本用「上亮下黑」的渐变棱边：深色下实测左右两侧中段只剩 white 0.075（≈不可见），
    /// 底边 73 与容器 67 几乎重合 —— 图元实际只剩一条亮顶边，读不成一块完整的屏幕。
    /// 现在每种 skin 都保证能闭合，只是明暗语义不同。
    private var rimStyle: AnyShapeStyle {
        switch skin {
        case .flat:
            return AnyShapeStyle(Color.white.opacity(isDark ? 0.22 : 0.55))
        case .inset:
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(isDark ? 0.32 : 0.12), location: 0.00),
                        .init(color: Color.black.opacity(0.00), location: 0.35),
                        .init(color: Color.white.opacity(isDark ? 0.15 : 0.62), location: 1.00)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        case .lifted:
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isDark ? 0.34 : 0.90), location: 0.00),
                        .init(color: Color.white.opacity(isDark ? 0.10 : 0.38), location: 0.50),
                        .init(color: Color.white.opacity(isDark ? 0.05 : 0.26), location: 1.00)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        case .pane:
            // 顶边接光 / 中段中性 / 底边落影 —— 用一条边就闭合整块玻璃，
            // 而不是一圈均匀描边（均匀描边正是「描边小卡片」的来源）。
            // 浅色下中段取 black，让侧边比填充再暗约 14 级，图元轮廓才立得住。
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(isDark ? 0.24 : 0.85), location: 0.00),
                        .init(color: Color.black.opacity(isDark ? 0.05 : 0.06), location: 0.55),
                        .init(color: Color.black.opacity(isDark ? 0.16 : 0.10), location: 1.00)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
    }

    var body: some View {
        ZStack {
            // 激活区 bloom 铺在网格**之下**：目标格本身不透明，
            // 柔光因此只会从它边缘漏进相邻的透光格子里，形成「玻璃内部发光」的观感。
            if let rect = activeRegionRect {
                // 受光柔光 —— 冷白，不是 accent 蓝。
                // 原先这里是 accentColor 0.50 加 blur(5)，那正是「obvious blue glow」。
                // 现在改为极弱的冷白：光只从目标格边缘漏进相邻的透光格子，
                // 读作「玻璃内部被照亮」，而不是一圈蓝色光晕。
                RoundedRectangle(cornerRadius: SnapIslandGeometry.glyphCornerRadius, style: .continuous)
                    .fill(iceWhite(isDark ? 0.14 : 0.30))
                    .frame(width: rect.width, height: rect.height)
                    .blur(radius: 5)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            // 网格与整块光泽一起被屏幕形状裁切 —— 光泽跨格连续，不在缝上重启
            ZStack {
                grid
                glassSheen
            }
            .clipShape(screenShape)

            screenShape.strokeBorder(rimStyle, lineWidth: outlineWidth)
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 0.16), value: hoveredSlot)
    }

    // MARK: Grid

    private var grid: some View {
        let columnWidths = resolvedColumnWidths
        let rowHeights = resolvedRowHeights

        return VStack(spacing: 0) {
            ForEach(spec.rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(spec.rows[rowIndex].indices, id: \.self) { columnIndex in
                        let region = spec.rows[rowIndex][columnIndex]

                        Rectangle()
                            .fill(regionStyle(for: region))
                            // 唯一的蓝：只落在目标分区**内部**，且不超过 0.08。
                            // 不覆盖整个 layout item，也不形成描边。
                            .overlay(
                                Group {
                                    if region.slot == hoveredSlot {
                                        Rectangle().fill(activeCoolTint)
                                    }
                                }
                            )
                            .frame(width: columnWidths[columnIndex], height: rowHeights[rowIndex])

                        // 列间分割线：紧贴两侧填充，不是缝隙
                        if columnIndex < spec.rows[rowIndex].count - 1 {
                            Rectangle()
                                .fill(seamColor)
                                .frame(width: dividerWidth, height: rowHeights[rowIndex])
                        }
                    }
                }

                // 行间分割线
                if rowIndex < spec.rows.count - 1 {
                    Rectangle()
                        .fill(seamColor)
                        .frame(height: dividerWidth)
                }
            }
        }
    }

    private func regionStyle(for region: LayoutGlyphSpec.Region) -> AnyShapeStyle {
        region.slot == hoveredSlot ? activeCellStyle : idleCellStyle
    }

    /// 激活格在 glyph 内的矩形。
    ///
    /// 与 `grid` 复用同一套 `resolvedColumnWidths` / `resolvedRowHeights` / `dividerWidth`，
    /// 因此 bloom 的位置永远与真正被点亮的格子严格重合。
    private var activeRegionRect: CGRect? {
        guard let slot = hoveredSlot else { return nil }

        let columnWidths = resolvedColumnWidths
        let rowHeights = resolvedRowHeights

        var y: CGFloat = 0
        for rowIndex in spec.rows.indices {
            var x: CGFloat = 0
            for columnIndex in spec.rows[rowIndex].indices {
                let width = columnWidths[columnIndex]
                if spec.rows[rowIndex][columnIndex].slot == slot {
                    return CGRect(x: x, y: y, width: width, height: rowHeights[rowIndex])
                }
                x += width + dividerWidth
            }
            y += rowHeights[rowIndex] + dividerWidth
        }
        return nil
    }

    private var resolvedColumnWidths: [CGFloat] {
        distribute(
            total: size.width,
            weights: spec.columnWeights,
            dividerCount: max(0, spec.columnWeights.count - 1)
        )
    }

    private var resolvedRowHeights: [CGFloat] {
        distribute(
            total: size.height,
            weights: spec.rowWeights,
            dividerCount: max(0, spec.rowWeights.count - 1)
        )
    }

    /// 扣掉分割线占位后按权重分配剩余空间
    private func distribute(total: CGFloat, weights: [CGFloat], dividerCount: Int) -> [CGFloat] {
        let weightSum = weights.reduce(0, +)
        guard !weights.isEmpty, weightSum > 0 else {
            return Array(repeating: 0, count: weights.count)
        }
        let available = total - dividerWidth * CGFloat(dividerCount)
        return weights.map { available * ($0 / weightSum) }
    }
}

// MARK: - Layout Item (悬浮岛中的一个布局条目)

/// 悬浮岛中的一个布局条目：**只有一个玻璃图元**。
///
/// 状态层**完全没有底色**：
/// - 被点亮的是图元内部的**落点格**（由 `LayoutGlyphView` 负责），不是整个条目；
/// - 条目本身不设背景、不设描边、不设阴影、不做缩放 ——
///   这四者会让条目在一级 Surface 之上重新长成一张独立卡片。
///
/// 原本图元下方还有一行 11.5pt 文案（idle 显示布局名、hover 显示落点名）。
/// 已移除：图元本身已足够表意，文案反而把条目重心从「图元」拉走，
/// 并占掉图元本可用于放大的垂直空间。移掉后图元在条目内垂直居中。
///
/// 条目宽度明显大于图元宽度，两者之差就是「命中区可以大、但视觉上不画出来」的余量。
/// 命中区与视觉如何解耦（真实机制）：
/// 悬浮岛的 `NSPanel.ignoresMouseEvents` 恒为 true，命中不由 SwiftUI 决定，
/// 而是由 `WindowSnapIslandPanel.slot(at:)` 拿光标位置去查 `SnapIslandGeometry.cardRects`。
/// 条目矩形宽 140pt、图元只画 106~112pt 宽，两者之差就是「可以命中、但不画出来」的余量。
private struct LayoutItemView: View {
    let card: SnapIslandGeometry.Card
    let spec: LayoutGlyphSpec
    let hoveredSlot: SnapSlot?
    let width: CGFloat

    var body: some View {
        // 外层 frame 就是命中区的形状（宽 = 条目宽，高 = cardHeight），
        // 图元在其中居中 —— 视觉尺寸与命中尺寸由此彻底解耦。
        LayoutGlyphView(card: card, spec: spec, hoveredSlot: hoveredSlot)
            .frame(width: width, height: SnapIslandGeometry.cardHeight)
    }
}

// MARK: - Island Content View (单一 Liquid Glass Vessel)

/// 分屏岛内容视图。
///
/// 层级刻意收敛到**两层**：
/// ```
/// 第一层  Liquid Glass Vessel  ← 全岛唯一的 Surface（一层玻璃 + 一层极薄自适应纱）
/// 第二层  Layout Glyph         ← 每个条目一个玻璃图元（自带外棱与内部接缝）
/// ```
/// 中间那一层「独立圆角 Card」（旧版的 hover 蓝底）与条目之间的竖向 Divider 均已删除，
/// 四个条目的关系完全由 `interItemSpacing` 的留白建立。
public struct WindowSnapIslandContentView: View {
    @ObservedObject public var viewModel = WindowSnapIslandViewModel.shared
    @Environment(\.colorScheme) var colorScheme

    public init() {}

    public var body: some View {
        HStack(spacing: SnapIslandGeometry.interItemSpacing) {
            // 宽度、间距、内边距全部取自 SnapIslandGeometry ——
            // UI 与 slot(at:) 命中测试共用同一份几何，此处调整即自动同步命中区。
            LayoutItemView(
                card: .halfSplit, spec: .halfSplit,
                hoveredSlot: viewModel.hoveredSlot,
                width: SnapIslandGeometry.Card.halfSplit.width
            )

            LayoutItemView(
                card: .mainSide, spec: .mainSide,
                hoveredSlot: viewModel.hoveredSlot,
                width: SnapIslandGeometry.Card.mainSide.width
            )

            LayoutItemView(
                card: .quarter, spec: .quarter,
                hoveredSlot: viewModel.hoveredSlot,
                width: SnapIslandGeometry.Card.quarter.width
            )

            LayoutItemView(
                card: .thirds, spec: .thirds,
                hoveredSlot: viewModel.hoveredSlot,
                width: SnapIslandGeometry.Card.thirds.width
            )
        }
        .padding(.horizontal, SnapIslandGeometry.horizontalPadding)
        .padding(.vertical, SnapIslandGeometry.verticalPadding)
        .frame(width: SnapIslandGeometry.panelSize.width, height: SnapIslandGeometry.panelSize.height)
        // 第一层：唯一的一级 Surface。
        // 纱层压到 0.20 / 0.10 —— 岛上已无任何文案，纱层只用于压住极端底图上的脏色，
        // 壁纸必须能明显透过玻璃被感知，不再有传统灰色遮罩。
        .background(
            ZStack {
                NativeLiquidGlassView(
                    cornerRadius: SnapIslandGeometry.cornerRadius,
                    style: .regular
                )
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.20 : 0.10)
            }
            .clipShape(RoundedRectangle(cornerRadius: SnapIslandGeometry.cornerRadius, style: .continuous))
        )
        // rimIntensity 0.0：深色主题下不再出现抢眼的外圈浅色描边（见上一轮修复）
        .overlay(
            LiquidGlassEdgeOverlay(cornerRadius: SnapIslandGeometry.cornerRadius, rimIntensity: 0.0)
        )
        // Atmospheric Elevation Shadow —— 已整个移除，与划词工具栏同因同治
        // （成因详见 ToolbarPanel.swift 同一位置的注释）。
        //
        // 原在此叠了两层 .shadow，而它们挂在上方 .frame(width:height:) 的**矩形**栈上，
        // 栈内含 NativeLiquidGlassView（NSViewRepresentable）。SwiftUI 取不到 AppKit 视图的
        // 真实 alpha 轮廓来求投影，于是退化为用视图 bounds（矩形）来投 ——
        // 一圈方角暗影套在圆角玻璃外面。
        //
        // 分屏岛比划词栏更刺眼，因为：尺寸大、圆角大，方角错位更明显；
        // 且 rimIntensity 归零后岛上已无任何边缘轮廓，
        // 唯一还在「定义形状」的就只剩这圈方角投影，与本该圆角的玻璃直接打架。
        //
        // 注意：调小 radius 只会减弱方角、不会消除 —— 只要 shadow 还在含 representable
        // 的矩形栈上，方角就一直在，因此必须整体移除。
        .scaleEffect(viewModel.isAppearing ? 1.0 : 0.96)
        .opacity(viewModel.isAppearing ? 1.0 : 0.0)
    }
}

// MARK: - Window Snap Island Floating Panel
public class WindowSnapIslandPanel: NSPanel {
    private static let storage = WindowSnapIslandPanel()
    private static var hasMaterialized = false

    /// 面板是否已被实体化。**不会触发创建** —— 用于在不付出构造代价的前提下短路判断。
    public static var isMaterialized: Bool { hasMaterialized }

    public static var shared: WindowSnapIslandPanel {
        hasMaterialized = true
        return storage
    }

    /// 若面板已实体化则返回实例，否则返回 nil，绝不触发构造
    public static var safeShared: WindowSnapIslandPanel? {
        isMaterialized ? storage : nil
    }

    public let viewModel = WindowSnapIslandViewModel.shared
    private var currentActiveScreen: NSScreen?
    private var animationToken: Int = 0

    // 舒展大气的大尺寸规格（620 x 88pt），大幅提升拖窗视觉舒适度与命中率。
    // 尺寸真源已收敛到 SnapIslandGeometry，此处保留别名以兼容既有调用方与测试。
    public static let panelWidth: CGFloat = SnapIslandGeometry.panelSize.width
    public static let panelHeight: CGFloat = SnapIslandGeometry.panelSize.height

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.becomesKeyOnlyIfNeeded = false
        self.alphaValue = 0.0
        self.ignoresMouseEvents = true
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.canHide = false

        let hostingView = FirstMouseHostingView(rootView: WindowSnapIslandContentView())
        self.contentView = hostingView
    }

    public func show(on screen: NSScreen) {
        animationToken += 1
        let isSameScreen = (currentActiveScreen?.frame == screen.frame)
        self.currentActiveScreen = screen

        let targetX = round(screen.frame.midX - (Self.panelWidth / 2.0))
        let targetY = max(screen.visibleFrame.maxY - Self.panelHeight - 6, screen.frame.maxY - Self.panelHeight - 8)
        let targetRect = NSRect(x: targetX, y: targetY, width: Self.panelWidth, height: Self.panelHeight)

        if self.isVisible && isSameScreen {
            self.alphaValue = 1.0
            self.viewModel.isAppearing = true
            return
        }

        let startRect = NSRect(x: targetX, y: targetY + 14, width: Self.panelWidth, height: Self.panelHeight)
        self.setFrame(startRect, display: false)
        self.alphaValue = 0.0
        self.orderFrontRegardless()

        viewModel.isAppearing = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            self.viewModel.isAppearing = true
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().setFrame(targetRect, display: true)
            self.animator().alphaValue = 1.0
        }
    }

    public func hide() {
        guard self.isVisible else { return }
        viewModel.hoveredSlot = nil

        animationToken += 1
        let token = animationToken

        withAnimation(.easeOut(duration: 0.14)) {
            self.viewModel.isAppearing = false
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            if self.animationToken == token {
                self.orderOut(nil)
            }
        })
    }

    /// 智能解析鼠标在分屏岛卡片内的自适应落点（**严格卡片内部感应**）
    ///
    /// 判定链：
    /// 1. 面板可见；
    /// 2. 光标落在面板矩形内；
    /// 3. **光标严格落在某张卡片的矩形内**（`CGRect.contains`）；
    /// 4. 按卡片内相对位置解析具体落点。
    ///
    /// 卡片之间的分隔线 / 间距、面板四周内边距**一律返回 `nil`**，
    /// 绝不被"就近吸附"到相邻卡片 —— 视觉上不是卡片的地方，就不会触发分屏。
    ///
    /// 所有尺寸来自 `SnapIslandGeometry`，此处不含任何魔法数字。
    public func slot(at screenPoint: NSPoint) -> SnapSlot? {
        guard self.isVisible else { return nil }

        // 面板本地坐标（原点左下角，与 SnapIslandGeometry 坐标系一致）
        let local = NSPoint(
            x: screenPoint.x - self.frame.minX,
            y: screenPoint.y - self.frame.minY
        )

        // 外层包络：光标必须落在分屏岛面板内部
        let bounds = CGRect(origin: .zero, size: SnapIslandGeometry.panelSize)
        guard bounds.contains(local) else { return nil }

        // 严格卡片内命中：逐张卡片做矩形判定，未命中任何卡片即视为落在缝隙 / 内边距上
        for card in SnapIslandGeometry.Card.allCases {
            let rect = SnapIslandGeometry.rect(for: card)
            guard rect.contains(local) else { continue }

            let ratio = (local.x - rect.minX) / rect.width

            switch card {
            case .halfSplit:
                // 二分屏：左 1/2 vs 右 1/2
                return ratio <= SnapIslandGeometry.halfSplitRatio ? .leftHalf : .rightHalf

            case .mainSide:
                // 主辅 2:1：左主 2/3 vs 右辅 1/3
                return ratio <= SnapIslandGeometry.mainSideSplitRatio ? .mainWorkspace : .sideWorkspace

            case .quarter:
                // 四等分：田字格 2x2，纵向以图元垂直中线分界
                let isLeft = ratio <= SnapIslandGeometry.quarterSplitRatio
                let isTop = local.y >= SnapIslandGeometry.quarterGlyphCenterY
                if isTop {
                    return isLeft ? .topLeftQuarter : .topRightQuarter
                } else {
                    return isLeft ? .bottomLeftQuarter : .bottomRightQuarter
                }

            case .thirds:
                // 标准三等分：左 1/3 / 中 1/3 / 右 1/3
                if ratio <= 1.0 / 3.0 {
                    return .leftThird
                } else if ratio <= 2.0 / 3.0 {
                    return .centerThird
                } else {
                    return .rightThird
                }
            }
        }

        // 落在卡片之间的分隔线、间距或面板内边距上 —— 明确不吸附
        return nil
    }

    public func setHoveredSlot(_ slot: SnapSlot?) {
        if viewModel.hoveredSlot != slot {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                viewModel.hoveredSlot = slot
            }
        }
    }
}

// MARK: - Ghost Preview Content View (纯净原生 Liquid Glass 高光落点面板)
public struct GhostPreviewContentView: View {
    public let slot: SnapSlot
    @Environment(\.colorScheme) var colorScheme

    public init(slot: SnapSlot) {
        self.slot = slot
    }

    public var body: some View {
        ZStack {
            // 落点底色 —— 冷白玻璃微光，不再是 accent 蓝。
            //
            // 旧实现铺的是 accent 0.16 → 0.08 的蓝色渐变，再叠上后面的蓝棱与蓝投影，
            // 整体读起来就是「一块蓝色按钮」。现在改为「目标分区被光照亮」：
            // 以冷白提亮为主，蓝只作为极弱冷调存在（见下方 overlay），严格 ≤ 0.08。
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            iceWhite(colorScheme == .dark ? 0.15 : 0.22),
                            iceWhite(colorScheme == .dark ? 0.05 : 0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    // 落点内部允许存在的唯一蓝，且压在 0.08 以内 ——
                    // 只铺在分区内部、不参与描边，因此不会形成「蓝色边框」。
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.05))
                )

            // 高对比度光学外轮廓边（替代全屏离屏高斯模糊投影，彻底消除全屏 Offscreen Gaussian Blur Pass 开销）
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.85 : 0.95), location: 0.0),
                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.45 : 0.55), location: 0.35),
                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.20 : 0.30), location: 0.75),
                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.40 : 0.50), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )

            // 内层微透反射边（微光渐变，强化双层光学边界与景深感）
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.30),
                            Color.white.opacity(colorScheme == .dark ? 0.06 : 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
                .padding(1)
        }
        .padding(2)
    }
}

// MARK: - Ghost Preview Floating Overlay Panel
public class GhostPreviewPanel: NSPanel {
    private static let storage = GhostPreviewPanel()
    private static var hasMaterialized = false

    /// 面板是否已被实体化。**不会触发创建** —— 用于在不付出构造代价的前提下短路判断。
    public static var isMaterialized: Bool { hasMaterialized }

    public static var shared: GhostPreviewPanel {
        hasMaterialized = true
        return storage
    }

    /// 若面板已实体化则返回实例，否则返回 nil，绝不触发构造
    public static var safeShared: GhostPreviewPanel? {
        isMaterialized ? storage : nil
    }

    private var currentSlot: SnapSlot? = nil
    private var animationToken: Int = 0
    private let hostingView: FirstMouseHostingView<AnyView>

    private init() {
        let initialView = AnyView(EmptyView())
        self.hostingView = FirstMouseHostingView(rootView: initialView)

        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.becomesKeyOnlyIfNeeded = false
        self.alphaValue = 0.0
        self.ignoresMouseEvents = true
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.canHide = false
        self.contentView = hostingView
    }

    public func show(targetRect: NSRect, slot: SnapSlot, on screen: NSScreen) {
        animationToken += 1
        let insetRect = targetRect

        if currentSlot != slot {
            currentSlot = slot
            hostingView.rootView = AnyView(GhostPreviewContentView(slot: slot))
        }

        if !self.isVisible || self.alphaValue < 0.1 {
            self.setFrame(insetRect, display: true)
            self.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                self.animator().alphaValue = 1.0
            }
            let token = animationToken
            let fallback = Timer(timeInterval: 0.20, repeats: false) { [weak self] _ in
                guard let self, self.animationToken == token else { return }
                self.alphaValue = 1.0
            }
            RunLoop.main.add(fallback, forMode: .common)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                self.animator().setFrame(insetRect, display: true)
                self.animator().alphaValue = 1.0
            }
        }
    }

    public func hide() {
        guard self.isVisible else {
            if self.frame != .zero {
                self.setFrame(.zero, display: false)
                self.hostingView.rootView = AnyView(EmptyView())
                self.currentSlot = nil
            }
            return
        }
        currentSlot = nil

        animationToken += 1
        let token = animationToken

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.finishHide(token: token)
        })

        // AppKit animation completion can be skipped in a headless/test run loop. Keep the
        // WindowServer framebuffer reclamation deterministic even when that callback is lost.
        let fallback = Timer(timeInterval: 0.20, repeats: false) { [weak self] _ in
            self?.finishHide(token: token)
        }
        RunLoop.main.add(fallback, forMode: .common)
    }

    private func finishHide(token: Int) {
        guard animationToken == token else { return }
        orderOut(nil)
        setFrame(.zero, display: false)
        hostingView.rootView = AnyView(EmptyView())
    }
}
