import CoreGraphics
import Foundation

/// Which way the body is looking. The atlas carries a row for each, and nothing outside the sprite
/// needs to know about it: the wander walks a perimeter, which has no left or right in it.
enum DeloresCompanionFacing: Equatable, Sendable {
    case left, right
}

/// Which row of the atlas the body is drawn from, and how fast that row changes.
///
/// Pure, so the mapping can be asserted without a window. This is the whole of the animation policy —
/// everything downstream writes one CGRect into one layer — which is why the two rulings it carries
/// live here rather than in the panel that obeys them.
enum DeloresCompanionAnimation {
    /// One breath: two frames, each held for half of this. The period of a Core Animation keyframe
    /// animation, not a timer interval — see the sprite plan's first ruling.
    static let breathDuration: TimeInterval = 2.0

    /// How often the drawn pose changes while walking. An amble, not a march: half the cadence a
    /// walk animation usually runs at, because the body strolls and quicker feet read as scurrying.
    static let walkFrame: TimeInterval = 1.0 / 6.0

    /// How often the body is *moved* while walking.
    ///
    /// Ruling 2, rewritten. The pose and the position used to share one clock, which made the walk a
    /// staircase — the body was elsewhere for a sixth of a second and then it was here. Three
    /// position ticks to one pose now, and at the speeds it ambles at that is about one point per
    /// tick: the distance pixel art wants to travel, since a slower tick jumps far enough to read as
    /// a slide and a faster one spends most of its frames standing still.
    static let walkStep: TimeInterval = 1.0 / 18.0

    /// One loop of a reaction. Played twice and then left, at a rate a pixel reads as deliberate.
    static let reactionDuration: TimeInterval = 0.24

    /// Duration for lazy loitering / daze behaviors (yawn, stretch, flop).
    static let dazeDuration: TimeInterval = 1.6

    /// Duration for acrobatic hops or rolling maneuvers.
    static let acrobaticsDuration: TimeInterval = 0.8

    /// Cells in a walk cycle. Both walk rows are the same length, because one is the other mirrored.
    static var walkFrameCount: Int { CompanionAtlas.Row.walkLeft.frameCount }

    /// Which row a pose is on.
    ///
    /// Everything that is not a trip is idle: a body holding a shell, one the reader has captured, and
    /// one being dragged all stand still, and none of them has a wander state to read.
    static func row(isStrolling: Bool, isHeld: Bool, facing: DeloresCompanionFacing) -> CompanionAtlas.Row {
        guard isStrolling, !isHeld else { return .idle }
        return facing == .left ? .walkLeft : .walkRight
    }

    /// Which way the body turned between two steps (ruling 3).
    ///
    /// The wander walks the display's perimeter, so a step along a vertical edge has no horizontal
    /// component at all, and a body there must not flip sides every frame. `fallback` is the facing it
    /// already had, and it is what a purely vertical step keeps.
    static func facing(
        from previous: CGPoint, to current: CGPoint, fallback: DeloresCompanionFacing
    ) -> DeloresCompanionFacing {
        let dx = current.x - previous.x
        if dx > 0 { return .right }
        if dx < 0 { return .left }
        return fallback
    }

    /// The atlas rectangle for one frame, in `contentsRect`'s 0–1 space.
    ///
    /// Core Animation measures y from the bottom and the sheet is authored from the top, so the row is
    /// flipped once here — this is the only place that knows either fact.
    static func contentsRect(row: CompanionAtlas.Row, frame: Int) -> CGRect {
        let width = 1 / CGFloat(CompanionAtlas.columns)
        let height = 1 / CGFloat(CompanionAtlas.rows)
        let y = 1 - (CGFloat(row.rawValue) + 1) * height
        return CGRect(x: CGFloat(frame) * width, y: y, width: width, height: height)
    }
}
