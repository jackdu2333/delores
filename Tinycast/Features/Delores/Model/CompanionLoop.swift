import CoreGraphics

/// The loop the body walks: one or more runs of straight line across a display, in screen coordinates.
///
/// The body moves inside a run and turns back at its ends. The gaps between runs are places it may not
/// go, which is what keeps it off the menu bar's icons and out of the notch; a detour is folded into a
/// run instead, so the Dock is walked around rather than cut out.
///
/// Pure and value-typed: what the display is, and where the things it walks around or avoids are,
/// arrive as arguments. None of the walk needs a screen to be asserted.
struct DeloresCompanionLoop: Equatable, Sendable {
    /// One run, walked in the order its points are given.
    struct Run: Equatable, Sendable {
        var points: [CGPoint]
        /// Distance from the first point to each point, so a position is a lookup rather than a walk.
        var offsets: [CGFloat]
        /// A closed run is walked round and round; an open one is walked back and forth.
        var isClosed: Bool

        var length: CGFloat { offsets.last ?? 0 }

        init(points: [CGPoint], isClosed: Bool = false) {
            self.points = points
            self.isClosed = isClosed
            var offsets: [CGFloat] = []
            var running: CGFloat = 0
            for (index, point) in points.enumerated() {
                if index > 0 {
                    let previous = points[index - 1]
                    running += hypot(point.x - previous.x, point.y - previous.y)
                }
                offsets.append(running)
            }
            self.offsets = offsets
        }
    }

    var runs: [Run]

    /// Whether there is anywhere at all to walk. A display too small to hold the body says so.
    var isEmpty: Bool { runs.allSatisfy { $0.length <= 0 } }

    /// The run at `index`, clamped: a body whose run disappeared with a screen change still has to
    /// stand somewhere.
    func run(at index: Int) -> Run {
        runs[min(max(index, 0), max(runs.count - 1, 0))]
    }
}

// MARK: - Reading a run

extension DeloresCompanionLoop {
    /// The point `distance` along a run.
    static func position(at distance: CGFloat, in run: Run) -> CGPoint {
        guard let first = run.points.first else { return .zero }
        guard run.points.count > 1, run.length > 0 else { return first }
        let clamped = min(max(distance, 0), run.length)
        for index in 1..<run.points.count where run.offsets[index] >= clamped {
            let start = run.points[index - 1]
            let end = run.points[index]
            let span = run.offsets[index] - run.offsets[index - 1]
            let along = span > 0 ? (clamped - run.offsets[index - 1]) / span : 0
            return CGPoint(
                x: start.x + (end.x - start.x) * along,
                y: start.y + (end.y - start.y) * along)
        }
        return run.points[run.points.count - 1]
    }

    /// How far along a run the point on it nearest to `point` sits.
    static func distance(of point: CGPoint, in run: Run) -> CGFloat {
        guard run.points.count > 1 else { return 0 }
        var bestDistance: CGFloat = 0
        var bestSquared = CGFloat.greatestFiniteMagnitude
        for index in 1..<run.points.count {
            let start = run.points[index - 1]
            let end = run.points[index]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let span = dx * dx + dy * dy
            var along: CGFloat = 0
            if span > 0 {
                along = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / span, 0), 1)
            }
            let projectedX = start.x + dx * along
            let projectedY = start.y + dy * along
            let squared = (projectedX - point.x) * (projectedX - point.x)
                + (projectedY - point.y) * (projectedY - point.y)
            if squared < bestSquared {
                bestSquared = squared
                bestDistance = run.offsets[index - 1]
                    + along * (run.offsets[index] - run.offsets[index - 1])
            }
        }
        return bestDistance
    }

    /// The nearest point on the whole loop: which run, how far along it, and where that is.
    func nearest(to point: CGPoint) -> (run: Int, distance: CGFloat, point: CGPoint) {
        var best = (run: 0, distance: CGFloat(0), point: runs.first?.points.first ?? .zero)
        var bestSquared = CGFloat.greatestFiniteMagnitude
        for (index, run) in runs.enumerated() where run.points.count > 1 {
            let distance = Self.distance(of: point, in: run)
            let candidate = Self.position(at: distance, in: run)
            let squared = (candidate.x - point.x) * (candidate.x - point.x)
                + (candidate.y - point.y) * (candidate.y - point.y)
            if squared < bestSquared {
                bestSquared = squared
                best = (index, distance, candidate)
            }
        }
        return best
    }

    /// Moves a budget along a run.
    ///
    /// An open run is walked back and forth — the body reaches an end and turns, which is the only
    /// thing it can do at a run that stops short of a forbidden stretch. A closed one is walked round
    /// and round, so the ordinary screen still reads as a body circling it rather than pacing an edge.
    static func travel(_ budget: CGFloat, from start: CGFloat, in run: Run) -> CGFloat {
        let length = run.length
        guard length > 0 else { return 0 }
        if run.isClosed {
            let wrapped = (start + budget).truncatingRemainder(dividingBy: length)
            return wrapped < 0 ? wrapped + length : wrapped
        }
        let period = 2 * length
        var folded = (start + budget).truncatingRemainder(dividingBy: period)
        if folded < 0 { folded += period }
        return folded > length ? period - folded : folded
    }
}

