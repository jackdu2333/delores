import CoreGraphics
import Foundation

/// Which edge of its display the Companion rides. Declared beside the wander that walks it, so the
/// rules can be asserted without a window: a corner is two edges at once, and the right one wins.
enum DeloresCompanionEdge: Equatable, Sendable {
    case top, bottom, left, right
}

/// How the Companion decides where to be.
///
/// Randomness is injected rather than drawn, because a wander nobody can replay is a wander nobody
/// can assert. A trip is one speed and one destination; between trips it stands still, and for much
/// longer than it walks. The clock is the caller's — a rest's `until` and the `now` compared
/// against it only have to come from the same one.
///
/// Where it *may* go is not decided here. `DeloresCompanionLoop` says which stretches of the display
/// are walkable and which are not; this only decides how the body moves along them.
enum DeloresCompanionWander {
    enum Phase: Equatable, Sendable {
        case resting(until: TimeInterval)
        case strolling(run: Int, destination: CGFloat, speed: CGFloat)
    }

    /// Where the body is, which run it is on, and what it is doing.
    ///
    /// The run is carried rather than re-derived from the position. Two runs can touch without being
    /// connected — an allowed stretch of menu bar begins exactly where a forbidden one ends — and a
    /// body that picked the wrong one would walk straight into what it is meant to keep off.
    struct State: Equatable, Sendable {
        var center: CGPoint
        var run: Int
        var phase: Phase
    }

    /// Most rests are a pause; the tail is what makes the thing read as occupied rather than
    /// scheduled. An even rhythm is the thing that looks mechanical. Long rests are the lazy
    /// default now — the Companion loiters far more than it walks.
    static let shortRestRange: ClosedRange<TimeInterval> = 4...14
    static let longRestRange: ClosedRange<TimeInterval> = 20...60
    static let longRestChance = 0.4

    /// Past this a motionless Companion reads as a dead one, so no rest is allowed to reach it.
    static let maximumRest: TimeInterval = longRestRange.upperBound

    /// A trip holds one speed from end to end. Held, because a speed that jitters reads as a fault
    /// and a speed that never varies reads as a motor. Slow on purpose: the Companion ambles
    /// along its loop, it does not commute.
    static let speedRange: ClosedRange<CGFloat> = 14...24

    /// How far a trip goes. Most are a few steps and a look around; the tail is the long way, which
    /// is what keeps the walking from reading as a metronome.
    static let shortTripRange: ClosedRange<CGFloat> = 90...240
    static let longTripChance = 0.15

    /// A frame that arrives late — a slept machine, a stalled run loop — must not fling the body
    /// across the display.
    static let maximumStep: TimeInterval = 0.25

    /// Every arrival — a start, a drop, a screen change — begins here: still, on the loop.
    static func settled(
        at center: CGPoint, in loop: DeloresCompanionLoop, at now: TimeInterval,
        using rng: inout some RandomNumberGenerator
    ) -> State {
        let nearest = loop.nearest(to: center)
        return State(
            center: nearest.point,
            run: nearest.run,
            phase: .resting(until: now + restDuration(using: &rng)))
    }

    /// One frame. A rest that is not yet due returns the state untouched, which is what lets the
    /// caller run no timer at all in between.
    static func advance(
        _ state: State, elapsed: TimeInterval, now: TimeInterval, in loop: DeloresCompanionLoop,
        stepFrame: Int = 0,
        using rng: inout some RandomNumberGenerator
    ) -> State {
        switch state.phase {
        case .resting(let until):
            guard now >= until else { return state }
            let run = loop.run(at: state.run)
            return State(
                center: state.center,
                run: state.run,
                phase: .strolling(
                    run: state.run,
                    destination: destination(from: state.center, in: run, using: &rng),
                    speed: CGFloat.random(in: speedRange, using: &rng)))
        case .strolling(let index, let destination, let speed):
            let run = loop.run(at: index)
            let baseBudget = speed * CGFloat(min(max(elapsed, 0), maximumStep))
            let budget = baseBudget * stepWeight(for: stepFrame)
            return travel(
                state, run: index, to: destination, budget: budget, in: run, at: now, using: &rng)
        }
    }

    /// Odd frames are the passing / push-off poses; even frames plant. The index is the drawn frame.
    static func stepWeight(for frame: Int) -> CGFloat {
        let cycle = frame % 4
        return (cycle == 1 || cycle == 3) ? 1.5 : 0.5
    }

