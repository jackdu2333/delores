import CoreGraphics

/// Spatial Snap 瞬时展示的槽位；这是能力几何，不是一个产品 Surface。
enum DeloresSnapSlot: Sendable {
    case left, right, mainWorkspace, sideWorkspace
    case leftThird, centerThird, rightThird
    case topLeft, topRight, bottomLeft, bottomRight

    /// 判断它和邻接窗口共享 seam 的哪一侧，用于 Divider 配对。
    var isLeftOfSeam: Bool {
        switch self {
        case .left, .mainWorkspace, .leftThird: return true
        case .right, .sideWorkspace, .rightThird: return false
        case .centerThird, .topLeft, .topRight, .bottomLeft, .bottomRight: return false
        }
    }

    /// 返回槽位占用的圆角矩形，并包含用户配置的外边距。
    func rect(in frame: CGRect, gap: CGFloat = 0) -> CGRect {
        let g = WindowPlacementEngine.sanitizedGap(gap, in: frame)
        let f = fractions
        let left = frame.minX + f.x0 * frame.width + (f.x0 == 0 ? g : g / 2)
        let right = frame.minX + f.x1 * frame.width - (f.x1 == 1 ? g : g / 2)
        let top = frame.maxY - (f.y0 * frame.height + (f.y0 == 0 ? g : g / 2))
        let bottom = frame.maxY - (f.y1 * frame.height - (f.y1 == 1 ? g : g / 2))
        return WindowPlacementEngine.rounded(
            CGRect(x: left, y: bottom, width: max(1, right - left), height: max(1, top - bottom)))
    }

    private var fractions: (x0: CGFloat, x1: CGFloat, y0: CGFloat, y1: CGFloat) {
        let oneThird: CGFloat = 1.0 / 3.0
        let twoThirds: CGFloat = 2.0 / 3.0
        switch self {
        case .left: return (0, 0.5, 0, 1)
        case .right: return (0.5, 1, 0, 1)
        case .mainWorkspace: return (0, twoThirds, 0, 1)
        case .sideWorkspace: return (twoThirds, 1, 0, 1)
        case .leftThird: return (0, oneThird, 0, 1)
        case .centerThird: return (oneThird, twoThirds, 0, 1)
        case .rightThird: return (twoThirds, 1, 0, 1)
        case .topLeft: return (0, 0.5, 0, 0.5)
        case .topRight: return (0.5, 1, 0, 0.5)
        case .bottomLeft: return (0, 0.5, 0.5, 1)
        case .bottomRight: return (0.5, 1, 0.5, 1)
        }
    }
}