// MARK: - Building one

extension DeloresCompanionLoop {
    /// The loop for a display.
    ///
    /// - Parameters:
    ///   - frame: the display's whole frame. The loop is inset by `bodyRadius`, so the body itself
    ///     never leaves the screen.
    ///   - obstacle: a rectangle standing on the bottom edge that the body walks *around* — the Dock.
    ///     Ignored when it does not reach the edge or does not overlap it.
    ///   - topRuns: the stretches of the top edge the body is allowed on, in x. Nil allows all of it,
    ///     which is what a body that has not been told otherwise should do. Each gap becomes an end to
    ///     turn back at.
    static func around(
        _ frame: CGRect,
        bodyRadius: CGFloat,
        walkingAround obstacle: CGRect? = nil,
        topRuns: [ClosedRange<CGFloat>]? = nil
    ) -> DeloresCompanionLoop {
        let r = frame.insetBy(dx: bodyRadius, dy: bodyRadius)
        guard r.width > 0, r.height > 0 else { return DeloresCompanionLoop(runs: []) }

        let allowed = (topRuns ?? [r.minX...r.maxX])
            .map { max($0.lowerBound, r.minX)...min($0.upperBound, r.maxX) }
            .filter { $0.upperBound > $0.lowerBound }
            .sorted { $0.lowerBound < $1.lowerBound }

        // The long way round: down the left edge, across the bottom (around whatever stands on it), up
        // the right edge, then back along the top as far as it is allowed to go.
        var main: [CGPoint] = [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY)]
        main.append(contentsOf: bottomRun(r, around: obstacle))
        main.append(CGPoint(x: r.maxX, y: r.maxY))

        let topIsWhole = allowed.count == 1
            && allowed[0].lowerBound <= r.minX && allowed[0].upperBound >= r.maxX
        if topIsWhole {
            // Nothing is forbidden up there, so the loop closes: one run, walked round and round.
            main.append(CGPoint(x: r.minX, y: r.maxY))
            return DeloresCompanionLoop(runs: [Run(points: main, isClosed: true)])
        }

        var runs: [Run] = []
        if let last = allowed.last, last.upperBound < r.maxX {
            main.append(CGPoint(x: last.upperBound, y: r.maxY))
        }
        runs.append(Run(points: main))
        // Each allowed stretch is a run of its own, walked from its right end to its left.
        for band in allowed.reversed() {
            runs.append(
                Run(points: [
                    CGPoint(x: band.upperBound, y: r.maxY),
                    CGPoint(x: band.lowerBound, y: r.maxY),
                ]))
        }
        return DeloresCompanionLoop(runs: runs)
    }

    /// The bottom edge, from the left corner to the right one, folded around anything standing on it.
    private static func bottomRun(_ r: CGRect, around obstacle: CGRect?) -> [CGPoint] {
        let corner = CGPoint(x: r.maxX, y: r.minY)
        guard let obstacle,
            obstacle.minY < r.minY,
            obstacle.maxY > r.minY,
            obstacle.minX < r.maxX,
            obstacle.maxX > r.minX
        else { return [corner] }

        let left = max(obstacle.minX, r.minX)
        let right = min(obstacle.maxX, r.maxX)
        let top = min(obstacle.maxY, r.maxY)
        guard right > left, top > r.minY else { return [corner] }

        return [
            CGPoint(x: left, y: r.minY),
            CGPoint(x: left, y: top),
            CGPoint(x: right, y: top),
            CGPoint(x: right, y: r.minY),
            corner,
        ]
    }
}