    /// When the caller has to think about the Companion again: the end of a rest, or nothing at all
    /// while it is walking.
    static func nextWake(after state: State) -> TimeInterval? {
        guard case .resting(let until) = state.phase else { return nil }
        return until
    }

    /// The point on the loop nearest `point`. Every write to the body goes through here, so it can
    /// never be left somewhere the wander has no way back from.
    static func project(_ point: CGPoint, into loop: DeloresCompanionLoop) -> CGPoint {
        loop.nearest(to: point).point
    }

    /// A corner is equally near two edges, and the right one wins — the edge it spawns on.
    static func edge(for point: CGPoint, in bounds: CGRect) -> DeloresCompanionEdge {
        let distances: [(DeloresCompanionEdge, CGFloat)] = [
            (.right, abs(bounds.maxX - point.x)),
            (.left, abs(point.x - bounds.minX)),
            (.top, abs(bounds.maxY - point.y)),
            (.bottom, abs(point.y - bounds.minY)),
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .right
    }

    static func restDuration(using rng: inout some RandomNumberGenerator) -> TimeInterval {
        let range = Double.random(in: 0...1, using: &rng) < longRestChance ? longRestRange : shortRestRange
        return min(Double.random(in: range, using: &rng), maximumRest)
    }

    /// How far a trip is allowed to go.
    ///
    /// The floor is the shortest trip, so a long run still gets steps that read as steps. A run
    /// *shorter* than that — a stretch of menu bar beside the notch — can only be walked end to end,
    /// which is what the body does there.
    static func tripDistance(in length: CGFloat, using rng: inout some RandomNumberGenerator) -> CGFloat {
        let longest = max(shortTripRange.upperBound, length)
        let range = Double.random(in: 0...1, using: &rng) < longTripChance
            ? shortTripRange.upperBound...longest
            : shortTripRange
        return CGFloat.random(in: range, using: &rng)
    }

    /// A destination on the same run, drawn as a signed offset from where the body stands, so the
    /// draw itself can never land on the spot it is leaving.
    private static func destination(
        from center: CGPoint, in run: DeloresCompanionLoop.Run,
        using rng: inout some RandomNumberGenerator
    ) -> CGFloat {
        let here = DeloresCompanionLoop.distance(of: center, in: run)
        let reach = tripDistance(in: run.length, using: &rng)
        let sign: CGFloat = Bool.random(using: &rng) ? 1 : -1
        let target = here + sign * reach
        // A closed run is walked round, so its destination wraps. An open one stops at its ends: the
        // body turns when it gets there rather than continuing into what it may not walk.
        guard run.isClosed, run.length > 0 else { return min(max(target, 0), run.length) }
        let wrapped = target.truncatingRemainder(dividingBy: run.length)
        return wrapped < 0 ? wrapped + run.length : wrapped
    }

    private static func travel(
        _ state: State, run index: Int, to destination: CGFloat, budget: CGFloat,
        in run: DeloresCompanionLoop.Run, at now: TimeInterval,
        using rng: inout some RandomNumberGenerator
    ) -> State {
        let here = DeloresCompanionLoop.distance(of: state.center, in: run)
        let delta = shortestDelta(from: here, to: destination, in: run)
        guard abs(delta) > budget else {
            return State(
                center: DeloresCompanionLoop.position(at: destination, in: run),
                run: index,
                phase: .resting(until: now + restDuration(using: &rng)))
        }
        let moved = DeloresCompanionLoop.travel(delta > 0 ? budget : -budget, from: here, in: run)
        return State(
            center: DeloresCompanionLoop.position(at: moved, in: run),
            run: index,
            phase: state.phase)
    }

    /// How far it is from here to there *the way the body will walk it*: the short way round a closed
    /// run, and the direct way along an open one, whose ends it cannot cross.
    private static func shortestDelta(
        from here: CGFloat, to there: CGFloat, in run: DeloresCompanionLoop.Run
    ) -> CGFloat {
        let total = run.length
        guard run.isClosed, total > 0 else { return there - here }
        var delta = (there - here).truncatingRemainder(dividingBy: total)
        if delta > total / 2 { delta -= total }
        if delta < -total / 2 { delta += total }
        return delta
    }
}
