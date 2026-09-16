import CoreGraphics

enum DeloresContextIslandPlacement {
    static func frame(
        in screen: InvocationScreen,
        size: CGSize,
        margin: CGFloat = 10
    ) -> CGRect {
        let screenFrame = screen.frame
        let minX = screenFrame.minX + margin
        let maxX = max(minX, screenFrame.maxX - size.width - margin)
        let usesNotchAnchor = screen.auxiliaryTopRightArea?.width ?? 0 > 0
        let preferredX = usesNotchAnchor
            ? screen.auxiliaryTopRightArea!.minX + margin
            : screenFrame.midX - size.width / 2
        let x = min(max(preferredX, minX), maxX)

        let menuBarHeight = max(0, screen.menuBarFrame.height)
        let preferredY: CGFloat
        if menuBarHeight > 0 {
            preferredY = screen.menuBarFrame.minY + (menuBarHeight - size.height) / 2
        } else {
            preferredY = screenFrame.maxY - size.height
        }
        let minY = screenFrame.minY
        let maxY = max(minY, screenFrame.maxY - size.height)
        let y = min(max(preferredY, minY), maxY)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
