import CoreGraphics
import Foundation

@main
@MainActor
struct DeloresGeometryTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(abs(actual - expected) < 0.01, "\(message) — got \(actual), want \(expected)")
    }

    static func main() {
        snapGeometry()
        dividerGeometry()

        print("\n\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func snapGeometry() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let arrangedScreen = CGRect(x: 1440, y: -20, width: 1728, height: 1117)
        let arrangedVisibleFrame = CGRect(x: 1440, y: 0, width: 1728, height: 1045)
        let trigger = DeloresSnapTriggerGeometry.revealFrame(
            screenFrame: arrangedScreen, visibleFrame: arrangedVisibleFrame)
        let topBand = DeloresSnapTriggerGeometry.topEdgeBand(
            screenFrame: arrangedScreen, visibleFrame: arrangedVisibleFrame)
        let narrowScreen = CGRect(x: -420, y: 0, width: 420, height: 800)
        let narrowTrigger = DeloresSnapTriggerGeometry.revealFrame(
            screenFrame: narrowScreen, visibleFrame: narrowScreen)
        let gap: CGFloat = 16
        let left = DeloresSnapSlot.left.rect(in: screen, gap: gap)
        let right = DeloresSnapSlot.right.rect(in: screen, gap: gap)
        let main = DeloresSnapSlot.mainWorkspace.rect(in: screen, gap: gap)
        let side = DeloresSnapSlot.sideWorkspace.rect(in: screen, gap: gap)
        let topLeft = DeloresSnapSlot.topLeft.rect(in: screen, gap: gap)
        let bottomLeft = DeloresSnapSlot.bottomLeft.rect(in: screen, gap: gap)

        expect(trigger.width, 560, "snap reveal zone is narrower than the previous hot zone")
        expect(trigger.height, 140, "reveal zone includes the menu bar and 88pt of usable display")
        expect(trigger.midX, arrangedScreen.midX, "snap reveal zone stays centered on each display")
        expect(narrowTrigger.width, narrowScreen.width, "reveal zone fits a narrow display")
        expect(trigger.minY, arrangedVisibleFrame.maxY - 88, "reveal zone ends 88pt into the display")
        expect(trigger.maxY, arrangedScreen.maxY, "reveal zone stops at the physical display top")
        expect(
            trigger.contains(CGPoint(x: trigger.midX, y: trigger.minY + 1)),
            "the centered reveal zone includes its lower interior")
        expect(
            !trigger.contains(CGPoint(x: trigger.minX - 1, y: trigger.midY)),
            "the reveal zone rejects drags outside its horizontal range")
        expect(
            !topBand.contains(CGPoint(x: arrangedScreen.midX, y: trigger.minY - 1)),
            "the top band rejects drags below its reduced depth")
        expect(
            topBand.contains(CGPoint(x: arrangedScreen.minX + 1, y: trigger.midY)),
            "the active top band spans the display after the island opens")

        expect(DeloresSnapSlot.left.isLeftOfSeam, "左半槽位应是 Divider 的左侧")
        expect(!DeloresSnapSlot.right.isLeftOfSeam, "右半槽位不应被判为 Divider 左侧")
        expect(left.maxX + gap, right.minX, "half slots preserve the configured seam gap")
        expect(main.maxX + gap, side.minX, "workspace slots preserve the configured seam gap")
        expect(main.width > side.width, "main workspace remains wider than the side workspace")
        expect(topLeft.maxY, screen.maxY - gap, "top-left slot stays inside the top edge")
        expect(bottomLeft.minY, screen.minY + gap, "bottom-left slot stays inside the bottom edge")
        expect(topLeft.minY - gap, bottomLeft.maxY, "stacked slots preserve the configured row gap")

        print(
            "MEASURE snap.left x=\(left.minX) y=\(left.minY) "
                + "w=\(left.width) h=\(left.height) gap=\(right.minX - left.maxX)")
        print(
            "MEASURE snap.workspace ratio=\(main.width / side.width) "
                + "seam=\(side.minX - main.maxX)")
    }

    static func dividerGeometry() {
        let left = CGRect(x: 0, y: 100, width: 600, height: 700)
        let right = CGRect(x: 612, y: 100, width: 600, height: 700)
        let seam = DeloresDividerGeometry.seam(
            left: left,
            right: right,
            gapTolerance: 12,
            minimumHeight: DeloresDividerGeometry.minimumPairHeight)

        guard let seam else {
            expect(false, "touching windows form a divider seam")
            return
        }
        expect(seam.dividerX, 606, "divider is centered in the window gap")
        expect(seam.y, 100, "divider starts at the shared top edge")
        expect(seam.height, 700, "divider spans the shared window height")
        expect(
            DeloresDividerGeometry.isNear(
                CGPoint(x: seam.dividerX, y: seam.y + seam.height / 2),
                seam: seam,
                tolerance: 50),
            "pointer on the seam activates the divider")
        expect(
            DeloresDividerGeometry.seam(
                left: left,
                right: right.offsetBy(dx: 13, dy: 0),
                gapTolerance: 12) == nil,
            "a gap beyond tolerance is not treated as a divider")
        expect(
            DeloresDividerGeometry.seam(
                left: left,
                right: CGRect(x: 612, y: 750, width: 600, height: 700),
                gapTolerance: 12) == nil,
            "insufficient vertical overlap is not treated as a divider")

        let reset = DeloresDividerGeometry.reset(
            DeloresDividerGeometry.Seam(
                left: CGRect(x: 0, y: 100, width: 400, height: 700),
                right: CGRect(x: 412, y: 100, width: 800, height: 700)))
        expect(reset.left.width, 600, "reset returns the left window to half the pair width")
        expect(reset.right.width, 600, "reset returns the right window to half the pair width")

        let dragged = DeloresDividerGeometry.dragged(seam, deltaX: 500)
        expect(dragged?.left.width ?? 0, 950, "drag clamps the left window at the minimum right width")
        expect(dragged?.right.width ?? 0, 250, "drag clamps the right window at its minimum width")
        expect(dragged?.right.minX ?? 0, 962, "drag preserves the seam gap while moving the divider")
        expect(
            DeloresDividerGeometry.ratio(leftWidth: dragged?.left.width ?? 0, total: 1200)?.left == 79,
            "divider ratio rounds to whole percentages")

        print(
            "MEASURE divider x=\(seam.dividerX) y=\(seam.y) h=\(seam.height) "
                + "gap=\(seam.right.minX - seam.left.maxX)")
        if let dragged {
            print(
                "MEASURE divider.drag left=\(dragged.left.width) right=\(dragged.right.width) "
                    + "ratio=\(Int((dragged.left.width / 1200 * 100).rounded())):"
                    + "\(Int((dragged.right.width / 1200 * 100).rounded()))")
        }
    }
}
