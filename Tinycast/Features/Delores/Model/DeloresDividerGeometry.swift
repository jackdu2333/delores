import CoreGraphics

/// Spatial Divider coordinator 与回归测量共用的纯几何模型。
enum DeloresDividerGeometry {
    static let defaultPairGap: CGFloat = 12
    static let minimumPairHeight: CGFloat = 120
    static let minimumOverlapRatio: CGFloat = 0.7
    static let minimumWindowWidth: CGFloat = 250

    struct Seam: Equatable, Sendable {
        let left: CGRect
        let right: CGRect

        var dividerX: CGFloat { (left.maxX + right.minX) / 2 }
        var y: CGFloat { max(left.minY, right.minY) }
        var height: CGFloat { max(0, min(left.maxY, right.maxY) - y) }
    }

    static func seam(
        left: CGRect,
        right: CGRect,
        gapTolerance: CGFloat,
        minimumHeight: CGFloat = 0,
        minimumOverlapRatio: CGFloat = Self.minimumOverlapRatio
    ) -> Seam? {
        let ordered = left.minX <= right.minX ? (left, right) : (right, left)
        let candidate = Seam(left: ordered.0, right: ordered.1)
        let gap = abs(candidate.right.minX - candidate.left.maxX)
        let shortestHeight = min(candidate.left.height, candidate.right.height)
        guard gap <= gapTolerance,
            shortestHeight > 0,
            candidate.height / shortestHeight >= minimumOverlapRatio,
            candidate.height >= minimumHeight
        else { return nil }
        return candidate
    }

    static func isNear(_ point: CGPoint, seam: Seam, tolerance: CGFloat) -> Bool {
        abs(point.x - seam.dividerX) <= tolerance
            && point.y >= seam.y && point.y <= seam.y + seam.height
    }

    static func ratio(leftWidth: CGFloat, total: CGFloat) -> (left: Int, right: Int)? {
        guard total > 0 else { return nil }
        let left = Int((leftWidth / total * 100).rounded())
        return (left, 100 - left)
    }

    static func reset(_ seam: Seam) -> Seam {
        let total = seam.left.width + seam.right.width
        let half = total / 2
        return Seam(
            left: CGRect(
                x: seam.left.minX, y: seam.left.minY, width: half, height: seam.left.height),
            right: CGRect(
                x: seam.left.minX + half, y: seam.right.minY,
                width: total - half, height: seam.right.height))
    }

    static func dragged(_ seam: Seam, deltaX: CGFloat, minimumWidth: CGFloat = minimumWindowWidth) -> Seam? {
        let total = seam.left.width + seam.right.width
        guard total >= minimumWidth * 2 else { return nil }
        let leftWidth = min(max(seam.left.width + deltaX, minimumWidth), total - minimumWidth)
        let delta = leftWidth - seam.left.width
        return Seam(
            left: CGRect(
                x: seam.left.minX, y: seam.left.minY,
                width: leftWidth, height: seam.left.height),
            right: CGRect(
                x: seam.right.minX + delta, y: seam.right.minY,
                width: total - leftWidth, height: seam.right.height))
    }
}
